-- Bind the independent Lua character controller to a REAL host player object.
-- No synthetic player or emulator userdata: the host owns player sessions.
-- The Lua ObjectRef subset is installed only when the host does not already
-- implement its own physics methods; disconnect restores original behavior.
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
  assert(self==player,'physics override called with wrong player')
  assert(not detached,'physics binding was disconnected')
 end
 local setter=function(self,overrides)
  check(self)
  return controller:set_physics_override(overrides)
 end
 local getter=function(self)
  check(self)
  return controller:get_physics_override()
 end
 -- Both methods are attached to the host ObjectRef table. Luanti mods
 -- receive the same object from get_connected_players/get_player_by_name.
 player.set_physics_override=setter
 player.get_physics_override=getter
 return function()
  if detached then return end
  detached=true
  -- Never remove or overwrite a newer implementation supplied by host.
  if rawget(player,'set_physics_override')==setter then
   player.set_physics_override=nil
  end
  if rawget(player,'get_physics_override')==getter then
   player.get_physics_override=nil
  end
 end
end
return Bridge
