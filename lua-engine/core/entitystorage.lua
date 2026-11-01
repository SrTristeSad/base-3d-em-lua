-- Runtime object sidecar: data-only, versioned, limited, no load/eval.
-- Save beside LUAENGINE 1 map; includes registered LuaEntity state too.
local Serialization=require('core.serialization')
local Falling=require('core.falling')
local Stack=require('core.itemstack')
local LuaEntities=require('core.luaentities')
local M={}
local HEADER='LUAENGINE OBJECTS 1\n'
local MAX_BYTES=1024*1024
local MAX_OBJECTS=2000
local function finite(n)
 return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge
end
local function pos(v)
 assert(type(v)=='table' and finite(v.x) and finite(v.y) and finite(v.z)
  and math.abs(v.x)<=31000 and math.abs(v.y)<=31000 and
  math.abs(v.z)<=31000,'invalid object coordinates')
 return {x=v.x,y=v.y,z=v.z}
end
local function velocity(v)
 v=pos(v or {x=0,y=0,z=0})
 assert(math.abs(v.x)<=10000 and math.abs(v.y)<=10000 and
  math.abs(v.z)<=10000,'velocity out of range')
 return v
end
local function integer(n,low,high)
 return finite(n) and n==math.floor(n) and n>=low and n<=high
end
local function stack_record(v)
 assert(type(v)=='table' and type(v.name)=='string' and v.name~='' and
  integer(v.count,1,65535) and integer(v.wear,0,65535),
  'invalid persisted item stack')
 local fields=v.fields or {}
 assert(type(fields)=='table','invalid persisted item metadata')
 local clean={}
 for k,value in pairs(fields) do
  assert(type(k)=='string' and type(value)=='string',
   'invalid persisted item metadata field')
  clean[k]=value
 end
 return {name=v.name,count=v.count,wear=v.wear,fields=clean}
end
local function metadata(v)
 assert(type(v)=='table','invalid falling-node metadata')
 local fields=v.fields or {}
 local inventory=v.inventory or {}
 assert(type(fields)=='table' and type(inventory)=='table',
  'invalid falling-node fields/inventory')
 for k,value in pairs(fields) do
  assert(type(k)=='string' and type(value)=='string',
   'invalid node metadata field')
 end
 for name,entry in pairs(inventory) do
  assert(type(name)=='string' and type(entry)=='table' and
   integer(entry.size,0,65535) and
   integer(entry.width or 0,0,65535) and
   type(entry.stacks)=='table',
   'invalid node inventory')
  for index,vstack in pairs(entry.stacks) do
   assert(integer(index,1,entry.size),'invalid node inventory index')
   if vstack~=false then stack_record(vstack) end
  end
 end
 return v
end
local function timer(v)
 if v==nil then return nil end
 assert(type(v)=='table' and finite(v.timeout) and v.timeout>0
  and finite(v.elapsed) and v.elapsed>=0,'invalid falling-node timer')
 return {timeout=v.timeout,elapsed=v.elapsed}
