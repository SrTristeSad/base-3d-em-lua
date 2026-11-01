-- Phase 40: real node collision results for registered LuaEntities.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Storage=require('core.entitystorage')
local Nodebox=require('core.nodebox')
local function p(x,y,z) return {x=x,y=y,z=z} end
local function near(a,b,why)
 assert(math.abs(a-b)<1e-6,
  (why or 'value')..': '..tostring(a)..' ~= '..tostring(b))
end
local function world()
 local rt=Runtime.new({auto_pickup=false,item_physics=false})
 local a=rt.api
 a.register_node('test:stone',{})
 a.register_node('test:airlike',{walkable=false})
 a.register_node('test:slab',{drawtype='nodebox',
  node_box={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}}})
 a.register_node('test:thin',{drawtype='nodebox',
  node_box={type='fixed',fixed={-.125,-.5,-.125,.125,.5,.125}}})
 a.register_node('test:rotated',{drawtype='nodebox',paramtype2='4dir',
  node_box={type='fixed',fixed={-.375,-.5,-.125,.375,.5,.125}}})
 a.register_node('test:connected',{drawtype='nodebox',
  connects_to={'test:airlike'},
  node_box={type='connected',
   fixed={-.125,-.5,-.125,.125,.5,.125},
   connect_right={.125,-.1,-.125,.5,.1,.125}}})
 a.register_entity('test:physical',{
  initial_properties={physical=true,collide_with_objects=false,
   collisionbox={-.3,-.3,-.3,.3,.3,.3}},
  on_step=function(self,dt,moveresult)
   self.last=moveresult
  end,
 })
 a.register_entity('test:ghost',{
  initial_properties={physical=false,collisionbox={-.3,-.3,-.3,.3,.3,.3}},
  on_step=function(self,dt,moveresult)self.last=moveresult end,
 })
 return rt,a
end

-- Native Luanti LuaEntities are not automatically subject to gravity:
-- their scripts call set_acceleration. With negative acceleration they fall.
local ground,api=world()
for x=-3,12 do for z=-1,1 do
 api.set_node(p(x,0,z),{name='test:stone'})
end end
local still=api.add_entity(p(0,6,0),'test:physical')
ground:step(.2)
near(still:get_pos().y,6,'no gravity without mod acceleration')
still:set_acceleration(p(0,-9.81,0))
ground:step(5)
near(still:get_pos().y,.8,'floor collision')
near(still:get_velocity().y,0,'vertical speed cleared')
local mr=still:get_luaentity().last
assert(mr.collides and mr.touching_ground and #mr.collisions==1)
local contact=mr.collisions[1]
assert(contact.type=='node' and contact.axis=='y')
assert(contact.node_pos.y==0 and contact.normal.y==1)
assert(contact.old_velocity.y==0 and contact.new_velocity.y==0)
ground:step(.1)
near(still:get_pos().y,.8,'must rest stably on floor')
assert(still:get_luaentity().last.touching_ground)
-- Vertical jump changes grounded state until next downward contact.
still:set_acceleration(p(0,-9.81,0))
still:set_velocity(p(0,8,0))
ground:step(.1)
assert(still:get_pos().y>.8)
assert(not still:get_luaentity().last.touching_ground)
assert(still:get_velocity().y>0)

-- High-speed movement cannot tunnel through a node; it slides parallel
-- to a wall after horizontal contact.
local wall,wa=world()
wa.set_node(p(3,3,0),{name='test:stone'})
local runner=wa.add_entity(p(0,3,0),'test:physical')
runner:set_velocity(p(100,0,2))
wall:step(.1)
near(runner:get_pos().x,2.2,'fast wall stop')
near(runner:get_pos().z,.2,'slide along wall')
near(runner:get_velocity().x,0)
near(runner:get_velocity().z,2)
local bump=runner:get_luaentity().last
assert(bump.collides and not bump.touching_ground)
assert(#bump.collisions==1 and bump.collisions[1].axis=='x')
assert(bump.collisions[1].node_pos.x==3)
assert(bump.collisions[1].normal.x==-1)
near(bump.collisions[1].old_velocity.x,100)

-- Half-height collision stops at the actual slab surface, not cell top.
local half,ha=world()
ha.set_node(p(0,0,0),{name='test:slab'})
local jumping=ha.add_entity(p(0,8,0),'test:physical')
jumping:set_acceleration(p(0,-9.81,0))
half:step(3)
near(jumping:get_pos().y,.3,'slab collision top')
assert(jumping:get_luaentity().last.touching_ground)
local thin,ta=world()
ta.set_node(p(2,3,0),{name='test:thin'})
local narrow=ta.add_entity(p(0,3,0),'test:physical')
narrow:set_velocity(p(50,0,0))
thin:step(.1)
near(narrow:get_pos().x,2-.125-.3,'thin post stop')
local outside=ta.add_entity(p(0,3,.5),'test:physical')
outside:set_velocity(p(50,0,0))
thin:step(.1)
near(outside:get_pos().x,5,'empty space beside thin nodebox')

-- Orientation of collision boxes changes the physical hit boundary.
for orient=0,3 do
 local rt,a=world()
 a.set_node(p(2,3,0),{name='test:rotated',param2=orient})
 local node=a.get_node(p(2,3,0))
 local boxes=Nodebox.boxes(rt.registry.nodes[node.name],node,
  rt.map,p(2,3,0),rt.registry.nodes,'collision_box')
 local obj=a.add_entity(p(0,3,0),'test:physical')
 obj:set_velocity(p(50,0,0))
 rt:step(.1)
 near(obj:get_pos().x,2+boxes[1][1]-.3,'4dir orientation')
end
-- Connected nodeboxes add collision arms even through nonwalkable nodes.
local connect,ca=world()
ca.set_node(p(2,3,0),{name='test:connected'})
ca.set_node(p(3,3,0),{name='test:airlike'})
local beam=ca.add_entity(p(2.35,3,-2),'test:physical')
beam:set_velocity(p(0,0,30))
connect:step(.1)
near(beam:get_pos().z,-.125-.3,'connected arm contact')

-- Nonphysical scripted entities still move freely, matching Phase 38.
local rt,g=world()
g.set_node(p(2,3,0),{name='test:stone'})
local ghost=g.add_entity(p(0,3,0),'test:ghost')
ghost:set_velocity(p(50,0,0))
rt:step(.1)
near(ghost:get_pos().x,5)
assert(not ghost:get_luaentity().last.collides)
assert(not ghost:get_luaentity().last.touching_ground)
-- physical flag must be a boolean: failed update is transactional.
local survivor=g.add_entity(p(0,4,0),'test:physical')
assert(not pcall(survivor.set_properties,survivor,{physical='true'}))
assert(survivor:get_properties().physical==true)

-- Preserve physics flags and acceleration across the Phase 39 sidecar.
local saved=Storage.encode(half)
local loaded,la=world()
local drops,falls,entities=Storage.restore(loaded,saved)
assert(drops==0 and falls==0 and entities==1)
local restored=la.get_active_lua_entities()[1]
assert(restored:get_properties().physical==true)
near(restored:get_acceleration().y,-9.81)
near(restored:get_pos().y,.3)
la.set_node(p(0,0,0),{name='test:slab'})
loaded:step(.1)
near(restored:get_pos().y,.3)
assert(restored:get_luaentity().last.touching_ground)
assert(Storage.encode(loaded)~=nil)

print('LUA ENGINE PHASE 40 LUAENTITY COLLISION PHYSICS PASS')
