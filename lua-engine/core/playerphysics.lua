-- Bridge the host-owned Player ObjectRef subset to a Lua character.
-- The host owns player identity and session lifetime. Lua methods installed
-- here are removed on disconnect and never replace existing host methods.
local Bridge={}
local Inventory=require('core.inventory')
local Stack=require('core.itemstack')
local function validate(player,controller)
 assert(type(player)=='table' and type(player.get_player_name)=='function',
  'physics bridge needs a host player table')
 assert(type(controller)=='table' and
  type(controller.set_physics_override)=='function' and
  type(controller.get_physics_override)=='function',
  'physics bridge needs a character controller')
 assert(player.set_physics_override==nil and
  player.get_physics_override==nil,
  'host already implements player physics overrides; refusing to replace')
end
function Bridge.attach(player,controller,hp_set,player_meta)
 validate(player,controller)
 local detached=false
 local function check(self)
  assert(self==player,'player API called with wrong player')
  assert(not detached,'player binding was disconnected')
 end
 -- Player inventory is session-owned unless the host supplies a native
 -- inventory. Never replace the host's get_inventory implementation.
 local registry=controller.api.registered_items
 local owned_inventory=nil
 if player.get_inventory==nil then
  owned_inventory=Inventory.new(registry,
   {type='player',name=player:get_player_name()})
  owned_inventory:set_size('main',32)
 end
 local wield_index=1
 local hp=math.min(20,controller.hp_max or 20)
 local function inventory()
  if owned_inventory then return owned_inventory end
  local inv=player:get_inventory()
  assert(inv and type(inv.get_stack)=='function' and
   type(inv.set_stack)=='function' and
   type(inv.get_size)=='function',
   'host inventory must support main wield operations')
  return inv
 end
 local functions={
  set_physics_override=function(self,overrides)
   check(self)
   return controller:set_physics_override(overrides)
  end,
  get_physics_override=function(self)
   check(self)
   return controller:get_physics_override()
  end,
  get_inventory=function(self)
   check(self)
   return owned_inventory
  end,
  get_meta=function(self)
   check(self)
   return player_meta
  end,
  get_wield_list=function(self)
   check(self)
   return 'main'
  end,
  get_wield_index=function(self)
   check(self)
   return wield_index
  end,
  set_wield_index=function(self,index)
   check(self)
   local inv=inventory()
   assert(type(index)=='number' and index==math.floor(index) and
    index>=1 and index<=inv:get_size('main'),
    'invalid wield index')
   wield_index=index
  end,
  get_wielded_item=function(self)
   check(self)
   return inventory():get_stack('main',wield_index)
  end,
  set_wielded_item=function(self,item)
   check(self)
   local inv=inventory()
   assert(wield_index>=1 and wield_index<=inv:get_size('main'),
    'wielded slot no longer exists')
   return inv:set_stack('main',wield_index,Stack.new(item,registry))
  end,
  get_pos=function(self)
   check(self)
   return controller:get_pos()
  end,
  set_pos=function(self,position)
   check(self)
   return controller:set_pos(position)
  end,
  get_velocity=function(self)
   check(self)
   return controller:get_velocity()
  end,
  set_velocity=function(self,velocity)
   check(self)
   return controller:set_velocity(velocity)
  end,
  add_velocity=function(self,velocity)
   check(self)
   return controller:add_velocity(velocity)
  end,
  get_player_control=function(self)
   check(self)
   return controller:get_player_controls()
  end,
  get_properties=function(self)
   check(self)
   return controller:get_properties()
  end,
  set_properties=function(self,properties)
   check(self)
   local result=controller:set_properties(properties)
   hp=math.min(hp,controller.hp_max or 20)
   return result
  end,
 }
 -- Preserve native health methods. An incomplete native pair is not
 -- replaced with a different Lua-owned HP state.
 if player.get_hp==nil and player.set_hp==nil then
  assert(type(hp_set)=='function','Lua HP requires a runtime dispatcher')
  functions.get_hp=function(self)
   check(self)
   hp=math.min(hp,controller.hp_max or 20)
   return hp
  end
  functions.set_hp=function(self,requested,reason)
   check(self)
   hp_set(self,hp,requested,controller.hp_max or 20,reason,
    function(next_hp) hp=next_hp end)
  end
 end
 local installed={}
 -- Methods provided by a real host remain authoritative. Only supply the
 -- missing methods; do not manufacture any unrelated ObjectRef capabilities.
 for key,fn in pairs(functions) do
  if player[key]==nil then
   player[key]=fn
   installed[key]=fn
  end
 end
 return function()
  if detached then return end
  detached=true
  for key,fn in pairs(installed) do
   -- If a host replaced a method during the session, leave it untouched.
   if rawget(player,key)==fn then player[key]=nil end
  end
 end
end
return Bridge
