# Luanti 5.18 — carregamento explícito e emergência de mapblocks (Fase 79)

Referência de comportamento: `luanti-org/luanti` tag `5.18.0`, `doc/lua_api.md`, especialmente `core.load_area`, `core.emerge_area`, `core.get_node`, `core.get_node_or_nil`, `core.get_node_raw` e as constantes de `builtin/game/constants.lua`.

Este código complementa, **sem substituir**, o streaming em `core/mapblockstore.lua`.

## API exposta aos mods originais

- `core.load_area(pos1[, pos2])`: carrega da memória/disco os mapblocks disponíveis **sincronamente**, sem gerar novas regiões e sem ativar LBMs por si só. Não retorna valores, assim como a função C++ original.
- `core.emerge_area(pos1, pos2[, callback[, param]])`: insere em fila os mapblocks, processados nas chamadas seguintes de `runtime:step`; não executa callbacks na mesma chamada que solicita emergência. Cada callback recebe `blockpos, action, calls_remaining, param`.
- Constantes originais: `EMERGE_CANCELLED=0`, `EMERGE_ERRORED=1`, `EMERGE_FROM_MEMORY=2`, `EMERGE_FROM_DISK=3`, `EMERGE_GENERATED=4`.
- `core.get_loaded_blocks()`, `core.get_active_blocks()` e `core.compare_block_status(pos, condition)` usam o estado real residente/ativo. `condition` suporta `unknown`, `emerging`, `loaded`, `active`, comparados como níveis mínimos de prontidão (`status >= condition`), conforme `ServerEnvironment::BlockStatus`.
- Em mundos com armazenamento segmentado, `core.get_node(pos)` retorna `ignore` em região não carregada, `get_node_or_nil(pos)` retorna `nil` e `get_node_raw(x,y,z)` retorna `CONTENT_IGNORE, 0, 0, false`. Em blocos residentes, as posições `air` continuam representadas por `air`, e não por `ignore`. Os testes antigos sem streaming conservam a semântica protótipo de mapa esparso.

## Geração de blocos ausentes

A emergência de um bloco não encontrado no disco **não pode criar terreno parecido com Minecraft ou VoxeLibre por suposição**. Só retorna `EMERGE_GENERATED` quando um gerador explícito do host existir e retornar `true`:

```lua
runtime:setMapBlockGenerator(function(runtime, minp, maxp)
  -- Invocar o gerador efetivo do mundo, quando estiver implementado.
  -- Este exemplo NÃO gera terreno.
  return false
end)
```

Após geração confirmada, o runtime marca o timestamp de geração, assinala os LBMs anteriores como não aplicáveis aos novos blocos e chama os callbacks `register_on_generated`. A geração real do Luanti/VoxeLibre ainda precisa ser portada; essa interface permite conectá-la sem alteração de mods.

A fila executa no máximo `opts.emerge_blocks_per_step` mapblocks por tick (padrão 8, intervalo 1–4096); solicitações acima de 4096 blocos são recusadas para impedir exploração de recursos. Regiões fora dos limites do mapa não são geradas.

## Limites conhecidos

Esta é uma fila cooperativa no loop do servidor Lua, **não** a implementação multithread do EmergeManager de Luanti; o disco ainda usa arquivos individualmente atômicos via adaptador do host, e não MapDatabase SQLite/LevelDB. O motor não implementa ainda geração original do VoxeLibre, streaming de entidades estáticas, gerenciamento completo de mapgen, forceload persistente ou rede multijogador.

As chamadas de `get_node` sem streaming permanecem compatíveis com os testes legados, mas não representam o comportamento completo de um ServerMap nativo. A fila e as constantes foram testadas com Lua 5.4 e LuaJIT; não reivindicamos compatibilidade de jogo completo.

## Regressão

```sh
lua5.4 tests/lua_engine_emerge_area.lua
luajit tests/lua_engine_emerge_area.lua
```
