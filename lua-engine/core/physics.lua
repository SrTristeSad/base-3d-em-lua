-- Independent Lua character controller against actual node collision boxes.
-- Coordinates are node-centered; character pos.y is FEET, not eye height.
-- Sweep each axis against AABBs to prevent walking/tunneling through solids.
local Physics={}
Physics.__index=Physics
local floor,sqrt,max,min,abs=math.floor,math.sqrt,math.max,math.min,math.abs
local EPS=1e-7
local function finite(n)
 return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge
end
local function approach(current,target,rate,dt)
 if rate==0 then return target end  -- compatibility for old instant-move configs
 if current<target then return min(target,current+rate*dt) end
 return max(target,current-rate*dt)
end
local function valid_rate(n)
 return finite(n) and n>=0
end
local function group(def,name)
 local groups=def and def.groups
 return type(groups)=='table' and tonumber(groups[name]) or 0
end
local function copy(p) return {x=p.x,y=p.y,z=p.z} end
-- Luanti ObjectRef physics overrides are multiplicative. Keep only
-- supported fields, and return copies so callers cannot mutate our state.
local override_keys={
 speed=true,speed_walk=true,speed_crouch=true,speed_fast=true,
 speed_climb=true,jump=true,gravity=true,
 acceleration_default=true,acceleration_air=true,
 acceleration_fast=true,liquid_sink=true,
 liquid_fluidity=true,liquid_fluidity_smooth=true,
}
local flag_keys={sneak=true,sneak_glitch=true,new_move=true}
local function default_overrides()
 local value={}
 for name in pairs(override_keys) do value[name]=1 end
 value.sneak=true;value.sneak_glitch=false;value.new_move=true
 return value
end

local function bounds(p,r,h)
 return {p.x-r,p.y,p.z-r,p.x+r,p.y+h,p.z+r}
end
local function overlap(a,b,c,d)
 return a<d-EPS and c<b-EPS
end
local function broadphase(box)
 -- A node may have nodeboxes extending outside its cell (e.g. fences).
 return floor(box[1]-1.5),floor(box[4]+1.5),
  floor(box[2]-1.5),floor(box[5]+1.5),
  floor(box[3]-1.5),floor(box[6]+1.5)
