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
