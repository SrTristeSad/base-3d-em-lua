-- Phase 8: CPU particle-spawner bookkeeping and inventory permission callbacks.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Particles=require('core.particles')
local r=Runtime.new()
local a=r.api
local function eq(x,y)
 assert(x==y,'expected '..tostring(y)..', got '..tostring(x))
end
for _,p in ipairs({{x=0,y=0,z=0},{x=-1,y=2,z=-3},
 {x=-32768,y=-32768,z=-32768},{x=32767,y=32767,z=32767}}) do
 local n=a.hash_node_position(p)
 local q=a.get_position_from_hash(n)
 eq(q.x,p.x);eq(q.y,p.y);eq(q.z,p.z)
 eq(n,Particles.hash_node_position(p))
end
assert(not pcall(a.hash_node_position,{x=32768,y=0,z=0}))
assert(not pcall(a.get_position_from_hash,-1))
assert(not pcall(a.get_position_from_hash,281474976710656))
local d={amount=3,texture='smoke.png',nested={size=2}}
local one=a.add_particlespawner(d)
eq(one,1)
d.nested.size=19
eq(r.particles:get_spawner(one).nested.size,2)
local copy=r.particles:get_spawner(one)
copy.nested.size=71
eq(r.particles:get_spawner(one).nested.size,2)
eq(a.delete_particlespawner(one),true)
eq(a.delete_particlespawner(one),false)
eq(r.particles:get_spawner(one),nil)
local two=a.add_particlespawner({amount=1})
eq(two,2)
local accepted,why=a.add_particle({texture='smoke.png'})
eq(accepted,false)
assert(why:find('renderer'))
assert(not pcall(a.add_particlespawner,'invalid'))
local events={}
a.register_allow_player_inventory_action(function(_,action,_,info)
 events[#events+1]='check'
 if action=='move' and info.to_list=='protected' then return 0 end
 return nil
end)
a.register_allow_player_inventory_action(function()
 return 4
end)
a.register_on_player_inventory_action(function(_,action)
 events[#events+1]=action
end)
eq(r:allowedInventoryAction(nil,'move',nil,{
 from_list='main',to_list='protected',count=7}),0)
eq(r:allowedInventoryAction(nil,'move',nil,{
 from_list='main',to_list='other',count=7}),4)
eq(r:allowedInventoryAction(nil,'put',nil,{
 stack=a.ItemStack('test:stone 2')}),2)
r:emit('on_player_inventory_action',nil,'move',nil,{count=1})
eq(events[#events],'move')
assert(not pcall(r.allowedInventoryAction,r,nil,'move',nil,{count=-4}))
assert(a.show_formspec('player','test','size[2,2]')==false,
 'offline formspec calls must not create a fake player session')
local c=a.colorize('#ff0088','Hello')
assert(c:find('Hello',1,true))
assert(c:find('#ff0088',1,true))
print('lua_engine_particles_inventory: OK')
