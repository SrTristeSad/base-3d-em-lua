-- Item entity motion. Axis-aligned swept voxel checks prevent tunneling
-- through full solid nodes, even with large delta times. This remains a
-- subset of Luanti's physics: no moving objects/player collision or liquid
-- buoyancy, and nodeboxes use their enclosing map cell.
local Physics={}
local floor=math.floor
local abs=math.abs
local HALF=.16
local GRAVITY=9.81
local DRAG=4
local function finite(n)
 return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge
end
local function node_blocks(rt,x,y,z)
 if abs(x)>31000 or abs(y)>31000 or abs(z)>31000 then return true end
 local node=rt.map:get_node({x=x,y=y,z=z})
 local def=rt.registry.nodes[node.name]
 if not def then return true end
 return def.walkable~=false and not def.buildable_to
end
local function axis_collision(rt,pos,axis,index,direction)
 local a,b
 if axis=='x' then a,b='y','z'
 elseif axis=='y' then a,b='x','z'
 else a,b='x','y' end
 local loA,hiA=floor(pos[a]-HALF+.5),floor(pos[a]+HALF+.5)
 local loB,hiB=floor(pos[b]-HALF+.5),floor(pos[b]+HALF+.5)
 for v=loA,hiA do
  for w=loB,hiB do
   local x,y,z
   if axis=='x' then x,y,z=index,v,w
   elseif axis=='y' then x,y,z=v,index,w
   else x,y,z=v,w,index end
   if node_blocks(rt,x,y,z) then return true end
  end
 end
 return false
end
-- Sweeps the front face of a small AABB through every crossed voxel.
local function sweep(rt,pos,axis,delta)
 if delta==0 then return false end
 local current=pos[axis]
 local target=math.max(-30999,math.min(30999,current+delta))
 local direction=target>current and 1 or -1
 local front=current+direction*HALF
 local nextfront=target+direction*HALF
 local start=floor(front+.5)
 local finish=floor(nextfront+.5)
 if direction==1 then
  for cell=start+1,finish do
   if axis_collision(rt,pos,axis,cell,direction) then
    pos[axis]=cell-.5-HALF
    return true
   end
  end
 else
  for cell=start-1,finish,-1 do
   if axis_collision(rt,pos,axis,cell,direction) then
    pos[axis]=cell+.5+HALF
    return true
   end
  end
 end
 pos[axis]=target
 return false
end
function Physics.step(rt,dt)
 assert(finite(dt) and dt>=0,'item physics timestep must be finite')
 if rt.opts.item_physics==false or dt==0 then return end
 local g=rt.api.settings:get_num('movement_gravity',GRAVITY)
 if not finite(g) or g<0 then g=GRAVITY end
 for _,item in ipairs(rt.droppedItems or {}) do
  local v=item.velocity
  if v then
   -- Motion is integrated before pickup; the rendered position and
   -- interaction target always refer to the same physical object.
   local dy=v.y*dt-.5*g*dt*dt
   local dx,dz=v.x*dt,v.z*dt
   if sweep(rt,item.pos,'x',dx) then v.x=0 end
   if sweep(rt,item.pos,'z',dz) then v.z=0 end
   local grounded=sweep(rt,item.pos,'y',dy)
   if grounded then
    v.y=0
    -- Friction only when resting against walkable ground.
    local attenuation=math.exp(-DRAG*dt)
    v.x,v.z=v.x*attenuation,v.z*attenuation
    if abs(v.x)<.005 then v.x=0 end
    if abs(v.z)<.005 then v.z=0 end
   else
    v.y=v.y-g*dt
   end
  end
 end
end
return Physics
