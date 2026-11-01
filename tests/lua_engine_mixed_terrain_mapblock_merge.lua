-- Phase 51: differential validation of ordered mapblock streams in
-- mixed dense/sparse terrain, plus player and LuaEntity interactions.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Index=require('core.mapnodeindex')
local Geometry=require('core.collisiongeometry')
local Nodebox=require('core.nodebox')
local Physics=require('core.physics')
local function p(x,y,z)return {x=x,y=y,z=z} end
local function key(pos)return pos.x..','..pos.y..','..pos.z end
local function less(a,b)
 if a.x~=b.x then return a.x<b.x end
 if a.y~=b.y then return a.y<b.y end
 return a.z<b.z
end
local function reference(map,x1,x2,y1,y2,z1,z2)
 local out={}
 for x=x1,x2 do for y=y1,y2 do for z=z1,z2 do
  local q=p(x,y,z)
  if map.nodes[key(q)] then out[#out+1]=q end
 end end end
 return out
end
local function check(map,x1,x2,y1,y2,z1,z2,label)
 local actual=Index.query(map,x1,x2,y1,y2,z1,z2)
 local expected=reference(map,x1,x2,y1,y2,z1,z2)
 assert(#actual==#expected,label..': count '..#actual..' vs '..#expected)
 for i=1,#actual do
  assert(key(actual[i])==key(expected[i]),label..': wrong order at '..i)
  if i>1 then assert(less(actual[i-1],actual[i])) end
 end
 return actual
end
local function raw_geometry(rt,region,pad,skip)
 local floor,min,max=math.floor,math.min,math.max
 local x1,x2=max(-31000,floor(region[1]-pad)),
  min(31000,floor(region[4]+pad))
 local y1,y2=max(-31000,floor(region[2]-pad)),
  min(31000,floor(region[5]+pad))
 local z1,z2=max(-31000,floor(region[3]-pad)),
  min(31000,floor(region[6]+pad))
 local out={}
 for x=x1,x2 do for y=y1,y2 do for z=z1,z2 do
  local q=p(x,y,z)
  local node=rt.map:get_node(q)
  local def=rt.registry.nodes[node.name]
  if def and def.walkable~=false and
     (not skip or not def.buildable_to) then
   for _,b in ipairs(Nodebox.boxes(
     def,node,rt.map,q,rt.registry.nodes,'collision_box')) do
    out[#out+1]={pos=q,box={x+b[1],y+b[2],z+b[3],
     x+b[4],y+b[5],z+b[6]}}
   end
  end
 end end end
 return out
end
local function compare_geometry(rt,region,pad,skip,label)
 local actual=Geometry.collect(rt,region,pad,skip)
 local expected=raw_geometry(rt,region,pad,skip)
 assert(#actual==#expected,label..': count '..#actual..'/'..#expected)
 for i=1,#actual do
  local a,b=actual[i],expected[i]
  assert(key(a.node_pos)==key(b.pos),label..': node order '..i)
  for k=1,6 do
   assert(math.abs(a.box[k]-b.box[k])<1e-8,
    label..': geometry '..i..','..k)
  end
 end
 return actual
end
local rt=Runtime.new({auto_pickup=false,item_physics=false})
local api=rt.api
api.register_node('test:stone',{})
api.register_node('test:slab',{drawtype='nodebox',node_box={
 type='fixed',fixed={-.5,-.5,-.5,.5,-.1,.5}}})
api.register_node('test:angle',{drawtype='nodebox',paramtype2='facedir',
 node_box={type='fixed',fixed={-.5,-.5,-.2,.5,.5,.2}}})
api.register_node('test:fence',{drawtype='nodebox',
 connects_to={'test:fence'},node_box={
  type='connected',fixed={-.1,-.5,-.1,.1,.5,.1},
  connect_left={-.5,-.15,-.15,-.1,.15,.15},
  connect_right={.1,-.15,-.15,.5,.15,.15}}})
-- Build four clustered terrain types across positive/negative mapblocks.
-- Deliberately no random generator: fixture bytes stay identical on LuaJIT.
for x=-34,47 do
 for y=-2,3 do
  for z=-7,7 do
   local dense=x>=-16 and x<0 or x>=16 and x<32
   local occupied=dense and (x+y+z)%7~=0 or
    (not dense and (x*19+y*11+z*7)%23==0)
   if occupied then
    local typ=(x*5+y*3+z*2)%23
    local name=typ==0 and 'test:slab' or
      typ==1 and 'test:angle' or
      typ==2 and 'test:fence' or 'test:stone'
    api.set_node(p(x,y,z),{name=name,param2=(x+z)%24})
   end
  end
 end
end
-- Block boundaries and strictly sorted x,y,z results.
local map=rt.map
local first=check(map,-34,47,-2,3,-7,7,'mixed complete')
assert(#first>500)
check(map,-17,17,-1,1,-3,3,'mixed boundary')
check(map,-33,-16,-2,3,-7,7,'negative mapblocks')
check(map,16,33,-2,3,-7,7,'positive mapblocks')
local index=Index.ensure(map)
local prior=index.sorted_blocks
check(map,-34,47,-2,3,-7,7,'repeat mixed')
assert(index.sorted_blocks==prior,'repeated scans should reuse sorted buckets')
-- A single-node change invalidates only one block's sorted list.
local replace=p(17,1,2)
local existed=map.nodes[key(replace)]~=nil
api.set_node(replace,{name=existed and 'air' or 'test:stone'})
check(map,-34,47,-2,3,-7,7,'incremental change')
assert(index.sorted_blocks==prior+1,
 'one edit must reorder only its modified mapblock')
prior=index.sorted_blocks
check(map,-34,47,-2,3,-7,7,'repeat after change')
assert(index.sorted_blocks==prior)
-- A tiny isolated block is added, edited, removed, and later restored.
local isolated=p(-64,2,0)
api.set_node(isolated,{name='test:stone'})
assert(Index.ensure(map)==index)
check(map,-65,-48,-2,3,-3,3,'new negative block')
local count=index.block_count
api.set_node(isolated,{name='test:slab'})
assert(index.block_count==count)
check(map,-65,-48,-2,3,-3,3,'same block different shape')
api.remove_node(isolated)
assert(index.block_count==count-1)
check(map,-65,-48,-2,3,-3,3,'last node removed')
-- The limit-based early rejection remains available for dense blocks.
assert(Index.query(map,-16,-1,-2,3,-7,7,100)==nil)
assert(index.dense_rejections>=1)
local all=Index.query(map,-16,-1,-2,3,-7,7)
assert(#all>100)
-- Compare exact custom collision boxes and original traversal order.
compare_geometry(rt,{-34,-1,-5,47,2,5},2,true,'mixed entity boxes')
compare_geometry(rt,{-34,-1,-5,47,2,5},1.5,false,'mixed player boxes')
local cache=Geometry.cache(rt)
assert(cache.sparse_queries+cache.dense_queries>=2)
-- Connected fences must invalidate their geometry after a neighbor edit.
api.set_node(p(0,0,0),{name='test:fence'})
api.set_node(p(1,0,0),{name='test:fence'})
compare_geometry(rt,{-3,-1,-2,4,1,2},2,true,'connected neighbors')
api.remove_node(p(1,0,0))
compare_geometry(rt,{-3,-1,-2,4,1,2},2,true,'connected neighbor removed')
-- A large controller sweep uses the same collision geometry in player API.
local controller=Physics.new(api,p(0,5,0),{profile='luanti',stepheight=0})
local region={-35,-1,-4,35,3,4}
local cboxes=controller:colliders(region)
local raw=raw_geometry(rt,region,1.5,false)
assert(#cboxes==#raw)
for i=1,#raw do
 for j=1,6 do
  assert(math.abs(cboxes[i][j]-raw[i].box[j])<1e-8,
   'player collider geometry differs from baseline')
 end
end
-- Real physical entity crosses a mapblock edge and hits a solid wall
-- without tunneling. Keep it away from the mixed terrain fixture.
api.set_node(p(16,0,32),{name='test:stone'})
api.register_entity('test:mob',{initial_properties={
 physical=true,collide_with_objects=true,
 collisionbox={-.3,-.3,-.3,.3,.3,.3}},
 on_step=function(self,dt,result)self.last=result end})
local mob=assert(api.add_entity(p(12,0,32),'test:mob'))
mob:set_velocity(p(20,0,0))
rt:step(.4)
assert(math.abs(mob:get_pos().x-15.2)<1e-5,
 'mob must stop at wall crossing x=16 mapblock boundary')
assert(mob:get_luaentity().last.collides)
local hit=false
for _,c in ipairs(mob:get_luaentity().last.collisions) do
 if c.type=='node' and c.node_pos and c.node_pos.x==16 then
  hit=true
 end
end
assert(hit,'mob must report the blocking world node')
-- Replacing the map storage is a supported restoration mechanism.
local rebuilt={}
for k,v in pairs(map.nodes) do rebuilt[k]=v end
map.nodes=rebuilt
local newindex=Index.ensure(map)
assert(newindex~=index and newindex.rebuilds==index.rebuilds+1)
check(map,-34,47,-2,3,-7,7,'restored node table')
compare_geometry(rt,{-34,-1,-5,47,2,5},2,true,'restored geometry')
print('LUA ENGINE PHASE 51 MIXED TERRAIN MAPBLOCK MERGE PASS')
