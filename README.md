# Base 3D em Lua — Beta 1.8.1 (Fase 5)

Reimplementação independente em **Lua + LÖVR 0.19**, usando a
experiência da **Minecraft Java Beta 1.8.1** como referência técnica.
Não redistribui recursos da Mojang nem pretende representar um produto
oficial. **Ainda não é uma cópia 1:1**: muitos sistemas continuam
experimentais ou ausentes.

## Download

Na [página do GitHub Actions](https://github.com/SrTristeSad/base-3d-em-lua/actions),
abra a execução mais recente aprovada. Baixe um dos artefatos:

- `Base3D-Beta181-Day-Night-Windows-EXE` — Windows 64 bits.
- `Base3D-Beta181-Day-Night-LOVR` — projeto `.lovr`.

Extraia o ZIP Windows inteiro (inclusive as DLLs) e execute
`Base3D-Beta181-Day-Night.exe`. Requer GPU/driver com Vulkan.
A CI valida sintaxe, lógica e empacotamento, **não a execução real na GPU**.

## Fase 5: ciclo de dia e noite

O mundo Beta tem relogio de **20 minutos reais por dia**, com transicao
suave de cor do ceu e luminosidade ambiental. O HUD mostra o dia, horario
e fase. F7 no Criativo avanca seis horas para testes. Os dados sao salvos
por mundo, e saves anteriores continuam legiveis.

A iluminacao por bloco (tochas, lava, cavernas) ainda nao foi implementada.

## Fase 4: fornalha funcional

1. Entre em um mundo Beta 1.8.1, preferencialmente Sobrevivência.
2. Em uma bancada 3×3, disponha **oito pedregulhos**, deixando o centro
   vazio. Você receberá uma fornalha.
3. Coloque-a no terreno e use **clique direito** para abrir sua interface.
4. Arraste **minério de ferro**, **minério de ouro**, **areia** ou
   **carne crua** para o espaço **MATERIAL**.
5. Arraste **carvão**, **troncos**, **tábuas**, **gravetos** ou uma
   **bancada** para o espaço **COMBUSTÍVEL**.
6. Aguarde **10 segundos por item**. Uma unidade de carvão dura
   **80 segundos** (até oito fundições). Retire os produtos à direita.

A fornalha funciona mesmo com a interface fechada enquanto você
permanece no mundo. A queima do combustível continua mesmo quando a
entrada acaba, desperdiçando o restante, como no jogo de referência.
O combustível é consumido no início da queima.

| Entrada | Produto |
| --- | --- |
| Minério de ferro | Lingote de ferro |
| Minério de ouro | Lingote de ouro |
| Areia | Vidro |
| Porco cru | Porco assado |
| Carne bovina crua | Bife |
| Frango cru | Frango assado |

**Progresso, combustível restante e conteúdo dos três slots são
salvos individualmente para cada fornalha.** Para evitar perda de
materiais, temporariamente não é permitido quebrá-la enquanto
possuir itens. Esvazie-a primeiro.

Os lingotes de ferro agora permitem fabricar **picaretas,
espadas, machados e pás de ferro** na bancada 3×3. A fundição de ouro
também funciona. A progressão completa ainda exige sistemas adicionais.

## Controles das fases anteriores

| Controle | Função |
| --- | --- |
| WASD, mouse, Espaço | Mover, olhar e pular |
| Shift | Corrida, limitada por fome |
| Segurar esquerdo | Minerar progressivamente |
| Segurar direito com comida | Comer após 1,6 segundo |
| Direito sobre bancada | Crafting 3×3 |
| Direito sobre fornalha | Abrir fundição |
| E | Inventário 36 slots e crafting 2×2 |
| Esquerdo/direito nos slots | Mover pilha, dividir ou colocar um item |
| Shift + clique | Transferir itens entre slots |
| 1–9 / scroll | Selecionar slot rápido |
| F3 / F5 / F6 | Diagnóstico, câmera e salvar |
| F7 (Criativo Beta) | Avançar seis horas para testar o ciclo |
| Esc | Fechar interface ou pausar |

Mundos novos usam somente **seeds**. Imagens foram retiradas da criação;
saves antigos, inclusive do perfil Classic 0.30, permanecem legíveis.

## Limitações conhecidas

As gerações de biomas, cavernas, estruturas e minérios ainda não são
idênticas às mesmas seeds da Beta. Faltam iluminação por bloco, sombra em cavernas,
IA de mobs historicamente fiel, Nether, camas, líquidos dinâmicos,
sistema completo de combate e várias receitas e itens da época.

A interface da fornalha usa uma arte original simplificada em vez da
interface proprietária do Minecraft. Os blocos têm **IDs internos
próprios**, diferentes dos IDs históricos em vários casos.

## Documentação

- [Relatório técnico — Fase 5: dia/noite](docs/FASE_05_BETA181.md)
- [Relatório técnico — Fase 4: fornalhas](docs/FASE_04_BETA181.md)
- [Fase 3: mineração e fome](docs/FASE_03_BETA181.md)
- [Fase 2: inventário](docs/FASE_02_BETA181.md)
- [Fase 1: terreno](docs/FASE_01_BETA181.md)
- [Plano de reconstrução](docs/BASELINE_BETA_181.md)
- [FUTURO.md](FUTURO.md) — **Cubic Chunks somente depois** da
  reconstrução do jogo-base; outras ideias ainda em análise.

Este projeto não é afiliado ou endossado pela Mojang/Microsoft.
Antes de eventual distribuição comercial, a identidade visual e
outros elementos expressivos exigem revisão de direitos autorais.
