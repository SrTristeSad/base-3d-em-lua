-- Luanti 5.18 player privilege, chat delivery and protection callback bridge.
-- No fake network/auth server: a host can provide persistent privilege
-- callbacks and a chat transport. Without them, the Lua runtime maintains
-- explicitly scoped session state and a consumable inbox for connected users.
local M={}
local floor=math.floor
local function copy(t)
 local out={}
 for k,v in pairs(t) do out[k]=v end
 return out
end
local function player_name(player)
 if type(player)=='table' and type(player.get_player_name)=='function' then
  player=player:get_player_name()
 end
 assert(type(player)=='string','expected player or player name')
 return player
end
local function privilege_set(source)
 if type(source)=='string' then
  local out={}
  for priv in source:gmatch('[^,%s]+') do out[priv]=true end
  return out
 end
 assert(type(source)=='table','privileges must be a table or comma-separated string')
 local out={}
 for key,value in pairs(source) do
  assert(type(key)=='string' and key~='' and type(value)=='boolean',
   'privileges must be a set of booleans')
  if value then out[key]=true end
 end
 return out
end
local function position(pos)
 assert(type(pos)=='table' and type(pos.x)=='number' and
  type(pos.y)=='number' and type(pos.z)=='number' and
  pos.x==pos.x and pos.y==pos.y and pos.z==pos.z,
  'expected finite position')
 return {x=pos.x,y=pos.y,z=pos.z}
end
local function format(msg,name,message,timestamp)
 assert(type(msg)=='string' and msg:find('@name',1,true)
  and msg:find('@message',1,true),
  'chat format must include @name and @message')
 -- Substitute by callback, not gsub replacement string, because % and
 -- Lua patterns inside player-provided text must remain uninterpreted.
 local str=msg:gsub('@name',function() return name end,1)
 str=str:gsub('@timestamp',function() return timestamp end,1)
 str=str:gsub('@message',function() return message end,1)
 return str
end
function M.install(rt,api)
 local explicit={}
 local pending={}
 local defaults=privilege_set(rt.opts.default_privs or {})
 local protection_callbacks={}
 api.registered_on_protection_violation=protection_callbacks
 local function get(name)
  name=player_name(name)
  if type(rt.opts.read_player_privs)=='function' then
   local result=rt.opts.read_player_privs(name)
   return privilege_set(result or {})
  end
  return copy(explicit[name] or defaults)
 end
 function api.get_player_privs(name)
  return get(name)
 end
 function api.set_player_privs(name,privs)
  name=player_name(name)
  assert(name~='','player name must not be empty')
  local nextset=privilege_set(privs)
  if type(rt.opts.write_player_privs)=='function' then
   local ok=rt.opts.write_player_privs(name,copy(nextset))
   if ok==false then return false end
  end
  explicit[name]=nextset
  return true
 end
 function api.change_player_privs(name,changes)
  name=player_name(name)
  assert(type(changes)=='table','expected privilege changes')
  local old=get(name)
  for key,value in pairs(changes) do
   assert(type(key)=='string' and key~='' and type(value)=='boolean',
    'privilege changes must be booleans')
   if value then old[key]=true else old[key]=nil end
  end
  return api.set_player_privs(name,old)
 end
 function api.check_player_privs(player,...)
  local owned=get(player)
  local n=select('#',...)
  local required={...}
  local missing={}
  if n>=1 and type(required[1])=='table' then
   for key,required_value in pairs(required[1]) do
    if required_value and not owned[key] then
     missing[#missing+1]=key
    end
   end
  else
   for i=1,n do
    local key=required[i]
    assert(type(key)=='string','privilege names must be strings')
    if not owned[key] then missing[#missing+1]=key end
   end
  end
  if #missing==0 then return true,'' end
  table.sort(missing)
  return false,missing
 end
 function api.register_on_protection_violation(fn)
  assert(type(fn)=='function','protection callback must be callable')
  protection_callbacks[#protection_callbacks+1]=fn
 end
 function api.record_protection_violation(pos,name)
  local p=position(pos)
  name=player_name(name)
  for _,fn in ipairs(protection_callbacks) do
   fn(copy(p),name)
  end
 end
 -- Luanti's builtin default is unprotected; mods can override this
 -- function in-place. A host can optionally supply a real policy.
 api.is_protected=function(pos,name)
  pos=position(pos);name=player_name(name)
  if type(rt.opts.is_protected)=='function' then
   return rt.opts.is_protected(pos,name)==true
  end
  return false
 end
 function api.is_area_protected(minp,maxp,name,interval)
  local a,b=position(minp),position(maxp)
  name=player_name(name)
  interval=interval or 4
  assert(type(interval)=='number' and interval>0 and
   interval<math.huge and interval==interval,
   'invalid protection interval')
  local steps={}
  for _,axis in ipairs({'x','y','z'}) do
   if a[axis]>b[axis] then
    a[axis],b[axis]=b[axis],a[axis]
   end
   steps[axis]=math.max(1,math.ceil((b[axis]-a[axis])/interval))
  end
  assert((steps.x+1)*(steps.y+1)*(steps.z+1)<=100000,
   'protection scan too large for Lua runtime')
  -- Like builtin/game/misc.lua, sample a bounded lattice including
  -- every corner and edge, at intervals never exceeding the request.
  for z=0,steps.z do for y=0,steps.y do for x=0,steps.x do
   local p={x=floor(a.x+(b.x-a.x)*x/steps.x+.5),
    y=floor(a.y+(b.y-a.y)*y/steps.y+.5),
    z=floor(a.z+(b.z-a.z)*z/steps.z+.5)}
   if api.is_protected(p,name) then return p end
  end end end
  return false
 end
 local function deliver(name,message)
  if rt.players[name]==nil then return end
  if type(rt.opts.chat_sink)=='function' then
   rt.opts.chat_sink(name,message)
  else
   local inbox=pending[name] or {}
   inbox[#inbox+1]=message
   pending[name]=inbox
  end
 end
 function api.chat_send_player(name,message)
  name=player_name(name)
  assert(type(message)=='string','chat message must be a string')
  deliver(name,message)
 end
 function api.chat_send_all(message)
  assert(type(message)=='string','chat message must be a string')
  local names={}
  for name in pairs(rt.players) do names[#names+1]=name end
  table.sort(names)
  for _,name in ipairs(names) do deliver(name,message) end
 end
 function api.format_chat_message(name,message)
  assert(type(name)=='string' and type(message)=='string',
   'chat name and message must be strings')
  local settings=rt.opts.settings or {}
  return format(settings.chat_message_format or '<@name> @message',
   name,message,os.date('%H:%M:%S'))
 end
 function rt:pollChat(player)
  local name=player_name(player)
  local queue=pending[name] or {}
  pending[name]=nil
  return queue
 end
 function rt:clearChat(player)
  pending[player_name(player)]=nil
 end
end
return M
