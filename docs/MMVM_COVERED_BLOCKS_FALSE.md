# Fase 99 — MMVManip::getCoveredBlocks com NO_DATA explícito

## Referência original

Em Luanti 5.18.0, [`src/map.cpp`, `MMVManip::getCoveredBlocks()` linhas 858–892](https://github.com/luanti-org/luanti/blob/5.18.0/src/map.cpp#L858-L892), a função enumera **todos** os mapblocks da `VoxelArea` (que deve estar alinhada a 16³) e devolve uma tabela booleana. `true` significa que **algum voxel** não possui `VOXELFLAG_NO_DATA`; `false` significa que todos os voxels do bloco são desconhecidos. `MMVManip::initialEmerge` (linhas 805–855) reimporta blocos marcados como `false` e pula apenas aqueles marcados como `true`. `blitBackAll` (linhas 894–935) copia somente `true`.

A representação Lua anterior incluía apenas as chaves dos blocos cobertos (`true`) e omitia as chaves `false`. Para leituras por índice, ambos são falsey, mas iterações com `pairs()` não eram equivalentes; uma mudança direta para a tabela completa sem corrigir consumidores poderia disparar uma validação incorreta do halo.

## Implementação

- Após `initialEmerge`, `Buffer:getCoveredBlocks()` devolve uma entrada por mapblock em toda a extensão alinhada: `false` inicialmente, `true` para nós sobrepostos, colunas de AIR conhecido e mapblocks importados. MapBlocks parciais carregados podem ter `CONTENT_IGNORE` em todas as posições e ainda assim são `true`: `MapBlock::copyTo` limpa `NO_DATA` mesmo quando o conteúdo é `IGNORE`.
- Antes de `initialEmerge`, a reserva geométrica Lua continua com a **cobertura esparsa anterior**: pode identificar blocos já existentes no mapa e overlays/colunas previamente preparados, mas não enumera todos os blocos desconhecidos como `false`. A tabela integral é garantida apenas após o snapshot.
- `validate_blank_halo` ignora explicitamente as entradas `false`, evitando tratar blocos não importados como uma alteração concorrente. `blitBackAll` e `blitBackHalo` já consideravam os valores booleanos.
- `Buffer:get_flags` agora mantém o bit `NO_DATA` sem somá-lo duas vezes quando o flag já está presente. A soma anterior poderia convertê-lo incorretamente em `CHECKED1`.

## Regressões

```sh
lua5.4 tests/lua_engine_mmvm_covered_false.lua
luajit tests/lua_engine_mmvm_covered_false.lua
```

O novo teste inclui um volume 3×3×3, snapshot de bloco completo, bloco `CONTENT_IGNORE` carregado, blocos ausentes com `false`, reemergência após atualização do mapa ao vivo, expansão para coordenadas negativas, nó staged que muda a cobertura para `true`, preflight do halo, blit sem criar blocos desconhecidos, coluna AIR e flags `NO_DATA` idempotentes.

## Escopo e limites

Esta etapa corrige a **semântica da tabela de cobertura**; não adiciona um sistema nativo completo de flags por voxel, iluminação/cache ou os MapBlocks binários originais. O fluxo de geração V7 continua com a proteção de blocos gerados. `getCoveredBlocks()` ainda usa uma representação esparsa e colunas AIR comprimidas, não uma cópia 1:1 dos arrays em C++; o comportamento booleano exposto após a emergência é equivalente para os casos cobertos pelo teste. Não é uma certificação de compatibilidade integral com VoxeLibre.
