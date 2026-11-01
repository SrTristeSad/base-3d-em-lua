# Engenharia reversa funcional: motor Luanti -> Lua

## Objetivo

Reconstruir **o comportamento observável da API e do motor Luanti**
em Lua, usando o jogo VoxeLibre como referência de compatibilidade.
A meta de longo prazo é reduzir as diferenças funcionais para zero.

A reimplementação é independente: usar interfaces documentadas,
testes próprios e fontes GPL para referência, respeitando as
licenças de ambas as bases. O projeto não constitui um motor completo
apenas por existir uma API com os mesmos nomes.

## Estado: fase inicial do motor em Lua

| Subsistema | Estado |
| --- | --- |
| Registros de nós, ferramentas, itens, entidades e crafts | Parcial, funcional |
| Mapa esparso, blocos 16³, coordenadas negativas | Funcional para nós editados |
| Ler/editar nós, metadados, timers | Parcial, com testes |
| Eventos, after(), globalstep, ABM, callbacks | Parcial, com testes |
| Serialização segura, determinística, sem execução de código | Implementada (formato próprio) |
| Câmera livre, renderização voxel básica, mineração/colocação | Demo LÖVR independente |
| Loader `mod.conf`, dependências obrigatórias e opcionais | **Parcial, testado; não inicia VoxeLibre** |
| Módulos Lua originais do VoxeLibre | **Até 31 módulos selecionados no teste de inicialização Lua 5.4/LuaJIT (incluindo mcl_formspec); sem gameplay completo** |
| Jogo VoxeLibre completo no motor Lua | **Não funcional ainda** |
| VoxelArea, VoxelManip e IDs de conteúdo | **Parcial: buffers, mapblocks, param2 e escrita testados** |
| Registro de biomas, minérios e decorações | **Definições armazenadas; sem geração real** |
| Geração procedural **própria**, semente e persistência de chunks | **Implementada como experimento Lua; NÃO é mapgen Luanti** |
| Mapgen do Luanti, iluminação e simulação de líquidos | **Ausentes** |
| ItemStack, InvRef, listas em nós, detached, metadados e save | **Parcial, testado** |
| Receitas shaped/shapeless, grupos, forno/combustível, devoluções | **Parcial, testado** |
| Craft completo, toolrepair, callbacks e transações player | Pendentes |
| Entidades em mundo, mobs e física completa | Ausentes |
| Formspec, HUD, chat, multimídia, áudio | **Formspec parcialmente implementado (sessões e callbacks, sem renderizador);** HUD, multimídia e áudio completos ausentes |
| Rede, persistência SQLite/LevelDB, servidor multiplayer | Ausentes |
| Compatibilidade real de versão LuaJIT/Lua 5.1 | Pendente |
| Testes de equivalência com Luanti original | Pendente |

## Como é organizado

