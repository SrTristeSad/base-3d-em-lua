# Skins UV dos mobs — Classic 0.30

O renderizador do projeto agora aceita **atlas de textura por criatura**,
em vez de se limitar a cubos com cores sólidas. É uma implementação
original de caixas texturizadas, no formato de UV pixel art 64×32 ou 64×64.

## Arquivos opcionais

Insira suas próprias texturas PNG nesta pasta, antes de recompilar o
projeto .lovr e o executável Windows:

```text
assets/skins/mobs/
  creeper.png
  zombie.png
  skeleton.png
  spider.png
  pig.png
  sheep.png
```

São aceitos PNGs **64×32 ou 64×64 pixels**. São os arquivos que
substituem as skins geradas automaticamente no jogo.

O atlas segue a convenção de cubo aberto:
topo e fundo na primeira faixa, esquerda, frente, direita e trás na
segunda faixa. A frente da cabeça começa em X=8, Y=8
e possui largura de 8 pixels; tronco, pernas e braços usam regiões
separadas. Os braços e pernas dos modelos humanoides são cubos distintos,
capazes de movimentação simples.

**Observação:** o sistema é **compatível em conceito e dimensão com
skins clássicas**, mas ainda NÃO tem mapeamento exato para todos os
modelos e variantes originais do Minecraft de 2009.
Pig, Sheep e Spider usam UVs adaptados às dimensões da malha própria,
portanto um PNG obtido para um modelo original pode precisar de
edição ou reposicionamento das regiões para encaixar corretamente.
As texturas oficiais da Mojang **não estão incluídas**; use apenas
texturas que você tem direito de utilizar.

O fallback cria seis texturas pixeladas próprias no carregamento. O
jogo não depende da internet, de Roblox ou de sites de skin. O pacote
de instalação é autocontido.

## Câmera e controle

O controle usa mouse em modo relativo, sem inércia. Virar o mouse para
a direita deve fazer a visão virar para a direita. Mover para cima deve
olhar para cima. O ângulo vertical é limitado a ±89 graus.

Agora estão disponíveis em Configurações:

- Sensibilidade Baixa / Média / Alta / Muito Alta.
- Inverter o eixo horizontal e/ou vertical.
- Campo de visão (FOV).
- Distância de visão.

No modo em terceira pessoa (F5), uma verificação de colisões evita que a
câmera atravesse uma parede ou fique dentro de blocos. Uma troca do modo
normal para mouse relativo descarta o primeiro delta para reduzir saltos
ao abrir o jogo ou voltar de um menu.

O objetivo é aproximar a movimentação da sensação do Minecraft Classic,
mas ainda será necessário validar o comportamento no Windows em uma GPU
real, principalmente sensibilidade em diferentes taxas de FPS e DPI.

## Regressão

```sh
lua5.4 tests/camera_fps.lua
lua5.4 tests/mob_skins_uv.lua
```

Os testes usam mocks: verificam orientação da câmera, limites, inversões,
colisões, UVs, fallback, carregamento de PNG e geometria.
Não equivalem à verificação visual em LÖVR.
