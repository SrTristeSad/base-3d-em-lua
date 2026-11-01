# Motor Luanti em Lua — implementação incremental

Este diretório contém a **primeira implementação própria de um
motor voxel em Lua**, cujo objetivo de longo prazo é oferecer uma
camada de compatibilidade com a API Lua do Luanti e permitir executar
o VoxeLibre sem o motor original.

**O alvo é compatibilidade 1:1, mas esta fase NÃO é um porte 1:1.**
Na Fase 8, executamos três módulos originais adicionais de utilitários e itens: `mcl_worlds`, `mcl_particles` e `mcl_stonecutter`. O código original registra o bloco Stonecutter, suas receitas e callbacks de inventário. Um diagnóstico separado tenta carregar `mcl_core` inteiro, mas não o declara compatível. Continuamos usando o gerador **próprio** de chunks em Lua da Fase 7:
terreno determinístico por semente, areia, florestas, árvores, pequenas
cavernas e minérios. Não é o gerador do Minecraft nem do VoxeLibre.
A marcação de chunks gerados é salva para preservar construções e
remoções de blocos quando o mundo é reaberto. Desde a Fase 13, os 24 módulos Lua selecionados, incluindo `mcl_core`,
inicializam no teste de integração. A demo gráfica continua independente
e **não inicializa o jogo VoxeLibre**.

## Experimentar

Baixe o pacote `Motor-Lua-Experimental-Windows-x64` na
[workflow de builds](../.github/workflows/lua-engine-port.yml),
extraia os arquivos e execute `Motor-Lua-Demo.exe`.

**Controles:** mouse para olhar, WASD para caminhar, Espaço pula
(e sobe escadas/nada), Ctrl agacha no solo e desce escadas/água, Shift corre, botão esquerdo quebra bloco,
direito coloca pedra, F6 salva o mapa, **F7 gera o chunk 16×16 sob a câmera**; Escape libera o cursor.

O motor 3D usa o runtime **LÖVR 0.19** como camada nativa de
renderização, entrada e janela. Todo o mapa, registro de blocos,
API inicial, eventos e persistência foi escrito em Lua.

Para rodar com LÖVR instalado, execute `lovr lua-engine`
a partir da raiz do repositório.

## API já implementada (subconjunto)

- `core` / `minetest`, `register_node`, `register_tool`,
  `register_craftitem`, `register_entity`, `register_alias`,
  `register_craft`;
- `registered_nodes`, `registered_items`,
  `registered_entities`, grupos;
- `core/pseudorandom.lua`: algoritmo `PseudoRandom` legado do Luanti,
  testado contra sequências determinísticas com estados assinados.
- `core/nodedrops.lua`: leitura dos drops originais dos nós (subconjunto: strings, listas, `rarity`, `max_items` e ferramentas); sem silk touch ou fortune.
- `core/particles.lua`: hash espacial reversível de posições, registro e retirada de emissores de partículas (sem renderizador visual).
- callbacks de permissão e notificação de operações de inventário,
  registro da bancada de corte original e receita (sem interface de jogador).
- `core/worldgen.lua`: geração determinística independente em chunks 16×16,
  biomas simples, cavernas, árvores e minérios; a demo permite usar F7;
- salvamento de marcação de chunks gerados pelo formato `G` de
  `LUAENGINE 1`, com leitura dos saves antigos;
- `VoxelArea`, `get_voxel_manip`, `get_content_id`,
  `get_name_from_content_id`; leitura/edição de buffers e `param2`,
  escrita no mapa e preservação de metadados;
- `register_biome`, `register_ore`, `register_decoration`,
  com armazenamento de definições **sem geração real**;
- `get_node`, `get_node_or_nil`, `set_node`,
  `swap_node`, `remove_node`, `place_node`, `dig_node`;
- `get_meta`, `get_node_timer`, `find_nodes_in_area`;
- `register_globalstep`, `after`, `register_abm`,
  `register_lbm`, `register_on_generated`;
- `bit` (operações de 32 bits) e `PcgRandom` PCG32
  com `next`, `rand_normal_dist`, `get_state` e `set_state`;
- `get_mod_storage`, `register_chatcommand` e callbacks de eventos
  básicos exigidos por mods originais;
- executor de arquivos reais de mods em `core/modenvironment.lua`,
  com globais separadas e restrição aos caminhos registrados;
- smoke test de 24 módulos reais: `mcl_init`, `mcl_util`,
  `vl_unittests`, `mcl_colors`, `mcl_sounds`, `mcl_autogroup`,
  `tga_encoder`, `vl_tuning`, `flowlib`, `vl_legacy`, `controls`,
  `mcl_worlds`, `mcl_particles`, `mcl_stonecutter`, `doc`, `doc_items`,
  `tt`, `walkover`, `mcl_luck`, `mcl_gamemode`,
  `mcl_death_drop`, `mcl_experience`, `mcl_enchanting` e `mcl_core`;
- `get_craft_result`, `get_craft_recipe` e `get_all_craft_recipes`;
- receitas com formato, sem formato, grupos, forno, combustível e
  recipientes retornáveis (subconjunto da API original);
- crafting atômico no inventário de teste, sem consumir ingredientes
  quando o destino não tem espaço;
- `ItemStack` e `InvRef` (pilhas, metadados, desgaste,
  empilhamento por limite, busca, transferência e listas copiadas);
- `get_meta(pos):get_inventory()` e inventários destacados;
- salvamento de listas de nós e metadados de cada item com
  retrocompatibilidade com `LUAENGINE 1`;
- `mod.conf`, dependências obrigatórias/opcionais e
  carregamento de mods em ordem topológica por
  [`core/modloader.lua`](core/modloader.lua), ainda sem executar
  todos os mods do VoxeLibre;
- `vector.new` e operações vetoriais;
- armazenamento esparso por **mapblocks 16³**, marcação de
  alterações, persistência de blocos, metadados e timers;
- configuração básica, log e APIs de registro de callbacks.

[Veja a matriz de compatibilidade e os limites](../docs/ENGINE_LUA_PORT.md).

A CI também gera um **relatório estático de APIs do VoxeLibre**
que ainda faltam. A CI executa **apenas 24 módulos selecionados**,
sem iniciar o jogo. O arquivo `VoxeLibre-Real-Mod-Boot.md`
registra quais módulos e arquivos Lua foram carregados. A presença de uma API
no relatório não significa compatibilidade semântica completa.

Os testes de lógica executam sob Lua 5.4 **e LuaJIT**:
`tests/lua_engine_core.lua` e
`tests/lua_engine_inventory_modloader.lua` e
`tests/lua_engine_crafting.lua`, `tests/lua_engine_rng.lua`,
`tests/lua_engine_voxel.lua`, `tests/lua_engine_worldgen.lua` e
`tests/lua_engine_nodedrops.lua`.
A demonstração gráfica precisa de hardware Vulkan e teste manual.

O VoxeLibre integral continua disponível em `games/voxelibre/`
através de submódulo Git. **Não removemos o pacote funcional
Luanti + VoxeLibre** enquanto o novo motor não executar esse jogo.

### Primeiro conjunto real de blocos VoxeLibre (Fase 9)

O teste de integração carrega parcialmente `mcl_core/init.lua`
original e exige pelo menos nove definições reais, incluindo
`mcl_core:stone` e o minério de ferro. Valida os drops da pedra
(`mcl_core:cobble`) e do minério (`mcl_raw_ores:raw_iron`), seus
IDs e colocação no mapa. A execução ainda é interrompida por uma
referência ao módulo de documentação `doc_items`, que requer sua
própria cadeia de carregamento. **Não inicia o jogo completo.**

