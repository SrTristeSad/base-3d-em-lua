# Fase 101 — MapBlock::m_lighting_complete (Luanti 5.18.0)

## Referência nativa

O campo `m_lighting_complete` do [`src/mapblock.h` do Luanti 5.18.0](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.h) começa com o valor **`0xFFFF`** (`65535`). Os bits **0–5** registram a completude das seis direções do banco DAY; os bits **6–11**, do banco NIGHT. Os quatro bits superiores são preservados. `setLightingComplete(u16)` só altera o estado se os flags diferirem, sinalizando `MOD_STATE_WRITE_AT_UNLOAD`; o setter por banco/direção troca apenas o bit solicitado. O formato binário de mapblock nativo grava esse `u16` (versões de serialização ≥27) em [`src/mapblock.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.cpp).

## API Lua

```lua
local k='-1,0,0'  -- o MapBlock deve estar residente
local flags=map:get_mapblock_lighting_complete(k) -- 65535 por padrão
local complete=map:is_mapblock_lighting_complete(k,'day',0)
local changed=map:set_mapblock_lighting_complete_direction(k,'night',4,false)
-- Bancos: 'day' / 'night', ou 0 / 1.
-- Direções: números inteiros de 0 a 5.
local changed2=map:set_mapblock_lighting_complete(k,flags)
```

A tabela `map.lighting_complete` mantém apenas os valores que diferem de `65535`; consultar um bloco sem registro devolve o valor padrão. A modificação exige que exista um MapBlock residente; quando há transição de valor, `map.modified[k]` recebe `true`. Setter idempotente retorna `false` e não altera o estado de modificação. A representação mantém os bits 12–15 e rejeita argumentos incorretos.

**Importante:** os flags registrados aqui **não são um cálculo de luz**. Um valor completo significa somente que o indicador está marcado, e não que o motor Lua tenha executado a propagação nativa. A rotina atual `lighting.lua` permanece independente, sem inventar resultados físicos.

## Persistência e retrocompatibilidade

O formato textual `LUAENGINE 1` mantém seu cabeçalho, acrescentando opcionalmente o registro:

```text
Q -1 0 0 64511
```

São **coordenadas de mapblock**, não de voxel. O registro `Q` só é gravado para valores diferentes de `65535`, permitindo ler todos os saves anteriores sem migração. Seu valor deve ser inteiro entre 0 e 65535, as coordenadas devem ser canônicas e a duplicação é rejeitada. O serializador não pretende reproduzir o formato binário de MapBlock de Luanti.

`MapBlockStore` valida a identidade dos registros tanto nas imagens completas (`.map`) quanto nas imagens parciais (`.map.partial`). Carregamento de um bloco copia seus flags para o mapa residente, descarregamento limpa o estado em RAM, e `flush()` persiste as alterações por escrita atômica, conservando os metadados, os inventários e os timers anteriores. Uma imagem com flags de outro MapBlock é rejeitada **antes** de alterar o mapa em memória. O header global `world.map` não aceita dados locais `Q`.

## Teste automatizado

```sh
lua5.4 tests/lua_engine_mapblock_lighting_complete.lua
luajit tests/lua_engine_mapblock_lighting_complete.lua
```

Cobre valor inicial, 12 direções independentes, bits reservados, setter no-op, argumentos e coordenadas inválidos, serialização antiga, registros ausentes/duplicados/corrompidos, persistência de bloco gerado e de bloco `CONTENT_IGNORE` com metadados e timers, reinício, `unload`/`emerge`, preservação após transição para bloco completo e falha na escrita atômica.

## Limites

A implementação não calcula a iluminação nativa, não implementa a semântica completa `MOD_STATE_WRITE_AT_UNLOAD`/`MOD_REASON_SET_LIGHTING_COMPLETE`, nem cobre a serialização binária do Luanti 5.18.0 ou a sincronização entre servidores e clientes. Este é um avanço no **estado e na persistência do MapBlock**, não na compatibilidade integral do VoxeLibre.
