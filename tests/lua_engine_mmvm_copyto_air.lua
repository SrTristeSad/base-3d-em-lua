-- Luanti 5.18 src/voxel.cpp:231-246 and src/mapblock.cpp:224-234.
-- copyTo skips CONTENT_IGNORE, but copies known AIR and its parameters.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Map=require('core.map')
local Buffer=require('core.mapgen_voxelbuffer')
local Chunk=require('core.mapgen_chunk')
local Runtime=require('core.runtime')
local function eq(actual,expected,label)
 assert(actual==expected,(label or 'mismatch')..': '..
  tostring(actual)..' ~= '..tostring(expected))
end
local function runtime()
 local rt=Runtime.new({mapgen={seed=95,mg_name='v7'},
  active_block_range=0})
 rt.api.register_node('test:marker',{})
 return rt
end
local geom=Chunk.geometry({x=-1,y=-1,z=0},1)
local block='-1,-1,0'
local marker={x=-16,y=-16,z=0}
local known_air={x=-16,y=-14,z=0}
local lit_air={x=-16,y=-13,z=0}
local untouched={x=-15,y=-14,z=0}
local world=runtime()
local map=world.map
assert(map:create_blank_block(block))
map:set_node(marker,{name='test:marker',param1=7,param2=9})
local stage=Buffer.new(map,geom)
eq(stage:initialEmerge(false),1)
eq(stage:get_node(known_air).name,'ignore','before terrain')
stage:begin_terrain_column(-16,0,-16,-1)
eq(stage:get_node(known_air).name,'air','air column replaces IGNORE')
eq(stage:get_node(marker).name,'test:marker','imported node preserved')
eq(stage:get_node(marker).param2,9)
eq(stage:get_node(untouched).name,'ignore','other column stays unknown')
eq(stage:get_flags(known_air),0,'known AIR has no NO_DATA flag')
assert(stage:set_node(lit_air,{name='air',param1=37,param2=11}))
eq(stage:get_node(lit_air).param1,37,
 'AIR parameters cannot be lost to a compressed column')
eq(stage:commit_core(),1,'explicit overlay write count')
eq(stage.core_air_copied,14,'other 14 cells copied as AIR')
eq(map:get_node(known_air).name,'air','copyTo must copy known AIR')
eq(map:get_node(marker).name,'test:marker')
eq(map:get_node(untouched).name,'ignore',
 'copyTo skips unknown CONTENT_IGNORE cells')
eq(map:get_node(lit_air).param1,37)
eq(map:get_node(lit_air).param2,11)
eq(map.count,16,'one known column transferred to blank block')
assert(map:finish_blank_block(block))
eq(map:get_node(untouched).name,'air','generated block defaults to AIR')
eq(map:get_node(lit_air).param1,37)
eq(map:get_node(lit_air).param2,11)
eq(map:get_node(marker).param2,9)
eq(map.count,2,'only default AIR(0,0) becomes sparse')
assert(map.nodes['-16,-13,0'],'parameterized AIR retained')
assert(not map.nodes['-16,-14,0'],'zero-parameter AIR compressed')
-- Segmented persist/restart: a parameterized AIR is still a real MapNode.
local disk={files={}}
function disk.read(path)
 return disk.files[path],disk.files[path] and nil or 'not found'
end
function disk.write_atomic(path,data) disk.files[path]=data;return true end
map.last_active[block]=world.clock
local store=world:attachMapBlockStore(disk,'mmvm95')
assert(store:flush())
local reboot=runtime()
local reload=reboot:attachMapBlockStore(disk,'mmvm95')
assert(reload:emerge(block))
eq(reboot.map:get_node(marker).name,'test:marker')
eq(reboot.map:get_node(marker).param1,7)
eq(reboot.map:get_node(lit_air).name,'air')
eq(reboot.map:get_node(lit_air).param1,37)
eq(reboot.map:get_node(lit_air).param2,11)
-- For already generated air blocks, a nonzero param also cannot vanish.
local ordinary=Map.new()
ordinary.last_active['0,0,0']=0
local p={x=0,y=0,z=0}
ordinary:set_node(p,{name='air',param1=6,param2=10})
eq(ordinary:get_node(p).param1,6)
assert(ordinary.revisions['0,0,0'],
 'AIR param write must bump the revision used by MMVManip preflight')
ordinary:set_node(p,{name='air',param1=0,param2=0})
eq(ordinary:get_node(p).param2,0)
assert(not ordinary.nodes['0,0,0'])
-- A concurrent write must reject the whole staged copy before any AIR.
local concurrent=Map.new()
assert(concurrent:create_blank_block(block))
local other=Buffer.new(concurrent,geom)
other:initialEmerge(false)
other:begin_terrain_column(-16,0,-16,-1)
concurrent:set_node(untouched,{name='test:marker'})
assert(not pcall(other.commit_core,other))
eq(concurrent:get_node(known_air).name,'ignore',
 'failed preflight must not leave partial AIR copied')
eq(concurrent:get_node(untouched).name,'test:marker')
print('LUANTI MMVM COPYTO KNOWN AIR AND PARAMETER PRESERVATION PASS')
