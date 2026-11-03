assert(core.get_current_modname()=='boot_second')
assert(_G.boot_shared=='base initialized')
_G.boot_shared='second initialized'
core.register_node('boot_second:brick',{description='Dependent node'})
core.register_on_mods_loaded(function()
 _G.boot_ready=(_G.boot_ready or 0)+1
end)
