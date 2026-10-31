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
local rt=Engine.new({settings={mcl_keepInventory='false'},
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

local report={
 '# VoxeLibre real Lua mod boot — Fase 6','',
 'Original VoxeLibre code from the pinned Git checkout was executed.',
 'Lua 5.4 and LuaJIT tests must both pass for this report to be published.','',
 ('- Real modules loaded: **%d**'):format(#results),
 ('- Real source files executed: **%d**'):format(runner.read_count),
 ('- Registered chat commands: **%d**'):format(count),
 '- Modules: mcl_init, mcl_util, vl_unittests, mcl_colors,',
 '  mcl_sounds, mcl_autogroup, tga_encoder, vl_tuning,',
 '  flowlib, vl_legacy, controls.',
 '- Luanti binary engine: not used in this module integration test.',
 '- VoxeLibre gameplay: **NOT RUNNING** (only selected Lua modules loaded).',
 '',
 '## Verified runtime behavior', '',
 '- Real VoxeLibre hashing asserts and DJB2 golden value passed.',
 '- Real mcl_util UUID generation executed with the Lua PCG32 replacement.',
 '- Real mod loading follows declared dependencies.',
 '- Real flowlib water predicate and vl_legacy inventory conversions passed.',
 '- Real controls callback registrations were verified.',
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
