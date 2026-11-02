# Fase 84 — geometria e geração de chunks alinhados do Luanti 5.18

**Objetivo:** eliminar a limitação de gerar cada mapblock isoladamente, que interrompe os percursos do `CavesRandomWalk`, sem reivindicar que o pipeline final do Luanti está pronto.

## Código-fonte de referência

- [`src/emerge.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/emerge.cpp): `EmergeManager::getContainingChunk`.
- [`src/servermap.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/servermap.cpp): `ServerMap::initBlockMake`, limites com `EMERGE_EXTRA_BORDER`.
- [`src/mapgen/mapgen_v7.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapgen/mapgen_v7.cpp): `blockpos_min/max`, `node_min/max`, `full_node_min/max`, semente do chunk e geração.
- [`src/mapgen/mapgen.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/mapgen/mapgen.cpp): `getBlockSeed2` e ordem de processamento dos sistemas de cavernas.

## Implementação

1. `core/mapgen_chunk.lua` reproduz o deslocamento central `-chunksize / 2` com divisão inteira e busca por contêiner, inclusive em posições negativas. Constrói os limites em coordenadas de **mapblock** e **nó**, incluindo a borda extra de 16 nós.
2. `V7:_generateRegion` compartilha altura, escavação por dois ruídos, cavernas profundas e **uma única sequência de CavesRandomWalk** em toda a região do chunk. O `blockseed` agora usa as coordenadas `full_node_min` do chunk inteiro, como no C++.
3. `V7:generateChunk` gera em um `Map` de estágio separado e só transfere os nós depois do sucesso das etapas. Se houver **qualquer** mapblock existente no chunk (inclusive no disco), recua para a geração isolada anterior sem modificar os mapblocks já existentes.
4. `core.emerge_area` aceita um retorno opcional do gerador com o retângulo completo de nós gerados; marca todos esses mapblocks como gerados, invalida os respectivos caches de ausência do armazenamento e chama `register_on_generated` com os limites da região completa.
5. `Runtime:enableMapgenV7Chunks(config,size)` ativa explicitamente o modo de geração por chunks. O modo prévio `enableMapgenV7Base` permanece inalterado.

## Uso de teste

```lua
local Runtime = require('core.runtime')
local rt = Runtime.new({mapgen={seed=42,mg_name='v7'}})
rt.api.register_node('terrain:stone',{})
rt.api.register_node('terrain:water',{})
local gen = rt:enableMapgenV7Chunks({
  stone='terrain:stone', water='terrain:water',
  randomwalk_caves=true, noise_caves=true
}, {x=2,y=1,z=2})
```

Para que o mundo seja persistente, anexar o `MapBlockStore` com um host de arquivos capaz de gravar atomicamente, como nas fases anteriores. Não se geram nós falsos para representar o conteúdo do VoxeLibre.

## Limites declarados (ainda não é 1:1)

- O cálculo geométrico da classe aceita os tamanhos conhecidos do Luanti, mas o **processamento de chunks está limitado a até 2 mapblocks em cada eixo**, por limites práticos de memória/tempo do protótipo Lua. O Luanti usa tamanho padrão **5×5×5**. A dimensão nativa não está habilitada neste estágio.
- A área `full_node_min/max` é calculada corretamente, mas a geração e a escrita continuam restritas ao **interior** do chunk. O `MMVManip` real com uma borda adicional, preservação de estados `CONTENT_IGNORE`, flags, iluminação e líquidos ainda não foi portado. Isto pode produzir diferenças nas bordas.
- A conexão de cavernas é preservada **dentro** do chunk nesta etapa, mas não necessariamente entre chunks vizinhos.
- Chunks parcialmente existentes recorrem à geração por mapblock, evitando destruição de dados ao custo de fidelidade das transições.
- Callback `emerge_area`: a primeira solicitação que dispara o chunk recebe `EMERGE_GENERATED`; solicitações seguintes para blocos agora residentes recebem `EMERGE_FROM_MEMORY`. O agendamento original do EmergeManager ainda precisa ser reproduzido com fidelidade.
- Os sistemas de biomas, minérios, decorações, masmorras, liquids, lighting e os arredondamentos `float` continuam incompletos.

### Teste automatizado

```sh
lua5.4 tests/lua_engine_chunk_generation.lua
luajit tests/lua_engine_chunk_generation.lua
```

Verifica coordenadas em chunks positivos/negativos, região central e borda, geração de 4 mapblocks sob um único callback, seed e eventos de caminhada, persistência/recarga, fallback diante de alterações preexistentes, modo anterior e limite de chunk.
