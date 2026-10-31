# Base 3D em Lua — Beta 1.8.1 (Fase 7)

Reimplementação **independente em Lua + LÖVR 0.19** com **Minecraft Java Beta 1.8.1** como referência de comportamento histórico. Não utiliza código, texturas ou outros arquivos da Mojang. **O projeto ainda não é uma reprodução 1:1**: alguns algoritmos e sistemas são aproximações e vários recursos estão pendentes.

## Baixar a versão jogável

Na página [GitHub Actions](https://github.com/SrTristeSad/base-3d-em-lua/actions), abra a execução mais recente **aprovada** e baixe um dos artefatos:

- `Base3D-Beta181-Skylight-Windows-EXE` — Windows 64 bits, executável e DLLs em ZIP.
- `Base3D-Beta181-Skylight-LOVR` — pacote `.lovr` para executar no motor LÖVR.

Extraia o ZIP Windows **inteiro**, mantendo as DLLs junto de `Base3D-Beta181-Skylight.exe`. É necessário Windows 64 bits e GPU/driver com Vulkan. Os testes automatizados verificam a lógica e o empacotamento; **a aparência e o desempenho exigem teste real em uma GPU**.

## Fase 7 — skylight em poços, telhados e cavernas

A luz do céu agora respeita o teto **real de cada coluna**, inclusive
blocos construídos ou escavados. Poços abertos recebem claridade até
o fundo; a luz também entra lateralmente por entradas de cavernas,
perdendo intensidade ao percorrer os corredores.

As alterações invalidam os caches solares e atualizam os chunks
necessários sem recriar malhas apenas por passar de dia para noite.
O cálculo é aproximado e usa buscas limitadas a 14 passos.

[Relatório técnico da Fase 7](docs/FASE_07_BETA181.md).

## Fase 6 — luz bloqueada por paredes

Tochas e lava colocada agora propagam luz em seis direcoes, com
perda por bloco e **bloqueio por materiais opacos**. Corredores e
buracos deixam a luz passar; fechar uma passagem recalcula as
fontes proximas, incluindo as bordas dos chunks.

O sistema conserva o relogio e salva os mesmos mundos. A
iluminacao do ceu ainda e aproximada; nao ha skylight
propagado completamente por voxel.

[Relatorio tecnico da Fase 6](docs/FASE_06_BETA181.md).

## Fase 5 — luz, dia/noite e criaturas

**Novos mundos Beta 1.8.1** começam durante a manhã. A cada **20 minutos de jogo ativo** transcorre um dia completo (24.000 ticks, 20 ticks/s). O tempo progride no mundo e nas interfaces de inventário, bancada e fornalha; fica **pausado no menu de pausa**.

- Dia, pôr do sol, noite e amanhecer, com transições graduais de cor do céu e brilho.
- **Relógio e número de dias salvos**, de forma compatível com saves das fases anteriores.
- **Tochas (bloco 52)** iluminam a geometria próxima; retirar uma tocha atualiza as malhas afetadas. Luz local usa propagação BFS por voxels transparentes, respeitando paredes.
- **O renderizador diferencia exterior e subsolo**, aplicando tonalidade diurna/noturna e luz local nas superfícies. A Fase 5 utilizava altura natural; a Fase 7 acrescentou verificação da geometria real.
- **Mobs passivos** são tentados em terrenos iluminados; **hostis** em locais escuros. Regiões já visitadas voltam a receber tentativas quando o dia muda para noite ou vice-versa.
- **Zumbis e esqueletos** expostos diretamente ao sol sofrem dano periódico; creepers não queimam. Há verificação real de blocos acima dos mobs para reconhecer abrigos.
- O HUD exibe **dia, horário aproximado, fase e nível da luz do céu**.

Os mobs ainda são provisórios: faltam geração subterrânea completa, a distribuição de spawn original, efeitos visuais de fogo, comportamento complexo, skylight historicamente exato, sombras suavizadas e animações finais.

## Recursos das fases 1–4

O Overworld possui seeds determinísticas, altura Y=0–127, mares até Y=62, biomas, cavernas, árvores e minérios. O **inventário com 36 slots** contém crafting 2×2 e bancada 3×3. Mineração por tempo, desgaste de ferramentas, fome e comida estão disponíveis. **Fornalhas** fundem minérios e cozinham alimentos, consumindo combustível e preservando seu progresso ao salvar.

### Controles

| Controle | Ação |
| --- | --- |
| WASD + mouse | Andar e olhar |
| Espaço / Shift | Pular / correr |
| Segurar botão esquerdo | Minerar por tempo |
| Segurar direito com comida | Comer |
| Botão direito sobre bancada/fornalha | Abrir crafting/fundição |
| E | Abrir/fechar inventário |
| 1–9 / scroll | Seleção na hotbar |
| F3 / F5 / F6 | Estatísticas / câmera / salvar |
| Esc | Pausa, inclusive do relógio |

## Compatibilidade e desenvolvimento

- **Classic 0.30** e saves antigos permanecem no perfil anterior, sem relógio ou luz dinâmica.
- A nova versão cria mundos somente com **seeds**, não com PNG/JPG. Imagens antigas de saves legados permanecem legíveis.
- O formato `DAYTIME <tick> <dia>` é adicionado apenas aos saves Beta; saves sem essa linha iniciam com horário padrão.
- O registro de tochas usa as coordenadas salvas de edições de blocos. A iluminação local é reconstruída ao carregar o mundo.
- Arquivos e testes em `src/beta181_lighting.lua`, `tests/beta181_lighting.lua`, `src/mesher.lua`, `src/mob_spawning.lua` e `src/creatures.lua`.

Documentação: [Fase 5](docs/FASE_05_BETA181.md), [Fase 4](docs/FASE_04_BETA181.md), [plano Beta](docs/BASELINE_BETA_181.md), [FUTURO.md](FUTURO.md). **Cubic Chunks** é a primeira melhoria aprovada *para depois* da reprodução do jogo-base.

**Ainda faltam:** algoritmo exato de seeds e biomas, vários itens e estruturas, sistema de luz voxel completo, clima, água/lava dinâmica, camas, Nether, física e mobs historicamente fiéis. O jogo não é oficial nem afiliado à Mojang/Microsoft. Uma futura distribuição comercial necessita de identidade própria e avaliação jurídica adequada.
