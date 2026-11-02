# Fase 96 — `MMVManip::blitBackAll` com halo parcialmente conhecido

## Fonte de comportamento

Luanti 5.18.0 (LGPL-2.1-or-later):
- [`src/map.cpp`, `MMVManip::blitBackAll` linhas 894–935](https://github.com/luanti-org/luanti/blob/5.18.0/src/map.cpp#L894-L935): percorre os mapblocks cobertos por dados, omite os já gerados por padrão, mas aceita mapblocks presentes e ainda não gerados.
- [`src/mapblock.cpp`, `MapBlock::copyFrom` linhas 224–234](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.cpp#L224-L234): usa o `VoxelManipulator::copyTo`.
- [`src/voxel.cpp`, `copyTo` linhas 231–246](https://github.com/luanti-org/luanti/blob/5.18.0/src/voxel.cpp#L231-L246): copia todo nó cujo conteúdo não é `CONTENT_IGNORE`, inclusive AIR com parâmetros.

## Desvio corrigido

A Fase 95 corrigiu a transferência do ar para o núcleo parcialmente conhecido. No halo, `MapgenBorder:blitBackHalo` ainda rejeitava todos os mapblocks com `map.revisions[block]` — **inclusive `Map.blank_blocks` ainda não gerados**, embora seu conteúdo pudesse ser copiado pelo original. Assim, o terreno sobregerado e o ar conhecido não chegavam ao bloco parcial.

## Implementação delimitada

1. `MapgenVoxelBuffer:validate_blank_halo` valida um snapshot de revisões para todos os mapblocks em branco cobertos antes de modificar o núcleo; o halo é revalidado antes de ser copiado. Blocos gerados continuam protegidos.
2. `MapgenBorder:blitBackHalo` copia voxels conhecidos de X/Y/Z diretamente para blocos **transitórios não gerados** (não para blocos gerados), sem copiar `CONTENT_IGNORE` nem perder `param1`/`param2`.
3. Como `MapBlockStore` ainda não tem serialização parcial nativa, os novos nós e nós conhecidos previamente no snapshot são também escritos nos arquivos `.border`, recuperáveis após reinício. A repetição do mesmo blit é idempotente; novas mutações externas continuam invalidadas pela revisão.
4. `MapBlockStore:flush` deixa de tratar revisões de `blank_blocks` como arquivos completos: grava os arquivos de borda e ignora os blocos transitórios ao serializar mapas completos. O bloco só é serializado depois de finalizado.
5. `MapgenBorder:publish` não publica antecipadamente nos mapblocks `blank_blocks`, deixando a transferência sob o preflight do `blitBackHalo`.

## Validação

```sh
lua5.4 tests/lua_engine_mmvm_blank_halo.lua
luajit tests/lua_engine_mmvm_blank_halo.lua
```

O teste exercita lados X/Z, coordenadas negativas, nós de snapshot com parâmetros, ar com parâmetros, `CONTENT_IGNORE`, idempotência, conflitos antes do núcleo e antes do halo, carve local na borda, persistência provisória, reinício e geração real do V7 ao lado de bloco não gerado.

## Lacunas remanescentes

Continua sendo um **subconjunto** do `blitBackAll`: não substitui `MapBlock` nativo, não oferece o modo geral `overwrite_generated=true`, nem a transferência íntegra de todas as flags e estados. Metadata, temporizadores e outros estados dos blocos transitórios não são persistidos no arquivo parcial `.border`; os testes não demonstram compatibilidade completa com VoxeLibre original. A finalização completa de iluminação, biomas, líquidos, minérios e decorações permanece pendente.