end
function Physics.new(api,position,opts)
 assert(type(api)=='table' and type(api.get_node)=='function' and
  type(api.get_node_boxes)=='function','physics requires Lua node collision APIs')
 opts=opts or {}
 position=position or {x=0,y=4,z=0}
 for _,k in ipairs({'x','y','z'}) do
  assert(finite(position[k]),'invalid player '..k)
 end
 local radius=opts.radius or .3
 local height=opts.height or 1.8
 local stepheight=opts.stepheight or .6
 local eyeheight=opts.eyeheight or 1.62
 local default_profile=opts.profile=='luanti'
 assert(opts.profile==nil or opts.profile=='luanti',
  'unknown physics profile')
 -- Official Luanti movement defaults, opt-in for backwards-compatible tests.
 -- Braking and terminal velocity are local prototype approximations.
 local base_speed=default_profile and 4 or 4.8
 local base_fast=default_profile and 20 or 7.2
 local base_jump=default_profile and 6.5 or 7.2
 local base_gravity=default_profile and 9.81 or 20
 local base_accel=default_profile and 3 or 26
 local base_air=default_profile and 2 or 9
 local acceleration=opts.acceleration==nil and base_accel or opts.acceleration
 local braking=opts.braking==nil and 20 or opts.braking
 local air_acceleration=opts.air_acceleration==nil and base_air or opts.air_acceleration
 local water_acceleration=opts.water_acceleration==nil and 8 or opts.water_acceleration
 local water_braking=opts.water_braking==nil and 7 or opts.water_braking
 local water_gravity=opts.water_gravity==nil and 3 or opts.water_gravity
 local water_drag=opts.water_drag==nil and 3 or opts.water_drag
 local swim_speed=opts.swim_speed==nil and 3 or opts.swim_speed
 local climb_speed=opts.climb_speed==nil and 3 or opts.climb_speed
 local sneak_speed=opts.sneak_speed==nil and
  (default_profile and 1.35 or 1.5) or opts.sneak_speed
 local sneak_eye_offset=opts.sneak_eye_offset==nil and .28 or opts.sneak_eye_offset
 assert(finite(radius) and radius>0 and radius<=.5)
 assert(finite(height) and height>0 and height<=3)
 assert(finite(stepheight) and stepheight>=0 and stepheight<=1)
 assert(finite(eyeheight) and eyeheight>0 and eyeheight<=height)
 assert(valid_rate(sneak_speed) and finite(sneak_eye_offset) and
  sneak_eye_offset>=0 and sneak_eye_offset<eyeheight,
  'invalid sneak movement configuration')
 for _,rate in ipairs({acceleration,braking,air_acceleration,
  water_acceleration,water_braking,water_gravity,water_drag,
  swim_speed,climb_speed}) do
  assert(valid_rate(rate),'invalid movement parameter')
 end
 for _,entry in ipairs({opts.speed or base_speed,opts.sprint_speed or base_fast,
  opts.gravity or base_gravity,opts.jump_speed or base_jump,
  opts.terminal_velocity or 40}) do
  assert(valid_rate(entry),'invalid character physics tuning')
 end
 assert(valid_rate(opts.sneak_camera_rate==nil and 2.8 or opts.sneak_camera_rate),
  'invalid sneak camera rate')
 return setmetatable({
  api=api,pos=copy(position),velocity={x=0,y=0,z=0},
  radius=radius,height=height,eyeheight=eyeheight,
  stepheight=stepheight,gravity=opts.gravity or base_gravity,
  jump_speed=opts.jump_speed or base_jump,
  speed=opts.speed or base_speed,sprint_speed=opts.sprint_speed or base_fast,
  terminal_velocity=opts.terminal_velocity or 40,
  acceleration=acceleration,braking=braking,
  air_acceleration=air_acceleration,
  water_acceleration=water_acceleration,water_braking=water_braking,
  water_gravity=water_gravity,water_drag=water_drag,
  swim_speed=swim_speed,climb_speed=climb_speed,
  fluid_physics=opts.fluid_physics~=false,
  sneak_speed=sneak_speed,sneak_eye_offset=sneak_eye_offset,
  sneak_camera_rate=opts.sneak_camera_rate==nil and 2.8 or opts.sneak_camera_rate,
  sneak_edge_guard=opts.sneak_edge_guard~=false,
  sneaking=false,view_offset=0,
  grounded=false,in_liquid=false,on_ladder=false,
  physics_overrides=default_overrides()
 },Physics)
end
function Physics:set_physics_override(override)
 assert(type(override)=='table','physics override must be a table')
 -- Validate the entire transaction before modifying the live state.
 for name,value in pairs(override) do
  if override_keys[name] then
   assert(finite(value) and value>=0,
    'invalid numeric physics override: '..name)
   if name=='liquid_fluidity' then
    assert(value>=1,'liquid_fluidity below 1 is unsupported')
   end
  elseif flag_keys[name] then
   assert(type(value)=='boolean',
    'invalid boolean physics override: '..name)
  else
   error('unsupported physics override: '..tostring(name))
  end
 end
 for name,value in pairs(override) do
  self.physics_overrides[name]=value
 end
end
function Physics:get_physics_override()
 local result={}
 for name,value in pairs(self.physics_overrides) do result[name]=value end
 return result
end

function Physics:eye()
 return {x=self.pos.x,y=self.pos.y+self.eyeheight+self.view_offset,z=self.pos.z}
