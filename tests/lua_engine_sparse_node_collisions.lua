-- Phase 49: occupied-mapblock broadphase must preserve exact nodeboxes
-- and contact order while skipping empty voxels on wide physical sweeps.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Geometry=require('core.collisiongeometry')
local MapNodeIndex=require('core.mapnodeindex')
local Nodebox=require('core.nodebox')
local Physics=require('core.physics')
local function p(x,y,z)return {x=x,y=y,z=z} end
local function equal(a,b,why)
 assert(#a==#b,(why or '')..': size '..#a..' vs '..#b)
 for i=1,#a do
  assert(math.abs(a[i]-b[i])<1e-8,(why or '')..' index '..i)
 end
end
local function reference(rt,swept,pad,skip)
 local floor,min,max=math.floor,math.min,math.max
 local x1,x2=max(-31000,floor(swept[1]-pad)),
  min(31000,floor(swept[4]+pad))
 local y1,y2=max(-31000,floor(swept[2]-pad)),
  min(31000,floor(swept[5]+pad))
 local z1,z2=max(-31000,floor(swept[3]-pad)),
  min(31000,floor(swept[6]+pad))
 local out={}
 for x=x1,x2 do for y=y1,y2 do for z=z1,z2 do
  local pos=p(x,y,z)
  local node=rt.map:get_node(pos)
  local def=rt.registry.nodes[node.name]
  if def and def.walkable~=false and
    (not skip or not def.buildable_to) then
   for _,b in ipairs(Nodebox.boxes(
     def,node,rt.map,pos,rt.registry.nodes,'collision_box')) do
    out[#out+1]={node_pos=pos,box={
     x+b[1],y+b[2],z+b[3],x+b[4],y+b[5],z+b[6]}}
   end
  end
 end end end
 return out
