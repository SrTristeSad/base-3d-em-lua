# Fase 2 — Inventário 36 slots e crafting Beta 1.8.1

**Data:** 2026-10-31

## Escopo concluído no código

- `src/beta181_items.lua`: inventário com **36 slots** (9 rápidos e
  27 de armazenamento), pilhas de 64 e ferramentas não empilháveis.
  Implementa cursor, clique esquerdo/direito, Shift+clique, fusão,
  divisão e troca de pilhas.
- `src/beta181_crafting.lua`: receitas moldadas por padrões. A grade
  **2×2** é aberta com E; o **3×3** aparece quando se interage com uma
  bancada de trabalho colocada no mundo.
- `src/ui.lua`: desenha todas as células e usa o mesmo posicionamento
  para hit testing, saída e cursor. Não requer renderização especial.
- `main.lua`: E abre/fecha inventário Beta; botão direito sobre a
  bancada abre o 3×3. Cliques movimentam itens em vez de minerar.
- `src/player.lua`: coloca blocos do slot efetivamente selecionado
  na hotbar Beta, consumindo **somente essa pilha**.
- `src/world.lua`: serialização `SLOT`, `CRAFT2`, `CRAFT3`,
  `CURSOR`; lê saves antigos do formato `ITEM` e evita conversão
  automática dos mundos Classic.
- `src/textures.lua`: materiais provisórios para bancada, forno,
  tocha e novas páginas criativas.
- `tests/beta181_inventory.lua`: casos de receitas, ações por clique,
  Shift, capacidade, limite de empilhamento, persistência e interface.
- `tests/beta181_world.lua`: mantém cobertura do terreno e da
  separação entre versões.

## Receitas dessa etapa

| Grade | Receita | Saída |
| --- | --- | --- |
| 2×2 | 1 tronco | 4 tábuas |
| 2×2 | 2 tábuas na vertical | 4 gravetos |
| 2×2 | 4 tábuas | Bancada de trabalho |
| 2×2 | Carvão sobre graveto | 4 tochas |
| 3×3 | 3 tábuas ou 3 pedras com gravetos abaixo | Picareta |
| 3×3 | 2 tábuas ou 2 pedras sobre graveto | Espada |
| 3×3 | Tábuas ou pedras em formato de machado | Machado |
| 3×3 | 8 pedregulhos, centro vazio | Fornalha |
| 3×3 | 3 trigos em linha | Pão |

**Limites declarados:** padrões de receitas só cobrem uma parte da
Beta 1.8.1; forno ainda não funde minérios; ferramentas ainda não
têm dano/durabilidade/velocidade; faltam crafting avançado e itens
de comida coletáveis. Não foi recriado o pacote original da Mojang.

O inventário anterior da Fase 1 agrupava itens por ID e podia ter até
64 por tipo. A Fase 2 usa slots independentes e atualiza saves de
forma que mundos existentes possam manter seus materiais.

## Comportamento de Shift+clique

Na Beta 1.8, a versão corrigida do crafting permitia fabricar a maior
quantidade possível ao usar Shift na saída. A implementação interrompe
a fabricação quando não há ingredientes ou espaço suficiente no
inventário. Isso impede a perda silenciosa de itens.

**Fontes históricas consultadas:**
- https://minecraft.wiki/w/Inventory
- https://minecraft.wiki/w/Crafting
- https://minecraft.wiki/w/Crafting_Table

A reconstrução é independente e ainda exige comparação com a Beta
histórica para atingir fidelidade visual, funcional e de balanceamento.
