# Cubic Chunks — streaming tridimensional de mundo voxel

## O que foi implementado

O mundo da base Lua passou de geração em colunas 16×16 e altura completa para
**seções cúbicas 16×16×16**, com cache indexado por `cx:cy:cz`. A ideia é
semelhante ao projeto CubicChunks e à arquitetura 3D anunciada pelo Hytale.
Não reutiliza seus arquivos nem seus códigos.

- Janela de renderização padrão: 4×4 chunks na horizontal, ou **64×64 blocos**.
- Janela vertical: seção atual e seções imediatamente acima/abaixo,
  **48 blocos de altura** carregados ao redor do jogador (3 seções).
- Janela padrão: **4×4×3 = 48 seções cúbicas**; se a câmera estiver no
  limite Y, menos seções poderão ser renderizadas.
- Alcance horizontal configurável: 64×64, 96×96 ou 128×128 blocos.
- Orçamento de até três seções de malha nova por frame em jogo, seis no
  carregamento inicial e duas por frame para o panorama do menu.
- Prioridade pela distância tridimensional em **chunks**.
- Regiões distantes são removidas do cache CPU e suas malhas GPU são liberadas.
- Edições persistem em um overlay de blocos, indexado também pela altura.
- A geração é determinística e inclui cavernas básicas no subsolo.
- Limites atuais do mundo: **Y −32..63** e X/Z ±1.048.575;
  altura e profundidade verdadeiramente ilimitadas **não** estão prontas.

## Pipeline

1. `World:get(x,y,z)` calcula `floor(x/16),floor(y/16),floor(z/16)`.
2. `World:generateSection(cx,cy,cz)` gera **só os 4096 voxels
   possíveis naquela seção**, sem gerar a coluna vertical completa.
   Voxels de ar não ocupam um item individual na tabela Lua.
3. `World:load()` lê as alterações do jogador; o formato legível
   `BLOCK x y z id` é compatível com saves de versões anteriores.
4. `Mesher.buildData(world,cx,cy,cz,faces)` percorre seis faces
   cúbicas e faz greedy meshing de retângulos coplanares por textura.
5. `Mesher:sync(px,py,pz,view,budget)` escolhe as seções em três
   dimensões, ordena as pendentes por distância e cria poucas malhas
   GPU em cada quadro.
6. `World:prune(px,py,pz,horizontal,vertical)` descarta os
   caches fora da janela + margem de consulta; voltar a uma seção
   a regenera e reaplica as edições salvas.
7. Monstros são reposicionados ao redor do jogador quando ele se afasta
   muito da região anterior, mantendo quantidade limitada de entidades.

## Testes

```sh
lua5.4 tests/streaming_64.lua
lua5.4 tests/cubic_chunks_3d.lua
lua5.4 tests/world_basic.lua
lua5.4 tests/blocks_030.lua
lua5.4 tests/creatures_030.lua
```

Os testes incluem: uma plataforma sintética que deve virar só seis
quads após greedy meshing; janela de 48 seções ao redor do jogador;
carregar longe do spawn; descarregar e recuperar chunks GPU; editar no
Y=45 e Y=-16; atravessar fronteiras de seção e reabrir o save.

A verificação automática **não é teste gráfico de Vulkan**. FPS, VRAM,
folhagens, transparência e desempenho ao andar rápido continuam exigindo
teste no PC com LÖVR 0.19.

## Próximas evoluções

1. Mais profundidade vertical por geração de bioma/cavernas e iluminação 3D.
2. Frustum e occlusion culling para reduzir draw calls.
3. Material de voxel em atlas, ao invés de uma malha por textura.
4. Medições reais de frame pacing, FPS, GPU e RAM.
5. Uso de tarefas assíncronas LÖVR quando os dados e os perfis de
   performance justificarem, preservando a sincronização GPU no thread gráfico.
6. Entidades e física organizadas por seção, com persistência por região.

## Referências

- [CubicChunks](https://modrinth.com/mod/cubicchunks)
- [Hytale — First Look: Chapter 1 and More](https://hytale.com/news/2026/7/first-look-chapter-1-and-more)
- [LÖVR 0.19](https://lovr.org/docs/v0.19.0)

Essa base não copia o motor nem os assets desses jogos.