- `lua-engine/core/map.lua`: armazenamento esparso, metadados e timers.
- `lua-engine/core/nodedrops.lua`: leitura parcial de `drop` nos nós, inclusive distribuição por raridade e máximo de itens; sem geração de item-drop físico.
- `lua-engine/core/voxel.lua`: VoxelArea, IDs de conteúdo e VoxelManip experimental com regiões alinhadas a mapblocks.
- `lua-engine/core/worldgen.lua`: mapa original por semente, chunks 16×16 e construção via VoxelManip.
- `scripts/mcl_core_dependencies.py`: gera árvore real de dependências obrigatórias de mcl_core a partir do mod.conf upstream.
- `lua-engine/core/runtime.lua`: registro e despachos da API minetest/core.
- `lua-engine/core/vector.lua`: vetores e operações aritméticas.
- `lua-engine/core/storage.lua`: save seguro e determinístico, incluindo inventários de nós.
- `lua-engine/core/itemstack.lua`: valores `ItemStack` copiáveis e metadados.
- `lua-engine/core/inventory.lua`: listas `InvRef` e inserção com sobras.
- `lua-engine/core/modloader.lua`: leitura de `mod.conf`, ordenação por dependências e falha explícita.
- `lua-engine/core/modenvironment.lua`: ambiente de globais separado que executa arquivos Lua reais dos mods de referência, com acesso ao sistema de arquivos limitado aos diretórios de mods declarados. **Não é sandbox de segurança contra código não confiável.**
- `lua-engine/core/modstorage.lua`: `StorageRef` por mod/mundo, com persistência versionada opcional via filesystem de host; o formato não reproduz o backend SQLite do Luanti.
- `lua-engine/core/bitops.lua`: bitops de 32 bits em Lua sem operadores da sintaxe Lua 5.3.
- `lua-engine/core/pcgrandom.lua`: gerador PCG32 com dois limbs de 32 bits e estado restaurável; referência Luanti 5.18.0.
- `tests/lua_engine_real_voxelibre.lua`: executa 11 módulos upstream em CI Lua 5.4 e LuaJIT, incluindo verificações de flowlib e conversão de inventários com vl_legacy.
- `lua-engine/core/crafting.lua`: registro, consulta, escolha prioritária e execução atômica de receitas.
- `scripts/audit_voxelibre_api.py`: inspeção estática das chamadas `core.*`/`minetest.*` no VoxeLibre; não mede paridade funcional.
- `lua-engine/main.lua`: demo independente LÖVR para testarmos o motor.
- `tests/lua_engine_core.lua`: regressões da API inicial.
- `scripts/package_lua_engine.py`: gera `.lovr` autônomo.

O arquivo `lua-engine/main.lua` não é o antigo `main.lua`:
são executáveis separados, não duas implementações conflitantes.

## Constrangimento técnico

Um motor de vídeo totalmente em Lua puro, sem bibliotecas nativas,
não pode fazer sozinho a interface gráfica Vulkan/Direct3D, a janela
e a entrada do sistema operacional. **A lógica será em Lua**,
mas o LÖVR usa código nativo para GPU/áudio/janela.

O backend LÖVR é uma escolha inicial, não uma implementação 1:1
das estruturas internas do Luanti, que usa C++ para mundo, render,
inventários, rede e serialização. A compatibilidade completa
terá de ser comprovada, e não pressuposta.

## Próximos marcos objetivos

1. Completar os callbacks de craft/inventário e toolrepair; conectar
   o resultado da receita ao inventário do jogador e à interface.
2. Expandir os testes de execução da árvore de módulos além dos
   seis módulos já testados, corrigindo APIs ausentes e dependências.
3. Lua VoxelManip + geração/iluminação e mundos persistentes;
   streaming e greedy meshing em renderização otimizada.
4. HUD/formspec, entidades físicas, players, multijogador.
5. Rodar VoxeLibre sem Luanti, e executar testes de equivalência
   de blocos, seeds, mundo, jogabilidade e mods.

**Não iniciar mudanças de gameplay proprietárias antes que a
base de compatibilidade esteja verificável.**

## Segurança e licença

O VoxeLibre original continua intacto em `games/voxelibre`,
sob GPLv3+, com créditos e licenças de media. Luanti é LGPLv2.1+.
O protótipo Lua ainda não é uma tradução linha-por-linha do
código C++; é uma reimplementação incremental de interfaces e
comportamentos a partir de uma arquitetura nova.

### Fase 4 — verificação real

Na execução Linux de GitHub Actions, seis módulos originais foram
carregados com sucesso usando Lua 5.4 e LuaJIT, totalizando 12 arquivos
Lua: mcl_init, mcl_colors, mcl_sounds, mcl_autogroup,
tga_encoder e vl_tuning.

O módulo seguinte mcl_util continua bloqueado em fase de inicialização:
ao menos os recursos bit (Lua 5.4) e PcgRandom (LuaJIT) precisam ser
portados. Os relatórios de cada execução documentam o erro observável.
A auditoria estática registra 66 dos 240 nomes de API usados nos mods
presentes na tabela do motor, com 174 nomes ainda não exportados.
**Quantidade de nomes de funções NÃO equivale a compatibilidade funcional.**

A implementação de Settings lê game.conf para fins de inicialização,
e get_version identifica este porte como 0.1.0-lua-port, e NÃO como
o binário Luanti original. Os arquivos do VoxeLibre não são alterados.

