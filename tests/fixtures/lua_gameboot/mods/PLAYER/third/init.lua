assert(core.get_current_modname()=='boot_third')
assert(_G.boot_shared=='second initialized')
dofile(core.get_modpath('boot_third')..'/extra.lua')
assert(_G.boot_extra=='executed')
