# Fase 93 — `MMVManip::initialEmerge(true)` e mapblocks vazios não gerados

## Referência original

- [Luanti 5.18 — `src/map.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/map.cpp): `MMVManip::initialEmerge`, linhas 805–856.
- [`src/servermap.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/servermap.cpp): `ServerMap::emergeBlock(p, true)`, linhas 419–440; procura bloco na memória, depois em disco, senão cria um bloco vazio.
- [`src/mapblock.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.cpp): `MapBlock` inicializa os 16³ nós como `CONTENT_IGNORE`, sem marcar o bloco como gerado.
- [`src/voxel.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/voxel.cpp): `VoxelManipulator::copyFrom` copia os nós e limpa `VOXELFLAG_NO_DATA` do bloco existente, inclusive se os nós são `CONTENT_IGNORE`.

## Implementação em Lua/LuaJIT

- `Map.blank_blocks` representa mapblocks **presentes, mas ainda não gerados**. `Map:create_blank_block(key)` cria um bloco de `CONTENT_IGNORE` sem alocar uma tabela Lua para cada voxel. `Map:get_node` distingue esse estado de ar gerado.
- `MapBlockStore:load_or_create_blank(key)` tenta carregar um bloco existente persistido **antes** de criar um bloco vazio temporário. Arquivos inválidos produzem erro; não são substituídos por blocos vazios.
- `MapgenVoxelBuffer:initialEmerge(true)` expande a área, copia os blocos já carregados e cria blocos vazios nos locais ausentes. Os blocos vazios são capturados com `CONTENT_IGNORE` e flags de dados conhecidos (sem `VOXELFLAG_NO_DATA`), conforme `MapBlock::copyTo`.
- `MapgenVoxelBuffer:terrain_writable` e `set_node` permitem gerar terreno sobre os voxels `CONTENT_IGNORE` desses blocos **não gerados**, mas continuam protegendo mapblocks já gerados.
- `emerge_area` não considera blocos vazios temporários como terreno gerado: eles podem passar ao gerador posteriormente, retornando `EMERGE_GENERATED`.
- `Runtime:markGeneratedMapBlocks` encerra o estado transitório somente após a geração ser confirmada, convertendo os vazios restantes em ar conhecido.
- `MapBlockStore:flush` não serializa os blocos transitórios como imagens completas; um bloco vazio sem geração é mantido somente em memória. Arquivos completos mantêm o formato `LUAENGINE 1`.

## Verificação

```sh
lua5.4 tests/lua_engine_mmvm_create_blank.lua
luajit tests/lua_engine_mmvm_create_blank.lua
```

O teste exercita criação inicial de 27 mapblocks na área 3×3×3, `CONTENT_IGNORE` com flags limpas, idempotência de `initialEmerge(true)`, materialização de ar escrito num bloco temporário, carregamento prioritário do disco, ausência de serialização prematura, geração posterior, recuperação de um bloco completo e rejeição de arquivo corrompido.

## Limitações e cuidados

- Os mapblocks vazios sem geração são **temporários**, não persistidos como objetos `MapBlock` independentes; ainda não há a serialização nativa de um mapblock não gerado. Alterações de nós em blocos transitórios devem ser finalizadas pela geração antes de persistir a região.
- Não há suporte a todas as combinações de `MMVManip::blitBackAll`, objetos estáticos, timers internos, metadados de MapBlock e persistência transacional em um bloco não gerado.
- A semântica de `MapBlock::isGenerated()` é aproximada pela separação Lua `blank_blocks` versus `last_active` e `lbm_applied`.
- Continuam incompletos biomas, minérios, decorações, iluminação, líquidos e a execução integral do VoxeLibre original.
