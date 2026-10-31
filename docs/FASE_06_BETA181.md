# Fase 6 — propagacao de luz nas cavernas e paredes

Extensao do sistema de iluminacao independente da Beta 1.8.1.

- Tochas (14) e lava posicionada (15) difundem luz pelas seis
  direcoes dos voxels: BFS, um nivel a menos por passo.
- Materiais opacos interrompem a difusao. Buracos e corredores
  permitem caminhos alternativos; desvios sao mais fracos.
- Fontes vizinhas coexistem; retirar uma nao desliga outra.
- Bloquear ou desobstruir passagens invalida caches de fontes
  proximas e marca chunks influenciados para reconstruir as malhas.
- Fontes salvas sao restauradas sem reprocessamento imediato de
  todas as regioes: a propagacao ocorre sob demanda.
- Compatibilidade preservada com o arquivo DAYTIME, inventario,
  fornalhas e mundos Classic 0.30.

## Limites
Ainda falta skylight real propagado por voxel, iluminacao
continuamente suavizada por vertice, lava natural indexada e
otimizacao para grandes quantidades de fontes ativas. O BFS
opera apenas nas fontes posicionadas/indexadas. Nao e copia 1:1
do motor original de iluminacao.

Teste: `lua5.4 tests/beta181_light_occlusion.lua`.
Aparencia e desempenho exigem validacao em hardware Vulkan.
