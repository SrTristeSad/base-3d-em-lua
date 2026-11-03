local core=minetest
assert(core.get_current_modname()=='a_core')
boot_order=boot_order or {}
boot_order[#boot_order+1]='a_core'
core.register_node('test_boot:stone',{description='Boot Fixture Stone'})
core.register_on_mods_loaded(function()
 assert(core.registered_craftitems['test_boot:token'])
 boot_hooks_fired=true
end)
