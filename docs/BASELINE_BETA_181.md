# Direção do projeto — reconstrução independente da Beta 1.8.1

## Decisão de referência (2026-10-31)

A referência principal passa a ser **Minecraft Java Beta 1.8.1**,
a atualização de correção da Beta 1.8 (Adventure Update). O objetivo
é reproduzir em Lua/LÖVR o **comportamento e a experiência de jogo**,
sem copiar o código, sons, texturas, modelos ou outros arquivos
proprietários da Mojang.

**Não declarar o jogo como cópia fiel ou 98% concluída antes de
validar as mecânicas e a aparência.** O estado atual do repositório
continua sendo um protótipo Classic 0.30 e não implementa Beta 1.8.1.

## Fase A — baseline Beta 1.8.1

1. Mundo Overworld com geração Beta 1.8: seed determinística,
   continentes, oceanos, biomas e alturas, cavernas, ravinas,
   veios minerais, árvores e estruturas.
2. Blocos e itens de época, inventário de 36 espaços, hotbar de
   nove, empilhamento e drops, receitas e fornalha.
3. Física: colisão, movimento, sprint, nado, gravidade, queda,
   mineração com ferramentas e durabilidade.
4. Sobrevivência: vida, fome, regeneração, danos, morte e respawn.
5. Iluminação, céu e ciclo dia/noite; água e lava.
6. Mobs da época: modelos, animações, IA, spawn condicionado por
   bioma, iluminação e tipo, despawn e drops.
7. Nether com portal, blocos e mobs adequados.
8. Cama com sono e ponto de renascimento; mundo salvo.
9. Vilas, minas abandonadas, ravinas e fortalezas, com as
   limitações reais dessa versão.
10. Testes comparativos com vídeos, documentação e, quando
    possível, execução autorizada da versão original.

A Beta 1.8.1 ainda **não inclui o End nem o dragão**. O End
apareceu nas prereleases da Beta 1.9 e no lançamento 1.0.

## Fase B — melhorias próprias (somente depois)

- Cubic Chunks 16×16×16 e mundo vertical expansível.
- Streaming volumétrico adaptativo, renderização e meshing
  modernos, preservando performance.
- Geração por imagem e variações de relevo, além das seeds.
- Outras melhorias aprovadas pelo criador, sem sobrescrever o
  baseline fiel.

## Compatibilidade

Não alterar automaticamente saves Classic existentes.
O catálogo de mundos já tem o campo `generatorVersion`;
será usado para distinguir `classic030` e `beta181`.
**Não habilitar beta181 para novos mundos até haver gerador,
regras de jogo e testes funcionais.** A versão atual continua
criando Classic para não fingir que a migração foi concluída.

## Referências a consultar durante a implementação

- https://minecraft.wiki/w/Java_Edition_Beta_1.8.1
- https://minecraft.wiki/w/Java_Edition_Beta_1.8
- https://minecraft.wiki/w/History_of_world_generation
- https://minecraft.wiki/w/Bed
- https://minecraft.wiki/w/Mob_spawning

A arquitetura atual pode ser reutilizada como infraestrutura,
mas seus sistemas simplificados não devem ser confundidos com
mecânicas fiéis da Beta 1.8.1.
