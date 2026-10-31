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
| Compatibilidade com mods do VoxeLibre | **Não funcional ainda** |
| VoxelManip, Mapgen, biomas, caves e iluminação Luanti | Ausentes |
| ItemStack, invref, craft real, ferramentas | Ausentes |
| Entidades em mundo, mobs e física completa | Ausentes |
| Formspec, HUD, chat, multimídia, áudio | Ausentes |
| Rede, persistência SQLite/LevelDB, servidor multiplayer | Ausentes |
| Compatibilidade real de versão LuaJIT/Lua 5.1 | Pendente |
| Testes de equivalência com Luanti original | Pendente |

## Como é organizado

- `lua-engine/core/map.lua`: armazenamento esparso, metadados e timers.
- `lua-engine/core/runtime.lua`: registro e despachos da API minetest/core.
- `lua-engine/core/vector.lua`: vetores e operações aritméticas.
- `lua-engine/core/storage.lua`: save seguro e determinístico.
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

1. `ItemStack`, inventário/metadata com inventários,
   callbacks de interação e crafting equivalente ao Luanti.
2. Loader real da árvore de 221 módulos do VoxeLibre, dependências
   e log de chamadas de API ainda não implementadas.
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
