# Fase 88 — escavação de cavernas nas bordas X/Z do MMVManip

## Referência de comportamento

O Luanti 5.18, em `src/mapgen/cavegen.cpp::CavesRandomWalk::carveRoute` (linhas 565–574), aceita uma posição se estiver dentro de **`vm->m_area`** e se o conteúdo definido for material de terreno (`is_ground_content`). Não restringe a escavação ao núcleo `node_min..node_max`. O algoritmo usa o `MMVManip` preparado em `src/servermap.cpp::initBlockMake` e copia os dados de volta com `blitBackAll` em `finishBlockMake`.

Referências oficiais: [cavegen.cpp](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapgen/cavegen.cpp), [voxel.h](https://github.com/luanti-org/luanti/blob/5.18.0/src/voxel.h), [servermap.cpp](https://github.com/luanti-org/luanti/blob/5.18.0/src/servermap.cpp). Licença LGPL-2.1-or-later.

## Implementado

- `mapgen_border.lua:seedExpanded` importa os nós já conhecidos de sidecars em **toda a área extra X/Y/Z** do buffer de geração, não apenas dentro do núcleo. Não inventa materiais em `CONTENT_IGNORE` nem importa sobre mapblocks residentes.
- `mapgen_voxelbuffer.lua` distingue os voxels carregados inicialmente das **alterações posteriores** por meio de `mark_imports_clean()` e um conjunto de posições modificadas.
- `caves_randomwalk.lua` verifica os limites completos do buffer (`MMVManip::m_area.contains`) quando ele é utilizado; uma rocha conhecida na borda pode ser escavada. O modo histórico de mapa permanece restrito ao seu núcleo. A escavação **não altera mapblocks já residentes** (limitação declarada deste estágio).
- `mapgen_border.lua:publishModifiedHalo` exporta para os sidecars apenas modificações de voxels externos ao núcleo que **já estavam presentes como nós parciais conhecidos**, sem sobrescrever blocos completos nem inventar dados em regiões desconhecidas.
- `mapgen_v7.lua` liga a importação da área extra e a transferência de alterações às gerações normais e ao fallback por mapblock, preservando a transferência vertical da Fase 87.

## Teste independente

```sh
lua5.4 tests/lua_engine_mmvm_halo_caves.lua
luajit tests/lua_engine_mmvm_halo_caves.lua
```

Cobre escavação real via `CavesRandomWalk::_carveRoute` de rochas em uma borda X positiva, `CONTENT_IGNORE` sem modificação, flags de não-dados, retorno em sidecar, persistência/reload no disco e incorporação dos dados quando o chunk de destino for gerado. Mantém as demais suítes de regressão.

## Não é `MMVManip::blitBackAll` completo

Ainda não há geração de terreno **nova** nas regiões X/Z ampliadas, nem suporte a sobrescrever mapblocks vizinhos já completos como o sistema nativo pode fazer. A escavação X/Z depende de **rochas previamente conhecidas na região extra**, geralmente vindas de outra sobregeração. A marcação de `is_ground_content` ainda está restrita ao nome da rocha principal; biomas e outros materiais ainda precisam ser portados. Não há transação atômica conjunta entre sidecars e blocos, e a execução completa do VoxeLibre original não foi demonstrada.
