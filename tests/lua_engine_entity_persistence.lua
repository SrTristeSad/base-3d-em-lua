-- Phase 39: persistent registered LuaEntities using Luanti get_staticdata.
-- Snapshot files remain plain data-only "LUAENGINE OBJECTS 1".
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Entities=require('core.entitystorage')
local Serialization=require('core.serialization')
local function p(x,y,z) return {x=x,y=y,z=z} end
local function near(a,b)
 assert(math.abs(a-b)<1e-7,tostring(a)..' != '..tostring(b))
end
local events={}
local function world(opts)
 local rt=Runtime.new(opts or {auto_pickup=false,item_physics=false})
 local api=rt.api
 api.register_craftitem('test:gem',{})
 api.register_node('test:stone',{})
 api.register_entity('test:mob',{
  initial_properties={visual='cube',textures={'default_stone.png'},
   hp_max=15,collisionbox={-.3,-.3,-.3,.3,.3,.3},
   selectionbox={-.4,-.4,-.4,.4,.4,.4}},
  on_activate=function(self,data,elapsed)
   self.counter=tonumber(data) or 0
   events[#events+1]='activate:'..self.counter..':'..elapsed
   self.object:set_velocity(p(99,0,0))
  end,
  get_staticdata=function(self)
   return tostring(self.counter)
  end,
  on_step=function(self,dt)
   self.counter=self.counter+1
  end,
  on_deactivate=function(self,removal)
   events[#events+1]=removal and 'remove' or 'unload'
  end
 })
 return rt,api
end

local rt,api=world()
local a=assert(api.add_entity(p(1,4,2),'test:mob','7'))
local b=assert(api.add_entity(p(-3,5,1),'test:mob','2'))
a:set_velocity(p(.5,0,-.75))
a:set_acceleration(p(0,-2,0))
a:set_yaw(1.25)
a:set_properties({hp_max=8,visual_size={x=2,y=1}})
a:set_hp(5)
b:set_velocity(p(0,.1,0))
b:set_hp(3)
rt:step(.25)
assert(a:get_luaentity().counter==8 and b:get_luaentity().counter==3)
local a_pos=a:get_pos()
local a_vel=a:get_velocity()
local a_acc=a:get_acceleration()
local a_yaw=a:get_yaw()
local a_hp=a:get_hp()
local b_pos=b:get_pos()
api.add_item(p(4,2,0),'test:gem 6')
local saved=Entities.encode(rt)
assert(saved:sub(1,#'LUAENGINE OBJECTS 1\n')=='LUAENGINE OBJECTS 1\n')
assert(saved:find('lua_entities',1,true))
assert(saved:find('test:mob',1,true))
assert(#api.get_active_lua_entities()==2)

-- Restore into an independent runtime, preserving world entities AND drops.
local fresh,fresh_api=world()
local old=fresh_api.add_entity(p(8,8,8),'test:mob','42')
local count_drops,count_falling,count_entities=Entities.restore(fresh,saved)
assert(count_drops==1 and count_falling==0 and count_entities==2)
assert(old.removed and old:get_luaentity()==nil,
 'old world refs must be invalidated after successful reload')
assert(events[#events]=='unload',
 'old live entity must receive on_deactivate(false)')
local current=fresh_api.get_active_lua_entities()
assert(#current==2 and current[1]~=a and current[2]~=b)
local aa,bb=current[1],current[2]
near(aa:get_pos().x,a_pos.x)
near(aa:get_pos().y,a_pos.y)
near(aa:get_pos().z,a_pos.z)
near(bb:get_pos().x,b_pos.x)
near(aa:get_velocity().x,a_vel.x)
near(aa:get_velocity().z,a_vel.z)
near(aa:get_acceleration().y,a_acc.y)
near(aa:get_yaw(),a_yaw)
assert(aa:get_hp()==a_hp and bb:get_hp()==3)
assert(aa:get_properties().hp_max==8)
assert(aa:get_properties().visual_size.x==2)
assert(aa:get_luaentity().counter==8 and bb:get_luaentity().counter==3)
assert(fresh_api.get_dropped_items()[1].stack:get_count()==6)
assert(Entities.encode(fresh)==saved,
 'round trip must preserve staticdata, physics, HP and properties')
fresh:step(.1)
assert(aa:get_luaentity().counter==9)
assert(bb:get_luaentity().counter==4)
assert(fresh_api.get_active_lua_entities()[1]==aa)

-- The same path is used by the LÖVR demo filesystem adapter.
local fs={}
function fs.write(path,data)fs[path]=data;return true end
function fs.read(path)return fs[path] end
assert(Entities.save(rt,'world.objects',fs))
assert(fs['world.objects']==saved)
local another,another_api=world()
local nd,nf,ne=Entities.load(another,'world.objects',fs)
assert(nd==1 and nf==0 and ne==2)
assert(another_api.get_active_lua_entities()[1]:get_luaentity().counter==8)
assert(Entities.encode(another)==saved)

-- Old Phase 34/35/36/37 saves lack lua_entities: load as empty safely.
local legacy='LUAENGINE OBJECTS 1\n'..
 Serialization.serialize({drops={},falling={}})
local clean,cleanapi=world()
local first=cleanapi.add_entity(p(0,0,0),'test:mob','5')
local d,f,e=Entities.restore(clean,legacy)
assert(d==0 and f==0 and e==0)
assert(#cleanapi.get_active_lua_entities()==0 and first.removed)
assert(not cleanapi.get_active_lua_entities()[1])

-- Reject unknown definitions BEFORE changing any live world objects.
local wrong,wrongapi=world()
local permanent=wrongapi.add_entity(p(2,3,4),'test:mob','11')
local original=Entities.encode(wrong)
local unknown=saved:gsub('test:mob','test:unknown')
assert(not pcall(Entities.restore,wrong,unknown))
assert(wrongapi.get_active_lua_entities()[1]==permanent)
assert(Entities.encode(wrong)==original)

-- Corrupted staticdata, invalid yaw, and unsafe expressions are rejected.
local parsed=Serialization.deserialize(saved:sub(#'LUAENGINE OBJECTS 1\n'+1))
parsed.lua_entities[1].yaw=math.huge
assert(not pcall(Serialization.serialize,parsed))
parsed.lua_entities[1].yaw=0
parsed.lua_entities[1].staticdata=string.rep('x',65537)
local too_large='LUAENGINE OBJECTS 1\n'..Serialization.serialize(parsed)
assert(not pcall(Entities.restore,wrong,too_large))
parsed.lua_entities[1].staticdata='7'
parsed.lua_entities[1].hp=100
assert(not pcall(Entities.restore,wrong,
 'LUAENGINE OBJECTS 1\n'..Serialization.serialize(parsed)))
assert(not pcall(Entities.restore,wrong,
 'LUAENGINE OBJECTS 1\nreturn os.execute("no")'))
assert(wrongapi.get_active_lua_entities()[1]==permanent)
assert(Entities.encode(wrong)==original)

-- Bad get_staticdata never produces a partial save.
local invalid,invalidapi=world()
invalidapi.register_entity('test:broken',{
 get_staticdata=function()return {unserializable='table'} end
})
invalidapi.add_entity(p(0,0,0),'test:broken')
assert(not pcall(Entities.encode,invalid))
local maxed,maxapi=world({max_lua_entities=1})
maxapi.add_entity(p(0,0,0),'test:mob')
assert(not pcall(Entities.restore,maxed,saved))
assert(#maxapi.get_active_lua_entities()==1)

-- Activation failure rolls back the staged list without destroying refs.
local broken,brokenapi=world()
brokenapi.register_entity('test:mob',{
 initial_properties={hp_max=15},
 on_activate=function(self,data)
  if data=='8' then error('intentional activation error') end
 end,
 get_staticdata=function()return 'stable' end
})
local intact=brokenapi.add_entity(p(9,9,9),'test:mob')
local before=Entities.encode(broken)
assert(not pcall(Entities.restore,broken,saved))
assert(#brokenapi.get_active_lua_entities()==1)
assert(brokenapi.get_active_lua_entities()[1]==intact and not intact.removed)
assert(Entities.encode(broken)==before)

-- Removal and world shutdown have different on_deactivate flags.
local lifecycle,lapi=world()
local removed=lapi.add_entity(p(1,1,1),'test:mob')
local unloaded=lapi.add_entity(p(2,1,1),'test:mob')
removed:remove()
assert(events[#events]=='remove')
lifecycle:deactivateLuaEntities()
assert(events[#events]=='unload')
assert(unloaded.removed and unloaded:get_luaentity()==nil)
assert(#lapi.get_active_lua_entities()==0)
print('LUA ENGINE PHASE 39 ENTITY PERSISTENCE PASS')
