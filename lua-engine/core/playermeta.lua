-- PlayerMetaRef for Lua-hosted player sessions. Distinct from node metadata.
-- The runtime owns the reference by player name; reconnects reuse its fields.
local PlayerMeta={}
PlayerMeta.__index=PlayerMeta
local floor=math.floor

function PlayerMeta.new()
 return setmetatable({fields={}},PlayerMeta)
end

function PlayerMeta:get(name)
 assert(type(name)=='string','metadata key must be a string')
 return self.fields[name]
end

function PlayerMeta:get_string(name)
 return self:get(name) or ''
end

function PlayerMeta:set_string(name,value)
 assert(type(name)=='string' and name~='','invalid player metadata key')
 assert(type(value)=='string' or type(value)=='number',
  'player metadata values must be strings or numbers')
 self.fields[name]=tostring(value)
 return true
end

function PlayerMeta:get_int(name)
 local value=tonumber(self:get(name))
 return value and floor(value) or 0
end

function PlayerMeta:set_int(name,value)
 assert(type(value)=='number' and value==floor(value) and
  value~=math.huge and value~=-math.huge,'invalid metadata integer')
 return self:set_string(name,value)
end

function PlayerMeta:get_float(name)
 return tonumber(self:get(name)) or 0
end

function PlayerMeta:set_float(name,value)
 assert(type(value)=='number' and value==value and
  value~=math.huge and value~=-math.huge,'invalid metadata number')
 return self:set_string(name,value)
end

function PlayerMeta:contains(name)
 return self:get(name)~=nil
end

function PlayerMeta:to_table()
 local fields={}
 for name,value in pairs(self.fields) do fields[name]=value end
 return {fields=fields}
end

function PlayerMeta:from_table(data)
 assert(type(data)=='table' and type(data.fields)=='table',
  'player metadata requires fields table')
 local fields={}
 for name,value in pairs(data.fields) do
  assert(type(name)=='string' and type(value)=='string',
   'invalid player metadata content')
  fields[name]=value
 end
 self.fields=fields
 return true
end

return PlayerMeta
