# Base 3D em Lua — VoxeLibre completo (Luanti)

**Base principal atual: [VoxeLibre](https://github.com/VoxeLibre/VoxeLibre)**,
com motor **[Luanti](https://www.luanti.org/)**. A partir desta migração,
não vamos reconstruir blocos, IA, crafting ou dimensões do zero.
Vamos aproveitar a implementação existente, com todos os mods e recursos
do jogo, e desenvolver nossas alterações em cima dela.

> **Importante:** VoxeLibre não é uma cópia exata do Minecraft Java
> Beta 1.8.1. É um jogo independente, jogável, com recursos próprios
> e de versões diferentes de Minecraft. A direção futura do projeto
> (por exemplo, mudanças de geração e Cubic Chunks) ainda será
> definida e implementada, não está presente por padrão.

## Novo desenvolvimento: motor Luanti em Lua (experimental)

Começamos a reconstrução de um motor voxel **em Lua**, visando
compatibilidade progressiva com a API Luanti e o VoxeLibre.
O código independente fica em [`lua-engine/`](lua-engine/README.md).

**Esta versão experimental ainda não executa o VoxeLibre.**
Já contém armazenamento de blocos, metadados, timers, callbacks,
registros de nós/itens, `ItemStack`, inventários de nós, salvamento
de inventários, um loader inicial de mods por `mod.conf` e um
sistema de crafting com receitas e grupos, além de
uma cena 3D editável usando
o LÖVR somente como backend gráfico.

[Baixar a demonstração Lua para Windows](../../actions/workflows/lua-engine-port.yml)
e [acompanhar a matriz de compatibilidade](docs/ENGINE_LUA_PORT.md).

A distribuição funcional e completa com o Luanti original continua
disponível abaixo, sem alterações.

## Baixar e jogar no Windows

1. Vá à [aba Actions — VoxeLibre completo](../../actions/workflows/voxelibre-windows.yml)
   e abra a execução verde mais recente.
2. Em **Artifacts**, baixe **Base3D-VoxeLibre-Completo-Windows-x64**.
3. Extraia **toda** a pasta e execute `JOGAR-VOXELIBRE.bat`.
4. No menu do Luanti, selecione **VoxeLibre**, crie um mundo e jogue.

O pacote inclui o motor Luanti Windows **5.18.0** e a cópia
**integral** do VoxeLibre (mods, texturas, sons, modelos e
dados). Não exige instalação separada do motor. É necessário
Windows 64 bits e gráficos compatíveis com Luanti. O trabalho foi
empacotado e verificado automaticamente; o teste visual em uma
máquina Windows real precisa ser feito.

## Baixar e modificar todo o código

Clone **com submódulo** para obter o código do VoxeLibre junto:

```sh
git clone --recurse-submodules https://github.com/SrTristeSad/base-3d-em-lua.git
```

O código original do VoxeLibre está em `games/voxelibre/` (fixado
em um commit upstream para builds reproduzíveis). Se você baixar
somente o **ZIP do repositório** no GitHub, o ZIP **não inclui**
os arquivos do submódulo; nesse caso execute
`scripts/Instalar-VoxeLibre.cmd` no Windows para baixá-los.

Para usar o jogo com um Luanti já instalado, copie a pasta
`games/voxelibre/` para `games/voxelibre/` no diretório
de dados do Luanti ou instale VoxeLibre pelo ContentDB.

**Todas as funcionalidades do VoxeLibre continuam disponíveis**
pela própria estrutura do jogo, incluindo sobrevivência, criativo,
criaturas, agricultura, crafting, redstone, Nether, trilhos,
multiplayer e mods. Não desabilitamos módulos para construir o
pacote. Consulte também [GETTING_STARTED upstream](https://github.com/VoxeLibre/VoxeLibre/blob/master/GETTING_STARTED.md).

## Arquitetura e manutenção

- `games/voxelibre/`: **VoxeLibre completo**, submódulo Git.
- `scripts/package_voxelibre.py`: pacote Windows reproduzível,
  com verificação do motor e dos recursos originais.
- `.github/workflows/voxelibre-windows.yml`: CI de embalagem
  e testes. Baixa o Luanti 5.18.0 oficial com SHA-256 verificado.
- `src/`, `main.lua`, `tests/beta181_*.lua`: código histórico
  do protótipo LÖVR. Não é o motor atual nem é automaticamente
  integrado ao Luanti.
- Branch [`legacy/lovr-phase-10`](../../tree/legacy/lovr-phase-10):
  versão antiga preservada. Históricos de desenvolvimento estão
  em [`docs/README_LOVR_ARCHIVE.md`](docs/README_LOVR_ARCHIVE.md).

[Detalhes de instalação, licenciamento e evolução](docs/MIGRACAO_VOXELIBRE.md).

## Créditos e licenças

VoxeLibre é desenvolvido pela comunidade; **não** é de autoria
exclusiva deste repositório. O código é licenciado sob a GPLv3 ou
posterior; arquivos de mídia têm licenças próprias (como Creative
Commons) descritas no `LEGAL.md`. Preserve os créditos
`CREDITS.md`, as licenças e a disponibilidade do código-fonte
em distribuições derivadas.

O motor Luanti tem sua própria licença, LGPLv2.1+.
Consulte os documentos originais incluídos nos projetos.
Não redistribua o jogo como software proprietário fechado.