### Fase 5 — bitops e PCG32

Foram implementados bitops aritméticos de 32 bits em Lua puro e uma
implementação PCG32 baseada no algoritmo do Luanti 5.18.0, usando
metades de 32 bits para evitar perda de precisão em LuaJIT.
Os testes comparam sequências determinísticas de valores assinados
com vetores de referência para sementes 0, 42, 12345 e -1.
O módulo `mcl_util` e sua dependência `vl_unittests` passam a integrar
o teste real de carregamento, além dos seis módulos anteriores.

**Limitação:** sementes/seq em valor numérico Lua acima do intervalo
exato de 53 bits são rejeitadas explicitamente; o código Luanti aceita
u64 completo. A API ainda não é 1:1 nesse caso. PCG32 não é gerador
criptograficamente seguro. Continua faltando rodar o jogo inteiro.

### Fase 6 — manipulação voxel e módulos de blocos

- Implementados `VoxelArea` (indexação x-fastest),
  `VoxelManip` (leitura alinhada em mapblocks 16³,
  `get_data`, `set_data`, `get_param2_data`,
  `set_param2_data`, `get_node_at`,
  `set_node_at` e `write_to_map`) e mapa de IDs.
- IDs numéricos são temporários e reproduzíveis dentro da
  sessão, mas **não garantem igualdade com os IDs internos do Luanti**.
  O formato de salvamento antigo continua baseado em nomes de nós.
- `register_biome`, `register_ore` e `register_decoration`
  armazenam configurações sem gerar biomas ou recursos minerais.
- O voxel buffer possui limite de 262.144 células por chamada
  e não implementa luz, líquidos, emerge assíncrono ou
  serialização nativa do Luanti.
- O terreno da demo 3D usa agora VoxelManip em vez de chamadas
  `set_node` individuais; o terreno continua sendo uma simulação
  simples, não uma reprodução do mapgen VoxeLibre.
- O teste de boot integra os módulos originais independentes
  `flowlib`, `vl_legacy` e `controls`, somados aos oito
  módulos anteriores. Testa consultas reais de água, conversão de
  inventário legado e registro de callbacks sem jogadores conectados.

**Ainda não são carregados os módulos de gameplay `mcl_core`,
`mcl_mapgen_core` e `mcl_biomes` completos**. Dependem de outros
módulos, da geração do motor e de centenas de funções que ainda faltam.

### Fase 7 — chunks e dependências de mcl_core

O gerador próprio em `lua-engine/core/worldgen.lua` produz terreno de
teste determinístico a partir da semente, com camadas de solo, areia,
água, cavernas simplificadas, minério e árvores. O gerador utiliza
`VoxelManip` da Fase 6, não APIs internas de terreno C++ do Luanti.

- Chunks 16×16, camada vertical **-16 a +31**, gerados sob demanda.
- Ordem de geração não altera os blocos resultantes, inclusive
  folhas que cruzam a borda entre chunks.
- `G cx cz seed` marca chunks gerados no save `LUAENGINE 1`;
  saves anteriores continuam legíveis. Regerar com seed diferente
  é recusado para evitar destruir dados do jogador.
- `F7` na demonstração gera o chunk da posição atual do jogador.
  A demo **não possui streaming automático**, física nem meshing otimizado.
- A análise `mcl_core_dependencies.py` percorre os `mod.conf`
  originais do VoxeLibre, sem alterar arquivos, e produz o fechamento
  das dependências de `mcl_core` como artefato da CI.
- **Ainda não executa `mcl_core`**, `mcl_mapgen_core` ou
  `mcl_biomes` no novo motor. O mapa de teste não tem
  correspondência 1:1 com as sementes do Luanti.

Os testes de integração continuam executando os **11 módulos
originais** já confirmados na Fase 6; nenhum módulo novo foi declarado
compatível sem executar seu código original e validar o resultado.

### Fase 8 — três módulos adicionais, bloco de bancada real

