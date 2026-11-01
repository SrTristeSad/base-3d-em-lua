-- Tool digging parameters ported from Luanti src/tool.cpp (getDigParams).
-- Pure Lua implementation; used by both the host and core.get_dig_params.
local Digging = {}
local floor, min = math.floor, math.min

local function finite(n)
 return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

local function result(diggable, time, wear, group, reason)
 return {diggable=diggable, time=time, wear=wear,
  main_group=group, group=group, reason=reason}
end

-- Luanti distributes 65536 wear points over exactly `uses` digs.
-- The last `remainder` digs receive one extra point each.
function Digging.calculate_wear(uses, initial_wear)
 assert(finite(uses) and uses >= 0, 'invalid tool uses')
 assert(finite(initial_wear) and initial_wear >= 0 and initial_wear <= 65535,
  'invalid initial wear')
 uses = floor(uses)
 initial_wear = floor(initial_wear)
 if uses == 0 then return 0 end
 uses = min(65535, uses)
 local normal = floor(65536 / uses)
 local oversized = 65536 % uses
 local threshold = (uses - oversized) * normal
 return normal + ((oversized > 0 and initial_wear >= threshold) and 1 or 0)
end

function Digging.get_params(groups, capabilities, initial_wear)
 assert(type(groups) == 'table', 'dig groups required')
 assert(type(capabilities) == 'table', 'tool capabilities required')
 initial_wear = initial_wear or 0
 assert(finite(initial_wear) and initial_wear >= 0 and initial_wear <= 65535,
  'invalid initial wear')
 local caps = capabilities.groupcaps or {}
 assert(type(caps) == 'table', 'groupcaps must be a table')

 -- Only dig_immediate=2 and =3 bypass toolcaps in native Luanti.
 -- A custom dig_immediate toolcap overrides this fixed-time path.
 if caps.dig_immediate == nil then
  if groups.dig_immediate == 2 then
   return result(true, 0.5, 0, 'dig_immediate')
  elseif groups.dig_immediate == 3 then
   return result(true, 0, 0, 'dig_immediate')
  end
 end

 local level = groups.level or 0
 local best
 -- Luanti iterates std::map: use sorted names for deterministic ties.
 local names = {}
 for name in pairs(caps) do names[#names+1] = name end
 table.sort(names)
 for _,name in ipairs(names) do
  local cap = caps[name]
  if type(cap) == 'table' and type(cap.times) == 'table' then
   local rating = groups[name] or 0
   local maxlevel = cap.maxlevel == nil and 1 or cap.maxlevel
   local diff = maxlevel - level
   local duration = cap.times[rating]
   if diff >= 0 and finite(duration) and duration >= 0 then
    if diff > 1 then duration = duration / diff end
    if not best or duration < best.time then
     local uses = cap.uses == nil and 20 or cap.uses
     local real_uses = (finite(uses) and uses > 0) and
      min(65535, floor(uses * 3 ^ diff)) or 0
     best = result(true, duration,
      Digging.calculate_wear(real_uses, initial_wear), name)
    end
   end
  end
 end
 return best or result(false, 0, 0, '', 'unsupported_tool')
end

function Digging.params(node_def, tool)
 assert(type(node_def) == 'table', 'node definition required')
 assert(type(tool) == 'table' and type(tool.get_tool_capabilities) == 'function'
  and type(tool.get_wear) == 'function', 'ItemStack required')
 if node_def.diggable == false then
  return result(false, 0, 0, '', 'not_diggable')
 end
 return Digging.get_params(node_def.groups or {}, tool:get_tool_capabilities(),
  tool:get_wear())
end
return Digging
