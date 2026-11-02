# Fase 97 — persistência do estado de MapBlocks não gerados

## Referência e problema

Luanti 5.18.0: [`src/servermap.cpp` (`ServerMap::initBlockMake`, `finishBlockMake`)](https://github.com/luanti-org/luanti/blob/5.18.0/src/servermap.cpp), [`src/mapblock.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.cpp) e [`src/map.cpp` (`MMVManip::blitBackAll`)](https://github.com/luanti-org/luanti/blob/5.18.0/src/map.cpp). O conteúdo do MapBlock pode ser parcialmente conhecido sem `isGenerated=true`, incluindo nós, metadados e temporizadores. Referência de código LGPL-2.1-or-later.

A Fase 96 preservou os nós transferidos do halo com `.border`, mas `MapBlockStore:flush` ignorava completamente os estados não nodais de `blank_blocks`. Metadados de nós, inventários e temporizadores em blocos transitórios eram perdidos ao reiniciar antes da finalização.

## Implementação

- `MapBlockStore:partial_path(k)` guarda uma imagem `.map.partial` separada dos mapblocks completos. Usa o serializador seguro `LUAENGINE 1`; **não** cria `last_active` ou marcador gerado.
- `Storage.decode(data,{partial_block=k})` inicializa a representação como `CONTENT_IGNORE`, preservando até mesmo o `AIR(0,0)` explicitamente conhecido em um mapblock parcialmente preenchido. Chamadas antigas de `Storage.decode(data)` permanecem intactas.
- `MapBlockStore:load_partial` lê e valida por completo a imagem antes de modificar o mapa: coordenadas pertencentes ao próprio mapblock, ausência de timestamps de bloco completo, ausência de estados LBM/chunk e timestamp do mundo não futuro. Usa os mecanismos existentes de restauração de inventários e temporizadores.
- `load_or_create_blank` escolhe **bloco completo em disco primeiro**, depois imagem parcial, depois criação de um novo bloco `CONTENT_IGNORE`. Imagens parciais desatualizadas não sobrescrevem mapblocks completos.
- `MapblockStore:flush` persiste estados parciais com nós, metadados e temporizadores, mas continua sem classificá-los como mapblocks completos. O retorno de quantidade mantém a contagem somente de imagens completas.
- `MapgenV7:generateChunk` recupera imagens parciais do núcleo e dos mapblocks vizinhos **antes de** `initialEmerge(false)`. A operação `initialEmerge(false)` em si continua sem fazer I/O.

## Testes

```sh
lua5.4 tests/lua_engine_mmvm_partial_state.lua
luajit tests/lua_engine_mmvm_partial_state.lua
```

Casos: coordenadas negativas, `AIR(0,0)` versus `CONTENT_IGNORE`, `param1`/`param2`, metadados, inventário, temporizadores e tempo decorrido, persistência antes da geração, imagem completa prioritária, corrupção/dados de outro mapblock, falha de gravação, retomada da geração V7 no núcleo e recuperação de estado em vizinhos.

## Limitações

Este é um **adaptador de persistência do motor Lua**, não o formato binário nativo de MapBlock do Luanti. Arquivos `.map.partial` podem permanecer após um bloco ser finalizado, mas arquivos completos sempre têm precedência; a interface atual de armazenamento não oferece exclusão de arquivos. A serialização e a atualização de estados não nodais não constituem ainda um porte integral de `MapBlock` ou do servidor Luanti. Liquidez, iluminação, biomas, minérios, decorações e execução integral do VoxeLibre original continuam pendentes.
