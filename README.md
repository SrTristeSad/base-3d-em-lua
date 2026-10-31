# Base 3D em Lua — Reconstrução Beta 1.8.1 (em desenvolvimento)

Base independente de mundo 3D em blocos, escrita em **Lua** para **LÖVR 0.19** (Windows/Linux/macOS). Não precisa do Roblox nem de Minecraft.

**Versão jogável em desenvolvimento:** tela inicial, criação de mundos, geração por seed ou imagem e mundo procedural com streaming de chunks 16×16, 64×64 blocos carregados por padrão, árvores, terreno e água decorativa; renderização GPU com greedy meshing; controle em primeira pessoa com opção de terceira pessoa; quebrar/colocar blocos; barra de seleção; menus de início, pausa e configurações; sensibilidade, campo de visão, distância de renderização e tela cheia salvos; mundo e posição do jogador persistidos localmente.

## Nova referência: Minecraft Beta 1.8.1

A próxima etapa é uma **reconstrução independente da Beta 1.8.1**
em Lua/LÖVR, antes de implementar Cubic Chunks e geração de mundo
aprimorada. **A versão jogável atual ainda é o protótipo Classic 0.30**,
não uma reprodução Beta 1.8.1.

Leia o [plano de reconstrução e critérios de fidelidade](docs/BASELINE_BETA_181.md).
Consulte também [FUTURO.md](FUTURO.md), com **Cubic Chunks confirmado**
e uma pesquisa exploratória de oportunidades a partir do feedback da comunidade.
A geração por imagem foi retirada do planejamento futuro; ainda há
código legado para essa função no protótipo atual, que não foi removido.
Os saves existentes não serão migrados automaticamente.

## Novidade — Criar mundo com semente ou imagem

A tela inicial agora permite **criar, selecionar e continuar mundos
independentes**, no estilo de menu do Minecraft Classic.

- Escolha um nome, uma semente **numérica ou em texto** e Criativo/Sobrevivência.
- O mesmo texto/semente produz o mesmo terreno (versão fixa do gerador);
  sementes diferentes geram mundos diferentes.
- Opcional: **use uma imagem PNG ou JPG para gerar o mapa**. Cores e
  brilho influenciam vales, lagos, florestas, desertos e neve; a
  topografia continua procedural para parecer um mundo natural.
- Inclui uma **imagem de exemplo pronta** para testar imediatamente
  sem copiar nenhum arquivo externo.
- Para fotos pessoais, coloque o PNG/JPG na pasta `maps` do save
  e selecione na interface. O save memoriza uma amostra de 64×64
  pixels, para a foto original não precisar continuar disponível.
- Os arquivos de mundos ficam em `worlds/` e não sobrescrevem o
  `world.sav` antigo. O sistema suporta até 96 mundos listados.

**Guia completo:** [Sementes e imagens](docs/SEMENTES_E_IMAGENS.md).

## Referencia escolhida: Minecraft Classic 0.30

O sandbox usa como **referencia de comportamento** o Minecraft Classic
0.30 (10/11/2009), que possui duas variantes. No menu, escolha entre:

- **Sobrevivencia 0.30:** creepers atacam corpo a corpo, **so explodem ao
  morrer**, saude de 20 pontos, pontuacao por derrota, coleta com estoque
  finito (pilhas de 99), colocacao consome itens.
- **Criativo 0.30:** construcao ilimitada sem criaturas hostis.
- Ambos compartilham o mesmo mundo; modo, pontuacao e quantidades por bloco
  sao salvos no `world.sav` (os arquivos anteriores continuam aceitos).

A base reproduz **parte** das regras dessa epoca, nao todo o jogo original.
A maior parte dessas categorias ja existe em versao simplificada.
Ainda faltam IA e animacoes mais fiéis, arco do jogador, geracao de cavernas,
formas nao-cubicas para flores e lajes, liquidos dinamicos e os ajustes
necessarios para uma reproducao mais fiel do Classic 0.30.
Nao ha crafting moderno, e as regras/arte sao independentes.

**Controles adaptados:** F5 alterna camera 1a/3a pessoa neste projeto,
apesar de no Classic original controlar chuva. Os creepers NAO explodem
simplesmente por se aproximar nesta versao, diferentemente de um creeper
moderno. Os blocos coletados que possuem drop disponivel alimentam
a barra e o estoque de 99 unidades.

## Nova arquitetura Cubic Chunks: streaming 3D de seções 16×16×16

