# Fase 11 — Baldes de água e lava

## Implementado

- Itens: **325 balde vazio**, **326 balde de água**, **327 balde de lava**.
  Cada balde ocupa exatamente um slot, sem empilhamento.
- Receita do balde: três lingotes de ferro em V, na bancada 3×3.
- No modo sobrevivência, clique direito com balde vazio recolhe
  exclusivamente uma **fonte** de água ou lava. Correntes e
  líquidos atrás de blocos não são coletados.
- Com balde cheio, o clique direito despeja uma fonte em espaço
  livre adjacente a um bloco, sem colocar líquido dentro do corpo
  do jogador. Balde cheio volta a vazio após o uso.
- No criativo Beta, baldes de água/lava da nova página da barra
  colocam fontes ilimitadas. Não consomem inventário.
- A fonte criada usa a simulação da Fase 9, acionando propagação,
  iluminação, malha e consequências para o jogador da Fase 10.
- Registros existentes `SLOT` e `BLOCK` preservam itens e
  líquidos; nenhuma migração nem alteração de saves é necessária.
- O uso de balde tem prioridade no clique direito somente quando
  o item está selecionado. Bancadas, fornalhas, comida e construção
  mantêm a sequência anterior.
- Classic 0.30 permanece inalterado.

## Limites

Não implementa fontes infinitas de água, enchimento de caldeirões,
leite, interação com entidades, sons/partículas nem animação
realista. Ainda falta teste manual com renderização Vulkan.

Teste: `lua5.4 tests/beta181_buckets.lua`.
