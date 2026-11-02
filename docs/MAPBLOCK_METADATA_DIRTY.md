# Fase 105 — Alterações de metadados, inventários e timers de MapBlock

## Problema corrigido

Até a Fase 104, `Map:set_node`, `is_underground` e alguns outros caminhos registravam o MapBlock como modificado, mas as operações feitas por `NodeMetaRef`, inventários de nós e `NodeTimerRef` não necessariamente o faziam. O `MapBlockStore:flush` enumerava metadados e timers **presentes**, mas, quando o último campo ou timer era removido, podia faltar uma entrada para sobrescrever o arquivo `.map.partial` e o dado removido podia reaparecer após reiniciar.

## Implementação

- `Map:report_node_metadata_change(pos)` usa `MOD_STATE_WRITE_NEEDED` com `MOD_REASON_REPORT_META_CHANGE` (bit 6, valor 64). `get_meta` e leituras de inventário não sinalizam modificação.
- Escritas em `set_string`, `set_int`, `set_float` e `from_table` avisam o MapBlock. As alterações efetivas de inventários retornados por `get_meta(...):get_inventory()` também avisam: `set_size`, `set_width`, `set_stack`, `set_list`, `set_lists`, `from_table`, `add_item` e `remove_item`.
- `Inventory` recebe opcionalmente a função interna `_on_change`; inventários independentes, como os detached, continuam sem notificação de bloco. `get_stack` e `get_list` seguem retornando cópias isoladas.
- `Map:report_node_timer_change(pos)` sinaliza `WRITE_AT_UNLOAD` e `MOD_REASON_UNKNOWN`. **O Luanti 5.18 não define um motivo exclusivo para timers** e seus métodos `Map::setNodeTimer`/`removeNodeTimer` não chamam diretamente `raiseModified`. Portanto este uso de `UNKNOWN` é uma **garantia de durabilidade do adaptador Lua**, não uma alegação de equivalência exata com o C++.
- `NodeTimerRef:start`, `set`, `stop` de um timer existente, o vencimento no scheduler e a remoção de metadata/timer pelos métodos `api.set_node`/`api.remove_node` registram a mudança. Consultas e `stop` de timer inexistente permanecem operações sem alteração.
- `Storage.decode` limpa `modified`, `modified_states` e `modified_reasons` ao terminar a importação. Imagens importadas não aparecem falsamente como modificadas.
- O formato `LUAENGINE 1` e os registros de persistência permanecem **inalterados**. Após escrita atômica bem-sucedida, `MapBlockStore` limpa os estados como na Fase 103; falhas mantêm a alteração pendente.

## Exemplo

```lua
local pos={x=-16,y=0,z=0}
local m=runtime.api.get_meta(pos)
m:set_string('owner','builder')
local inv=m:get_inventory()
inv:set_size('main',1)
inv:set_stack('main',1,'test:stone 3')
runtime.api.get_node_timer(pos):start(5)
-- A exclusão de todo o metadata ou timer também marca o bloco.
```

Com apenas timers, o estado pode ser `WRITE_AT_UNLOAD`. Com metadata/inventário, o estado é `WRITE_NEEDED`, e o motivo mais grave substitui o de timer, conforme `raiseModified`.

## Testes

```sh
lua5.4 tests/lua_engine_mapblock_metadata_dirty.lua
luajit tests/lua_engine_mapblock_metadata_dirty.lua
```

A regressão cobre leituras sem modificação, alterações de campos e inventários, inventários detached, `NodeTimerRef`, ordem dos motivos, falha de escrita atômica, exclusão do último dado em sidecar parcial, reinício limpo, substituição de nó de conteúdo idêntico, descarregamento de bloco completo e vencimento de timers.

## Limites

O registro de mudança de metadata reflete a semântica observável do `NodeMetaRef::reportMetadataChange`, mas não implementa ainda todos os eventos do barramento nativo `MapEditEvent`, callbacks de inventários do motor original, privacidade de campos, rollback e todas as ramificações de `MOD_REASON_REPORT_META_CHANGE`. A progressão contínua de `timer.elapsed` não marca cada frame como uma gravação pendente: os snapshots existentes capturam o valor no momento de `flush()`; transições explícitas e vencimentos são rastreados. Não significa compatibilidade completa do VoxeLibre.

Referências upstream: [`src/mapblock.h`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.h), [`src/script/lua_api/l_nodemeta.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/script/lua_api/l_nodemeta.cpp), [`src/map.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/map.cpp).
