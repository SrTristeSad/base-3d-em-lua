-- Luanti StorageRef subset, backed by a versioned per-world Lua sidecar.
-- Metadata is per mod, not shared between mods or different world files.
-- Saved data is deserialized without eval/load; a failed decode never
-- replaces a live mod's StorageRef or fields.
local Serialization=require('core.serialization')
local Storage={}
local mt={}
mt.__index=mt

local HEADER='LUAENGINE MODSTORAGE 1\n'
local MAX_BYTES=1024*1024
local MAX_MODS=256
local MAX_FIELDS=8192
local MAX_NAME=256
local MAX_FIELD_BYTES=65536

local function keys(table_value)
 local r={}
 for k in pairs(table_value) do r[#r+1]=k end
 table.sort(r)
 return r
end

local function fields_copy(fields)
 assert(type(fields)=='table','mod storage fields must be a table')
 local clean={}
 local count=0
 for k,v in pairs(fields) do
  count=count+1
  assert(count<=MAX_FIELDS and type(k)=='string' and
   #k<=MAX_NAME and type(v)=='string' and
   #v<=MAX_FIELD_BYTES,'invalid mod storage key/value or field limit')
  if v~='' then clean[k]=v end
 end
 return clean
end

function Storage.new(values)
 return setmetatable({fields=fields_copy(values or {})},mt)
end
function mt:get_string(k)
 assert(type(k)=='string','mod storage key must be string')
 return self.fields[k] or ''
end
function mt:set_string(k,value)
 assert(type(k)=='string' and #k<=MAX_NAME and
  type(value)=='string' and #value<=MAX_FIELD_BYTES,
  'invalid string field')
 if value=='' then self.fields[k]=nil
 else self.fields[k]=value end
end
function mt:get_int(k)
 local n=tonumber(self:get_string(k))
 if not n then return 0 end
 return math.floor(n)
end
function mt:set_int(k,n)
 assert(type(n)=='number' and n==math.floor(n) and
  n>=-2147483648 and n<=2147483647,'invalid s32 integer')
 self:set_string(k,tostring(n))
end
function mt:get_float(k)
 return tonumber(self:get_string(k)) or 0
end
function mt:set_float(k,n)
 assert(type(n)=='number' and n==n and n~=math.huge and
  n~=-math.huge,'invalid float')
 self:set_string(k,string.format('%.17g',n))
end
function mt:contains(k)
 assert(type(k)=='string','mod storage key must be string')
 return self.fields[k]~=nil
end
function mt:to_table()
 return {fields=fields_copy(self.fields)}
end
function mt:from_table(t)
 -- Matches Luanti MetaDataRef: non-table clears the metadata.
 if type(t)~='table' then
  self.fields={}
 else
  self.fields=fields_copy(t.fields or {})
 end
 return true
end
function mt:get_keys() return keys(self.fields) end
function mt:equals(other)
 if type(other)~='table' or type(other.to_table)~='function' then
  return false
 end
 local a,b=self.fields,other:to_table().fields
 for k,v in pairs(a) do if b[k]~=v then return false end end
 for k,v in pairs(b) do if a[k]~=v then return false end end
 return true
end

local function snapshot(storages)
 assert(type(storages)=='table','mod storage registry required')
 local result={}
 local count=0
 for name,ref in pairs(storages) do
  count=count+1
  assert(count<=MAX_MODS and type(name)=='string' and
   #name>0 and #name<=MAX_NAME and
   name:match('^[%w_%-]+$'),'invalid storage mod identifier')
  assert(type(ref)=='table' and type(ref.to_table)=='function',
   'invalid mod StorageRef in registry')
  result[name]=fields_copy(ref:to_table().fields)
 end
 return result
end

function Storage.encode(storages)
 local text=HEADER..Serialization.serialize(snapshot(storages))
 assert(#text<=MAX_BYTES,'mod storage save too large')
 return text
end
function Storage.decode(data)
 assert(type(data)=='string' and #data<=MAX_BYTES and
  data:sub(1,#HEADER)==HEADER,'invalid mod storage header/size')
 local value=Serialization.deserialize(data:sub(#HEADER+1))
 assert(type(value)=='table','invalid mod storage payload')
 local clean={}
 local count=0
 for mod,fields in pairs(value) do
  count=count+1
  assert(count<=MAX_MODS and type(mod)=='string' and
   #mod>0 and #mod<=MAX_NAME and
   mod:match('^[%w_%-]+$'),'invalid saved mod identifier')
  clean[mod]=fields_copy(fields)
 end
 return clean
end
function Storage.save(storages,path,fs)
 assert(type(path)=='string' and path~='' and fs and
  type(fs.write)=='function','mod storage write requires path/filesystem')
 return fs.write(path,Storage.encode(storages))
end
function Storage.load(path,fs)
 assert(type(path)=='string' and path~='' and fs and
  type(fs.read)=='function','mod storage read requires path/filesystem')
 local data=fs.read(path)
 if data==nil then return nil,'not found' end
 local ok,result=pcall(Storage.decode,data)
 if not ok then return nil,result end
 return result
end

return Storage
