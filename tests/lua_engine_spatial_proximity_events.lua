-- Phase 46: exact center-radius lookup for ALL LuaEntities, plus
-- indexed TOI event selection in worlds with >128 physical objects.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Storage=require('core.entitystorage')
local Index=require('core.spatialindex')
local Events=require('core.collisionevents')
local function p(x,y,z)return {x=x,y=y,z=z} end
local function near(a,b,label)
 assert(math.abs(a-b)<1e-5,
  (label or 'value')..': '..tostring(a)..' != '..tostring(b))
end
local function world()
 local rt=Runtime.new({auto_pickup=false,item_physics=false})
 local api=rt.api
 api.register_node('test:stone',{})
 api.register_entity('test:solid',{
  initial_properties={physical=true,collide_with_objects=true,
   collisionbox={-.3,-.3,-.3,.3,.3,.3}},
  on_step=function(self,dt,result)
   self.calls=(self.calls or 0)+1
   self.last=result
  end
 })
 api.register_entity('test:ghost',{
  initial_properties={physical=false,collide_with_objects=false,
   collisionbox={-.3,-.3,-.3,.3,.3,.3}}
 })
 return rt,api
end
-- The original core.get_objects_inside_radius tests DISTANCE FROM CENTER,
-- not AABB intersection, including nonphysical registered entities.
local rt,api=world()
local ghosts={}
local body=assert(api.add_entity(p(0,3,0),'test:solid'))
ghosts[1]=assert(api.add_entity(p(0,3,0),'test:ghost'))
ghosts[2]=assert(api.add_entity(p(2,3,0),'test:ghost'))
ghosts[3]=assert(api.add_entity(p(-2,3,0),'test:ghost'))
for i=1,160 do api.add_entity(p(i*12,3,100),'test:ghost') end
local zero=api.get_objects_inside_radius(p(0,3,0),0)
assert(#zero==2 and zero[1]==body and zero[2]==ghosts[1],
 'radius zero must include coincident physical and nonphysical centers')
local near_list=api.get_objects_inside_radius(p(0,3,0),2)
assert(#near_list==4 and near_list[1]==body and
 near_list[2]==ghosts[1] and near_list[3]==ghosts[2] and
 near_list[4]==ghosts[3],
 'radius query must preserve registration ordering, not distance ordering')
assert(#api.get_objects_inside_radius(p(0,3,0),1.99)==2)
assert(not pcall(api.get_objects_inside_radius,p(0,3,0),-0.1))
assert(not pcall(api.get_objects_inside_radius,p(0,3,0),math.huge))
assert(not pcall(api.get_objects_inside_radius,p(32000,3,0),1))
local stats=Index.ensure(rt)
local checked=stats.proximity_candidates_examined
assert(#api.get_objects_inside_radius(p(0,3,0),.5)==2)
assert(stats.proximity_candidates_examined-checked<=4,
 'small search must not walk all 160 distant LuaEntities')
-- Neither physical nor collide_with_objects flags affect radius results.
ghosts[2]:set_properties({physical=true,collide_with_objects=true})
assert(api.get_objects_inside_radius(p(2,3,0),0)[1]==ghosts[2])
ghosts[2]:set_properties({physical=false,collide_with_objects=false})
assert(api.get_objects_inside_radius(p(2,3,0),0)[1]==ghosts[2])
-- Teleports and movement must update center buckets.
ghosts[3]:set_pos(p(-12,3,0))
assert(#api.get_objects_inside_radius(p(-2,3,0),0)==0)
assert(api.get_objects_inside_radius(p(-12,3,0),0)[1]==ghosts[3])
ghosts[3]:set_pos(p(-2,3,0))
ghosts[1]:remove()
assert(api.get_objects_inside_radius(p(0,3,0),0)[1]==body)
assert(#api.get_objects_inside_radius(p(0,3,0),0)==1)
-- The fallback searches every active center, including ghost objects.
local before_fallback=stats.proximity_fallback_queries
local all=api.get_objects_inside_radius(p(0,3,0),30000)
assert(#all==163)
assert(stats.proximity_fallback_queries==before_fallback+1)
assert(all[1]==body and all[2]==ghosts[2] and all[3]==ghosts[3])
-- Saved entity lists are reconstructed, not persisted as index tables.
local data=Storage.encode(rt)
local fresh,fa=world()
local d,f,e=Storage.restore(fresh,data)
assert(d==0 and f==0 and e==163)
assert(#fa.get_objects_inside_radius(p(0,3,0),0)==1)
assert(#fa.get_objects_inside_radius(p(0,3,0),30000)==163)
assert(Storage.encode(fresh)==data)
local previous=Index.ensure(fresh)
local original=fa.get_objects_inside_radius(p(-2,3,0),0)[1]
assert(not pcall(Storage.restore,fresh,'invalid'))
assert(Index.ensure(fresh)==previous)
assert(fa.get_objects_inside_radius(p(-2,3,0),0)[1]==original)

-- Long-distance physical mobs now run the same TOI event solver even
-- when the world has more than the former 128-body cutoff.
local crowded,ca=world()
for i=1,130 do ca.add_entity(p(i*16,3,100),'test:solid') end
local left=ca.add_entity(p(0,3,0),'test:solid')
local right=ca.add_entity(p(4,3,0),'test:solid')
left:set_velocity(p(20,0,0))
right:set_velocity(p(-20,0,0))
-- Compatibility of the direct, unbound algorithm remains unchanged.
assert(#Events.schedule(crowded.luaEntities,.2,5)==5,
 'legacy three-argument schedule retains >128 fallback')
local indexed=Events.schedule(crowded.luaEntities,.2,5,crowded)
local found=false
for _,time in ipairs(indexed) do
 if math.abs(time-.425)<1e-8 then found=true end
end
assert(found,'indexed planner must retain nearby head-on TOI over 128 mobs')
local index=Index.ensure(crowded)
local examined_before=index.candidates_examined
crowded:step(.2)
near(left:get_pos().x,1.7,'left head-on contact in crowded world')
near(right:get_pos().x,2.3,'right head-on contact in crowded world')
near(left:get_velocity().x,0)
near(right:get_velocity().x,0)
assert(left:get_luaentity().calls==1 and right:get_luaentity().calls==1)
assert(left:get_luaentity().last.collides and
 right:get_luaentity().last.collides)
assert(left:get_luaentity().last.collisions[1].object==right)
assert(right:get_luaentity().last.collisions[1].object==left)
-- Candidate counts do not pretend to measure actual graphics FPS.
assert(index.candidates_examined-examined_before<300,
 'indexed event planner should not enumerate every distant NPC pair')
crowded:step(.1)
assert(not left:get_luaentity().last.collides)
assert(not right:get_luaentity().last.collides)
-- Opt-outs must not create event boundaries in large worlds.
right:set_properties({physical=false,collide_with_objects=false})
left:set_pos(p(0,3,0));right:set_pos(p(4,3,0))
left:set_velocity(p(20,0,0));right:set_velocity(p(-20,0,0))
assert(#Events.schedule(crowded.luaEntities,.2,5,crowded)==5)
crowded:step(.2)
near(left:get_pos().x,4)
near(right:get_pos().x,0)
print('LUA ENGINE PHASE 46 PROXIMITY AND INDEXED EVENT PAIRS PASS')
