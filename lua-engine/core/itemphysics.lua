-- Swept AABB item physics against the SAME collision boxes as the player
-- controller. Handles oriented, connected, leveled and wall-mounted nodeboxes.
-- Water introduces damping and lower effective gravity; this is an explicit
-- engine approximation, NOT a port of native Luanti liquid ObjectRef physics.
local Nodebox=require('core.nodebox')
local Physics={}
local floor,min,max,abs,exp=math.floor,math.min,math.max,math.abs,math.exp
local HALF=.16
local GRAVITY=9.81
local DRAG=4
local EPS=1e-8
local min_world,max_world=-30999,30999
local function finite(n)
 return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge
end
local indexes={x={1,4},y={2,5},z={3,6}}
local other_axes={x={'y','z'},y={'x','z'},z={'x','y'}}
local function intersect(a0,a1,b0,b1)
 return a0 < b1-EPS and b0 < a1-EPS
end
local function solid_boxes(rt,x,y,z)
 if abs(x)>31000 or abs(y)>31000 or abs(z)>31000 then
  return {{-.5,-.5,-.5,.5,.5,.5}}
 end
 local p={x=x,y=y,z=z}
 local node=rt.map:get_node(p)
 local def=rt.registry.nodes[node.name]
 if not def then return {{-.5,-.5,-.5,.5,.5,.5}} end
 if def.walkable==false or def.buildable_to then return nil end
 -- get_node_boxes resolves rotation, connected neighbors and leveled height
 -- in pure Lua. Empty boxes must not become an unintended solid cube.
 return Nodebox.boxes(def,node,rt.map,p,rt.registry.nodes,'collision_box')
end
-- Return only actual overlapping collision boxes. We check a two-cell
-- neighborhood because supported nodeboxes can protrude beyond their cell.
-- The same test is used to verify escape destinations, so an embedded item
-- cannot be moved into an adjacent wall or the closed world boundary.
local function overlaps(rt,pos)
 local collisions={}
 local x1,x2=floor(pos.x-HALF-2),floor(pos.x+HALF+2)
 local y1,y2=floor(pos.y-HALF-2),floor(pos.y+HALF+2)
 local z1,z2=floor(pos.z-HALF-2),floor(pos.z+HALF+2)
 for x=x1,x2 do for y=y1,y2 do for z=z1,z2 do
  local boxes=solid_boxes(rt,x,y,z)
  if boxes then
   for _,b in ipairs(boxes) do
    if intersect(pos.x-HALF,pos.x+HALF,x+b[1],x+b[4]) and
       intersect(pos.y-HALF,pos.y+HALF,y+b[2],y+b[5]) and
       intersect(pos.z-HALF,pos.z+HALF,z+b[3],z+b[6]) then
     collisions[#collisions+1]={x+b[1],y+b[2],z+b[3],
      x+b[4],y+b[5],z+b[6]}
    end
   end
  end
 end end end
 return collisions
