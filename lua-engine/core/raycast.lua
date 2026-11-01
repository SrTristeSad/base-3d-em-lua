-- Host-independent voxel ray selection. The selection surface uses the same
-- rotated/connected nodeboxes as the map, not a whole-cube approximation.
-- Drops and falling blocks are the currently supported world ObjectRefs.
local Nodebox=require('core.nodebox')
local Ray={}
local abs, floor, sqrt, min, max=math.abs,math.floor,math.sqrt,math.min,math.max
local INF=math.huge
local EPS=1e-9
local function finite(v)
 return type(v)=='number' and v==v and v~=INF and v~=-INF
end
local function vector(v,what)
 assert(type(v)=='table' and finite(v.x) and finite(v.y) and finite(v.z),
  'raycast '..what..' must be finite coordinates')
 return {x=v.x,y=v.y,z=v.z}
end
local function copy(v) return {x=v.x,y=v.y,z=v.z} end
local function unit(direction)
 local len=sqrt(direction.x*direction.x+
  direction.y*direction.y+direction.z*direction.z)
 assert(finite(len) and len>0,'raycast direction must be nonzero')
 return {x=direction.x/len,y=direction.y/len,z=direction.z/len}
end
-- Slab intersection with inward-facing entry normal. A ray originating
-- inside a box selects it at distance 0, instead of seeing through it.
local function intersect(origin,dir,minp,maxp,limit)
 local near,far=-INF,INF
 local normal={x=0,y=0,z=0}
 local axes={'x','y','z'}
 for _,axis in ipairs(axes) do
  local o,d=origin[axis],dir[axis]
  local lo,hi=minp[axis],maxp[axis]
  if abs(d)<EPS then
   if o<lo or o>hi then return nil end
  else
   local a,b=(lo-o)/d,(hi-o)/d
   local sign=-1
   if a>b then a,b=b,a;sign=1 end
   if a>near then
    near=a
    normal={x=0,y=0,z=0}
    normal[axis]=sign
   end
   far=min(far,b)
   if near>far+EPS then return nil end
  end
 end
 if far<-EPS or near>limit+EPS then return nil end
 if near<0 then
  -- Inside: position is already occupied by the selected object/node.
  normal={x=0,y=0,z=0}
  local strongest='x'
  if abs(dir.y)>abs(dir[strongest]) then strongest='y' end
  if abs(dir.z)>abs(dir[strongest]) then strongest='z' end
  normal[strongest]=dir[strongest]>0 and -1 or 1
 end
 return max(0,near),normal
end
local function center_box(center,box)
 return {x=center.x+box[1],y=center.y+box[2],z=center.z+box[3]},
  {x=center.x+box[4],y=center.y+box[5],z=center.z+box[6]}
end
local function item_box(obj)
 local stack=obj.stack
 if stack and type(stack.get_count)=='function' then
  -- Approximation of Luanti builtin item's variable visual/collision box.
  local maxstack=type(stack.get_stack_max)=='function' and
   stack:get_stack_max() or 99
  local ratio=maxstack>0 and min(1,stack:get_count()/maxstack) or 1
  local half=.2+.1*(ratio^(1/3))
  return {-half,-half,-half,half,half,half}
 end
 return {-.3,-.3,-.3,.3,.3,.3}
end
local function eligible_node(rt,pos,liquids)
 local node=rt.map:get_node(pos)
 if node.name=='air' or node.name=='ignore' then return nil end
 local def=rt.registry.nodes[node.name]
 if not def or def.pointable==false then return nil end
 if not liquids and def.liquidtype and def.liquidtype~='none' then
  return nil
 end
 return node,def
