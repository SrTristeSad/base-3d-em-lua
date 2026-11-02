# Fase 91 — snapshot de blocos no MMVManip::initialEmerge(false)

## Código original utilizado

O Luanti 5.18 implementa `MMVManip::initialEmerge(p_min, p_max, load_if_inexistent)` em [`src/map.cpp`](https://github.com/luanti-org/luanti/blob/5.18.0/src/map.cpp#L805-L856) e usa `getCoveredBlocks` / `blitBackAll` posteriormente. Se um `MapBlock` já está carregado, `MapBlock::copyTo` copia seu conteúdo para o `VoxelManipulator`. Se não está, a região fica com a flag `VOXELFLAG_NO_DATA` quando `load_if_inexistent=false`.

## Adições em Lua/LuaJIT

- `MapgenVoxelBuffer:initialEmerge(false)` captura **uma única vez** os mapblocks carregados dentro da geometria completa com a borda de um mapblock em X/Y/Z. Não cria nem carrega blocos do disco.
- Captura nós não-ar incluindo `param1` e `param2`. Mapblocks carregados inteiramente de ar permanecem reconhecidos como **ar conhecido**, não `CONTENT_IGNORE`.
- Integra os marcadores `map.revisions`, `last_active`, `lbm_applied` e também **blocos conhecidos apenas por metadados e/ou temporizadores**, conforme a política atual de `MapBlockStore:resident`.
- `get_node`, `get_flags`, `terrain_writable`, `getCoveredBlocks` e os caminhos seguros de escavação de terreno residente passam a observar os dados capturados, não novas alterações no mapa vivo.
- O `MapgenV7:generateChunk` agora chama `initialEmerge(false)` antes de importar os sidecars provisórios e antes de executar os estágios de terreno e cavernas. A geração isolada em fallback usa a mesma etapa.
- A validação de alterações em blocos residentes continua sendo feita **antes de aplicar modificações** ao mapa vivo.

O método `initialEmerge(true)` **não está implementado** nesta fase e falha de forma explícita, para não afirmar indevidamente que pode criar/carregar mapblocks nativos.

## Testes

```bash
lua5.4 tests/lua_engine_mmvm_initial_emerge.lua
luajit tests/lua_engine_mmvm_initial_emerge.lua
```

Verifica: nó e parâmetros capturados; blocos somente com metadata/timer; ar conhecido em mapblocks carregados; `CONTENT_IGNORE` em blocos ausentes; cópia imutável diante de alteração posterior no mapa; prevenção de commits conflitantes; ausência de IO de mapblock durante `initialEmerge(false)`; carga explícita posterior via `MapBlockStore:emerge`; e integração na geração real de um chunk V7.

## Limites

Esta é uma **implementação de snapshot para uma única geração**, não o `initialEmerge` nativo completo: não oferece expansão subsequente de `VoxelArea` nem `initialEmerge(true)`, tampouco cópia densa de todos os voxels e flags adicionais. Continua usando a estrutura esparsa Lua e as sobreposições em sidecars.

A separação entre `MapBlock` criado, `MapBlock` carregado e `MapBlock` já gerado ainda não é equivalente à estrutura nativa do Luanti. O porte completo do motor, incluindo biomas, iluminação e líquidos, segue incompleto; **não está comprovada a execução integral do VoxeLibre original**.
