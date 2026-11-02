# LoadingBlockModifiers no motor Lua

Referência: Luanti 5.18, `doc/lua_api.md`, seção **LBM (LoadingBlockModifier) definition**, e `src/serverenvironment.cpp` (`ServerEnvironment::activateBlock`).

O `core.register_lbm` agora aceita `action(pos, node, dtime_s)` ou `bulk_action(pos_list, dtime_s)`, com nomes persistentes, `nodenames` e grupos. A ordem de registro é mantida; o motor captura posições antes dos callbacks e revalida cada nó após alterações de outros LBMs.

O host chama `runtime:activateMapBlock(node_pos, dtime_s)` **na ativação** de um mapblock residente. `node_pos` é uma coordenada de nó dentro do mapblock, não o índice do bloco. **Não** chamar a cada frame, ao consultar nós ou simplesmente ao decodificar o mapa. O tempo transcorrido `dtime_s` precisa ser calculado pelo host; na ausência desse relógio, o padrão é zero.

LBMs com `run_at_every_load=true` rodam a cada ativação. Para LBMs de execução única, o motor salva um registro `A bx by bz nome` por mapblock e por nome no formato compatível `LUAENGINE 1`. Nomes de LBMs introduzidos depois ainda executam em blocos antigos. `markGeneratedMapBlocks(minp,maxp)` registra os LBMs já conhecidos em blocos recém-gerados, impedindo migrações antigas sobre terreno novo; o gerador Lua existente já faz essa chamada.

**Limitações conhecidas:** Luanti original decide se um LBM é executado comparando o timestamp de introdução do LBM ao último timestamp ativo do mapblock, armazenando a introdução em `env_meta.txt`. Este porte usa marcadores persistentes por nome e bloco em vez desses timestamps; a equivalência ainda não é total. O runtime não faz streaming automático de mapblocks nem sabe calcular sozinho `dtime_s` a partir de um relógio mundial persistente. Um host que ainda não comunica ativações reais não executa os LBMs automaticamente. `register_on_generated` continua sendo o mecanismo correto para alterar a saída do mapgen.

Teste de regressão: `lua5.4 tests/lua_engine_lbm_activation.lua` e `luajit tests/lua_engine_lbm_activation.lua`. Ambos usam exclusivamente o motor Lua e verificam fronteiras negativas, snapshot, bulk, reaplicação, introdução tardia, geração e persistência.
