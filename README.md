# Base 3D em Lua — Classic Sandbox com Creepers

Base independente de mundo 3D em blocos, escrita em **Lua** para **LÖVR 0.19** (Windows/Linux/macOS). Não precisa do Roblox nem de Minecraft.

**Versão jogável em desenvolvimento:** mundo procedural com streaming de chunks 16×16, 64×64 blocos carregados por padrão, árvores, terreno e água decorativa; renderização GPU com greedy meshing; controle em primeira pessoa com opção de terceira pessoa; quebrar/colocar blocos; barra de seleção; menus de início, pausa e configurações; sensibilidade, campo de visão, distância de renderização e tela cheia salvos; mundo e posição do jogador persistidos localmente.

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

## Nova arquitetura de mundo infinito com streaming 64×64

O mapa **deixou de ser um quadrado fixo 48×48**. A região de spawn antiga
continua como referencia para mobs iniciais, mas terreno e construcoes
podem se estender por uma area muito maior (limite de seguranca:
±1.048.575 blocos nos eixos X/Z).

- Geração procedural determinística sob demanda, dividida em chunks de 16×16.
- **Janela padrão 64×64 blocos** em torno do jogador (4×4 chunks).
- Distância configurável: 64×64, 96×96 ou 128×128 blocos.
- Carregamento priorizado pela proximidade e limitado a dois chunks GPU
  por frame, para reduzir travamentos.
- Descarregamento de chunks distantes e liberação de malhas GPU.
- **Greedy meshing:** faces contíguas do mesmo material viram retângulos,
  em vez de milhares de quads independentes; redução de geometria sobretudo
  em superfícies planas.
- O save grava apenas os blocos modificados. Ao voltar, o terreno é
  regenerado, e as alterações previamente salvas são reaplicadas.
- Zumbis, ovelhas, porcos e demais criaturas próximas são reaproveitadas
  quando o jogador viaja para outra região, sem criar hordas ilimitadas.
- **F3** mostra chunks visíveis, quads de geometria, cache e contador de geração.
- Testes verificam geração após 480 blocos de distância, persistência de
  alterações, recarga de regiões, descarregamento de memória e meshing.

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

## Baixar a versao jogavel

Na pagina [GitHub Actions](https://github.com/SrTristeSad/base-3d-em-lua/actions/workflows/lua-check.yml),
abra a execucao mais recente **aprovada** e baixe o artefato
`Base3D-Classic-030-Streaming64-LOVR`. Extraia o arquivo
`Base3D-Classic-030-Streaming64.lovr`. E um jogo empacotado (ZIP renomeado)
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
src/world.lua        geração procedural, cache espacial de chunks + salvamento
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