O mapa **deixou de ser um quadrado fixo 48×48**. A região de spawn antiga
continua como referencia para mobs iniciais, mas terreno e construcoes
podem se estender por uma area muito maior (limite de seguranca:
±1.048.575 blocos nos eixos X/Z).

- Geração procedural determinística sob demanda, dividida em seções cúbicas de **16×16×16** blocos.
- **Janela padrão 64×64×48 blocos** em torno do jogador (**4×4×3 = 48 seções cúbicas**).
- Distância horizontal configurável: 64×64, 96×96 ou 128×128 blocos;
  carregamento vertical limitado a três seções ao redor do personagem.
- Carregamento por proximidade **tridimensional**, limitado a três seções
  de GPU por frame para reduzir travamentos.
- Descarregamento horizontal **e vertical** de seções distantes e
  liberação de malhas GPU.
- **Greedy meshing:** faces contíguas do mesmo material viram retângulos,
  em vez de milhares de quads independentes; redução de geometria sobretudo
  em superfícies planas.
- O save grava apenas os blocos modificados. Ao voltar, a seção cúbica
  é regenerada, e as alterações previamente salvas são reaplicadas.
- Zumbis, ovelhas, porcos e demais criaturas próximas são reaproveitadas
  quando o jogador viaja para outra região, sem criar hordas ilimitadas.
- **F3** mostra chunks visíveis, quads de geometria, cache e contador de geração.
- Testes verificam geração após 480 blocos de distância, persistência
  em Y=45 e Y=-16, recarga, descarregamento vertical e greedy meshing.

A altura experimental foi ampliada para **Y=-32 até 63**, incluindo
cavernas simples abaixo da superfície. **Isso ainda não é um mundo com
altura ilimitada, nem um motor 98% finalizado.**

O motor continua sendo **LÖVR 0.19 / Lua**, com buffers GPU de malhas.
A versão 0.19 suporta também Luau, tarefas assíncronas e novos recursos
de renderização, mas **não declaramos que estão integrados**: a geração
atual usa orçamento controlado por quadro. Ver
[arquitetura de streaming](docs/CHUNK_STREAMING.md).

## Novidades: criaturas e blocos do Classic 0.30

- Criaturas **zumbi, esqueleto, aranha, porco e ovelha** renderizadas em cubos,
  com IA basica. Esqueletos lancam projeteis; animais passivos perambulam.
  O creeper original continua no Survival e explode quando e morto.
- **Catalogo de 46 blocos/variantes**, incluindo minerios, vidro, TNT,
  cogumelos, flores, saplings, obsidiana, lava decorativa, estante,
  pedregulho, lajes visuais e 16 cores de la.
- **TNT funcional:** clique esquerdo em TNT no Survival acende o pavio,
  clique direito na entidade armada desarma, detonacoes podem ativar outras TNTs.
- **6 paginas de blocos (TAB)**, com 8 itens na barra por pagina.
  Inventario salva todos os 46 IDs, sem destruir saves antigos.
- **Cogumelos curativos:** E consome um cogumelo quando a vida estiver baixa.
- Geracao deterministica de pequenos veios minerais e flores no terreno.
  As formas de decoracao ainda sao blocos inteiros; modelos de
  saplings/flores e fluxo de lava serao aprimorados mais adiante.

## O que ja foi implementado

- Mundo voxel procedural em chunks, com árvores, areia, água, mineração, construção e salvamento local.
- **5 creepers** originais em blocos (somente no modo Sobrevivencia): surgem longe do spawn, perseguem o jogador,
  **atacam de perto e explodem ao serem derrotados**, como no Survival Test 0.30.
- As explosões removem blocos editáveis próximos (as alterações são salvas).
  Água, camada de fundo e ponto de nascimento ficam protegidos.
- Os creepers podem ser derrotados com **quatro golpes**, acionando a explosao;
  o ataque usa a mira do jogador e alcance de aproximadamente quatro blocos.
- Barra de **20 pontos de vida**, imunidade curta apos levar dano,
  tela de morte e renascimento com **R**.
- Salvamento automatico a cada 45 segundos enquanto estiver jogando,
  incluindo os blocos coletados, o modo e a pontuacao.
- Câmera em primeira pessoa e terceira pessoa, seleção de oito blocos,
  texturas PNG personalizadas, skin 64×64, menus e configurações.
- Projeto **independente em Lua**, sem Roblox Studio.

