# Fase 103 — Estados de modificação e motivos de MapBlock (Luanti 5.18.0)

## Fonte nativa

Em [`src/modifiedstate.h`](https://github.com/luanti-org/luanti/blob/5.18.0/src/modifiedstate.h), `MOD_STATE_CLEAN = 0`, `MOD_STATE_WRITE_AT_UNLOAD = 2` e `MOD_STATE_WRITE_NEEDED = 4`. Em [`src/mapblock.h`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.h), `MapBlock::raiseModified(state,reason)`:

- se a nova gravidade for **maior**, substitui o estado e os motivos;
- se a gravidade for **igual**, acumula os motivos por OR de bits;
- se a gravidade for **menor**, não muda o estado nem os motivos;
- ao receber `WRITE_NEEDED`, invalida a lista interna de contents do MapBlock (ainda sem equivalente completo no adaptador Lua).

`resetModified()` zera gravidade e motivos; o serializador nativo não grava esses campos de diagnóstico como parte do conteúdo de um MapBlock.

## Interface Lua

```lua
local block='0,0,0'
map:get_mapblock_modified_state(block)         -- 0, 2 ou 4
map:get_mapblock_modified_reason(block)        -- máscara de bits
map:get_mapblock_modified_reason_string(block) -- texto compatível com os nomes C++
map:raise_mapblock_modified(block,
  map.MOD_STATE_WRITE_NEEDED, map.MOD_REASON_VMANIP)
map:reset_mapblock_modified(block)
```

A tabela `map.modified` continua como **indicador booleano de alterações pendentes**, preservando os consumidores anteriores. As novas tabelas `modified_states` e `modified_reasons` são mantidas somente na memória, sem modificar o formato `LUAENGINE 1`. São disponibilizadas as constantes nativas necessárias aos caminhos implementados: `SET_IS_UNDERGROUND` (bit 1), `SET_LIGHTING_COMPLETE` (bit 2), `SET_NODE` (bit 4), `EXPIRE_IS_AIR` (bit 16), `VMANIP` (bit 17) e outras.

A API usa aritmética inteira compatível com Lua 5.4 e LuaJIT, sem exigir uma biblioteca `bit32`. As consultas rejeitam chaves inválidas, e `raise_mapblock_modified` rejeita severidade fora dos três valores suportados e motivos fora dos 19 bits definidos pelo Luanti 5.18.

## Integrado aos caminhos existentes

| Origem | Severidade | Motivo |
|---|---:|---|
| `Map:set_node` quando há mudança real de célula | 4 | `SET_NODE` |
| `Map:set_mapblock_is_underground`, inclusive se o valor for idêntico | 4 | `SET_IS_UNDERGROUND` |
| `Map:set_mapblock_lighting_complete`, somente ao mudar | 2 | `SET_LIGHTING_COMPLETE` |
| `Buffer:blitBackAll`, inclusive quando o conteúdo copiado é idêntico | 4 | `VMANIP` |

O caminho `blitBackAll` conserva motivos preexistentes e não produz motivos `SET_NODE` espúrios da cópia interna: o C++ `MapBlock::copyFrom` trabalha diretamente com os dados, sem chamar `MapBlock::setNode` para cada posição.

`MapBlockStore:flush` só redefine o estado de cada bloco **depois** que a escrita atômica desse bloco termina com sucesso. Uma falha mantém o estado pendente. `MapBlockStore:unload` elimina o estado descartado da RAM, e `emerge`/`load_partial` restauram blocos limpos: importação não é edição nova.

## Regressão automatizada

```sh
lua5.4 tests/lua_engine_mapblock_modified_state.lua
luajit tests/lua_engine_mapblock_modified_state.lua
```

A regressão cobre gravidade e composição dos motivos, getters, reset, máscaras de bits, strings de diagnóstico, flags Q/U das fases 101–102, blit idêntico e alterado, falha de escrita, escrita parcial e completa e reload limpo.

## Limites

Esta fase **não** implementa o mecanismo nativo completo `m_disk_timestamp`, as razões dos objetos estáticos, a lista `contents` ou os estados reservados 1/3/5. No motor Lua, `set_node` só produz `SET_NODE` quando há mudança observável: chamar `set_node` com um valor byte-idêntico não altera o marcador de modificação, como já ocorria nas fases anteriores. Esta escolha mantém os invariantes do gerador esparso e evita registrar falsas escritas em blocos não residentes; não equivale a chamar diretamente `MapBlock::setNode` C++ em todos os casos. A sinalização de mudança de metadata e timers ainda não usa todas as razões nativas. `map.modified` permanece um booleano de persistência do adaptador, não um substituto dos objetos C++.
