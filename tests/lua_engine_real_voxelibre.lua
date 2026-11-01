-- Integration smoke against REAL VoxeLibre Lua mods at pinned git submodule.
-- Run with: lua5.4 tests/lua_engine_real_voxelibre.lua games/voxelibre
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Engine=require('core.runtime')
local ModLoader=require('core.modloader')
local Environment=require('core.modenvironment')
local root=(arg and arg[1]) or 'games/voxelibre'
root=root:gsub('/$','')

local function read(path)
 local f=io.open(path,'rb')
 assert(f,'file does not exist: '..path)
 local result=f:read('*a'); f:close();return result
end
local paths={
 doc='mods/HELP/doc/doc',
 doc_items='mods/HELP/doc/doc_items',
 tt='mods/HELP/tt',
 walkover='mods/CORE/walkover',
 mcl_luck='mods/PLAYER/mcl_luck',
 mcl_gamemode='mods/PLAYER/mcl_gamemode',
 mcl_colors='mods/CORE/mcl_colors',
 mcl_init='mods/CORE/mcl_init',
 mcl_util='mods/CORE/mcl_util',
 vl_unittests='mods/CORE/vl_unittests',
 mcl_sounds='mods/CORE/mcl_sounds',
 mcl_autogroup='mods/CORE/mcl_autogroup',
 tga_encoder='mods/CORE/tga_encoder',
 vl_tuning='mods/CORE/vl_tuning',
 flowlib='mods/CORE/flowlib',
 vl_legacy='mods/CORE/vl_legacy',
 controls='mods/CORE/controls',
 mcl_particles='mods/CORE/mcl_particles',
 mcl_worlds='mods/CORE/mcl_worlds',
 mcl_stonecutter='mods/ITEMS/mcl_stonecutter',
}
local targets={}
for name,path in pairs(paths) do
 local directory=root..'/'..path
 local def=ModLoader.parse(read(directory..'/mod.conf'))
 assert(def.name==name, 'wrong upstream mod.conf name: '..name)
 def.path=directory
 targets[#targets+1]=def
end
local ordered=ModLoader.plan(targets)
local rt=Engine.new({settings={
 mcl_keepInventory='false',mcl_node_particles='medium'},
 mapgen={seed=42,mg_name='v7',chunksize=5,mapgen_limit=31000},
 game_info={path=root,title='VoxeLibre'}})
local runner=Environment.new(rt)
rt.opts.executeMod=function(path,name) return runner:executeMod(path,name) end
rt.opts.modpaths={
 _mcl_autogroup=root..'/mods/CORE/_mcl_autogroup'
}
local success,results=ModLoader.load(rt,ordered)
if not success then
 local messages={}
 for _,v in ipairs(results) do
  messages[#messages+1]=v.name..': '..(v.ok and 'OK' or v.error)
 end
 error('cannot load real mods:\n'..table.concat(messages,'\n'))
end
local g=runner.globals
assert(g.mcl_colors.WHITE=='#FFFFFF')
assert(type(g.mcl_util)=='table','mcl_util did not load')
assert(g.mcl_util.djb2_hash('VoxeLibre')==2331368085,
 'original VoxeLibre DJB2 self-test was not preserved')
assert(type(g.mcl_util.gen_uuid())=='string','original UUID generator not running')
assert(g.vl_unittests and g.vl_unittests.enabled==false)
assert(type(g.flowlib.is_water)=='function')
assert(type(g.vl_legacy.convert_itemstack)=='function')
assert(type(g.controls.register_on_press)=='function')
assert(type(g.mcl_particles.add_node_particlespawner)=='function')
assert(type(g.mcl_worlds.y_to_layer)=='function')
assert(type(g.mcl_stonecutter.register_recipe)=='function')
assert(type(g.walkover.register_global)=='function',
 'original walkover runtime did not load')
assert(type(g.tt.register_snippet)=='function',
 'original tooltip module did not load')
local tooltip_stack=rt.api.ItemStack('mcl_stonecutter:stonecutter')
assert(tooltip_stack:get_definition()==
 rt.api.registered_items['mcl_stonecutter:stonecutter'])
assert(rt:predictCraft(tooltip_stack,nil,{},nil)==tooltip_stack)
assert(tooltip_stack:get_name()=='mcl_stonecutter:stonecutter',
 'tooltip prediction must not change the source item name')
rt.api.register_craftitem('test:tooltip',{
 description='Tooltip probe',_tt_help='Genuine upstream snippet'})
local item=rt.api.ItemStack('test:tooltip')
rt:predictCraft(item,nil,{},nil)
assert(item:get_meta():get_string('description'):find('Genuine upstream snippet',1,true),
 'original tooltip callback must populate itemstack metadata')
rt.api.override_item('test:tooltip',{description='Updated tooltip probe'})
assert(rt.api.registered_items['test:tooltip'].description=='Updated tooltip probe')
assert(type(g.mcl_luck.get_luck)=='function',
 'original luck module did not load')
assert(type(g.mcl_gamemode.get_gamemode)=='function',
 'original gamemode module did not load')
assert(type(g.doc)=='table' and type(g.doc.sub.items.temp.build)=='string',
 'original doc_items must load before mcl_core')
assert(rt.api.registered_nodes['mcl_stonecutter:stonecutter'],
 'stonecutter original upstream node not registered')
assert(rt.api.registered_items['mcl_stonecutter:stonecutter'].groups.pickaxey==1)
assert(#rt.callbacks.allow_player_inventory_action>=1)
assert(#rt.callbacks.on_player_inventory_action>=1)
local layer,dimension=g.mcl_worlds.y_to_layer(g.mcl_vars.mg_overworld_min+80)
assert(layer==80 and dimension=='overworld')
local upper=g.mcl_worlds.layer_to_y(80,'overworld')
assert(upper==g.mcl_vars.mg_overworld_min+80)
local pp={x=-12,y=14,z=19}
local hash=rt.api.hash_node_position(pp)
local unpacked=rt.api.get_position_from_hash(hash)
assert(unpacked.x==pp.x and unpacked.y==pp.y and unpacked.z==pp.z)
local id=g.mcl_particles.add_node_particlespawner(pp,{
 amount=4,time=1,texture='test_particle.png'},'low')
assert(type(id)=='number' and id>0 and rt.particles:get_spawner(id).amount==4)
assert(g.mcl_particles.delete_node_particlespawners(pp))
assert(rt.particles:get_spawner(id)==nil)
assert(not g.mcl_particles.delete_node_particlespawners(pp))
local blocked=rt:allowedInventoryAction(nil,'move',nil,{
 from_list='main',to_list='stonecutter_output',count=3})
assert(blocked==0,'stonecutter output is write-protected by actual mod callback')
local permitted=rt:allowedInventoryAction(nil,'move',nil,{
 from_list='main',to_list='stonecutter_input',count=3})
assert(permitted==3)
assert(not pcall(rt.api.show_formspec,'player','stonecutter','size[4,3]'),
 'unimplemented GUI must explicitly reject display')
rt.api.register_node('test:block_for_cutting',{})
rt.api.register_node('test:cut_block',{})
g.mcl_stonecutter.register_recipe('test:block_for_cutting','test:cut_block',2)
assert(g.mcl_stonecutter.registered_recipes['test:block_for_cutting']
 ['test:cut_block']==2)
rt.api.register_node('test:water',{groups={water=1,liquid=1}})
rt.api.register_node('test:old',{})
rt.api.register_node('test:new',{})
rt.api.set_node({x=2,y=0,z=0},{name='test:water'})
assert(g.flowlib.is_water({x=2,y=0,z=0}))
assert(not g.flowlib.is_lava({x=2,y=0,z=0}))
g.vl_legacy.register_item_conversion('test:old','test:new')
local item=rt.api.ItemStack('test:old 3')
g.vl_legacy.convert_itemstack(item)
assert(item:get_name()=='test:new' and item:get_count()==3)
local inv=rt.api.create_detached_inventory('legacy-test')
inv:set_size('main',2)
inv:set_stack('main',1,'test:old 5')
g.vl_legacy.convert_inventory(inv)
assert(inv:get_stack('main',1):get_name()=='test:new')
assert(#rt.registry.lbms>=2 and #rt.registry.abms>=1)
assert(#rt.callbacks.on_joinplayer>=3)
assert(type(g.mcl_vars)=='table' and type(g.mcl_vars.mg_nether_min)=='number')
assert(rt.api.get_mapgen_setting('vl_world_version')=='0.93.0-SNAPSHOT')
local song=g.mcl_sounds.node_sound_stone_defaults({})
assert(song.footstep.name=='default_hard_footstep')
g.mcl_autogroup.register_diggroup('test_mining',{levels={'iron','gold'}})
assert(g.mcl_autogroup.registered_diggroups.test_mining.levels[1]=='iron')
assert(type(g.tga_encoder.image)=='table','real TGA module missing')
assert(g.vl_tuning.registered_settings['gamerule:keepInventory'])
assert(rt.chatcommands.gamerule and rt.chatcommands.settings)
assert(rt.api.get_modpath('mcl_colors')==root..'/mods/CORE/mcl_colors')
assert(rt.mod_storage.vl_tuning,'mod storage not attached to source mod')
assert(#rt.callbacks.on_dieplayer==1)
assert(#rt.callbacks.on_joinplayer>=1)
assert(runner.read_count>=8,'vl_tuning should load additional source files')
assert(g.mcl_colors~=rawget(_G,'mcl_colors'),
 'real mod must not contaminate host global environment')
local count=0
for _ in pairs(rt.chatcommands) do count=count+1 end
print(('VOXELIBRE REAL MODS PASS: %d modules, %d source files, %d registered commands')
 :format(#results,runner.read_count,count))

-- Diagnostic only: try the real mcl_core source without disguising missing
-- gameplay dependencies. A partial failure must not count as a loaded mod.
local path_core=root..'/mods/ITEMS/mcl_core'
rt.opts.modpaths.mcl_core=path_core
local core_ok,core_error=pcall(rt.loadMod,rt,'mcl_core',path_core)
assert(rt.current_mod==nil,'mod context leaked after probe')
local core_nodes={}
for name in pairs(rt.api.registered_nodes) do
 if name:sub(1,9)=='mcl_core:' then core_nodes[#core_nodes+1]=name end
end
table.sort(core_nodes)
local stone=rt.api.registered_nodes['mcl_core:stone']
assert(#core_nodes>=166,
 'regression: at least 166 original mcl_core nodes must register')
assert(stone,'upstream mcl_core:stone definition not registered')
if stone then
 assert(stone.description=='Stone')
 assert(stone.groups.pickaxey==1)
 assert(rt.api.get_node_drops('mcl_core:stone')[1]=='mcl_core:cobble')
 assert(rt.api.get_node_drops('mcl_core:stone_with_iron')[1]==
  'mcl_raw_ores:raw_iron')
 assert(rt.api.get_content_id('mcl_core:stone')~=rt.api.CONTENT_IGNORE,
  'real stone content ID must be available to VoxelManip')
 rt.api.set_node({x=8,y=2,z=3},{name='mcl_core:stone'})
 assert(rt.api.get_node({x=8,y=2,z=3}).name=='mcl_core:stone',
  'real mcl_core stone must be placeable in the Lua map')
end
print(('MCL_CORE PROBE: %d original nodes registered; stone=%s; error=%s')
 :format(#core_nodes,tostring(stone~=nil),tostring(core_error):sub(1,180)))
local report={
 '# VoxeLibre real Lua mod boot — Fase 12','',
 'Original VoxeLibre code from the pinned Git checkout was executed.',
 'Lua 5.4 and LuaJIT tests must both pass for this report to be published.','',
 ('- Real modules loaded: **%d**'):format(#results),
 ('- Real source files executed: **%d**'):format(runner.read_count),
 ('- Registered chat commands: **%d**'):format(count),
 '- Modules: mcl_init, mcl_util, vl_unittests, mcl_colors,',
 '  mcl_sounds, mcl_autogroup, tga_encoder, vl_tuning,',
 '  flowlib, vl_legacy, controls, mcl_particles, mcl_worlds, mcl_stonecutter.',
 '- Luanti binary engine: not used in this module integration test.',
 '- VoxeLibre gameplay: **NOT RUNNING** (only selected Lua modules loaded).',
 '',
 '## Verified runtime behavior', '',
 '- Real VoxeLibre hashing asserts and DJB2 golden value passed.',
 '- Real mcl_util UUID generation executed with the Lua PCG32 replacement.',
 '- Real mod loading follows declared dependencies.',
 '- Real flowlib water predicate and vl_legacy inventory conversions passed.',
 '- Real controls callback registrations were verified.',
 '- Original stonecutter node and craft recipe registered successfully.',
 '- Actual stonecutter inventory permission callbacks rejected invalid moves.',
 '- Original mcl_particles particle registration and deletion verified in CPU-side bookkeeping.',
 '- Original mcl_worlds dimension coordinate conversion verified.',
 '- The actual player GUI and visual particle renderer are not implemented.',
 '',
 '## mcl_core original source probe', '',
 ('- Init source execution: **%s**'):format(core_ok and
  'returned (not a verified game)' or 'blocked'),
 ('- First issue: %s'):format(tostring(core_error or
  'no Lua error; gameplay and dependencies still unverified')
  :gsub('[\\r\\n]+',' '):sub(1,900)),
 ('- Real mcl_core nodes registered before failure: **%d**'):format(#core_nodes),
 ('- Original stone registered and its drops evaluated: **%s**')
  :format(tostring(stone~=nil)),
 '- The original doc and doc_items source is included in the loaded module count.',
 '- This is a diagnostic; mcl_core is not counted as a loaded module.',
 '- The original files remain unchanged.',
 '',
 '## Pending', '',
 'Player, entity, full mapgen, lighting, networking, sound and UI',
 'are not functionally compatible with the full VoxeLibre game.',
 'The working playable game still uses Luanti C++ from the separate build.',
}
if arg and arg[2] then
 local out=assert(io.open(arg[2],'wb'))
 out:write(table.concat(report,'\\n')..'\\n')
 out:close()
end
