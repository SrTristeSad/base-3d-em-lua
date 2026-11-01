-- Luanti player HP callbacks: see builtin/game/register.lua (5.18.0).
-- Does not implement engine physics damage or native ObjectRef transport.
local PlayerHP={}
local floor,max,min=math.floor,math.max,math.min

local function finite(value)
 return type(value)=='number' and value==value and
  value~=math.huge and value~=-math.huge
end

function PlayerHP.install(api)
 local callbacks={modifiers={},loggers={}}
 api.registered_on_player_hpchanges=callbacks

 function api.register_on_player_hpchange(fn,modifier)
  assert(type(fn)=='function','player HP callback must be a function')
  local list=modifier and callbacks.modifiers or callbacks.loggers
  list[#list+1]=fn
 end

 -- Matches Luanti: newest modifier runs first; loggers see the final delta
 -- and run in registration order, including when a modifier stops the chain.
 function api.registered_on_player_hpchange(player,delta,reason)
  assert(finite(delta),'HP change must be finite')
  for i=#callbacks.modifiers,1,-1 do
   local stop
   delta,stop=callbacks.modifiers[i](player,delta,reason)
   assert(finite(delta),'HP modifier must return a finite number')
   if stop then break end
  end
  for _,fn in ipairs(callbacks.loggers) do fn(player,delta,reason) end
  return delta
 end
end

-- This is used only by host-controlled player ObjectRefs with Lua-owned HP.
-- Native hosts retain their own set_hp implementation and must forward
-- native HP events if they want to use the Lua callback registry.
function PlayerHP.set(runtime,player,current,requested,hp_max,provided_reason,apply)
 assert(finite(current) and finite(requested) and
  requested==floor(requested),'player HP must be a finite integer')
 assert(finite(hp_max) and hp_max==floor(hp_max) and
  hp_max>=1 and hp_max<=65535,'invalid player hp_max')
 assert(provided_reason==nil or type(provided_reason)=='table',
  'player HP reason must be a table')
 local reason={}
 for k,v in pairs(provided_reason or {}) do reason[k]=v end
 if reason.type==nil then reason.type='set_hp' end
 if reason.from==nil then reason.from='mod' end
 current=min(max(0,current),hp_max)
 local delta=requested-current
 -- Luanti ignores further damage when a player is already dead.
 if current==0 and delta<0 then return 0 end
 local final_delta=runtime.api.registered_on_player_hpchange(player,delta,reason)
 local resulting_hp=min(hp_max,max(0,floor(current+final_delta)))
 -- Commit HP before dispatching death so callbacks observe get_hp() == 0.
 if apply then apply(resulting_hp) end
 if current>0 and resulting_hp==0 then
  runtime:emit('on_dieplayer',player,reason)
 end
 return resulting_hp
end

return PlayerHP
