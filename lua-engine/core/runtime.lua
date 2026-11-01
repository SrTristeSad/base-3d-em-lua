-- Primeiro nucleo do Luanti em Lua: API e registro de mods.
-- Compativel apenas com o subconjunto documentado neste prototipo.
local Map=require('core.map')
local Vector=require('core.vector')
local ItemStack=require('core.itemstack')
local Inventory=require('core.inventory')
local Crafting=require('core.crafting')
local ModStorage=require('core.modstorage')
local Voxel=require('core.voxel')
local Particles=require('core.particles')
local NodeDrops=require('core.nodedrops')
local Digging=require('core.digging')
local Placement=require('core.placement')
local Falling=require('core.falling')
local Raycast=require('core.raycast')
local LuaEntities=require('core.luaentities')
local EntityPhysics=require('core.entityphysics')
local CollisionGeometry=require('core.collisiongeometry')
local Attached=require('core.attached')
local PlayerPhysics=require('core.playerphysics')
local Serialization=require('core.serialization')
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
    entities={},aliases={},crafts={},abms={},lbms={},
    biomes={},ores={},decorations={}},
  fallingNodes={},droppedItems={},luaEntities={},nextLuaEntityId=0,
  callbacks={globalstep={},generated={},mods_loaded={},shutdown={},
    on_placenode={},on_dignode={},on_punchnode={},on_punchplayer={},on_joinplayer={},
    on_dieplayer={},on_leaveplayer={},on_player_receive_fields={},
    on_craft={},craft_predict={},on_item_eat={},on_item_pickup={},liquid_transformed={},
    allow_player_inventory_action={},on_player_inventory_action={}},
  abmClock={}, logging={}, detached={},mod_storage={},
  chatcommands={},privileges={},players={},playerPhysicsBindings={},playerPhysicsControllers={},particles=Particles.new()
 },Runtime)
 local api={}
 self.api=api
 api.serialize=Serialization.serialize
 api.deserialize=Serialization.deserialize
 self.map.registry=self.registry.items
 self.crafting=Crafting.new(self.registry.items,self.registry.aliases)
 self.content=Voxel.ContentIDs.new()
 api.registered_nodes=self.registry.nodes
 api.registered_items=self.registry.items
 api.registered_entities=self.registry.entities
 api.registered_aliases=self.registry.aliases
 api.registered_tools=self.registry.tools
 api.registered_craftitems=self.registry.craftitems
 api.registered_abms=self.registry.abms
 api.registered_lbms=self.registry.lbms
 api.registered_biomes=self.registry.biomes
 api.registered_ores=self.registry.ores
 api.registered_decorations=self.registry.decorations
 -- Engine-owned definitions exist before gameplay mods load.  Content IDs
 -- 0 (air) and 127 (ignore) are reserved by Voxel.ContentIDs.
 local air={name='air',description='Air',drawtype='airlike',
  pointable=false,walkable=false,buildable_to=true,diggable=false,groups={}}
 local ignore={name='ignore',description='Ignore',drawtype='airlike',
  pointable=false,walkable=false,buildable_to=false,diggable=false,groups={}}
 self.registry.nodes.air=air
 self.registry.nodes.ignore=ignore
 self.registry.items.air=air
 self.registry.items.ignore=ignore
 self.registry.items['']={name='',description='',type='none',
  range=4,groups={}}
 api.CONTENT_AIR=0
 api.CONTENT_IGNORE=127
 local biomeIds,biomeNames,nextBiomeId={}, {},1
 function api.get_content_id(name)
  assert(type(name)=='string','content name must be string')
  local visited={}
  while self.registry.aliases[name] and not visited[name] do
   visited[name]=true
   name=self.registry.aliases[name]
  end
  return self.content:get_id(name)
 end
 function api.get_name_from_content_id(id)
  return self.content:get_name(id)
 end
 function api.get_voxel_manip(minp,maxp)
  assert(minp and maxp,
   'this Lua prototype requires explicit VoxelManip bounds')
  local manip=Voxel.VoxelManip.new(self.map,self.content)
  local a,b=manip:read_from_map(minp,maxp)
  return manip,a,b
 end
 function api.register_biome(def)
  assert(type(def)=='table' and type(def.name)=='string' and def.name~='',
   'biome must be named')
  assert(not biomeIds[def.name],'biome already registered')
  local id=nextBiomeId
  nextBiomeId=id+1
  biomeIds[def.name]=id
  biomeNames[id]=def.name
  self.registry.biomes[def.name]=opts_copy(def)
  return id
 end
 function api.get_biome_id(name) return biomeIds[name] end
 function api.get_biome_name(id) return biomeNames[id] end
 function api.register_ore(def)
  assert(type(def)=='table' and type(def.ore)=='string',
   'ore registration requires ore node')
  self.registry.ores[#self.registry.ores+1]=opts_copy(def)
 end
 function api.register_decoration(def)
  assert(type(def)=='table' and type(def.deco_type)=='string',
   'decoration type required')
  self.registry.decorations[#self.registry.decorations+1]=opts_copy(def)
 end
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
 function api.get_connected_players()
  local names={}
  for name in pairs(self.players) do names[#names+1]=name end
  table.sort(names)
  local players={}
  for _,name in ipairs(names) do players[#players+1]=self.players[name] end
  return players
 end
 function api.get_player_by_name(name)
  return self.players[name]
 end
 function api.register_chatcommand(name,def)
  assert(type(name)=='string' and name~='' and type(def)=='table',
   'invalid chat command')
  assert(not self.chatcommands[name],'chatcommand already registered: '..name)
  self.chatcommands[name]=opts_copy(def)
 end
 api.registered_chatcommands=self.chatcommands
 api.registered_privileges=self.privileges
 function api.register_privilege(name,def)
  assert(type(name)=='string' and name~='' and type(def)=='table',
   'invalid privilege registration')
  assert(not self.privileges[name],'privilege already registered: '..name)
  self.privileges[name]=opts_copy(def)
 end
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
 function api.register_allow_player_inventory_action(callback)
  assert(type(callback)=='function')
  local t=self.callbacks.allow_player_inventory_action
  t[#t+1]=callback
 end
 function api.register_on_player_inventory_action(callback)
  assert(type(callback)=='function')
  local t=self.callbacks.on_player_inventory_action
  t[#t+1]=callback
 end
 -- Storage registration can be exercised by mods even though no player
 -- renderer, HUD, or formspec backend exists in this port.
 function api.show_formspec()
  error('formspec renderer and player sessions are not implemented',2)
 end
 function api.colorize(color,message)
  assert(type(color)=='string' and type(message)=='string',
   'colorize expects color and message strings')
  local esc=string.char(27)
  return esc..'(c@'..color..')'..message..esc..'(E)'
 end
 function api.hash_node_position(pos)
  return Particles.hash_node_position(pos)
 end
 function api.get_position_from_hash(hash)
  return Particles.get_position_from_hash(hash)
 end
 function api.add_particlespawner(def)
  return self.particles:add_spawner(def)
 end
 function api.delete_particlespawner(id)
  return self.particles:delete_spawner(id)
 end
 function api.add_particle(def)
  return self.particles:add_particle(def)
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
  -- Luanti treats a leading colon as an explicit name prefix override,
  -- not as part of the registered item identifier.
  if name:sub(1,1)==':' then name=name:sub(2) end
  assert(name~='','registered item cannot have an empty identifier')
  assert(type(definition)=='table','definition must be table')
  assert(not self.registry.items[name],'item already registered: '..name)
  local def=opts_copy(definition)
  def.name=name
  def.type=kind
  def.groups=opts_copy(def.groups)
  if kind=='node' then
   if def.stack_max==nil then def.stack_max=api.nodedef_default.stack_max end
   if def.walkable==nil then def.walkable=true end
   if def.pointable==nil then def.pointable=true end
   if def.buildable_to==nil then def.buildable_to=false end
   self.registry.nodes[name]=def
   self.content:register(name)
  elseif kind=='tool' then
   def.stack_max=def.stack_max or 1
   self.registry.tools[name]=def
  else
   if def.stack_max==nil then def.stack_max=api.craftitemdef_default.stack_max end
   self.registry.craftitems[name]=def
  end
  self.registry.items[name]=def
 end
 function api.override_item(name,overrides)
  assert(type(name)=='string' and type(overrides)=='table',
   'override_item requires an item name and override table')
  local def=self.registry.items[name]
  assert(def,'cannot override unknown item: '..name)
  for key,value in pairs(overrides) do
   if key~='name' then def[key]=value end
  end
  CollisionGeometry.invalidate(self)
 end
 function api.register_node(name,def)
  register('node',name,def)
  CollisionGeometry.invalidate(self)
 end
 function api.register_tool(name,def) register('tool',name,def) end
 function api.register_craftitem(name,def) register('craftitem',name,def) end
 function api.register_entity(name,def)
  assert(type(name)=='string' and name~='' and type(def)=='table',
   'register_entity requires nonempty name and definition')
  self.registry.entities[name]=opts_copy(def)
 end
 function api.add_entity(pos,name,staticdata)
  return LuaEntities.add(self,pos,name,staticdata)
 end
 function api.get_active_lua_entities()
  return LuaEntities.get(self)
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
 function api.register_on_shutdown(callback)
  assert(type(callback)=='function','shutdown callback must be a function')
  self.callbacks.shutdown[#self.callbacks.shutdown+1]=callback
 end
 function api.register_on_mods_loaded(callback)
  assert(type(callback)=='function')
  self.callbacks.mods_loaded[#self.callbacks.mods_loaded+1]=callback
 end
 function api.register_on_placenode(callback)
  assert(type(callback)=='function')
  self.callbacks.on_placenode[#self.callbacks.on_placenode+1]=callback
 end
 function api.register_craft_predict(callback)
  assert(type(callback)=='function','craft prediction callback must be callable')
  local callbacks=self.callbacks.craft_predict
  callbacks[#callbacks+1]=callback
 end
 function api.register_on_craft(callback)
  assert(type(callback)=='function','craft callback must be callable')
  local callbacks=self.callbacks.on_craft
  callbacks[#callbacks+1]=callback
 end
 -- Headless subset of Luanti's builtin item-eating lifecycle.
 -- Callback cancellation, item consumption, HP changes and replacements that
 -- fit a stack or inventory are supported. Audible eat sounds and dropped
 -- entity overflow remain unsupported until their respective systems exist.
 function api.do_item_eat(hp_change,replace_with_item,itemstack,user,pointed_thing)
  assert(type(hp_change)=='number','item_eat requires numeric HP change')
  assert(type(itemstack)=='table' and type(itemstack.take_item)=='function',
   'item_eat requires an ItemStack')
  assert(type(user)=='table' and type(user.get_hp)=='function'
   and type(user.set_hp)=='function','item_eat requires a player HP API')
  for _,callback in ipairs(self.callbacks.on_item_eat) do
   local result=callback(hp_change,replace_with_item,itemstack,user,pointed_thing)
   if result then return result end
  end
  if itemstack:is_empty() then return itemstack end
  local preview=itemstack:copy()
  preview:take_item(1)
  local overflow=preview:add_item(replace_with_item or '')
  local inventory
  if not overflow:is_empty() then
   inventory=type(user.get_inventory)=='function' and user:get_inventory() or nil
   assert(inventory and inventory:room_for_item('main',overflow),
    'item entity overflow is not yet implemented')
  end
  itemstack:take_item(1)
  local leftover=itemstack:add_item(replace_with_item or '')
  if not leftover:is_empty() then
   local still=inventory:add_item('main',leftover)
   assert(still:is_empty(),'inventory changed during item_eat')
  end
  user:set_hp(user:get_hp()+hp_change,
   {type='set_hp',custom_type='__builtin:item_eat'})
  return nil
 end
 function api.item_eat(hp_change,replace_with_item)
  assert(type(hp_change)=='number','item_eat HP must be numeric')
  return function(itemstack,user,pointed_thing)
   if user then
    return api.do_item_eat(hp_change,replace_with_item,
     itemstack,user,pointed_thing)
   end
  end
 end
 function api.register_on_liquid_transformed(callback)
  assert(type(callback)=='function',
   'liquid transformation callback must be callable')
  local callbacks=self.callbacks.liquid_transformed
  callbacks[#callbacks+1]=callback
 end
 function api.register_on_item_eat(callback)
  assert(type(callback)=='function','eat callback must be callable')
  local callbacks=self.callbacks.on_item_eat
  callbacks[#callbacks+1]=callback
 end
 -- Matches core.item_pickup's callback-first return convention:
 -- return a leftover ItemStack to intercept; nil delegates.
 function api.register_on_item_pickup(callback)
  assert(type(callback)=='function','item pickup callback must be callable')
  local callbacks=self.callbacks.on_item_pickup
  callbacks[#callbacks+1]=callback
 end
 api.registered_on_item_pickups=self.callbacks.on_item_pickup
 function api.item_pickup(itemstack,picker,pointed_thing)
  return Falling.item_pickup(self,itemstack,picker,pointed_thing)
 end
 function api.register_on_punchplayer(callback)
  assert(type(callback)=='function',
   'punch player callback must be callable')
  local list=self.callbacks.on_punchplayer
  list[#list+1]=callback
 end
 function api.register_on_punchnode(callback)
  assert(type(callback)=='function','punch callback must be callable')
  local callbacks=self.callbacks.on_punchnode
  callbacks[#callbacks+1]=callback
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
  local inv=Inventory.new(self.registry.items,{type='detached',name=name})
  self.detached[name]={inv=inv,callbacks=callbacks or {}}
  return inv
 end
 function api.get_inventory(location)
  if type(location)~='table' then return nil end
  if location.type=='detached' then
   local v=self.detached[location.name]
   return v and v.inv or nil
  elseif location.type=='player' and type(location.name)=='string' then
   local player=self.players[location.name]
   if player and type(player.get_inventory)=='function' then
    return player:get_inventory()
   end
   return nil
  elseif location.type=='node' and ispos(location.pos) then
   return self.map:get_meta(location.pos):get_inventory()
  end
  return nil
 end
 function api.get_node(pos) return self.map:get_node(pos) end
 function api.get_node_boxes(box_type,pos,node)
  assert(type(pos)=='table' and
   type(pos.x)=='number' and type(pos.y)=='number' and
   type(pos.z)=='number','get_node_boxes requires a valid position')
  node=node or self.map:get_node(pos)
  assert(type(node)=='table' and type(node.name)=='string',
   'get_node_boxes requires a node')
  local definition=self.registry.nodes[node.name]
  if not definition then return {} end
  return require('core.nodebox').boxes(definition,node,self.map,pos,
   self.registry.nodes,box_type)
 end

 -- Internal immutable collision entries; public get_node_boxes remains
 -- uncached so mods cannot mutate the physics cache by editing its result.
 function api._node_collision_entries(swept,pad,exclude_buildable)
  return CollisionGeometry.collect(self,swept,pad,exclude_buildable)
 end
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
 -- Match Luanti's core.get_dig_params(groups, toolcaps, initial_wear).
 function api.get_dig_params(groups,tool_capabilities,initial_wear)
  return Digging.get_params(groups,tool_capabilities,initial_wear)
 end
 -- Small supported subset of Luanti node drops. No fortune/silk-touch or
 -- automatic item entities: the caller must consume returned item strings.
 function api.get_node_drops(name,tool,rng)
  assert(type(name)=='string','node name required')
  return NodeDrops.evaluate(self.registry.nodes,resolve(name),tool,rng)
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
  api.check_for_falling(pos)
  return true
 end
 function api.dig_node(pos)
  local old=api.get_node(pos)
  if old.name=='air' then return false end
  local def=self.registry.nodes[old.name]
  if def and def.on_destruct then def.on_destruct(clone(pos)) end
  api.remove_node(pos)
  api.get_meta(pos):from_table({fields={},inventory={}})
  api.get_node_timer(pos):stop()
  if def and def.after_destruct then def.after_destruct(clone(pos),old) end
  for _,cb in ipairs(self.callbacks.on_dignode) do
   cb(clone(pos),old,nil)
  end
  api.check_for_falling(pos)
  return true
 end
 -- Minimal builtin callback helpers for custom mods using
 -- on_dig=core.node_dig or calling core.item_place_node.
 -- Only real connected host players are supported in this port.
 function api.node_dig(pos,node,digger)
  if not digger then return false end
  return require('core.playeractions').dig(self,digger,pos,true)
 end
 function api.item_place_node(itemstack,placer,pointed_thing,param2,prevent_after_place)
  if not placer then return api.ItemStack(itemstack),nil end
  return require('core.playeractions').default_place(self,
   itemstack,placer,pointed_thing,param2,prevent_after_place)
 end
 function api.item_place(itemstack,placer,pointed_thing,param2)
  return require('core.playeractions').item_place(
   self,itemstack,placer,pointed_thing,param2)
 end
 api.dir_to_wallmounted=Placement.dir_to_wallmounted
 api.dir_to_facedir=Placement.dir_to_facedir
 api.dir_to_fourdir=Placement.dir_to_fourdir
 -- Luanti builtin falling.lua subset: explicit checks are mod-accessible,
 -- while placement/dig/punch callbacks trigger neighbor propagation.
 function api.spawn_falling_node(pos) return Falling.spawn(self,pos) end
 function api.check_single_for_falling(pos)
  return Falling.check_single(self,pos)
 end
 function api.check_for_falling(pos) return Falling.check(self,pos) end
 function api.add_item(pos,itemstack)
  return Falling.add_item(self,pos,itemstack)
 end
 function api.get_falling_nodes() return Falling.get_falling_nodes(self) end
 function api.get_dropped_items() return Falling.get_dropped_items(self) end
 api.wallmounted_to_dir=Attached.wallmounted_to_dir
 api.facedir_to_dir=Attached.facedir_to_dir
 api.fourdir_to_dir=Attached.fourdir_to_dir
 -- A host may supply a dynamic creative-mode predicate or a global flag.
 -- The native API exists for mods even when creative mode is disabled.
 function api.is_creative_enabled(player_name)
  assert(type(player_name)=='string','creative mode requires player name')
  if type(self.opts.creative_enabled)=='function' then
   return self.opts.creative_enabled(player_name)==true
  end
  if type(self.opts.creative_players)=='table' then
   if self.opts.creative_players[player_name]~=nil then
    return self.opts.creative_players[player_name]==true
   end
  end
  return self.opts.creative_mode==true
 end
 function api.get_node_light(pos)
  local n=api.get_node(pos)
  local d=self.registry.nodes[n.name]
  return d and d.light_source or 0
 end
 function api.is_protected() return false end
 function api.get_objects_inside_radius(pos,radius)
  local out=LuaEntities.radius(self,pos,radius)
  assert(type(radius)=='number' and radius>=0 and
   radius==radius and radius~=math.huge,
   'object radius must be finite and nonnegative')
  for _,obj in ipairs(self.droppedItems or {}) do
   if not obj.removed then
    local p=obj:get_pos()
    local dx,dy,dz=p.x-pos.x,p.y-pos.y,p.z-pos.z
    if dx*dx+dy*dy+dz*dz<=radius*radius then out[#out+1]=obj end
   end
  end
  return out
 end
 -- First native-like raycast subset. Includes pointable registered nodes
 -- and real dropped/falling objects, not arbitrary LuaEntity refs yet.
 function api.raycast(from,to,objects,liquids)
  return Raycast.iterator(self,from,to,objects,liquids)
 end
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
 -- Falling object state advances before ABMs, with swept vertical collision
 -- to avoid tunneling through ground when the host supplies a large delta.
 Falling.step(self,dt)
 LuaEntities.step(self,dt)
 -- When the host exposes a real player position, items can be collected
 -- automatically. Iterate by player name for deterministic contention.
 if self.opts.auto_pickup~=false then
  local names={}
  for name in pairs(self.players) do names[#names+1]=name end
  table.sort(names)
  for _,name in ipairs(names) do
   Falling.pickup_player(self,self.players[name])
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
-- Prediction is a separate lifecycle from taking a crafting result.
-- The host supplies the item stack and actual crafting inventory.
function Runtime:predictCraft(stack,player,old_grid,inventory)
 assert(type(stack)=='table' and type(stack.get_name)=='function',
  'craft prediction needs an ItemStack')
 for _,callback in ipairs(self.callbacks.craft_predict) do
  local changed=callback(stack,player,old_grid,inventory)
  if changed~=nil then stack=changed end
 end
 return stack
end
-- Dispatch a batch of actual changed liquid nodes supplied by the host.
-- The source and target nodes are managed by the liquid simulation, not
-- mutated by merely registering this callback.
function Runtime:liquidTransformed(positions)
 assert(type(positions)=='table','liquid transformation needs positions')
 local snapshot={}
 for i,pos in ipairs(positions) do
  assert(ispos(pos),'invalid transformed liquid position')
  snapshot[i]=clone(pos)
 end
 return self:emit('liquid_transformed',snapshot)
end
-- Attach optional host-owned character physics without replacing the
-- host player object. Mods always receive that SAME table in callbacks.
function Runtime:bindPlayerPhysics(name,controller)
 local player=self.players[name]
 assert(player,'cannot bind physics to a disconnected player: '..tostring(name))
 assert(not self.playerPhysicsBindings[name],
  'player already has a Lua physics binding: '..name)
 assert(type(controller)=='table' and controller.api==self.api,
  'character controller belongs to a different runtime')
 local release=PlayerPhysics.attach(player,controller)
 local previous_provider=controller.object_colliders
 controller.object_colliders=function(swept)
  local boxes=EntityPhysics.entity_boxes(self,swept)
  -- Connected player controllers also block each other. Never infer
  -- collision data from unbound/native host-owned player objects.
  local names={}
  for other_name in pairs(self.playerPhysicsControllers) do
   if other_name~=name and self.players[other_name] then
    names[#names+1]=other_name
   end
  end
  table.sort(names)
  for _,other_name in ipairs(names) do
   local other=self.playerPhysicsControllers[other_name]
   local position=other:get_pos()
   local b=other:get_properties().collisionbox
   boxes[#boxes+1]={
    position.x+b[1],position.y+b[2],position.z+b[3],
    position.x+b[4],position.y+b[5],position.z+b[6]
   }
  end
  return boxes
 end
 self.playerPhysicsBindings[name]=function()
  controller.object_colliders=previous_provider
  release()
 end
 self.playerPhysicsControllers[name]=controller
 return player
end
-- Control flags come from the REAL host input, never inferred from
-- movement vectors. ObjectRef:get_player_control returns a defensive copy.
function Runtime:updatePlayerControls(name,controls)
 local controller=self.playerPhysicsControllers[name]
 assert(controller,'no connected player physics controller: '..tostring(name))
 return controller:set_player_controls(controls)
end
-- Host-provided players only. An optional controller is bound BEFORE mods
-- see on_joinplayer, and rollback leaves no partially connected player.
function Runtime:connectPlayer(player,controller)
 assert(type(player)=='table' and type(player.get_player_name)=='function',
  'connectPlayer requires a player object')
 local name=player:get_player_name()
 assert(type(name)=='string' and name~='', 'invalid player name')
 assert(not self.players[name], 'player already connected: '..name)
 self.players[name]=player
 local ok,err=pcall(function()
  if controller then self:bindPlayerPhysics(name,controller) end
  self:emit('on_joinplayer',player)
 end)
 if not ok then
  local release=self.playerPhysicsBindings[name]
  if release then release();self.playerPhysicsBindings[name]=nil end
  self.playerPhysicsControllers[name]=nil
  if self.playerDigSessions then self.playerDigSessions[name]=nil end
 self.players[name]=nil
  error(err,0)
 end
 return player
end
function Runtime:disconnectPlayer(name)
 local player=self.players[name]
 if not player then return false end
 -- Leave callbacks can still use player physics before the host releases it.
 local ok,err=pcall(function() self:emit('on_leaveplayer',player) end)
 local release=self.playerPhysicsBindings[name]
 if release then release();self.playerPhysicsBindings[name]=nil end
  self.playerPhysicsControllers[name]=nil
 if self.playerDigSessions then self.playerDigSessions[name]=nil end
 self.players[name]=nil
 if not ok then error(err,0) end
 return true
end
-- Host-driven player node actions. Unlike core.dig_node/place_node, these
-- pass the actual connected player, wielded stack, and real drop inventory.
-- Timed player mining; player and tool belong to this runtime.
function Runtime:beginDigNodeAsPlayer(player,pos)
 return require('core.playeractions').begin(self,player,pos)
end
function Runtime:advanceDigNodeAsPlayer(player,dt)
 return require('core.playeractions').advance(self,player,dt)
end
function Runtime:cancelDigNodeAsPlayer(player)
 return require('core.playeractions').cancel(self,player)
end
function Runtime:getDigProgress(player)
 return require('core.playeractions').progress(self,player)
end
function Runtime:digNodeAsPlayer(player,pos)
 return require('core.playeractions').dig(self,player,pos)
end
function Runtime:placeNodeAsPlayer(player,pos,pointed_thing)
 return require('core.playeractions').place(self,player,pos,pointed_thing)
end
-- Explicit host action for manual pickup tests and scripted magnet systems.
-- Returns number of world-item units transferred or consumed by callbacks.
function Runtime:pickupItemsAsPlayer(player,radius)
 return Falling.pickup_player(self,player,radius)
end
-- Host-level object punch path. Unlike automatic proximity pickup, it
-- verifies that the referenced object belongs to this world and is within
-- reach of the player's collisionbox before invoking item callbacks.
function Runtime:punchItemAsPlayer(player,item,reach)
 return Falling.punch_item(self,player,item,reach)
end
-- LuaEntity ObjectRefs have their own on_punch/on_rightclick callbacks.
-- They are not item stacks and must not be processed as dropped items.
-- Unload active LuaEntity ObjectRefs after the host has saved the world.
-- on_deactivate(false) differs from removal-triggered on_deactivate(true).
function Runtime:deactivateLuaEntities()
 return LuaEntities.deactivate_all(self)
end
function Runtime:punchLuaEntity(obj,puncher,interval,toolcaps,dir,damage)
 return LuaEntities.punch(self,obj,puncher,interval,toolcaps,dir,damage)
end
function Runtime:rightclickLuaEntity(obj,clicker)
 return LuaEntities.rightclick(self,obj,clicker)
end
-- Return the first real pointing hit; entities behind node collision
-- geometry cannot be selected. Direction need not be normalized.
function Runtime:raycast(origin,direction,reach,opts)
 return Raycast.first(self,origin,direction,reach or 6,opts)
end
-- Host-player ray interaction. A forged remote camera origin cannot
-- collect items because the ray origin must remain near the live player.
-- The existing item-punch path checks object ownership and reach again.
function Runtime:punchItemAlongRay(player,origin,direction,reach)
 assert(type(player)=='table' and
  type(player.get_player_name)=='function' and
  self.players[player:get_player_name()]==player,
  'ray punch requires connected player')
 assert(type(player.get_pos)=='function',
  'ray punch requires player position')
 local feet=player:get_pos()
 assert(type(origin)=='table' and
  type(origin.x)=='number' and type(origin.y)=='number' and
  type(origin.z)=='number','ray punch requires eye coordinates')
 local dx,dy,dz=origin.x-feet.x,
  origin.y-feet.y,origin.z-feet.z
 if dx*dx+dz*dz>.75*.75 or dy<-.6 or dy>2.6 then
  return false,'invalid_origin'
 end
 reach=reach or self.opts.item_punch_reach or 4
 local hit=self:raycast(origin,direction,reach)
 if not hit or hit.type~='object' then return false,'not_item' end
 -- A falling block has no dropped-item inventory and cannot be punched
 -- as an item until it actually becomes a dropped entity.
 local found=false
 for _,obj in ipairs(self.droppedItems or {}) do
  if obj==hit.ref then found=true;break end
 end
 if not found then return false,'not_item' end
 return self:punchItemAsPlayer(player,hit.ref,reach)
end
-- Return true when a Lua mod cancels the incoming player punch.
-- This is a policy/callback preflight; the host owns actual HP and physics.
-- Ray-directed LuaEntity interaction. The origin must be near the REAL
-- connected player, and only the first visible pointed object is valid.
function Runtime:interactObjectAlongRay(player,origin,direction,reach,action)
 assert(type(player)=='table' and
  type(player.get_player_name)=='function' and
  self.players[player:get_player_name()]==player,
  'ray interaction requires connected player')
 assert(type(player.get_pos)=='function','player has no position')
 assert(action=='punch' or action=='rightclick','invalid entity action')
 local at=player:get_pos()
 assert(type(origin)=='table' and type(origin.x)=='number' and
  type(origin.y)=='number' and type(origin.z)=='number',
  'ray requires eye position')
 local dx,dy,dz=origin.x-at.x,origin.y-at.y,origin.z-at.z
 if dx*dx+dz*dz>.75*.75 or dy<-.6 or dy>2.6 then
  return false,'invalid_origin'
 end
 reach=reach or 4
 local hit=self:raycast(origin,direction,reach)
 if not hit or hit.type~='object' then return false,'not_object' end
 for _,obj in ipairs(self.luaEntities) do
  if obj==hit.ref and not obj.removed then
   if action=='punch' then
    self:punchLuaEntity(obj,player,1,nil,direction,0)
   else self:rightclickLuaEntity(obj,player) end
   return true,obj
  end
 end
 if action=='punch' then
  local ok,count=self:punchItemAsPlayer(player,hit.ref,reach)
  if ok then return true,count end
  return false,count
 end
 return false,'not_entity'
end
function Runtime:isPlayerPunchCancelled(player,hitter,interval,toolcaps,dir,damage)
 assert(type(player)=='table','punch victim required')
 for _,cb in ipairs(self.callbacks.on_punchplayer) do
  if cb(player,hitter,interval,toolcaps,dir,damage)==true then
   return true
  end
 end
 return false
end
-- A punch is distinct from digging a node: do not remove the node or
-- simulate a player.  The host passes the actual puncher when available.
function Runtime:punchNode(pos,puncher,pointed_thing)
 assert(ispos(pos),'punch requires a node position')
 local node=self.api.get_node(pos)
 self:emit('on_punchnode',clone(pos),node,puncher,pointed_thing)
 self.api.check_for_falling(pos)
 return node
end
-- Explicit event dispatch for tests and future player integration.
-- Count-restrictions from upstream callbacks are combined conservatively.
-- This checks permissions only: actual moving/taking must be performed by
-- a future player backend after this preflight succeeds.
function Runtime:allowedInventoryAction(player,action,inventory,info)
 assert(type(action)=='string' and type(info)=='table',
  'invalid inventory action')
 local count=info.count or (info.stack and info.stack:get_count()) or 0
 assert(type(count)=='number' and count>=0 and count==math.floor(count),
  'invalid action count')
 for _,callback in ipairs(self.callbacks.allow_player_inventory_action) do
  local result=callback(player,action,inventory,info)
  if result~=nil then
   assert(type(result)=='number' and result>=0
    and result==math.floor(result),'invalid inventory allowance')
   count=math.min(count,result)
  end
 end
 return count
end
-- Called once by the host when the world/session closes.  Luanti's
-- register_on_shutdown callbacks are not regular per-frame callbacks.
function Runtime:shutdown()
 if self.shut_down then return false end
 self.shut_down=true
 self:emit('shutdown')
 return true
end
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
