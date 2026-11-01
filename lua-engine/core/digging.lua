-- Tool capability based dig times and tool wear.  Pure Lua, LuaJIT-safe.
-- Approximates level-difference time scaling; custom game rules remain external.
local Digging={}
local floor,ceil,min=math.floor,math.ceil,math.min
local function finite(v) return type(v)=='number' and v==v and
 v~=math.huge and v~=-math.huge end
local function validnonnegative(v) return finite(v) and v>=0 end
-- Luanti dig-immediate groups are supported without a tool.
local immediate_times={[1]=2,[2]=.5,[3]=0}
function Digging.params(node_def,tool,registry)
 assert(type(node_def)=='table','node definition required')
 assert(type(tool)=='table' and type(tool.get_name)=='function',
  'ItemStack required for tool dig parameters')
 local groups=node_def.groups or {}
 if node_def.diggable==false then return {diggable=false,reason='not_diggable'} end
 local immediate=immediate_times[groups.dig_immediate]
 if immediate~=nil then
  return {diggable=true,time=immediate,wear=0,group='dig_immediate'}
 end
 local capabilities=tool:get_tool_capabilities()
 local best,selected=nil,nil
 local level=groups.level or 0
 for group,cap in pairs(capabilities.groupcaps or {}) do
  local rating=groups[group]
  if type(rating)=='number' and rating>0 and
   type(cap)=='table' and type(cap.times)=='table' then
   local maxlevel=cap.maxlevel or 0
   local t=cap.times[rating]
   local diff=maxlevel-level
   if diff>=0 and validnonnegative(t) then
    -- The native Luanti engine reduces dig time for easier node levels.
    -- Keep the supported simple 2+ level rule explicit.
    local time=diff>1 and t/(diff*2) or t
    if not best or time<best.time then
     local uses=cap.uses or 0
     local wear=0
     if registry and registry.tools and registry.tools[tool:get_name()]
       and uses>0 then
      local total=uses*3^diff
      wear=ceil(65535/total)
     end
     best={diggable=true,time=time,wear=wear,group=group}
     selected=cap
    end
   end
  end
 end
 if best then return best end
 -- Items without capabilities are not automatically capable of breaking
 -- stone.  Nodes with no groups can be dug in the legacy instant API only.
 return {diggable=false,reason='unsupported_tool'}
end
return Digging
