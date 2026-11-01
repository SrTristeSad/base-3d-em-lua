-- Bridge the host-owned Player ObjectRef subset to a Lua character.
-- The host owns player identity and session lifetime. Lua methods installed
-- here are removed on disconnect and never replace existing host methods.
local Bridge={}
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
function Bridge.attach(player,controller)
 validate(player,controller)
 local detached=false
 local function check(self)
  assert(self==player,'player API called with wrong player')
  assert(not detached,'player binding was disconnected')
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
   return controller:set_properties(properties)
  end,
 }
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
