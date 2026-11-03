-- Game boot in one integration batch: multi-root dependencies, original
-- source execution, loadfile/dofile compatibility and blocked dependents.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Loader=require('core.modloader')
local Environment=require('core.modenvironment')
local Boot=require('core.gamebootstrap')
local root='tests/fixtures/lua_gameboot/mods'
local paths={
 core=root..'/CORE',items=root..'/ITEMS',player=root..'/PLAYER'
}
local discovered={
 [paths.core]={paths.core..'/start',paths.core..'/alone'},
 [paths.items]={paths.items..'/second'},
 [paths.player]={paths.player..'/third'}
}
local fs={}
function fs.walk(r) return discovered[r] or {} end
function fs.read(path)
 local f=io.open(path,'rb')
 if not f then return nil end
 local s=f:read('*a'); f:close()
 return s
end
local roots={paths.player,paths.core,paths.items}
local order=Loader.discover_roots(roots,fs)
local names={}
for i,mod in ipairs(order) do names[i]=mod.name end
assert(table.concat(names,',')=='boot_alone,boot_start,boot_second,boot_third')
assert(not pcall(Loader.discover_roots,{},fs))
assert(not pcall(Loader.discover_roots,{paths.core},{}))
local repeated={walk=function() return {paths.core..'/start'} end,read=fs.read}
assert(not pcall(Loader.discover_roots,{paths.core,paths.items},
 {walk=function(path)
  return {paths.core..'/start',paths.items..'/second',
          paths.core..'/start'}
 end,read=function(path)
  if path:find('second/mod.conf',1,true) then
   return 'name = boot_start\n'
  end
  return fs.read(path)
 end}),'duplicate mod name must not silently override an earlier directory')
-- Entire game registry visible to earlier mods BEFORE their init.lua runs.
local rt=Runtime.new()
local saved=function() error('previous executeMod should be temporarily replaced') end
rt.opts.executeMod=saved
local report=Boot.start(rt,roots,fs)
assert(report.ok and report.callbacks_completed)
assert(report.total==4 and report.loaded==4 and report.attempted==4)
assert(report.files_executed==6,'init + original helper source count')
assert(#report.results==4 and #report.order==4)
assert(rt.current_mod==nil and rt.opts.executeMod==saved)
assert(rt.api.get_modnames()[1]=='boot_alone')
assert(rt.api.get_modnames()[4]=='boot_third')
assert(rt.api.get_modpath('boot_third')==paths.player..'/third')
assert(rt.api.registered_nodes['boot_start:stone'])
assert(rt.api.registered_nodes['boot_second:brick'])
assert(rt.api.registered_craftitems['boot_alone:gem'])
assert(report.environment.globals.boot_ready==1)
assert(report.environment.globals.boot_shared=='second initialized')
assert(report.environment.globals.boot_extra=='executed')
assert(report.environment.globals.boot_helper_calls==1)
assert(rawget(_G,'boot_shared')==nil,'host globals must remain isolated')
assert(rawget(_G,'boot_ready')==nil,'host callbacks must remain isolated')
local env=report.environment
assert(#env.files==6 and env.read_count==6)
assert(not pcall(env.globals.loadfile,'lua-engine/core/runtime.lua'))
assert(not pcall(env.globals.dofile,'lua-engine/core/runtime.lua'))
assert(not pcall(env.globals.loadfile,paths.core..'/../ITEMS/second/init.lua'))
assert(not pcall(env.globals.loadfile,paths.core..'/start/helpers.txt'))
assert(not pcall(env.globals.loadfile,paths.core..'/start/helpers.lua','b'))
local nofile,reason=env.globals.loadfile(paths.core..'/start/no-such.lua')
assert(nofile==nil and type(reason)=='string')
local before=env.read_count
local extra=assert(env.globals.loadfile(paths.core..'/start/helpers.lua','t'))
assert(env.read_count==before,'loadfile compiles without executing')
assert(extra()=='compiled and executed original helper')
assert(env.read_count==before+1)
-- On failure: skip mandatory dependents, continue to unrelated mods.
local failed=Runtime.new()
local callback_count=0
failed.api.register_on_mods_loaded(function() callback_count=callback_count+1 end)
local faulty=Environment.new(failed)
local raw_exec=faulty.executeMod
function faulty:executeMod(path,name)
 if name=='boot_second' then error('simulated original mod failure') end
 return raw_exec(self,path,name)
end
local incomplete=Boot.start(failed,roots,fs,{
 continue_on_error=true,environment=faulty})
assert(incomplete.ok==false and incomplete.callbacks_completed==false)
assert(incomplete.loaded==2 and incomplete.total==4)
assert(incomplete.attempted==4 and callback_count==0)
assert(incomplete.results[1].status=='loaded')
assert(incomplete.results[2].status=='loaded')
assert(incomplete.results[3].status=='failed')
assert(incomplete.results[3].error:find('simulated original mod failure',1,true))
assert(incomplete.results[4].status=='blocked')
assert(incomplete.results[4].dependency=='boot_second')
assert(failed.current_mod==nil and failed.opts.executeMod==nil)
assert(failed.api.registered_nodes['boot_start:stone']~=nil)
assert(failed.api.registered_nodes['boot_second:brick']==nil)
-- Stop-on-error mode does not run later modules or mods_loaded.
local stopped=Runtime.new()
local stopped_env=Environment.new(stopped)
function stopped_env:executeMod(path,name)
 if name=='boot_second' then error('stop here') end
 return raw_exec(self,path,name)
end
local early=Boot.start(stopped,roots,fs,{
 continue_on_error=false,environment=stopped_env})
assert(early.ok==false and early.attempted==3)
assert(early.loaded==2 and early.callbacks_completed==false)
-- Failure of on_mods_loaded must be reported without a false success.
local callback_runtime=Runtime.new()
callback_runtime.api.register_on_mods_loaded(function()
 error('original post-init error')
end)
local after=Boot.start(callback_runtime,roots,fs)
assert(after.ok==false and after.loaded==4 and after.total==4)
assert(after.callback_error:find('original post-init error',1,true))
assert(callback_runtime.current_mod==nil)
-- The directory walker must not need to recurse inside Lua.
print('ORIGINAL GAME MULTI-ROOT BOOT AND SCOPED LUA SOURCE PASS')
