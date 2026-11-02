# Streaming segmentado de mapblocks — Fase 78

A camada de armazenamento em `core/mapblockstore.lua` é o primeiro caminho **real e opt-in** de carga/descarga 16×16×16 do motor Luanti em Lua. É separada da exportação completa antiga `Storage.save` e não usa serialização de código.

## Ativação no host

```lua
local store=runtime:attachMapBlockStore(fs,'myworld')
-- fs.read(path) -> string | nil,'not found'
-- fs.write_atomic(path,contents) -> true | nil,error
runtime:connectPlayer(player_with_get_pos)
runtime:step(dt)
-- before application exit:
store:flush()
```

O adaptador é responsável por caminhos relativos, criação dos diretórios necessários e **substituição atômica** de arquivos. O engine rejeita adaptadores sem `write_atomic`. A demo LÖVR existente continua com o formato de save completo; não se deve substituí-la por esta interface sem implementar primeiro o adaptador atômico compatível com sua plataforma.

## Dados e invariantes

- `myworld/world.map` armazena o relógio persistente e os marcadores globais de chunks gerados.
- `myworld/blocks/<bx>_<by>_<bz>.map` guarda apenas os dados de um bloco, via formato `LUAENGINE 1`: nós, `param1/param2`, metadados, inventários, timers, marcadores LBMs e `last_active`.
- Quando um bloco deixa a área ativa, o gerenciador salva os dados globais e o bloco; **somente após gravação atômica bem-sucedida** descarta o bloco da RAM e atualiza o índice de colisão.
- Ao se aproximar novamente, o gerenciador lê, valida e insere o bloco antes de disparar LBMs e recuperar o tempo dos timers.
- Imagens inválidas, fora dos limites ou contendo nós de outros blocos são recusadas antes da mutação do mapa. Falhas de gravação não descartam dados vivos.
- `store:flush()` grava os blocos residentes sem descarregá-los; `store:invalidate(key)` limpa uma ausência previamente memorizada se outro processo tiver criado um bloco. `store:emerge(key)` e `store:unload(key)` também permitem gerenciamento manual.
- `Storage.encode(runtime.map)` em sessões segmentadas falha explicitamente, impedindo que uma exportação parcial sobrescreva acidentalmente um mundo completo.

## Limitações verificáveis

A implementação ainda é **uma etapa da reconstrução**, não o sistema de ServerMap completo. Não há banco de dados SQLite/LevelDB original, geração automática de mapblocks ausentes, objetos estáticos paginados, forceload, transações atômicas entre diversos arquivos, cache com orçamento de memória, servidor de rede nem sinalização de regiões ausentes em `get_node`. O arquivo `world.map` e os arquivos individuais são gravados separadamente; somente cada arquivo possui atomicidade garantida pelo host. A escrita do estado global **não** é um commit transacional de todo o mundo.

A ativação automática só opera para jogadores conectados com posição real, como na etapa anterior, e mantém o `active_block_range` configurado. O motor não é ainda equivalente 1:1 ao Luanti 5.18 e o VoxeLibre original não está inteiramente executável.

## Regressão

```sh
lua5.4 tests/lua_engine_mapblock_streaming.lua
luajit tests/lua_engine_mapblock_streaming.lua
```
