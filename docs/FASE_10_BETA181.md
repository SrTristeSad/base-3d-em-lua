# Fase 10 — natação, correnteza, ar e lava

A Fase 9 introduziu água e lava com fluxo. A Fase 10 acrescenta a
**interação do jogador** com esses blocos, preservando o motor Lua/LÖVR.

- A água reduz a velocidade horizontal e a gravidade. Segurar
  **Espaço** faz o jogador subir, inclusive dentro de uma coluna.
- Lava também desacelera o movimento e permite movimento vertical
  reduzido. A simulação distingue lava e água.
- Correntes podem deslocar o personagem sem teclas; fontes naturais
  paradas, sem estado de fluxo, não geram impulso.
- As superfícies fluidas são amostradas pela altura real da corrente,
  inclusive correntes rasas, para diferenciar imersão e ar.
- Submersão da cabeça consome **15 segundos de ar**; após esgotar,
  há pulsos de dano por afogamento. Voltar à superfície restaura o ar.
- No sobrevivência, contato prolongado com lava causa dano periódico.
  No criativo, a lava não reduz vida.
- Indicadores de ar e lava aparecem no HUD.
- O save pode registrar `PLAYERAIR` (0–15 s), mantendo a leitura de
  arquivos antigos que não possuem esse campo.
- Sem alterações nos saves de fluidos da Fase 9, iluminação, fornalhas,
  crafting ou mundos Classic 0.30.

## Limitações

É uma aproximação independente, não uma reconstrução 1:1 da
física histórica. Falta ajustar o movimento em água por geometria
do corpo, animações de nado, efeitos de fogo após sair da lava,
baldes, física de entidades soltas e quedas ao entrar em água.

A IA e a simulação gráfica ainda precisam de testes manuais em PC
com Vulkan. A suíte automatizada verifica física e persistência.

Teste: `lua5.4 tests/beta181_fluid_player.lua`.
