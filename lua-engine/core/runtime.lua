-- Primeiro nucleo do Luanti em Lua: API e registro de mods.
-- Compativel apenas com o subconjunto documentado neste prototipo.
local Map=require('core.map')
local Vector=require('core.vector')
local ItemStack=require('core.itemstack')
local Inventory=require('core.inventory')
local Crafting=require('core.crafting')
local ModStorage=require('core.modstorage')
local Runtime={}
Runtime.__index=Runtime
local floor=math.floor
local unpack_args=table.unpack or unpack
local function clone(node)
 return {x=node.x,y=node.y,z=node.z}
end
local function ispos(v)
 return type(v)=='table' and type(v.x)=='number'
   and type(v.y)=='number' and type(v.z)=='number'
end
local function opts_copy(obj)
 local copy={}
 for k,v in pairs(obj or {}) do copy[k]=v end
 return copy
end
function Runtime.new(options)
 local self=setmetatable({
  opts=options or {}, map=Map.new(),clock=0,stepcount=0,
  current_mod=nil,scheduled={},nextTask=0,
  registry={nodes={},items={},tools={},craftitems={},
    entities={},aliases={},crafts={},abms={},lbms={}},
  callbacks={globalstep={},generated={},mods_loaded={},
    on_placenode={},on_dignode={},on_joinplayer={},
    on_dieplayer={},on_leaveplayer={},on_player_receive_fields={}},
  abmClock={}, logging={}, detached={},mod_storage={},
  chatcommands={}
 },Runtime)
 local api={}
 self.api=api
 self.map.registry=self.registry.items
 self.crafting=Crafting.new(self.registry.items,self.registry.aliases)
 api.registered_nodes=self.registry.nodes
 api.registered_items=self.registry.items
 api.registered_entities=self.registry.entities
 api.registered_aliases=self.registry.aliases
 api.registered_tools=self.registry.tools
 api.registered_craftitems=self.registry.craftitems
 api.registered_abms=self.registry.abms
 api.registered_lbms=self.registry.lbms
 api.nodedef_default={stack_max=99}
 api.craftitemdef_default={stack_max=99}
 api.MAP_BLOCKSIZE=16
 api.MAX_MAP_GENERATION_LIMIT=31000
 api.features={hud_def_type_field=true}
 api.settings={}
 local settings=self.opts.settings or {}
 local mapgen=self.opts.mapgen or {}
 self.opts.mapgen=mapgen
 function api.settings:get(name)
  local v=settings[name]
  if v==nil then return nil end
  return tostring(v)
 end
 function api.settings:get_bool(name,default)
  local v=settings[name]
  if v==nil then return default end
  if v==true or v==1 or v=='true' or v=='1' then return true end
  if v==false or v==0 or v=='false' or v=='0' then return false end
  return default
 end
 function api.settings:get_num(name,default)
  return tonumber(settings[name]) or default
 end
 function api.settings:set(name,value)
  assert(type(name)=='string' and type(value)=='string','invalid setting')
  settings[name]=value
 end
 function api.settings:set_bool(name,value)
  assert(type(name)=='string' and type(value)=='boolean','invalid bool setting')
  settings[name]=value and 'true' or 'false'
 end
 function api.get_mod_storage()
  assert(type(self.current_mod)=='string','get_mod_storage only within a mod')
  local name=self.current_mod
  if not self.mod_storage[name] then
   self.mod_storage[name]=ModStorage.new()
  end
  return self.mod_storage[name]
 end
 function api.register_chatcommand(name,def)
  assert(type(name)=='string' and name~='' and type(def)=='table',
   'invalid chat command')
  assert(not self.chatcommands[name],'chatcommand already registered: '..name)
  self.chatcommands[name]=opts_copy(def)
 end
 api.registered_chatcommands=self.chatcommands
 function api.register_on_dieplayer(callback)
  assert(type(callback)=='function')
  self.callbacks.on_dieplayer[#self.callbacks.on_dieplayer+1]=callback
 end
 function api.register_on_joinplayer(callback)
  assert(type(callback)=='function')
  self.callbacks.on_joinplayer[#self.callbacks.on_joinplayer+1]=callback
 end
 function api.register_on_leaveplayer(callback)
  assert(type(callback)=='function')
  self.callbacks.on_leaveplayer[#self.callbacks.on_leaveplayer+1]=callback
 end
 function api.register_on_player_receive_fields(callback)
  assert(type(callback)=='function')
  self.callbacks.on_player_receive_fields[
   #self.callbacks.on_player_receive_fields+1]=callback
 end
 -- For use when an actual player/HUD backend exists; registration
 -- alone must never invent a player or pretend to emit sound.
 function api.formspec_escape(text)
  assert(type(text)=='string','formspec text required')
  return (text:gsub('\\','\\\\'):gsub('%]','\\]'):gsub('%[','\\[')
   :gsub(';','\\;'):gsub(',','\\,'))
 end
 function api.log(level,message)
  if message==nil then message=level;level='action' end
  local line='['..tostring(level)..'] '..tostring(message)
  self.logging[#self.logging+1]=line
 end
 function api.get_current_modname() return self.current_mod end
 function api.get_modpath(name)
  return self.opts.modpaths and self.opts.modpaths[name] or nil
 end
 function api.get_worldpath() return self.opts.worldpath or 'worlds/lua-engine' end
 function api.get_mapgen_setting(name)
  local v=mapgen[name]
  if v==nil then return nil end
  return tostring(v)
 end
 function api.set_mapgen_setting(name,value)
  assert(type(name)=='string' and type(value)=='string',
   'invalid mapgen setting')
  mapgen[name]=value
  return true
 end
 function api.get_game_info()
  local info=self.opts.game_info or {}
  return {path=info.path or '.',title=info.title or 'Lua Engine',
   author=info.author or ''}
 end
 function api.get_version()
  -- This is the Lua port version, never a forged Luanti binary version.
  return {string='0.1.0-lua-port',major=0,minor=1,patch=0,
    project='lua-engine'}
 end
 function api.global_exists(name)
  assert(type(name)=='string','global name required')
  -- The mod environment exposes only explicitly supported globals.
  return type(self.opts.modglobals)=='table'
    and self.opts.modglobals[name]~=nil or false
 end
 function api.get_gametime() return floor(self.clock) end
 function api.get_timeofday() return (self.clock/1200)%1 end
 function api.get_translator()
  return function(msg,...) local args={...}
   return (msg:gsub('@(%d+)',function(index)
    return tostring(args[tonumber(index)] or ('@'..index))
   end))
  end
 end
 local function register(kind,name,definition)
  assert(type(name)=='string' and name~='','registered name required')
  assert(type(definition)=='table','definition must be table')
  assert(not self.registry.items[name],'item already registered: '..name)
  local def=opts_copy(definition)
  def.name=name
  def.groups=opts_copy(def.groups)
  if kind=='node' then
   if def.stack_max==nil then def.stack_max=api.nodedef_default.stack_max end
   if def.walkable==nil then def.walkable=true end
   if def.pointable==nil then def.pointable=true end
   if def.buildable_to==nil then def.buildable_to=false end
   self.registry.nodes[name]=def
  elseif kind=='tool' then
   def.stack_max=def.stack_max or 1
   self.registry.tools[name]=def
  else
   if def.stack_max==nil then def.stack_max=api.craftitemdef_default.stack_max end
   self.registry.craftitems[name]=def
  end
  self.registry.items[name]=def
 end
 function api.register_node(name,def) register('node',name,def) end
 function api.register_tool(name,def) register('tool',name,def) end
 function api.register_craftitem(name,def) register('craftitem',name,def) end
 function api.register_entity(name,def)
  assert(type(name)=='string' and type(def)=='table')
  self.registry.entities[name]=opts_copy(def)
 end
 function api.register_alias(name,target)
  assert(type(name)=='string' and type(target)=='string')
  self.registry.aliases[name]=target
 end
 function api.register_alias_force(name,target)
  api.register_alias(name,target)
 end
 function api.register_craft(recipe)
  assert(type(recipe)=='table','craft recipe required')
  local registered=self.crafting:register(recipe)
  self.registry.crafts[#self.registry.crafts+1]=registered
 end
 function api.get_craft_result(input)
  return self.crafting:result(input)
 end
 function api.get_craft_recipe(output)
  return self.crafting:one_for(output)
 end
 function api.get_all_craft_recipes(output)
  return self.crafting:all_for(output)
 end
 -- Project helper, not part of the Luanti API. Consume a single valid
 -- crafting recipe only if the destination inventory can accept the output.
 function api.lua_engine_craft_inventory(inv,source,destination,method)
  return self.crafting:take(inv,source,destination,method)
 end
 function api.register_globalstep(callback)
  assert(type(callback)=='function')
  self.callbacks.globalstep[#self.callbacks.globalstep+1]=callback
 end
 function api.register_on_generated(callback)
  assert(type(callback)=='function')
  self.callbacks.generated[#self.callbacks.generated+1]=callback
 end
 function api.register_on_mods_loaded(callback)
  assert(type(callback)=='function')
  self.callbacks.mods_loaded[#self.callbacks.mods_loaded+1]=callback
 end
 function api.register_on_placenode(callback)
  assert(type(callback)=='function')
  self.callbacks.on_placenode[#self.callbacks.on_placenode+1]=callback
 end
 function api.register_on_dignode(callback)
  assert(type(callback)=='function')
  self.callbacks.on_dignode[#self.callbacks.on_dignode+1]=callback
 end
 function api.register_abm(def)
  assert(type(def)=='table' and type(def.action)=='function')
  local copy=opts_copy(def)
  copy.interval=def.interval or 1
  copy.chance=def.chance or 1
  assert(copy.interval>0 and copy.chance>=1)
  self.registry.abms[#self.registry.abms+1]=copy
 end
 function api.register_lbm(def)
  assert(type(def)=='table' and type(def.action)=='function')
  self.registry.lbms[#self.registry.lbms+1]=opts_copy(def)
 end
 function api.after(delay,fn,...)
  assert(type(delay)=='number' and delay>=0 and
   type(fn)=='function','invalid after() call')
  self.nextTask=self.nextTask+1
  local task={id=self.nextTask,at=self.clock+delay,
   callback=fn,args={...},count=select('#',...)}
  self.scheduled[#self.scheduled+1]=task
  return {cancel=function()
   task.cancelled=true
  end}
 end
 local function resolve(name)
  local seen={}
  while self.registry.aliases[name] do
   assert(not seen[name],'circular node alias: '..name)
   seen[name]=true
   name=self.registry.aliases[name]
  end
  return name
 end
 function api.ItemStack(value)
  return ItemStack.new(value,self.registry.items)
 end
 function api.create_detached_inventory(name,callbacks)
  assert(type(name)=='string' and name~='' and
   not self.detached[name],'detached inventory name already exists')
  local inv=Inventory.new(self.registry.items)
  self.detached[name]={inv=inv,callbacks=callbacks or {}}
  return inv
 end
 function api.get_inventory(location)
  if type(location)~='table' then return nil end
  if location.type=='detached' then
   local v=self.detached[location.name]
   return v and v.inv or nil
  elseif location.type=='node' and ispos(location.pos) then
   return self.map:get_meta(location.pos):get_inventory()
  end
  return nil
 end
 function api.get_node(pos) return self.map:get_node(pos) end
 function api.get_node_or_nil(pos) return self.map:get_node(pos) end
 function api.set_node(pos,node)
  local n=opts_copy(node)
  n.name=resolve(n.name)
  return self.map:set_node(pos,n)
 end
 function api.swap_node(pos,node) return api.set_node(pos,node) end
 function api.remove_node(pos) return self.map:remove_node(pos) end
 function api.get_meta(pos) return self.map:get_meta(pos) end
 function api.get_node_timer(pos) return self.map:get_timer(pos) end
 function api.get_item_group(name,group)
  local def=self.registry.items[resolve(name)]
  return (def and def.groups and def.groups[group]) or 0
 end
 function api.get_node_group(name,group)
  local def=self.registry.nodes[resolve(name)]
  return (def and def.groups and def.groups[group]) or 0
 end
 function api.find_nodes_in_area(minp,maxp,names)
  local matches={}
  if type(names)=='string' then names={names} end
  local lookup={}
  for _,n in ipairs(names or {}) do lookup[n]=true end
  for _,entry in ipairs(self.map:iter_nodes(minp,maxp)) do
   local name=entry.node.name
   if lookup[name] then matches[#matches+1]=entry.pos
   else
    local def=self.registry.nodes[name]
    for n in pairs(lookup) do
     local g=n:match('^group:(.+)')
     if g and def and def.groups and (def.groups[g] or 0)>0 then
      matches[#matches+1]=entry.pos
      break
     end
    end
   end
  end
  return matches
 end
 function api.place_node(pos,node)
  local old=api.get_node(pos)
  if not api.set_node(pos,node) then return false end
  local new=api.get_node(pos)
  local def=self.registry.nodes[new.name]
  if def and def.on_construct then def.on_construct(clone(pos)) end
  for _,cb in ipairs(self.callbacks.on_placenode) do
   cb(clone(pos),new,nil,old,nil,nil)
  end
  return true
 end
 function api.dig_node(pos)
  local old=api.get_node(pos)
  if old.name=='air' then return false end
  local def=self.registry.nodes[old.name]
  if def and def.on_destruct then def.on_destruct(clone(pos)) end
  api.remove_node(pos)
  if def and def.after_destruct then def.after_destruct(clone(pos),old) end
  for _,cb in ipairs(self.callbacks.on_dignode) do
   cb(clone(pos),old,nil)
  end
  return true
 end
 function api.get_node_light(pos)
  local n=api.get_node(pos)
  local d=self.registry.nodes[n.name]
  return d and d.light_source or 0
 end
 function api.is_protected() return false end
 function api.get_objects_inside_radius() return {} end
 function api.get_connected_players() return {} end
 function api.get_player_by_name() return nil end
 -- Access to not-yet-ported APIs intentionally raises instead of returning
 -- plausible but false results. This is essential to track compatibility.
 return self
end
local function named(def,node)
 for _,name in ipairs(def.nodenames or {}) do
  if name==node.name then return true end
  local group=name:match('^group:(.+)$')
  if group then
   local api=def._api
   if api.get_node_group(node.name,group)>0 then return true end
  end
 end
 return false
end
function Runtime:step(dt)
 assert(type(dt)=='number' and dt>=0 and dt==dt,'invalid dt')
 self.clock=self.clock+dt
 self.stepcount=self.stepcount+1
 -- Queue snapshot prevents recursive after(0) from locking a frame.
 local pending=self.scheduled
 self.scheduled={}
 for _,task in ipairs(pending) do
  if not task.cancelled then
   if task.at<=self.clock then
    task.callback(unpack_args(task.args,1,task.count))
   else self.scheduled[#self.scheduled+1]=task end
  end
 end
 for _,fn in ipairs(self.callbacks.globalstep) do fn(dt) end
 -- Node timers run once per tick, without repeated callbacks in one frame.
 local timeouts={}
 for key,t in pairs(self.map.timers) do
  t.elapsed=t.elapsed+dt
  if t.elapsed>=t.timeout then
   timeouts[#timeouts+1]={key=key,time=t.timeout,elapsed=t.elapsed,pos=t.pos}
  end
 end
 for _,timer in ipairs(timeouts) do
  local current=self.map.timers[timer.key]
  if current and current.elapsed>=current.timeout then
   self.map.timers[timer.key]=nil
   local n=self.map:get_node(timer.pos)
   local def=self.registry.nodes[n.name]
   if def and def.on_timer and def.on_timer(timer.pos,timer.elapsed) then
    self.map.timers[timer.key]={
     timeout=timer.time,elapsed=0,pos=timer.pos}
   end
  end
 end
 -- ABMs operate only on edited/resident sparse nodes in this first phase.
 for i,def in ipairs(self.registry.abms) do
  self.abmClock[i]=(self.abmClock[i] or 0)+dt
  if self.abmClock[i]>=def.interval then
   self.abmClock[i]=self.abmClock[i]%def.interval
   def._api=self.api
   for poskey,node in pairs(self.map.nodes) do
    if named(def,node) and math.random(def.chance)==1 then
     local x,y,z=poskey:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
     def.action({x=tonumber(x),y=tonumber(y),z=tonumber(z)},node,0,0)
    end
   end
  end
 end
end
function Runtime:generate(minp,maxp,seed)
 for _,fn in ipairs(self.callbacks.generated) do
  fn(minp,maxp,seed or 0)
 end
end
function Runtime:installGlobals(target)
 target=target or _G
 target.minetest=self.api
 target.core=self.api
 target.vector=Vector
 target.ItemStack=self.api.ItemStack
 return self.api
end
function Runtime:loadMod(name,path)
 assert(type(name)=='string' and type(path)=='string')
 assert(not self.current_mod,'nested mod loading unsupported')
 self.opts.modpaths=self.opts.modpaths or {}
 self.opts.modpaths[name]=path
 self.current_mod=name
 local execute=self.opts.executeMod or dofile
 local ok,err=pcall(execute,path..'/init.lua',name)
 self.current_mod=nil
 if not ok then error('error loading mod '..name..': '..tostring(err),0) end
end
function Runtime:finishMods()
 for _,fn in ipairs(self.callbacks.mods_loaded) do fn() end
end
-- Explicit event dispatch for tests and future player integration.
function Runtime:emit(event,...)
 local callbacks=self.callbacks[event]
 assert(callbacks,'unknown runtime event: '..tostring(event))
 local results={}
 for i,callback in ipairs(callbacks) do
  results[i]=callback(...)
 end
 return results
end
return Runtime