end
function Physics:colliders(swept)
 local x1,x2,y1,y2,z1,z2=broadphase(swept)
 local colliders={}
 for x=x1,x2 do for y=y1,y2 do for z=z1,z2 do
  local pos={x=x,y=y,z=z}
  local node=self.api.get_node(pos)
  local def=self.api.registered_nodes[node.name]
  if def and def.walkable~=false then
   -- Collision boxes are DISTINCT from visible geometry. For nodebox
   -- drawtypes, the runtime supplies connected and facedir shapes.
   local boxes=self.api.get_node_boxes('collision_box',pos,node)
   for _,b in ipairs(boxes) do
    colliders[#colliders+1]={
     x+b[1],y+b[2],z+b[3],x+b[4],y+b[5],z+b[6]
    }
   end
  end
 end end end
 return colliders
end
-- Contact with climbable nodes or liquids is independent from walkable
-- collision geometry. Sample a small footprint at leg and chest height.
function Physics:medium()
 local p=self.pos
 local radius=self.radius*.8
 local offsets={{0,0},{radius,0},{-radius,0},{0,radius},{0,-radius}}
 local heights={.2,self.height*.55}
 local liquid=false
 for _,offset in ipairs(offsets) do
  for _,height in ipairs(heights) do
   local at={x=floor(p.x+offset[1]+.5),
    y=floor(p.y+height+.5),
    z=floor(p.z+offset[2]+.5)}
   local node=self.api.get_node(at)
   local def=self.api.registered_nodes[node.name]
   if def then
    if def.climbable==true then return false,true end
    if self.fluid_physics and
     ((def.liquidtype and def.liquidtype~='none')
       or group(def,'water')>0 or group(def,'liquid')>0) then
     liquid=true
    end
   end
  end
 end
 return liquid,false
end
-- Look up the material that is ACTUALLY supporting the feet. The
-- simple cell under player center can be air alongside slabs, stairs and
-- narrow nodeboxes; friction must follow the resolved collision surface.
function Physics:ground_material()
 local p,r=self.pos,self.radius
 local best,best_area=nil,0
 local sample_bottom=p.y-.075
 for x=floor(p.x-r-1),floor(p.x+r+1) do
  for z=floor(p.z-r-1),floor(p.z+r+1) do
   for y=floor(p.y-1.5),floor(p.y+.5) do
    local where={x=x,y=y,z=z}
    local node=self.api.get_node(where)
    local def=self.api.registered_nodes[node.name]
    if def and def.walkable~=false then
     local boxes=self.api.get_node_boxes('collision_box',where,node)
     for _,b in ipairs(boxes) do
      local top=y+b[5]
      if top<=p.y+.02 and top>=sample_bottom then
       local left=max(p.x-r,x+b[1])
       local right=min(p.x+r,x+b[4])
       local near=max(p.z-r,z+b[3])
       local far=min(p.z+r,z+b[6])
       local area=max(0,right-left)*max(0,far-near)
       if area>best_area+EPS then best_area=area;best=def end
      end
     end
    end
   end
  end
 end
 return best
end
function Physics:surface_friction()
 local value=group(self:ground_material(),'slippery')
 return value>0 and 1/(value+1) or 1
end

function Physics:supportAt(p)
 local probe=.035
 local below={
  p.x-probe,p.y-.085,p.z-probe,
  p.x+probe,p.y+.03,p.z+probe
 }
 for _,box in ipairs(self:colliders(below)) do
  if box[4]>p.x-probe+EPS and box[1]<p.x+probe-EPS and
     box[6]>p.z-probe+EPS and box[3]<p.z+probe-EPS and
     box[5]>=p.y-.085-EPS and box[5]<=p.y+.02 then
   return true
  end
 end
 return false
end

