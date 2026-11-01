-- Phase 44: exact head-on event boundaries and multi-contact reporting.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Storage=require('core.entitystorage')
local Events=require('core.collisionevents')
local function p(x,y,z)return {x=x,y=y,z=z} end
local function near(a,b,msg)
 assert(math.abs(a-b)<.00001,
  (msg or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
end
local function world()
 local rt=Runtime.new({auto_pickup=false,item_physics=false})
 local api=rt.api
 api.register_node('test:solid',{})
 api.register_entity('test:physical',{
  initial_properties={physical=true,collide_with_objects=true,
   collisionbox={-.3,-.3,-.3,.3,.3,.3},hp_max=10},
  on_step=function(self,dt,mr)
   self.calls=(self.calls or 0)+1
   self.elapsed=(self.elapsed or 0)+dt
   self.last=mr
  end,
 })
 api.register_entity('test:ghost',{
  initial_properties={physical=false},
  on_step=function(self)self.calls=(self.calls or 0)+1 end,
 })
 return rt,api
end
local function hits(result,other)
 local count=0
 for _,c in ipairs(result.collisions) do
  if c.type=='object' and c.object==other then count=count+1 end
 end
 return count
end
-- Events locate the exact contact fraction of two opposite moving AABBs:
-- start gap 3.4, closing velocity 40, duration .2 => 0.425 frame.
local rt,api=world()
local left=api.add_entity(p(0,3,0),'test:physical')
local right=api.add_entity(p(4,3,0),'test:physical')
left:set_velocity(p(20,0,0))
right:set_velocity(p(-20,0,0))
local times=Events.schedule({left,right},.2,5)
local found=false
for i,t in ipairs(times) do
 if math.abs(t-.425)<1e-8 then found=true end
 if i>1 then assert(t>times[i-1]) end
end
assert(found,'contact boundary must include analytic head-on TOI')
near(times[#times],1)
rt:step(.2)
near(left:get_pos().x,1.7,'symmetric first contact x')
near(right:get_pos().x,2.3,'symmetric second contact x')
near(left:get_velocity().x,0)
near(right:get_velocity().x,0)
assert(left:get_luaentity().calls==1 and right:get_luaentity().calls==1)
near(left:get_luaentity().elapsed,.2)
assert(hits(left:get_luaentity().last,right)==1)
assert(hits(right:get_luaentity().last,left)==1)
local firstcontact=left:get_luaentity().last.collisions[1]
assert(firstcontact.normal.x==-1 and firstcontact.coordinated)
local secondcontact=right:get_luaentity().last.collisions[1]
assert(secondcontact.normal.x==1)
rt:step(.1)
assert(not left:get_luaentity().last.collides and
 not right:get_luaentity().last.collides,
 'a resting touching pair must not fire repeat collisions')

-- Three-body crowd: two runners hit the SAME stationary middle NPC.
-- The middle NPC receives both distinct contacts in a single on_step.
local crowd,ca=world()
local a=ca.add_entity(p(0,3,0),'test:physical')
local b=ca.add_entity(p(4,3,0),'test:physical')
local c=ca.add_entity(p(8,3,0),'test:physical')
a:set_velocity(p(40,0,0))
c:set_velocity(p(-40,0,0))
crowd:step(.2)
near(a:get_pos().x,3.4,'left approach to crowded middle')
near(b:get_pos().x,4,'stationary middle position')
near(c:get_pos().x,4.6,'right approach to crowded middle')
local middle=b:get_luaentity().last
assert(middle.collides and #middle.collisions==2,
 'middle creature must learn about impacts from both neighbors')
assert(hits(middle,a)==1 and hits(middle,c)==1)
assert(hits(a:get_luaentity().last,b)==1)
assert(hits(c:get_luaentity().last,b)==1)
assert(a:get_luaentity().calls==1 and
 b:get_luaentity().calls==1 and c:get_luaentity().calls==1)
-- A second pass does not invent impacts when all three are stationary.
crowd:step(.1)
assert(not b:get_luaentity().last.collides)

-- Three dynamic bodies: first impact halts A and B; C then reaches B.
local chain,cha=world()
local p1=cha.add_entity(p(0,3,0),'test:physical')
local p2=cha.add_entity(p(4,3,0),'test:physical')
local p3=cha.add_entity(p(8,3,0),'test:physical')
p1:set_velocity(p(60,0,0))
p2:set_velocity(p(-30,0,0))
p3:set_velocity(p(-60,0,0))
chain:step(.2)
assert(p1:get_pos().x+.6<=p2:get_pos().x+1e-6)
assert(p2:get_pos().x+.6<=p3:get_pos().x+1e-6)
assert(hits(p2:get_luaentity().last,p1)==1)
assert(hits(p2:get_luaentity().last,p3)==1)
assert(p1:get_luaentity().calls==1 and
 p2:get_luaentity().calls==1 and p3:get_luaentity().calls==1)
assert(p2:get_luaentity().last.collides)

-- Opt-out and nonphysical entities do not create phantom event times.
local disabled,da=world()
local solid=da.add_entity(p(0,3,0),'test:physical')
local pass=da.add_entity(p(4,3,0),'test:physical')
solid:set_velocity(p(20,0,0))
pass:set_velocity(p(-20,0,0))
pass:set_properties({collide_with_objects=false})
local no_events=Events.schedule({solid,pass},.2,4)
assert(#no_events==4)
disabled:step(.2)
assert(solid:get_pos().x>3 and pass:get_pos().x<1)
local ghost=da.add_entity(p(10,3,0),'test:ghost')
ghost:set_velocity(p(-10,0,0))
assert(#Events.schedule({solid,ghost},.2,3)==3)

-- Bounded event search does not explode in large NPC groups.
local huge={}
for i=1,129 do
 huge[i]={removed=false,pos=p(i*3,3,0),
  velocity=p(i%2==0 and -20 or 20,0,0),
  acceleration=p(0,0,0),
  properties={physical=true,collide_with_objects=true,
   collisionbox={-.3,-.3,-.3,.3,.3,.3}}}
end
assert(#Events.schedule(huge,.2,5)==5,
 'large worlds must use the bounded fallback schedule')
-- Saved world data remains independent from ephemeral moveresult contacts.
local data=Storage.encode(crowd)
local restored,ra=world()
local drops,falls,entities=Storage.restore(restored,data)
assert(drops==0 and falls==0 and entities==3)
assert(Storage.encode(restored)==data)
print('LUA ENGINE PHASE 44 MULTIBODY CONTACT EVENTS PASS')
