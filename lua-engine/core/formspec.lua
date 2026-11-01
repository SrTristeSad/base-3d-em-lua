-- Luanti server-side formspec sessions and syntax preservation.
-- No window renderer: a host can draw get_player_formspec() and submit fields
-- received from its actual UI. Never synthesize client input from a mod.
local Formspec={}
Formspec.__index=Formspec

local function elements(source)
 local out={}
 local at=1
 while at<=#source do
  local first,last,name=source:find('([%w_]+)%[',at)
  if not first then break end
  local depth=1
  local start=last+1
  local i=start
  while i<=#source and depth>0 do
   local char=source:sub(i,i)
   if char=='\\' then
    i=i+2
   else
    if char=='[' then depth=depth+1 end
    if char==']' then depth=depth-1 end
    i=i+1
   end
  end
  if depth~=0 then
   return nil,'incomplete formspec element: '..name
  end
  out[#out+1]={name=name,params=source:sub(start,i-2)}
  at=i
 end
 return out
end
Formspec.parse=elements

function Formspec.new(runtime)
 return setmetatable({runtime=runtime,active={}},Formspec)
end

local function snapshot(session)
 if not session then return nil end
 local result={formname=session.formname,formspec=session.formspec}
 if session.elements then
  result.elements={}
  for i,element in ipairs(session.elements) do
   result.elements[i]={name=element.name,params=element.params}
  end
 end
 return result
end

function Formspec:get(playername)
 return snapshot(self.active[playername])
end

function Formspec:notify(playername)
 local callback=self.runtime.opts.on_formspec_change
 if callback then callback(playername,self:get(playername)) end
end

function Formspec:close(playername,formname)
 assert(type(playername)=='string' and playername~='',
  'formspec requires playername')
 assert(type(formname)=='string','formspec requires formname')
 local old=self.active[playername]
 if not old or (formname~='' and old.formname~=formname) then
  return false
 end
 self.active[playername]=nil
 self:notify(playername)
 return true
end

function Formspec:show(playername,formname,formspec)
 assert(type(playername)=='string' and playername~='',
  'formspec requires playername')
 assert(type(formname)=='string','formspec requires formname')
 assert(type(formspec)=='string','formspec must be a string')
 if not self.runtime.players[playername] then return false end
 if formspec=='' then return self:close(playername,formname) end
 -- The Luanti server passes the raw formspec to its client. Do not reject
 -- game-authored extensions because our optional parser is incomplete.
 local parsed=elements(formspec)
 self.active[playername]={formname=formname,formspec=formspec,
  elements=parsed}
 self:notify(playername)
 return true
end

-- Only a host-owned, connected player can submit an event for their active form.
-- Callbacks execute last-registered first; a true result stops dispatch.
function Formspec:receive(playername,formname,fields)
 assert(type(playername)=='string' and playername~='',
  'formspec event requires player name')
 assert(type(formname)=='string','formspec event requires form name')
 assert(type(fields)=='table','formspec fields must be a table')
 local player=self.runtime.players[playername]
 local active=self.active[playername]
 if not player or not active or active.formname~=formname then
  return false,'form not active'
 end
 local payload={}
 for k,v in pairs(fields) do
  assert(type(k)=='string' and type(v)=='string',
   'Luanti formspec fields must map names to string values')
  payload[k]=v
 end
 -- Client close is distinct from server close: deliver quit to the mods.
 if payload.quit=='true' then self:close(playername,formname) end
 local callbacks=self.runtime.callbacks.on_player_receive_fields
 for i=#callbacks,1,-1 do
  if callbacks[i](player,formname,payload)==true then return true end
 end
 return true
end
return Formspec