end
local function compare(rt,swept,pad,skip,label)
 local expected=reference(rt,swept,pad,skip)
 local actual=Geometry.collect(rt,swept,pad,skip)
 assert(#actual==#expected,label..': box count '..#actual..
  ' != '..#expected)
 for i=1,#actual do
  local a,b=actual[i],expected[i]
  assert(a.type=='node' and a.node_pos.x==b.node_pos.x and
   a.node_pos.y==b.node_pos.y and a.node_pos.z==b.node_pos.z,
   label..' traversal order '..i)
  equal(a.box,b.box,label)
 end
 return actual
end
local rt=Runtime.new({auto_pickup=false,item_physics=false})
local api=rt.api
api.register_node('test:solid',{})
api.register_node('test:slab',{
 drawtype='nodebox',node_box={
  type='fixed',fixed={-.5,-.5,-.5,.5,-.1,.5}}})
api.register_node('test:rotated',{
 drawtype='nodebox',paramtype2='facedir',
 node_box={type='fixed',fixed={-.5,-.5,-.2,.5,.5,.2}}})
api.register_node('test:connected',{
 drawtype='nodebox',connects_to={'test:connected'},
 node_box={type='connected',
  fixed={-.1,-.5,-.1,.1,.5,.1},
  connect_right={.1,-.1,-.1,.5,.1,.1},
  connect_left={-.5,-.1,-.1,-.1,.1,.1}}})
api.register_node('test:ghost',{walkable=false})
api.register_node('test:buildable',{buildable_to=true})
api.set_node(p(-31,0,-1),{name='test:solid'})
api.set_node(p(-17,0,0),{name='test:slab'})
api.set_node(p(-16,0,0),{name='test:rotated',param2=1})
api.set_node(p(0,0,0),{name='test:connected'})
api.set_node(p(1,0,0),{name='test:connected'})
api.set_node(p(2,0,0),{name='test:ghost'})
api.set_node(p(3,0,0),{name='test:buildable'})
api.set_node(p(16,0,0),{name='test:solid'})
api.set_node(p(32,0,1),{name='test:solid'})
api.set_node(p(80,0,0),{name='test:solid'})
local all={-38,-.4,-4,38,.4,4}
compare(rt,all,2,true,'entity sparse')
compare(rt,all,1.5,false,'player sparse')
local cache=Geometry.cache(rt)
assert(cache.sparse_queries==2 and cache.dense_queries==0)
local nodeindex=MapNodeIndex.ensure(rt.map)
assert(nodeindex.count==10)
assert(cache.nodes_examined<25,
 'wide sparse traversal must not inspect thousands of air cells')
assert(nodeindex.candidates_examined>=9)
local bounds={-40,40,-3,3,-8,8}
local direct=MapNodeIndex.query(rt.map,
 bounds[1],bounds[2],bounds[3],bounds[4],bounds[5],bounds[6])
assert(#direct==9)
for i=2,#direct do
 local a,b=direct[i-1],direct[i]
 assert(a.x<b.x or a.x==b.x and
  (a.y<b.y or a.y==b.y and a.z<b.z),
  'node index must preserve original x/y/z collision order')
end
-- A small query stays on the dense path: avoid index setup overhead.
compare(rt,{-1,-.2,-1,1,.2,1},2,true,'dense local')
assert(Geometry.cache(rt).dense_queries>=1)
-- A direct Map:set_node call updates index, not just core API calls.
rt.map:set_node(p(8,0,0),{name='test:solid'})
assert(MapNodeIndex.ensure(rt.map)==nodeindex)
assert(nodeindex.count==11)
compare(rt,all,2,true,'direct insertion')
rt.map:remove_node(p(-17,0,0))
assert(nodeindex.count==10)
compare(rt,all,2,true,'direct removal')
rt.map:set_node(p(-17,0,0),{name='test:slab'})
local rev=rt.map.geometry_revision
rt.map:set_node(p(-17,0,0),{name='test:slab'})
assert(rt.map.geometry_revision==rev)
assert(nodeindex.count==11)
compare(rt,all,2,true,'unchanged replacement')
-- Connected nodeboxes rely on neighbor state: scan matches raw API
-- after neighbor added/removed on either side of a block boundary.
api.remove_node(p(1,0,0))
compare(rt,all,2,true,'connected neighbor removed')
api.set_node(p(1,0,0),{name='test:connected'})
compare(rt,all,2,true,'connected neighbor restored')
api.swap_node(p(-16,0,0),{name='test:rotated',param2=11})
compare(rt,all,2,true,'rotation changed')
-- Crossing the world boundary: both index and old voxel loop clamp.
compare(rt,{30998,-.3,-1,31003,.3,1},2,true,'world clamp')
compare(rt,{-31003,-.3,-1,-30998,.3,1},1.5,false,'negative clamp')
-- Replacing the entire map.nodes dictionary invalidates the index and
-- collision cache even if the map revision number remains unchanged.
local previous_index=MapNodeIndex.ensure(rt.map)
local old=rt.map.nodes
local replacement={}
for k,v in pairs(old) do replacement[k]=v end
replacement[rt.map.key(p(4,0,0))]={name='test:solid',param1=0,param2=0}
replacement[rt.map.key(p(80,0,0))]=nil
rt.map.nodes=replacement
assert(MapNodeIndex.ensure(rt.map)~=previous_index)
assert(MapNodeIndex.ensure(rt.map).count==11)
compare(rt,all,2,true,'replaced dictionary')
-- Bounded long sweeps should not materialize empty mapblocks or millions
-- of entries when the map stores just a handful of voxels.
local cache_before=Geometry.cache(rt).nodes_examined
local wide=Geometry.collect(rt,{-12000,-.1,-.1,12000,.1,.1},2,true)
assert(#wide>=5 and #wide<=11)
assert(Geometry.cache(rt).nodes_examined-cache_before<=11)
local sparse_index=MapNodeIndex.ensure(rt.map)
assert(sparse_index.blocks_examined<100,
 'huge empty traversal must visit occupied mapblocks, not every block')
-- A body travelling quickly toward a distant block must still stop.
api.register_entity('test:body',{
 initial_properties={physical=true,collisionbox={
  -.3,-.3,-.3,.3,.3,.3}},
 on_step=function(self,dt,result)self.result=result end})
local moving=api.add_entity(p(19,0,1),'test:body')
moving:set_velocity(p(60,0,0))
rt:step(.4)
assert(moving:get_pos().x<=31.4+1e-5)
assert(moving:get_luaentity().result.collides)
assert(moving:get_luaentity().result.collisions[1].type=='node')
-- Player controller's long-range sweep sees same node colliders.
local controller=Physics.new(api,p(0,2,0),{profile='luanti'})
local playerbox={-35,-.25,-2,35,.25,2}
local player_nodes=controller:colliders(playerbox)
local raw_player=reference(rt,playerbox,1.5,false)
assert(#player_nodes==#raw_player)
for i=1,#player_nodes do equal(player_nodes[i],raw_player[i].box,'player') end
print('LUA ENGINE PHASE 49 SPARSE MAP NODE BROADPHASE PASS')
