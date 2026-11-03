-- Full-mod boot orchestration for the original VoxeLibre mod tree.
-- It does not replace the game's files or bypass missing Luanti APIs.
local ModLoader=require('core.modloader')
local ModEnvironment=require('core.modenvironment')
local Bootstrap={}
local function readonly_manifest(manifest)
 assert(type(manifest)=='table','game manifest must be a table')
 local result={}
 for i,mod in ipairs(manifest) do
  assert(type(mod)=='table' and type(mod.name)=='string' and
   type(mod.path)=='string','game manifest entry requires name and path')
  local hard,optional={},{}
  for n,value in ipairs(mod.depends or {}) do
   assert(type(value)=='string','invalid required mod dependency')
   hard[n]=value
  end
  for n,value in ipairs(mod.optional_depends or {}) do
   assert(type(value)=='string','invalid optional mod dependency')
   optional[n]=value
  end
  result[i]={name=mod.name,path=mod.path,
   depends=hard,optional_depends=optional}
 end
 return result
end
-- Accept a manifest of *all* game mods, not a handpicked list.
-- Status is explicit: incomplete boots return false and diagnostics.
-- Preserve the original Bootstrap.load interface for the existing full-game
-- CLI and tests. Required dependents of failed mods are never started.
function Bootstrap.load(runtime,manifest,opts)
 assert(type(runtime)=='table' and type(runtime.api)=='table' and
  type(runtime.loadMod)=='function','runtime required')
 opts=opts or {}
 assert(type(opts)=='table','game bootstrap options must be a table')
 local mods=readonly_manifest(manifest)
 local ordered=ModLoader.plan(mods)
 local environment=opts.environment or ModEnvironment.new(runtime)
 assert(type(environment.executeMod)=='function',
  'boot environment must execute original Lua source')
 assert(not runtime.current_mod,'cannot bootstrap during mod execution')
 runtime.opts.modpaths=runtime.opts.modpaths or {}
 for _,mod in ipairs(ordered) do
  runtime.opts.modpaths[mod.name]=mod.path
 end
 local previous=runtime.opts.executeMod
 runtime.opts.executeMod=function(path,name)
  return environment:executeMod(path,name)
 end
 local results,status={},{}
 local succeeded=true
 local passed,failed=0,0
 local initial_count=environment.read_count or 0
 for _,mod in ipairs(ordered) do
  local blocked
  for _,dep in ipairs(mod.depends or {}) do
   if status[dep]~='loaded' then blocked=dep;break end
  end
  if blocked then
   succeeded=false
   failed=failed+1
   status[mod.name]='blocked'
   results[#results+1]={name=mod.name,ok=false,status='blocked',
    dependency=blocked,error='required dependency not loaded: '..blocked}
  else
   local ok,err=pcall(runtime.loadMod,runtime,mod.name,mod.path)
   if ok then
    passed=passed+1
    status[mod.name]='loaded'
    results[#results+1]={name=mod.name,ok=true,status='loaded'}
   else
    succeeded=false
    failed=failed+1
    status[mod.name]='failed'
    results[#results+1]={name=mod.name,ok=false,status='failed',
     error=tostring(err)}
    if opts.continue_on_error~=true then break end
   end
  end
 end
 runtime.opts.executeMod=previous
 local callback_error
 if succeeded then
  local ok,err=pcall(runtime.finishMods,runtime)
  if not ok then
   succeeded=false
   callback_error=tostring(err)
  end
 end
 local report={
  success=succeeded,ordered=ordered,results=results,
  environment=environment,loaded_files=environment.files,
  executed_files=(environment.read_count or 0)-initial_count,
  discovered=#mods,passed=passed,failed=failed,
  callback_error=callback_error,callbacks_completed=succeeded
 }
 return succeeded,report
end

-- Filesystem discovery across separate game mod roots using the SAME
-- boot engine. Lua itself does not need to recurse platform directories.
function Bootstrap.start(runtime,roots,fs,opts)
 opts=opts or {}
 assert(type(opts)=='table','boot options must be a table')
 local ordered=ModLoader.discover_roots(roots,fs)
 local success,report=Bootstrap.load(runtime,ordered,{
  continue_on_error=opts.continue_on_error~=false,
  environment=opts.environment
 })
 local names={}
 for i,mod in ipairs(report.ordered) do names[i]=mod.name end
 return {
  ok=success,order=names,results=report.results,
  loaded=report.passed,attempted=#report.results,total=report.discovered,
  files_executed=report.executed_files,
  callback_error=report.callback_error,
  callbacks_completed=report.callbacks_completed,
  environment=report.environment
 }
end
return Bootstrap
