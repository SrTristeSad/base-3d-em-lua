-- Luanti LuaEntity/ObjectRef subset. The host owns the world and physics
-- remain deliberately limited: callbacks run, velocity/acceleration integrate,
-- but collisions, attachments and native serialization are not implemented.
local Entities={}
local floor,sqrt=math.floor,math.sqrt
local function finite(n)
 return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge
end
local function vec(p)
 assert(type(p)=='table' and finite(p.x) and finite(p.y) and finite(p.z),
  'entity vector must contain finite x, y, z')
 assert(math.abs(p.x)<=31000 and math.abs(p.y)<=31000 and
  math.abs(p.z)<=31000,'entity outside map boundary')
 return {x=p.x,y=p.y,z=p.z}
end
local function copy(value,seen)
 if type(value)~='table' then return value end
 seen=seen or {}
 assert(not seen[value],'cyclic entity properties unsupported')
 seen[value]=true
 local out={}
 for k,v in pairs(value) do out[k]=copy(v,seen) end
 seen[value]=nil
 return out
end
local function props(def)
 local value=copy(def.initial_properties or {})
 if value.collisionbox==nil then
  value.collisionbox={-.3,-.3,-.3,.3,.3,.3}
 end
 if value.selectionbox==nil then
  value.selectionbox=copy(value.collisionbox)
 end
 if value.pointable==nil then value.pointable=true end
 if value.hp_max==nil then value.hp_max=10 end
 assert(type(value.collisionbox)=='table' and
  type(value.selectionbox)=='table',
  'entity collision/selection boxes required')
 for _,box in ipairs({value.collisionbox,value.selectionbox}) do
  assert(#box==6,'entity box needs six coordinates')
  for i=1,6 do assert(finite(box[i]) and math.abs(box[i])<=5,
   'entity box coordinate outside supported range') end
  for i=1,3 do assert(box[i]<=box[i+3],'entity box bounds inverted') end
 end
 assert(finite(value.hp_max) and value.hp_max>=0,
  'entity hp_max must be nonnegative')
 return value
end
local function active(rt,obj)
 return not obj.removed and obj._runtime==rt
end
local function methods(rt,obj)
 function obj:get_id() return self.id end
 function obj:is_player() return false end
 function obj:get_luaentity()
  if not active(rt,self) then return nil end
  return self.luaentity
 end
 function obj:get_pos()
  if not active(rt,self) then return nil end
  return vec(self.pos)
 end
 function obj:set_pos(p)
  assert(active(rt,self),'entity is removed')
  self.pos=vec(p)
 end
 function obj:get_velocity()
  if not active(rt,self) then return nil end
  return vec(self.velocity)
 end
 function obj:set_velocity(p)
  assert(active(rt,self),'entity is removed')
  self.velocity=vec(p)
 end
 function obj:get_acceleration()
  if not active(rt,self) then return nil end
  return vec(self.acceleration)
 end
 function obj:set_acceleration(p)
  assert(active(rt,self),'entity is removed')
  self.acceleration=vec(p)
 end
 function obj:get_yaw()
  if not active(rt,self) then return nil end
  return self.yaw
 end
 function obj:set_yaw(yaw)
  assert(active(rt,self) and finite(yaw),'invalid entity yaw')
  self.yaw=yaw
 end
 function obj:get_rotation()
  if not active(rt,self) then return nil end
  return {x=0,y=self.yaw,z=0}
 end
 function obj:set_rotation(rotation)
  assert(active(rt,self),'entity is removed')
  assert(type(rotation)=='table' and finite(rotation.x) and
   finite(rotation.y) and finite(rotation.z),
   'entity rotation requires three angles')
  -- This subset implements yaw only; reject unsupported pitch/roll rather
  -- than pretending the rotation was applied.
  assert(rotation.x==0 and rotation.z==0,
   'entity pitch and roll unsupported')
  self.yaw=rotation.y
 end
 function obj:get_properties()
  if not active(rt,self) then return nil end
  return copy(self.properties)
 end
 function obj:set_properties(changes)
  assert(active(rt,self) and type(changes)=='table',
   'entity properties require active object and table')
  local merged=copy(self.properties)
  for k,v in pairs(changes) do merged[k]=copy(v) end
  self.properties=props({initial_properties=merged})
  self.hp=math.min(self.hp,self.properties.hp_max)
 end
 function obj:get_hp()
  if not active(rt,self) then return nil end
  return self.hp
 end
 function obj:set_hp(hp)
  assert(active(rt,self) and finite(hp),'invalid entity HP')
  self.hp=math.max(0,math.min(hp,self.properties.hp_max))
 end
 function obj:remove()
  if self.removed then return end
  self.removed=true
  for i,v in ipairs(rt.luaEntities) do
   if v==self then table.remove(rt.luaEntities,i);break end
  end
 end
end
function Entities.add(rt,pos,name,staticdata)
 assert(type(name)=='string','entity name must be a string')
 if staticdata==nil then staticdata='' end
 assert(type(staticdata)=='string','staticdata must be a string')
 local def=rt.registry.entities[name]
 if not def then return nil end
 rt.luaEntities=rt.luaEntities or {}
 local cap=rt.opts.max_lua_entities or 4096
 assert(type(cap)=='number' and cap>=0 and cap==floor(cap),
  'invalid Lua entity cap')
 if #rt.luaEntities>=cap then return nil end
 pos=vec(pos)
 rt.nextLuaEntityId=(rt.nextLuaEntityId or 0)+1
 local obj={id=rt.nextLuaEntityId,_runtime=rt,removed=false,
  pos=pos,velocity={x=0,y=0,z=0},acceleration={x=0,y=0,z=0},
  yaw=0,properties=props(def)}
 obj.hp=obj.properties.hp_max
 methods(rt,obj)
 local instance={name=name,object=obj}
 for k,v in pairs(def) do
  if k~='initial_properties' and k~='name' then instance[k]=copy(v) end
 end
 obj.luaentity=instance
 rt.luaEntities[#rt.luaEntities+1]=obj
 -- on_activate gets the actual object already in the active registry, as
 -- native mods often query self.object inside their activation callback.
 if type(instance.on_activate)=='function' then
  local ok,err=pcall(instance.on_activate,instance,staticdata,0)
  if not ok then obj:remove();error(err,0) end
 end
 return obj
end
function Entities.step(rt,dt)
 assert(finite(dt) and dt>=0,'invalid Lua entity timestep')
 -- Snapshot ensures entities created inside on_step are NOT stepped in
 -- the same frame, and removal does not skip adjacent entities.
 local snapshot={}
 for i,obj in ipairs(rt.luaEntities or {}) do snapshot[i]=obj end
 for _,obj in ipairs(snapshot) do
  if active(rt,obj) then
   local v,a=obj.velocity,obj.acceleration
   local nextpos={x=obj.pos.x+v.x*dt+.5*a.x*dt*dt,
    y=obj.pos.y+v.y*dt+.5*a.y*dt*dt,
    z=obj.pos.z+v.z*dt+.5*a.z*dt*dt}
   if math.abs(nextpos.x)<=31000 and
    math.abs(nextpos.y)<=31000 and math.abs(nextpos.z)<=31000 then
    obj.pos=nextpos
   else
    -- Halt at the edge instead of letting an overflow silently corrupt
    -- the entity's position or serialization.
    obj.velocity={x=0,y=0,z=0}
    obj.acceleration={x=0,y=0,z=0}
   end
   if active(rt,obj) and type(obj.luaentity.on_step)=='function' then
    obj.luaentity:on_step(dt,{
     touching_ground=false,collides=false,collisions={}})
   end
  end
 end
end
function Entities.get(rt)
 local out={}
 for _,obj in ipairs(rt.luaEntities or {}) do
  if active(rt,obj) then out[#out+1]=obj end
 end
 return out
end
function Entities.radius(rt,pos,radius)
 pos=vec(pos)
 assert(finite(radius) and radius>=0,'invalid object radius')
 local out={}
 for _,obj in ipairs(rt.luaEntities or {}) do
  if active(rt,obj) then
   local p=obj.pos
   local dx,dy,dz=p.x-pos.x,p.y-pos.y,p.z-pos.z
   if dx*dx+dy*dy+dz*dz<=radius*radius then
    out[#out+1]=obj
   end
  end
 end
 return out
end
function Entities.punch(rt,obj,puncher,interval,toolcaps,dir,damage)
 assert(active(rt,obj),'cannot punch absent Lua entity')
 local entity=obj.luaentity
 if type(entity.on_punch)=='function' then
  return entity:on_punch(puncher,interval or 1,toolcaps or {},
   dir or {x=0,y=0,z=0},damage or 0)
 end
end
function Entities.rightclick(rt,obj,clicker)
 assert(active(rt,obj),'cannot rightclick absent Lua entity')
 local entity=obj.luaentity
 if type(entity.on_rightclick)=='function' then
  return entity:on_rightclick(clicker)
 end
end
return Entities