- `mcl_worlds`: o código original carrega e conversões de camadas/dimensões foram testadas.
- `mcl_particles`: o código original registra e elimina emissores em posições de nós usando hash reversível. A camada Lua registra as definições, **não desenha partículas**.
- `mcl_stonecutter`: o código original registra o nó `mcl_stonecutter:stonecutter`, receitas e callbacks de inventário; o motor avalia permissões e proíbe escrita no slot de saída.
- **Ainda não existe GUI de bancada de corte, sessão de jogador nem backend de renderização de partículas**; chamadas GUI falham explicitamente em vez de simular sucesso.
- O teste de integração também tenta executar `mcl_core/init.lua` como diagnóstico depois dos módulos compatíveis e registra o erro observado. Esse probe não conta como módulo carregado nem satisfaz as dependências ainda ausentes.
- O motor continua **longe da paridade 1:1**. O número de módulos que inicializam não representa quantidade de jogabilidade portada.

### Fase 9 — drops e inspeção de blocos originais

Foi implementado um avaliador específico das regras `drop` de nós.
Oferece `get_node_drops` para drops diretos, item lists, `rarity`,
`max_items` e restrições simples de ferramenta, com RNG injetável
para testes determinísticos. **Não implementa encantamentos,
Fortune, Silk Touch ou criação de entidades de itens**.

A integração executa o arquivo `mcl_core/init.lua` original de
forma diagnóstica e registra quantos nós originais foram declarados
até a primeira dependência ainda não suportada. O teste verifica
os drops da pedra original somente quando ela já estiver registrada.
Não simula dependências, não edita o VoxeLibre original e não declara
`mcl_core` carregado. A meta é aumentar o carregamento real.

O diagnóstico de `mcl_core/functions.lua` apontou o primeiro bloqueio na
linha 528: `PseudoRandom`. Foi portada a implementação legado do
Luanti (LCG 32-bit, com divisão assinada), com vetores determinísticos
para várias sementes e testes em Lua 5.4/LuaJIT. O número de nós
originais registrados após o porte é relatado pela CI, **sem contar
carregamento parcial como sucesso integral do módulo**.

**Resultado confirmado na CI da Fase 9:** o `mcl_core/init.lua` real
executa `functions.lua` até o final e inicia `nodes_base.lua`.
Registra pelo menos **9 nós originais**, inclusive `mcl_core:stone` e
`mcl_core:stone_with_iron`. Foram testados os drops originais e o
registro de IDs e colocação no mapa do protótipo. O carregamento para
no arquivo `nodes_base.lua:235` porque usa
`doc.sub.items.temp.build` do módulo upstream `doc_items`, ainda não
carregado neste ambiente. **mcl_core segue incompleto e não deve ser
considerado um dos módulos integrados.**


### Fase 58 — sessões de formspec e bancada de corte original

- Implementado `core.show_formspec(playername, formname, formspec)` e
  `core.close_formspec(playername, formname)`, com substituição de formulário,
  isolamento por jogador, fechamento por nome exato ou coringa vazio e limpeza
  ao desconectar. Jogadores ausentes não recebem sessões fictícias.
- O host pode obter uma cópia de `Runtime:getPlayerFormspec(playername)`
  e entregar eventos reais de seu próprio cliente por
  `Runtime:receiveFormFields(playername, formname, fields)`.
  Estes callbacks são despachados em ordem inversa de registro, conforme
  o Luanti 5.18.0, e uma callback que retorna `true` impede as anteriores.
  `quit="true"` fecha antes da notificação; `try_quit` não fecha.
- O analisador de elementos preserva o texto original e aceita a sintaxe de
  texturas `^[...` comum em formspecs; fornece uma representação auxiliar,
  **não** um layout, interpretador visual ou filtro de segurança.
- `PlayerMetaRef` com campos `string/int/float` já atende seleções da bancada,
  reutilizando o mesmo armazenamento por nome durante reconexões no runtime.
  A persistência em disco desse metadado de jogador ainda não está conectada.
- Foi adicionado ao teste geral o `mcl_formspec` original. Um teste
  independente carrega **seis módulos originais** do VoxeLibre, inclusive
  `mcl_stonecutter` e `mcl_formspec`, e executa a interface real da bancada:
  abre o formulário, seleciona receita, atualiza a saída, alterna tamanho da
  pilha e fecha, devolvendo os insumos ao inventário.
