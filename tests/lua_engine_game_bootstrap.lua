-- Full-mod loader orchestration with actual Lua mod files and callbacks.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Bootstrap=require('core.gamebootstrap')
local Loader=require('core.modloader')
local root='tests/fixtures/boot_game/mods/'
local mods={
 {name='b_game',path=root..'b_game',depends={'a_core'}},
 {name='a_core',path=root..'a_core',depends={}}
}
local rt=Runtime.new()
local success,report=Bootstrap.load(rt,mods)
assert(success and report.success)
assert(report.discovered==2 and report.passed==2 and report.failed==0)
assert(report.executed_files==2 and #report.loaded_files==2)
assert(report.ordered[1].name=='a_core')
assert(report.ordered[2].name=='b_game')
assert(report.results[1].ok and report.results[2].ok)
assert(rt.api.registered_nodes['test_boot:stone'])
assert(rt.api.registered_craftitems['test_boot:token'])
assert(report.environment.globals.boot_order[1]=='a_core')
assert(report.environment.globals.boot_order[2]=='b_game')
assert(report.environment.globals.boot_hooks_fired==true)
assert(rt.current_mod==nil)
local broken={
 {name='a_core',path=root..'a_core',depends={}},
 {name='c_broken',path='tests/fixtures/boot_broken/c_broken',
  depends={'a_core'}},
 {name='b_game',path=root..'b_game',depends={'a_core'}}
}
local retry=Runtime.new()
local ok,diag=Bootstrap.load(retry,broken,{continue_on_error=true})
assert(not ok and not diag.success and diag.discovered==3)
assert(diag.passed==2 and diag.failed==1 and #diag.results==3)
assert(diag.results[3].name=='c_broken')
assert(diag.results[3].error:find('deliberately blocked mod',1,true))
assert(diag.environment.globals.boot_hooks_fired==nil,
 'mods_loaded callbacks must not run after incomplete full-game boot')
local quick=Runtime.new()
local failed,short=Bootstrap.load(quick,broken,{continue_on_error=false})
assert(not failed and #short.results==3 or
 not failed and short.failed==1)
-- Input manifest is not mutated in planning or loading.
assert(mods[1].name=='b_game' and mods[1].depends[1]=='a_core')
assert(not pcall(Loader.plan,{{name='bad',path='missing',depends={'ghost'}}}))
print('FULL GAME LUA BOOTSTRAP AND FAILURE DIAGNOSTICS PASS')
