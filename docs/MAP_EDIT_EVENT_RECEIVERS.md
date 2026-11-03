# Fase 106 — Eventos de edição de mapa (Luanti 5.18.0)

## Referência upstream

O [`src/map.h`](https://github.com/luanti-org/luanti/blob/5.18.0/src/map.h) define `MapEditEvent`, `MapEventReceiver` e `Map::addEventReceiver` / `removeEventReceiver` / `dispatchEvent`. O [`src/map.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/map.cpp) emite eventos nas rotinas de edição **de alto nível** (`addNodeWithEvent`, `removeNodeWithEvent`), em vez de disparar eventos indistintamente a cada gravação de MapNode. O [`NodeMetaRef::reportMetadataChange`](https://github.com/luanti-org/luanti/blob/5.18.0/src/script/lua_api/l_nodemeta.cpp) envia `MEET_BLOCK_NODE_METADATA_CHANGED`.

Este avanço implementa um **barramento interno** observável pelos componentes do host. Ele **não cria** uma nova API Lua oficial do Luanti voltada aos mods nem implementa transporte de eventos pela rede.

## API

```lua
local map=runtime.map
local receiver={}
function receiver:onMapEditEvent(event)
 print(event.type,event.p and event.p.x)
end

map:add_event_receiver(receiver)
-- ou map:add_event_receiver(function(event) ... end)
map:remove_event_receiver(receiver)
```

`add_event_receiver` aceita função ou objeto com método `onMapEditEvent`; devolve `true` na primeira inscrição e `false` em inscrições duplicadas. `remove_event_receiver` devolve `true` apenas quando o receptor estava registrado. O dispatcher valida o evento antes da entrega, impede aliasing dos vetores de um receptor para outro e suporta remover receptores ou adicionar novos durante uma notificação. A ordem da entrega é a ordem de inscrição, uma escolha determinística do adaptador Lua.

Os valores de `event.type` seguem a ordem do enum do Luanti:

| Constante `Map.MEET_*` | Valor | Evento |
|---|---:|---|
| `ADDNODE` | 0 | Adição/substituição de nó via `api.set_node` ou `api.add_node` |
| `REMOVENODE` | 1 | Remoção via `api.remove_node` |
| `SWAPNODE` | 2 | Troca via `api.swap_node` |
| `BLOCK_NODE_METADATA_CHANGED` | 3 | Campos/inventários de metadata alterados |
| `OTHER` | 4 | Evento interno enviado explicitamente por `map:dispatch_event` |

Cada evento expõe `type`, `p`, `n`, `modified_blocks`, `is_private_change` e `low_priority`. As posições e os MapBlocks são vetores `{x,y,z}`, como no C++; `modified_blocks` usa **coordenadas de MapBlock**, não de nó. Para posições negativas, utiliza a divisão com arredondamento para baixo. Os campos booleanos começam em `false`. `MEET_OTHER` admite lista de blocos múltiplos e posição omitida.

`Map:emit_node_edit_event(type,pos,node)` e `Map:dispatch_event(event)` são rotinas do adaptador; `Map:report_node_metadata_change(pos,private)` continua marcando o MapBlock como modificado e agora também envia um evento de metadata, quando houver receptor. A implementação ainda não tem representação de campos privados por `NodeMetaRef`: alterações normais informam `is_private_change=false`, mas o helper manual aceita `true` para compatibilidade de payload.

## Comportamentos preservados

- `Map:set_node` e `Map:remove_node` são **métodos de mapa de baixo nível**, usados também por geração, blit, carga de disco e outras rotinas. Não emitem `MapEditEvent`; seu observador de geometria e invalidadores de colisão continuam funcionando.
- `api.set_node`, `api.swap_node` e `api.remove_node` continuam a executar os callbacks e regras de metadata/timers previamente implementadas. A notificação de nó é enviada após a operação de alto nível, sem um segundo evento redundante de metadata quando a remoção é implícita ao substituir o nó.
- `NodeMetaRef:set_string/set_int/set_float` e operações de inventário notificam `MEET_BLOCK_NODE_METADATA_CHANGED`. `NodeMetaRef:from_table` emite **um único evento** para a substituição completa, evitando um evento por slot restaurado internamente.
- `get_meta`, getters de inventário e `get_node_timer` não emitem eventos. `NodeTimerRef` não possui `MEET_*` próprio no Luanti 5.18.0; seu rastreamento de durabilidade da Fase 105 permanece inalterado.
- `MapBlockStore:emerge` e `load_partial` utilizam setters silenciosos durante a importação, inclusive para timers e inventários. Blocos recuperados **não** geram eventos falsos.
- Uma inscrição pertence à instância do `Map`; depois de `Runtime:replaceMap`, receptores do mapa antigo não são transferidos implicitamente para outro objeto. O host pode se inscrever no novo mapa.
- Se uma função receptora lançar erro, a chamada propagará o erro ao host, **sem desfazer** uma edição já aplicada. A aplicação deve tratar falhas de observadores quando for apropriado.

## Regressão

```sh
lua5.4 tests/lua_engine_map_edit_events.lua
luajit tests/lua_engine_map_edit_events.lua
```

A regressão inclui valores do enum, snapshots isolados, blocos negativos, mutação e remoção de receptores durante dispatch, reentrância, validação de eventos, callbacks de criação, semântica da troca/remoção de nós, metadados e inventários, timers silenciosos e persistência parcial/completa.

## Limitações deliberadas

O Luanti distribui esses eventos também para sistemas de cliente e sincronização pela rede. A Fase 106 **não implementa** esse pipeline, não substitui `MapEditEvent::getArea()` integralmente nem força eventos `MEET_OTHER` automáticos para todo o trabalho de `MMVManip` ou geração: fazer isso sem mapear o ciclo nativo poderia criar notificações erradas e prejudicar o desempenho. Também não altera os timestamps, formatos `LUAENGINE 1`, arquivos de mundo ou a fidelidade visual de VoxeLibre.
