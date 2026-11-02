# Fase 102 — Flag persistida MapBlock::is_underground

## Referências Luanti 5.18.0

A implementação original [`src/mapblock.h`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.h) declara `bool is_underground = false`, `getIsUnderground()` e `setIsUnderground(bool)`. Diferentemente de `setLightingComplete`, **o setter sempre** invoca `raiseModified(MOD_STATE_WRITE_NEEDED, MOD_REASON_SET_IS_UNDERGROUND)`, mesmo quando o booleano não mudou. Em [`src/mapblock.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.cpp), o bit 0 do primeiro byte de flags serializado representa `is_underground`.

No Luanti, este campo influencia a hipótese de luz solar quando falta um bloco acima do atual. O motor Lua **ainda não executa a propagação nativa de luz**; nesta fase, o valor é representado e persistido, sem alterar a iluminação visível.

## API e modelo de dados

```lua
local block='-1,0,0' -- deve estar residente
local current=map:get_mapblock_is_underground(block) -- false por padrão
local changed=map:set_mapblock_is_underground(block,true)
```

- `map.underground` armazena somente valores `true`. A ausência de entrada equivale a `false`.
- O setter exige um MapBlock residente, aceita apenas booleanos e devolve `true` se houve mudança de valor. **Toda chamada válida** marca `map.modified[block]=true`, inclusive se o valor era idêntico, como no C++.
- O campo é independente das flags de `lighting_complete`, dos metadados, do inventário e dos temporizadores. Não modifica `MapNode` nem marca um bloco parcial como gerado.

## Persistência compatível com LUAENGINE 1

Um único registro opcional representa o valor não padrão:

```text
U -1 0 0 1
```

As coordenadas são do **mapblock**, não dos voxels. O decoder rejeita coordenadas inválidas/não canônicas, valores diferentes do literal `1`, duplicatas e registros pertencentes a outro bloco. O formato antigo continua legível: arquivos sem `U` restauram `false`.

O `MapBlockStore` transmite o estado em snapshots completos (`.map`) e parciais (`.map.partial`); `unload` o descarta da RAM, e `emerge`/`load_partial` o recuperam. O header global `world.map` rejeita campos específicos de mapblocks. O `flush` considera também `map.modified` para permitir que um valor **true → false** ou `lighting_complete` não padrão → padrão substitua um arquivo parcial antigo, mesmo que nenhum voxel tenha mudado; isso evita a ressurreição de flags após o reinício.

## Regressão

```sh
lua5.4 tests/lua_engine_mapblock_underground.lua
luajit tests/lua_engine_mapblock_underground.lua
```

Cobre valor padrão, idempotência/dirty nativo, validação de entradas, isolamento dos flags de luz, saves antigos, arquivos malformados, estado parcial com `CONTENT_IGNORE`, reinício, `unload`/`emerge`, corrupção entre blocos, persistência de flags removidas, falha de escrita atômica e finalização de um MapBlock parcial.

## Limitações

Este estado ainda não reproduz todos os níveis/motivos de `MapBlock::raiseModified`, a propagação do sol, a serialização binária nativa ou a sincronização de clientes. Trata-se de uma etapa para paridade de estado e segurança da persistência, não de uma certificação da execução integral do VoxeLibre.
