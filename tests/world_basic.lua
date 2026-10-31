-- Testes puros do mundo (sem Vulkan / sem LÖVR).
package.path = './?.lua;./?/init.lua;' .. package.path
local saved
lovr = {
  filesystem = {
    read = function() return saved end,
    write = function(_,data) saved=data; return true end
  }
}
local World = require('src.world')
local w = World.new()
assert(w:get(0,-4,0)~=0, 'solo inicial ausente')
local ground = w:spawnHeight(0,0)
local y = math.floor(ground + .49)
assert(w:get(0,y,0)==0, 'spawn obstruido')
assert(w:set(0,y,0,7), 'colocar bloco falhou')
assert(w:get(0,y,0)==7, 'bloco nao colocado')
assert(w:set(0,y,0,0), 'quebrar bloco falhou')
assert(w:get(0,y,0)==0, 'bloco nao quebrado')
assert(not w:set(0,w.YMIN,0,1), 'camada limite nao protegida')
local p={x=0,y=ground,z=0,yaw=.5,pitch=-.2}
assert(w:save(p), 'salvamento falhou')
local reload=World.new()
assert(reload:get(0,y,0)==0, 'blocos alterados nao persistem')
assert(reload.savedPlayer and math.abs(reload.savedPlayer.y-ground)<.001,
  'posicao nao persistiu')
assert(reload.cache['0:0:0'], 'secao cubica nao foi carregada sob demanda')
print('world_basic: OK')
