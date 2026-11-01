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
remoções de blocos quando o mundo é reaberto. A cadeia de dependências
reais do módulo `mcl_core` é auditada, mas ele ainda não executa.
A versão atual roda apenas uma demonstração independente.

## Experimentar

Baixe o pacote `Motor-Lua-Experimental-Windows-x64` na
[workflow de builds](../.github/workflows/lua-engine-port.yml),
extraia os arquivos e execute `Motor-Lua-Demo.exe`.

**Controles:** mouse para olhar, WASD para voar, Espaço sobe,
Ctrl desce, Shift acelera, botão esquerdo quebra bloco,
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
- smoke test de 14 módulos reais: `mcl_init`, `mcl_util`,
  `vl_unittests`, `mcl_colors`, `mcl_sounds`, `mcl_autogroup`,
  `tga_encoder`, `vl_tuning`, `flowlib`, `vl_legacy`, `controls`,
  `mcl_worlds`, `mcl_particles` e `mcl_stonecutter`;
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
que ainda faltam. A CI executa **apenas catorze módulos selecionados**,
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
