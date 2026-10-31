# Fase 5 — ciclo de dia/noite e iluminação local

**Registro:** 31 de outubro de 2026.

## Escopo desta entrega

- `src/beta181_lighting.lua`: relógio 24.000 ticks, 20 ticks por segundo (20 minutos por dia), transições de dia, crepúsculo, noite e amanhecer, cor do céu e luz natural aproximada de 4–15.
- Gerenciamento de fontes de luz por seções tridimensionais. Uma **tocha** (ID 52) emite nível 14 e uma lava **colocada** (ID 29) emite 15. A luz é atenuada por distância Manhattan, sem bloqueio por paredes nesta fase (aperfeiçoado na [Fase 6](FASE_06_BETA181.md)).
- `src/world.lua`: mantém o relógio somente para perfil `beta181`, indexa luz das edições e salva `DAYTIME <tick> <dia>`. Ao alterar uma fonte, invalida malhas vizinhas, inclusive em direções verticais.
- `src/mesher.lua`: agrupa faces de mesmo material conforme aproximação de céu aberto e faixa de luz local. Os multiplicadores de brilho são atualizados a cada frame **sem refazer as malhas quando apenas o horário muda**.
- `main.lua`: avança o relógio apenas durante a sessão jogável, inclusive nas interfaces; aplica cor de fundo dinâmica pela API `Pass:setClear` do LÖVR 0.19.
- `src/mob_spawning.lua`: escolhe grupos passivos em locais claros e hostis em locais escuros, impedindo que tochas iluminadas aceitem nascimentos hostis. Regiões podem gerar novos grupos quando muda o período do dia.
- `src/creatures.lua`: zumbis/esqueletos expostos diretamente à luz solar perdem vida; a leitura de blocos acima da criatura diferencia sol e abrigo. Os demais mobs/Classic não são alterados.
- `src/ui.lua`: dia, horário, fase (dia/noite) e luminosidade do céu.

## Limitações honestas

A iluminação é uma **base simplificada**, não a propagação de iluminação do Minecraft: não calcula sombras causadas por paredes na iluminação das tochas, não propaga o valor pelo interior de galerias com flood-fill e a seleção de superfícies ao céu usa altura natural aproximada, não iluminação vertical completa por voxel. A consulta de sombra para mobs verifica a coluna real de blocos, mas não simula os diversos estados de transparência, chuva e equipamentos.

O spawner atual tenta posições **próximas da superfície**: ainda não usa volumes de cavernas, distribuição histórica por categorias de chunk nem limites iguais aos da Beta 1.8.1. A transição de noite para dia reinicia a tentativa local de spawn para permitir a mudança de categorias. Zumbis/esqueletos sofrem dano, mas ainda não renderizam fogo.

Não há ainda lua, sol geométrico, estrelas animadas, nuvens, clima, tochas 3D fisicamente pequenas ou iluminação RGB. A cor do céu é uniforme em vez de gradiente atmosférico.

## Testes novos

`tests/beta181_lighting.lua` valida:
- manhã, noite, crepúsculo, amanhecer, sequência de 24.000 ticks e contagem de dias;
- salvação e restauração do tempo, inclusive compatibilidade com saves antigos;
- fontes de luz nas fronteiras de seções, remoção de tochas e atualização das malhas;
- exposição ao céu com e sem abrigo;
- agrupamento de malhas por classe de iluminação;
- seleção de mobs passivos/hostis baseada na claridade;
- dano solar de zumbis e ausência de dano sob telhados ou à noite.

A CI também preserva todos os testes das fases anteriores (terreno, inventário, ferramentas, fome, forno e Classic). A verificação **não substitui** testes reais de aparência ou FPS no Windows.

## Referências

- [Daylight cycle — Minecraft Wiki](https://minecraft.wiki/w/Daylight_cycle).
- [Light — Minecraft Wiki](https://minecraft.wiki/w/Light).
- [Mob spawning — Minecraft Wiki](https://minecraft.wiki/w/Mob_spawning).
- [Pass:setClear — LÖVR 0.19](https://lovr.org/docs/v0.19.0/Pass%3AsetClear).

A referência é de mecânica e constantes, **não** de código ou assets de Minecraft.
