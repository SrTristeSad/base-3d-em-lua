local core=minetest
assert(core.get_current_modname()=='b_game')
assert(boot_order and boot_order[1]=='a_core')
assert(core.registered_nodes['test_boot:stone'])
boot_order[#boot_order+1]='b_game'
core.register_craftitem('test_boot:token',{description='Boot Token'})