**Limitações atuais:** jogo local, sem crafting, com IA simplificada de criaturas,
inventário limitado, iluminação dinâmica incompleta, física de líquidos estática
e sem multiplayer.
Embora os testes de lógica e sintaxe sejam executados automaticamente,
a renderização e os controles ainda precisam ser testados num PC com
LÖVR 0.19 e Vulkan. Não é uma reprodução completa de Minecraft.

## Reconstrução da geração e do nascimento de mobs do Classic 0.30

A partir desta atualização, **somente mundos novos** usam o gerador
`classic030` inspirado no visual de 2009. Os saves anteriores mantêm
o gerador antigo graças a uma versão persistente no catálogo.

- **Terreno clássico:** costas, praias de areia e cascalho, relevo
  ondulado, escarpas de rocha, cavernas com túneis, camadas de terra,
  minérios e pequenos bolsões de lava na base.
- **Sem biomas modernos por padrão:** o modo Classic não distribui
  neve/desertos modernos como se fossem sistemas da versão de 2009.
- **Semente + foto:** continuarão funcionando juntas; a foto modifica
  as colinas e a costa, mas o mundo mantém estética Classic.
- **Spawn regional de mobs:** no Sobrevivência, os animais e inimigos
  nascem em pequenos grupos nas regiões próximas, respeitam distância
  mínima do jogador e limites de população.
- **Streaming de entidades:** criaturas distantes são descarregadas, sem
  teletransporte artificial para perto do personagem. O Criativo não
  cria mobs hostis nem passivos.
- **Compatibilidade:** os mundos antigos continuam usando seu terreno e
  o comportamento anterior de criaturas. Esta nova implementação é
  exclusiva de mundos gerados com o perfil `classic030`.

Isso é uma **reconstrução independente baseada em documentação e capturas
do Survival Test 0.30**, não engenharia reversa exata do arquivo original.
A frequência e a posição de surgimento dos mobs ainda são aproximações.
Veja o [relatório técnico](docs/RECONSTRUCAO_CLASSIC_030.md).

## Atualização — Visão FPS e skins de criaturas

- **Visão FPS corrigida:** mouse relativo com sensibilidade ajustável,
  proteção contra saltos ao recuperar foco e ângulo vertical de ±89°.
- **Visão de terceira pessoa:** a câmera recua apenas até onde não
  encontra paredes. F5 alterna entre primeira e terceira pessoa.
- **Inverter eixo X/Y:** opções novas em Configurações; é possível
  usar a orientação natural ou invertida do mouse.
- **Seis mobs com malhas UV texturizadas:** creeper, zumbi, esqueleto,
  aranha, porco e ovelha, com cabeça, corpo e membros separados.
- **Skins personalizadas:** arquivos PNG 64×32 ou 64×64 podem substituir
  a textura de qualquer mob. Na ausência, o jogo cria textura original
  pixelada automaticamente, sem distribuir arquivos oficiais de Minecraft.

Confira [SKINS_MOBS.md](docs/SKINS_MOBS.md). O visual das criaturas
ainda é **inspirado e aproximado**, não idêntico aos modelos de 2009.

## Testar no Windows sem instalar o motor

O GitHub Actions agora gera **dois arquivos de teste**:
- `Base3D-Sementes-Imagens-Windows-EXE`: ZIP para Windows 64 bits.
  Extraia tudo e abra `Base3D-Sementes-Imagens.exe` com duplo clique.
  O pacote traz as DLLs do runtime LÖVR v0.19.0.
- `Base3D-Sementes-Imagens-LOVR`: ZIP com o projeto `.lovr`
  para usar com uma instalacao de LÖVR que voce ja possua.

