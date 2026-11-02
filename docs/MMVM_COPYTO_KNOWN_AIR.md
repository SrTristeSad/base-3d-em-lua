# Fase 95 — `VoxelManipulator::copyTo`: AIR conhecido em MapBlock parcialmente gerado

## Referência exata

Luanti 5.18.0: [`src/voxel.cpp` linhas 231–246](https://github.com/luanti-org/luanti/blob/5.18.0/src/voxel.cpp#L231-L246) e [`src/mapblock.cpp` linhas 224–234](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.cpp#L224-L234). `VoxelManipulator::copyTo` copia todo `MapNode` cujo conteúdo não seja `CONTENT_IGNORE` ao destino, inclusive `CONTENT_AIR`, `param1` e `param2`. A origem desta adaptação é LGPL-2.1-or-later.

## Desvio da Fase 94

`MapgenVoxelBuffer` comprimía o ar das colunas V7 somente em memória. Ao realizar `commit_core` em um `Map.blank_blocks` ainda não gerado, copiava nós explicitamente diferentes de ar, mas deixava as células conhecidas de ar como `CONTENT_IGNORE` no bloco de destino. Além disso, o snapshot de bloco em branco prevalecia incorretamente sobre o ar gerado ao consultar `get_node`. `Map:set_node` descartava os parâmetros de nós AIR após o bloco ser completado.

## Alterações

- A consulta ao buffer dá prioridade a nós explicitamente importados, depois ao ar gerado na coluna; regiões que nunca foram escritas continuam `CONTENT_IGNORE`.
- A finalização de um núcleo **ainda em branco** materializa apenas o ar gerado nas colunas, sem modificar nós anteriormente conhecidos nem posições que permanecem `CONTENT_IGNORE`. Blocos novos/gerados continuam usando ar implícito e não pagam esse custo.
- O `commit_core` transfere também AIR explícito com parâmetros, como em `copyTo`.
- `Map` comprime apenas AIR(0,0); AIR com `param1` ou `param2` diferente de zero é mantido no mapblock, serializado e recarregado. A alteração incrementa a revisão do mapblock para preservar os mecanismos de detecção de conflito já existentes.
- O preflight do `commit_core` continua ocorrendo **antes** de qualquer cópia de ar ou nó.

## Regressão

```sh
lua5.4 tests/lua_engine_mmvm_copyto_air.lua
luajit tests/lua_engine_mmvm_copyto_air.lua
```

O teste cobre coordenadas negativas, snapshot com parâmetros, `CONTENT_IGNORE` não copiado, ar gerado, ar com parâmetros, finalização, persistência, reinício e conflito concorrente. Também mantém os testes da Fase 94 no CI.

## Limites

Isto **não** implementa o `MMVManip::blitBackAll` integral, nem a estrutura interna nativa de `MapBlock`. A materialização das colunas em mapblocks em branco continua delimitada ao caminho V7 e seu núcleo. A representação comprimida de nós AIR(0,0) em blocos completos não reproduz todas as particularidades de armazenamento e luz do C++ original. A execução completa do VoxeLibre original não está comprovada.
