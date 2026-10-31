# Criacao de mundos — seed ou imagem

## Como testar agora

1. No GitHub Actions, baixe o artefato `Base3D-Sementes-Imagens-LOVR`
   e extraia `Base3D-Sementes-Imagens.lovr`.
2. Baixe o LÖVR 0.19 de https://lovr.org e arraste o arquivo `.lovr`
   sobre o executavel `lovr.exe` (Windows).
3. No menu inicial clique **CRIAR NOVO MUNDO**.
4. Digite um nome e uma **semente numérica ou textual**. Se deixar a
   semente vazia, o programa usa uma semente temporal e registra o valor.
5. Escolha Criativo/Sobrevivência. Se não quiser imagem, deixe o campo
   vazio e clique **CRIAR E JOGAR**.
6. Para testar mundo com imagem, clique **TESTAR IMAGEM EXEMPLO**
   (usa o PNG colorido `assets/worlds/demo.png`, embutido no pacote).
7. Clique **CRIAR E JOGAR** e explore. Os Cubic Chunks 16×16×16 surgem
   ao redor do jogador e são descarregados em regiões distantes.
8. Use **ESC** para voltar ao menu; **ESC > MENU INICIAL > ESCOLHER MUNDO**
   permite reabrir os mundos criados.

## Como importar qualquer foto

O projeto usa o sistema de arquivos virtual do LÖVR, que não pode abrir
diretamente qualquer lugar do Windows por razões de segurança.
Copie seu arquivo PNG ou JPEG para a pasta `maps` do diretório de
salvamento do jogo, que no Windows é, em geral:

```text
%APPDATA%\LOVR\base3demlua\maps\
```

Se a pasta ainda não existir, abra a tela de escolha de imagem uma vez
para criá-la, ou crie-a manualmente. Depois, no jogo clique
**CRIAR NOVO MUNDO > ESCOLHER IMAGEM NA PASTA MAPS** e escolha sua foto.
Também pode digitar o caminho relativo `maps/minha foto.jpg` no campo
**IMAGEM PNG/JPG**. Uma foto usada em um mundo **não é enviada à Internet**
pelo jogo, e a imagem original não é alterada.

O botão **TESTAR IMAGEM EXEMPLO** usa um PNG que já vem no pacote,
dispensando essa cópia. A importação aceita imagens decodificadas pelo
LÖVR; PNG e JPEG são os formatos indicados e testados em lógica.

## Como a imagem se transforma em mapa

- A imagem é reduzida a uma amostra de **64×64 pixels**. Cada pixel
  fornece luminosidade e tendência de bioma.
- Azuis favorecem lagos e depressões; verdes favorecem florestas;
  amarelos/ocres, regiões secas; cores quase brancas, neve.
- Ruído suave e multiescala, controlado pela semente, acrescenta
  colinas, montanhas e detalhes e suaviza transições. O resultado
  *não* é simplesmente reproduzir a foto como um tapete.
- O mapa de influência se repete a uma escala ampla (64×22 blocos),
  enquanto o ruído procedural evita repetição exata.
- O sistema gera cada **seção cúbica 16×16×16** sob demanda.
- Os pixels amostrados são gravados em `worlds/000001.map`,
  incluindo verificação de hash. O arquivo original pode ser removido
  depois, sem afetar o terreno gerado.
- A **mesma imagem e a mesma semente** reproduzem o mesmo mundo,
  desde que a mesma versão do gerador seja utilizada.
- Imagens diferentes ou sementes diferentes produzem mundos distintos.

Isso é um *gerador interpretativo*, não extração 3D fiel do conteúdo
da fotografia: rostos, prédios e animais não viram objetos 3D
reconhecíveis automaticamente.

## Onde ficam os saves

O catálogo é armazenado em `worlds/index.txt`; cada mundo novo guarda
o próprio `worlds/000001.sav` e, se criado por foto, um snapshot
`worlds/000001.map`. Mundos antigos que usam `world.sav` aparecem
separadamente como **Mundo antigo**; o save anterior não é sobrescrito
pela criação de mundos novos.

**Atenção:** por enquanto, não troque a imagem nem a semente de um mundo
já criado. Para outra variação, crie um mundo novo. Existe limite de 96
mundos no catálogo, sem opção gráfica de exclusão nesta etapa.

## Testes e limites

```sh
lua5.4 tests/worldgen_seed.lua
lua5.4 tests/worlds_menu.lua
```

Testes automatizados verificam determinismo, sementes diferentes,
interpretação de cores, persistência da amostra, separação dos saves,
catálogo, migração e botões do menu. A renderização e a interface
ainda precisam de teste manual em LÖVR/Windows. Não há seletor de
arquivo nativo do Windows nesta versão: use a pasta `maps`.
