# Fase 104 — Timestamp nativo de MapBlock e referência de disco

## Referência Luanti 5.18.0

Em [`src/mapblock.h`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapblock.h), o campo `m_timestamp` é um inteiro sem sinal de 32 bits, com sentinela `BLOCK_TIMESTAMP_UNDEFINED = 0xffffffff`. O método `setTimestamp(time)` **sempre** chama `raiseModified(MOD_STATE_WRITE_AT_UNLOAD, MOD_REASON_SET_TIMESTAMP)`, inclusive quando o número permanece igual. `setTimestampNoChangedFlag(time)` muda apenas o valor, sem marcar modificação.

O campo `m_disk_timestamp` também começa indefinido; o método `getDiskTimestamp()` é explicitamente **deprecated** no upstream. `MapBlock::raiseModified` copia `m_timestamp` para `m_disk_timestamp` quando a severidade **aumenta** para pelo menos `WRITE_AT_UNLOAD`. Essa regra não é uma garantia de que o arquivo já foi gravado. Após a importação de um MapBlock salvo, os dois valores são inicializados com o timestamp persistido.

O código Lua já possui `last_active[block]`, um relógio **fracionário** usado para temporizadores e LBMs. Esta fase não altera esse relógio: ele continua distinto do timestamp inteiro de MapBlock.

## Interface Lua

```lua
local block='-1,0,0' -- precisa ser residente
local undefined=map.BLOCK_TIMESTAMP_UNDEFINED -- 4294967295
map:get_mapblock_timestamp(block)
map:get_mapblock_disk_timestamp(block)
map:set_mapblock_timestamp_no_changed_flag(block,123)
map:set_mapblock_timestamp(block,124)
```

Os setters aceitam apenas números inteiros de `0` a `4294967295`. Atribuir a sentinela restaura o estado indefinido. O setter sem marcação não modifica `map.modified` nem os motivos. O setter normal solicita `WRITE_AT_UNLOAD` e `SET_TIMESTAMP`; quando o estado anterior é `WRITE_NEEDED`, vale a regra de prioridade do `raiseModified` da Fase 103.

As tabelas `block_timestamps` e `block_disk_timestamps` usam entradas esparsas: `nil` representa a sentinela. Ambas são limpas ao descartar o bloco residente. `block_disk_timestamps` é apenas estado de runtime; durante gravação atômica bem-sucedida de um bloco, o adaptador atualiza seu valor para refletir a imagem escrita, preservando o indicador em caso de falha.

## Persistência e retrocompatibilidade

O formato textual `LUAENGINE 1` mantém o cabeçalho anterior e admite o novo registro opcional:

```text
P -1 0 0 4000000000
```

As coordenadas são de **MapBlock**. `P` somente é emitido para timestamps concretos `0..4294967294`. A ausência de `P` significa timestamp indefinido, mesmo em saves antigos. A leitura rejeita duplicatas, coordenadas não canônicas (inclusive `-0` no LuaJIT), números fracionários, negativos, fora do intervalo, valores redundantes da sentinela e registros de outros blocos.

Os campos e registros possuem funções distintas:

| Registro/campo | Papel |
|---|---|
| `B x y z tempo` / `last_active` | Instante fracionário de atividade de LBMs/timers |
| `P x y z u32` / `block_timestamps` | Timestamp persistido do MapBlock |
| `block_disk_timestamps` | Espelho transitório do timestamp associado ao ciclo de modificação/disco, não serializado |

O `MapBlockStore` valida `P` nos arquivos completos e parciais, proíbe esse campo no header global `world.map`, restaura os timestamps após importação e os limpa em `unload`. Uma escrita atômica falha não limpa a alteração pendente nem sobrescreve o indicador de disco. Os formatos anteriores continuam legíveis.

## Teste

```sh
lua5.4 tests/lua_engine_mapblock_timestamps.lua
luajit tests/lua_engine_mapblock_timestamps.lua
```

A regressão cobre sentinela, limites u32, semântica de `setTimestamp` e `setTimestampNoChangedFlag`, prioridade dos motivos, captura de `m_disk_timestamp`, independência de `last_active`, formato antigo, imagens completas e parciais, corrupção, atomicidade de escrita, reinício e `unload`/`emerge`.

## Limitações

Não há relógio de disco nativo nem serialização binária de MapBlock; `P` é uma extensão compatível do formato textual Lua. O campo `m_disk_timestamp` é marcado como obsoleto no Luanti original, por isso não deve servir como prova de durabilidade. A execução Lua ainda não replica todos os eventos do servidor que chamam `setTimestamp` nativamente; o relógio de atividade `last_active` permanece com sua semântica preexistente para evitar alterações de gameplay não solicitadas.