-- Resolve each lateral coordinate separately: this allows walking ALONG a
-- cliff without accepting unsupported diagonal destinations. A binary
-- search finds the last supported position along each blocked component.
function Physics:sneakClamp(start,destination)
 local p=copy(start)
 for _,axis in ipairs({'x','z'}) do
  local distance=destination[axis]-start[axis]
  local candidate=copy(p)
  candidate[axis]=p[axis]+distance
  if self:supportAt(candidate) then
   p=candidate
  elseif self:supportAt(p) then
   local low,high=0,1
   for _=1,15 do
    local midpoint=(low+high)*.5
    candidate[axis]=p[axis]+distance*midpoint
    if self:supportAt(candidate) then
     low=midpoint
    else
     high=midpoint
    end
   end
   p[axis]=p[axis]+distance*low
   self.velocity[axis]=0
  end
 end
 return p
end

function Physics:clip(p,axis,wanted)
 if abs(wanted)<EPS then return 0,false end
 local before=bounds(p,self.radius,self.height)
 local index=axis=='x' and 1 or axis=='y' and 2 or 3
 local swept={before[1],before[2],before[3],before[4],before[5],before[6]}
 swept[index]=min(before[index],before[index]+wanted)
 swept[index+3]=max(before[index+3],before[index+3]+wanted)
 local actual=wanted
 local blocked=false
 for _,b in ipairs(self:colliders(swept)) do
  local transverse=true
  for i=1,3 do
   if i~=index and not overlap(before[i],before[i+3],b[i],b[i+3]) then
    transverse=false
    break
   end
  end
  if transverse then
   if wanted>0 and before[index+3]<=b[index]+EPS then
    local distance=max(0,b[index]-before[index+3])
    if distance<actual then actual=distance;blocked=true end
   elseif wanted<0 and before[index]>=b[index+3]-EPS then
    local distance=min(0,b[index+3]-before[index])
    if distance>actual then actual=distance;blocked=true end
   end
  end
 end
 return actual,blocked
end
local function horizontal(self,start,dx,dz)
 local p=copy(start)
 local mx,bx=self:clip(p,'x',dx)
 p.x=p.x+mx
 local mz,bz=self:clip(p,'z',dz)
 p.z=p.z+mz
 return p,(bx or bz)
end
local function distance2(start,p)
 return (p.x-start.x)^2+(p.z-start.z)^2