### Inicialização real de documentação e blocos (Fase 11)

O motor carrega os módulos originais `doc` e `doc_items` antes do
diagnóstico de `mcl_core`. O carregamento conjunto de **16 módulos**
foi observado nos testes Lua 5.4 e LuaJIT. `doc_items` registra seus
callbacks de mineração, interação, crafting e consumo; o motor já
mantém os registradores correspondentes, mas ainda não reproduz todos
os caminhos de gameplay que geram esses eventos.

A tentativa de iniciar `mcl_core` após carregar a documentação
registrou **166 nós originais** antes de encontrar a dependência da API
`register_on_liquid_transformed`. O registro e despacho do evento de
transformação de líquidos foi acrescentado, mas **não há simulação
1:1 do fluxo de líquidos** nesta versão. A contagem de 166 é o último
resultado confirmado antes da implementação de \`item_eat\`, não uma previsão da
próxima auditoria.

Foram adicionadas as definições nativas de `air`, `ignore` e da mão;
registro de privilégios, sessões de jogadores fornecidos pelo host,
eventos de `on_punchnode`, `on_craft`, `on_item_eat` e
`register_on_shutdown` com encerramento único da demo LÖVR.

**Essas verificações não equivalem a executar o jogo.** A renderização
das texturas originais, física completa, entidades, jogadores e a
compatibilidade 1:1 do motor continuam em desenvolvimento.

### Dependências originais adicionais (Fase 12)

Quatro módulos upstream adicionais inicializam junto aos dezesseis já
verificados: `tt` (tooltips), `walkover` (eventos de caminhar sobre blocos),
`mcl_luck` (modificadores de sorte) e `mcl_gamemode` (modos de jogo).
A integração executou **20 módulos e 32 arquivos Lua originais** nos
testes Lua 5.4 e LuaJIT. O módulo real `tt` também atualizou a
descrição de um ItemStack via callback de previsão de crafting.

O motor implementou `register_craft_predict`, execução dos respectivos
callbacks, `ItemStack:get_definition`,
`ItemStack:get_tool_capabilities` e `override_item`.
Essas APIs continuam parciais em relação ao Luanti completo.

`mcl_core` continua interrompido na dependência de `mcl_enchanting`.
Ainda não existe experiência 1:1 do VoxeLibre no executável LÖVR.

### Inicialização integrada de mcl_core (Fase 13)

O carregador de mods executa **24 módulos Lua originais e 52 arquivos
fonte**, incluindo `mcl_death_drop`, `mcl_experience`,
`mcl_enchanting` e `mcl_core`, em ordem de dependências. A inicialização
de `mcl_core` agora ocorre **antes** dos callbacks de
`on_mods_loaded`. Lua 5.4 e LuaJIT confirmaram 166 nós originais
registrados e retorno sem erro do código de inicialização.

O runtime recebeu o registro cancelável de
`register_on_punchplayer`, suporte a localização de inventários
`InvRef:get_location()`, consultas a inventários de jogadores realmente
conectados, registro de nomes explícitos com `:`, serialização de
tabelas de metadados sem executar código de entrada e receitas
`toolrepair` que respeitam desgaste e `disable_repair`.

**Carregar os 24 módulos não equivale a executar todo o jogo.**
Ainda faltam entidades funcionais, HUD, física e combate completos,
texturas dos nós originais, persistência integral, rede e a execução
normal dos callbacks de jogabilidade. O executável LÖVR continua
uma demonstração independente, não o VoxeLibre pronto para jogar.

### Renderização de faces visíveis (Fase 14)

O arquivo `core/mesher.lua` cria, em Lua puro, triângulos para apenas
as faces expostas dos cubos com `drawtype=normal` ou `allfaces`.
A consulta utiliza as definições reais dos nós registrados, inclusive
`tiles` de `mcl_core`, com mapeamento UV e normals por face.
Faces escondidas por cubos opacos são descartadas até quando os cubos
estão em mapblocks vizinhos. Alterações nas revisões do bloco ou de
seus seis vizinhos invalidam a malha correspondente.

O arquivo `core/renderer.lua` integra essas malhas ao LÖVR 0.19
por meio de buffers de vértices e `Pass:mesh`, substituindo a chamada
`pass:box` por nó. Os buffers são reutilizados até que o mapa seja
modificado ou um novo mundo seja carregado.

A distribuição gera automaticamente `visual/atlas.png`, um atlas
4×4 de texturas **procedurais provisórias** criado pelo script
`scripts/build_lua_engine_atlas.py`. Os nomes de textura seguem
identificadores usados pelo VoxeLibre, mas os pixels do atlas
**não são os arquivos gráficos originais do VoxeLibre**.
O atlas também não compõe arbitrariamente modificadores de textura;
a lateral de grama usa um substituto combinado.

Os testes de geometria rodam no Lua 5.4 e LuaJIT sem GPU. A compilação
do executável verifica o pacote, mas a nova renderização ainda exige
inspeção visual num PC Windows com LÖVR 0.19.

**Limites:** `nodebox`, `mesh`, `plantlike`, líquidos e transparências
corretas, colorização de `param2`, iluminação Luanti e shaders de
materiais continuam por implementar. O objetivo de compatibilidade
1:1 permanece; esta etapa não o conclui.

### Texturas upstream e novos drawtypes (Fase 15)

A compilação oficial agora lê os PNGs **originais** do submódulo
`games/voxelibre/textures/`, fixado pelo Git, e monta um atlas de 20
texturas. O modo de release exige `--require-upstream-textures` e falha
quando a origem não está disponível. Os arquivos `LICENSE.txt`,
`CREDITS.md` e `mods/ITEMS/mcl_core/README.txt` são incluídos no
pacote, em `visual/licenses/`. Não há substituição silenciosa por
texturas inventadas nos builds oficiais.

A lateral de grama é composta a partir do original `default_dirt.png`
e de `mcl_dirt_grass_shadow.png`. A água e a lava utilizam o primeiro
quadro de suas faixas PNG animadas; **a animação ainda não funciona**.
Um slot continua reservado à textura de erro. Empacotamentos locais sem
o submódulo podem solicitar placeholders, mas não se confundem com os
artefatos oficiais.

O mesher suporta aproximativamente `glasslike`,
`glasslike_framed`, `glasslike_framed_optional`, `liquid`,
`flowingliquid` e `plantlike`, além de `normal` e `allfaces`.
Vidros e líquidos idênticos adjacentes não geram faces internas.
Plantas usam dois planos cruzados de dupla face. A demo independente
exibe amostras de água, lava, vidro e flor com os pixels do VoxeLibre.

**Ainda não é compatibilidade gráfica 1:1**: vidros emoldurados usam
cubos simples sem os detalhes de moldura, líquidos não têm superfícies
de altura variável nem movimentação, não há ordenação correta de todas
as transparências, e `nodebox`, `mesh`, `facedir`, cores de bioma,
iluminação e muitos nós continuam ausentes. Os testes checam a
correspondência de pixels do atlas e a geometria em CPU; uma inspeção
visual em Windows com GPU permanece necessária.

### Catálogo de texturas completo do submódulo (Fase 16)

O atlas deixou de ficar limitado aos 20 identificadores cadastrados
manualmente. A geração de release agora percorre
`games/voxelibre/textures/*.png` na revisão do Git já fixada no
submódulo, ordena todos os nomes de arquivos e acrescenta cada PNG
que não estava nas posições reservadas. Na revisão verificada há
**2.898 arquivos PNG upstream**, resultando em **2.900 slots**
(incluindo a textura de erro e a composição de grama da demo).

O atlas usa 64 colunas de 16 pixels (largura 1.024 pixels) e linhas
calculadas conforme a contagem. O empacotador inclui no arquivo
`.lovr` três saídas criadas a partir da mesma lista:

- `visual/atlas.png`: pixels reais, em ordem estável;
- `core/atlas_manifest.lua`: índice carregado por `core.atlas` para
  localizar automaticamente uma textura pelo nome;
- `visual/ATLAS-INDEX.txt`: relação legível de nomes por posição.

Os primeiros 20 índices permanecem inalterados. Sem manifesto,
execuções dos testes Lua diretamente na árvore de fontes continuam
usando o atlas anterior. O build de release exige as texturas e
nunca mascara arquivos ausentes com arte inventada.

**Limites importantes:** disponibilidade de um nome de PNG no atlas
não significa que todos os nós já são renderizados corretamente.
A maioria dos modifiers de textura Luanti, animações além do primeiro
quadro, paletas de bioma, dimensões de sprite distintas, transparência
e geometrias de `nodebox`/`mesh` ainda precisam ser implementados.
Todas as imagens são reduzidas a células de 16×16 nesta fase;
isso é um passo de cobertura de assets, **não paridade 1:1**.

### Blocos com geometria fixa e orientação (Fase 17)

O módulo independente `core/nodebox.lua` traduz `drawtype=nodebox`,
`node_box.type=fixed` e `node_box.fixed` em faces reais, preservando
caixas parciais, lajes, caminhos rebaixados, camadas finas de neve
e vários cuboides no mesmo nó. Um plano de espessura zero pode
produzir as duas faces visíveis, como a lâmina do cortador de pedra.

Os parâmetros `paramtype2=facedir` e `colorfacedir` utilizam as
24 orientações ortogonais de Luanti. `4dir` e `color4dir` aplicam
as quatro orientações horizontais. O `param2` é lido diretamente
do mapa, cujas revisões já invalidam as malhas após uma rotação.
Para faces de caixas tocando os limites da célula, o mesher evita
enviá-las quando há um cubo opaco adjacente que as cobre.
O empacotamento da demo inclui o módulo automaticamente.

Os testes em Lua 5.4 e LuaJIT cobrem os seis eixos da rotação,
os 24 valores de `facedir`, lajes, elementos de espessura zero,
oclusão nas bordas e alteração de `param2`. A auditoria VoxeLibre
usa sem reescrever as definições dos nós originais
`mcl_stonecutter:stonecutter`, `mcl_core:grass_path`
e `mcl_core:snow`.

**Ainda não é geometria 1:1**: tipos `connected`, `leveled`
e orientações `wallmounted`, colisões e seleção por formas,
ocultação parcial entre superfícies complexas, modelos OBJ
e tratamento exato de texturas/iluminação continuarão em fases
posteriores. Esta fase não transforma a demo LÖVR no jogo
VoxeLibre completo.

### Nodeboxes dinâmicos e geometria de conexão (Fase 18)

`core/nodebox.lua` agora resolve as caixas `type=connected`
diretamente a partir do mapa e das definições dos blocos vizinhos.
`connects_to` aceita identificadores exatos e grupos `group:*`,
com `connect_sides`, braços `connect_top/bottom/front/left/back/right`,
formas `disconnected_*`, `disconnected` e
`disconnected_sides`. A geometria reage à colocação e à remoção
de nós vizinhos; `facedir` não rotaciona nodeboxes conectados.

`type=leveled` lê os níveis do `param2` em unidades de 1/64
da altura do bloco, com o valor inicial configurado em `leveled`.
`type=wallmounted` escolhe `wall_top`, `wall_bottom` ou
`wall_side` e orienta a caixa pelas posições 0–7 do `param2`.

Os testes de geometria testam cercas conectadas, filtros de
conexão, giro sem alteração das formas, altura, posições de parede
e atualização de malhas. A integração já executa **26 módulos originais e 56 arquivos Lua**,
incluindo `mcl_nether` e `mcl_fences`, sem modificar o upstream.
O teste verifica as barras de uma cerca real após colocar ou
remover sua vizinha.

A API `core.get_node_boxes(box_type, pos, node)` também retorna
as caixas resolvidas (`node_box`, `collision_box` e `selection_box`),
com a orientação e as conexões atuais. A consulta é utilizada nos
testes de seleção e colisão, mas ainda não aciona um motor de física.

**Limites atuais:** ainda falta o tratamento exato de oclusão parcial
entre caixas complexas, a equivalência entre `node_box` visível e
`collision_box`/`selection_box`, os modelos `mesh`, as cores
de `param2` e a execução completa do VoxeLibre pelo LÖVR.
A compatibilidade 1:1 permanece a meta, não uma condição alcançada.

### Física inicial do personagem (Fase 19)

`core/physics.lua` implementa um controlador AABB em Lua puro,
independente da renderização. A posição do personagem corresponde
aos **pés**; `eyeheight` determina a altura da câmera. O controlador
aplica gravidade, velocidade terminal, salto, sprint, movimento
horizontal e subpassos físicos limitados a 50 ms.

As colisões usam `core.get_node_boxes('collision_box', pos, node)`
e consultam a geometria verdadeira dos nós: cubos, nodeboxes
parciais, formas conectadas e orientações de `param2`.
As distâncias percorridas por eixo são **varridas** antes da
movimentação, evitando atravessar paredes quando o personagem
se move rapidamente. Nós com `walkable=false` não bloqueiam
a movimentação. Obstáculos baixos podem ser superados com
`stepheight`, desde que haja espaço livre acima; cercas altas
e tetos impedem subir.

A demo LÖVR passa a usar WASD para caminhar, Shift para correr e
Espaço para saltar; não usa mais câmera com voo livre. A câmera
acompanha o personagem que cai e colide com o mundo.

A regressão `tests/lua_engine_physics.lua` executa em Lua 5.4
e LuaJIT: aterrissagem, salto, paredes, prevenção de atravessamento
em velocidade alta, plantas/líquidos não sólidos, lajes, degraus
altos, teto, cercas com `collision_box` próprio e `4dir`.
A auditoria original também faz o personagem caminhar sobre
`mcl_core:snow_2` (a primeira camada `mcl_core:snow` é
atravessável no original) e testa a colisão de `mcl_fences:fence`.

**Ainda não é a física 1:1 de Luanti:** faltam aceleração e atrito
fieis, sneak nas bordas, escadas, nado, líquidos com arrasto,
colisões entre entidades, movimentação em rede, dano de queda,
escala de propriedades dos jogadores e vários efeitos de nós.
A compilação Windows não substitui um teste visual em máquina real.

### Aceleração, superfícies escorregadias, água e escadas (Fase 20)

`core/physics.lua` agora permite transições progressivas entre
velocidade atual e a velocidade desejada. As propriedades configuráveis
`acceleration`, `braking` e `air_acceleration` separam movimento
no solo, desaceleração e controle no ar. Sobre nós com o grupo
`slippery`, a aderência diminui de acordo com o valor do grupo;
o movimento horizontal conserva mais inércia.

Nós `climbable=true` permitem subida com Espaço e descida com Ctrl;
sem entrada vertical o personagem mantém sua altura enquanto está
em contato com a escada. Líquidos declarados com `liquidtype` ou
grupos `water`/`liquid` são atravessáveis mas passam a impor
aceleração e resistência próprias, gravidade reduzida e velocidade
vertical limitada; Espaço permite nadar para cima. A demo inclui
nós de água e escada, além de controles de subida/descida.

A regressão antiga da Fase 19 mantém, **explicitamente**, aceleração
instantânea e fluidos desligados para preservar as asserções de
colisões e velocidade constante. Os testes novos verificam a
aceleração progressiva, soltura de teclas, gelo/aderência, movimento
aéreo, nado, escada e opções inválidas em Lua 5.4 e LuaJIT.

**Limitações:** os parâmetros ainda não são valores calibrados para
física 1:1 do Luanti; não há simulação exata de correntezas,
viscosidade por definição de líquido, afogamento, danos por lava,
posição do jogador em rede, impulsos de superfícies ou sistema de
animações. O suporte gráfico a escadas utiliza um modelo provisório
`plantlike`, não a geometria original. O objetivo segue sendo a
compatibilidade 1:1, ainda não alcançada.

### Agachar e proteger bordas (Fase 21)

O controlador em `core/physics.lua` reconhece `input.sneak`
enquanto o jogador está apoiado, fora de água e escadas.
No solo, Ctrl reduz a velocidade máxima para
`sneak_speed` (1,5 nós/s por padrão) e rebaixa
gradualmente a câmera por `sneak_eye_offset` (0,28 nó).
A caixa de colisão do corpo **não é redimensionada**.

A proteção de bordas consulta as caixas reais de colisão
sob o **centro** do jogador, não apenas o tipo de nó, para
detectar solo firme. Quando o próximo movimento sairia do
apoio, a coordenada horizontal é limitada por uma busca
binária; o movimento paralelo à borda permanece disponível.
A implementação suporta superfícies parciais como lajes e
pode ser desativada com `sneak_edge_guard=false`, sem alterar
o movimento agachado. Ao nadar ou subir escadas, Ctrl continua
funcionando como comando de descida, sem prender o jogador
nas bordas.

A regressão `tests/lua_engine_sneak.lua` cobre o limite
da plataforma, movimento diagonal paralelo ao precipício,
câmera agachada, travessia normal sem proteção, lajes,
prioridade de água/escadas e configuração inválida em
Lua 5.4 e LuaJIT.

**Limites:** a busca atual por apoio é conservadora e não
reproduz toda a lógica de `sneak` nativa do Luanti,
incluindo pendurar-se nas bordas, colisão exata com
faces irregulares, animação corporal e movimentação em rede.
Os números da física são provisórios, não calibrados
como a física 1:1 do Luanti.

### Propriedades físicas e contato com nodeboxes (Fase 22)

O controlador `core/physics.lua` oferece agora o perfil
`Physics.new(api, pos, {profile='luanti'})`, com valores-base de
movimento documentados pelo Luanti: caminhada 4 nós/s,
agachamento 1,35 nós/s, velocidade fast 20 nós/s,
salto inicial 6,5 nós/s, gravidade 9,81 nós/s²,
aceleração no solo 3 nós/s² e aceleração aérea 2 nós/s².
A demo LÖVR usa esse perfil. A opção sem `profile` conserva
os valores de testes e demonstrações anteriores.

O controlador também implementa os métodos
`set_physics_override(override)` e `get_physics_override()`.
Os campos numéricos de velocidade, salto, gravidade,
aceleração e líquidos usam **multiplicadores por personagem**,
enquanto `sneak`, `sneak_glitch` e `new_move` são campos
booleanos. Atualizações parciais preservam os campos omitidos,
são validadas antes da aplicação e a consulta retorna uma cópia.
A definição `sneak=false` desativa a proteção de bordas.

O reconhecimento de material sob os pés usa agora as
`collision_box` de suporte, incluindo nodeboxes parciais e
objetos que ocupam uma fração da célula. A aderência ao piso é
selecionada pela interseção do corpo com a superfície real
de colisão, e não pela simples consulta ao centro do nó
arredondado. Assim o grupo `slippery` pode afetar o jogador
mesmo sobre lajes ou placas estreitas.

**Limites atuais:** a interface de overrides pertence ao controlador
local de física, ainda não aos `ObjectRef` de todos os módulos
originais. As equações de frenagem, nado, escalada e detecção
do suporte ainda são aproximações do motor Luanti, e velocidade
fast não inclui a verificação de privilégio original. O teste
automatizado não substitui a execução visual em Windows.
A paridade 1:1 permanece a meta.

### Física por jogador ligada à API de mods (Fase 23)

O novo módulo `core/playerphysics.lua` conecta um controlador
`core.physics` a um objeto de jogador que **o host fornece**.
`Runtime:connectPlayer(player, controller)` instala nesse objeto
os métodos Luanti `player:set_physics_override(table)` e
`player:get_physics_override()` **antes** de executar
`register_on_joinplayer`. O objeto visto pelos mods é a mesma
referência que o host passou e que a API retorna por
`get_player_by_name` e `get_connected_players`.

Um host também pode ligar a física depois da conexão, com
`Runtime:bindPlayerPhysics(player_name, controller)`. Os métodos
encaminham as alterações ao controlador real, preservando
atualizações parciais, validação de valores e cópias independentes.
Quando o jogador sai, `on_leaveplayer` ainda vê os overrides;
em seguida, a ligação é desfeita, sem apagar o estado do controlador.
Falhas em `on_joinplayer` desfazem a conexão antes de retornar
o erro. Um jogador que já implementa os métodos nativamente
não é substituído silenciosamente.

A demo LÖVR agora conecta uma sessão local mínima chamada
`singleplayer` ao controlador de movimento existente e a
desconecta ao encerrar. **Isso não implementa os demais métodos
de um ObjectRef nem autenticação, replicação em rede ou um
servidor multijogador.** A integração da física cobre apenas
jogadores fornecidos explicitamente pelo host. O runtime
continua sem fabricar jogadores para simular o VoxeLibre.

O teste `tests/lua_engine_player_physics_bridge.lua` verifica
identidade, callbacks de entrada/saída, aplicação real de overrides,
cópias de dados, falha atômica, conexão tardia, objetos com
métodos nativos, rejeição de controladores de outros runtimes,
reconexão e limpeza após falha de entrada em Lua 5.4 e LuaJIT.

**Limites:** o contrato ObjectRef ainda é parcial, a física
continua aproximada e a demo não executa o VoxeLibre completo.
A compatibilidade 1:1 com Luanti permanece como objetivo.

### Estado do jogador: posição, velocidade, controles e propriedades (Fase 24)

A ponte `core/playerphysics.lua` agora disponibiliza, nos **objetos
de jogador já fornecidos pelo host**, o subconjunto de métodos
`get_pos`, `set_pos`, `get_velocity`, `set_velocity`,
`add_velocity`, `get_player_control`, `get_properties` e
`set_properties`, além dos métodos de física da Fase 23.

As posições e velocidades pertencem ao **mesmo controlador Lua**
usado pelo movimento e são devolvidas por cópia. `set_pos` efetua
um teleporte simples, sem resolver colisões. Os controles não são
inventados a partir de vetores de movimento: o host envia
as teclas/botões reais usando `Runtime:updatePlayerControls(nome,
tabela)`, de onde `get_player_control()` retorna uma cópia
com os campos booleanos de direção, pulo, agachamento,
auxiliar, zoom, escavar e colocar.

As propriedades físicas hoje reconhecidas são `physical=true`,
`collisionbox` (AABB simétrica com os pés na origem),
`eye_height` e `stepheight`. Alterações são validadas
**antes** de modificar o controlador. Formas assimétricas,
modo não físico e propriedades de animação/visuais ainda não
são implementados; nesses casos o motor lança um erro
explícito em vez de prometer paridade com Luanti.

Quando o host já fornece um método específico, a ponte
preserva esse método. Ao sair, os métodos instalados pela
ponte são desfeitos sem apagar novos métodos do host.
A demo LÖVR agora associa as teclas WASD, Espaço, Ctrl e
Shift às flags reais do objeto local. A bateria
`tests/lua_engine_player_objectref.lua` testa os métodos,
cópias defensivas, falhas atômicas, controladores e
callbacks de entrada/saída com Lua 5.4 e LuaJIT.

**Ainda não é um ObjectRef 1:1:** falta a API completa de
jogadores, aparência, HUD, inventário de jogador integrado
à sessão visual, interações com entidades, sincronização
cliente-servidor e a execução integral do VoxeLibre.

### Inventário do jogador, ferramenta selecionada e ações no mundo (Fase 25)

O jogador fornecido pelo host expõe agora `get_inventory()`,
`get_wield_list()`, `get_wield_index()`, `set_wield_index()`,
`get_wielded_item()` e `set_wielded_item()`. Caso o host não
tenha inventário próprio, o runtime fornece uma **InvRef por sessão**
com lista `main` de 32 espaços. Caso o host já forneça
`get_inventory`, ela não é sobrescrita. Os valores `ItemStack`
retornados são cópias, com índices de ferramenta iniciando em 1.

`Runtime:digNodeAsPlayer(player,pos)` consulta a ferramenta selecionada
e os drops originais do nó, testa espaço disponível no inventário
**antes de escavar** e envia o jogador conectado a
`on_dignode`. Respeita os bloqueios básicos de proteção,
`diggable=false` e `can_dig`. `Runtime:placeNodeAsPlayer(player,pos)`
coloca um nó simples registrado pelo motor a partir do item
selecionado, consumindo uma unidade somente quando a colocação
é aceita e repassando o jogador a `on_placenode`. Todos os
métodos validam que o jogador pertence à sessão conectada.

A demo LÖVR agora conecta a sessão local **durante `lovr.load`**,
antes de encaminhar os controles (corrigindo uma lacuna da demo
anterior). Começa com 64 blocos de pedra na posição 1 e uma
picareta demonstrativa na posição 2. As teclas 1 a 9 selecionam
os espaços da barra; botão esquerdo escava, direito coloca o
bloco selecionado. O inventário ainda não possui HUD visual.

A regressão `tests/lua_engine_player_gameplay.lua` cobre
`InvRef`, seleção, cópias de `ItemStack`, drops dependentes de
ferramentas, callbacks, inventário cheio, nós protegidos,
conexão/desconexão e inventários próprios do host.

**Limitações:** não implementa ainda desgaste e velocidade reais de
ferramentas, animação de mineração, colocação por `on_place`,
escavação personalizada por `on_dig`, itens caídos como entidades,
modo criativo, callbacks completos de inventário, persistência
da lista `main` entre sessões, ou menu/HUD de inventário.
Os nós com esses callbacks personalizados são rejeitados
explicitamente no novo caminho simplificado, não tratados como
compatíveis. Portanto, este avanço **não é jogabilidade 1:1 do
VoxeLibre**. A meta continua a compatibilidade completa em Lua.

### Mineração por duração e desgaste (Fase 26)

O módulo `core/digging.lua` agora interpreta o subconjunto
`tool_capabilities.groupcaps`, `times`, `uses`, `maxlevel`,
`groups.level` e `dig_immediate`. Calcula a duração necessária
para quebrar um nó e o incremento de desgaste da ferramenta
(`ItemStack.wear`). Uma ferramenta de usos limitados se quebra
quando atinge o limite de desgaste. A Fase 28 substituiu as aproximações de `leveldiff` pela
fórmula do motor Luanti e expôs `core.get_dig_params`.

O runtime fornece um ciclo de mineração por jogador:
`beginDigNodeAsPlayer(player,pos)`,
`advanceDigNodeAsPlayer(player,dt)`,
`cancelDigNodeAsPlayer(player)` e
`getDigProgress(player)`. O controlador só retira o nó e entrega
os drops **ao concluir a duração prevista**; ferramentas usadas
recebem desgaste apenas após sucesso. Troca da ferramenta,
modificação do nó, proteção ou desconexão cancelam o progresso.

A mineração pela sessão de jogador preserva uma cópia de
`oldmetadata`, remove metadados do nó antigo e executa
`after_dig_node(pos,oldnode,oldmetadata,digger)` quando
o nó implementa esse callback. Os callbacks personalizados
`on_dig` foram posteriormente integrados na Fase 27.

Na demo LÖVR, o botão esquerdo **precisa ser mantido**
para minerar; soltar o botão ou deixar de mirar no bloco
interrompe a escavação. A picareta de demonstração tem
habilidades para vários grupos de materiais, mas não é
um item original do VoxeLibre. A API anterior
`digNodeAsPlayer` permanece instantânea para os testes
e hosts que usam o caminho legado.

A bateria `tests/lua_engine_timed_digging.lua`, executada em
Lua 5.4 e LuaJIT, verifica tempos por grupos, desgaste e quebra,
drops, metadados e callbacks originais, cancelamento por mudanças
e limpeza na desconexão. A compilação Windows ainda exige teste
visual em máquina real.

**Não é ainda a mineração 1:1 de Luanti**: faltam calibração
completa de `get_dig_params`, `on_dig` customizado,
`on_place` para itens, regras completas de privilégio e modo
criativo, partículas de progresso, pontuação de experiência
e persistência do desgaste por inventário entre sessões.

### Callbacks personalizados de interação com nós (Fase 27)

O motor aceita `on_dig(pos,node,digger)` definido por mods:
o jogador é o mesmo objeto conectado que executou a ação.
O resultado `false` cancela a operação; `true` e `nil`
(depreciado pelo Luanti) indicam que o mod tratou o evento.
**O motor não duplica drops nem remove o bloco automaticamente
após um callback customizado**: esse trabalho pertence ao mod.
Mods podem reutilizar `core.node_dig(pos,node,digger)`, que
executa o caminho de mineração padrão, com drops, metadados
anteriores e callbacks, sem recursão para `on_dig`.
A mineração progressiva também chama o callback personalizado
quando o tempo de escavação termina.

O comando `placeNodeAsPlayer(player,pos,pointed_thing)`
passa o `ItemStack`, o jogador e as posições `under`/`above`
para `on_place`, inclusive de `craftitem` e ferramentas.
O retorno `ItemStack` substitui a ferramenta/item apenas quando
o próprio callback não modificou diretamente o inventário;
`nil` preserva a pilha original. Quando o bloco apontado tem
`on_rightclick`, ele recebe prioridade em relação à colocação
do item. A proteção das posições é conferida antes de invocar
esses callbacks. A demo LÖVR agora repassa `under`/`above`
reais do raycast.

`core.item_place_node(itemstack,placer,pointed_thing[,param2,
prevent_after_place])` oferece o caminho simples de colocar
nós a partir de um callback personalizado. O helper devolve
`ItemStack, bool`, executa `on_construct` e
`after_place_node`, e chama `register_on_placenode` apenas
quando colocou o bloco, sem consumir itens duas vezes. Retorno
`true` de `after_place_node` preserva a pilha.

Os testes em `tests/lua_engine_custom_interactions.lua`
verificam escavação delegada e customizada, cancelamento,
retorno `nil`, ausência de drops duplicados, chamadas de
`on_place`, `on_rightclick`, proteção, integridade do
inventário, orientação `param2` e callbacks após mineração
com tempo em Lua 5.4 e LuaJIT.

**Limitações:** estes helpers ainda não representam toda a
implementação builtin Luanti: faltam `core.item_place` genérico,
fluxos de controle cliente-servidor, orientação automática completa,
interação com entidades, privilegios completos, drops como entidades
e regras especiais de mineração. A compatibilidade 1:1 com VoxeLibre
continua sendo uma meta, não uma funcionalidade já alcançada.


### Parâmetros nativos de mineração e interação (Fase 28)

O cálculo de `core.get_dig_params(groups,tool_capabilities[,initial_wear])`
agora segue o código-fonte de `src/tool.cpp` do Luanti:
`dig_immediate=2/3` com tempos fixos quando não há groupcap
específico, `maxlevel=1` e `uses=20` por padrão,
redução de duração por `leveldiff` quando superior a 1 e
desgaste escalonado em `65536` unidades, distribuído
entre usos normais e usos de desgaste adicional.
A implementação usa o `initial_wear` real do `ItemStack` e
seleciona o grupo mais rápido. O campo `main_group`
está disponível, assim como o alias interno `group`.

O desgaste do caminho padrão de mineração foi centralizado:
`core.node_dig` chamado por um `on_dig` personalizado
não aplica o desgaste duas vezes quando a mineração começou
por `beginDigNodeAsPlayer`. Ferramentas com `after_use`
podem alterar/devolver o `ItemStack`, preservando alterações
diretas que callbacks façam ao inventário.

A colocação padrão substitui o nó apontado quando ele define
`buildable_to` (p.ex. neve fina); a devolução de `true`
em `register_on_placenode` também impede consumir o item,
e um jogador agachado ignora `on_rightclick` na interação
padrão. Os métodos posicionais legados continuam aceitos.

Regressões em `tests/lua_engine_native_dig_params.lua`, cobrindo
Lua 5.4 e LuaJIT, verificam a fórmula e os limiares de desgaste,
escavação delegada, `after_use`, colocação substituível,
retenção de pilha por callback e interação agachada.

**Compatibilidade 1:1 ainda não concluída:** faltam regras
completas de `item_place`, `preserve_metadata`, modo criativo,
overflow de drops como entidades, orientação por `paramtype2`,
`attached_node` e implementação integral da lógica client/server
do Luanti/VoxeLibre.


### Fase 29 — core.item_place, orientação e preserve_metadata

A API de mods agora expõe `core.item_place(itemstack,placer,pointed_thing[,param2])`,
além de `core.item_place_node`. A primeira função prioriza
`on_rightclick` quando o jogador não está agachado, e caso contrário
coloca um nó somente se o item for do tipo node. Seguindo o builtin
do Luanti, o segundo retorno de colocação é a **posição** onde
houve colocação (ou `nil` quando não ocorreu), e não mais um booleano.
Chamadas existentes que apenas testavam a verdade desse retorno seguem
funcionando.

`core.dir_to_wallmounted`, `core.dir_to_facedir` (modo horizontal)
e `core.dir_to_fourdir` podem ser chamados pelos mods. As novas
colocações calculam automaticamente os `param2` de `wallmounted`,
`facedir`, `4dir` e variantes coloridas. Respeitam `place_param2`
e o parâmetro explícito de orientação; também transferem
`palette_index` do `ItemStack` para o `param2` das variantes
coloridas. `wallmounted_rotate_vertical` cobre a lógica de
orientação vertical do builtin para torchlike/signlike e outros
drawtypes quando há posição do jogador.

`preserve_metadata(pos,oldnode,oldfields,drops)` é executado no
caminho padrão de `core.node_dig`, recebendo uma cópia dos campos
do nó e uma lista mutável de `ItemStack` para os drops.
As alterações de metadados feitas pelo mod nos drops são mantidas
no inventário, enquanto `after_dig_node` ainda recebe a cópia
original dos metadados do nó removido. O bloqueio conservador de
inventário cheio permanece ativo até existir suporte real para
entidades de itens excedentes.

Os testes de `tests/lua_engine_placement_metadata.lua` cobrem
orientações, prioridades, metadados, trocas de pilha e substituição
de nós `buildable_to` em Lua 5.4 e LuaJIT.

**Limites restantes:** posicionamento em mapas descarregados e previsão
cliente/servidor, regras de `attached_node`, `is_creative_enabled`,
overflow em entidades, regras completas de ferramentas, mapeamento
6d de facedir, modificação de drops por itemstack em todas as APIs
e cobertura visual do executável no Windows. A compatibilidade 1:1
com Luanti/VoxeLibre ainda não está completa.


### Fase 30 — blocos fixados e modo criativo configurável

O caminho de `core.item_place_node` agora verifica
`groups.attached_node` antes de modificar o mundo, assim como
o `builtin_shared.check_attached_node` do Luanti:
`1` usa a direção `wallmounted` (ou chão por padrão);
`2` usa a direção de `facedir`/`4dir`;
`3` exige um bloco de apoio abaixo; `4` exige apoio acima.
A validação considera a propriedade `walkable` do nó de apoio
e funciona também com os bits de cor de `colorfacedir`,
`color4dir` e `colorwallmounted`.

Foi adicionada a tabela de vetores inversos do `directiontables.cpp`
do Luanti, exposta aos mods como
`core.facedir_to_dir`, `core.fourdir_to_dir` e
`core.wallmounted_to_dir`. As orientações `facedir`
de 0 a 23 são cobertas. Tentativas de colocar itens sem
apoio não retiram a pilha nem executam callbacks de colocação.

O motor também expõe `core.is_creative_enabled(player_name)`
com integração opcional ao host:
`Runtime.new({creative_mode=true})` habilita todos os jogadores;
`creative_players={Alice=true}` pode sobrescrever esse valor
individualmente; `creative_enabled=function(name) ... end`
pode fornecer uma política dinâmica. Com modo criativo habilitado,
o desgaste padrão da ferramenta é desativado; um callback
customizado `after_use` continua sendo responsabilidade do mod.

Regressões: `tests/lua_engine_attached_nodes.lua` em Lua 5.4
e LuaJIT. A cobertura inclui fixação nas paredes, no chão, no
teto, rotações `facedir` 6d, componentes coloridos e desgaste
com opções criativas.

**Limites:** `core.check_for_falling` e o ciclo de física de nós
desanexados ainda não foram portados. Um bloco pode ficar sem
apoio depois de ter sido colocado até que a física de nós seja
implementada. Faltam ainda overflow de drops como entidades,
modo criativo em inventário/colocação, sincronização de
cliente/servidor e outras regras do jogo completo. Não é uma
implementação 1:1 do Luanti nem do VoxeLibre.


### Fase 31 — física inicial de blocos que caem e nós sem apoio

O runtime implementa uma versão inicial dos pontos de entrada do
`builtin/game/falling.lua`:

- `core.check_single_for_falling(pos)`: converte nós com
  `groups.falling_node` em objetos de queda quando o bloco abaixo
  permite atravessá-lo; detecta `attached_node` sem sustentação.
- `core.check_for_falling(pos)`: percorre os 11 vizinhos na mesma
  ordem básica do Luanti e reavalia nós afetados em cascata, com
  limite de segurança para evitar propagação infinita.
- `core.spawn_falling_node(pos)`: converte um nó existente em
  objeto de queda, preservando `param1`, `param2`, metadados,
  inventário e estado do temporizador.
- `core.add_item(pos,itemstack)`: registra drops como itens do
  runtime, sem serializar `ItemStack` com metadados para uma string
  que perderia informação.

`Runtime:step(dt)` atualiza os objetos de queda com gravidade e
verifica cada célula vertical atravessada para não atravessar um
bloco sólido mesmo com um `dt` grande. Ao pousar, o nó original
é reconstruído e seus metadados/temporizador são restaurados.
A consulta `core.get_falling_nodes()` fornece cópias do estado
dos objetos em movimento para integração com o renderer, e
`core.get_dropped_items()` retorna cópias dos drops registrados.

A propagação de queda passa a ocorrer depois dos callbacks de
mineração, colocação e soco, incluindo os caminhos de jogador
`digNodeAsPlayer` e `placeNodeAsPlayer`. O acesso de baixo
nível `set_node`, `swap_node` e `remove_node` permanece
sem propagação automática, em conformidade com a distinção entre
alterações brutas do mapa e eventos de interação.

Teste de regressão: `tests/lua_engine_falling_nodes.lua` em
Lua 5.4 e LuaJIT. O teste cobre perda de apoio lateral e vertical,
drops de `attached_node` com `preserve_metadata`, atualização
em cadeia, transporte de metadados e temporizadores durante quedas
e colisão vertical sem atravessar o chão.

**Limitações intencionais:** o runtime ainda não apresenta entidades
3D animadas na demonstração, nem coleta automática de itens,
colisão com jogadores/objetos, mesclagem de nós de nível
(`leveled`) ou toda a física de líquidos. Os drops ficam
registrados em memória no runtime para o host; ainda não têm
persistência própria em disco. Portanto, esta fase não promete
compatibilidade 1:1 com o Luanti nem com o VoxeLibre.


### Fase 32 — renderização de blocos em queda e itens soltos

O renderizador LÖVR agora desenha objetos que não fazem parte dos
mapblocks estáticos. `Renderer:draw_dynamic(pass,runtime,camera,radius)`
renderiza blocos ativos de `core.get_falling_nodes()` nas posições
interpoladas pelo estado de gravidade do runtime, e pequenos cubos
texturizados para `core.get_dropped_items()`. A chamada ocorre
depois de `Renderer:draw`, portanto o cache estático de chunks
continua separado dos buffers dos objetos móveis.

O `Mesher.single_node(node,registry[,scale])` reutiliza as mesmas
regras de geometria, normais, UVs do atlas, `param2` e `node_box`
do mesher de mapa, com vizinhos virtuais de ar para mostrar todas as
faces do objeto isolado. `Mesher.item_cube(tile[,scale])` gera a
representação cúbica reduzida para craftitems e ferramentas;
`inventory_image` ou `wield_image` é priorizada, depois
as texturas do nó, com fallback para a textura de item ausente.
O cache GPU reutiliza geometria entre quadros e instâncias iguais,
é liberado por `Renderer:reset()` e expira modelos sem uso após
600 quadros. A renderização usa o `Pass:mesh` do LÖVR sem importar
a API gráfica para o runtime de gameplay.

**Teste no executável LÖVR:** pressione **F8** mirando um bloco para
criar um bloco de areia seis células acima e observá-lo cair.
Pressione **F9** para criar um pequeno item solto visível acima do
bloco mirado. A tecla **3** seleciona areia na hotbar para testar
colocação e queda normais. A tecla **F6** continua salvando o
mapa estático. Os objetos em movimento e drops ainda não são
gravados no arquivo do mundo.

`tests/lua_engine_dynamic_rendering.lua` valida, sem exigir GPU,
a construção de geometria, UVs, face winding existente, orientação,
cache e liberação dos buffers, deslocamento vertical, culling
por distância e transferência do bloco que pousou para o mapa
estático. A suíte roda em Lua 5.4 e LuaJIT.

**Limitações:** os itens soltos são cubos representativos, não
sprites ou entidades Luanti completas; animações, transparência
complexa, coleta automática, persistência, colisão com entidades,
integração completa dos mods originais VoxeLibre e validação visual
no Windows permanecem pendentes. O objetivo 1:1 continua em
desenvolvimento, não foi alcançado nesta fase.


### Fase 33 — coleta automática de itens soltos com inventário real

Quando o host conecta jogadores com `get_pos()` e `get_inventory()`,
`Runtime:step(dt)` pode coletar os drops próximos com o inventário
`main` do jogador. O mecanismo usa exclusivamente o InvRef real e as
mesmas regras de pilhas (`stack_max`, desgaste e metadados) do motor.

- `core.register_on_item_pickup(callback)` e
  `core.registered_on_item_pickups`: callbacks globais que podem
  interceptar a coleta retornando um `ItemStack` restante; `nil`
  permite que o próximo callback ou inventário processe o item.
- `core.item_pickup(itemstack,picker,pointed_thing)`: aplica os
  callbacks e, na ausência de interceptação, transfere para
  `picker:get_inventory():add_item("main",itemstack)`.
- `itemdef.on_pickup`: se definido para um item, controla a coleta
  desse item, recebendo `pointed_thing={type="object",ref=obj}`;
  retorno `nil` mantém o drop sem alteração.
- `Runtime:pickupItemsAsPlayer(player[,radius])`: coleta explicitamente
  objetos próximos e retorna a quantidade de unidades removidas.
  A função exige jogador conectado ao runtime, nunca transfere
  itens entre sessões e respeita a idade mínima dos objetos.
- `core.add_item` agora disponibiliza também `obj:set_item(stack)`
  para atualizar a pilha existente (ou removê-la ao esvaziar).
  `core.get_dropped_items()` inclui a idade e continua retornando
  cópias de `ItemStack` para não expor referências internas.

Uma coleta parcial **mantém o objeto no mundo** e troca apenas sua
pilha pelo saldo restante; inventários sem espaço não alteram o
objeto. Modificações de metadados não são perdidas nem fundidas
em pilhas diferentes. Itens só ficam elegíveis para coleta após
0,35 segundo, evitando recolhimento na mesma operação de drop.
A busca padrão considera uma distância de 1,5 bloco do centro do
jogador e processa jogadores conectados em ordem determinística
de nome, impedindo duplicação entre jogadores que disputam um drop.

Opções de `Runtime.new`: `auto_pickup=false` desabilita a coleta
automática, `pickup_delay=0` permite coleta imediata, e
`pickup_radius=2` ajusta a proximidade. O callback manual
`pickupItemsAsPlayer` permite coletar quando o host deseja, sem
ativar a lógica em cada frame.

Na demonstração LÖVR, pressione **F9** mirando um bloco para criar
um item solto; aproxime-se para recolhê-lo. Quando o item for
recolhido, o renderizador deixa de desenhá-lo automaticamente.
Os demais controles da Fase 32 continuam funcionando.

Regressões: `tests/lua_engine_item_pickup.lua` em Lua 5.4 e LuaJIT,
cobrindo coleta automática, atraso, inventário cheio, saldos parciais,
distância, metadados distintos, callbacks, rejeição, remoção,
controle manual e disputa entre dois jogadores.

**Limitações:** não há ainda física de objetos soltos completos,
efeitos de magnetismo/animações, áudio de coleta, redes/multiplayer
real, persistência de entidades nem equivalência exata ao ciclo
de `__builtin:item` do Luanti. A demo permanece experimental.


### Fase 34 — física dos itens soltos e persistência de objetos

Itens criados por `core.add_item` agora possuem `obj:get_velocity()` e
`obj:set_velocity({x,y,z})`, além de `obj:get_pos()`. O módulo
`core.itemphysics` integra gravidade com detecção de colisão por
varredura de voxels nas três direções, inclusive quando o `dt` é
grande. No chão, a velocidade vertical para e há atrito horizontal.
Objetos permanecem distintos do terreno e do jogador: não há
ainda colisão entre objetos, rotação visual nativa ou física detalhada
de `node_box`. O host pode desativar a física com
`Runtime.new({item_physics=false})`. A consulta
`core.get_dropped_items()` agora inclui também `velocity`.

O módulo `core.entitystorage` salva um arquivo lateral versionado
`LUAENGINE OBJECTS 1` usando um serializador de dados puro:
`EntityStorage.save(runtime,path,filesystem)` e
`EntityStorage.load(runtime,path,filesystem)`. Nele são guardados
itens soltos (pilhas, desgaste, metadados, idade, posição e velocidade)
e blocos em queda (posição, velocidade, nome, `param1`, `param2`,
inventário, metadados e temporizador). O leitor valida o documento
inteiro **antes** de substituir objetos da sessão. Ele não executa
código do arquivo carregado. Há limites de tamanho, contagem e valores.

A demonstração LÖVR agora utiliza dois arquivos:
`lua-engine-world.map` continua o formato do mapa estático da
Fase 1, enquanto `lua-engine-world.objects` armazena drops e
objetos em queda. Ambos são gravados por **F6** e ao sair e
restaurados ao iniciar o mundo salvo. Mundos mais antigos, sem
arquivo de objetos, continuam carregando normalmente.

Os testes `tests/lua_engine_item_physics_persistence.lua` cobrem
colisão vertical/horizontal, prevenção de atravessar o chão em
passos grandes, estados de velocidade, snapshots independentes,
retorno ao mundo de itens com metadados, blocos em queda com
inventário e temporizador e rejeição de conteúdo inválido sem
alterar a sessão. O CI executa Lua 5.4 e LuaJIT.

**Limites:** este é um formato de persistência de objetos separado,
não compatível com arquivos nativos do Luanti. O salvamento em dois
arquivos ainda não é transacional/atômico; um erro de disco entre
as gravações pode deixar versões diferentes. Ainda faltam
física de objetos contra jogadores, líquidos, geometria
detalhada de `node_box`, áudio, coleta visual animada e
compatibilidade 1:1 com Luanti/VoxeLibre.


### Fase 35 — colisão precisa de itens e resistência em líquidos

O módulo `core.itemphysics` substitui a aproximação de colisão por
células inteiras por uma **varredura AABB** contra as caixas reais de
`Nodebox.boxes(..., "collision_box")`. A detecção consulta as formas
que o motor já conhece para lajes, nós `fixed` com múltiplas caixas,
formas `facedir`/`4dir`, paredes `wallmounted`, cercas
`connected` e nós `leveled`. Blocos que estendem a geometria para
fora de sua célula também entram na busca de colisão. O resultado é
que o item pode atravessar a região vazia de uma laje ou ao lado de
um poste fino, sem atravessar a parte sólida quando a velocidade é alta.

Na água e em outros nós marcados por `liquidtype`, os drops recebem
amortecimento exponencial de velocidade e gravidade efetiva reduzida.
É uma **aproximação física local**, ainda não equivalente ao ciclo
nativo de física de entidades do Luanti; não existe correnteza nem
interação completa com líquidos. A resistência pode ser configurada
por `Runtime.new({item_liquid_drag=3})` e pode ser zerada. O atrito
depois de uma colisão vertical agora considera o grupo
`groups.slippery`: superfícies mais escorregadias retêm mais
velocidade horizontal.

**Experimento visual na demonstração LÖVR:** mire em um bloco de
terreno e pressione **F10**; será colocada uma laje de meia altura
com um item de areia suspenso três blocos acima, para observar a
colisão no topo real da laje. **F8** continua testando areia caindo
como nó e **F9** cria um item solto. Os mapas e objetos continuam
sendo salvos pelas funções da Fase 34.

**Teste automatizado:** `tests/lua_engine_item_nodebox_liquids.lua`
roda em Lua 5.4 e LuaJIT, cobrindo lajes, postes, orientação,
caixas fora da célula, atravessamento de partes vazias,
damping em líquidos, superfícies escorregadias e persistência após
movimentação. As regressões de todas as fases anteriores também
continuam habilitadas.

**Limites:** ainda faltam colisões entre entidades e jogadores,
correção de itens que nascem dentro de sólidos, física exata de
flutuabilidade/correnteza, efeitos visuais de água e testes
manuais da demonstração gráfica. Não há compatibilidade 1:1
com Luanti/VoxeLibre nesta fase.


### Fase 36 — recuperação de itens presos e interação de coleta por golpe

O módulo `core.itemphysics` agora reconhece quando um item nasce ou
entra em uma caixa sólida de colisão. Ele tenta deslocar o centro
até o espaço **livre** mais próximo por +X, -X, +Z, -Z e finalmente
+Y, consultando a geometria real de `core.nodebox` — incluindo lajes,
postes e caixas que ultrapassam as células. A posição candidata só
é aceita se **todo o volume do item** estiver livre. Se a região
estiver completamente bloqueada, o objeto não é apagado: permanece
intacto, zera a velocidade e tenta escapar novamente quando a física
for atualizada, inclusive depois de uma alteração no terreno.

A coleta automática da Fase 33 permanece. Além dela, o host pode usar
`Runtime:punchItemAsPlayer(player,item_object[,reach])` para processar
o golpe/interação em um item real. O método exige um jogador conectado,
um objeto pertencente à mesma sessão e proximidade da caixa de colisão
do jogador. A distância máxima padrão é **4 nós**, configurável por
`item_punch_reach`. A coleta usa o mesmo mecanismo de
`itemdef.on_pickup` e `core.register_on_item_pickup`, respeitando
metadados, pilhas parciais e ausência de espaço no inventário.
O resultado é `true,quantidade_coletada` quando processado, ou
`false,"missing_item"` / `false,"out_of_reach"` na rejeição.
O golpe não usa a espera mínima da coleta automática.

Como no Luanti, o item solto **não empurra fisicamente jogadores**:
a entidade `__builtin:item` original usa
`collide_with_objects=false`. Esta fase implementa a
interação com jogadores, não uma colisão física adicional que
desrespeitaria o objetivo de compatibilidade.

**Controles experimentais da demonstração LÖVR:**
**F11** cria um drop no interior do bloco mirado, para observar a
recuperação automática da posição. **F12** tenta recolher manualmente
o item solto mais próximo do jogador usando o novo método validado.
A seleção por proximidade no F12 é **apenas de depuração** e ainda
não faz raycast ou teste de linha de visão. F8–F10 e F6 continuam
com suas funções anteriores.

A suíte `tests/lua_engine_item_player_interaction.lua` testa em
Lua 5.4 e LuaJIT: ejeção de blocos completos e postes finos,
prioridade dos sentidos de saída, objetos inteiramente enclausurados,
recuperação após remoção de bloco, salvamento de itens presos,
objetos não sólidos, inventário cheio, golpes repetidos,
callbacks personalizados, alcance físico do jogador e recusa de
objetos de outros runtimes.

**Limites:** a recuperação é discreta, sem animação de expulsão nem
velocidade de repulsão do Luanti, e não simula todos os detalhes da
física nativa. A demonstração ainda não tem ataque a entidades por
raycast; o sistema de objetos do Luanti/VoxeLibre e a compatibilidade
1:1 continuam incompletos.
