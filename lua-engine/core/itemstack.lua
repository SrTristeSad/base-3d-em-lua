-- Luanti ItemStack subset. Value semantics: inventories always return copies.
local ItemStack={}
local methods={}
local mt={__index=methods}
local floor=math.floor
local function integer(value,minv,maxv,default)
 local n=tonumber(value)
 if not n or n~=n or n==math.huge or n==-math.huge then return default end
 return math.max(minv,math.min(maxv,floor(n)))
end
local function fields_copy(source)
 local out={}
 for k,v in pairs(source or {}) do
  if type(k)=='string' and (type(v)=='string' or type(v)=='number') then
   out[k]=tostring(v)
  end
 end
 return out
end
local function info(src)
 local name,count,wear,fields=' ',0,0,{}
 if getmetatable(src)==mt then
  name,count,wear,fields=src.name,src.count,src.wear,fields_copy(src.fields)
 elseif type(src)=='string' then
  local n,c,w=src:match('^(%S+)%s+(%d+)%s+(%d+)$')
  if not n then n,c=src:match('^(%S+)%s+(%d+)$') end
  if not n then n=src:match('^(%S+)$') end
  name=n or ''
  count=integer(c,0,65535, name~='' and 1 or 0)
  wear=integer(w,0,65535,0)
 elseif type(src)=='table' then
  name=type(src.name)=='string' and src.name or ''
  count=integer(src.count,0,65535,name~='' and 1 or 0)
  wear=integer(src.wear,0,65535,0)
  fields=fields_copy(src.fields or src.metadata)
 else
  name=''
 end
 if name=='' or name==' ' or count<=0 then
  return '',0,0,{}
 end
 return name,count,wear,fields
end
local function create(name,count,wear,fields,registry)
 return setmetatable({name=name,count=count,wear=wear,
  fields=fields,registry=registry},mt)
end
function ItemStack.new(src,registry)
 local name,count,wear,fields=info(src)
 return create(name,count,wear,fields,registry)
end
setmetatable(ItemStack,{__call=function(_,...) return ItemStack.new(...) end})
function methods:copy()
 return create(self.name,self.count,self.wear,fields_copy(self.fields),self.registry)
end
function methods:is_empty() return self.name=='' or self.count==0 end
function methods:get_name() return self.name end
function methods:get_definition()
 return self.registry[self.name] or nil
end
function methods:get_tool_capabilities()
 local def=self:get_definition()
 return def and def.tool_capabilities or {}
end
function methods:get_count() return self.count end
function methods:get_wear() return self.wear end
function methods:set_name(name)
 assert(type(name)=='string','item name must be a string')
 if name=='' then self:clear()
 else
  self.name=name
  if self.count==0 then self.count=1 end
 end
end
function methods:set_count(n)
 self.count=integer(n,0,65535,0)
 if self.count==0 then self:clear() end
end
function methods:set_wear(n)
 self.wear=integer(n,0,65535,0)
end
function methods:clear()
 self.name,self.count,self.wear,self.fields='',0,0,{}
end
function methods:get_stack_max()
 if self:is_empty() then return 99 end
 local def=self.registry and self.registry[self.name]
 return integer(def and def.stack_max,1,65535,99)
end
function methods:get_free_space()
 if self:is_empty() then return 0 end
 return math.max(0,self:get_stack_max()-self.count)
end
function methods:to_table()
 if self:is_empty() then return nil end
 return {name=self.name,count=self.count,wear=self.wear,
  metadata='',fields=fields_copy(self.fields)}
end
function methods:to_string()
 if self:is_empty() then return '' end
 if next(self.fields) then
  error('metadata-bearing ItemStack requires Luanti binary itemstring support')
 end
 if self.wear~=0 then
  return ('%s %d %d'):format(self.name,self.count,self.wear)
 end
 if self.count~=1 then return ('%s %d'):format(self.name,self.count) end
 return self.name
end
function methods:equals(other)
 other=ItemStack.new(other,self.registry)
 if self.name~=other.name or self.count~=other.count or self.wear~=other.wear then
  return false
 end
 for k,v in pairs(self.fields) do if other.fields[k]~=v then return false end end
 for k,v in pairs(other.fields) do if self.fields[k]~=v then return false end end
 return true
end
function methods:stackable(other)
 other=ItemStack.new(other,self.registry)
 if self:is_empty() or other:is_empty() or self.name~=other.name
  or self.wear~=other.wear then return false end
 for k,v in pairs(self.fields) do if other.fields[k]~=v then return false end end
 for k,v in pairs(other.fields) do if self.fields[k]~=v then return false end end
 return true
end
function methods:peek_item(n)
 if self:is_empty() then return ItemStack.new(nil,self.registry) end
 local copy=self:copy()
 copy.count=math.min(self.count,integer(n,0,65535,1))
 if copy.count==0 then copy:clear() end
 return copy
end
function methods:take_item(n)
 local taken=self:peek_item(n)
 self.count=self.count-taken.count
 if self.count==0 then self:clear() end
 return taken
end
function methods:add_item(other)
 local rest=ItemStack.new(other,self.registry)
 if rest:is_empty() then return rest end
 if self:is_empty() then
  local amount=math.min(rest.count,rest:get_stack_max())
  local inserted=rest:take_item(amount)
  self.name,self.count,self.wear,self.fields=
   inserted.name,inserted.count,inserted.wear,fields_copy(inserted.fields)
 elseif self:stackable(rest) then
  local n=math.min(self:get_free_space(),rest.count)
  self.count=self.count+n
  rest:take_item(n)
 end
 return rest
end
function methods:get_meta()
 local stack=self
 local meta={}
 function meta:get_string(k) return stack.fields[k] or '' end
 function meta:set_string(k,v)
  assert(type(k)=='string' and type(v)=='string')
  if v=='' then stack.fields[k]=nil else stack.fields[k]=v end
 end
 function meta:get_int(k) return floor(tonumber(stack.fields[k]) or 0) end
 function meta:set_int(k,v) self:set_string(k,tostring(floor(v))) end
 function meta:get_float(k) return tonumber(stack.fields[k]) or 0 end
 function meta:set_float(k,v) self:set_string(k,tostring(v)) end
 function meta:contains(k) return stack.fields[k]~=nil end
 function meta:to_table() return {fields=fields_copy(stack.fields)} end
 function meta:from_table(t)
  stack.fields=fields_copy(t and t.fields)
 end
 return meta
end
mt.__tostring=methods.to_string
mt.__eq=function(a,b) return a:equals(b) end
return ItemStack
