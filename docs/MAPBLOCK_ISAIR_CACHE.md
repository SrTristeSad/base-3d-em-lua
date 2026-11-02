# Fase 100 — MapBlock::isAir e expiração do cache

## Fontes originais (Luanti 5.18.0)

- [`src/mapblock.h`: `isAir`, `expireIsAirCache`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.h): `isAir()` consulta um cache e recalcula somente quando expirado.
- [`src/mapblock.cpp`: `actuallyUpdateIsAir`, `expireIsAirCache`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.cpp): somente os 4096 `MapNode` com conteúdo `CONTENT_AIR` caracterizam um mapblock como todo-ar. Metadados, timers, `param1` e `param2` não fazem parte do predicado.
- [`src/map.cpp`: `MMVManip::blitBackAll`](https://github.com/luanti-org/luanti/blob/5.18.0/src/map.cpp): a transferência invalida o cache mesmo quando não há alteração do conteúdo dos nós.

## Implementação Lua

```lua
local value = map:is_mapblock_air('0,0,0')
-- true: todos os 16³ nós são AIR
-- false: bloco residente com ao menos um nó não AIR/IGNORE
-- nil: nenhum MapBlock residente identificado
map:expire_mapblock_air_cache('0,0,0')
```

O novo `block_air_cache` armazena valores booleanos por chave canônica `x,y,z`. A primeira consulta de um mapblock residente percorre os nós explícitos e guarda o resultado. A tabela `block_air_scans` é um contador de recálculos para diagnóstico/regressão; nenhum desses estados derivados é serializado.

- **Blocos gerados:** nós ausentes na representação esparsa equivalem a `AIR`. Um `AIR` com `param1` ou `param2` não nulo continua sendo ar.
- **Blocos transitoriamente não gerados:** nós ausentes equivalem a `CONTENT_IGNORE`. Para um bloco `blank_blocks` ser todo-ar, ele precisa ter explicitamente conhecidos os 4096 nós como `AIR`.
- `Map:set_node` expira o cache do mapblock em qualquer escrita, inclusive idêntica, com custo O(1) no caminho quente de geração.
- `Map:create_blank_block` e `Map:finish_blank_block` expiram o cache na mudança de representação da área.
- `Buffer:blitBackAll` expira o cache de **todos** os destinos efetivamente copiados, inclusive em blits sem mudanças nodais — de acordo com `MapBlock::expireIsAirCache` na rotina nativa.
- `MapBlockStore:unload` elimina o cache do bloco ao remover sua representação residente. `emerge` constrói o resultado sob demanda a partir dos nós efetivamente recuperados.

## Regressões

```sh
lua5.4 tests/lua_engine_mapblock_isair.lua
luajit tests/lua_engine_mapblock_isair.lua
```

O teste exercita coordenação negativa, AIR com parâmetros, CONTENT_IGNORE, preenchimento 16³ de um mapblock parcial, transição para estado gerado, metadados, timers, invalidação em escrita idêntica e em blit idêntico, além de unload/emerge usando armazenamento segmentado e retrocompatibilidade dos saves.

## Limites

Trata-se de um **cache derivado de conteúdo MapNode**, e não de um porte integral da estrutura `MapBlock` do Luanti. A implementação não adiciona iluminação propagada nativa, mapa binário, estado de completude da luz por direção, sincronização de cache entre threads ou todos os motivos de modificação (`MOD_REASON_*`). A semântica `nil` para mapblocks não residentes é uma conveniência do adaptador Lua (um `MapBlock::isAir()` C++ só existe quando há objeto MapBlock). A reconstituição inicial por varredura dos nós explícitos do mapa inteiro privilegia integridade e compatibilidade; um índice incremental por mapblock pode ser acrescentado em fase futura se benchmarks indicarem necessidade.
