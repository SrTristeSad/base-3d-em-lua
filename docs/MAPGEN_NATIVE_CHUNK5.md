# Fase 86 — chunk V7 de 5×5×5 mapblocks, sem alocar ar por voxel

## Referência original

O Luanti 5.18 usa `MapgenParams::chunksize = v3s16(5)`, `EmergeManager::getContainingChunk` e o volume de `MMVManip` com borda de 1 mapblock. Fontes fixas:
- [`src/mapgen/mapgen.h`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapgen/mapgen.h)
- [`src/mapgen/mapgen.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapgen/mapgen.cpp), `MapgenParams` e `getBlockSeed2`.
- [`src/emerge.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/emerge.cpp), `getContainingChunk`.
- [`src/voxel.h`](https://github.com/luanti-org/luanti/blob/5.18.0/src/voxel.h), `VOXELFLAG_NO_DATA` e `CONTENT_IGNORE`.
- [`src/mapgen/mapgen_v7.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapgen/mapgen_v7.cpp), `generateTerrain`.
- Licença original: LGPL-2.1-or-later.

## Implementação

- `Runtime:enableMapgenV7Chunks(config, size)` agora aceita e usa por **padrão** `size=5`: núcleo de 80×80×80 nós, 125 mapblocks, área total com borda de 112×112×112 posições. Tamanhos 1 a 5 por eixo são aceitos; acima disso, falham com erro explícito. `enableMapgenV7Base` permanece inalterado.
- `MapgenVoxelBuffer` implementa `begin_terrain_column(x,z,ymin,ymax)`, identificando uma faixa vertical de **ar gerado conhecido**, sem criar uma entrada de tabela Lua por voxel. Materiais sólidos e líquidos são armazenados como exceções explícitas; escavar uma dessas exceções grava um nó de ar explícito. O sistema mantém `get_node`, `get_flags`, `CONTENT_IGNORE`, proteção de blocos residentes, `VMANIP_FLAG_CAVE` e os limites com borda.
- `MapgenV7:_generateRegion` preenche os intervalos de ar antes de gravar materiais não-ar, incluindo as camadas verticais Y±1 do Luanti 5.18. As cavernas continuam lendo o mesmo resultado (ar conhecido, rocha e água).
- `commit_core` não exporta as faixas de ar como milhares de nós; os **125 mapblocks** são marcados como gerados pelo `emerge_area`. `MapBlockStore` salva também blocos inteiramente vazios como imagens válidas do mundo.

## Como ativar

```lua
local gen = rt:enableMapgenV7Chunks({
  stone='terrain:stone',
  water='terrain:water',
  noise_caves=true,
  randomwalk_caves=true
}) -- tamanho de chunk 5×5×5, como o original

-- Para manter os mapas experimentais antigos:
local small = rt_alt:enableMapgenV7Chunks(config,{x=2,y=1,z=2})
```

O teste `tests/lua_engine_native_chunk5.lua` valida exatamente 125 blocos, coordenadas negativas, seed de chunk, sobregeração não gravada, status `EMERGE_GENERATED`, ausência de 512.000 entradas Lua de ar em um chunk vazio, persistência de blocos vazios e recuperação do disco. Executado em Lua 5.4 e LuaJIT.

## Limitações — ainda não é porte integral 1:1

- A dimensão padrão dos chunks é agora equivalente à original, mas **não** a simulação completa. `MapgenV7` continua opcional e o algoritmo de geração integral ainda precisa dos biomas, flags, minérios, decoração, iluminação, líquidos e comportamentos faltantes.
- A otimização de ar por intervalo é uma representação interna Lua, não uma cópia física dos arrays densos do C++. Mantém os estados observáveis disponíveis nesta etapa, mas não inclui todas as operações de `MMVManip`.
- A região extra Y±1 continua transitória, e a borda X/Z segue sem geração/commit; a continuidade perfeita entre chunks distintos ainda não foi demonstrada.
- Um chunk de rocha maciça ainda armazena muitos nós individualmente; o ganho de memória é maior para regiões de ar (céu, espaços abertos). Não afirmar desempenho nem compatibilidade integral sem medir.
- Se algum mapblock do chunk já existe na RAM/disco, o gerador utiliza fallback de bloco isolado para preservar edições anteriores. Portanto, o mesmo mapa parcialmente explorado pode diferir do gerado por um chunk limpo.
