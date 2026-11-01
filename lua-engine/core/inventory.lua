-- Luanti InvRef subset: lists of isolated ItemStack values, 1-based indices.
local Stack=require('core.itemstack')
local Inventory={}
local methods={}
local mt={__index=methods}
local floor=math.floor
local function integer(v)
 return type(v)=='number' and v==floor(v) and v>=0 and v<=65535
end
local function check_name(name)
 assert(type(name)=='string' and name~='','inventory list name required')
end
local function compatible(a,b)
 return a:stackable(b)
end
function Inventory.new(registry,location)
 local actual=location or {type='undefined'}
 assert(type(actual)=='table' and type(actual.type)=='string',
  'inventory location must have a type')
 return setmetatable({lists={},widths={},registry=registry,
  location=actual},mt)
end
function methods:get_location()
 local copy={}
 for key,value in pairs(self.location) do
  if type(value)=='table' then
   copy[key]={}
   for k,v in pairs(value) do copy[key][k]=v end
  else copy[key]=value end
 end
 return copy
end
function methods:set_size(name,size)
 check_name(name)
 assert(integer(size),'invalid list size')
 if size==0 then
  self.lists[name]=nil
  self.widths[name]=nil
  return true
 end
 local old=self.lists[name] or {}
 local cells={}
 for i=1,size do cells[i]=old[i] or Stack.new(nil,self.registry) end
 self.lists[name]=cells
 return true
end
function methods:get_size(name)
 local list=self.lists[name]
 return list and #list or 0
end
function methods:set_width(name,width)
 check_name(name)
 assert(integer(width),'invalid width')
 self.widths[name]=width
end
function methods:get_width(name) return self.widths[name] or 0 end
function methods:get_stack(name,index)
 local cells=self.lists[name]
 if not cells or not integer(index) or index<1 or index>#cells then
  return Stack.new(nil,self.registry)
 end
 return cells[index]:copy()
end
function methods:set_stack(name,index,item)
 local cells=self.lists[name]
 if not cells or not integer(index) or index<1 or index>#cells then
  return false
 end
 cells[index]=Stack.new(item,self.registry)
 return true
end
function methods:get_list(name)
 local cells=self.lists[name]
 if not cells then return nil end
 local result={}
 for i=1,#cells do result[i]=cells[i]:copy() end
 return result
end
function methods:get_lists()
 local result={}
 for name in pairs(self.lists) do result[name]=self:get_list(name) end
 return result
end
function methods:set_list(name,values)
 check_name(name)
 if values==nil then return self:set_size(name,0) end
 assert(type(values)=='table','list must be table')
 local oldsize=self:get_size(name)
 local size=oldsize>0 and oldsize or #values
 assert(size<=65535,'list too large')
 if size==0 then return self:set_size(name,0) end
 local result={}
 for i=1,size do result[i]=Stack.new(values[i],self.registry) end
 self.lists[name]=result
 return true
end
function methods:set_lists(lists)
 assert(type(lists)=='table','inventory lists must be a table')
 for name,values in pairs(lists) do
  self:set_list(name,values)
 end
 return true
end
function methods:is_empty(name)
 local cells=self.lists[name]
 if not cells then return true end
 for i=1,#cells do if not cells[i]:is_empty() then return false end end
 return true
end
-- insert() shared by room_for_item/add_item. Simulating insertion on a
-- clone for room_for_item keeps the original inventory completely unchanged.
local function insert(cells,original,registry)
 local rest=Stack.new(original,registry)
 if rest:is_empty() then return rest end
 -- Stack matching includes wear and metadata; other variants never merge.
 for i=1,#cells do
  local stack=cells[i]
  if compatible(stack,rest) and stack:get_free_space()>0 then
   rest=stack:add_item(rest)
   if rest:is_empty() then return rest end
  end
 end
 for i=1,#cells do
  local stack=cells[i]
  if stack:is_empty() then
   rest=stack:add_item(rest)
   if rest:is_empty() then return rest end
  end
 end
 return rest
end
function methods:add_item(name,item)
 local cells=self.lists[name]
 if not cells then return Stack.new(item,self.registry) end
 return insert(cells,item,self.registry)
end
function methods:room_for_item(name,item)
 local cells=self:get_list(name)
 if not cells then return false end
 return insert(cells,item,self.registry):is_empty()
end
function methods:contains_item(name,item,match_meta)
 local remaining=Stack.new(item,self.registry)
 if remaining:is_empty() then return true end
 local cells=self.lists[name]
 if not cells then return false end
 for i=1,#cells do
  local stack=cells[i]
  local ok=match_meta and stack:stackable(remaining) or
    (stack.name==remaining.name and stack.wear==remaining.wear)
  if ok then
   remaining.count=math.max(0,remaining.count-stack.count)
   if remaining.count==0 then return true end
  end
 end
 return false
end
function methods:remove_item(name,item)
 local wanted=Stack.new(item,self.registry)
 local out=Stack.new(nil,self.registry)
 if wanted:is_empty() then return out end
 local cells=self.lists[name]
 if not cells then return out end
 local count=wanted.count
 for i=1,#cells do
  local stack=cells[i]
  if compatible(stack,wanted) then
   local taken=stack:take_item(count)
   if out:is_empty() then out=taken
   else out.count=out.count+taken.count end
   count=count-taken.count
   if count==0 then break end
  end
 end
 return out
end
function methods:to_table()
 local result={}
 for name,cells in pairs(self.lists) do
  local stacks={}
  for i=1,#cells do stacks[i]=cells[i]:to_table() or false end
  result[name]={size=#cells,width=self.widths[name] or 0,stacks=stacks}
 end
 return result
end
function methods:from_table(t)
 assert(type(t)=='table','invalid inventory table')
 self.lists={}
 self.widths={}
 for name,entry in pairs(t) do
  if type(entry)=='table' and integer(entry.size) and entry.size>0 then
   self:set_size(name,entry.size)
   self:set_width(name,entry.width or 0)
   for i=1,entry.size do
    self:set_stack(name,i,entry.stacks and entry.stacks[i] or nil)
   end
  end
 end
end
return Inventory
