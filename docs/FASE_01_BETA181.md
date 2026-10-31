# Beta 1.8.1 — Fase 1 (fundação)

A versão jogável atual é um **protótipo de reconstrução**, não uma cópia 1:1.

## Implementado nesta fase
- Perfil `beta181` separado de mundos anteriores.
- Overworld por seed: continentes, oceanos, rios, planícies, deserto, floresta, taiga, pântanos e Extreme Hills.
- Altura 0–127; oceano com água até Y=62; cavernas, árvores e seis tipos de minérios.
- Spawn preferencial em terra firme.
- Barra de nove posições e pilhas provisórias de 64 blocos.
- Geração por imagem desativada para mundos novos, sem impedir leitura de saves antigos.
- Testes automatizados de terreno, versionamento e salvamento.

## Pendente para fidelidade à Beta
- Geração original calibrada, ravinas, vilas vazias, minas e fortalezas.
- Inventário 36 slots, ferramentas, crafting, fornalha, fome e alimentação.
- Mobs da Beta, lógica de luz, ciclo dia/noite, água e lava dinâmicas.
- Camas, portal, Nether, movimento e HUD fiel.

A criação de mundo usa o gerador próprio em Lua: não promete que a mesma seed produzirá a geografia exata do Minecraft.

Fontes históricas:
- https://minecraft.wiki/w/Java_Edition_Beta_1.8
- https://minecraft.wiki/w/Java_Edition_Beta_1.8.1
- https://minecraft.wiki/w/History_of_world_generation

Cubic Chunks e outras mudanças do [FUTURO](../FUTURO.md) ficam para **depois** da reprodução do jogo-base.
