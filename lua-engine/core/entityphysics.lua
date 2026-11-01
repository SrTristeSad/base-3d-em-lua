-- Swept LuaEntity AABB physics, matching the native object-property model.
-- Nodes use real collision_box geometry; other physical LuaEntities may
-- block movement when BOTH parties have collide_with_objects enabled.
-- Object response is deterministic sequential blocking, NOT native impulses.
local Nodebox=require('core.nodebox')
local P={}
local floor,min,max,abs=math.floor,math.min,math.max,math.abs
local EPS=1e-8
local axes={'x','y','z'}
local indices={x=1,y=2,z=3}
local function copy(v) return {x=v.x,y=v.y,z=v.z} end
local function aabb(pos,box)
 return {pos.x+box[1],pos.y+box[2],pos.z+box[3],
  pos.x+box[4],pos.y+box[5],pos.z+box[6]}
end
local function overlap(a,b,c,d)
 return a<d-EPS and c<b-EPS
end
local function colliders(rt,swept,selfobj)
 local boxes={}
 -- Supported nodeboxes can extend 1.45 nodes beyond their voxel cell.
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
    boxes[#boxes+1]={type='node',box={
     x+b[1],y+b[2],z+b[3],x+b[4],y+b[5],z+b[6]},node_pos=pos}
   end
  end
 end end end
 if selfobj.properties.collide_with_objects~=false then
  for _,other in ipairs(rt.luaEntities or {}) do
   if other~=selfobj and not other.removed and
    other.properties.physical==true and
    other.properties.collide_with_objects~=false then
    local candidate=aabb(other.pos,other.properties.collisionbox)
    if overlap(swept[1],swept[4],candidate[1],candidate[4]) and
      overlap(swept[2],swept[5],candidate[2],candidate[5]) and
      overlap(swept[3],swept[6],candidate[3],candidate[6]) then
     boxes[#boxes+1]={type='object',box=candidate,object=other}
    end
   end
  end
 end
 return boxes
end
local function sweep(rt,obj,pos,box,axis,wanted)
 if abs(wanted)<EPS then return 0,nil end
 local before=aabb(pos,box)
 local index=indices[axis]
 local swept={before[1],before[2],before[3],before[4],before[5],before[6]}
 swept[index]=min(before[index],before[index]+wanted)
 swept[index+3]=max(before[index+3],before[index+3]+wanted)
 local actual,contact=wanted,nil
 for _,entry in ipairs(colliders(rt,swept,obj)) do
  local other=entry.box
  local transverse=true
  for i=1,3 do
   if i~=index and not overlap(before[i],before[i+3],
      other[i],other[i+3]) then transverse=false;break end
  end
  if transverse then
   if wanted>0 and before[index+3]<=other[index]+EPS then
    local d=max(0,other[index]-before[index+3])
    if d<actual-EPS then actual,contact=d,entry end
   elseif wanted<0 and before[index]>=other[index+3]-EPS then
    local d=min(0,other[index+3]-before[index])
    if d>actual+EPS then actual,contact=d,entry end
   end
  end
 end
 return actual,contact
end
local function ground(rt,obj,pos,box)
 local probe,contact=sweep(rt,obj,pos,box,'y',-.045)
 return contact~=nil and probe>-.045+EPS
end
local function horizontal(rt,obj,initial,box,dx,dz)
 local pos=copy(initial)
 local actualx,contactx=sweep(rt,obj,pos,box,'x',dx)
 pos.x=pos.x+actualx
 local actualz,contactz=sweep(rt,obj,pos,box,'z',dz)
 pos.z=pos.z+actualz
 return pos,contactx,contactz
end
local function sqdist(p,q)
 return (p.x-q.x)^2+(p.z-q.z)^2
end
local function record(result,contact,axis,wanted,before,final_v)
 result.collides=true
 if axis=='y' and wanted<0 then result.touching_ground=true end
 local normal={x=0,y=0,z=0}
 normal[axis]=wanted>0 and -1 or 1
 local collision={type=contact.type,axis=axis,normal=normal,
  old_velocity=copy(before),new_velocity=copy(final_v)}
 if contact.type=='node' then
  collision.node_pos=copy(contact.node_pos)
 else collision.object=contact.object end
 collision.new_velocity[axis]=0
 result.collisions[#result.collisions+1]=collision
 final_v[axis]=0
end
function P.move(rt,obj,dt)
 local v,a=obj.velocity,obj.acceleration
 local before=copy(v)
 local result={touching_ground=false,collides=false,collisions={}}
 local displacement={x=v.x*dt+.5*a.x*dt*dt,
  y=v.y*dt+.5*a.y*dt*dt,z=v.z*dt+.5*a.z*dt*dt}
 local final_v={x=v.x+a.x*dt,y=v.y+a.y*dt,z=v.z+a.z*dt}
 if obj.properties.physical==true then
  local box=obj.properties.collisionbox
  local start=copy(obj.pos)
  local initial_grounded=ground(rt,obj,start,box)
  local normal,cx,cz=horizontal(rt,obj,start,box,
   displacement.x,displacement.z)
  local chosen=normal
  local stepped=false
  local height=obj.properties.stepheight or 0
  -- A step is attempted only while supported, moving horizontally
  -- into a node/object, and not deliberately jumping or ascending.
  if height>0 and initial_grounded and displacement.y<=EPS and
     (cx or cz) then
   local rise,ceiling=sweep(rt,obj,start,box,'y',height)
   if not ceiling and rise>=height-EPS and
      start.y+rise<=31000 then
    local raised=copy(start);raised.y=raised.y+rise
    local candidate=horizontal(rt,obj,raised,box,
     displacement.x,displacement.z)
    local drop,landing=sweep(rt,obj,candidate,box,'y',
     -(height+.045))
    if landing then
     candidate.y=candidate.y+drop
     if candidate.y>=start.y-EPS and
       sqdist(start,candidate)>sqdist(start,normal)+EPS then
      chosen=candidate
      stepped=true
      result.touching_ground=true
     end
    end
   end
  end
  -- Preserve collision details only on the path actually selected.
  if not stepped then
   if cx then record(result,cx,'x',displacement.x,before,final_v) end
   if cz then record(result,cz,'z',displacement.z,before,final_v) end
  end
  obj.pos=chosen
  -- Integrate vertical acceleration after horizontal/step movement.
  -- Downward sweep from a successful step cannot pass the new support.
  local dy,cy=sweep(rt,obj,obj.pos,box,'y',displacement.y)
  local target=max(-31000,min(31000,obj.pos.y+dy))
  if cy then
   record(result,cy,'y',displacement.y,before,final_v)
  elseif target~=obj.pos.y+dy then final_v.y=0 end
  obj.pos.y=target
  if stepped and not result.touching_ground then
   -- A step ending on support is grounded even without new Y movement.
   result.touching_ground=ground(rt,obj,obj.pos,box)
  end
  if not result.touching_ground and final_v.y<=0 then
   result.touching_ground=ground(rt,obj,obj.pos,box)
  end
 else
  local proposed={x=obj.pos.x+displacement.x,
   y=obj.pos.y+displacement.y,z=obj.pos.z+displacement.z}
  if abs(proposed.x)<=31000 and abs(proposed.y)<=31000 and
     abs(proposed.z)<=31000 then obj.pos=proposed
  else
   final_v={x=0,y=0,z=0}
   obj.acceleration={x=0,y=0,z=0}
  end
 end
 obj.velocity=final_v
 return result
end
return P
