# Luanti 5.18 Mapgen V7 — etapa de terreno bruto (Fase 81)

**Referência fixa:** `luanti-org/luanti` tag `5.18.0`, `src/mapgen/mapgen_v7.cpp` e `src/mapgen/mapgen_v7.h`, licença LGPL-2.1-or-later. Esta etapa porta partes definidas do código original; não cria um gerador novo por inspiração no Minecraft ou no VoxeLibre.

## Funcionalidade portada

- Defaults numéricos originais de `MapgenV7Params` para terrain base/alt, terrain persistence, height selector, filler, mountain, rivers, caverns, caves, floatland e dungeons. As camadas de cave/floatland/dungeon ainda **não usam** essas definições.
- `baseTerrainLevelAtPoint(x,z)`: amostragem do `terrain_persist`, aplicação dessa persistência aos dois ruídos terrain base e alt, clamp 0..1 do height selector e regra que dá prioridade ao alt se exceder base.
- `getMountainTerrainAtPoint(x,y,z)`: ruído 2D de altura com mínimo 1 e densidade 3D compensada pelo gradiente vertical, fiel à condição `mountain_noise - (y - zero)/mountain_height >= 0`.
- `getRiverChannelAtPoint(x,y,z)`: teste de largura máxima 0.2, ruído 3D de crista, altitude e modulação de canal da rotina `getRiverChannelFromMap` original.
- `materialAt(x,y,z)`: classificação de *terreno bruto* em stone/water/air, com verificações de blocos de 16 nós e limiar do nível de água.
- `generateBlock(minp,maxp)`: geração sob demanda do mapblock alinhado de 16³ células, sem sobrescrever blocos modificados/residentes. O runtime somente habilita esse gerador mediante `enableMapgenV7Base(config)`; a demo não é alterada automaticamente.
- O mecanismo de `core.emerge_area` da fase 79 identifica `EMERGE_GENERATED` na primeira criação, preserva os marcadores de geração, dispara os callbacks já suportados e usa `EMERGE_FROM_DISK` em reinício com armazenamento segmentado.

## Como habilitar explicitamente

```lua
local rt = require('core.runtime').new({
  mapgen = { seed=42, mg_name='v7', water_level=1 }
})
rt.api.register_node('terrain:stone',{description='Stone'})
rt.api.register_node('terrain:water',{description='Water'})
local v7 = rt:enableMapgenV7Base({
  stone='terrain:stone',
  water='terrain:water',
  spflags='mountains,ridges,caverns'
})
-- Os nomes devem ser substituídos pelos nós realmente registrados pelo jogo.
-- rt.api.emerge_area(...) gera o terreno bruto com a fila cooperativa.
```

Os nomes dos materiais são parâmetros explícitos porque os aliases de mapgen e as definições de nós vêm dos mods do jogo original; o motor não os substitui por nós fictícios.

## Diferenças conhecidas com Luanti nativo

A rotina original trabalha em **chunks completos**, incluindo bordas de sobregeração de um bloco e um pipeline posterior de caves, biomes, ores, decorations, dungeons, lighting, liquids, floatlands e outros objetos. Esta fase executa exclusivamente a porção inicial **por mapblock**, portanto não reivindica equivalência de um mundo final gerado 1:1. A amostragem ponto-a-ponto do ruído de montanhas/rios pode diferir no último bit da amostragem `float` de C++ feita em arrays. O ciclo original de geração exige os callbacks e a ordenação total do EmergeManager, ainda pendentes.

**Caverns não são geradas nesta fase. Floatlands ativadas provocam erro explícito**, em vez de produzir geografia substituta. `caverns` pode estar presente no `mgv7_spflags` padrão, mas ainda não tem efeito: isso deve ser considerado nos testes e na interpretação dos resultados.

## Verificação

```sh
lua5.4 tests/lua_engine_mapgen_v7.lua
luajit tests/lua_engine_mapgen_v7.lua
```

Os testes comparam altura, montanhas e rios às expressões matemáticas do código-fonte e validam geração de 16³, camadas de água/ar, reabertura a partir do disco, preservação de edição e ausência de regeneração sobre regiões já existentes. Eles não substituem testes de equivalência visual de biomas do VoxeLibre.
