# Fase 107 — MapEditEvent agrupado para MMVManip (Luanti 5.18.0)

## Semântica nativa verificada

No Luanti 5.18.0, [`src/map.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/map.cpp#L894) implementa `MMVManip::blitBackAll` e, opcionalmente, preenche um `std::map<v3s16, MapBlock*>` de blocos modificados. **O método não despacha `MapEditEvent` diretamente.**

Em [`src/script/lua_api/l_vmanip.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/script/lua_api/l_vmanip.cpp), a rotina de alto nível `LuaVoxelManip::write_to_map` chama o blit (ou a rotina de iluminação) e, em seguida, entrega **um único** `MEET_OTHER` com as posições dos blocos alterados. Esse evento é emitido inclusive quando o conjunto está vazio. A geração assíncrona de mapa agrega alterações por ciclo antes de despachar os eventos em [`src/emerge.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/emerge.cpp).

## Novas APIs internas do adaptador Lua

```lua
local Buffer = require('core.mapgen_voxelbuffer')
local vm = Buffer.new(map, geometry)
vm:initialEmerge(false)
vm:stage_vmanip_node({x=-16,y=0,z=0}, {name='test:stone'})

-- Alto nível: grava e notifica os observadores UMA vez
local modified_blocks, changed_nodes, created_blocks = vm:write_to_map(true)

-- Ou, para quem já tem um conjunto de blocos alterados:
map:dispatch_modified_blocks_event({
 ['-1,0,0']=true, ['0,0,1']=true
}, false)
```

O método `Buffer:write_to_map(overwrite_generated)` mantém os mesmos resultados e regras de preflight de `Buffer:blitBackAll` (inclusive a restrição de buffer consumido uma única vez), acrescentando a entrega de um único `MEET_OTHER` após concluir a gravação. `blitBackAll` permanece silencioso, preservando o comportamento dos caminhos internos de geração. O argumento `overwrite_generated` mantém o significado já definido no adaptador, sem introduzir a opção nativa `update_light`, que ainda não foi portado integralmente.

`Map:dispatch_modified_blocks_event(modified_blocks,low_priority,include_empty)` recebe um conjunto cujas chaves são **coordenadas canônicas de MapBlock** e cujos valores são `true`. Rejeita entradas não canônicas, fora dos limites e com valores inválidos **antes de enviar o primeiro evento**; converte para `{x,y,z}` e ordena numericamente por X/Y/Z para resultados reprodutíveis em Lua 5.4 e LuaJIT. Retorna a quantidade de observadores notificados.

`low_priority` é opcional e usa `false` por padrão. `include_empty` também é opcional e usa `false`; quando `true`, despacha um `MEET_OTHER` com lista vazia, reproduzindo a decisão explícita de `LuaVoxelManip::write_to_map`. `Buffer:write_to_map` sempre utiliza `include_empty=true`.

## Eventos emitidos e preservação do estado

- O payload é `{type=Map.MEET_OTHER,p=nil,n={name='air',param1=0,param2=0},modified_blocks={{x=...,y=...,z=...},...},is_private_change=false,low_priority=false}`. Seu conteúdo é copiado por receptor, conforme a Fase 106.
- Um bloco copiado sem qualquer diferença nos valores dos nós **ainda é marcado** e incluído no evento, conforme o comportamento de `MMVManip::blitBackAll`.
- Blocos gerados que não são sobrescritos, áreas sem dados conhecidos e alvos pulados não entram no conjunto. No entanto, `write_to_map` entrega seu evento mesmo se o conjunto final ficar vazio.
- Nenhum evento é emitido durante `initialEmerge`, `stage_vmanip_node`, `blitBackAll` diretamente nem na importação do armazenamento segmentado.
- Se o preflight falhar por conflito de revisão, alvo indisponível ou arquivo de disco não importado, **não há escrita nem notificação**.
- Se um observador falhar depois do blit, o erro é propagado, mas os dados já gravados no mapa **não são revertidos**. O buffer continua consumido e não pode efetuar uma segunda escrita.
- Essa notificação não altera as regras de dirty tracking, motivos `MOD_REASON_VMANIP`, estados de geração, nem o formato de persistência `LUAENGINE 1`.

## Testes

```sh
lua5.4 tests/lua_engine_mmvm_map_edit_other.lua
luajit tests/lua_engine_mmvm_map_edit_other.lua
```

A regressão verifica ordenação com coordenadas negativas e multidígitos, rejeição de conjuntos inválidos antes de notificar, múltiplos blocos em um único evento, blocos parciais de disco, cópias idênticas, filtros de `overwrite_generated`, evento vazio, separação entre blit interno e escrita de alto nível, preflight transacional e falhas de observadores.

## Limitações

Este avanço não implementa transmissão dos eventos a clientes, a API Lua completa `VoxelManip` do Luanti, nem despacho automático agregado de todos os caminhos de emergência de `EmergeManager`. A agregação para `write_to_map` é fiel ao comportamento de notificação da API Lua de alto nível, enquanto os caminhos internos do motor permanecem sem notificações extras. Também não implementa `voxalgo::blit_back_with_light` (`update_light` do upstream), pois isso exige trabalho independente de iluminação.
