# Fase 87 — transferência vertical de terreno sobregerado entre chunks

## Código-fonte fixo de referência

- [Luanti 5.18 `src/mapgen/mapgen_v7.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapgen/mapgen_v7.cpp): `MapgenV7::generateTerrain` constrói também as camadas `node_min.Y - 1` e `node_max.Y + 1` e respeita células que não sejam `CONTENT_IGNORE`.
- [`src/servermap.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/servermap.cpp): `ServerMap::finishBlockMake` usa `MMVManip::blitBackAll` e gerencia alterações nos blocos de borda.
- [`src/voxel.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/voxel.cpp): cópia de nós sem substituir `CONTENT_IGNORE`.

A implementação existente do motor Lua já calculava essas camadas, mas as descartava no fechamento do buffer. Esta fase fornece **uma transferência vertical persistível**, não uma implementação integral de `MMVManip::blitBackAll`.

## Implementação

O módulo `lua-engine/core/mapgen_border.lua` mantém voxels **provisórios** de Y−1 e Y+1 organizados por mapblock de destino, separado dos nós completos do mundo. São guardados tanto `air` quanto nomes reais de materiais e parâmetros `param1`/`param2`.

O fluxo de `MapgenV7:generateChunk` é:

1. Verificar se o núcleo do chunk está totalmente ausente na memória/disco. Em chunks parcialmente existentes, optar pela geração em buffer de apenas um mapblock.
2. Antes da geração, importar as camadas provisórias dos mapblocks do núcleo para o `MapgenVoxelBuffer`. O teste original `CONTENT_IGNORE` faz a geração **respeitar os voxels importados**.
3. Gerar terreno, cavernas e demais estágios atualmente portados, com o restante do buffer vazio.
4. Transferir o núcleo completo para o mapa e marcar os mapblocks como gerados pelo `emerge_area`.
5. Descartar entradas provisórias dos mapblocks que acabaram de ser gerados e publicar novas camadas Y−1 e Y+1 para os vizinhos verticais ainda ausentes.

O `MapBlockStore` escreve os dados provisórios em arquivos separados `vertical-borders/<x>_<y>_<z>.border` no mesmo prefixo do mundo. O formato `LUAENGINE BORDER 1` é textual, validado e **não usa `load`/avaliação de código**. Os arquivos são gravados atomicamente em `flush` ou antes de `unload`. Um bloco vizinho não passa a ser considerado carregado somente porque recebeu terreno provisório.

## Testes

```sh
lua5.4 tests/lua_engine_vertical_border.lua
luajit tests/lua_engine_vertical_border.lua
```

A suíte cobre: publicação de duas camadas 32×32; `get_node` devolvendo `ignore` no bloco de destino ainda não gerado; marcação e recuperação por arquivo após reinício; prioridade dos voxels existentes em `terrain_writable`; descarte dos dados provisórios após completar o bloco; comportamento em chunks mistos, `EMERGE_ERRORED` para dados externos inválidos e recuperação após falha de escrita do armazenamento.

## Limites assumidos

- O Luanti original compartilha o buffer denso de **todos os eixos** em `MMVManip`. Este porte cobre somente **as duas camadas verticais** que o `MapgenV7::generateTerrain` já sobregera. Não há `blitBackAll` genérico, nem preservação das bordas X/Z por outros algoritmos.
- Se a geração do chunk é interrompida entre a escrita dos mapblocks e das sobreposições, a próxima recuperação pode precisar refazer regiões incompletas. O formato de armazenamento ainda não é transacional.
- As células pendentes são escritas em arquivos sidecar distintos. Isso preserva a semântica de carregamento de mapblocks e permite recuperar informação de borda, mas **não replica o formato nativo dos arquivos de mundo Luanti**.
- Chunks parcialmente existentes ainda utilizam processamento por mapblock e podem diferir da geração integral do Luanti; os biomas, minérios, decorações, iluminação, líquidos e boa parte do `MMVManip` continuam incompletos.
- A compatibilidade total com VoxeLibre **não** é comprovada pelos testes desta fase.
