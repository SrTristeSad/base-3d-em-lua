-- Phase 52: live terrain edits keep physics and nearby connected shapes
-- current without wiping the whole collision cache on every node change.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Geometry=require('core.collisiongeometry')
local MapIndex=require('core.mapnodeindex')
local Nodebox=require('core.nodebox')
local Physics=require('core.physics')
local function p(x,y,z)return {x=x,y=y,z=z} end
local function near(x,y)assert(math.abs(x-y)<1e-6,tostring(x)..' != '..tostring(y))end
local function world()
 local rt=Runtime.new({auto_pickup=false,item_physics=false})
 local api=rt.api
 api.register_node('test:stone',{})
 api.register_node('test:slab',{drawtype='nodebox',node_box={
  type='fixed',fixed={-.5,-.5,-.5,.5,-.2,.5}}})
 api.register_node('test:fence',{drawtype='nodebox',
  connects_to={'test:fence'},
  node_box={type='connected',
   fixed={-.1,-.5,-.1,.1,.5,.1},
   connect_left={-.5,-.1,-.1,-.1,.1,.1},
   connect_right={.1,-.1,-.1,.5,.1,.1}}})
 api.register_node('test:angle',{drawtype='nodebox',paramtype2='facedir',
  node_box={type='fixed',fixed={-.5,-.5,-.2,.5,.5,.2}}})
 return rt,api
end
local function around(x,y,z)
 return {x-.25,y-.25,z-.25,x+.25,y+.25,z+.25}
