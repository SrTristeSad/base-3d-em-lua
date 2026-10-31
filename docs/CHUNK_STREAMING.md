# Chunks 64×64 — geração e renderização do mundo

## O que mudou

Na versão inicial, todo o mundo tinha 48×48 colunas pré-calculadas e renderizadas
por seis faces de cada bloco exposto. Agora a base utiliza **chunks 16×16**
em X/Z e uma **janela padrão de quatro por quatro chunks** em torno do jogador:
**64×64 colunas**. As camadas verticais permanecem em Y -4 a 19.

A janela de renderização pode ser configurada como 64×64 (16 chunks),
96×96 (36 chunks) ou 128×128 (64 chunks). O carregamento começa nos chunks
próximos à câmera e prossegue gradualmente; duas malhas/chunks por quadro
são o orçamento no modo de jogo. O menu carrega um chunk por quadro.

Não há mais uma fronteira do mundo em ±24. O limite de coordenadas
está fixado em ±1.048.575 por segurança dos floats e do save, não por
decisão visual. Os mobs inicialmente nascem na antiga região de spawn,
mas são realocados para regiões próximas quando o jogador se afasta.

## Pipeline

1. `World:get(x,y,z)` descobre o chunk `floor(x/16):floor(z/16)`.
2. `World:generateChunk(cx,cz)` gera estratos, água, árvores, minérios,
   flores e cogumelos com funções determinísticas, sem fazer IO.
3. `World:load()` carrega um overlay compacto de edições por chunk.
   Essas edições são reaplicadas sempre que o chunk é regenerado.
4. `Mesher.buildData(world,cx,cz,faces)` encontra apenas as faces
   expostas e funde retângulos adjacentes da mesma textura em
   uma malha por material. Os polígonos usam UVs repetidos para
   preencher o retângulo.
5. `Mesher:sync(px,pz,view,budget)` carrega primeiro os chunks
   próximos, respeita o orçamento por quadro e chama
   `Mesh:release()` para as regiões fora da janela.
6. `World:prune(...)` descarta caches antigos de CPU; o overlay
   de edições persiste. Entrar novamente naquela região regenera
   o terreno e aplica o overlay sem perder construções.

A CPU usa até a janela visível e uma pequena borda de chunks para
consulta de faces vizinhas. O tamanho máximo estimado do cache de terreno
ao redor de um jogador em 64×64 é 9×9=81 chunks. **Essa não é uma
garantia de uso de RAM em bytes ou de FPS**.

## Escolhas técnicas

- Motor: LÖVR 0.19. O lançamento adicionou suporte a Luau,
  tarefas assíncronas e novos recursos de GPU.
- Renderização atual: `lovr.graphics.newMesh` com `storage='gpu'`,
  malhas por material, greedy meshing e janela de visibilidade.
- As tarefas assíncronas do LÖVR ainda **não foram usadas**, pois o
  primeiro passo é manter geração determinística e uploads gráficos
  coordenados ao frame principal.
- Não existem occlusion culling avançado, LOD, shaders PBR, SSR,
  cascaded shadows ou iluminação volumétrica implementados.
- O estilo permanece voxel em blocos, mas **o mundo não é mais
  uma placa quadrada fixa**.

## Como testar

```sh
lua5.4 tests/streaming_64.lua
lua5.4 tests/world_basic.lua
lua5.4 tests/classic_basic.lua
lua5.4 tests/blocks_030.lua
lua5.4 tests/creatures_030.lua
lua5.4 tests/creepers_basic.lua
```

Em execução LÖVR, pressione **F3** para observar chunks visíveis,
quantidade de quads, cache e geração. Caminhe mais de 64 blocos do
spawn e volte. Confirme se edificações reaparecem exatamente como
antes, sem buracos nas bordas e sem travamentos relevantes.

Testes automatizados verificam somente lógica de chunks e simulação,
com GPU simulada por mocks. Testar FPS, perda de dispositivo, memória de
VRAM e comportamento de shaders ainda exige execução real no PC.

## Referências de engenharia

- [LÖVR 0.19](https://lovr.org/docs/v0.19.0) — novos recursos de
  Mesh e suporte a execução paralela.
- [LÖVR Mesh](https://lovr.org/docs/v0.19.0/Mesh) — malhas e vertex
  buffers na GPU.
- [Hytale Update 6](https://hytale.com/news/2026/8/update-6-patch-notes)
  — geração otimizada e prioridade na entrega de chunks próximos.

O Hytale é **referência de arquitetura**, não de implementação ou assets.
Nenhum código de Hytale ou Minecraft foi copiado.

## Próximas entregas para a maturidade pretendida

- Adaptar o renderer para occlusion/frustum culling e medir draw calls.
- Adicionar testes gráficos e captura automatizada em Windows/Linux.
- Separar geração CPU em tarefas paralelas com buffers imutáveis se o
  perfil de FPS justificar.
- Aumentar a altura vertical por subchunks, caves, iluminação e líquidos.
- Melhorar a simulação de entidades, spawn por bioma e persistência.
- Validar desempenho em hardware real, otimizar assets e corrigir bugs.
