# Fase 89 — getCoveredBlocks e blit seguro dos voxels de borda

## Referência fixa do Luanti 5.18

- [`src/map.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/map.cpp), `MMVManip::initialEmerge` (a partir da linha 805), `MMVManip::getCoveredBlocks` (858) e `MMVManip::blitBackAll` (894).
- [`src/voxel.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/voxel.cpp), `VoxelManipulator::copyTo` (231).
- [`src/mapblock.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.cpp), `MapBlock::copyFrom` (224).
- [`src/servermap.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/servermap.cpp), `ServerMap::finishBlockMake` (275).

**Regra original:** `getCoveredBlocks` seleciona blocos com qualquer voxel marcado como contendo dados, incluindo ar conhecido. `blitBackAll` escreve os blocos selecionados no mapa, **mas por padrão ignora os blocos com `isGenerated()==true`** quando `overwrite_generated=false`.

## Código implementado

- `MapgenVoxelBuffer:getCoveredBlocks()` calcula os blocos com pelo menos um voxel conhecido. Considera entradas explícitas da sobreposição, ar conhecido comprimido em colunas e mapblocks residentes (inclusive blocos completamente vazios). Não percorre todos os voxels de ar individualmente; uma coluna representa um intervalo de blocos.
- `MapgenBorder:blitBackHalo(buffer)` copia dados **novos ou modificados** do halo X/Y/Z para arquivos provisórios, respeitando a presença de dados e preservando blocos que já possuam revisões, carregamento ou marcadores LBM. Diferentemente do método anterior, não exige que o voxel já estivesse presente em um sidecar para copiá-lo.
- O `MapgenV7:generateChunk` e seu fallback isolado passam a usar a transferência genérica do halo. A transferência vertical anterior continua existindo, sem alterar a semântica dos callbacks de geração de mapblock completo.
- Os dados do halo seguem em sidecars textuais validados, sem ser publicados como mapblocks gerados. O `MapBlockStore` mantém seu formato anterior para blocos completos.

## Testes

```sh
lua5.4 tests/lua_engine_mmvm_blit.lua
luajit tests/lua_engine_mmvm_blit.lua
```

Testa cobertura de ar conhecido, bloco totalmente vazio já carregado, voxels novos no halo X, preservação de `CONTENT_IGNORE`, não sobrescrita de mapblocks gerados/editados, idempotência, serialização dos sidecars, reinicialização e geração do chunk vizinho. Para chunks originais de 5×5×5, a cobertura esperada das colunas Y±1 é de 125 blocos internos e 50 blocos verticais parciais.

## Integração com a geração de cavernas em blocos residentes

A `main` também contém um estágio experimental separado de escavação em mapblocks residentes, com validação contra alterações simultâneas. `blitBackHalo` **não** substitui esse caminho nem reescreve esses blocos novamente: sua responsabilidade é exclusivamente armazenar os dados de bordas **ainda não geradas**. A cobertura de blocos conhecidos serve à seleção, não concede autorização para sobrescrever construções existentes.

## Diferenças ainda existentes para o C++ original

Esta é uma **transferência do halo em staging**, não um `MMVManip::blitBackAll` integral. O original pode criar e modificar mapblocks parcialmente carregados diretamente na estrutura interna do mapa. A implementação Lua usa arquivos provisórios para impedir que mapblocks com dados parciais sejam confundidos com mapblocks completos. Além disso:

- A geração de novo terreno nas bordas X/Z ainda não foi portado; o halo só transmite dados que já se tornaram conhecidos por outros passes.
- `overwrite_generated=true` ainda não está implementado (nem deve ser usado para reescrever construções de jogador sem autorização).
- A proteção conservadora de revisões locais não é um clone completo do bit `MapBlock::m_generated` de C++.
- Sistemas de biomas, minérios, decorações, iluminação, líquidos e vários estágios nativos de mapgen ainda faltam.
- A execução integral do VoxeLibre original segue **não verificada**.

O objetivo permanece o porte fiel 1:1 do motor Luanti, não um motor Minecraft simplificado.
