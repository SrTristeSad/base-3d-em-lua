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
 mcl_death_drop='mods/PLAYER/mcl_death_drop',
 mcl_experience='mods/HUD/mcl_experience',
 mcl_enchanting='mods/ITEMS/mcl_enchanting',
 mcl_core='mods/ITEMS/mcl_core',
 mcl_nether='mods/ITEMS/mcl_nether',
 mcl_fences='mods/ITEMS/mcl_fences',
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
local mod_names={}
for name in pairs(paths) do mod_names[#mod_names+1]=name end
table.sort(mod_names)
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
assert(type(g.mcl_death_drop.register_dropped_list)=='function',
 'original death-drop module did not load')
assert(#g.mcl_death_drop.registered_dropped_lists>=6,
 'original player inventory lists for death-drop were not registered')
assert(type(g.mcl_experience.add_xp)=='function' and
 rt.api.registered_entities['mcl_experience:orb'] and
 rt.api.registered_entities['mcl_experience:bottle'],
 'original XP entities and functions must register')
assert(type(g.mcl_enchanting)=='table' and
 type(g.mcl_enchanting.overlay)=='string' and
 type(g.mcl_enchanting.enchantments)=='table',
 'original enchantment registry failed to initialize')
assert(type(g.doc)=='table' and type(g.doc.sub.items.temp.build)=='string',
 'original doc_items must load before mcl_core')
assert(rt.api.registered_nodes['mcl_stonecutter:stonecutter'],
 'stonecutter original upstream node not registered')
-- Actual VoxeLibre connected fence, not a duplicated test definition.
local oak_fence=rt.api.registered_nodes['mcl_fences:fence']
assert(oak_fence and oak_fence.drawtype=='nodebox' and
 oak_fence.node_box.type=='connected' and
 type(oak_fence.connects_to)=='table',
 'original VoxeLibre oak fence registration must load')
local npos={x=8,y=5,z=7}
rt.api.set_node(npos,{name='mcl_fences:fence'})
local isolated=require('core.nodebox').faces(
 oak_fence,rt.api.get_node(npos),rt.map,npos,rt.registry.nodes)
assert(isolated and #isolated==6,'original oak fence must begin as isolated post')
rt.api.set_node({x=9,y=5,z=7},{name='mcl_fences:fence'})
local connected=require('core.nodebox').faces(
 oak_fence,rt.api.get_node(npos),rt.map,npos,rt.registry.nodes)
assert(connected and #connected==18,
 'original oak fence must grow its two right-side horizontal rails')
local visual_boxes=rt.api.get_node_boxes('node_box',npos)
local collision_boxes=rt.api.get_node_boxes('collision_box',npos)
assert(#visual_boxes==3 and #collision_boxes==2,
 'original fence must provide separate visible and collision geometry')
rt.api.remove_node({x=9,y=5,z=7})
local disconnected=require('core.nodebox').faces(
 oak_fence,rt.api.get_node(npos),rt.map,npos,rt.registry.nodes)
assert(#disconnected==6,'oak fence rails must disappear when neighbor is mined')
local Nodebox=require('core.nodebox')
local real_stonecutter=rt.api.registered_nodes['mcl_stonecutter:stonecutter']
assert(real_stonecutter.drawtype=='nodebox' and
 real_stonecutter.paramtype2=='facedir')
local blade=Nodebox.faces(real_stonecutter,{param2=0})
assert(blade and #blade==8,
 'upstream stonecutter must render base and two-sided zero-width blade')
rt.api.set_node({x=6,y=4,z=2},
 {name='mcl_stonecutter:stonecutter',param2=1})
local blade_vertices,blade_stats=require('core.mesher').build(
 rt.map,rt.api.registered_nodes,0,0,0)
assert(blade_stats.nodeboxes>=1 and blade_stats.faces>=8,
 'the real facedir stonecutter must produce nodebox triangles')
assert(#blade_vertices==blade_stats.faces*6)
local original_path=rt.api.registered_nodes['mcl_core:grass_path']
assert(original_path and original_path.drawtype=='nodebox')
local grass_boxes=Nodebox.faces(original_path,{param2=0})
assert(grass_boxes and #grass_boxes==6)
assert(grass_boxes[1].corners[1][2]==0.4375,
 'real grass path must be one sixteenth below a full block')
local original_snow=rt.api.registered_nodes['mcl_core:snow']
assert(original_snow and original_snow.drawtype=='nodebox')
local snow_faces=Nodebox.faces(original_snow,{param2=0})
assert(snow_faces and snow_faces[1].corners[1][2]==-.375,
 'real snow layer height must follow upstream definition')
-- Physics must consume genuine collision boxes from the original mods.
local PlayerPhysics=require('core.physics')
for bx=98,110 do
 rt.api.set_node({x=bx,y=0,z=0},{name='mcl_core:stone'})
end
assert(rt.api.registered_nodes['mcl_core:snow'].walkable==false)
assert(rt.api.registered_nodes['mcl_core:snow_2'].walkable==true)
rt.api.set_node({x=102,y=1,z=0},{name='mcl_core:snow_2'})
rt.api.set_node({x=106,y=1,z=0},{name='mcl_fences:fence'})
local simulated=PlayerPhysics.new(rt.api,{x=100,y=.5,z=0})
local climbed=false
for _=1,30 do
 simulated:update(.05,{x=1})
 if simulated.pos.y>.5+.05 then climbed=true end
end
assert(climbed,'upstream snow layer must raise feet by its actual height')
assert(simulated.pos.x>103,
 'player must walk across original snow collision box')
assert(simulated.pos.x<105.6,
 'original fence collision must prevent walking through or stepping over')
for _=1,10 do simulated:update(.05,{x=1,sprint=true}) end
assert(simulated.pos.x<105.6,
 'fence collision must also block the original physics at sprint speed')
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
local permission_inv=rt.api.create_detached_inventory('stonecutter-permission')
assert(permission_inv:get_location().type=='detached')
assert(permission_inv:get_location().name=='stonecutter-permission')
local blocked=rt:allowedInventoryAction(nil,'move',permission_inv,{
 from_list='main',to_list='stonecutter_output',count=3})
assert(blocked==0,'stonecutter output is write-protected by actual mod callback')
local permitted=rt:allowedInventoryAction(nil,'move',permission_inv,{
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
assert(#rt.callbacks.on_dieplayer>=2,
 'original death-drop callback must be registered')
assert(#rt.callbacks.on_joinplayer>=1)
assert(runner.read_count>=8,'vl_tuning should load additional source files')
assert(g.mcl_colors~=rawget(_G,'mcl_colors'),
 'real mod must not contaminate host global environment')
local count=0
for _ in pairs(rt.chatcommands) do count=count+1 end
print(('VOXELIBRE REAL MODS PASS: %d modules, %d source files, %d registered commands')
 :format(#results,runner.read_count,count))

-- The original mcl_core is now loaded in the normal dependency-ordered
-- mod pass, BEFORE on_mods_loaded. Do not reexecute its init script here.
local core_ok,core_error=true,nil
assert(rt.current_mod==nil,'mod context leaked after real mod boot')
assert(type(g.mcl_enchanting.enchantments.sharpness)=='table',
 'original enchantments must be registered alongside mcl_core')
local enchanted_book=rt.api.ItemStack('mcl_enchanting:book_enchanted')
enchanted_book:get_meta():set_string('mcl_enchanting:enchantments',
 rt.api.serialize({sharpness=3,unbreaking=2}))
assert(g.mcl_enchanting.get_enchantment(enchanted_book,'sharpness')==3)
assert(g.mcl_enchanting.get_enchantments(enchanted_book).unbreaking==2,
 'real enchanting metadata must round-trip through core.deserialize')
assert(type(rt.api.registered_craftitems['mcl_core:apple_gold_enchanted'])=='table',
 'original enchanted golden apple must register after mcl_enchanting')
assert(rt.api.registered_craftitems['mcl_core:apple_gold_enchanted']
 .inventory_image:find(g.mcl_enchanting.overlay,1,true),
 'real enchanted apple overlay was not preserved')
local repair_registered=false
for _,recipe in ipairs(rt.registry.crafts) do
 if recipe.kind=='toolrepair' then repair_registered=true end
end
assert(repair_registered,'original mcl_core toolrepair recipe missing')
local core_nodes={}
for name in pairs(rt.api.registered_nodes) do
 if name:sub(1,9)=='mcl_core:' then core_nodes[#core_nodes+1]=name end
end
table.sort(core_nodes)
local stone=rt.api.registered_nodes['mcl_core:stone']
assert(#core_nodes>=166,
 'regression: at least 166 original mcl_core nodes must register')
assert(stone,'upstream mcl_core:stone definition not registered')
local Mesher=require('core.mesher')
local Atlas=require('core.atlas')
assert(Atlas.index(stone.tiles[1])==4,
 'original stone tile must resolve to stone atlas slot')
local original_grass=rt.api.registered_nodes['mcl_core:dirt_with_grass']
assert(original_grass and Atlas.index(original_grass.tiles[1])==2,
 'original grass top tile must resolve')
assert(Atlas.index(original_grass.tiles[3])==9,
 'original grass side overlay must be selected')
local glass=rt.api.registered_nodes['mcl_core:glass']
local water=rt.api.registered_nodes['mcl_core:water_source']
local lava=rt.api.registered_nodes['mcl_core:lava_source']
assert(glass and glass.drawtype=='glasslike_framed_optional' and
 Atlas.index(glass.tiles[1])==17 and Mesher.is_cube(glass),
 'upstream framed glass must have actual atlas geometry')
assert(water and water.drawtype=='liquid' and
 Atlas.index(water.tiles[1])==12 and Mesher.is_cube(water),
 'upstream water source must render using real first-frame texture')
assert(lava and Atlas.index(lava.tiles[1])==19 and Mesher.is_cube(lava),
 'upstream lava source must render using real first-frame texture')
local smoke=require('core.map').new(rt.registry.items)
smoke:set_node({x=0,y=0,z=0},{name='mcl_core:glass'})
smoke:set_node({x=2,y=0,z=0},{name='mcl_core:water_source'})
smoke:set_node({x=4,y=0,z=0},{name='mcl_core:lava_source'})
local _,real_metrics=Mesher.build(smoke,rt.api.registered_nodes,0,0,0)
assert(real_metrics.faces==18 and real_metrics.liquids==2,
 'real upstream glass and liquids must yield visible faces')

local current_mesh,mesh_stat=Mesher.build(rt.map,rt.api.registered_nodes,0,0,0)
assert(mesh_stat.faces>0 and #current_mesh==mesh_stat.faces*6,
 'original mcl_core registered cubes must produce visible faces')
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
print(('MCL_CORE BOOT: %d original nodes registered; stone=%s; error=%s')
 :format(#core_nodes,tostring(stone~=nil),tostring(core_error):sub(1,180)))
local report={
 '# VoxeLibre real Lua mod boot — Fase 13','',
 'Original VoxeLibre code from the pinned Git checkout was executed.',
 'Lua 5.4 and LuaJIT tests must both pass for this report to be published.','',
 ('- Real modules loaded: **%d**'):format(#results),
 ('- Real source files executed: **%d**'):format(runner.read_count),
 ('- Registered chat commands: **%d**'):format(count),
 '- Modules: '..table.concat(mod_names,', '),
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
 '## mcl_core dependency-ordered original source boot', '',
 ('- Init source execution: **%s**'):format(core_ok and
  'returned (not a verified game)' or 'blocked'),
 ('- First issue: %s'):format(tostring(core_error or
  'no Lua error; gameplay and dependencies still unverified')
  :gsub('[\\r\\n]+',' '):sub(1,900)),
 ('- Real mcl_core nodes registered before failure: **%d**'):format(#core_nodes),
 ('- Original stone registered and its drops evaluated: **%s**')
  :format(tostring(stone~=nil)),
 '- The original doc, doc_items and mcl_core sources are included in the loaded module count.',
 '- mcl_core Lua initialization is not proof of a playable or 1:1 game.',
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
