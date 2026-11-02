# Fase 82 — túneis de ruído e cavernas profundas do Luanti 5.18

**Fonte original**: [Luanti 5.18 `src/mapgen/cavegen.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapgen/cavegen.cpp), classes `CavesNoiseIntersection` e `CavernsNoise`; [`src/mapgen/mapgen.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapgen/mapgen.cpp), `MapgenBasic::generateCavesNoiseIntersection` / `generateCavernsNoise`; e `src/mapgen/mapgen_v7.cpp`. Licença dos originais: LGPL-2.1-or-later.

## O que foi portado

O novo módulo `lua-engine/core/cave_noise.lua` implementa a parte de decisão matemática e escavação inicial:

- `contour(n) = 0` se `abs(n)>=1`, senão `1-abs(n)`.
- Túneis: `contour(cave1(x,y,z)) * contour(cave2(x,y,z)) > cave_width`, com `cave_width` padrão `0.09` e desativação de ruído em `cave_width >= 10`, conforme upstream.
- Cavernas: ruído 3D `abs(cavern(x,y,z)) * min((cavern_limit-y)/cavern_taper,1)`. Escava o solo acima de `cavern_threshold` (padrão `0.7`) e sinaliza proximidade acima de `cavern_threshold - 0.1`. Defaults `cavern_limit=-256`, `cavern_taper=256`.
- Mantém a ordem do pipeline original: escavação da interseção de ruídos primeiro, cavernas depois.
- Rejeita escavação de líquidos ou nós que não correspondem ao material de rocha bruta do gerador. Isso restringe a operação à área sobre a qual há informação confiável de conteúdo do terreno.
- Integrado opcionalmente a `Runtime:enableMapgenV7Base({ ..., noise_caves=true })`. O mundo criado nas fases anteriores continua inalterado por padrão.
- Persiste mapblocks **inteiramente escavados**: os marcadores de geração permitem distinguir blocos vazios já criados de regiões desconhecidas no disco.

## Exemplo para testes, sem fingir que é VoxeLibre completo

```lua
local rt = require('core.runtime').new({mapgen={seed=42,mg_name='v7'}})
rt.api.register_node('terrain:stone',{})
rt.api.register_node('terrain:water',{})
local v7 = rt:enableMapgenV7Base({
  stone='terrain:stone',
  water='terrain:water',
  spflags='mountains,ridges,caverns',
  noise_caves=true
})
```

O usuário/host precisa fornecer os nomes dos nós registrados pelo jogo original. `core.emerge_area` provoca geração de terreno bruto com túneis/cavernas de ruído em um mapblock de 16³ células.

## Diferenças relevantes para compatibilidade 1:1

Esta **não é ainda** a implementação completa de `CavesNoiseIntersection::generateCaves`: a original utiliza o `biomemap` e a `BiomeGen` para recolocar a superfície, o piso, o filler e o teto de entradas de túneis, além de `1-down overgeneration` em chunks maiores. Como o pipeline de biomas ainda não foi portado, esta etapa escava apenas o nó de rocha bruto, não as substituições de biome top/filler.

**Ainda não foram portados:** `CavesRandomWalk` (cavernas de caminhada aleatória, inclusive grandes cavernas e líquidos), geração real por chunks de tamanho configurável, carimbos de blocos completos com bordas, biomas, minérios, dungeons, decorações, líquidos e iluminação de mapgen. `near_cavern` é calculado, mas ainda não influencia a geração de `CavesRandomWalk`, que permanece ausente. Logo, **nenhuma equivalência de mundo 1:1 é reivindicada**.

A implementação de ruído da Fase 80 é matematicamente baseada no original, mas Lua não necessariamente reproduz bit a bit cada arredondamento de `float` intermediário de C++.

## Testes

```sh
lua5.4 tests/lua_engine_cave_noise.lua
luajit tests/lua_engine_cave_noise.lua
```

Os testes exercitam critérios exatos de contorno e amplitude, profundidade e limiar de proximidade, bloqueio de escavação de materiais não elegíveis, desativação por `cave_width >= 10`, um mapblock inteiramente escavado e recarregado do disco sem regeneração, fase antiga sem mudança e cavernas profundas independentes da interseção de ruídos.
