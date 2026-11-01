-- Phase 45: sparse spatial hash broadphase + live lifecycle integration.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Index=require('core.spatialindex')
local EntityPhysics=require('core.entityphysics')
local Physics=require('core.physics')
local Storage=require('core.entitystorage')
local function p(x,y,z)return {x=x,y=y,z=z} end
local function near(a,b)
 assert(math.abs(a-b)<1e-7,tostring(a)..' != '..tostring(b))
end
local function world()
 local rt=Runtime.new({auto_pickup=false,item_physics=false})
 local api=rt.api
 api.register_node('test:stone',{})
 api.register_entity('test:body',{
  initial_properties={physical=true,collide_with_objects=true,
   collisionbox={-.3,-.3,-.3,.3,.3,.3}},
  on_step=function(self,dt,mr)self.result=mr end
 })
 api.register_entity('test:ghost',{
  initial_properties={physical=false}
 })
 return rt,api
end
local function box(x,y,z,r)
 r=r or .3
 return {x-r,y-r,z-r,x+r,y+r,z+r}
end
local rt,api=world()
local entities={}
-- Sparse world: most entities live in unrelated hash buckets.
for i=1,140 do
 local obj=assert(api.add_entity(p(i*8,3,0),'test:body'))
 entities[#entities+1]=obj
end
assert(#Index.query(rt,box(8,3,0))==1)
assert(Index.query(rt,box(8,3,0))[1]==entities[1])
local idx=Index.ensure(rt)
assert(idx.queries>=2 and idx.candidates_examined<=2)
assert(#Index.query(rt,box(0,3,500))==0,
 'far-away query must not enumerate the whole world')
local old_count=idx.candidates_examined
local near_list=Index.query(rt,box(24,3,0,5))
assert(#near_list==1 and near_list[1]==entities[3])
assert(idx.candidates_examined==old_count+1,
 'broadphase should inspect only candidates in query cells')
-- A moving entity changes buckets. Its old cells cannot retain stale refs.
entities[1]:set_pos(p(320,3,100))
assert(#Index.query(rt,box(8,3,0))==0)
assert(Index.query(rt,box(320,3,100))[1]==entities[1])
entities[1]:set_pos(p(16,3,0))
assert(Index.query(rt,box(16,3,0))[1]==entities[1])
-- Two entities occupying same cell preserve registration order.
local same=Index.query(rt,box(16,3,0))
assert(#same==2 and same[1]==entities[1] and same[2]==entities[2])
-- Opt-out and reactivation update membership at runtime.
entities[2]:set_properties({collide_with_objects=false})
assert(#Index.query(rt,box(16,3,0))==1)
entities[2]:set_properties({collide_with_objects=true})
assert(#Index.query(rt,box(16,3,0))==2)
entities[2]:set_properties({physical=false})
assert(#Index.query(rt,box(16,3,0))==1)
entities[2]:set_properties({physical=true})
assert(#Index.query(rt,box(16,3,0))==2)
entities[1]:remove()
assert(#Index.query(rt,box(16,3,0))==1)
assert(Index.query(rt,box(16,3,0))[1]==entities[2])
-- ObjectRef updates from the physics solver also change the index.
local moving=entities[3]
moving:set_velocity(p(80,0,0))
rt:step(.1)
near(moving:get_pos().x,32)
assert(#Index.query(rt,box(24,3,0))==0)
assert(Index.query(rt,box(32,3,0))[1]==moving)
moving:set_velocity(p(0,0,0))
-- Collision with a far-offset body is still detected correctly.
local blocker=api.add_entity(p(42,3,0),'test:body')
moving:set_velocity(p(100,0,0))
rt:step(.1)
near(moving:get_pos().x,41.4)
assert(moving:get_luaentity().result.collides)
assert(moving:get_luaentity().result.collisions[1].object==blocker)
assert(Index.query(rt,box(41.4,3,0))[1]==moving)
-- A nonphysical entity is absent from the broadphase and not a barrier.
api.add_entity(p(100,3,0),'test:ghost')
assert(#Index.query(rt,box(100,3,0))==0)
-- Large collisionboxes span multiple cells, including negative ones.
local wide=api.add_entity(p(-16,3,-16),'test:body')
wide:set_properties({collisionbox={-5,-1,-5,5,1,5}})
assert(Index.query(rt,box(-20,3,-20))[1]==wide)
assert(Index.query(rt,box(-12,3,-12))[1]==wide)
wide:set_properties({collisionbox={-.2,-.2,-.2,.2,.2,.2}})
assert(#Index.query(rt,box(-20,3,-20))==0)
assert(Index.query(rt,box(-16,3,-16))[1]==wide)
-- Querying a giant swept box degrades safely to a linear scan, no giant
-- allocation or missed obstacles at the index's query-volume threshold.
local fallback=Index.query(rt,{-30000,-1,-1,30000,7,1})
assert(#fallback>=139)
assert(idx.fallback_queries>=1)
-- Restoring a new entity list must invalidate the old index automatically.
local saved=Storage.encode(rt)
local old=Index.ensure(rt)
local fresh,newapi=world()
Storage.restore(fresh,saved)
local fresh_index=Index.ensure(fresh)
assert(fresh_index~=old)
assert(#fresh_index.members>=0) -- members are intentionally a map
assert(#Index.query(fresh,box(-16,3,-16))==1)
local previous_list=fresh.luaEntities
local count=select(3,Storage.restore(fresh,saved))
assert(count==#previous_list)
assert(fresh.luaEntities~=previous_list)
assert(Index.ensure(fresh).objects==fresh.luaEntities)
assert(#Index.query(fresh,box(-16,3,-16))==1)
-- A malformed load does not destroy live memberships.
local previous=Index.ensure(fresh)
local keep=Index.query(fresh,box(-16,3,-16))[1]
assert(not pcall(Storage.restore,fresh,'not a valid save'))
assert(Index.query(fresh,box(-16,3,-16))[1]==keep)
assert(Index.ensure(fresh)==previous)
-- Player swept AABBs are filtered by the same index, not all mobs.
local player_rt,papi=world()
for i=1,120 do
 papi.add_entity(p(i*8,3,0),'test:body')
end
local target=papi.add_entity(p(2,3,0),'test:body')
local player={name='Luna'}
function player:get_player_name()return self.name end
local controller=Physics.new(papi,p(0,2.7,0),{profile='luanti',stepheight=0})
player_rt:connectPlayer(player,controller)
local before_queries=Index.ensure(player_rt).queries
local nearboxes=controller.object_colliders(box(2,3,0,1))
assert(#nearboxes==1)
near(nearboxes[1][1],1.7)
assert(Index.ensure(player_rt).queries==before_queries+1)
local stats=Index.ensure(player_rt)
assert(stats.candidates_examined<=3)
controller:update(.05,{x=1})
player_rt:disconnectPlayer('Luna')
assert(controller.object_colliders==nil)
print('LUA ENGINE PHASE 45 SPATIAL COLLISION HASH PASS')
