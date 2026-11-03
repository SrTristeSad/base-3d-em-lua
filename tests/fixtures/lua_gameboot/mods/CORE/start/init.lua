assert(core.get_current_modname()=='boot_start')
assert(type(core.get_modpath('boot_second'))=='string')
assert(#core.get_modnames()==4)
local fn=assert(loadfile(core.get_modpath('boot_start')..'/helpers.lua'))
assert(_G.boot_helper_calls==nil)
assert(fn()=='compiled and executed original helper')
assert(_G.boot_helper_calls==1)
_G.boot_shared='base initialized'
core.register_node('boot_start:stone',{description='Original node'})