end
function M.encode(rt)
 assert(type(rt)=='table' and type(rt.registry)=='table',
  'runtime required for entity storage')
 local data={drops={},falling={},lua_entities=LuaEntities.snapshot(rt)}
 for _,obj in ipairs(rt.droppedItems or {}) do
  if not obj.removed then
   data.drops[#data.drops+1]={
    pos=pos(obj.pos),velocity=velocity(obj.velocity),
    age=obj.age,stack=obj:get_item():to_table()
   }
  end
 end
 for _,obj in ipairs(rt.fallingNodes or {}) do
  data.falling[#data.falling+1]={
   pos=pos(obj.pos),velocity=obj.velocity,
   node={name=obj.node.name,param1=obj.node.param1,
    param2=obj.node.param2},meta=obj.meta,timer=obj.timer
  }
 end
 assert(#data.drops+#data.falling+#data.lua_entities<=MAX_OBJECTS,
  'too many saved entities')
 local result=HEADER..Serialization.serialize(data)
 assert(#result<=MAX_BYTES,'entity save too large')
 return result
end
local function parse(data,rt)
 assert(type(data)=='string' and #data<=MAX_BYTES and
  data:sub(1,#HEADER)==HEADER,'invalid entity save header or size')
 local value=Serialization.deserialize(data:sub(#HEADER+1))
 assert(type(value)=='table' and type(value.drops)=='table' and
  type(value.falling)=='table','malformed entity save')
 local entity_list=value.lua_entities
 if entity_list==nil then entity_list={} end -- Backward compatible v1 file
 assert(type(entity_list)=='table','invalid LuaEntity list')
 assert(#value.drops+#value.falling+#entity_list<=MAX_OBJECTS,
  'too many loaded entities')
 local drops,falling,entities={},{},{}
 for _,entry in ipairs(value.drops) do
  assert(type(entry)=='table' and finite(entry.age) and entry.age>=0,
   'invalid drop age')
  drops[#drops+1]={
   pos=pos(entry.pos),velocity=velocity(entry.velocity),
   age=entry.age,stack=stack_record(entry.stack)
  }
 end
 for _,entry in ipairs(value.falling) do
  assert(type(entry)=='table' and finite(entry.velocity),
   'invalid falling entity velocity')
  local n=entry.node
  assert(type(n)=='table' and type(n.name)=='string' and
   rt.registry.nodes[n.name] and
   integer(n.param1,0,255) and integer(n.param2,0,255),
   'unknown/invalid falling node')
  falling[#falling+1]={
   pos=pos(entry.pos),velocity=entry.velocity,
   node={name=n.name,param1=n.param1,param2=n.param2},
   meta=metadata(entry.meta),timer=timer(entry.timer)
  }
 end
 for _,entry in ipairs(entity_list) do
  assert(type(entry)=='table' and type(entry.name)=='string' and
   type(rt.registry.entities[entry.name])=='table',
   'unknown persisted LuaEntity definition')
  assert(type(entry.staticdata)=='string' and
   #entry.staticdata<=65536,'invalid LuaEntity staticdata')
  assert(finite(entry.yaw) and finite(entry.hp) and entry.hp>=0,
   'invalid LuaEntity orientation or HP')
  local properties=LuaEntities.validate_properties(entry.properties)
  assert(entry.hp<=properties.hp_max,'invalid LuaEntity HP range')
  entities[#entities+1]={
   name=entry.name,staticdata=entry.staticdata,
   pos=pos(entry.pos),velocity=velocity(entry.velocity),
   acceleration=velocity(entry.acceleration),
   yaw=entry.yaw,hp=entry.hp,properties=properties
  }
 end
 local maxactive=rt.opts.max_lua_entities or 4096
 assert(#entities<=maxactive,'LuaEntity limit exceeded')
 return drops,falling,entities
end
-- Validate complete snapshot before mutating the live runtime; failed loads
-- cannot partially overwrite the world's existing item entities.
function M.restore(rt,data)
 local drops,falling,entities=parse(data,rt)
 local previous_drops,previous_falling=rt.droppedItems,rt.fallingNodes
 local previous_entities,previous_next_id=rt.luaEntities,rt.nextLuaEntityId
 rt.droppedItems={}
 rt.fallingNodes={}
 rt.luaEntities={}
 local ok,err=pcall(function()
  for _,entry in ipairs(drops) do
   local obj=Falling.add_item(rt,entry.pos,Stack.new(entry.stack,rt.registry.items))
   assert(obj,'failed to recreate dropped stack')
   obj:set_velocity(entry.velocity)
   obj.age=entry.age
  end
  for _,entry in ipairs(falling) do
   rt.fallingNodes[#rt.fallingNodes+1]=entry
  end
  for _,entry in ipairs(entities) do
   -- on_activate may execute registered mod code. We keep all previously
   -- loaded world objects untouched until every activation succeeds.
   local obj=LuaEntities.add(rt,entry.pos,entry.name,entry.staticdata,entry)
   assert(obj and not obj.removed,'LuaEntity activation did not succeed')
  end
 end)
 if not ok then
  -- A callback might have spawned more objects during activation. Invalidate
  -- every staged ObjectRef, rather than leaving live refs in a discarded list.
  for _,obj in ipairs(rt.luaEntities) do obj.removed=true end
  rt.droppedItems,rt.fallingNodes=previous_drops,previous_falling
  rt.luaEntities,rt.nextLuaEntityId=previous_entities,previous_next_id
  error(err,0)
 end
 -- Old live ObjectRefs are invalid after replacement; notify mods that the
 -- objects were unloaded (removal=false), without firing removal callbacks.
 -- Runtime callbacks are not sandboxed: any side effects to the world map
 -- made in on_activate/on_deactivate cannot be rolled back by this sidecar.
 for _,obj in ipairs(previous_entities or {}) do
  if not obj.removed then
   obj.removed=true
   if type(obj.luaentity.on_deactivate)=='function' then
    local activated,problem=pcall(obj.luaentity.on_deactivate,
     obj.luaentity,false)
    if not activated then
     rt.logging[#rt.logging+1]={
      level='error',message='LuaEntity on_deactivate: '..tostring(problem)}
    end
   end
  end
 end
 return #drops,#falling,#entities
end
function M.save(rt,path,fs)
 assert(fs and type(fs.write)=='function','filesystem.write required')
 return fs.write(path,M.encode(rt))
end
function M.load(rt,path,fs)
 assert(fs and type(fs.read)=='function','filesystem.read required')
 local data=fs.read(path)
 if not data then return nil,'not found' end
 local ok,count,falling,entities=pcall(M.restore,rt,data)
 if not ok then return nil,count end
 return count,falling,entities
end
return M
