# Fase 83 — núcleo CavesRandomWalk do Luanti 5.18

## Fontes de referência

- [Luanti 5.18.0 `src/mapgen/cavegen.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapgen/cavegen.cpp), especificamente `CavesRandomWalk::makeCave`, `makeTunnel`, `carveRoute` e `isPosAboveSurface`.
- [`src/mapgen/mapgen.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapgen/mapgen.cpp), `getBlockSeed2` e `generateCavesRandomWalk`.
- [`src/noise.h`](https://github.com/luanti-org/luanti/blob/5.18.0/src/noise.h), `PseudoRandom`.
- Licença original do código portado: LGPL-2.1-or-later.

## Trabalho implementado

O novo `lua-engine/core/caves_randomwalk.lua` porta:

- `getBlockSeed2(full_node_min, world_seed)`: hash **com overflow u32 completo** (não confundir com a máscara de 31 bits de `noise2d`). Usa multiplicação por limbs de 16 bits para preservar o resultado em LuaJIT sem overflow de mantissa.
- `PseudoRandom(blockseed + 21343)` compartilhado por todas as cavernas de um chunk, com a ordem de sorteios descrita no C++.
- Quantidades de túneis pequenos e grandes (`small_cave_num_min/max`, `large_cave_num_min/max`), limites por `large_cave_depth`, seleção de comprimentos, direções, saltos, início de percurso, diâmetros, pisos planos e seções rugosas.
- Escavação de seções com limites de diâmetro da implementação original, incluindo a peculiaridade de `ps.range(0,1)` reavaliado a **cada teste** do limite de X.
- Preservação dos materiais não pertencentes à rocha-base; inundação de túneis grandes no regime básico com água/lava e ruído de cave liquids histórico, sem reivindicar compatibilidade com líquidos de biomas.
- Eventos internos `cave_begin`, `cave_end`, `large_cave_begin`, `large_cave_end` para posterior integração com `GenerateNotifier`.
- Integração **opcional** ao V7 já existente: `Runtime:enableMapgenV7Base({stone='...',water='...',randomwalk_caves=true})`. A altura das colunas é capturada depois do terreno bruto e antes dos cortes; a etapa vem depois do ruído de cavernas, de acordo com a sequência de `MapgenV7::makeChunk`.

## Dependências ainda em aberto — não é 1:1

A implementação opera sobre **mapblocks 16³ isolados**, enquanto o Luanti nativo calcula `CavesRandomWalk` sobre um chunk e pode escavar um `MMVManip` que inclui blocos vizinhos. A rotina Lua limita a escavação ao mapblock corrente e não altera blocos adjacentes ainda não gerados. **Essa limitação altera as estruturas e a conectividade das cavernas.**

O `BiomeGen` original ainda não foi portado: são utilizados apenas os materiais de rocha-base, e o fallback histórico de líquidos, em vez de `biome->c_cave_liquid`. Também faltam: flags de voxel `VMANIP_FLAG_CAVE`, callbacks nativos de `GenerateNotifier`, bordas e altura do chunk, correções `float` C++ de 32 bits, passe completo de biomas/top/filler e integração de outros componentes de mundo. Não reivindicar mundo final equivalente ao Luanti original nem funcionamento completo do VoxeLibre.

Para manter as fases anteriores intactas, `randomwalk_caves` fica **desabilitado por padrão**. Todos os níveis de mundo existentes permanecem sem alteração se o recurso não for explicitamente selecionado.

## Testes

```sh
lua5.4 tests/lua_engine_caves_randomwalk.lua
luajit tests/lua_engine_caves_randomwalk.lua
```

Verificam hash e seed u32 contra valores de referência do código C++, determinismo de rotas em duas execuções, sorteios com mesmo seed, escavação real de seções, preservação de água, limites da superfície, limiar de geração grande e fluxo de `emerge_area` com disco e reabertura. As suítes anteriores continuam executando no CI.
