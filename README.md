# Base 3D em Lua — Beta 1.8.1 (Fase 2)

Reimplementação **independente em Lua + LÖVR 0.19** da experiência de
Minecraft Java Beta 1.8.1. Sem redistribuir código, texturas, som ou
arquivos proprietários da Mojang. **Ainda não é uma cópia 1:1**.

## Baixar e jogar

Acesse as [compilações GitHub Actions](https://github.com/SrTristeSad/base-3d-em-lua/actions)
e abra a execução mais recente aprovada. Baixe:
- **Windows:** `Base3D-Beta181-Inventory-Crafting-Windows-EXE` (ZIP).
- **LÖVR:** `Base3D-Beta181-Inventory-Crafting-LOVR` (`.lovr`).

Extraia o ZIP inteiro. Execute `Base3D-Beta181-Inventory-Crafting.exe`
mantendo os DLLs na mesma pasta. Requer Windows x64 e driver com Vulkan.

Crie um mundo **Beta 1.8.1** usando uma **seed** numérica ou textual,
em Criativo ou Sobrevivência. O gerador não aceita mais imagens novas;
saves antigos com imagem continuam legíveis.

## Fase 2 — Inventário e crafting

No **Sobrevivência**, `E` abre o inventário, com **9 slots de hotbar,
27 de mochila e crafting 2×2**. O botão direito do mouse sobre uma
**bancada de trabalho** (construída com quatro tábuas) abre o
**crafting 3×3**.

| Controle | Ação |
| --- | --- |
| E | Abrir/fechar inventário |
| Esc | Fechar inventário ou pausar |
| Clique esquerdo no inventário | Pegar, colocar ou trocar pilha |
| Clique direito no inventário | Dividir pilha ou colocar uma unidade |
| Shift + clique | Transferir pilha; ao fabricar, repetir até o limite |
| Clique na saída do crafting | Fabricar receita com ingredientes dispostos na grade |
| 1–9 / scroll | Selecionar slot rápido |
| WASD, mouse, espaço | Movimento e câmera |
| F3 | Diagnóstico de chunks |
| F5 | Alternar primeira/terceira pessoa |
| F6 | Salvar mundo |

**Receitas implementadas:** tronco → 4 tábuas; duas tábuas →
4 gravetos; bancada de trabalho; carvão + graveto → 4 tochas;
picaretas, espadas e machados de madeira/pedra; fornalha; pão.
A **fornalha ainda não cozinha itens**, e as ferramentas ainda
não possuem velocidade/durabilidade fiéis.

**Itens salvam por slot**, incluindo as grades e o item segurado
pelo cursor. Pilhas comuns têm limite de 64, ferramentas não empilham.
Os saves de inventário simplificado da Fase 1 são migrados na abertura.
Se a mochila estiver cheia, ingredientes não são apagados ao fechar
a interface.

## Terreno da Fase 1

- Mundo por seed com biomas: oceano, rio, planície, deserto, taiga,
  floresta, pântano e Extreme Hills.
- Altura Y=0–127, mar até Y=62, cavernas, árvores e minérios.
- Spawn preferencial em terra firme.
- Mundos Classic anteriores mantêm seu perfil e limites.
- Seções 16×16×16 continuam na infraestrutura experimental do
  renderizador. **Cubic Chunks com altura expandida ainda é uma
  melhoria futura**, não foi antecipada.

## Falta para reproduzir a Beta 1.8.1

Fome, ferramentas com durabilidade, mineração por tempo, crafting e
fornalha completos, todos os itens e receitas originais, modelos e
inteligência dos mobs, iluminação, ciclo dia/noite, fluidos, clima,
estruturas, Nether, camas e detalhes de física e interface. O
gerador atual também **não reproduz as mesmas seeds da Mojang**.

Os testes automatizados cobrem Lua puro e empacotamento, mas
**não executam o jogo em GPU real**. O desempenho, a visibilidade,
o input e a interface precisam de validação manual no Windows.

## Documentação

- [Fase 2 — Inventário e crafting](docs/FASE_02_BETA181.md)
- [Fase 1 — Terreno](docs/FASE_01_BETA181.md)
- [Plano de reconstrução](docs/BASELINE_BETA_181.md)
- [FUTURO.md](FUTURO.md) — Cubic Chunks confirmado depois da
  reconstrução; outras ideias da comunidade ainda em análise.
- [Histórico Classic 0.30](docs/RECONSTRUCAO_CLASSIC_030.md)

**Projeto não afiliado, autorizado ou endossado pela Mojang/Microsoft.**
Antes de uma publicação comercial, revisar a identidade e o uso de
elementos expressivos com profissional de propriedade intelectual.
