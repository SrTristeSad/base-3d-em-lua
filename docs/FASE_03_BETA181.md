# Fase 3 — mineração, ferramentas, durabilidade e fome

**Marco:** 2026-10-31

## Escopo integrado

- `src/beta181_survival.lua`: durezas de blocos,
  velocidade/nível das ferramentas, regras de mineração, alimento,
  exaustão, saturação, regeneração e fome.
- `src/beta181_items.lua`: ferramentas não empilháveis com `damage`;
  desgaste até quebra (madeira 59, pedra 131, ferro 250,
  diamante 1561), regras de drop por tier, alimentação.
- `src/player.lua`: manter clique para minerar, cancelar ao mudar
  ferramenta/bloco ou soltar; comer após segurar botão direito por
  1,6 s, corrida condicionada a fome, exaustão por movimento.
- `main.lua`: estados dos botões e callbacks para soltar,
  separação entre Sobrevivência Beta e modo Classic anterior.
- `src/ui.lua`: HUD de fome, progresso de mineração e indicação
  da durabilidade das ferramentas na barra e no inventário.
- `src/creatures.lua`: porcos fornecem carne crua (ID 319) em
  Sobrevivência Beta; drops do Classic permanecem diferentes.
- `src/world.lua`: `PLAYERSTATUS` e serialização de durabilidade
  nos slots, crafting e cursor, preservando leitura de saves sem
  esses atributos.
- `src/beta181_crafting.lua`: receitas de pás e ferramentas de
  ferro/diamante além da Fase 2.

## Critérios verificáveis

- Mineração por tempo e cancelamento sem perda de bloco.
- Picareta de madeira coleta pedra mas não ferro/diamante; de
  pedra permite ferro; ferro permite diamante.
- Ferramentas desgastam, quebram, não empilham e não são
  reparadas involuntariamente ao mover/salvar.
- A fome de 20 pontos baixa com exaustão, primeiro consumindo
  saturação. Comer carne crua repõe 3 pontos, após 1,6 s.
- Fome ≥18 permite regenerar 1 HP em intervalos de 4 s;
  fome 0 causa dano sem matar diretamente (Normal).
- Persistência e compatibilidade com saves anteriores.
- CI verifica sintaxe, testes da Beta 1.8.1, do Classic e
  empacotamento de ZIP LÖVR/Windows.

## Diferenças e limites

Isto é uma **reconstrução independente, não idêntica** à Beta 1.8.1.
Constantes históricas verificadas orientaram o primeiro corte,
mas algumas durezas, velocidades e custos ainda requerem calibração
em comparação com a versão original.

**Limitadores atuais:** a fornalha ainda não funde minério de ferro
para obter lingotes, então a progressão completa até picareta de
ferro/diamante não está disponível sem materiais pré-existentes.
Faltam danos de queda, animação das ferramentas e da comida,
efeitos visuais de quebra do bloco, drops como entidades físicas,
barco, água corrente, itens de alimentação completos e sistema
de dificuldade configurável.

Não declarar o recurso finalizado antes de teste real no Windows;
a CI valida somente a estrutura, a lógica e a embalagem.

## Fontes históricas

- https://minecraft.wiki/w/Hunger
- https://minecraft.wiki/w/Raw_Porkchop
- https://minecraft.wiki/w/Tiers
- https://minecraft.wiki/w/Breaking
