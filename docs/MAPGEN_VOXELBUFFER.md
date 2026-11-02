# Fase 85 — buffer MMVManip com CONTENT_IGNORE e overgeneration V7

## Objetivo e referência

A geração por chunks da Fase 84 produzia a região principal, mas ainda não distinguia corretamente `CONTENT_IGNORE` (nó sem informação no buffer) de `CONTENT_AIR` (nó efetivamente gerado) e não produzia as duas camadas verticais extras do `MapgenV7::generateTerrain`.

Referências originais fixas do **Luanti 5.18**:

- [`src/voxel.h`](https://github.com/luanti-org/luanti/blob/5.18.0/src/voxel.h): `VoxelManipulator`, `VOXELFLAG_NO_DATA`, `VOXELFLAG_CHECKED1`, `getNodeNoExNoEmerge`.
- [`src/voxel.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/voxel.cpp): layout X mais rápido e `copyTo` que não copia `CONTENT_IGNORE`.
- [`src/mapgen/mapgen_v7.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapgen/mapgen_v7.cpp): `generateTerrain` percorre de `node_min.Y-1` a `node_max.Y+1`, pulando nós que não sejam `CONTENT_IGNORE`; o critério de geração de rios usa `node_max.Y` do chunk inteiro.
- [`src/cavegen.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapgen/cavegen.cpp): `VMANIP_FLAG_CAVE = VOXELFLAG_CHECKED1` em cavernas pequenas de caminhada aleatória.

Licença do código original: LGPL-2.1-or-later.

## Código novo

`lua-engine/core/mapgen_voxelbuffer.lua` é um **adaptador Lua de staging esparso**, não um substituto integral do `MMVManip` nativo.

- Coordenadas completas de `full_node_min` a `full_node_max`, índices em ordem X → Y → Z, 1-based em Lua.
- Célula não encontrada e não emergida: `ignore` com bit `VOXELFLAG_NO_DATA`.
- Ar gerado: valor `air` armazenado explicitamente, sem confusão com `ignore`.
- Mapblocks já residentes: conteúdo e ar existentes retornam do mundo original, e nenhuma alteração é permitida por esse buffer.
- `mark_cave`: bit transitório `VOXELFLAG_CHECKED1` em cavernas pequenas. Não há serialização de flags ainda.
- `commit_core()`: verifica primeiro os mapblocks originais e copia somente as células do núcleo; nunca converte a borda de overgeneration em mapblocks considerados totalmente gerados.

O `MapgenV7` gera no buffer as camadas de `Y-1` e `Y+1` ao longo de todo o plano X/Z do núcleo, como o código original. O critério de rios agora utiliza `node_max.Y` do chunk no modo de staging, não a altitude de cada mapblock isolado. As rotinas antigas `enableMapgenV7Base` e a API pública `get_voxel_manip` não foram substituídas.

## Escopo do experimento

O fluxo opcional existente `Runtime:enableMapgenV7Chunks(config,{x=2,y=1,z=2})` utiliza o buffer. O modo antigo por mapblocks permanece disponível e as estruturas de armazenamento persistente não mudam.

Ainda **não há equivalência 1:1** com o `MMVManip` original:

- A borda extra em X/Z é reservada e identificada, mas não é preenchida por uma passagem de terreno completa. A sobregeração em Y fica no buffer temporário e é descartada no commit.
- O `MMVManip` original pode enviar alterações de múltiplos mapblocks com `blitBackAll`; esta etapa mantém o commit apenas do núcleo para não invalidar blocos vizinhos não gerados. A transição exata entre chunks ainda requer uma representação persistente de blocos parcialmente gerados.
- Os flags de caverna são transitórios no buffer, não integrados à serialização de `VoxelManip`.
- O tamanho do chunk processado continua limitado a 2 por eixo, frente ao padrão 5×5×5 do Luanti; não existe suporte integral a biomas, iluminação, líquidos, ores ou decorações.

## Testes

```sh
lua5.4 tests/lua_engine_mapgen_voxelbuffer.lua
luajit tests/lua_engine_mapgen_voxelbuffer.lua
```

Cobrem a diferença entre `ignore` e `air`, índice X mais rápido, flags `NO_DATA` e `CHECKED1`, nós residentes que não podem ser sobrescritos, sobregeração Y±1, não persistência da borda, commit do núcleo e ligação com o fluxo real de `emerge_area`. As suítes da Fase 84 continuam executando.
