-- Bounded, revision-aware node collision geometry for LuaEntity and player
-- physics. Cache is runtime-private: public get_node_boxes keeps producing
-- fresh, mutable shape copies for mods.
local Nodebox=require('core.nodebox')
local Geometry={}
local floor,min,max=math.floor,math.min,math.max
local MAX_ENTRIES=8192
local EMPTY={boxes={}}
local function key(x,y,z)
 return x..','..y..','..z
end
local function fresh(rt)
 return {map=rt.map,nodes=rt.map.nodes,
  registry=rt.registry.nodes,revision=rt.map.geometry_revision or 0,
  data={},count=0,hits=0,misses=0,resets=0,
  nodes_examined=0}
end
function Geometry.cache(rt)
 local cache=rt.collisionNodeCache
 if not cache then
  cache=fresh(rt)
  rt.collisionNodeCache=cache
 elseif cache.map~=rt.map or cache.nodes~=rt.map.nodes or
   cache.registry~=rt.registry.nodes or
   cache.revision~=(rt.map.geometry_revision or 0) then
  local resets=cache.resets+1
  cache=fresh(rt)
  cache.resets=resets
  rt.collisionNodeCache=cache
 end
 return cache
end
function Geometry.invalidate(rt)
 rt.collisionNodeCache=nil
end
-- A map node is sampled just once while unchanged. Position is an integer
-- cell coordinate, so absolute boxes are reusable for every swept query.
local function entry(rt,cache,x,y,z)
 local k=key(x,y,z)
 -- Most large swept regions contain air. Caching every empty voxel
 -- caused pathological eviction churn and slower scattered queries.
 -- Sparse Map stores air as absent: bypass both allocation and cache.
 if not rt.map.nodes[k] and rt.registry.nodes.air.walkable==false then
  return EMPTY
 end
 local found=cache.data[k]
 if found and found.def==rt.registry.nodes[found.name] then
  cache.hits=cache.hits+1
  return found
 end
 cache.misses=cache.misses+1
 -- A capped cache avoids indefinite growth when the player explores.
 if cache.count>=MAX_ENTRIES then
  cache.data={}
  cache.count=0
  cache.resets=cache.resets+1
 end
 local pos={x=x,y=y,z=z}
 local node=rt.map:get_node(pos)
 local def=rt.registry.nodes[node.name]
 local boxes={}
 if def and def.walkable~=false then
  -- Full cubes cover the vast majority of terrain. This shortcut is
  -- equivalent to Nodebox.boxes' default regular collision shape.
  local shape=def.collision_box
  if (not shape and def.drawtype~='nodebox') or
     (type(shape)=='table' and shape.type=='regular') then
   boxes[1]={x-.5,y-.5,z-.5,x+.5,y+.5,z+.5}
  else
   for _,b in ipairs(Nodebox.boxes(
    def,node,rt.map,pos,rt.registry.nodes,'collision_box')) do
    boxes[#boxes+1]={
     x+b[1],y+b[2],z+b[3],x+b[4],y+b[5],z+b[6]}
   end
  end
 end
 found={name=node.name,def=def,buildable_to=def and def.buildable_to,
  node_pos=pos,boxes=boxes}
 cache.data[k]=found
 cache.count=cache.count+1
 return found
end
-- Match original sweep limits: entity uses pad=2 and excludes
-- buildable_to nodes; character uses pad=1.5 and includes those nodes.
-- Returns original x,y,z cell traversal order so tie resolution is stable.
function Geometry.collect(rt,swept,pad,exclude_buildable)
 local cache=Geometry.cache(rt)
 local x1,x2=max(-31000,floor(swept[1]-pad)),
  min(31000,floor(swept[4]+pad))
 local y1,y2=max(-31000,floor(swept[2]-pad)),
  min(31000,floor(swept[5]+pad))
 local z1,z2=max(-31000,floor(swept[3]-pad)),
  min(31000,floor(swept[6]+pad))
 local out={}
 for x=x1,x2 do for y=y1,y2 do for z=z1,z2 do
  cache.nodes_examined=cache.nodes_examined+1
  local node=entry(rt,cache,x,y,z)
  if not exclude_buildable or not node.buildable_to then
   for _,box in ipairs(node.boxes) do
    out[#out+1]={type='node',box=box,node_pos=node.node_pos}
   end
  end
 end end end
 return out
end
return Geometry
