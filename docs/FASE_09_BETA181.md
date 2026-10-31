# Fase 9 — simulação inicial de água e lava

Implementação original em Lua/LÖVR 0.19 com comportamento histórico
de Minecraft Java Beta 1.8.1 como **referência**, sem utilizar código
ou materiais proprietários.

## O que foi implementado

- Água (ID interno 9) flui em intervalos de 0,25 s; lava (ID 29),
  em 1,5 s, com filas independentes e limite de trabalho por atualização.
- Fontes despejam fluido verticalmente antes de se expandirem
  lateralmente. O fluxo se espalha por até 7 blocos (água) ou
  3 blocos (lava) em cada plataforma, com queda que continua
  até encontrar um suporte ou o fundo do mundo.
- Blocos sólidos bloqueiam fluxos, e abrir uma passagem ativa novamente
  os fluidos vizinhos; fluxos órfãos recuam após retirada da fonte.
- Água entrando em lava fonte gera obsidiana (ID 22);
  contato lateral com lava corrente gera pedregulho (ID 10).
  Lava caindo sobre água gera pedra (ID 3), como aproximação.
- Malhas das correntes possuem alturas visuais diferentes;
  blocos-fonte e colunas em queda permanecem de altura integral.
- Save acrescenta linhas `FLUID x y z id level falling`, sem
  alterar registros `BLOCK`, `DAYTIME`, `FURNACE`, etc.
  Saves antigos continuam válidos e o perfil Classic 0.30 não muda.
- No modo criativo Beta, água e lava podem ser colocadas diretamente
  para experimentar a simulação. No sobrevivência, continuam
  indisponíveis sem baldes, ainda não implementados.
- O painel F3 informa fila pendente e ticks de fluido processados.

## Limites conhecidos

Os oceanos e rios naturais não são simulados globalmente: são
estáticos até sofrerem uma atualização próxima, evitando criar
fluxos em todas as seções do mundo ao mesmo tempo.

O algoritmo é discreto e parcial. Faltam seleção do melhor caminho
em declive, fontes infinitas de água, correnteza aplicada ao jogador,
baldes, deslocamento em água/lava, danos térmicos, som, partículas,
transparência real e renderização avançada de fluidos. A geometria
de colisão permanece voxelizada, embora superfícies correntes
tenham alturas visuais distintas.

### Testes automatizados

`lua5.4 tests/beta181_fluids.lua`, regressões das Fases 1–8,
verificação de sintaxe e build portável Windows no GitHub Actions.
Teste visual e desempenho em GPU Vulkan ainda são necessários.
