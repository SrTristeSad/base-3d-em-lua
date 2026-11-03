# Integração de objetos e áudio (runtime Lua)

Este lote adiciona APIs úteis para mods de jogabilidade do VoxeLibre original.
Não declara que o jogo já iniciou completamente ou que o demo possui áudio audível.

## Consultas a objetos

`core.get_objects_inside_radius(pos,radius)` agora considera, em conjunto,
LuaEntities ativas, entidades de itens soltos no mundo e PlayerRefs
realmente conectados. `core.get_objects_in_area(minp,maxp)` consulta
o centro dos mesmos tipos de objeto em um paralelepípedo inclusivo.
As consultas devolvem referências reais; objetos removidos e jogadores
sem posição válida não entram. A ordem estável no adaptador Lua é
LuaEntities, itens e jogadores ordenados por nome. Não é uma garantia
de ordenação da API nativa Luanti.

## Ponte de áudio

`core.sound_play(spec,params,ephemeral)`, `core.sound_stop(handle)` e
`core.sound_fade(handle,step,gain)` agora existem no runtime Lua.
O SoundSpec aceita nome, ganho, fade, pitch, loop e início; os
parâmetros aceitam posição, ObjectRef, ganho, distância de audição,
destinatário e exclusão de jogador, com validação de valores finitos.

Para sons audíveis, o host precisa fornecer um backend de reprodução
real antes do uso, ao construir o runtime:

```lua
local rt=Runtime.new({sound_backend=backend})
-- backend:play(spec,params,ephemeral) -> native_ref ou nil
-- backend:stop(native_ref)
-- backend:fade(native_ref,step,gain)
```

O motor gera handles Lua inteiros somente quando o backend informa
que a reprodução foi iniciada. `ephemeral=true` não produz handle;
o backend é responsável por concluir a reprodução. Sem backend,
sem recurso de áudio ou quando a reprodução falha, `sound_play` retorna
`nil` — não produz sons falsos. Um backend pode ser associado depois
por `runtime:setSoundBackend(backend)` se não houver sons ativos.
Os handles ativos são finalizados no shutdown do mundo. O host
também pode informar encerramento espontâneo com
`runtime.sounds:finished(handle)`.

Limites: não há empacotamento/carregamento automático dos arquivos
de som originais, sincronização de áudio por rede, atenuação espacial
implementada no núcleo nem reprodução automática no demo LÖVR.
Essas responsabilidades exigem um backend de áudio de host conectado.

## Regressão

```sh
lua5.4 tests/lua_engine_world_objects_sound.lua
luajit tests/lua_engine_world_objects_sound.lua
```

Os testes abrangem ObjectRefs de entidades, itens e PlayerRefs,
remoções, fronteiras espaciais, efeitos colaterais dos callbacks
e controle de sons com um backend de teste, sem afirmar que ele
produziu áudio real.