end
function Physics:tick(dt,input)
 input=input or {}
 -- Movement input uses world-space X/Z; the caller handles camera yaw.
 local dx,dz=input.x or 0,input.z or 0
 assert(finite(dx) and finite(dz) and finite(dt) and dt>0)
 local length=sqrt(dx*dx+dz*dz)
 if length>1 then dx=dx/length;dz=dz/length end
 self.in_liquid,self.on_ladder=self:medium()
 local ground_delta,ground_hit=self:clip(self.pos,'y',-.045)
 self.grounded=ground_hit and ground_delta>-.045+EPS
 -- Ctrl serves as ladder/water descent in those media, not edge sneak.
 self.sneaking=input.sneak==true and self.physics_overrides.sneak and
  self.grounded and
  not self.in_liquid and not self.on_ladder
 local target_eye=self.sneaking and -self.sneak_eye_offset or 0
 self.view_offset=approach(self.view_offset,target_eye,
  self.sneak_camera_rate,dt)
 local traction=self.grounded and self:surface_friction() or 1
 local ov=self.physics_overrides
 local speed_factor=ov.speed
 local speed=self.sneaking and
  self.sneak_speed*ov.speed_crouch or
  (input.sprint and self.sprint_speed*ov.speed_fast or
   self.speed*ov.speed_walk)
 speed=speed*speed_factor
 if self.in_liquid then speed=speed*.48 end
 local rate
 if self.in_liquid then
  rate=(length>EPS and self.water_acceleration or self.water_braking)*
   ov.liquid_fluidity
 elseif self.grounded then
  rate=(length>EPS and self.acceleration or self.braking)*traction
 else
  rate=(length>EPS and self.air_acceleration or self.braking*.2)
 end
 rate=rate*speed_factor*
  (self.grounded and ov.acceleration_default or ov.acceleration_air)
 if input.sprint and self.grounded then
  rate=rate*ov.acceleration_fast
 end
 self.velocity.x=approach(self.velocity.x,dx*speed,rate,dt)
 self.velocity.z=approach(self.velocity.z,dz*speed,rate,dt)
 local vx,vz=self.velocity.x,self.velocity.z
 local jumping=input.jump and self.grounded and
  not self.in_liquid and not self.on_ladder
 if jumping then
  self.velocity.y=self.jump_speed*ov.jump
  self.grounded=false
 elseif self.grounded and self.velocity.y<0 then
  self.velocity.y=0
 end
 local xmove,zmove=vx*dt,vz*dt
 local old=copy(self.pos)
 local normal=horizontal(self,old,xmove,zmove)
 local chosen=normal
 local can_step=self.stepheight>0 and self.grounded and not jumping and
  (abs(xmove)>EPS or abs(zmove)>EPS) and
  distance2(old,normal)+EPS<xmove*xmove+zmove*zmove
 if can_step then
  local rise,blocked=self:clip(old,'y',self.stepheight)
  if not blocked and rise>=self.stepheight-EPS then
   local raised=copy(old);raised.y=raised.y+rise
   local candidate=horizontal(self,raised,xmove,zmove)
   local fall,hit=self:clip(candidate,'y',-(self.stepheight+.05))
   if hit then
    candidate.y=candidate.y+fall
    if distance2(old,candidate)>distance2(old,normal)+EPS then
     chosen=candidate
    end
   end
  end
 end
 -- Apply edge clamping only while supported. Falling, jumping and
 -- swimming must never snap onto an unsupported platform.
 if self.sneaking and self.sneak_edge_guard and self:supportAt(old) then
  chosen=self:sneakClamp(old,chosen)
 end
 self.pos=chosen
 if chosen~=normal then self.grounded=true end
 if self.on_ladder then
  self.velocity.y=input.jump and self.climb_speed*ov.speed_climb*speed_factor or
   (input.sneak and -self.climb_speed*ov.speed_climb*speed_factor or 0)
 elseif self.in_liquid then
  if input.jump or input.sneak then
   local target=input.jump and self.swim_speed or -self.swim_speed
   self.velocity.y=approach(self.velocity.y,target,
    self.water_acceleration*ov.liquid_fluidity,dt)
  else
   self.velocity.y=self.velocity.y-self.water_gravity*ov.gravity*dt
   self.velocity.y=self.velocity.y*max(0,1-self.water_drag*ov.liquid_fluidity_smooth*dt)
  end
  self.velocity.y=max(-self.swim_speed*ov.liquid_sink,
   min(self.swim_speed,self.velocity.y))
 else
  self.velocity.y=max(-self.terminal_velocity,
   self.velocity.y-self.gravity*ov.gravity*dt)
 end
 local vertical,collided=self:clip(self.pos,'y',self.velocity.y*dt)
 self.pos.y=self.pos.y+vertical
 if collided then
  if self.velocity.y<0 then self.grounded=true
  else self.grounded=false end
  self.velocity.y=0
 elseif self.velocity.y~=0 then
  self.grounded=false
 end
 -- Catch zero-velocity standing contact and stepped-floor contact.
 if self.velocity.y<=0 then
  local probe,hit=self:clip(self.pos,'y',-.045)
  if hit and probe>-.045+EPS then
   self.grounded=true
   self.velocity.y=0
  end
 end
 return self.pos
end
function Physics:update(dt,input)
 assert(finite(dt) and dt>=0 and dt<=1,'invalid frame delta')
 if dt==0 then return self.pos end
 -- Up to 20 bounded physics substeps/sec at 1.0s catch-up. Ordinary
 -- 60fps frames perform one substep; long frames cannot tunnel.
 local count=math.ceil(dt/.05)
 local step=dt/count
 for _=1,count do self:tick(step,input) end
 return self.pos
end
return Physics
