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
function Bootstrap.load(runtime,manifest,opts)
 assert(type(runtime)=='table' and type(runtime.api)=='table' and
  type(runtime.loadMod)=='function','runtime required')
 opts=opts or {}
 assert(type(opts)=='table','game bootstrap options must be a table')
 local mods=readonly_manifest(manifest)
 local ordered=ModLoader.plan(mods)
 local environment=ModEnvironment.new(runtime)
 assert(runtime.opts.executeMod==nil,
  'runtime already has a mod file executor')
 runtime.opts.executeMod=function(path,name)
  return environment:executeMod(path,name)
 end
 local success,results=ModLoader.load(runtime,ordered,{
  continue_on_error=opts.continue_on_error==true
 })
 local report={success=success,ordered=ordered,results=results,
  environment=environment,loaded_files=environment.files,
  executed_files=environment.read_count,discovered=#mods,
  passed=0,failed=0}
 for _,status in ipairs(results) do
  if status.ok then report.passed=report.passed+1
  else report.failed=report.failed+1 end
 end
 return success,report
end
return Bootstrap
