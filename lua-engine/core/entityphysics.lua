-- Swept LuaEntity AABB physics, matching the native object-property model.
-- Nodes use real collision_box geometry; other physical LuaEntities may
-- block movement when BOTH parties have collide_with_objects enabled.
-- Object response is deterministic sequential blocking, NOT native impulses.
local CollisionGeometry=require('core.collisiongeometry')
local SpatialIndex=require('core.spatialindex')
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
 local boxes=CollisionGeometry.collect(rt,swept,2,true)
 if selfobj.properties.collide_with_objects~=false then
  for _,other in ipairs(SpatialIndex.query(rt,swept,selfobj)) do
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
 -- Players are host-owned ObjectRefs. Only a player with an attached
 -- controller has authoritative position and collisionbox geometry here.
 -- Unbound native host players are not guessed at by the Lua engine.
 if selfobj.properties.collide_with_objects~=false then
  local names={}
  for name in pairs(rt.playerPhysicsControllers or {}) do
   if rt.players[name] then names[#names+1]=name end
  end
  table.sort(names)
  for _,name in ipairs(names) do
   local controller=rt.playerPhysicsControllers[name]
   local player=rt.players[name]
   local geometry=controller:get_properties().collisionbox
   local candidate=aabb(controller:get_pos(),geometry)
   if overlap(swept[1],swept[4],candidate[1],candidate[4]) and
    overlap(swept[2],swept[5],candidate[2],candidate[5]) and
    overlap(swept[3],swept[6],candidate[3],candidate[6]) then
    boxes[#boxes+1]={type='object',box=candidate,object=player}
   end
  end
 end
 return boxes
end
-- Available to the host player controller for symmetric obstacle tests.
-- Always read live positions; disconnected players must not retain a provider.
function P.entity_boxes(rt,swept)
 local boxes={}
 local candidates
 if swept then
  candidates=SpatialIndex.query(rt,swept)
 else
  -- Explicit unbounded queries are retained for existing callers.
  candidates=rt.luaEntities or {}
 end
 for _,obj in ipairs(candidates) do
  local prop=obj.properties
  if not obj.removed and prop.physical==true and
    prop.collide_with_objects~=false then
   boxes[#boxes+1]=aabb(obj.pos,prop.collisionbox)
  end
 end
 return boxes
end
-- Recover a newly spawned/teleported physical entity already embedded in
-- a block or another object. Each attempt chooses a shortest free exit.
-- No candidate may overlap any collidable geometry; never force teleport
-- into a different obstacle or beyond the supported world bounds.
local function recover(rt,obj,result)
 local box=obj.properties.collisionbox
 for _=1,8 do
  local current=aabb(obj.pos,box)
  local colliding=nil
  for _,entry in ipairs(colliders(rt,current,obj)) do
   local b=entry.box
   if overlap(current[1],current[4],b[1],b[4]) and
      overlap(current[2],current[5],b[2],b[5]) and
      overlap(current[3],current[6],b[3],b[6]) then
    colliding=entry
    break
   end
  end
  if not colliding then return end
  local choices={}
  for _,axis in ipairs(axes) do
   local index=indices[axis]
   local other=colliding.box
   local down=other[index]-current[index+3]-EPS*4
   local up=other[index+3]-current[index]+EPS*4
   choices[#choices+1]={axis=axis,d=down}
   choices[#choices+1]={axis=axis,d=up}
  end
  table.sort(choices,function(a,b)return abs(a.d)<abs(b.d) end)
  local chosen
  for _,choice in ipairs(choices) do
   local candidate=copy(obj.pos)
   candidate[choice.axis]=candidate[choice.axis]+choice.d
   if abs(candidate.x)<=31000 and abs(candidate.y)<=31000 and
      abs(candidate.z)<=31000 then
    local bounds=aabb(candidate,box)
    local clear=true
    for _,entry in ipairs(colliders(rt,bounds,obj)) do
     local other=entry.box
     if overlap(bounds[1],bounds[4],other[1],other[4]) and
        overlap(bounds[2],bounds[5],other[2],other[5]) and
        overlap(bounds[3],bounds[6],other[3],other[6]) then
      clear=false;break
     end
    end
    if clear then chosen=choice;break end
   end
  end
  if not chosen then return end
  local oldvelocity=copy(obj.velocity)
  obj.pos[chosen.axis]=obj.pos[chosen.axis]+chosen.d
  obj.velocity[chosen.axis]=0
  local normal={x=0,y=0,z=0}
  normal[chosen.axis]=chosen.d<0 and -1 or 1
  local hit={type=colliding.type,axis=chosen.axis,normal=normal,
   old_velocity=oldvelocity,new_velocity=copy(obj.velocity),
   recovery=true}
  if colliding.type=='node' then hit.node_pos=copy(colliding.node_pos)
  else hit.object=colliding.object end
  result.collides=true
  result.collisions[#result.collisions+1]=hit
 end
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
 local before
 local result={touching_ground=false,collides=false,collisions={}}
 if obj.properties.physical==true then recover(rt,obj,result) end
 -- Recovery changes the entity's live velocity before integration.
 v=obj.velocity
 before=copy(v)
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
 if obj.properties.physical==true then
  SpatialIndex.update(rt,obj)
 end
 return result
end
return P
