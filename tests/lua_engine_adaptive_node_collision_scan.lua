-- Phase 50: adaptive dense/sparse node broadphase correctness.
-- A dense region should choose direct scanning, whereas an equally wide
-- mostly empty region should choose the indexed mapblock traversal.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Geometry=require('core.collisiongeometry')
local Index=require('core.mapnodeindex')
local Nodebox=require('core.nodebox')
local function p(x,y,z)return {x=x,y=y,z=z} end
local function world()
 local rt=Runtime.new({auto_pickup=false,item_physics=false})
 local api=rt.api
 api.register_node('test:stone',{})
 api.register_node('test:slab',{drawtype='nodebox',
  node_box={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}}})
 api.register_node('test:rotated',{drawtype='nodebox',
  paramtype2='facedir',node_box={
   type='fixed',fixed={-.5,-.5,-.2,.5,.5,.2}}})
 api.register_node('test:connected',{drawtype='nodebox',
  connects_to={'test:connected'},
  node_box={type='connected',fixed={-.1,-.5,-.1,.1,.5,.1},
   connect_right={.1,-.1,-.1,.5,.1,.1},
   connect_left={-.5,-.1,-.1,-.1,.1,.1}}})
 return rt,api
end
local function baseline(rt,swept,pad,skip)
 local floor,max,min=math.floor,math.max,math.min
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
    out[#out+1]={pos=pos,box={
     x+b[1],y+b[2],z+b[3],x+b[4],y+b[5],z+b[6]}}
   end
  end
 end end end
 return out
end
local function verify(rt,swept,pad,skip,label)
 local actual=Geometry.collect(rt,swept,pad,skip)
 local expected=baseline(rt,swept,pad,skip)
 assert(#actual==#expected,label..': counts '..
  #actual..' vs '..#expected)
 for i=1,#actual do
  local a,b=actual[i],expected[i]
  assert(a.node_pos.x==b.pos.x and a.node_pos.y==b.pos.y and
   a.node_pos.z==b.pos.z,label..': traversal order '..i)
  for j=1,6 do
   assert(math.abs(a.box[j]-b.box[j])<1e-8,
    label..': wrong box '..i..' component '..j)
  end
 end
 return actual
end

local dense,api=world()
-- 4096 fully populated cells within one mapblock, including dynamic
-- nodeboxes, rotations and connected-node dependencies.
for x=0,15 do for y=0,15 do for z=0,15 do
 local name='test:stone'
 if x==1 and y==0 and z==1 then name='test:slab' end
 if x==2 and y==0 and z==1 then name='test:rotated' end
 if (x==3 or x==4) and y==0 and z==1 then
  name='test:connected'
 end
 api.set_node(p(x,y,z),{name=name,param2=3})
end end end
local dense_index=Index.ensure(dense.map)
assert(dense_index.count==4096 and dense_index.block_count==1)
assert(Index.query(dense.map,0,15,0,15,0,15,1000)==nil,
 'dense query must reject an expensive sparse enumeration')
assert(dense_index.dense_rejections==1)
local direct=Index.query(dense.map,0,15,0,15,0,15)
assert(#direct==4096 and direct[1].x==0 and direct[1].y==0 and
 direct[1].z==0 and direct[#direct].x==15 and
 direct[#direct].y==15 and direct[#direct].z==15)
local sweep={0,0,0,15,15,15}
local checked=verify(dense,sweep,2,true,'dense nodeboxes')
assert(#checked>=4096, 'connected nodes may contribute multiple shapes')
local cache=Geometry.cache(dense)
assert(cache.dense_fallbacks==1 and cache.dense_queries==1 and
 cache.sparse_queries==0,'dense world should use the direct scan')
verify(dense,sweep,2,true,'repeat dense nodeboxes')
assert(Geometry.cache(dense).dense_fallbacks==2)
-- A long query crossing thousands of EMPTY mapblocks should inspect
-- only occupied buckets, not loop over every empty mapblock.
local old=Index.ensure(dense.map).blocks_examined
local far=Index.query(dense.map,-16000,16000,0,0,0,0)
assert(#far==16 and far[1].x==0 and far[1].y==0 and
 far[1].z==0 and far[#far].x==15,
 'long sweep must retain every stored node along the chosen line')
assert(dense_index.blocks_examined-old==1,
 'mapblock traversal cost must be measured in blocks, not stored nodes')
-- Incremental growth/shrinkage updates block_count precisely.
api.set_node(p(-32,0,0),{name='test:stone'})
assert(dense_index.count==4097 and dense_index.block_count==2)
api.remove_node(p(-32,0,0))
assert(dense_index.count==4096 and dense_index.block_count==1)
-- When deleting a node, both cached shapes and index occupancy update.
api.remove_node(p(2,0,1))
verify(dense,sweep,2,true,'modified dense nodeboxes')
assert(Index.ensure(dense.map).count==4095)
-- Replacement of map.nodes invalidates both indexes, including when
-- revision does not change. Keep the collision geometry exactly intact.
local prev=Index.ensure(dense.map)
local replacement={}
for k,v in pairs(dense.map.nodes) do replacement[k]=v end
dense.map.nodes=replacement
assert(Index.ensure(dense.map)~=prev)
assert(Index.ensure(dense.map).block_count==1)
verify(dense,sweep,2,true,'replaced dense table')

local sparse,sa=world()
sa.set_node(p(-31,0,0),{name='test:stone'})
sa.set_node(p(0,0,0),{name='test:slab'})
sa.set_node(p(32,0,0),{name='test:rotated',param2=11})
sa.set_node(p(33,0,0),{name='test:connected'})
sa.set_node(p(34,0,0),{name='test:connected'})
local sparse_sweep={-40,-.2,-3,40,.2,3}
local sparse_result=verify(sparse,sparse_sweep,2,true,'sparse nodes')
assert(#sparse_result>=5)
local sparse_cache=Geometry.cache(sparse)
assert(sparse_cache.sparse_queries==1 and
 sparse_cache.dense_fallbacks==0 and sparse_cache.dense_queries==0)
assert(sparse_cache.nodes_examined<15,
 'sparse sweep should not visit thousands of implicit air voxels')
-- An opt-in walkable air definition invalidates the sparse assumption.
sa.override_item('air',{walkable=true})
local prev_cache=Geometry.cache(sparse)
local small_sweep={-.3,-.3,-.3,9,.3,.3}
verify(sparse,small_sweep,1.5,false,'walkable air requires dense')
assert(Geometry.cache(sparse).sparse_queries==0)
assert(Geometry.cache(sparse).dense_queries==1)
assert(Geometry.cache(sparse)==prev_cache)
sa.override_item('air',{walkable=false})
verify(sparse,sparse_sweep,2,true,'restore noncollidable air')
assert(Geometry.cache(sparse).sparse_queries==1)
-- No stale mapblock entries on removal, including negative coordinates.
sa.remove_node(p(-31,0,0))
assert(Index.ensure(sparse.map).block_count==2)
verify(sparse,sparse_sweep,2,true,'remove negative node')
print('LUA ENGINE PHASE 50 ADAPTIVE DENSE SPARSE NODE COLLISIONS PASS')