end
local function trace(rt,origin,dir,distance,objects,liquids)
 local hits,nodes={},{}
 local function add_node(x,y,z)
  if abs(x)>31000 or abs(y)>31000 or abs(z)>31000 then return end
  local key=x..','..y..','..z
  if nodes[key] then return end
  nodes[key]=true
  local pos={x=x,y=y,z=z}
  local node,def=eligible_node(rt,pos,liquids)
  if not node then return end
  local boxes=Nodebox.boxes(def,node,rt.map,pos,rt.registry.nodes,
   'selection_box')
  local closest,normal
  for _,box in ipairs(boxes) do
   local lo,hi=center_box(pos,box)
   local t,n=intersect(origin,dir,lo,hi,distance)
   if t and (not closest or t<closest) then closest,normal=t,n end
  end
  if closest then
   hits[#hits+1]={type='node',under=pos,
    above={x=x+normal.x,y=y+normal.y,z=z+normal.z},
    distance=closest,intersection_point={
     x=origin.x+closest*dir.x,
     y=origin.y+closest*dir.y,
     z=origin.z+closest*dir.z}}
  end
 end
 -- March along ray through node-centered cells with a halo of 2 nodes.
 -- The halo handles nodeboxes protruding 1.45 nodes beyond the source cell.
 -- Deduplication ensures each node/shape is tested exactly once per cast.
 local t=0
 while t<=distance do
  local x=floor(origin.x+dir.x*t+.5)
  local y=floor(origin.y+dir.y*t+.5)
  local z=floor(origin.z+dir.z*t+.5)
  for dx=-2,2 do for dy=-2,2 do for dz=-2,2 do
   add_node(x+dx,y+dy,z+dz)
  end end end
  t=t+.5
 end
 local x=floor(origin.x+dir.x*distance+.5)
 local y=floor(origin.y+dir.y*distance+.5)
 local z=floor(origin.z+dir.z*distance+.5)
 for dx=-2,2 do for dy=-2,2 do for dz=-2,2 do
  add_node(x+dx,y+dy,z+dz)
 end end end
 if objects then
  for _,obj in ipairs(rt.droppedItems or {}) do
   if not obj.removed then
    local pos=obj:get_pos()
    local lo,hi=center_box(pos,item_box(obj))
    local d=intersect(origin,dir,lo,hi,distance)
    if d then
     hits[#hits+1]={type='object',ref=obj,distance=d,
      intersection_point={x=origin.x+d*dir.x,
       y=origin.y+d*dir.y,z=origin.z+d*dir.z}}
    end
   end
  end
  for _,obj in ipairs(rt.luaEntities or {}) do
   if not obj.removed and obj.properties.pointable~=false then
    local pos=obj:get_pos()
    local box=obj.properties.selectionbox
    local lo,hi=center_box(pos,box)
    local d=intersect(origin,dir,lo,hi,distance)
    if d then
     hits[#hits+1]={type='object',ref=obj,distance=d,
      intersection_point={x=origin.x+d*dir.x,
       y=origin.y+d*dir.y,z=origin.z+d*dir.z}}
    end
   end
  end
  for _,obj in ipairs(rt.fallingNodes or {}) do
   local pos=obj.pos
   local lo,hi=center_box(pos,{-.5,-.5,-.5,.5,.5,.5})
   local d=intersect(origin,dir,lo,hi,distance)
   if d then
    hits[#hits+1]={type='object',ref=obj,distance=d,
     intersection_point={x=origin.x+d*dir.x,
      y=origin.y+d*dir.y,z=origin.z+d*dir.z}}
   end
  end
 end
 -- Solid node geometry wins an exact tie, preventing interactions through
 -- blocks that begin on the same face as an entity.
 table.sort(hits,function(a,b)
  if abs(a.distance-b.distance)<EPS then
   if a.type~=b.type then return a.type=='node' end
   return false -- equal items preserve world insertion order
  end
  return a.distance<b.distance
 end)
 return hits
end
function Ray.cast(rt,origin,direction,distance,opts)
 assert(type(rt)=='table' and type(rt.map)=='table' and
  type(rt.registry)=='table','raycast requires runtime')
 origin=vector(origin,'origin')
 direction=unit(vector(direction,'direction'))
 assert(finite(distance) and distance>=0 and distance<=64,
  'raycast distance must be between 0 and 64')
 opts=opts or {}
 assert(type(opts)=='table','raycast options must be a table')
 return trace(rt,origin,direction,distance,
  opts.objects~=false,opts.liquids==true)
end
function Ray.first(rt,origin,direction,distance,opts)
 return Ray.cast(rt,origin,direction,distance,opts)[1]
end
-- Native-like core.raycast(from,to,objects,liquids): a Lua iterator
-- yielding pointed_thing records in distance order. Only supported host
-- entities (drops and falling blocks) are included in this phase.
function Ray.iterator(rt,from,to,objects,liquids)
 from=vector(from,'from')
 to=vector(to,'to')
 local delta={x=to.x-from.x,y=to.y-from.y,z=to.z-from.z}
 local distance=sqrt(delta.x*delta.x+delta.y*delta.y+delta.z*delta.z)
 assert(finite(distance) and distance<=64,
  'raycast endpoint distance must be at most 64')
 if distance==0 then return function() return nil end end
 local hits=trace(rt,from,unit(delta),distance,
  objects~=false,liquids==true)
 local index=0
 return function()
  index=index+1
  return hits[index]
 end
end
return Ray
