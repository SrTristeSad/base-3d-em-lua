# Base 3D em Lua — Voxel Sandbox

Base independente de mundo 3D em blocos, escrita em **Lua** para **LÖVR 0.19** (Windows/Linux/macOS). Não precisa do Roblox nem de Minecraft.

**Primeira versão:** mundo procedural com árvores, terreno e água decorativa; renderização por malha de faces visíveis; controle em primeira pessoa com opção de terceira pessoa; quebrar/colocar blocos; barra de seleção; menus de início, pausa e configurações; sensibilidade, campo de visão, distância de renderização e tela cheia salvos; mundo e posição do jogador persistidos localmente.

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
| Botão esquerdo | Quebrar bloco |
| Botão direito | Colocar bloco |
| Teclas 1–8 / roda | Selecionar bloco |
| F5 | Alternar 1ª e 3ª pessoa |
| Esc | Pausar / abrir menu |
| F6 | Salvar imediatamente |

A tela inicial tem **Jogar**, **Configurações** e **Sair**. No menu de pausa, você pode **Salvar**, retornar ao menu e continuar.

## Skins e texturas

- Substitua o visual de cada bloco com um PNG em `assets/textures/NOME.png` (por exemplo, `grass_top.png`, `stone.png`, `wood_side.png`). A lista completa está em `src/textures.lua`. Texturas de 16×16 com transparência ou resoluções maiores são aceitas.
- Coloque sua **skin de personagem 64×64** em `assets/skins/player.png` e pressione **F5** para vê-la na terceira pessoa.
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
assets/              pasta livre para seus PNGs
```

Os arquivos de save são escritos no diretório de dados do usuário administrado por `lovr.filesystem`, não dentro do ZIP. O progresso não é sincronizado entre computadores.

## Referência e direitos

Este é um **projeto original e independente**. Como referência de funcionalidades do gênero voxel, foi consultado [VintageCube](https://github.com/VintageCube/VintageCube), um projeto Roblox licenciado sob AGPL-3.0. **Nenhum arquivo de código ou arte do VintageCube/Minecraft foi copiado para esta base**; as APIs e a implementação são próprias. O código autoral deste repositório é distribuído sob MIT. Skins e texturas importadas são responsabilidade de seus respectivos autores.

> Estado: primeira implementação de desenvolvimento; ainda requer execução/teste gráfico em um PC com LÖVR e Vulkan. Não é um jogo completo nem possui multiplayer.