end
-- Builtin item_entity.lua's stuck recovery tries +X,-X,+Z,-Z and +Y.
-- Here a candidate is the *nearest face* of an overlapping collision box,
-- not the border of the enclosing voxel. Verify that the whole target
-- AABB is free before committing. If there is no free destination, keep
-- the item intact and retry when the terrain changes.
function Physics.unstick(rt,pos)
 local collisions=overlaps(rt,pos)
 if #collisions==0 then return true end
 local directions={{'x',4,1},{'x',1,-1},{'z',6,1},
  {'z',3,-1},{'y',5,1}}
 for _,entry in ipairs(directions) do
  local axis,index,direction=entry[1],entry[2],entry[3]
  local candidates={}
  for _,box in ipairs(collisions) do
   local target=box[index]+direction*(HALF+0.00001)
   local delta=(target-pos[axis])*direction
   if delta>0 and target>=min_world and target<=max_world then
    candidates[#candidates+1]={target=target,delta=delta}
   end
  end
  table.sort(candidates,function(a,b) return a.delta<b.delta end)
  for _,candidate in ipairs(candidates) do
   local nextpos={x=pos.x,y=pos.y,z=pos.z}
   nextpos[axis]=candidate.target
   if #overlaps(rt,nextpos)==0 then
    pos.x,pos.y,pos.z=nextpos.x,nextpos.y,nextpos.z
    return true
   end
  end
 end
 return false
end
local function sweep(rt,pos,axis,delta)
 if delta==0 then return false,nil end
 local current=pos[axis]
 local target=max(min_world,min(max_world,current+delta))
 local positive=target>current
 if current==target then return false,nil end
 local aa,bb=other_axes[axis][1],other_axes[axis][2]
 local i=indexes[axis]
 local j,k=indexes[aa],indexes[bb]
 -- Luanti nodeboxes can protrude 1.45 nodes outside their own cell.
 -- The broadphase includes a two-node halo so thin fence arms and panels
 -- protruding from adjacent nodes are never missed by a long movement.
 local range={}
 for _,coord in ipairs({'x','y','z'}) do
  local start,finish
  if coord==axis then
   start=min(current,target)-HALF
   finish=max(current,target)+HALF
  else
   start=pos[coord]-HALF
   finish=pos[coord]+HALF
  end
  range[coord]={max(-31000,floor(start-2)),
   min(31000,floor(finish+2))}
 end
 local contact=nil
 local hit_node=nil
 for x=range.x[1],range.x[2] do
  for y=range.y[1],range.y[2] do
   for z=range.z[1],range.z[2] do
    local center={x=x,y=y,z=z}
    local boxes=solid_boxes(rt,x,y,z)
    if boxes then
     for _,b in ipairs(boxes) do
      if intersect(pos[aa]-HALF,pos[aa]+HALF,
        center[aa]+b[j[1]],center[aa]+b[j[2]]) and
       intersect(pos[bb]-HALF,pos[bb]+HALF,
        center[bb]+b[k[1]],center[bb]+b[k[2]]) then
       local boundary=positive and
        (center[axis]+b[i[1]]-HALF) or
        (center[axis]+b[i[2]]+HALF)
       local crosses=positive and
        (current<=boundary+EPS and target>=boundary-EPS) or
        (current>=boundary-EPS and target<=boundary+EPS)
       if crosses and (contact==nil or
         (positive and boundary<contact) or
         (not positive and boundary>contact)) then
        contact=boundary
        hit_node=rt.registry.nodes[rt.map:get_node(center).name]
       end
      end
     end
    end
   end
  end
 end
 if contact~=nil then
  pos[axis]=contact
  return true,hit_node
 end
 pos[axis]=target
 return false,nil
end
local function in_liquid(rt,pos)
 local p={x=floor(pos.x+.5),y=floor(pos.y+.5),
  z=floor(pos.z+.5)}
 local n=rt.map:get_node(p)
 local def=rt.registry.nodes[n.name]
 return def and def.liquidtype and def.liquidtype~='none'
end
local function damping(rt,dt)
 local rate=rt.opts.item_liquid_drag
 if rate==nil then rate=3 end
 assert(finite(rate) and rate>=0,'invalid item liquid drag')
 return exp(-rate*dt)
end
function Physics.step(rt,dt)
 assert(finite(dt) and dt>=0,'item physics timestep must be finite')
 if rt.opts.item_physics==false or dt==0 then return end
 local g=rt.api.settings:get_num('movement_gravity',GRAVITY)
 if not finite(g) or g<0 then g=GRAVITY end
 for _,item in ipairs(rt.droppedItems or {}) do
  local v=item.velocity
  if v then
   -- Never discard objects that spawn inside solid nodes: escape through
   -- a genuinely free face or remain in place until space becomes available.
   if not Physics.unstick(rt,item.pos) then
    v.x,v.y,v.z=0,0,0
   else
   local wet=in_liquid(rt,item.pos)
   local effective_g=g
   if wet then
    local k=damping(rt,dt)
    v.x,v.y,v.z=v.x*k,v.y*k,v.z*k
    -- Approximate submerged resistance while retaining downward gravity.
    effective_g=g*.25
   end
   local dy=v.y*dt-.5*effective_g*dt*dt
   local dx,dz=v.x*dt,v.z*dt
   if sweep(rt,item.pos,'x',dx) then v.x=0 end
   if sweep(rt,item.pos,'z',dz) then v.z=0 end
   local grounded,grounddef=sweep(rt,item.pos,'y',dy)
   if grounded then
    v.y=0
    local slipperiness=tonumber(grounddef and
     (grounddef.groups or {}).slippery) or 0
    if slipperiness<0 then slipperiness=0 end
    local friction=DRAG/(slipperiness+4)*4
    local attenuation=exp(-friction*dt)
    v.x,v.z=v.x*attenuation,v.z*attenuation
    if abs(v.x)<.005 then v.x=0 end
    if abs(v.z)<.005 then v.z=0 end
   else
    v.y=v.y-effective_g*dt
   end
   end -- world space available after stuck-object recovery
  end
 end
end
return Physics
