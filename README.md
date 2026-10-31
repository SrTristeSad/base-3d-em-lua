# Base 3D em Lua — Classic Sandbox com Creepers

Base independente de mundo 3D em blocos, escrita em **Lua** para **LÖVR 0.19** (Windows/Linux/macOS). Não precisa do Roblox nem de Minecraft.

**Versão jogável em desenvolvimento:** mundo procedural com árvores, terreno e água decorativa; renderização por malha de faces visíveis; controle em primeira pessoa com opção de terceira pessoa; quebrar/colocar blocos; barra de seleção; menus de início, pausa e configurações; sensibilidade, campo de visão, distância de renderização e tela cheia salvos; mundo e posição do jogador persistidos localmente.

## O que ja foi implementado

- Mundo voxel procedural 48×48 com árvores, areia, água, mineração, construção e salvamento local.
- **5 creepers** originais em blocos: surgem longe do spawn, perseguem o jogador,
  iniciam o pavio quando se aproximam e explodem após cerca de 1,55 segundo.
- As explosões removem blocos editáveis próximos (as alterações são salvas).
  Água, camada de fundo e ponto de nascimento ficam protegidos.
- Os creepers podem ser derrotados com **quatro golpes** antes de explodirem;
  o ataque usa a mira do jogador e alcance de aproximadamente quatro blocos.
- Barra de **20 pontos de vida**, imunidade curta após levar dano,
  tela de morte e renascimento com **R**.
- Salvamento automático a cada 45 segundos enquanto estiver jogando.
- Câmera em primeira pessoa e terceira pessoa, seleção de oito blocos,
  texturas PNG personalizadas, skin 64×64, menus e configurações.
- Projeto **independente em Lua**, sem Roblox Studio.

**Limitações atuais:** jogo local, sem crafting, animais passivos,
inventário limitado, iluminação dinâmica, física de líquidos ou multiplayer.
Embora os testes de lógica e sintaxe sejam executados automaticamente,
a renderização e os controles ainda precisam ser testados num PC com
LÖVR 0.19 e Vulkan. Não é uma reprodução completa de Minecraft.

## Baixar a versao jogavel

Na pagina [GitHub Actions](https://github.com/SrTristeSad/base-3d-em-lua/actions/workflows/lua-check.yml),
abra a execucao mais recente **aprovada** e baixe o artefato
`Base3D-Classic-Creeper-LOVR`. Extraia o arquivo
`Base3D-Classic-Creeper.lovr`. E um jogo empacotado (ZIP renomeado)
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
| Teclas 1–8 / roda | Selecionar bloco |
| F5 | Alternar 1ª e 3ª pessoa |
| Esc | Pausar / abrir menu |
| F6 | Salvar imediatamente |
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
src/world.lua        terreno e blocos + salvamento
src/mesher.lua       malhas de faces visíveis por material
src/textures.lua     PNGs externos e fallback procedural
src/player.lua       movimento, colisão e seleção
src/avatar.lua       skin 64×64 do jogador
src/ui.lua           menu e interface 2D
src/creepers.lua     IA, ataque, explosao e modelo cubico dos creepers
assets/              pasta livre para seus PNGs
```

Os arquivos de save são escritos no diretório de dados do usuário administrado por `lovr.filesystem`, não dentro do ZIP. O progresso não é sincronizado entre computadores.

## Referência e direitos

Este é um **projeto original e independente**. Como referência de funcionalidades do gênero voxel, foi consultado [VintageCube](https://github.com/VintageCube/VintageCube), um projeto Roblox licenciado sob AGPL-3.0. **Nenhum arquivo de código ou arte do VintageCube/Minecraft foi copiado para esta base**; as APIs e a implementação são próprias. O código autoral deste repositório é distribuído sob MIT. Skins e texturas importadas são responsabilidade de seus respectivos autores.

> Estado: sandbox funcional no código e testável sem Roblox. A jogabilidade 3D
> ainda requer verificação manual no LÖVR; sem multiplayer ou crafting.
