# Fase 89 — copiar alterações de cavernas para mapblocks vizinhos residentes

## Referências fixas
Luanti 5.18.0 (LGPL-2.1-or-later):
- [`src/mapgen/cavegen.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapgen/cavegen.cpp), `CavesRandomWalk::carveRoute`: escava voxels de terreno conhecidos dentro da área completa de `MMVManip`, não somente no núcleo.
- [`src/voxel.h`](https://github.com/luanti-org/luanti/blob/5.18.0/src/voxel.h), `VoxelManipulator`: dados conhecidos vs `VOXELFLAG_NO_DATA`.
- [`src/servermap.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/servermap.cpp), `ServerMap::initBlockMake` / `finishBlockMake`: prepara a área incluindo mapblocks residentes e usa `blitBackAll`.

## Implementação

A Fase 88 permitia escavar uma rocha na borda somente se ela viesse de um sidecar parcial. A Fase 89 implementa também o caso em que **o mapblock vizinho já foi carregado/gerado**:

- `MapgenVoxelBuffer:enable_resident_halo_caves(ground_name)` abre a janela de escrita **somente durante o CavesRandomWalk**. A geração de terreno não pode sobrescrever mapblocks residentes.
- `can_carve_resident` exige um nó de terreno com o nome permitido, posicionado fora do núcleo e dentro do `MMVManip`. Metadados e node timers proíbem o carve, protegendo o conteúdo persistente associado.
- `set_node` guarda uma cópia original e uma substituição provisória. O jogador/mundo continua vendo o nó antigo durante a preparação do chunk.
- `validate_resident_halo` é executada **antes de escrever qualquer nó do núcleo**; se a posição, `param1`/`param2`, metadados ou timers mudaram, a operação é abortada para evitar sobrescrever mudanças concorrentes.
- `commit_core` agora também transfere as substituições do halo residente com `Map:set_node`, conservando a revisão do mapblock e o fluxo normal de persistência. A quantidade fica em `lastChunkBorderStats.resident_blit`.
- O modo histórico `enableMapgenV7Base` e o processamento de sidecars parciais permanecem com a semântica anterior.

## Testes

```sh
lua5.4 tests/lua_engine_mmvm_resident_halo.lua
luajit tests/lua_engine_mmvm_resident_halo.lua
```

Verificam `CavesRandomWalk` escavando rocha residente na borda, ausência de mutação antes do commit, gravação e recarga do mapblock, preservação de `CONTENT_IGNORE`, conflitos de nome/parâmetros, metadados, timers e ausência de mudanças no caminho legado.

## Lacunas declaradas

Este não é o `MMVManip::blitBackAll` genérico. O commit aplica **apenas voxels de rocha escavados durante o CavesRandomWalk** dentro da área existente; não replica escritas arbitrárias de biomas, decorações, líquidos ou iluminação. `is_ground_content` do Luanti inclui outros materiais: nesta etapa o motor ainda usa o nome da rocha principal. Nós residentes com metadados/timers ficam protegidos de forma mais conservadora do que o upstream. A verificação de conflito é feita antes da gravação, mas este protótipo Lua não oferece transação multi-mapblock durável contra falha de disco. A execução integral do VoxeLibre original não foi demonstrada.
