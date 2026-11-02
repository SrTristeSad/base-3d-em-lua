# Fase 98 — MMVManip::blitBackAll explícito (overwrite_generated)

## Referências Luanti 5.18.0

- [src/map.cpp, linhas 894–935](https://github.com/luanti-org/luanti/blob/5.18.0/src/map.cpp#L894-L935): `MMVManip::blitBackAll(modified_blocks, overwrite_generated)` seleciona mapblocks com dados, carrega/cria blocos ausentes, omite mapblocks gerados por padrão e permite escrevê-los quando `overwrite_generated=true`.
- [src/mapblock.cpp, linhas 224–234](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.cpp#L224-L234): `MapBlock::copyFrom` copia a representação de nós.
- [src/voxel.cpp, linhas 231–246](https://github.com/luanti-org/luanti/blob/5.18.0/src/voxel.cpp#L231-L246): `VoxelManipulator::copyTo` transfere todo MapNode diferente de `CONTENT_IGNORE`, incluindo ar e seus parâmetros. Os flags `NO_DATA` não são inspecionados nesse laço.
- A referência original tem licença LGPL-2.1-or-later.

## API implementada

```lua
local Buffer=require('core.mapgen_voxelbuffer')
local vm=Buffer.new(runtime.map,geometry)
vm:initialEmerge(false)
vm:stage_vmanip_node(position,{name='air',param1=12,param2=3})
local modified_blocks,changed_nodes,created_blocks=
 vm:blitBackAll(true)  -- opção deliberada; padrão é false
```

O novo `stage_vmanip_node` é uma entrada explícita para manipular os nós do workspace mesmo quando foram importados de mapblocks já gerados. A escrita não afeta o mapa até o `blitBackAll`. Este comportamento fica **separado** do `set_node` usado na geração de terreno V7, que continua protegendo construções existentes.

A transferência copia os nós conhecidos (incluindo AIR implícito em blocos gerados, AIR explícito com parâmetros e nós carregados) de todos os mapblocks cobertos, preserva os nós desconhecidos `CONTENT_IGNORE`, mantém o estado gerado/ungenerated de cada bloco e não apaga metadados ou timers: `MapBlock::copyFrom` transfere apenas os MapNodes.

`overwrite_generated=false` omite mapblocks que já estavam gerados no snapshot. `overwrite_generated=true` permite sobrescrever somente MapNodes dos blocos gerados que tenham sido importados por `initialEmerge`. Todo bloco-alvo é validado por revisão e estado antes de qualquer mudança: conflito provoca erro e aborta a operação. Blocos ausentes são criados como parciais `CONTENT_IGNORE` sem adquiriem estado de geração completa, e o armazenador da Fase 97 consegue persistir os dados parciais. A operação é intencionalmente **one-shot**; um novo blit requer novo workspace. O resultado inclui a tabela de mapblocks marcados modificados, além da contagem de nós alterados e blocos criados.

## Teste

```sh
lua5.4 tests/lua_engine_mmvm_blitbackall.lua
luajit tests/lua_engine_mmvm_blitbackall.lua
```

Cobre default sem overwrite, modificação deliberada em mapa gerado, `param1`/`param2`, ar conhecido e ignorado, metadata/timers preservados, block modificado mesmo sem mudança nodal, novos `blank_blocks`, persistência após reinício e preflight de conflitos concorrentes.

## Limitações

Este método ainda é um **adaptador seguro do blit**, não um porte integral da classe C++: exige `initialEmerge` previamente, e não realiza por conta própria a procura arbitrária/carregamento dos mapblocks de destino a partir do disco. Para mapas em streaming, o caminho `initialEmerge(true)` ou `MapBlockStore:load_or_create_blank` pode carregar/criar os destinatários antes do blit. O valor de retorno no C++ é `void` com parâmetro de saída `modified_blocks`; a adaptação Lua retorna essa tabela. A validação de revisões intencionalmente rejeita alterações concorrentes que o C++ deixaria ocorrer. Como o motor não representa integralmente estado de iluminação/cache e callbacks nativos do MapBlock, essas partes permanecem fora de escopo; o CI não comprova execução integral do VoxeLibre original.
