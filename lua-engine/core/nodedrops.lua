-- Luanti node drop evaluator (explicit subset).
-- Supports direct string drops and table items with rarity / max_items.
-- Tool capabilities, silk touch, fortune and color inheritance are future work.
local Drops={}
local floor=math.floor
local function validate_rng(rng)
 assert(type(rng)=='function','drop RNG must be callable')
 return function(max)
  local n=rng(max)
  assert(type(n)=='number' and n==floor(n) and n>=1 and n<=max,
   'invalid RNG response')
  return n
 end
end
local function choose_item(entry)
 if type(entry)=='string' then return {entry} end
 if type(entry)=='table' then
  assert(type(entry.items)=='table','drop entry items must be a table')
  return entry.items
 end
 error('invalid drop entry',2)
end
local function name_only(stack)
 assert(type(stack)=='string','item name must be string')
 return stack:match('^%s*([^%s]+)') or ''
end
local function tool_match(entry,tool)
 if not entry.tools then return true end
 if type(entry.tools)~='table' then return false end
 for _,name in ipairs(entry.tools) do
  if name==tool then return true end
 end
 return false
end
function Drops.evaluate(registry,node,tool,rng)
 assert(type(registry)=='table' and type(node)=='string',
  'node drops require a registry and node name')
 local def=registry[node]
 if not def then return {} end
 local drop=def.drop
 if drop==nil then return {node} end
 if type(drop)=='string' then
  return drop~='' and {drop} or {}
 end
 assert(type(drop)=='table','unsupported node drops format')
 local next_int=validate_rng(rng or math.random)
 local list={}
 local max=drop.max_items or math.huge
 assert(type(max)=='number' and max>=0 and max==floor(max),
  'invalid max_items')
 for _,entry in ipairs(drop.items or {}) do
  local rarity=entry.rarity or 1
  assert(type(rarity)=='number' and rarity>=1 and rarity==floor(rarity),
   'invalid drop rarity')
  if #list<max and tool_match(entry,tool or '') and next_int(rarity)==1 then
   local choices=choose_item(entry)
   for _,item in ipairs(choices) do
    local name=name_only(item)
    if name~='' and #list<max then
     list[#list+1]=item
    end
   end
  end
 end
 return list
end
return Drops
