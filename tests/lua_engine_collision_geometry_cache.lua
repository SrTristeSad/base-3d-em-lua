-- Phase 48: cached node collision geometry must match uncached nodeboxes
-- exactly, including connected neighbors, orientation, replacement and
-- player/ObjectRef collision behavior.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Geometry=require('core.collisiongeometry')
local Nodebox=require('core.nodebox')
local Player=require('core.physics')
local function p(x,y,z)return {x=x,y=y,z=z} end
local function equalbox(a,b,msg)
 assert(#a==6 and #b==6,msg)
 for i=1,6 do
  assert(math.abs(a[i]-b[i])<1e-8,
   msg..' coordinate '..i..' '..a[i]..' ~= '..b[i])
 end
end
local function baseline(rt,swept,pad,skip)
 local out={}
 local floor,min,max=math.floor,math.min,math.max
 local x1,x2=max(-31000,floor(swept[1]-pad)),
  min(31000,floor(swept[4]+pad))
 local y1,y2=max(-31000,floor(swept[2]-pad)),
  min(31000,floor(swept[5]+pad))
 local z1,z2=max(-31000,floor(swept[3]-pad)),
  min(31000,floor(swept[6]+pad))
 for x=x1,x2 do for y=y1,y2 do for z=z1,z2 do
  local pos=p(x,y,z)
  local node=rt.map:get_node(pos)
  local def=rt.registry.nodes[node.name]
  if def and def.walkable~=false and (not skip or
     not def.buildable_to) then
   for _,b in ipairs(Nodebox.boxes(
    def,node,rt.map,pos,rt.registry.nodes,'collision_box')) do
    out[#out+1]={
     pos=pos,box={x+b[1],y+b[2],z+b[3],
      x+b[4],y+b[5],z+b[6]}}
   end
  end
 end end end
 return out
end
local function compare(rt,swept,pad,skip,label)
 local cached=Geometry.collect(rt,swept,pad,skip)
 local expected=baseline(rt,swept,pad,skip)
 assert(#cached==#expected,
  label..': cached '..#cached..' != raw '..#expected)
 for i=1,#cached do
  local a,b=cached[i],expected[i]
  assert(a.node_pos.x==b.pos.x and
   a.node_pos.y==b.pos.y and a.node_pos.z==b.pos.z,
   label..' node scan order '..i)
  equalbox(a.box,b.box,label..' box '..i)
 end
 return cached
end
local rt=Runtime.new({auto_pickup=false,item_physics=false})
local api=rt.api
api.register_node('test:cube',{})
api.register_node('test:nonwalk',{walkable=false})
api.register_node('test:buildable',{buildable_to=true})
api.register_node('test:slab',{
 drawtype='nodebox',node_box={
  type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}}})
api.register_node('test:rotated',{
 paramtype2='facedir',drawtype='nodebox',
 node_box={type='fixed',fixed={-.5,-.5,-.2,.5,.5,.2}}})
api.register_node('test:leveled',{
 drawtype='nodebox',paramtype2='leveled',
 leveled=32,node_box={
  type='leveled',fixed={-.5,-.5,-.5,.5,0,.5}}})
api.register_node('test:connected',{
 drawtype='nodebox',connects_to={'test:connected'},
 node_box={type='connected',
  fixed={-.12,-.5,-.12,.12,.5,.12},
  connect_right={.12,-.12,-.12,.5,.12,.12},
  connect_left={-.5,-.12,-.12,-.12,.12,.12},
  disconnected_right={.12,-.12,-.12,.2,.12,.12}}})
api.register_node('test:wall',{
 drawtype='nodebox',paramtype2='wallmounted',
 node_box={type='wallmounted',
  wall_top={-.5,-.5,-.5,.5,-.3,.5},
  wall_bottom={-.5,.3,-.5,.5,.5,.5},
  wall_side={-.5,-.3,-.3,-.3,.3,.3}}})
api.set_node(p(0,0,0),{name='test:cube'})
api.set_node(p(1,0,0),{name='test:slab'})
api.set_node(p(2,0,0),{name='test:rotated',param2=2})
api.set_node(p(3,0,0),{name='test:leveled',param2=28})
api.set_node(p(4,0,0),{name='test:connected'})
api.set_node(p(5,0,0),{name='test:connected'})
api.set_node(p(6,0,0),{name='test:wall',param2=5})
api.set_node(p(-1,0,0),{name='test:nonwalk'})
api.set_node(p(-2,0,0),{name='test:buildable'})
local swept={-2,-.4,-.5,7,.4,.5}
compare(rt,swept,2,true,'entity initial')
compare(rt,swept,1.5,false,'player initial')
local cache=Geometry.cache(rt)
local hits=cache.hits
compare(rt,swept,2,true,'entity repeated')
assert(Geometry.cache(rt)==cache and cache.hits>hits,
 'repeated node probes must reuse the same geometry cache')
assert(cache.count>0 and cache.misses>0)
-- Public API returns fresh mutable nodeboxes; modifying one must not
-- mutate the collision cache or a subsequent API query.
local returned=api.get_node_boxes('collision_box',p(1,0,0))
returned[1][1]=999
local still=api.get_node_boxes('collision_box',p(1,0,0))
assert(still[1][1]==-.5)
compare(rt,swept,2,true,'public API mutation')
-- Changing node param2 must invalidate rotations and leveled shapes.
local old=Geometry.cache(rt)
api.swap_node(p(2,0,0),{name='test:rotated',param2=13})
assert(Geometry.cache(rt)~=old)
compare(rt,swept,2,true,'facedir update')
api.swap_node(p(3,0,0),{name='test:leveled',param2=60})
compare(rt,swept,2,true,'leveled update')
-- Connected geometry changes even if its own node remains unchanged.
api.remove_node(p(5,0,0))
compare(rt,swept,2,true,'neighbor removed')
api.set_node(p(5,0,0),{name='test:connected'})
compare(rt,swept,2,true,'neighbor restored')
-- Override mutates the same definition table, so it must explicitly
-- invalidate the cache even if the map's node revision stays unchanged.
compare(rt,swept,2,true,'pre override')
local previous=Geometry.cache(rt)
api.override_item('test:slab',{collision_box={
 type='fixed',fixed={-.5,-.5,-.5,.5,.25,.5}}})
assert(Geometry.cache(rt)~=previous)
compare(rt,swept,2,true,'definition override')
-- Definition registered after the world has already queried a cell.
local newpos=p(0,1,0)
api.set_node(newpos,{name='test:unregistered'})
compare(rt,swept,2,true,'unregistered name')
api.register_node('test:unregistered',{walkable=true})
compare(rt,swept,2,true,'new registration')
-- Map replacement must invalidate even when the revision field matches.
local oldcache=Geometry.cache(rt)
local newnodes={}
for k,v in pairs(rt.map.nodes) do newnodes[k]=v end
rt.map.nodes=newnodes
assert(Geometry.cache(rt)~=oldcache)
compare(rt,swept,2,true,'map table swapped')
-- Player and NPC must both use the same private world geometry.
api.register_entity('test:body',{
 initial_properties={physical=true,
  collisionbox={-.3,-.3,-.3,.3,.3,.3}},
 on_step=function(self,dt,result)self.result=result end})
local mob=api.add_entity(p(0,.7,1),'test:body')
mob:set_velocity(p(0,0,-2))
rt:step(1)
assert(mob:get_pos().z>=.8-1e-8,
 'LuaEntity must collide with cached solid cube')
assert(mob:get_luaentity().result.collides)
assert(mob:get_luaentity().result.collisions[1].type=='node')
local controller=Player.new(api,p(0,.5,3),{
 profile='luanti',stepheight=0})
local player_swept={-.3,.5,1,.3,2.3,3}
local player_boxes=controller:colliders(player_swept)
local uncached=baseline(rt,player_swept,1.5,false)
assert(#player_boxes==#uncached)
for i=1,#uncached do
 equalbox(player_boxes[i],uncached[i].box,'player provider '..i)
end
-- Removing the node should allow crossing it on the following tick.
api.remove_node(p(0,0,0))
compare(rt,swept,2,true,'air after removal')
local reset=Geometry.cache(rt)
assert(reset.misses>0)
print('LUA ENGINE PHASE 48 COLLISION GEOMETRY CACHE PASS')
