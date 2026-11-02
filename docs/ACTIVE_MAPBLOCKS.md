# Mapblocks ativos — etapa de compatibilidade Luanti 5.18

**Referência upstream:** `src/serverenvironment.cpp`, `ActiveBlockList::update`, `ServerEnvironment::step` e `ServerEnvironment::activateBlock` (Luanti 5.18.0).

O runtime Lua agora identifica blocos residentes próximos a **jogadores conectados que fornecem uma posição real**, por `ObjectRef:get_pos()` ou pelo controlador de física associado. Mantém a união de esferas 3D por jogador com `active_block_range` (padrão 3 mapblocks, limite de implementação 0–8). Mapblocks fora dessa região deixam de ser ativos. Não é criada geometria ou área vazia artificialmente: somente blocos de mapa residentes (nós, metadata, timers ou LBMs) são ativados.

A ativação dispara automaticamente os LBMs do `register_lbm`, uma única vez por transição inativo→ativo, com `dtime_s` calculado a partir da última ativação. LBMs com `run_at_every_load=true` são executados novamente ao reentrar na região. Callbacks de timers em blocos inativos são pausados; ao reativar, recebem o tempo acumulado desde a última atividade (uma chamada, não repetição artificial de todo tick perdido). ABMs só atuam sobre blocos ativos em sessões com posições disponíveis.

O relógio do runtime e os timestamps de última atividade são gravados como registros opcionais `C <segundos>` e `B <bx> <by> <bz> <segundos>` no formato `LUAENGINE 1`. Saves antigos sem eles continuam válidos. `Runtime:replaceMap` restaura o tempo salvo e limpa a relação de blocos ativos anteriores. Blocos recém-gerados já recebem timestamp do tempo do mundo.

**Limites:** isso não é streaming de mapblocks nem ciclo de vida 1:1. Não há carregamento assíncrono de áreas ausentes, descarga física para disco, forceload ou faixa extra de visão de entidades. O runtime Lua mantém um mapa esparso residente em memória e ainda não dispõe da infraestrutura servidor/rede original. O tempo de introdução dos LBMs antigos continua apoiado nos marcadores implementados na etapa anterior, e não no histórico completo `env_meta.txt` do Luanti. Sem uma posição real, o runtime preserva o comportamento antigo dos testes headless; em modo `auto_activate_blocks=false`, a ativação automática é desabilitada.

## Testes

```sh
lua5.4 tests/lua_engine_active_mapblocks.lua
luajit tests/lua_engine_active_mapblocks.lua
```

A regressão cobre movimento entre mapblocks, fronteiras de 16 nós, união de dois jogadores, pausa e catch-up de timers, ABMs, repetição de LBMs, mundo salvo e mapas antigos.
