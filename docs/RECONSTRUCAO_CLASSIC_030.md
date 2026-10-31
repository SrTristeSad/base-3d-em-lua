# Reconstrução Lua — Minecraft Classic 0.30 (10/11/2009)

## Pesquisa da versão histórica

A versão 0.30 foi lançada em duas variantes, **Creative** e
**Survival Test**, com diferenças sobretudo no modo de jogo.
As primeiras builds anteriores aos reuploads estão perdidas; as variantes
que ainda existem devem ser tratadas como software proprietário.

Referências consultadas:
- https://minecraft.wiki/w/Classic_0.30
- https://minecraft.wiki/w/Java_Edition_Survival_Test
- https://theminecraftwiki.com/wiki/history-of-world-generation/
- https://minecraft.wiki/w/Mob_spawning
- https://pt.minecraft.wiki/w/Edi%C3%A7%C3%A3o_Java_Classic_0.30

A documentação histórica associa Classic a escarpas abruptas,
praias de areia e cascalho, cavernas, veios minerais, lava junto da
rocha-mãe, árvores pequenas e algumas flores e cogumelos. No Survival
Test, creepers atacavam corpo a corpo e explodiam ao morrer; ovelhas
passaram a surgir legitimamente no Survival em 0.30.

**Limite da pesquisa:** esta etapa consultou documentação e imagens
públicas, sem executar ou descompilar um .jar do Minecraft 0.30. Não
copiamos assets nem os algoritmos internos originais. As formas de
ruído e as taxas de spawn são **aproximações novas**, não equivalência
pixel a pixel da versão histórica.

## Nova geração de terreno (`src/classic_terrain.lua`)

- Combina ruído de continentes, colinas, escarpas e detalhes locais.
- O nível do mar é 1 nas coordenadas deste projeto (não um valor
  usado pelo Minecraft original). A altitude foi adaptada ao
  intervalo vertical atualmente disponível: -32 a 63.
- Grama nas áreas secas, areia e cascalho nas praias; rocha exposta
  em planaltos altos. Não existem neve e desertos modernos nesse perfil.
- Cavernas em túneis determinísticos e veios distribuídos na rocha.
- Rocha-mãe na base e pequenas bolsas de lava junto ao fundo.
- Árvores e vegetação distribuídas determinística e esparsamente.
- Imagens PNG/JPG continuam possíveis: cores mudam a elevação
  e favorecem depressões, sem remover a base de relevo Classic.
- Cubic Chunks permanecem de 16×16×16, com greedy meshing, streaming
  e salvamento de edições sob demanda.

## Compatibilidade

O registro `worlds/index.txt` agora aceita o sexto campo,
`generatorVersion`. Um mundo novo possui `classic030`. Registros
antigos com cinco campos são abertos normalmente pelo gerador anterior.
Quando um arquivo antigo é regravado, o sexto campo fica `legacy`.
Não substitua manualmente `legacy` por `classic030`: isso alteraria
os blocos não editados e poderia comprometer construções.

## Spawn (`src/mob_spawning.lua`)

- No **Sobrevivência**, tentativas de nascimento acontecem por
  regiões de 16×16, próximas ao personagem, em pequenos grupos.
- Seleção determinística por seed e coordenada de chunk.
- Não aparecem dentro de blocos sólidos, em água nem a menos de 12
  blocos do jogador.
- Limite de 26 mobs ativos; a simulação mantém apenas os próximos.
- Descarrega os que estão a mais de 64 blocos (sem teletransporte).
- O mesmo chunk não realiza tentativas ilimitadas, evitando chuva
  instantânea de criaturas após derrotá-las.
- Espécies: porco, ovelha, zumbi, esqueleto, aranha e creeper.
- No **Criativo** não existe nascimento de criaturas.
- Mundos anteriores continuam com a população antiga; mudança só se
  aplica a novos mundos `classic030`.

As chances, limites e comportamento de despawn foram **adaptados**
à arquitetura infinita, não devem ser apresentados como as exatas
constantes do Minecraft Classic original. Sem ciclo completo de
iluminação e persistência de mobs, não seria fiel aplicar as regras
modernas de luz/noturno ao jogo de 2009.

## Testar

```sh
lua5.4 tests/classic_030_terrain.lua
lua5.4 tests/classic_030_spawning.lua
lua5.4 tests/worldgen_seed.lua
lua5.4 tests/streaming_64.lua
lua5.4 tests/cubic_chunks_3d.lua
```

No menu, crie um **mundo novo** para visualizar o novo gerador.
Os mundos anteriores não mudam. Caminhe e observe o nascimento de
criaturas em diferentes chunks e o desaparecimento dos mobs distantes.
O pipeline cria um EXE portátil Windows e um pacote `.lovr`, mas
somente a execução em GPU real verifica se o resultado visual ficou
próximo ao objetivo.

## Próximos sistemas de fidelidade

- Câmera, mão e efeitos de chuva e iluminação do Classic.
- Água/lava com comportamento semelhante ao Survival Test.
- Caves com ramificações e distribuição de minério calibradas
  comparando screenshots e gravações da versão histórica.
- Sons, efeitos de dano, disparo e recuperação de flechas dos esqueletos.
- Mobs com UVs, proporções, animações e lógica de navegação refinadas.
- Persistência de entidades por Cubic Chunk, com testes visuais.
