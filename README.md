# Base 3D em Lua — Beta 1.8.1 (Fase 3)

Reimplementação **independente** da experiência de Minecraft Java
Beta 1.8.1, desenvolvida em **Lua + LÖVR 0.19**. Código e arte próprios:
não redistribui Minecraft ou recursos da Mojang. **Ainda não é uma
reprodução 1:1**: os algoritmos de mundo, IA, física e aparência estão
em diferentes estágios de implementação.

## Baixar e testar

Abra o [GitHub Actions](https://github.com/SrTristeSad/base-3d-em-lua/actions)
e escolha a última execução com **sucesso**. No final da página,
baixe `Base3D-Beta181-Survival-Tools-Windows-EXE` (ZIP) ou
`Base3D-Beta181-Survival-Tools-LOVR` (.lovr).

Extraia o ZIP inteiro, inclusive as DLLs, e execute
`Base3D-Beta181-Survival-Tools.exe`. Requer Windows x64 com Vulkan.
O pacote automatizado compila e testa lógica Lua, **não** valida
a renderização ou os controles em uma GPU real.

## Jogar — Fases 1 a 3

No menu, **CRIAR NOVO MUNDO**. Informe uma semente (*seed*)
numérica ou textual e selecione **Sobrevivência**. Novos mundos não
aceitam geração por imagem; mundos antigos continuam disponíveis.

| Controle | Ação |
| --- | --- |
| WASD, mouse, Espaço | Mover, olhar, pular |
| Shift | Correr enquanto a fome estiver acima de 6 |
| **Segurar esquerdo** | **Minerar até completar a barra** |
| **Segurar direito** com alimento na mão | **Comer em 1,6 s** |
| Direito sobre bancada | Crafting 3×3 |
| E | Inventário 9+27 e crafting 2×2 |
| 1–9 / scroll | Slot selecionado da barra rápida |
| Clique esquerdo no inventário | Pegar ou colocar pilha |
| Clique direito no inventário | Dividir ou depositar uma unidade |
| Shift + clique no inventário | Transferência/fabricação rápida |
| F3 | Estatísticas de chunks |
| F5 | Primeira/terceira pessoa |
| F6 | Salvar |
| Esc | Pausar ou fechar interface |

### Mineração e ferramentas — Fase 3

- Mineração progressiva enquanto o mouse estiver pressionado.
  Mudar o alvo, a ferramenta ou soltar o botão interrompe o progresso.
- Ferramentas de madeira, pedra e ferro diferem em **velocidade**.
  Madeira: **59 usos**; pedra: **131**; ferro: **250**;
  diamante: **1561**. O desgaste é salvo por ferramenta.
- Minérios exigem níveis adequados de picareta para oferecer drops.
  Sem a ferramenta apropriada, o bloco pode quebrar sem coletar minério.
- Primeiras receitas para pás e ferramentas de ferro e diamante.
  **Ainda não existe um forno de fundição funcional.** A progressão
  completa em Sobrevivência ainda não é possível.

### Fome e alimentação — Fase 3

- Dez ícones de fome, **20 pontos**, saturação e exaustão.
- Comer exige segurar o botão direito **1,6 segundo** e possuir fome.
  Porcos deixam **carne crua**, que restaura **3 pontos de fome**.
- Corrida consome mais energia; não é possível correr com fome ≤6.
  Regeneração gradual de vida se fome ≥18; fome zero causa dano.
  Nesta versão experimental, a dificuldade é equivalente ao *Normal*
  para fome: o dano para em um ponto de vida.
- O status de fome/vida e a condição de cada ferramenta persistem
  nos arquivos do mundo. Saves mais antigos sem esses campos são aceitos.
- Ainda não há animações de alimentação, ícones pixel-perfect,
  efeitos especiais e toda a lista de alimentos históricos.

### Recursos anteriores

- Overworld com oceanos, rios, planícies, florestas, deserto,
  taiga, pântanos, montanhas, cavernas, árvores e seis minérios.
- Altura **Y=0–127**; água dos mares até **Y=62**.
- Inventário **36 slots**, crafting 2×2 e bancada 3×3;
  tábuas, gravetos, picaretas, machados, espadas, forno, tochas
  e alguns alimentos/receitas.
- Saves `beta181` separados dos mundos Classic 0.30 anteriores.

## Pendências importantes

O projeto **não** reproduz ainda seeds idênticas às originais,
vilas, ravinas/estruturas completas, geração e mob spawning fiéis,
IA de criaturas, iluminação, clima, líquidos dinâmicos, Nether,
camas, fornalha com combustível, equipamentos completos ou
mecânicas de combate e física totalmente fiéis.

As futuras mudanças de [FUTURO.md](FUTURO.md), começando por
**Cubic Chunks**, serão implementadas somente depois da
reconstrução do jogo base.

## Documentação

- [Relatório técnico — Fase 3](docs/FASE_03_BETA181.md)
- [Inventário e crafting — Fase 2](docs/FASE_02_BETA181.md)
- [Terreno — Fase 1](docs/FASE_01_BETA181.md)
- [Planejamento Beta 1.8.1](docs/BASELINE_BETA_181.md)
- [FUTURO.md](FUTURO.md) — decisões e ideias da comunidade

Minecraft é marca de seus titulares. Este projeto não é oficial
nem associado à Mojang/Microsoft. Uma futura publicação comercial
precisará utilizar identidade e elementos expressivos próprios
e de avaliação jurídica especializada.
