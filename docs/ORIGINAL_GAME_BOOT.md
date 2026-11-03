# Inicialização integrada de mods originais — lote de implementação

O motor agora pode executar um grafo de mods originais do jogo em ordem
de dependências usando seu próprio runtime Lua. **Isso não significa
que VoxeLibre completo seja jogável**: esta etapa oferece um processo
real de inicialização e um relatório dos bloqueios, sem falsear sucesso.

## Executar o diagnóstico com VoxeLibre original

```sh
python3 scripts/boot_voxelibre.py --game games/voxelibre
python3 scripts/boot_voxelibre.py --game games/voxelibre --lua luajit
```

O Python apenas enumera diretórios reais com mod.conf, depois invoca
um programa Lua que resolve o grafo de dependências e tenta executar
os arquivos originais sem alterar a árvore upstream. Erros de execução
e dependências obrigatórias bloqueadas aparecem no relatório.

## Integração no runtime

```lua
local Boot=require('core.gamebootstrap')
local report=Boot.start(runtime,{
 'games/voxelibre/mods/CORE',
 'games/voxelibre/mods/ITEMS',
 'games/voxelibre/mods/PLAYER'
},fs,{continue_on_error=true})
```

O host injeta fs.walk(root) e fs.read(path). O grafo é planejado
**em conjunto**, inclusive dependências entre categorias. Caminhos
dos mods são publicados antes do início dos scripts. Dependências
obrigatórias malsucedidas bloqueiam os módulos dependentes; os
independentes ainda são executados se continue_on_error=true.

Todos os módulos compartilham um ModEnvironment, mas não o _G do host.
A API get_modnames() enumera os mods registrados em ordem estável.
O loadfile(path) restrito compila sem executar e dofile(path) executa
arquivos Lua nas pastas dos mods registrados. O contador files_executed
inclui apenas chunks realmente executados; não há execução de arquivos
do host fora dessas pastas.

Os callbacks mods_loaded só são chamados quando todos os módulos
carregam; exceções dos callbacks são registradas sem alegar sucesso.
A tentativa não inicia interface gráfica, rede, som nem todos os
serviços do Luanti. Uma falha pode deixar estado parcialmente registrado
no runtime do diagnóstico: esse estado não é considerado um jogo pronto.

## Testes

```sh
lua5.4 tests/lua_engine_game_boot.lua
luajit tests/lua_engine_game_boot.lua
python3 scripts/boot_voxelibre.py --game tests/fixtures/lua_gameboot --lua lua5.4
```

A fixture testa dependências entre CORE, ITEMS e PLAYER, arquivos
originais auxiliares via loadfile/dofile, ambiente isolado, falhas
e módulos bloqueados sem quebrar a inicialização dos independentes.