A versao Windows e um executavel fundido, feito conforme as
[instrucoes oficiais de distribuicao](https://lovr.org/docs/v0.19.0/Distribution).
Ainda exige Windows 10+ 64 bits, driver Vulkan funcional e possivelmente
Microsoft Visual C++ Runtime. O arquivo nao esta assinado digitalmente.
O workflow verifica integridade e empacotamento; **a interface e o render
3D ainda precisam de teste pratico** em computador com GPU.

## Baixar a versao jogavel

Na pagina [GitHub Actions](https://github.com/SrTristeSad/base-3d-em-lua/actions/workflows/lua-check.yml),
abra a execucao mais recente **aprovada** e baixe o artefato
`Base3D-Sementes-Imagens-LOVR`. Extraia o arquivo
`Base3D-Sementes-Imagens.lovr`. E um jogo empacotado (ZIP renomeado)
para o motor LÖVR; no Windows, arraste o arquivo `.lovr` sobre
`lovr.exe` baixado do site oficial. O pacote inclui as texturas,
scripts e configuracoes. Nao inclui o executavel do motor nem salva dentro
do proprio arquivo.

## Executar

1. Baixe o LÖVR 0.19 em https://lovr.org/ (Vulkan).
2. Baixe este projeto em **Code > Download ZIP** e extraia.
3. No Windows, **arraste a pasta do projeto sobre o `lovr.exe`**, ou use `lovr.exe caminho/da/pasta`. Não é preciso instalar Roblox Studio.
4. Se o Windows bloquear, use o LÖVR da página oficial e mantenha todos os arquivos DLL ao lado do executável.

## Controles

| Tecla | Ação |
|---|---|
| WASD | Mover |
| Mouse | Olhar (capturado quando joga) |
| Espaço | Pular |
| Shift | Correr |
| Botão esquerdo | Quebrar bloco / atacar creeper sob a mira |
| Botão direito | Colocar bloco |
| Teclas 1–8 / roda | Selecionar bloco da pagina atual |
| TAB | Trocar pagina de blocos |
| E | Comer cogumelo no modo Sobrevivencia |
| Clique esquerdo em TNT | Acender TNT no Sobrevivencia |
| Clique direito em TNT acesa | Desarmar TNT |
| F5 | Alternar 1ª e 3ª pessoa |
| Esc | Pausar / abrir menu |
| F6 | Salvar imediatamente |
| F3 | Mostrar/ocultar estatísticas de chunks e geometria |
| R (ao morrer) | Renascer com a vida restaurada |

A tela inicial tem **Jogar**, **Configurações** e **Sair**. No menu de pausa, você pode **Salvar**, retornar ao menu e continuar.

## Skins e texturas

- Substitua o visual de cada bloco com um PNG em `assets/textures/NOME.png` (por exemplo, `grass_top.png`, `stone.png`, `wood_side.png`). A lista completa está em `src/textures.lua`. Texturas de 16×16 com transparência ou resoluções maiores são aceitas.
- Coloque sua **skin de personagem 64×64** em `assets/skins/player.png` e pressione **F5** para vê-la na terceira pessoa.
- O projeto agora vem com 11 texturas CC0 de blocos do [Kenney Voxel Pack](https://kenney.nl/assets/voxel-pack)
  (grama, terra, pedra, tronco, folhas, areia, madeira, tijolos e agua).
  Atribuicao opcional e licenca CC0. Texturas oficiais do Minecraft nao sao redistribuidas.
- Na ausência de PNGs, a base gera texturas pixeladas originais automaticamente. O projeto funciona sem pacotes externos de arte.
- Reinicie para recarregar texturas/skins alteradas.

## Arquitetura

```
main.lua             loop, menus, render e controles
conf.lua             janela, módulos e identidade
src/world.lua        geração procedural e cache 3D de seções cúbicas + salvamento
src/mesher.lua       greedy meshing, streaming prioritizado e liberação GPU
src/textures.lua     PNGs externos e fallback procedural
src/player.lua       movimento, colisão e seleção
src/avatar.lua       skin 64×64 do jogador
src/ui.lua           menu e interface 2D
src/creepers.lua     IA, ataque, explosao e modelo cubico dos creepers
src/classic.lua      modos Creative/Survival, drops, estoque de 99 e pontuacao
src/creatures.lua    zumbi, esqueleto, aranha, porco e ovelha
src/tnt.lua          TNT acesa, desarme, explosoes em cadeia
assets/              pasta livre para seus PNGs
```

Os arquivos de save são escritos no diretório de dados do usuário administrado por `lovr.filesystem`, não dentro do ZIP. O progresso não é sincronizado entre computadores.

## Referência e direitos

Este é um **projeto original e independente**. Como referência de funcionalidades do gênero voxel, foi consultado [VintageCube](https://github.com/VintageCube/VintageCube), um projeto Roblox licenciado sob AGPL-3.0. **Nenhum arquivo de código ou arte do VintageCube/Minecraft foi copiado para esta base**; as APIs e a implementação são próprias. O código autoral deste repositório é distribuído sob MIT. Skins e texturas importadas são responsabilidade de seus respectivos autores.

> Estado: sandbox funcional no código e testável sem Roblox. A jogabilidade 3D
> ainda requer verificação manual no LÖVR; sem multiplayer ou crafting.
