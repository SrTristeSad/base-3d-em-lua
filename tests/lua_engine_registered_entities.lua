-- Phase 38: registered LuaEntity lifecycle, ObjectRef and geometric aiming.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Character=require('core.physics')
local function p(x,y,z)return {x=x,y=y,z=z} end
local function near(a,b)assert(math.abs(a-b)<1e-6,
 tostring(a)..' ~= '..tostring(b)) end
local rt=Runtime.new({auto_pickup=false,item_physics=false})
local api=rt.api
api.register_craftitem('test:gem',{})
api.register_node('test:stone',{})
local activation,steps,punches,clicks={},{},{},{}
api.register_entity('test:mob',{
 initial_properties={visual='cube',textures={'default_stone.png'},
  collisionbox={-.4,-.5,-.3,.4,.5,.3},
  selectionbox={-.25,-.5,-.25,.25,.5,.25},
  hp_max=12,pointable=true},
 tags={nested={value='isolated'}},
 on_activate=function(self,data,elapsed)
  activation[#activation+1]={self=self,staticdata=data,time=elapsed}
  self.counter=tonumber(data) or 0
 end,
 on_step=function(self,dt,result)
  assert(result and result.collides==false)
  self.counter=self.counter+1
  steps[#steps+1]={id=self.object:get_id(),dt=dt}
 end,
 on_punch=function(self,player,interval,caps,dir,damage)
  punches[#punches+1]={id=self.object:get_id(),player=player,
   elapsed=interval,damage=damage}
  self.object:set_hp(self.object:get_hp()-2)
 end,
 on_rightclick=function(self,player)
  clicks[#clicks+1]={id=self.object:get_id(),player=player}
 end,
})
local a=assert(api.add_entity(p(2,3,0),'test:mob','4'))
local b=assert(api.add_entity(p(4,3,0),'test:mob'))
assert(a:get_id()~=b:get_id() and a:is_player()==false)
assert(#activation==2 and activation[1].staticdata=='4' and
 activation[1].time==0 and activation[1].self==a:get_luaentity())
assert(a:get_luaentity().counter==4 and
 b:get_luaentity().counter==0)
assert(a:get_luaentity().object==a)
assert(a:get_hp()==12 and b:get_hp()==12)
local one=a:get_luaentity()
one.tags.nested.value='changed'
assert(b:get_luaentity().tags.nested.value=='isolated',
 'registered definition tables must be independent per instance')
assert(rt.registry.entities['test:mob'].tags.nested.value=='isolated')
local q=a:get_pos();q.x=-99
assert(a:get_pos().x==2,'get_pos needs defensive snapshot')
a:set_velocity(p(2,0,0))
local v=a:get_velocity();v.x=20
assert(a:get_velocity().x==2)
a:set_acceleration(p(-2,0,0))
near(a:get_acceleration().x,-2)
rt:step(.5)
near(a:get_pos().x,2.75)
near(a:get_velocity().x,1)
assert(one.counter==5 and b:get_luaentity().counter==1)
assert(#steps==2 and steps[1].id==a:get_id() and
 steps[2].id==b:get_id())
assert(#api.get_active_lua_entities()==2)
assert(api.get_objects_inside_radius(p(2.75,3,0),.01)[1]==a)
assert(#api.get_objects_inside_radius(p(0,0,0),.25)==0)

-- ObjectRef setters validate inputs without partially changing current state.
assert(not pcall(a.set_pos,a,p(math.huge,0,0)))
assert(not pcall(a.set_velocity,a,p(0/0,0,0)))
assert(not pcall(a.set_rotation,a,p(.2,0,0)),
 'unsupported non-yaw rotation must fail explicitly')
a:set_rotation(p(0,1.5,0))
near(a:get_yaw(),1.5)
a:set_yaw(.4)
near(a:get_rotation().y,.4)
a:set_hp(99)
assert(a:get_hp()==12)
a:set_hp(-5)
assert(a:get_hp()==0)
a:set_hp(12)
local props=a:get_properties()
props.textures[1]='unrelated'
props.selectionbox[1]=-10
assert(a:get_properties().textures[1]=='default_stone.png')
assert(a:get_properties().selectionbox[1]==-.25)
assert(not pcall(a.set_properties,a,{selectionbox={1,1,1,0,0,0}}))
assert(a:get_properties().selectionbox[1]==-.25)
a:set_properties({visual_size={x=2,y=2},hp_max=6})
assert(a:get_hp()==6 and b:get_hp()==12)
assert(a:get_properties().visual_size.x==2)
assert(b:get_properties().visual_size==nil)

-- The renderer and raycast can use actual pointable ObjectRefs.
local head=p(0,3,0)
local ray=assert(rt:raycast(head,p(1,0,0),6))
assert(ray.type=='object' and ray.ref==a)
near(ray.distance,a:get_pos().x-.25)
local pointed={}
for result in api.raycast(head,p(6,3,0),true,false) do
 pointed[#pointed+1]=result
end
assert(#pointed==2 and pointed[1].ref==a and pointed[2].ref==b)
a:set_properties({pointable=false})
assert(rt:raycast(head,p(1,0,0),6).ref==b,
 'nonpointable LuaEntity must be excluded')
a:set_properties({pointable=true})

-- A registered node blocks entity targeting behind it.
api.set_node(p(1,3,0),{name='test:stone'})
assert(rt:raycast(head,p(1,0,0),6).type=='node')
api.remove_node(p(1,3,0))

-- Host-player interaction routes callbacks only to the selected entity.
local alice={name='Alice'}
function alice:get_player_name()return self.name end
rt:connectPlayer(alice,Character.new(api,p(0,2,0)))
local ok,obj=rt:interactObjectAlongRay(alice,p(0,3.6,0),p(1,0,0),6,'punch')
-- The ray y=3.6 is above the entity selectionbox top (3.5), so no hit.
assert(not ok and obj=='not_object')
local eye=p(0,3.3,0)
ok,obj=rt:interactObjectAlongRay(alice,eye,p(1,0,0),6,'punch')
assert(ok and obj==a and #punches==1 and punches[1].player==alice)
assert(a:get_hp()==4)
ok,obj=rt:interactObjectAlongRay(alice,eye,p(1,0,0),6,'rightclick')
assert(ok and obj==a and #clicks==1 and clicks[1].player==alice)
ok,obj=rt:interactObjectAlongRay(alice,p(100,3.3,0),p(1,0,0),6,'punch')
assert(not ok and obj=='invalid_origin')
assert(not pcall(rt.interactObjectAlongRay,rt,alice,eye,p(1,0,0),6,'unknown'))
rt:disconnectPlayer('Alice')
assert(not pcall(rt.interactObjectAlongRay,rt,alice,eye,p(1,0,0),6,'punch'))

-- Entities can remove themselves or spawn others without stepping new
-- entities in the same tick or skipping adjacent callbacks.
local nested=Runtime.new()
local na=nested.api
local events={}
na.register_entity('test:child',{on_step=function(self)
 events[#events+1]='child'
end})
na.register_entity('test:parent',{on_step=function(self)
 events[#events+1]='parent'
 self.object:remove()
 na.add_entity(p(0,0,0),'test:child')
end})
na.register_entity('test:neighbor',{on_step=function(self)
 events[#events+1]='neighbor'
end})
local parent=na.add_entity(p(0,0,0),'test:parent')
na.add_entity(p(1,0,0),'test:neighbor')
nested:step(.1)
assert(table.concat(events,',')=='parent,neighbor')
assert(parent.removed and parent:get_luaentity()==nil)
assert(#na.get_active_lua_entities()==2)
nested:step(.1)
assert(table.concat(events,',')=='parent,neighbor,neighbor,child')
parent:remove()
assert(not pcall(parent.set_pos,parent,p(0,0,0)))
assert(not pcall(parent.set_properties,parent,{visual='cube'}))

-- Activation errors cannot leave phantom entities.
na.register_entity('test:faulty',{on_activate=function() error('boom') end})
local before=#na.get_active_lua_entities()
assert(not pcall(na.add_entity,p(0,0,0),'test:faulty'))
assert(#na.get_active_lua_entities()==before)
assert(na.add_entity(p(0,0,0),'test:missing')==nil)
assert(not pcall(na.add_entity,p(math.huge,0,0),'test:child'))
local limited=Runtime.new({max_lua_entities=1})
limited.api.register_entity('test:child',{})
assert(limited.api.add_entity(p(0,0,0),'test:child'))
assert(limited.api.add_entity(p(1,0,0),'test:child')==nil)
-- Automatic drops remain unaffected by LuaEntity lookup.
local item=api.add_item(p(2,3,0),'test:gem 2')
local local_objects=api.get_objects_inside_radius(p(2,3,0),3)
local found=false
for _,entry in ipairs(local_objects) do
 if entry==item then found=true end
end
assert(found,'radius query must expose loose items as well')
item:remove()
assert(#api.get_active_lua_entities()==2)
print('LUA ENGINE PHASE 38 REGISTERED ENTITIES PASS')
