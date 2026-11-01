-- Phase 43: dynamic collision substeps and connected player-player solids.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local Storage=require('core.entitystorage')
local function p(x,y,z)return {x=x,y=y,z=z} end
local function near(a,b,why)
 assert(math.abs(a-b)<1e-5,
  (why or 'value')..': '..tostring(a)..' ~= '..tostring(b))
end
local function world()
 local rt=Runtime.new({auto_pickup=false,item_physics=false})
 local api=rt.api
 api.register_node('test:stone',{})
 api.register_entity('test:body',{
  initial_properties={physical=true,collide_with_objects=true,
   collisionbox={-.3,-.3,-.3,.3,.3,.3}},
  on_step=function(self,dt,moveresult)
   self.count=(self.count or 0)+1
   self.elapsed=(self.elapsed or 0)+dt
   self.hit=moveresult
  end
 })
 api.register_entity('test:ghost',{
  initial_properties={physical=false},
  on_step=function(self)self.count=(self.count or 0)+1 end
 })
 return rt,api
end
local function connect(rt,api,name,pos)
 local player={name=name}
 function player:get_player_name()return self.name end
 local controller=Physics.new(api,pos,{profile='luanti',stepheight=0})
 rt:connectPlayer(player,controller)
 return player,controller
end
-- Two fast, head-on moving bodies should meet near their swept relative
-- time of impact, NOT wait until the first body reaches the other body's
-- initial x coordinate and force the second to stand still.
local rt,api=world()
local left=api.add_entity(p(0,3,0),'test:body')
local right=api.add_entity(p(4,3,0),'test:body')
left:set_velocity(p(20,0,0))
right:set_velocity(p(-20,0,0))
rt:step(.2)
assert(left:get_pos().x>1.35 and left:get_pos().x<2,
 'fast head-on collision must advance the first body to contact')
assert(right:get_pos().x>2 and right:get_pos().x<2.65,
 'fast head-on collision must advance the second body to contact')
near(right:get_pos().x-left:get_pos().x,.6,
 'colliding swept AABBs should be separated at contact')
assert(left:get_velocity().x==0 and right:get_velocity().x==0)
assert(left:get_luaentity().count==1 and right:get_luaentity().count==1,
 'microsteps must not deliver multiple on_step callbacks')
near(left:get_luaentity().elapsed,.2)
assert(left:get_luaentity().hit.collides)
assert(right:get_luaentity().hit.collides)
assert(left:get_luaentity().hit.collisions[1].type=='object')
assert(right:get_luaentity().hit.collisions[1].type=='object')
assert(left:get_luaentity().hit.collisions[1].object==right)
assert(right:get_luaentity().hit.collisions[1].object==left)
-- No repeated callbacks for two stationary touching bodies.
rt:step(.1)
assert(left:get_luaentity().count==2 and right:get_luaentity().count==2)
assert(not left:get_luaentity().hit.collides)
assert(not right:get_luaentity().hit.collides)

-- Ground collisions remain aggregated across substeps. The callback
-- gets a single ground contact event, not one per microstep.
local fall,fa=world()
for x=-2,3 do fa.set_node(p(x,0,0),{name='test:stone'}) end
local a=fa.add_entity(p(0,2,0),'test:body')
local b=fa.add_entity(p(3,2,0),'test:body')
a:set_velocity(p(.1,-20,0))
b:set_velocity(p(-.1,-20,0))
fall:step(.2)
near(a:get_pos().y,.8,'first body must land at ground top')
near(b:get_pos().y,.8,'second body must land at ground top')
local ahit=a:get_luaentity().hit
assert(ahit.touching_ground and ahit.collides)
assert(#ahit.collisions==1,
 'collision aggregation should not flood callbacks with repeated floor hits')
assert(ahit.collisions[1].type=='node' and
 ahit.collisions[1].axis=='y')
assert(a:get_luaentity().count==1 and b:get_luaentity().count==1)
-- One moving object and a stationary blocker preserve existing single pass
-- behavior; slow/mod scripted entity callbacks should not be reordered.
local single,sa=world()
local callback_order={}
sa.register_entity('test:order',{
 on_step=function(self)
  callback_order[#callback_order+1]=self.object:get_id()
  if self.object:get_id()==1 then
   self.object:remove()
   sa.add_entity(p(6,3,0),'test:order')
  end
 end
})
sa.add_entity(p(0,3,0),'test:order')
sa.add_entity(p(1,3,0),'test:order')
single:step(.1)
assert(#callback_order==2 and callback_order[1]==1 and
 callback_order[2]==2)
single:step(.1)
assert(#callback_order==4 and callback_order[3]==2 and
 callback_order[4]==3)

-- Player controllers block one another using live session positions.
local people,pa=world()
for x=-4,12 do pa.set_node(p(x,0,0),{name='test:stone'}) end
local alice,ac=connect(people,pa,'Alice',p(0,.5,0))
local bob,bc=connect(people,pa,'Bob',p(2,.5,0))
for i=1,60 do
 ac:update(.05,{x=1})
 bc:update(.05,{x=-1})
end
assert(ac:get_pos().x<bc:get_pos().x)
near(bc:get_pos().x-ac:get_pos().x,.6,
 'players must remain separated by collisionboxes')
local previous=ac:get_pos().x
people:disconnectPlayer('Bob')
assert(bc.object_colliders==nil and type(ac.object_colliders)=='function')
for i=1,25 do ac:update(.05,{x=1}) end
assert(ac:get_pos().x>previous+1,'disconnect removes player collider')
people:disconnectPlayer('Alice')
assert(ac.object_colliders==nil)
-- Players from other worlds and unbound native host objects do not
-- contribute fabricated obstacles.
local separate,sep=world()
local other_player,other_controller=connect(separate,sep,'Other',p(0,.5,0))
local walker,walker_controller=connect(separate,sep,'Walker',p(0,.5,3))
for i=1,10 do walker_controller:update(.05,{x=1}) end
assert(walker_controller:get_pos().x>0)
separate:disconnectPlayer('Other')
separate:disconnectPlayer('Walker')

-- Persist both bodies after a dynamic impact; collider references in
-- transient moveresult never enter the data-only snapshot.
local saved=Storage.encode(rt)
local fresh,fapi=world()
local drops,falling,entities=Storage.restore(fresh,saved)
assert(drops==0 and falling==0 and entities==2)
local persisted=fapi.get_active_lua_entities()
near(persisted[1]:get_pos().x,left:get_pos().x)
near(persisted[2]:get_pos().x,right:get_pos().x)
near(persisted[1]:get_velocity().x,0)
assert(Storage.encode(fresh)==saved)
print('LUA ENGINE PHASE 43 MOVING COLLISION AND PLAYER PAIRS PASS')
