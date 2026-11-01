-- Regression for translucent cube boundaries and crossed plantlike geometry.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Engine=require('core.runtime')
local Mesher=require('core.mesher')
local Atlas=require('core.atlas')
local rt=Engine.new()
rt.api.register_node('test:stone',{tiles={'default_stone.png'}})
rt.api.register_node('test:glass',{drawtype='glasslike',
 use_texture_alpha='blend',tiles={'default_stone.png'}})
rt.api.register_node('test:water',{drawtype='liquid',
 use_texture_alpha='blend',tiles={'mcl_core_water_source_animation.png'}})
rt.api.register_node('test:flower',{drawtype='plantlike',
 tiles={'flowers_dandelion_yellow.png'},walkable=false})
local map=rt.map
local function p(x,y,z)return {x=x,y=y,z=z}end
local function meshed()
 return Mesher.build(map,rt.registry.nodes,0,0,0)
end
map:set_node(p(0,0,0),{name='test:glass'})
local mesh,stats=meshed()
assert(stats.faces==6 and stats.cubes==1 and stats.plants==0)
map:set_node(p(1,0,0),{name='test:glass'})
mesh,stats=meshed()
assert(stats.faces==10 and #mesh==60,
 'adjacent glass should not double-render shared faces')
map:set_node(p(0,0,0),{name='test:stone'})
mesh,stats=meshed()
assert(stats.faces==11,
 'stone next to glass must keep its face; glass face behind stone is hidden')
map:set_node(p(1,0,0),{name='air'})
map:set_node(p(2,0,0),{name='test:water'})
map:set_node(p(3,0,0),{name='test:water'})
mesh,stats=meshed()
assert(stats.liquids==2 and stats.faces==16,
 'adjacent liquid blocks must not render shared internal surfaces')
map:set_node(p(5,0,0),{name='test:flower'})
mesh,stats=meshed()
assert(stats.plants==1 and stats.faces==20 and #mesh==120,
 'plantlike must emit two crossed, double-sided quads')
local flower=Mesher.build((function()
 local m=Engine.new().map
 m:set_node(p(5,0,0),{name='test:flower'})
 return m
end)(),rt.registry.nodes,0,0,0)
assert(#flower==24,'two crossed quads must have four visible sides')
for i=1,24,6 do
 local v=flower[i]
 assert(math.abs(v[4])>.7 and math.abs(v[6])>.7 and v[5]==0,
  'crossed plane normals must be diagonal')
 local a,b,c=flower[i],flower[i+1],flower[i+2]
 local u={b[1]-a[1],b[2]-a[2],b[3]-a[3]}
 local w={c[1]-a[1],c[2]-a[2],c[3]-a[3]}
 local cross={u[2]*w[3]-u[3]*w[2],
  u[3]*w[1]-u[1]*w[3],u[1]*w[2]-u[2]*w[1]}
 assert(cross[1]*v[4]+cross[2]*v[5]+cross[3]*v[6]>0,
  'plant plane triangle winding must point outward')
end
assert(Atlas.index('flowers_dandelion_yellow.png')==16)
assert(Atlas.index('mcl_core_water_source_animation.png')==12)
print('LUA ENGINE MATERIAL TYPES PASS')
