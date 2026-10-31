-- Mod ordering from Luanti mod.conf: hard dependencies, optional dependencies.
-- The caller provides read(path), walk(root) and run(mod), allowing tests
-- without filesystem access and without mutating the VoxeLibre checkout.
local Loader={}
local function csv(s)
 local out,seen={},{}
 for name in tostring(s or ''):gmatch('[%w_%-]+') do
  if not seen[name] then out[#out+1]=name;seen[name]=true end
 end
 return out
end
function Loader.parse(content,legacy)
 local config={}
 assert(type(content)=='string','mod.conf content must be text')
 for line in (content..'\n'):gmatch('(.-)\n') do
  local key,value=line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
  if key and key~='' then
   config[key]=value
  end
 end
 local hard,optional=csv(config.depends),csv(config.optional_depends)
 if legacy and config.depends==nil then
  hard,optional={},{}
  local hseen,oseen={},{}
  for line in (legacy..'\n'):gmatch('(.-)\n') do
   local entry=line:match('^%s*(.-)%s*$')
   local opt=entry:sub(-1)=='?'
   if opt then entry=entry:sub(1,-2) end
   local name=entry:match('^([%w_%-]+)$')
   if name then
    if opt then
     if not oseen[name] then optional[#optional+1]=name;oseen[name]=true end
    elseif not hseen[name] then
     hard[#hard+1]=name;hseen[name]=true
    end
   end
  end
 end
 return {name=config.name,depends=hard,optional_depends=optional,
  description=config.description or ''}
end
function Loader.plan(mods)
 assert(type(mods)=='table','mods must be an array')
 local indexed={}
 for _,mod in ipairs(mods) do
  assert(type(mod)=='table' and type(mod.name)=='string'
   and mod.name:match('^[%w_%-]+$') and type(mod.path)=='string',
   'each mod must have name and path')
  assert(not indexed[mod.name],'duplicate mod: '..mod.name)
  indexed[mod.name]=mod
 end
 local sorted={}
 for name in pairs(indexed) do sorted[#sorted+1]=name end
 table.sort(sorted)
 local visiting,loaded={},{}
 local ordered={}
 local function dfs(name,stack)
  if loaded[name] then return end
  if visiting[name] then
   error('circular mod dependency: '..stack..' -> '..name,0)
  end
  local mod=indexed[name]
  assert(mod,'missing required mod: '..name)
  visiting[name]=true
  local deps={}
  local seen={}
  for _,need in ipairs(mod.depends or {}) do
   assert(indexed[need],'mod '..name..' is missing required dependency '..need)
   if not seen[need] then deps[#deps+1]=need;seen[need]=true end
  end
  for _,need in ipairs(mod.optional_depends or {}) do
   if indexed[need] and not seen[need] then
    deps[#deps+1]=need;seen[need]=true
   end
  end
  table.sort(deps)
  for _,need in ipairs(deps) do dfs(need,stack..' -> '..name) end
  visiting[name]=nil
  loaded[name]=true
  ordered[#ordered+1]=mod
 end
 for _,name in ipairs(sorted) do dfs(name,'root') end
 return ordered
end
-- fs.walk(root) -> array of directory paths that contain mod.conf,
-- fs.read(path) -> text or nil. No guessed paths, no implicit execution.
function Loader.discover(root,fs)
 assert(type(root)=='string' and type(fs)=='table'
  and type(fs.walk)=='function' and type(fs.read)=='function')
 local result={}
 for _,path in ipairs(fs.walk(root)) do
  local content=fs.read(path..'/mod.conf')
  if content then
   local config=Loader.parse(content,fs.read(path..'/depends.txt'))
   assert(config.name,'mod.conf missing name: '..path)
   config.path=path
   result[#result+1]=config
  end
 end
 return Loader.plan(result)
end
function Loader.load(runtime,ordered,opts)
 assert(runtime and runtime.loadMod and type(ordered)=='table')
 opts=opts or {}
 -- Dependency mod paths must be visible even before each mod loads.
 runtime.opts.modpaths=runtime.opts.modpaths or {}
 for _,mod in ipairs(ordered) do
  runtime.opts.modpaths[mod.name]=mod.path
 end
 local results={}
 for _,mod in ipairs(ordered) do
  local ok,err=pcall(runtime.loadMod,runtime,mod.name,mod.path)
  if not ok then
   results[#results+1]={name=mod.name,ok=false,error=tostring(err)}
   if not opts.continue_on_error then
    return false,results
   end
  else
   results[#results+1]={name=mod.name,ok=true}
  end
 end
 if #results==#ordered and
    not (opts.continue_on_error and
     (function()
       for _,v in ipairs(results) do if not v.ok then return true end end
       return false
      end)()) then
  runtime:finishMods()
 end
 local all=true
 for _,v in ipairs(results) do if not v.ok then all=false end end
 return all,results
end
return Loader
