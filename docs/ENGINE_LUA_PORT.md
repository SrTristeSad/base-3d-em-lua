# Engenharia reversa funcional: motor Luanti -> Lua

## Objetivo

Reconstruir **o comportamento observável da API e do motor Luanti**
em Lua, usando o jogo VoxeLibre como referência de compatibilidade.
A meta de longo prazo é reduzir as diferenças funcionais para zero.

A reimplementação é independente: usar interfaces documentadas,
testes próprios e fontes GPL para referência, respeitando as
licenças de ambas as bases. O projeto não constitui um motor completo
apenas por existir uma API com os mesmos nomes.

## Estado: fase inicial do motor em Lua

| Subsistema | Estado |
| --- | --- |
| Registros de nós, ferramentas, itens, entidades e crafts | Parcial, funcional |
| Mapa esparso, blocos 16³, coordenadas negativas | Funcional para nós editados |
| Ler/editar nós, metadados, timers | Parcial, com testes |
| Eventos, after(), globalstep, ABM, callbacks | Parcial, com testes |
| Serialização segura, determinística, sem execução de código | Implementada (formato próprio) |
| Câmera livre, renderização voxel básica, mineração/colocação | Demo LÖVR independente |
| Loader `mod.conf`, dependências obrigatórias e opcionais | **Parcial, testado; não inicia VoxeLibre** |
| Seis módulos Lua originais reais de VoxeLibre | **Carregamento inicial em Lua, sem gameplay** |
| Jogo VoxeLibre completo no motor Lua | **Não funcional ainda** |
| VoxelManip, Mapgen, biomas, caves e iluminação Luanti | Ausentes |
| ItemStack, InvRef, listas em nós, detached, metadados e save | **Parcial, testado** |
| Receitas shaped/shapeless, grupos, forno/combustível, devoluções | **Parcial, testado** |
| Craft completo, toolrepair, callbacks e transações player | Pendentes |
| Entidades em mundo, mobs e física completa | Ausentes |
| Formspec, HUD, chat, multimídia, áudio | Ausentes |
| Rede, persistência SQLite/LevelDB, servidor multiplayer | Ausentes |
| Compatibilidade real de versão LuaJIT/Lua 5.1 | Pendente |
| Testes de equivalência com Luanti original | Pendente |

## Como é organizado

- `lua-engine/core/map.lua`: armazenamento esparso, metadados e timers.
- `lua-engine/core/runtime.lua`: registro e despachos da API minetest/core.
- `lua-engine/core/vector.lua`: vetores e operações aritméticas.
- `lua-engine/core/storage.lua`: save seguro e determinístico, incluindo inventários de nós.
- `lua-engine/core/itemstack.lua`: valores `ItemStack` copiáveis e metadados.
- `lua-engine/core/inventory.lua`: listas `InvRef` e inserção com sobras.
- `lua-engine/core/modloader.lua`: leitura de `mod.conf`, ordenação por dependências e falha explícita.
- `lua-engine/core/modenvironment.lua`: ambiente de globais separado que executa arquivos Lua reais dos mods de referência, com acesso ao sistema de arquivos limitado aos diretórios de mods declarados. **Não é sandbox de segurança contra código não confiável.**
- `lua-engine/core/modstorage.lua`: armazenamento de mod por runtime, ainda sem persistência em disco.
- `tests/lua_engine_real_voxelibre.lua`: executa 6 mods upstream e reporta primeiro bloqueio de `mcl_init`.
- `lua-engine/core/crafting.lua`: registro, consulta, escolha prioritária e execução atômica de receitas.
- `scripts/audit_voxelibre_api.py`: inspeção estática das chamadas `core.*`/`minetest.*` no VoxeLibre; não mede paridade funcional.
- `lua-engine/main.lua`: demo independente LÖVR para testarmos o motor.
- `tests/lua_engine_core.lua`: regressões da API inicial.
- `scripts/package_lua_engine.py`: gera `.lovr` autônomo.

O arquivo `lua-engine/main.lua` não é o antigo `main.lua`:
são executáveis separados, não duas implementações conflitantes.

## Constrangimento técnico

Um motor de vídeo totalmente em Lua puro, sem bibliotecas nativas,
não pode fazer sozinho a interface gráfica Vulkan/Direct3D, a janela
e a entrada do sistema operacional. **A lógica será em Lua**,
mas o LÖVR usa código nativo para GPU/áudio/janela.

O backend LÖVR é uma escolha inicial, não uma implementação 1:1
das estruturas internas do Luanti, que usa C++ para mundo, render,
inventários, rede e serialização. A compatibilidade completa
terá de ser comprovada, e não pressuposta.

## Próximos marcos objetivos

1. Completar os callbacks de craft/inventário e toolrepair; conectar
   o resultado da receita ao inventário do jogador e à interface.
2. Expandir os testes de execução da árvore de módulos além dos
   seis módulos já testados, corrigindo APIs ausentes e dependências.
3. Lua VoxelManip + geração/iluminação e mundos persistentes;
   streaming e greedy meshing em renderização otimizada.
4. HUD/formspec, entidades físicas, players, multijogador.
5. Rodar VoxeLibre sem Luanti, e executar testes de equivalência
   de blocos, seeds, mundo, jogabilidade e mods.

**Não iniciar mudanças de gameplay proprietárias antes que a
base de compatibilidade esteja verificável.**

## Segurança e licença

O VoxeLibre original continua intacto em `games/voxelibre`,
sob GPLv3+, com créditos e licenças de media. Luanti é LGPLv2.1+.
O protótipo Lua ainda não é uma tradução linha-por-linha do
código C++; é uma reimplementação incremental de interfaces e
comportamentos a partir de uma arquitetura nova.

### Fase 4 — verificação real

Na execução Linux de GitHub Actions, seis módulos originais foram
carregados com sucesso usando Lua 5.4 e LuaJIT, totalizando 12 arquivos
Lua: mcl_init, mcl_colors, mcl_sounds, mcl_autogroup,
tga_encoder e vl_tuning.

O módulo seguinte mcl_util continua bloqueado em fase de inicialização:
ao menos os recursos bit (Lua 5.4) e PcgRandom (LuaJIT) precisam ser
portados. Os relatórios de cada execução documentam o erro observável.
A auditoria estática registra 66 dos 240 nomes de API usados nos mods
presentes na tabela do motor, com 174 nomes ainda não exportados.
**Quantidade de nomes de funções NÃO equivale a compatibilidade funcional.**

A implementação de Settings lê game.conf para fins de inicialização,
e get_version identifica este porte como 0.1.0-lua-port, e NÃO como
o binário Luanti original. Os arquivos do VoxeLibre não são alterados.