- Testes: `tests/lua_engine_formspec_sessions.lua` e
  `tests/lua_engine_original_stonecutter_formspec.lua`, ambos em Lua 5.4 e
  LuaJIT na CI, além das regressões anteriores.
- **Não está pronto:** o LÖVR ainda não desenha os elementos formspec, a
  integração completa de inventário de nós e as transações de UI não estão
  implementadas, nem existe multiplayer/rede ou gameplay completo do VoxeLibre.


### Fase 60 — trocas de pilhas e ações put/take do inventário do jogador

- `Runtime:movePlayerInventoryStack` agora implementa **troca de pilhas**
  diferentes entre slots do mesmo `InvRef`, segundo
  `IMoveAction::apply` do Luanti 5.18.0: checagem de autorização nas
  **duas direções**, troca dos itens completos e envio de dois eventos
  `on_player_inventory_action(..., "move", ...)`, com origem e destino
  invertidos no segundo evento. Ações proibidas não alteram os slots.
- Novas funções exclusivas do host: `Runtime:takePlayerInventoryStack`
  retorna um `ItemStack` efetivamente retirado do jogador;
  `Runtime:putPlayerInventoryStack` consome o objeto de pilha mantido
  pelo host, respeitando capacidade e autorização de mods. Para ambas,
  `allow_player_inventory_action` ocorre antes da alteração e
  `on_player_inventory_action` depois, com `inventory_info.stack`
  contendo o quantitativo realmente transferido.
- Os três caminhos validam jogador conectado, índices válidos, contagens
  e alterações durante a checagem de permissão. Pilhas com metadados não
  se misturam indevidamente. A pilha mantida pelo host é decrementada
  somente quando o put é realizado com sucesso.
- A integração do `mcl_stonecutter` original foi ampliada: após os
  movimentos já existentes, o teste retira o produto do slot de saída
  por `take`, verifica o consumo dos ingredientes realizado pelo mod,
  e deposita o produto no inventário por `put`.
- Testes de regressão: `tests/lua_engine_inventory_swap_put_take.lua`,
  `tests/lua_engine_player_inventory_actions.lua` e
  `tests/lua_engine_original_stonecutter_formspec.lua`, em Lua 5.4 e LuaJIT.
- **Atenção:** este transporte trata apenas do `InvRef` de um jogador.
  A ligação de inventários entre jogadores, nós, entidades e detaches
  continua incompleta. O motor ainda não tem um cliente formspec visual
  plenamente funcional ou uma implementação de todos os casos especiais
  da lógica original do inventário, como estoques infinitos.

### Fase 61 — primeira apresentação visual de formspecs no host LÖVR

- Novo lua-engine/core/formspecview.lua: lê a sessão do core.show_formspec, sem criar outro esquema de formulário, e posiciona size, label, button, button_exit, image_button, item_image_button, list[current_player], scroll_container, image e box.
- Botões enviam os nomes dos campos originais ao Runtime:receiveFormFields; fechar envia quit e dispara os callbacks do mod. Cliques de inventário selecionam origem e destino e usam Runtime:movePlayerInventoryStack, com clique direito para uma unidade.
- O renderizador LÖVR apresenta layout ortográfico via Pass, preservando estado da GPU. Hit testing e células desenhadas compartilham as mesmas coordenadas. A rolagem da primeira scroll_container é limitada pela região visível e conteúdo real.
- O executável lua-engine/main.lua passa a desenhar as sessões abertas e a entregar mouse/teclado ao visualizador. F3 abre somente um formspec de diagnóstico no demo com os slots reais do jogador. Esc envia quit e devolve o controle ao jogo.
- Testes em tests/lua_engine_formspec_view.lua cobrem apresentação, callbacks, inventário e rolagem; tests/lua_engine_original_stonecutter_visual.lua usa o formspec original não modificado do VoxeLibre, com clicks de receita, saída e consumo.
- LIMITES: imagens e ícones são representados por placeholders planos, não sprites fiéis. field, dropdown, checkbox, table, hypertext, tooltips, scrollbar arrastável, containers aninhados e inventários externos ainda não são implementados. O demo não inicializa todos os mods do VoxeLibre, e a equivalência 1:1 continua uma meta, não um estado alcançado.

