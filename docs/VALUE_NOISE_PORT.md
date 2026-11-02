# Fractal value noise original — Luanti 5.18 (Fase 80)

Esta fase porta para Lua a **família de funções matemáticas de ruído** usada na geração procedural do Luanti 5.18. O algoritmo portado é `src/noise.cpp` (value noise com interpolação), **não** uma implementação nova de Perlin gradient noise. Luanti renomeou a API pública em 5.12.0, preservando aliases legados.

Referências fixas no Luanti 5.18.0: `src/noise.cpp`, `src/noise.h`, `src/script/lua_api/l_noise.cpp`, `src/script/lua_api/l_env.cpp` e `doc/lua_api.md`. A parte matemática original de `noise.cpp` é distribuída com aviso BSD; atribuição e licença originais permanecem nos arquivos-fonte upstream.

## APIs implementadas

- `core.get_value_noise(noiseparams)` e a assinatura histórica `core.get_value_noise(seed, octaves, persistence, spread)`. Somam o seed do mundo configurado no runtime ao seed do ruído, conforme a API C++.
- `core.get_value_noise_map(noiseparams, size)`: mapas 2D/3D com o mesmo seed de mundo; dimensões `x,y,z`, com `z > 1` para 3D.
- `core.get_perlin` e `core.get_perlin_map`: aliases das duas APIs.
- Construtores globais para mods: `ValueNoise`, `ValueNoiseMap` e aliases históricos `PerlinNoise`, `PerlinNoiseMap`, **sem** adicionar seed de mundo a estes construtores globais.
- Métodos `get_2d`, `get_3d`, `get_2d_map`, `get_3d_map`, formas `_flat`, `calc_2d_map`, `calc_3d_map`, `get_map_slice` e aliases sem underscore. O armazenamento do mapa é em ordem **X mais rápido, depois Y e Z**.
- Parâmetros originais `offset`, `scale`, `spread`, `seed`, `octaves`, `persist`/`persistence`, `lacunarity` e flags `defaults`, `eased`, `noeased`, `absvalue`. Default: 2D usa suavização quintic; 3D não usa suavização.
- O polinômio hash `1619*x + 31337*y + 52591*z + 1013*seed` e multiplicação cúbica são computados com módulo exato de 31 bits em LuaJIT e Lua 5.4 sem overflow de mantissa de 53 bits. Testes verificam vetores do polinômio original.

## Correção e limites

O algoritmo combinatório foi portado a partir do código de referência, inclusive a variação de suavização entre 2D e 3D. **A implementação atual não garante igualdade bit a bit para os valores de ponto flutuante**: C++ usa `float` de 32 bits em etapas intermediárias, e Lua usa números de precisão dupla. Os testes usam tolerância numérica onde apropriado e comparação exata dos hashes em posições inteiras.

Limites explícitos da versão Lua: até 24 oitavas, arrays com até 262.144 células, controle de frequência para evitar que comprimento de onda caia abaixo de um nó. Isto evita uso excessivo de CPU/RAM, mas constitui uma diferença da flexibilidade total nativa. Não há implementação dos buffers de ruído com persistência espacial variável e alguns flags não implementados no Luanti.

**Este módulo ainda não gera o terreno original do VoxeLibre.** Mapgen V7, cavidades, biomas, decoração, ores, liquids, biometadata, sequência de callbacks do EmergeManager e geração de chunks originais continuam pendentes. A demonstração independente não foi rebatizada como jogo original.

## Testes

```sh
lua5.4 tests/lua_engine_value_noise.lua
luajit tests/lua_engine_value_noise.lua
```

A suíte verifica os hashes originais (inclusive seeds negativos), flags, interpolação, sementes de mundo, maps 2D/3D, índices, slices, argumentos inválidos e ambiente isolado de mods.
