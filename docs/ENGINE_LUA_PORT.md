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
| Onze módulos Lua originais do VoxeLibre | **Inicialização testada em Lua 5.4/LuaJIT, sem gameplay** |
| Jogo VoxeLibre completo no motor Lua | **Não funcional ainda** |
| VoxelArea, VoxelManip e IDs de conteúdo | **Parcial: buffers, mapblocks, param2 e escrita testados** |
| Registro de biomas, minérios e decorações | **Definições armazenadas; sem geração real** |
| Geração procedural **própria**, semente e persistência de chunks | **Implementada como experimento Lua; NÃO é mapgen Luanti** |
| Mapgen do Luanti, iluminação e simulação de líquidos | **Ausentes** |
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
- `lua-engine/core/voxel.lua`: VoxelArea, IDs de conteúdo e VoxelManip experimental com regiões alinhadas a mapblocks.
- `lua-engine/core/worldgen.lua`: mapa original por semente, chunks 16×16 e construção via VoxelManip.
- `scripts/mcl_core_dependencies.py`: gera árvore real de dependências obrigatórias de mcl_core a partir do mod.conf upstream.
- `lua-engine/core/runtime.lua`: registro e despachos da API minetest/core.
- `lua-engine/core/vector.lua`: vetores e operações aritméticas.
- `lua-engine/core/storage.lua`: save seguro e determinístico, incluindo inventários de nós.
- `lua-engine/core/itemstack.lua`: valores `ItemStack` copiáveis e metadados.
- `lua-engine/core/inventory.lua`: listas `InvRef` e inserção com sobras.
- `lua-engine/core/modloader.lua`: leitura de `mod.conf`, ordenação por dependências e falha explícita.
- `lua-engine/core/modenvironment.lua`: ambiente de globais separado que executa arquivos Lua reais dos mods de referência, com acesso ao sistema de arquivos limitado aos diretórios de mods declarados. **Não é sandbox de segurança contra código não confiável.**
- `lua-engine/core/modstorage.lua`: armazenamento de mod por runtime, ainda sem persistência em disco.
- `lua-engine/core/bitops.lua`: bitops de 32 bits em Lua sem operadores da sintaxe Lua 5.3.
- `lua-engine/core/pcgrandom.lua`: gerador PCG32 com dois limbs de 32 bits e estado restaurável; referência Luanti 5.18.0.
- `tests/lua_engine_real_voxelibre.lua`: executa 11 módulos upstream em CI Lua 5.4 e LuaJIT, incluindo verificações de flowlib e conversão de inventários com vl_legacy.
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

### Fase 5 — bitops e PCG32

Foram implementados bitops aritméticos de 32 bits em Lua puro e uma
implementação PCG32 baseada no algoritmo do Luanti 5.18.0, usando
metades de 32 bits para evitar perda de precisão em LuaJIT.
Os testes comparam sequências determinísticas de valores assinados
com vetores de referência para sementes 0, 42, 12345 e -1.
O módulo `mcl_util` e sua dependência `vl_unittests` passam a integrar
o teste real de carregamento, além dos seis módulos anteriores.

**Limitação:** sementes/seq em valor numérico Lua acima do intervalo
exato de 53 bits são rejeitadas explicitamente; o código Luanti aceita
u64 completo. A API ainda não é 1:1 nesse caso. PCG32 não é gerador
criptograficamente seguro. Continua faltando rodar o jogo inteiro.

### Fase 6 — manipulação voxel e módulos de blocos

- Implementados `VoxelArea` (indexação x-fastest),
  `VoxelManip` (leitura alinhada em mapblocks 16³,
  `get_data`, `set_data`, `get_param2_data`,
  `set_param2_data`, `get_node_at`,
  `set_node_at` e `write_to_map`) e mapa de IDs.
- IDs numéricos são temporários e reproduzíveis dentro da
  sessão, mas **não garantem igualdade com os IDs internos do Luanti**.
  O formato de salvamento antigo continua baseado em nomes de nós.
- `register_biome`, `register_ore` e `register_decoration`
  armazenam configurações sem gerar biomas ou recursos minerais.
- O voxel buffer possui limite de 262.144 células por chamada
  e não implementa luz, líquidos, emerge assíncrono ou
  serialização nativa do Luanti.
- O terreno da demo 3D usa agora VoxelManip em vez de chamadas
  `set_node` individuais; o terreno continua sendo uma simulação
  simples, não uma reprodução do mapgen VoxeLibre.
- O teste de boot integra os módulos originais independentes
  `flowlib`, `vl_legacy` e `controls`, somados aos oito
  módulos anteriores. Testa consultas reais de água, conversão de
  inventário legado e registro de callbacks sem jogadores conectados.

**Ainda não são carregados os módulos de gameplay `mcl_core`,
`mcl_mapgen_core` e `mcl_biomes` completos**. Dependem de outros
módulos, da geração do motor e de centenas de funções que ainda faltam.

### Fase 7 — chunks e dependências de mcl_core

O gerador próprio em `lua-engine/core/worldgen.lua` produz terreno de
teste determinístico a partir da semente, com camadas de solo, areia,
água, cavernas simplificadas, minério e árvores. O gerador utiliza
`VoxelManip` da Fase 6, não APIs internas de terreno C++ do Luanti.

- Chunks 16×16, camada vertical **-16 a +31**, gerados sob demanda.
- Ordem de geração não altera os blocos resultantes, inclusive
  folhas que cruzam a borda entre chunks.
- `G cx cz seed` marca chunks gerados no save `LUAENGINE 1`;
  saves anteriores continuam legíveis. Regerar com seed diferente
  é recusado para evitar destruir dados do jogador.
- `F7` na demonstração gera o chunk da posição atual do jogador.
  A demo **não possui streaming automático**, física nem meshing otimizado.
- A análise `mcl_core_dependencies.py` percorre os `mod.conf`
  originais do VoxeLibre, sem alterar arquivos, e produz o fechamento
  das dependências de `mcl_core` como artefato da CI.
- **Ainda não executa `mcl_core`**, `mcl_mapgen_core` ou
  `mcl_biomes` no novo motor. O mapa de teste não tem
  correspondência 1:1 com as sementes do Luanti.

Os testes de integração continuam executando os **11 módulos
originais** já confirmados na Fase 6; nenhum módulo novo foi declarado
compatível sem executar seu código original e validar o resultado.
