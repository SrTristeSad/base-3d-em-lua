-- Persistent-by-runtime mod storage API (not yet serialized to disk).
local Storage={}
local mt={}
mt.__index=mt
local function keys(table_value)
 local r={}
 for k in pairs(table_value) do r[#r+1]=k end
 table.sort(r)
 return r
end
function Storage.new(values)
 assert(values==nil or type(values)=='table','invalid mod storage')
 return setmetatable({fields=values or {}},mt)
end
function mt:get_string(k) return self.fields[k] or '' end
function mt:set_string(k,value)
 assert(type(k)=='string' and type(value)=='string','invalid string')
 if value=='' then self.fields[k]=nil
 else self.fields[k]=value end
end
function mt:get_int(k)
 local n=tonumber(self.fields[k])
 if not n then return 0 end
 return math.floor(n)
end
function mt:set_int(k,n)
 assert(type(n)=='number' and n==math.floor(n),'invalid integer')
 self:set_string(k,tostring(n))
end
function mt:get_float(k) return tonumber(self.fields[k]) or 0 end
function mt:set_float(k,n)
 assert(type(n)=='number','invalid float')
 self:set_string(k,tostring(n))
end
function mt:contains(k) return self.fields[k]~=nil end
function mt:to_table()
 local out={}
 for k,v in pairs(self.fields) do out[k]=v end
 return {fields=out}
end
function mt:from_table(t)
 assert(type(t)=='table','invalid storage table')
 local out={}
 for k,v in pairs(t.fields or {}) do
  assert(type(k)=='string' and type(v)=='string','invalid storage field')
  out[k]=v
 end
 self.fields=out
end
function mt:get_keys() return keys(self.fields) end
return Storage