end
local function boxes_for(rt,pos)
 local list=Geometry.collect(rt,around(pos.x,pos.y,pos.z),0,true)
 local result={}
 for _,entry in ipairs(list) do
  if entry.node_pos.x==pos.x and entry.node_pos.y==pos.y and
     entry.node_pos.z==pos.z then result[#result+1]=entry.box end
 end
 return result
end
local function exact(rt,pos)
 local node=rt.map:get_node(pos)
 local def=rt.registry.nodes[node.name]
 if not def or def.walkable==false or def.buildable_to then return {} end
 local list={}
 for _,b in ipairs(Nodebox.boxes(
  def,node,rt.map,pos,rt.registry.nodes,'collision_box')) do
  list[#list+1]={pos.x+b[1],pos.y+b[2],pos.z+b[3],
   pos.x+b[4],pos.y+b[5],pos.z+b[6]}
 end
 return list
end
local function verify(rt,pos,label)
 local got=boxes_for(rt,pos)
 local raw=exact(rt,pos)
 assert(#got==#raw,label..' boxes mismatch '..#got..'/'..#raw)
 for i=1,#got do for j=1,6 do
  near(got[i][j],raw[i][j])
 end end
 return got
end
local rt,api=world()
local a,b,c=p(0,0,0),p(64,0,0),p(15,0,0)
api.set_node(a,{name='test:stone'})
api.set_node(b,{name='test:stone'})
api.set_node(c,{name='test:fence'})
api.set_node(p(16,0,0),{name='test:fence'})
verify(rt,a,'initial local')
verify(rt,b,'initial distant')
verify(rt,c,'initial connected at mapblock edge')
local cache=Geometry.cache(rt)
local far=cache.data['64,0,0']
local original=cache.data['0,0,0']
local idx=MapIndex.ensure(rt.map)
assert(far and original and idx.count==4)
local prior_updates=cache.selective_updates
local oldrev=rt.map.geometry_revision
api.set_node(a,{name='test:stone'})
assert(rt.map.geometry_revision==oldrev)
assert(cache.selective_updates==prior_updates,
 'no-op edit must not invalidate the cache')
api.swap_node(a,{name='test:slab'})
assert(Geometry.cache(rt)==cache,'local node edit should keep cache object')
assert(cache.selective_updates==prior_updates+1)
assert(cache.data['0,0,0']==nil)
assert(cache.data['64,0,0']==far,
 'far-away cached block must remain warm')
assert(idx.count==4 and MapIndex.ensure(rt.map)==idx)
verify(rt,a,'slab replaces cube')
assert(cache.data['0,0,0']~=original)
-- Changing a connected neighbor over the x=15/16 mapblock boundary
-- must update the unmoved fence's collision box on the next query.
local connected=cache.data['15,0,0']
api.remove_node(p(16,0,0))
assert(cache.data['15,0,0']==nil)
assert(cache.data['64,0,0']==far)
assert(idx.count==3)
verify(rt,c,'connected neighbor removed')
assert(cache.data['15,0,0']~=connected)
api.set_node(p(16,0,0),{name='test:fence'})
verify(rt,c,'connected neighbor restored')
assert(idx.count==4)
-- A param2 orientation change uses the same localized update.
api.set_node(p(-1,0,0),{name='test:angle',param2=1})
verify(rt,p(-1,0,0),'initial facing')
api.swap_node(p(-1,0,0),{name='test:angle',param2=13})
verify(rt,p(-1,0,0),'changed facing')
assert(cache.data['64,0,0']==far)
-- VoxelManip write_to_map routes through Map:set_node too.
local vm=api.get_voxel_manip(p(0,0,0),p(0,0,0))
vm:set_node_at(p(0,0,0),{name='test:stone'})
assert(vm:write_to_map()==1)
verify(rt,a,'voxel manip rebuilds collision geometry')
assert(cache.data['64,0,0']==far)
-- A definition override is broader than a local edit and must still
-- invalidate all cached shapes, even on an unchanged map revision.
local before_override=Geometry.cache(rt)
api.override_item('test:stone',{collision_box={
 type='fixed',fixed={-.5,-.5,-.5,.5,-.3,.5}}})
assert(Geometry.cache(rt)~=before_override)
verify(rt,a,'definition override')
-- Replacing map.nodes without an official edit must trigger a safe rebuild.
local prev_cache=Geometry.cache(rt)
local prev_index=MapIndex.ensure(rt.map)
local new_nodes={}
for k,v in pairs(rt.map.nodes) do new_nodes[k]=v end
rt.map.nodes=new_nodes
assert(Geometry.cache(rt)~=prev_cache)
assert(MapIndex.ensure(rt.map)~=prev_index)
verify(rt,a,'map storage replacement')
-- The runtime's own globalstep runs before entity physics in the frame.
local tickrt,tickapi=world()
tickapi.register_entity('test:runner',{
 initial_properties={physical=true,collisionbox={-.3,-.3,-.3,.3,.3,.3}},
 on_step=function(self,dt,result)self.last=result end})
local runner=tickapi.add_entity(p(0,0,0),'test:runner')
local ticks=0
tickapi.register_globalstep(function()
 ticks=ticks+1
 if ticks==1 then tickapi.set_node(p(4,0,0),{name='test:stone'})
 elseif ticks==2 then tickapi.remove_node(p(4,0,0)) end
end)
runner:set_velocity(p(20,0,0))
tickrt:step(.2)
near(runner:get_pos().x,3.2)
assert(runner:get_luaentity().last.collides)
assert(runner:get_luaentity().last.collisions[1].type=='node')
runner:set_pos(p(0,0,0))
runner:set_velocity(p(20,0,0))
tickrt:step(.2)
near(runner:get_pos().x,4)
assert(not runner:get_luaentity().last.collides,
 'removed wall must not remain in the entity collision cache')
-- Callbacks of earlier nonphysical entities can alter the collision
-- geometry seen by later physical objects in the SAME runtime step.
local callback_rt,callback_api=world()
local build=true
callback_api.register_entity('test:builder',{
 initial_properties={physical=false},
 on_step=function()
  if build then
   callback_api.set_node(p(4,0,0),{name='test:stone'})
  else
   callback_api.remove_node(p(4,0,0))
  end
 end})
callback_api.register_entity('test:runner',{
 initial_properties={physical=true,collisionbox={-.3,-.3,-.3,.3,.3,.3}},
 on_step=function(self,dt,result)self.last=result end})
callback_api.add_entity(p(100,0,0),'test:builder')
local second=callback_api.add_entity(p(0,0,0),'test:runner')
second:set_velocity(p(20,0,0))
callback_rt:step(.2)
near(second:get_pos().x,3.2)
assert(second:get_luaentity().last.collides)
build=false
second:set_pos(p(0,0,0))
second:set_velocity(p(20,0,0))
callback_rt:step(.2)
near(second:get_pos().x,4)
-- Player sweeps use updated geometry after adding/removing a wall.
local player_rt,player_api=world()
local controller=Physics.new(player_api,p(0,1,0),{profile='luanti',stepheight=0})
local sweep={-1,-.2,-.2,5,.2,.2}
local empty=controller:colliders(sweep)
assert(#empty==0)
player_api.set_node(p(3,0,0),{name='test:stone'})
local filled=controller:colliders(sweep)
assert(#filled==1)
player_api.remove_node(p(3,0,0))
assert(#controller:colliders(sweep)==0)
-- Repeated edits must not destroy remote cached world shapes.
local churn,churnapi=world()
for i=0,6 do
 churnapi.set_node(p(i*16,0,0),{name='test:stone'})
end
for i=0,6 do verify(churn,p(i*16,0,0),'warm long range') end
local warm=Geometry.cache(churn)
local distant=warm.data['96,0,0']
local base_resets=warm.resets
for i=1,40 do
 churnapi.set_node(p(0,0,0),{
  name=i%2==0 and 'test:stone' or 'test:slab'})
 verify(churn,p(0,0,0),'repeated live edit')
 assert(warm.data['96,0,0']==distant)
end
assert(Geometry.cache(churn)==warm)
assert(warm.resets==base_resets)
assert(warm.selective_updates>=40)
print('LUA ENGINE PHASE 52 LIVE TERRAIN COLLISION UPDATES PASS')
