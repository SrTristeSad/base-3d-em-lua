# Fase 92 — MMVManip initialEmerge(false) com expansão repetida

Referência fixa: Luanti 5.18, [src/map.cpp](https://github.com/luanti-org/luanti/blob/5.18.0/src/map.cpp), `MMVManip::initialEmerge` (linhas 805–856), `getCoveredBlocks` (858–892), `VoxelManipulator::addArea`. Licença do código-fonte original: LGPL-2.1-or-later.

## Comportamento portado

A API `MapgenVoxelBuffer:initialEmerge(false, block_min?, block_max?)` pode ser chamada novamente, inclusive com uma região de mapblocks que exceda a geometria do buffer existente. Sem as coordenadas opcionais, verifica a área já conhecida; com as coordenadas, solicita a inclusão dessa região. As coordenadas opcionais são **posições de mapblocks**, não posições de voxels.

- A área `full_node_min..full_node_max` cresce para abranger a região solicitada; o cálculo `VoxelArea:index` segue o layout nativo X/Y/Z, com X variando mais rapidamente.
- Os nós explícitos anteriores, parâmetros, flags de cavernas, intervalos de ar conhecido e snapshots já capturados permanecem inalterados quando a geometria cresce.
- Como no original, um mapblock com **qualquer voxel conhecido** em `getCoveredBlocks` é preservado na reemergência, mesmo quando o mapa vivo mudou. Mapblocks sem dados podem ser importados em chamada posterior, caso tenham sido carregados.
- A importação usa somente blocos presentes na memória, sem abrir arquivos de mundo; blocos vazios, mas residentes, representam ar conhecido.
- Preserva proteção contra alteração concorrente em cavernas de blocos vizinhos por meio da validação anterior ao commit.
- `MapgenV7:generateChunk` continua usando a chamada `initialEmerge(false)` de uma única etapa. A expansão repetida fica disponível para os próximos estágios do porte.

## Uso

```lua
local buffer = MapgenVoxelBuffer.new(map, chunkGeometry)
buffer:initialEmerge(false)  -- captura área inicial
buffer:initialEmerge(false, {x=2,y=0,z=0}, {x=3,y=0,z=0})
-- área expandida, sem sobrescrever dados já conhecidos
```

Executar a regressão:

```sh
lua5.4 tests/lua_engine_mmvm_expand.lua
luajit tests/lua_engine_mmvm_expand.lua
```

O teste verifica expansão em X positivo/negativo e Y negativo; índice de voxels; conservação de flags e parâmetros; blocos com dados parciais que devem ser ignorados em chamadas sobrepostas; blocos carregados apenas depois da primeira chamada; ar de bloco vazio; snapshot estável; validação de limites; e ausência de leitura implícita do disco.

## Limitações explícitas

Esta fase **não** implementa `initialEmerge(true)`: no Luanti, esse caminho chama `Map::emergeBlock(p, true)`, que pode carregar do disco **ou criar um novo MapBlock ainda não gerado**. O motor Lua atual distingue blocos gerados e parciais de outra forma e ainda não tem a mesma representação dos blocos criados vazios. Também não foi implementado um `VoxelArea` denso, nem todos os métodos/flags de `VoxelManipulator`.

Existe um limite defensivo de **8 milhões de posições** para a área expandida em Lua, e o buffer permanece limitado às coordenadas de voxels que a base Lua suporta. Esse limite não equivale a uma restrição do Luanti nativo.

A compatibilidade integral 1:1 com o motor Luanti e a execução completa do VoxeLibre original ainda não foram demonstradas.
