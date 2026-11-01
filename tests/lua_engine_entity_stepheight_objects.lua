-- Phase 41: grounded stepheight, object-object blocking and native flags.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Storage=require('core.entitystorage')
local function p(x,y,z)return {x=x,y=y,z=z} end
local function near(a,b,desc)
 assert(math.abs(a-b)<.00001,
  (desc or 'value')..' '..tostring(a)..' ~= '..tostring(b))
end
local function world()
 local rt=Runtime.new({auto_pickup=false,item_physics=false})
 local a=rt.api
 a.register_node('test:stone',{})
 a.register_node('test:slab',{drawtype='nodebox',node_box={
  type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}}})
 a.register_entity('test:body',{
  initial_properties={physical=true,
   collisionbox={-.3,-.3,-.3,.3,.3,.3},hp_max=12},
  on_step=function(self,dt,moveresult)self.result=moveresult end
 })
 a.register_entity('test:ghost',{
  initial_properties={physical=false},
  on_step=function(self,dt,moveresult)self.result=moveresult end
 })
 return rt,a
end
local function floorpad(a)
 for x=-2,12 do
  a.set_node(p(x,0,0),{name='test:stone'})
 end
end
-- Ground support before horizontal movement, then step and drop onto ledge.
local climb,ca=world()
floorpad(ca)
ca.set_node(p(2,1,0),{name='test:stone'})
local walker=ca.add_entity(p(0,.8,0),'test:body')
assert(walker:get_properties().stepheight==0)
assert(walker:get_properties().collide_with_objects==true)
walker:set_properties({stepheight=1.05})
walker:set_velocity(p(3,0,0))
walker:set_acceleration(p(0,-9.81,0))
climb:step(1)
near(walker:get_pos().x,3,'step crosses full one-node obstacle')
near(walker:get_pos().y,.8,'past step drops onto original floor')
-- The step was traversed but a fall to the following flat floor is normal.
assert(walker:get_luaentity().result.touching_ground)
near(walker:get_velocity().y,0)
-- At the same step, stop *on* the raised surface rather than falling.
local elevated,ea=world()
floorpad(ea)
ea.set_node(p(2,1,0),{name='test:stone'})
local climbing=ea.add_entity(p(0,.8,0),'test:body')
climbing:set_properties({stepheight=1.05})
climbing:set_acceleration(p(0,-9.81,0))
climbing:set_velocity(p(2,0,0))
elevated:step(1)
near(climbing:get_pos().x,2)
near(climbing:get_pos().y,1.8,'must end on top of full node')
assert(climbing:get_luaentity().result.touching_ground)
elevated:step(.1)
near(climbing:get_pos().y,1.8,'step-height landing must remain grounded')
-- With the default stepheight zero, collision remains exactly Phase 40.
local blocked,ba=world()
floorpad(ba)
ba.set_node(p(2,1,0),{name='test:stone'})
local stuck=ba.add_entity(p(0,.8,0),'test:body')
stuck:set_velocity(p(2,0,0))
stuck:set_acceleration(p(0,-9.81,0))
blocked:step(1)
near(stuck:get_pos().x,1.2)
assert(stuck:get_luaentity().result.collides)
assert(stuck:get_luaentity().result.collisions[1].axis=='x')
-- Ceiling prevents the raised candidate; cannot noclip through overhang.
local roof,ra=world()
floorpad(ra)
ra.set_node(p(2,1,0),{name='test:stone'})
ra.set_node(p(0,2,0),{name='test:stone'})
local low=ra.add_entity(p(0,.8,0),'test:body')
low:set_properties({stepheight=1.05})
low:set_velocity(p(2,0,0))
low:set_acceleration(p(0,-9.81,0))
roof:step(1)
near(low:get_pos().x,1.2,'blocked by low ceiling')
-- Off the edge, stepheight must not invent support while airborne.
local air,aa=world()
aa.set_node(p(2,1,0),{name='test:stone'})
local flying=aa.add_entity(p(0,.8,0),'test:body')
flying:set_properties({stepheight=1.05})
flying:set_velocity(p(2,0,0))
air:step(1)
near(flying:get_pos().x,1.2,'airborne cannot step over wall')
-- A half-slab of 0.5 height can be crossed with just .6 stepheight.
local half,ha=world()
floorpad(ha)
ha.set_node(p(2,1,0),{name='test:slab'})
local stair=ha.add_entity(p(0,.8,0),'test:body')
stair:set_properties({stepheight=.6})
stair:set_velocity(p(2,0,0))
stair:set_acceleration(p(0,-9.81,0))
half:step(1)
near(stair:get_pos().x,2)
near(stair:get_pos().y,1.3,'0.5-high slab landing')
-- Physical bodies with collide_with_objects=true block other entities.
local objects,oa=world()
local stationary=oa.add_entity(p(2,3,0),'test:body')
local mover=oa.add_entity(p(0,3,0),'test:body')
mover:set_velocity(p(30,0,0))
objects:step(.1)
near(mover:get_pos().x,1.4,'cannot pass a stationary physical entity')
near(stationary:get_pos().x,2)
near(mover:get_velocity().x,0)
local result=mover:get_luaentity().result
assert(result.collides and not result.touching_ground)
assert(#result.collisions==1)
assert(result.collisions[1].type=='object')
assert(result.collisions[1].object==stationary)
assert(result.collisions[1].axis=='x' and
 result.collisions[1].normal.x==-1)
near(result.collisions[1].old_velocity.x,30)
near(result.collisions[1].new_velocity.x,0)
-- If either party opts out, they no longer block one another.
local optout,op=world()
local target=op.add_entity(p(2,3,0),'test:body')
target:set_properties({collide_with_objects=false})
local runner=op.add_entity(p(0,3,0),'test:body')
runner:set_velocity(p(30,0,0))
optout:step(.1)
near(runner:get_pos().x,3,'other object opted out')
assert(not runner:get_luaentity().result.collides)
-- Nonphysical objects do not act as barriers.
local ghostworld,ga=world()
ga.add_entity(p(2,3,0),'test:ghost')
local passing=ga.add_entity(p(0,3,0),'test:body')
passing:set_velocity(p(30,0,0))
ghostworld:step(.1)
near(passing:get_pos().x,3)
-- Both moving objects see current obstacle positions in deterministic
-- runtime update order; they must not tunnel through one another.
local both,bo=world()
local first=bo.add_entity(p(0,3,0),'test:body')
local second=bo.add_entity(p(2,3,0),'test:body')
first:set_velocity(p(10,0,0))
second:set_velocity(p(-10,0,0))
both:step(.1)
assert(first:get_pos().x+.3<=second:get_pos().x-.3+1e-8,
 'sequential collision response must leave the two volumes disjoint')
assert(first:get_luaentity().result.collides or
 second:get_luaentity().result.collides)
-- Reject invalid physical tuning without damaging earlier settings.
local safe,sa=world()
local ref=sa.add_entity(p(0,3,0),'test:body')
for _,bad in ipairs({-1,math.huge,4,'1',0/0}) do
 assert(not pcall(ref.set_properties,ref,{stepheight=bad}))
end
assert(not pcall(ref.set_properties,ref,{collide_with_objects='false'}))
assert(ref:get_properties().stepheight==0)
assert(ref:get_properties().collide_with_objects==true)
ref:set_properties({stepheight=.4,collide_with_objects=false})
local snapshot=Storage.encode(safe)
local loaded,la=world()
local d,f,e=Storage.restore(loaded,snapshot)
assert(d==0 and f==0 and e==1)
local restored=la.get_active_lua_entities()[1]
near(restored:get_properties().stepheight,.4)
assert(restored:get_properties().collide_with_objects==false)
assert(Storage.encode(loaded)==snapshot)
print('LUA ENGINE PHASE 41 STEPHEIGHT AND OBJECT COLLISION PASS')
