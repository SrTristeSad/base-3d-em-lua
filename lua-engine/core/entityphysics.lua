-- Swept, axis-aligned collision of registered LuaEntities with actual
-- Luanti node collision_box geometry. Lua entities acquire acceleration from
-- mods (e.g. set_acceleration({x=0,y=-9.81,z=0})), not automatic gravity.
-- Supported: static nodeboxes, oriented/connected/leveled boxes and sliding.
-- Missing: entity-vs-entity collisions, stepheight, moving nodes, buoyancy.
local Nodebox=require('core.nodebox')
local P={}
local floor,min,max,abs=math.floor,math.min,math.max,math.abs
local EPS=1e-8
local axes={'x','y','z'}
local indices={x=1,y=2,z=3}
local function aabb(pos,box)
 return {pos.x+box[1],pos.y+box[2],pos.z+box[3],
  pos.x+box[4],pos.y+box[5],pos.z+box[6]}
end
local function overlap(a,b,c,d)
 return a<d-EPS and c<b-EPS
end
local function colliders(rt,swept)
 local boxes={}
 -- Supported nodeboxes extend up to 1.45 nodes outside the cell. The 2
 -- node halo includes those shapes even when the source node is not inside
 -- the swept footprint.
 local x1,x2=max(-31000,floor(swept[1]-2)),min(31000,floor(swept[4]+2))
 local y1,y2=max(-31000,floor(swept[2]-2)),min(31000,floor(swept[5]+2))
 local z1,z2=max(-31000,floor(swept[3]-2)),min(31000,floor(swept[6]+2))
 for x=x1,x2 do for y=y1,y2 do for z=z1,z2 do
  local pos={x=x,y=y,z=z}
  local node=rt.map:get_node(pos)
  local def=rt.registry.nodes[node.name]
  if def and def.walkable~=false and not def.buildable_to then
   for _,b in ipairs(Nodebox.boxes(
    def,node,rt.map,pos,rt.registry.nodes,'collision_box')) do
    boxes[#boxes+1]={box={x+b[1],y+b[2],z+b[3],
     x+b[4],y+b[5],z+b[6]},pos=pos}
   end
  end
 end end end
 return boxes
end
-- Continuous axis sweep: search geometry along the entire displacement.
-- Return actual displacement, collided node and contact normal.
local function sweep(rt,pos,box,axis,wanted)
 if abs(wanted)<EPS then return 0,nil end
 local before=aabb(pos,box)
 local index=indices[axis]
 local swept={before[1],before[2],before[3],before[4],before[5],before[6]}
 swept[index]=min(before[index],before[index]+wanted)
 swept[index+3]=max(before[index+3],before[index+3]+wanted)
 local actual,contact=wanted,nil
 for _,entry in ipairs(colliders(rt,swept)) do
  local other=entry.box
  local transverse=true
  for i=1,3 do
   if i~=index and not overlap(before[i],before[i+3],
      other[i],other[i+3]) then
    transverse=false;break
   end
  end
  if transverse then
   if wanted>0 and before[index+3]<=other[index]+EPS then
    local d=max(0,other[index]-before[index+3])
    if d<actual-EPS then actual,contact=d,entry.pos end
   elseif wanted<0 and before[index]>=other[index+3]-EPS then
    local d=min(0,other[index+3]-before[index])
    if d>actual+EPS then actual,contact=d,entry.pos end
   end
  end
 end
 return actual,contact
end
local function copy(v)return {x=v.x,y=v.y,z=v.z} end
function P.move(rt,obj,dt)
 local v,a=obj.velocity,obj.acceleration
 local before=copy(v)
 local result={touching_ground=false,collides=false,collisions={}}
 local physical=obj.properties.physical==true
 local requested={
  x=v.x*dt+.5*a.x*dt*dt,
  y=v.y*dt+.5*a.y*dt*dt,
  z=v.z*dt+.5*a.z*dt*dt}
 local final_v={x=v.x+a.x*dt,y=v.y+a.y*dt,z=v.z+a.z*dt}
 if physical then
  local box=obj.properties.collisionbox
  for _,axis in ipairs(axes) do
   local wanted=requested[axis]
   local actual,node=sweep(rt,obj.pos,box,axis,wanted)
   -- Preserve the existing world boundary behavior from phase 38.
   local bound=max(-31000,min(31000,obj.pos[axis]+actual))
   obj.pos[axis]=bound
   if node then
    result.collides=true
    if axis=='y' and wanted<0 then result.touching_ground=true end
    local normal={x=0,y=0,z=0}
    normal[axis]=wanted>0 and -1 or 1
    result.collisions[#result.collisions+1]={
     type='node',axis=axis,node_pos=copy(node),normal=normal,
     old_velocity=copy(before),
     -- The callback gets per-axis velocity after blocking this direction.
     new_velocity={x=final_v.x,y=final_v.y,z=final_v.z}}
    result.collisions[#result.collisions].new_velocity[axis]=0
    final_v[axis]=0
   elseif bound~=obj.pos[axis]+actual then
    final_v[axis]=0
   end
  end
  -- Contact with the ground is a state, not necessarily a new collision.
  -- Check support when a creature stands still on a slab and its velocity
  -- has already been reset by the previous collision frame.
  if not result.touching_ground and final_v.y<=0 then
   local probe,node=sweep(rt,obj.pos,box,'y',-.04)
   result.touching_ground=node~=nil and probe>-.04+EPS
  end
 else
  local nextpos={x=obj.pos.x+requested.x,
   y=obj.pos.y+requested.y,z=obj.pos.z+requested.z}
  if abs(nextpos.x)<=31000 and abs(nextpos.y)<=31000 and
     abs(nextpos.z)<=31000 then
   obj.pos=nextpos
  else
   final_v={x=0,y=0,z=0}
   a={x=0,y=0,z=0}
   obj.acceleration=a
  end
 end
 obj.velocity=final_v
 return result
end
return P
