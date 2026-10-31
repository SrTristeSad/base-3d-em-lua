# Migração de base: VoxeLibre + Luanti

## Decisão técnica

O projeto anterior `base-3d-em-lua` usava Lua + LÖVR e tentava
reconstruir progressivamente o Minecraft Beta 1.8.1.
A partir desta migração o jogo principal usa **Lua + Luanti**
e incorpora a implementação completa do **VoxeLibre**.

Isso preserva em vez de reimplementar as suas mecânicas maduras:
sobrevivência, inventário, craft, biomas, mobs, agricultura,
combate, Nether, redstone, carrinhos, itens, música e multiplayer.
A lista completa de funcionalidades pertence ao código do VoxeLibre
e muda conforme revisões upstream.

## Fontes fixadas para reprodução

- Game: https://github.com/VoxeLibre/VoxeLibre
- Commit exato: `4492ce6ff8d856daa4567abe2ea689f4e7a39842`
- Engine: https://github.com/luanti-org/luanti
- Luanti Windows 64-bit: `5.18.0`
- SHA-256 do ZIP Windows:
  `bebce52b58555d8208bf16767d0717788479fef23c35ec8d7bf287774d641835`

O submódulo usa um commit exato, não uma branch mutável.
Para atualizar o jogo depois será necessário avaliar
compatibilidade e atualizar o submódulo explicitamente.

## Editar o projeto

- Com `git clone --recurse-submodules`, o jogo fica
  diretamente acessível em `games/voxelibre/`.
- Para fazer uma **versão própria editável e sustentável**,
  crie primeiro um fork upstream do VoxeLibre e aponte o URL
  do submódulo para seu fork; depois envie suas alterações
  para o fork e atualize o commit aqui. Alterar arquivos sem
  atualizar o submódulo não registra as alterações neste repo.
- O antigo `src/` LÖVR não executa no Luanti; portar
  extensões exige usar a API Lua do Luanti.
- Os saves `world.sav` do protótipo não são mundos Luanti.
  Não tente copiá-los diretamente para `worlds/`.
- Qualquer futuro projeto de Cubic Chunks exigirá estudo
  da API do motor/armazenamento; **não está pronto** só por
  adotar o VoxeLibre.

## Licenças

Os arquivos `LEGAL.md`, `LICENSE.txt` e `CREDITS.md` do
VoxeLibre são preservados dentro da distribuição em
`games/voxelibre/`. Seu código usa GPLv3 ou posterior.
Áudios, imagens e modelos têm atribuições/licenças adicionais.
Consulte sempre o LEGAL do commit distribuído.

O Luanti usa LGPLv2.1+. Redistribuir alterações e binários
requer respeitar as condições de cada componente.
Esta migração não concede direito sobre código ou ativos
do Minecraft/Mojang.

## Estado de validação

- CI testa o empacotador com uma engine fictícia e um
  minijogo de teste; verifica o checkout completo do submódulo.
- O pacote completo é montado com binário Luanti oficial e
  o jogo inteiro (sem remover mods).
- Não há garantia de operação gráfica até executar um
  teste manual de abertura do mundo, renderização e interação
  no Windows.
