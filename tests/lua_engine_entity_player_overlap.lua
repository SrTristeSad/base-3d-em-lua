-- Phase 42: symmetric player/LuaEntity collision and safe overlap recovery.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Character=require('core.physics')
local Storage=require('core.entitystorage')
local function p(x,y,z)return {x=x,y=y,z=z} end
local function near(a,b,description)
 assert(math.abs(a-b)<.00001,
  (description or 'value')..': '..tostring(a)..' ~= '..tostring(b))
end
local function world()
 local rt=Runtime.new({auto_pickup=false,item_physics=false})
 local api=rt.api
 api.register_node('test:stone',{})
 api.register_entity('test:body',{
  initial_properties={physical=true,collide_with_objects=true,
   collisionbox={-.3,-.3,-.3,.3,.3,.3}},
  on_step=function(self,dt,res)self.hit=res end
 })
 api.register_entity('test:ghost',{
  initial_properties={physical=false},
  on_step=function(self,dt,res)self.hit=res end
 })
 return rt,api
end
local function connect(rt,api,name,at)
 local player={name=name}
 function player:get_player_name()return self.name end
 local controller=Character.new(api,at or p(0,.5,0),
  {stepheight=0,profile='luanti'})
 rt:connectPlayer(player,controller)
 return player,controller
end
local function floorpad(api)
 for x=-4,12 do
  for z=-1,1 do
   api.set_node(p(x,0,z),{name='test:stone'})
  end
 end
end
-- A player is blocked by a physical entity at the actual collisionbox.
local rt,api=world()
floorpad(api)
local player,char=connect(rt,api,'Alice',p(0,.5,0))
local body=api.add_entity(p(2,.8,0),'test:body')
assert(type(char.object_colliders)=='function')
for i=1,50 do char:update(.05,{x=1}) end
near(char:get_pos().x,1.4,'player stopped at entity surface')
assert(body:get_pos().x==2,'player must not teleport the other object')
local blocked_x=char:get_pos().x
for i=1,10 do char:update(.05,{x=1}) end
near(char:get_pos().x,blocked_x,'standing player remains blocked')
body:set_properties({collide_with_objects=false})
for i=1,25 do char:update(.05,{x=1}) end
assert(char:get_pos().x>2.4,'both flags must permit collision')
-- Host disconnection immediately drops registry obstacle provider.
assert(rt:disconnectPlayer('Alice'))
assert(char.object_colliders==nil)
local controller_pos=char:get_pos().x
char:update(.05,{x=0})
assert(char:get_pos().x>=controller_pos-1)

-- Entity movement toward host player reports real ObjectRef, not a fake.
local rt2,a2=world()
floorpad(a2)
local bob,bobchar=connect(rt2,a2,'Bob',p(2,.5,0))
local moving=a2.add_entity(p(0,.8,0),'test:body')
moving:set_velocity(p(30,0,0))
rt2:step(.1)
near(moving:get_pos().x,1.4,'entity stopped at player')
near(moving:get_velocity().x,0)
local res=moving:get_luaentity().hit
assert(res.collides and #res.collisions==1)
assert(res.collisions[1].type=='object')
assert(res.collisions[1].object==bob,
 'collision object must be identical connected host player')
assert(res.collisions[1].normal.x==-1)
bobchar:set_pos(p(5,.5,0))
moving:set_velocity(p(20,0,0))
rt2:step(.1)
assert(moving:get_pos().x>1.4,'player movement must be read live')
rt2:disconnectPlayer('Bob')
moving:set_pos(p(0,.8,0))
moving:set_velocity(p(30,0,0))
rt2:step(.1)
near(moving:get_pos().x,3,'disconnected player is not an obstacle')

-- A player connected without a controller cannot be assigned fabricated
-- collision geometry; the host remains authoritative and untouched.
local raw={name='Native'}
function raw:get_player_name()return self.name end
rt2:connectPlayer(raw)
moving:set_pos(p(0,.8,0))
moving:set_velocity(p(30,0,0))
rt2:step(.1)
near(moving:get_pos().x,3)
rt2:disconnectPlayer('Native')

-- Newly spawned entity overlaps a player: minimal horizontal escape.
local overlaprt,overapi=world()
floorpad(overapi)
local dana,dchar=connect(overlaprt,overapi,'Dana',p(0,.5,0))
local embedded=overapi.add_entity(p(0,.8,0),'test:body')
overlaprt:step(.01)
local exit=embedded:get_pos()
assert(math.abs(exit.x)>=.6-.00001 or
 math.abs(exit.z)>=.6-.00001,
 'spawn overlapping a player must evacuate without tunneling')
assert(embedded:get_luaentity().hit.collides)
local recovered=embedded:get_luaentity().hit.collisions[1]
assert(recovered.recovery and recovered.type=='object')
assert(recovered.object==dana)
overlaprt:step(.01)
assert(not embedded:get_luaentity().hit.collides,
 'recovered contact cannot repeat indefinitely')
-- A teleport into a solid node can evacuate via a free face.
local stone,sa=world()
sa.set_node(p(0,3,0),{name='test:stone'})
local inside=sa.add_entity(p(0,3,0),'test:body')
stone:step(.01)
local q=inside:get_pos()
assert(math.abs(q.x)>.79 or math.abs(q.y-3)>.79 or
 math.abs(q.z)>.79,'embedded entity must leave solid cube')
local recovery=inside:get_luaentity().hit.collisions[1]
assert(recovery.recovery and recovery.type=='node')
assert(recovery.node_pos.x==0 and recovery.node_pos.y==3)
-- One tiny step should not create a new contact through the same node.
stone:step(.01)
assert(not inside:get_luaentity().hit.collides)

-- Do not teleport out of a closed room to a position occupied by a wall.
local sealed,se=world()
for x=-1,1 do for y=2,4 do for z=-1,1 do
 if x~=-0 or y~=3 or z~=0 then
  se.set_node(p(x,y,z),{name='test:stone'})
 end
end end end
local trapped=se.add_entity(p(0,3,0),'test:body')
sealed:step(.01)
near(trapped:get_pos().x,0)
near(trapped:get_pos().y,3)
near(trapped:get_pos().z,0)
assert(not trapped.removed,'blocked recovery must not destroy object')

-- Nonphysical bodies ignore both other objects and player colliders.
local no_physics,napi=world()
local nplayer,nchar=connect(no_physics,napi,'Eva',p(2,.5,0))
local ghost=napi.add_entity(p(0,.8,0),'test:ghost')
ghost:set_velocity(p(30,0,0))
no_physics:step(.1)
near(ghost:get_pos().x,3)
assert(not ghost:get_luaentity().hit.collides)
no_physics:disconnectPlayer('Eva')

-- Recovery does not mutate persistent snapshots except the corrected pose.
local payload=Storage.encode(overlaprt)
local fresh,fapi=world()
local d,f,e=Storage.restore(fresh,payload)
assert(d==0 and f==0 and e==1)
near(fapi.get_active_lua_entities()[1]:get_pos().x,exit.x)
near(fapi.get_active_lua_entities()[1]:get_pos().z,exit.z)
assert(Storage.encode(fresh)==payload)
-- Connecting after entity spawn enables collision without any engine restart.
local later,la=world()
local target=la.add_entity(p(2,.8,0),'test:body')
local late,lchar=connect(later,la,'Later',p(0,.5,0))
lchar:update(.05,{x=1})
assert(type(lchar.object_colliders)=='function')
later:disconnectPlayer('Later')
assert(lchar.object_colliders==nil)
print('LUA ENGINE PHASE 42 PLAYER COLLISION AND OVERLAP RECOVERY PASS')
