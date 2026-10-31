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
 mcl_sounds='mods/CORE/mcl_sounds',
 mcl_autogroup='mods/CORE/mcl_autogroup',
 tga_encoder='mods/CORE/tga_encoder',
 vl_tuning='mods/CORE/vl_tuning',
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

-- Probe an actual foundational mod in another environment.
-- A failure here is diagnostic, not a false claim that VoxeLibre runs.
local probe=Engine.new({mapgen={seed=42,mg_name='v7',chunksize=5,mapgen_limit=31000},
 game_info={path=root,title='VoxeLibre'}})
local pe=Environment.new(probe)
probe.opts.executeMod=function(path,name) return pe:executeMod(path,name) end
probe.opts.modpaths={mcl_init=root..'/mods/CORE/mcl_init',
 mcl_util=root..'/mods/CORE/mcl_util',
 vl_unittests=root..'/mods/CORE/vl_unittests'}
local ok,err=pcall(probe.loadMod,probe,'mcl_init',probe.opts.modpaths.mcl_init)
if ok then
 ok,err=pcall(probe.loadMod,probe,'mcl_util',probe.opts.modpaths.mcl_util)
end
local report={
 '# VoxeLibre real Lua mod boot — Fase 4','',
 'Executed source files from pinned VoxeLibre Git checkout, not simulations.','',
 ('- Real modules loaded: **%d**'):format(#results),
 ('- Real source files executed: **%d**'):format(runner.read_count),
 ('- Registered chat commands: **%d**'):format(count),
 '- Modules: `mcl_colors`, `mcl_sounds`, `mcl_autogroup`, `tga_encoder`, `vl_tuning`, `mcl_init`.',
 '- Luanti source engine: **not used** in this integration test.',
 '- VoxeLibre gameplay: **NOT running** (only selected Lua modules loaded).',
 '',
 '## Next foundational mod: mcl_util',
 '',
 ('- Probe outcome: **%s**'):format(ok and 'loaded' or 'blocked'),
 '- Diagnostic:',
 '',
 '```text',
 tostring(ok and 'mcl_init + mcl_util loaded in isolation; this does not prove complete game compatibility'
  or err):gsub('[\r\n]+',' '):sub(1,2000),
 '```',
 '',
 'The probe is intentionally independent and does not alter VoxeLibre files.'
}
if arg and arg[2] then
 local out=assert(io.open(arg[2],'wb'))
 out:write(table.concat(report,'\n')..'\n');out:close()
end
print('mcl_util probe: '..(ok and 'LOADED' or ('BLOCKED '..tostring(err):sub(1,210))))