### Fase 62 — campos editáveis e controles de escolha dos formspecs

- O host LÖVR agora entrega eventos de texto via `lovr.textinput` e teclado
  via `lovr.keypressed` à sessão de formspec autorizada.
- A primeira camada visual interpreta os controles originais `field`,
  `pwdfield`, `textarea`, `checkbox` e `dropdown`, mantendo os
  valores por formulário. Ao clicar em um botão ou fechar, encaminha os
  valores editados com o nome de campo de cada widget a
  `on_player_receive_fields`; eventos específicos de escolhas também
  passam pelos callbacks originais.
- A tecla Enter respeita `field_close_on_enter` para campo comum e envia
  `key_enter_field`; a textarea aceita quebra de linha. Backspace remove
  um ponto de código UTF-8 por vez. Senhas são mascaradas no renderizador,
  mas enviadas ao mod quando o formulário é submetido.
- Combos respeitam a sintaxe formspec de eventos por texto ou índice
  e strings com vírgulas escapadas. Há limites defensivos de comprimento
  e opções para proteger o host contra formulários malformados.
- O formulário de diagnóstico F3 testa agora campo de texto, checkbox
  e dropdown sobre o inventário real do jogador.
- Os testes `tests/lua_engine_formspec_input_controls.lua` exercitam
  edição, teclado, valores enviados, UTF-8, defaults, estado após
  substituição de formulário, senha mascarada e fechamento no CI de
  Lua 5.4 e LuaJIT.
- **Limites:** ainda não há widgets nativos perfeitos nem escolha expandida
  em dropdown; o clique percorre as opções. Imagens de formulários
  continuam representadas por placeholders. Outras partes do protocolo
  formspec e o motor inteiro ainda não atingiram fidelidade funcional 1:1.

### Fase 63 — renderização de sprites do atlas VoxeLibre nos formspecs

- Novo módulo `lua-engine/core/formspecsprites.lua`: o host gera quads de
  seis vértices com os UVs fornecidos por `core.atlas`, usando exatamente
  o mesmo `visual/atlas.png` empregado pelo mesher 3D. O pacote LÖVR com
  o submódulo original inclui os pixels das texturas do VoxeLibre fixado.
  A ponte gráfica apenas usa `lovr.graphics`; toda a geometria, posição,
  indexação, seleção e lógica continuam em Lua.
- `formspecview.lua` agora representa `image`, `image_button`,
  `item_image`, `item_image_button` e slots reais do inventário com
  sprites do atlas quando existem. `inventory_image`, `wield_image`
  ou o primeiro `tiles[]` do item/nó registrado determinam a imagem.
  Texturas desconhecidas continuam usando placeholder/texto em vez de
  representar arbitrariamente outro item. As legendas de contagem e o
  hit testing continuam no mesmo lugar.
- O cache reutiliza buffers GPU para sprites de tamanho e posição iguais,
  descarta os que não apareceram nos últimos frames e tem teto de
  retenção; fechamento do executável libera os buffers e atlas.
- O empacotador declara a nova ponte visual como dependência obrigatória.
  Os testes `tests/lua_engine_formspec_atlas_sprites.lua` verificam
  vértices/UV, reutilização de buffer, rejeição de imagens ausentes,
  preservação das ações do mouse, ciclo de vida gráfico, e o
  `mcl_stonecutter` original continua passando por cliques com
  identificadores originais das imagens.
- **Limitações:** o atlas atual reduz PNGs a 16x16 e o renderer utiliza
  a imagem-base para texturas com modificadores (ex.: `^[verticalframe`).
  Sem composição de modificadores, nove fatias, animação e tamanhos
  originais, a interface ainda não é 1:1 em aparência. O subconjunto
  de elementos formspec e o boot completo do VoxeLibre continuam parciais.
