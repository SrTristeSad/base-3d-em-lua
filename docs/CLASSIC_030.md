# Classic 0.30 — Catálogo implementado

O motor é LÖVR/Lua, independente de Roblox e de qualquer arquivo binário do
Minecraft. O objetivo é **uma implementação original inspirada no comportamento
do Classic 0.30**, não uma cópia exata ou completa da versão histórica.

## Criaturas

| Criatura | Implementação | Diferenças conhecidas |
| --- | --- | --- |
| Creeper | Corpo cúbico; corre atrás do jogador, ataca de perto e explode quando derrotado; 200 pontos | IA, aparência e ritmo são simplificados |
| Zumbi | Hostil, dano corpo a corpo, 80 pontos | Sem armaduras opcionais ou animações dedicadas |
| Esqueleto | Hostil, flechas simuladas, 120 pontos | Sem arco equipado e sem recuperação de flechas |
| Aranha | Hostil e mais veloz, 105 pontos | Não escala paredes nem salta |
| Porco | Passivo, anda pelo mapa, dá 2 cogumelos marrons e 10 pontos | Sem animações ou física completa |
| Ovelha | Passiva, entrega lã branca e 10 pontos | Não possui tosquia sem morte nem lã sobreposta |

Os cinco tipos novos ficam em `src/creatures.lua`, o creeper em
`src/creepers.lua`, com formas produzidas por `pass:box`.
Sprites e sons oficiais não estão incluídos.

## Blocos

Os IDs 1–9 foram mantidos para não corromper mundos antigos.
Os novos blocos/variantes 10–46 incluem cobblestone, cascalho,
minérios de ouro/ferro/carvão, TNT, vidro, esponja, blocos de ouro/ferro,
pedra com musgo, estante, obsidiana, laje, flores, cogumelos,
muda de árvore, lava decorativa, rocha-mãe e 16 cores de lã.

**É uma paleta aproximada.** Alguns são cubos inteiros provisórios,
inclusive a laje, flores e cogumelos. O fluxo real de água e lava,
o crescimento das mudas, a mineração contínua com tempos distintos
e as variações de iluminação não foram implementados.

## Como jogar

- Menu inicial: alternar entre Criativo (blocos sem limite, sem hostis)
  e Sobrevivência (recolher recursos e consumir blocos para construir).
- `TAB`: avança uma das seis páginas de blocos, com oito espaços por página.
  As teclas de 1–8 e a roda do mouse selecionam espaços da página atual.
- `E`: comer cogumelo marrom ou vermelho para recuperar vida.
- Esquerdo em TNT posta: acende o pavio no Sobrevivência.
- Direito na TNT acesa sob a mira: desarma e devolve TNT ao estoque.
- Detonações têm atraso e podem detonar TNT próxima.
- `F6` salva o mundo e o estoque; carregamentos de saves anteriores
  continuam válidos.

Os dados do mundo incluem apenas as edições de blocos, a posição, o
modo, os itens e a pontuação. Posições de monstros e pavios não são salvos.

## Testes

```sh
lua5.4 tests/world_basic.lua
lua5.4 tests/classic_basic.lua
lua5.4 tests/blocks_030.lua
lua5.4 tests/creepers_basic.lua
lua5.4 tests/creatures_030.lua
```

O pipeline `lua-check.yml` verifica sintaxe, testes e empacota
`Base3D-Classic-030.lovr`. Ele **não testa gráficos nem inputs**.
É preciso executar o .lovr em LÖVR 0.19 com um computador compatível.

## Fontes históricas

- Minecraft Wiki — Java Edition Survival Test:
  https://minecraft.wiki/w/Java_Edition_Survival_Test
- Minecraft Wiki — Classic 0.30:
  https://minecraft.wiki/w/Classic_0.30
- Minecraft Wiki — Classic block IDs:
  https://minecraft.wiki/w/Java_Edition_Classic_data_values

As regras de pontuação e a explosão do Creeper na morte foram conferidas
na documentação histórica, mas esta implementação ainda não reproduz
fisicamente todas as diferenças de 2009.
