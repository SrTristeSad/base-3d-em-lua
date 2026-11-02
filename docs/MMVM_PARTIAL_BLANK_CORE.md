# Fase 94 — preservar mapblocks não gerados com conteúdo parcial

## Referências do Luanti 5.18

- [`src/map.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/map.cpp): `MMVManip::initialEmerge` preserva nós já conhecidos de mapblocks carregados, mas permite continuar a trabalhar com `CONTENT_IGNORE` em blocos ainda não gerados
- [`src/mapblock.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.cpp): `MapBlock::copyFrom` transfere dados de `VoxelManipulator` sem transformar o estado do bloco antecipadamente
- [`src/servermap.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/servermap.cpp): a finalização de `Mapgen` é distinta da criação de blocos vazios

## Bug corrigido

A Fase 93 introduziu `Map.blank_blocks` e `MMVManip::initialEmerge(true)`, permitindo criar mapblocks com `CONTENT_IGNORE`. Porém, se algum voxel conhecido tivesse sido escrito antes da geração completa, `Map:set_node` criava uma revisão, e `MapgenVoxelBuffer:commit_core` recusava toda a geração, apesar de o bloco continuar **não gerado**.

O código agora captura `initial_block_revisions` no mesmo instante em que recebe os nós e o estado do mapblock pelo `initialEmerge`. Durante o `commit_core`:

- Um bloco **já gerado** ainda não pode ser sobrescrito.
- Um bloco **transitório / não gerado** pode receber os voxels novos do terreno, desde que seu snapshot ainda seja válido.
- Voxels conhecidos capturados permanecem intactos: `terrain_writable` rejeita novas escritas nessas posições.
- Se qualquer outro código modificar o bloco depois da captura, a revisão não coincide e o commit aborta **antes de escrever qualquer voxel do núcleo**.
- Quando o gerador termina, `finish_blank_block` retira o estado provisório e transforma os espaços sem dados em ar conhecido; o `MapBlockStore` só passa a persistir o bloco completo.

Isso mantém as proteções de mudanças concorrentes implementadas anteriormente para o halo do `MMVManip`.

## Regressão

```sh
lua5.4 tests/lua_engine_mmvm_partial_core.lua
luajit tests/lua_engine_mmvm_partial_core.lua
```

Cobertura: nó existente com `param1/param2`, ar explícito parcial, `CONTENT_IGNORE`, proteção contra reescrita, revisão capturada, modificação concorrente, recusa de núcleo que foi gerado por outro processo, geração V7 de um mapblock parcialmente populado, armazenamento e recarga do mundo.

## Limitações

Não é o porte completo de `MapBlock::copyFrom`, nem implementa transações gerais do mundo. Blocos transitórios não são serializados como mapblocks Luanti nativos, e o pipeline integral de biomas, minérios, decorações, iluminação e líquidos continua incompleto.

A execução integral do VoxeLibre original permanece **não comprovada**.
