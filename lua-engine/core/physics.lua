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
 local acceleration=opts.acceleration==nil and 26 or opts.acceleration
 local braking=opts.braking==nil and 20 or opts.braking
 local air_acceleration=opts.air_acceleration==nil and 9 or opts.air_acceleration
 local water_acceleration=opts.water_acceleration==nil and 8 or opts.water_acceleration
 local water_braking=opts.water_braking==nil and 7 or opts.water_braking
 local water_gravity=opts.water_gravity==nil and 3 or opts.water_gravity
 local water_drag=opts.water_drag==nil and 3 or opts.water_drag
 local swim_speed=opts.swim_speed==nil and 3 or opts.swim_speed
 local climb_speed=opts.climb_speed==nil and 3 or opts.climb_speed
 assert(finite(radius) and radius>0 and radius<=.5)
 assert(finite(height) and height>0 and height<=3)
 assert(finite(stepheight) and stepheight>=0 and stepheight<=1)
 assert(finite(eyeheight) and eyeheight>0 and eyeheight<=height)
 for _,rate in ipairs({acceleration,braking,air_acceleration,
  water_acceleration,water_braking,water_gravity,water_drag,
  swim_speed,climb_speed}) do
  assert(valid_rate(rate),'invalid movement parameter')
 end
 return setmetatable({
  api=api,pos=copy(position),velocity={x=0,y=0,z=0},
  radius=radius,height=height,eyeheight=eyeheight,
  stepheight=stepheight,gravity=opts.gravity or 20,
  jump_speed=opts.jump_speed or 7.2,
  speed=opts.speed or 4.8,sprint_speed=opts.sprint_speed or 7.2,
  terminal_velocity=opts.terminal_velocity or 40,
  acceleration=acceleration,braking=braking,
  air_acceleration=air_acceleration,
  water_acceleration=water_acceleration,water_braking=water_braking,
  water_gravity=water_gravity,water_drag=water_drag,
  swim_speed=swim_speed,climb_speed=climb_speed,
  fluid_physics=opts.fluid_physics~=false,
  grounded=false,in_liquid=false,on_ladder=false
 },Physics)
end
function Physics:eye()
 return {x=self.pos.x,y=self.pos.y+self.eyeheight,z=self.pos.z}
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
function Physics:surface_friction()
 local p=self.pos
 local at={x=floor(p.x+.5),y=floor(p.y-.07+.5),
  z=floor(p.z+.5)}
 local node=self.api.get_node(at)
 local value=group(self.api.registered_nodes[node.name],'slippery')
 -- Higher group values mean reduced traction. Smoothly retain some grip.
 return value>0 and 1/(value+1) or 1
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
 local traction=self.grounded and self:surface_friction() or 1
 local speed=(input.sprint and self.sprint_speed or self.speed)
 if self.in_liquid then speed=speed*.48 end
 local rate
 if self.in_liquid then
  rate=(length>EPS and self.water_acceleration or self.water_braking)
 elseif self.grounded then
  rate=(length>EPS and self.acceleration or self.braking)*traction
 else
  rate=(length>EPS and self.air_acceleration or self.braking*.2)
 end
 self.velocity.x=approach(self.velocity.x,dx*speed,rate,dt)
 self.velocity.z=approach(self.velocity.z,dz*speed,rate,dt)
 local vx,vz=self.velocity.x,self.velocity.z
 local jumping=input.jump and self.grounded and
  not self.in_liquid and not self.on_ladder
 if jumping then
  self.velocity.y=self.jump_speed
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
 self.pos=chosen
 if chosen~=normal then self.grounded=true end
 if self.on_ladder then
  self.velocity.y=input.jump and self.climb_speed or
   (input.sneak and -self.climb_speed or 0)
 elseif self.in_liquid then
  if input.jump or input.sneak then
   local target=input.jump and self.swim_speed or -self.swim_speed
   self.velocity.y=approach(self.velocity.y,target,
    self.water_acceleration,dt)
  else
   self.velocity.y=self.velocity.y-self.water_gravity*dt
   self.velocity.y=self.velocity.y*max(0,1-self.water_drag*dt)
  end
  self.velocity.y=max(-self.swim_speed,min(self.swim_speed,
   self.velocity.y))
 else
  self.velocity.y=max(-self.terminal_velocity,
   self.velocity.y-self.gravity*dt)
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
