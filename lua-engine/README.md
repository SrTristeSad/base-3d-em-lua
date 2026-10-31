# Motor Luanti em Lua — implementação incremental

Este diretório contém a **primeira implementação própria de um
motor voxel em Lua**, cujo objetivo de longo prazo é oferecer uma
camada de compatibilidade com a API Lua do Luanti e permitir executar
o VoxeLibre sem o motor original.

**O alvo é compatibilidade 1:1, mas esta fase NÃO é um porte 1:1.**
Na Fase 5, o carregador passa a executar os arquivos originais de oito
mods do VoxeLibre, incluindo `mcl_util` e `vl_unittests`.
A implementação também introduz operações de bits portáveis e
um gerador PCG32 com estado de 64 bits em duas partes de 32 bits,
testado contra sequências determinísticas de referência.
A versão atual roda apenas uma demonstração independente.

## Experimentar

Baixe o pacote `Motor-Lua-Experimental-Windows-x64` na
[workflow de builds](../.github/workflows/lua-engine-port.yml),
extraia os arquivos e execute `Motor-Lua-Demo.exe`.

**Controles:** mouse para olhar, WASD para voar, Espaço sobe,
Ctrl desce, Shift acelera, botão esquerdo quebra bloco,
direito coloca pedra, F6 salva o mapa; Escape libera o cursor.

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
- smoke test de 8 módulos reais: `mcl_init`, `mcl_util`,
  `vl_unittests`, `mcl_colors`, `mcl_sounds`, `mcl_autogroup`,
  `tga_encoder` e `vl_tuning`;
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
que ainda faltam. A CI executa **apenas oito módulos selecionados**,
sem iniciar o jogo. O arquivo `VoxeLibre-Real-Mod-Boot.md`
registra quais módulos e arquivos Lua foram carregados. A presença de uma API
no relatório não significa compatibilidade semântica completa.

Os testes de lógica executam sob Lua 5.4 **e LuaJIT**:
`tests/lua_engine_core.lua` e
`tests/lua_engine_inventory_modloader.lua` e
`tests/lua_engine_crafting.lua` e `tests/lua_engine_rng.lua`.
A demonstração gráfica precisa de hardware Vulkan e teste manual.

O VoxeLibre integral continua disponível em `games/voxelibre/`
através de submódulo Git. **Não removemos o pacote funcional
Luanti + VoxeLibre** enquanto o novo motor não executar esse jogo.
