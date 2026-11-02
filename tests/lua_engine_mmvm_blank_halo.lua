-- Luanti 5.18 MMVManip::blitBackAll: non-generated halo MapBlocks
-- with existing revisions still accept non-CONTENT_IGNORE voxels.
-- The Lua streaming adapter must mirror partial content into sidecars.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Map=require('core.map')
local Runtime=require('core.runtime')
local Chunk=require('core.mapgen_chunk')
local Buffer=require('core.mapgen_voxelbuffer')
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
end
local function disk()
 local fs={files={}}
 function fs.read(path)
  return fs.files[path],fs.files[path] and nil or 'not found'
 end
 function fs.write_atomic(path,data) fs.files[path]=data;return true end
 return fs
end
local function runtime()
 local rt=Runtime.new({mapgen={seed=96,mg_name='v7',water_level=1},
  active_block_range=0,emerge_blocks_per_step=1})
 for _,name in ipairs({'test:marker','test:stone','test:water'}) do
  rt.api.register_node(name,{})
 end
 return rt
end
local function constant(n)
 return {offset=n,scale=0,spread={x=16,y=16,z=16},
  seed=1,octaves=1,persist=.5,lacunarity=2}
end
local options={stone='test:stone',water='test:water',
 spflags='nomountains,noridges,nocaverns',
 noise={terrain_base=constant(-25),terrain_alt=constant(-25),
  terrain_persist=constant(.5),height_select=constant(1)}}
local g=Chunk.geometry({x=0,y=0,z=0},1)
local left='-1,0,0'
local back='0,0,-1'
local left_marker={x=-15,y=2,z=0}
local back_marker={x=0,y=3,z=-15}
local left_new={x=-16,y=2,z=0}
local back_air={x=0,y=7,z=-16}
local unknown={x=-14,y=4,z=0}
local fs=disk()
local rt=runtime()
rt:enableMapgenV7Chunks(options,1)
local store=rt:attachMapBlockStore(fs,'blank96')
local map=rt.map
assert(map:create_blank_block(left))
assert(map:create_blank_block(back))
map:set_node(left_marker,{name='test:marker',param1=17,param2=29})
map:set_node(back_marker,{name='test:marker',param1=41,param2=53})
local vm=Buffer.new(map,g)
eq(vm:initialEmerge(false),2)
eq(vm:get_node(left_new).name,'ignore')
vm:begin_terrain_column(-16,0,0,15)
vm:begin_terrain_column(0,-16,0,15)
assert(vm:set_node(left_new,{name='test:stone',param1=2,param2=9}))
assert(vm:set_node(back_air,{name='air',param1=19,param2=27}))
eq(vm:commit_core(),0)
local transferred,blocks=rt.mapgenBorder:blitBackHalo(vm)
eq(transferred,34,'32 column positions + two existing snapshot nodes')
eq(blocks,2)
eq(map:get_node(left_new).name,'test:stone')
eq(map:get_node(left_new).param2,9)
eq(map:get_node(back_air).param1,19)
eq(map:get_node(back_air).param2,27)
eq(map:get_node(left_marker).param1,17,'existing marker unchanged')
eq(map:get_node(back_marker).param2,53)
eq(map:get_node(unknown).name,'ignore','unknown cells stay IGNORE')
assert(map.blank_blocks[left] and map.blank_blocks[back])
assert(not map.last_active[left] and not map.last_active[back])
eq(rt.mapgenBorder:blitBackHalo(vm),0,'identical blit idempotent')
local ok,written=store:flush()
assert(ok and written==0,'flush skips partial blocks without inventing completion')
assert(not fs.files[store:path(left)] and not fs.files[store:path(back)])
assert(fs.files[rt.mapgenBorder:path(left)])
assert(fs.files[rt.mapgenBorder:path(back)])
-- New process: prior known nodes and newly generated voxels must be
-- available as provisional sidecars, never as complete loaded blocks.
local restart=runtime()
restart:enableMapgenV7Chunks(options,1)
restart:attachMapBlockStore(fs,'blank96')
local reloaded=Buffer.new(restart.map,g)
eq(reloaded:initialEmerge(false),0,'sidecars are not complete MapBlocks')
assert(restart.mapgenBorder:seedExpanded(reloaded,g)>=34)
eq(reloaded:get_node(left_new).name,'test:stone')
eq(reloaded:get_node(left_marker).param1,17)
eq(reloaded:get_node(back_marker).param2,53)
eq(reloaded:get_node(back_air).param2,27)
-- Upon normal completion these nodes are saved in complete mapblocks.
for _,block in ipairs({left,back}) do
 assert(map:finish_blank_block(block))
 map.last_active[block]=rt.clock
end
assert(store:flush())
local boot=runtime()
local saved=boot:attachMapBlockStore(fs,'blank96')
assert(saved:emerge(left) and saved:emerge(back))
eq(boot.map:get_node(left_marker).param2,29)
eq(boot.map:get_node(left_new).param2,9)
eq(boot.map:get_node(back_marker).param1,41)
eq(boot.map:get_node(back_air).param1,19)
-- Preflight must reject external halo mutation BEFORE any core commit
-- or sidecar write (even if the changed cell is not in generated columns).
local conflict=runtime()
conflict:enableMapgenV7Chunks(options,1)
assert(conflict.map:create_blank_block(left))
local cv=Buffer.new(conflict.map,g)
cv:initialEmerge(false)
cv:begin_terrain_column(-16,0,0,15)
assert(cv:set_node({x=0,y=0,z=0},{name='test:stone'}))
conflict.map:set_node(unknown,{name='test:marker'})
assert(not pcall(cv.commit_core,cv))
eq(conflict.map:get_node({x=0,y=0,z=0}).name,'air',
 'conflict must not commit the core')
eq(conflict.map:get_node(left_new).name,'ignore')
-- Later conflict after core commit but before halo blit also rejects
-- the entire border operation.
local late=runtime()
late:enableMapgenV7Chunks(options,1)
assert(late.map:create_blank_block(left))
local lv=Buffer.new(late.map,g)
lv:initialEmerge(false)
lv:begin_terrain_column(-16,0,0,15)
lv:commit_core()
late.map:set_node(unknown,{name='test:marker'})
assert(not pcall(late.mapgenBorder.blitBackHalo,late.mapgenBorder,lv))
assert(next(late.mapgenBorder.dirty)==nil,
 'failed preflight must not publish partial sidecars')
-- A resident cave write made by THIS MMVManip commit is not a conflict.
local carve=runtime()
carve:enableMapgenV7Chunks(options,1)
assert(carve.map:create_blank_block(left))
carve.map:set_node(left_new,{name='test:stone'})
local cave=Buffer.new(carve.map,g)
cave:initialEmerge(false)
cave:enable_resident_halo_caves('test:stone')
assert(cave:set_node(left_new,{name='air'}))
cave:disable_resident_halo_caves()
local _,_,resident=cave:commit_core()
eq(resident,1)
eq(carve.mapgenBorder:blitBackHalo(cave),1)
eq(carve.map:get_node(left_new).name,'air')
-- An already generated halo must remain immutable with overwrite=false.
local generated=runtime()
generated:enableMapgenV7Chunks(options,1)
generated.map:set_node(left_new,{name='test:stone'})
generated.map.last_active[left]=0
local gv=Buffer.new(generated.map,g)
gv:initialEmerge(false)
assert(not gv:set_node(left_new,{name='test:marker'}))
eq(generated.mapgenBorder:blitBackHalo(gv),0)
eq(generated.map:get_node(left_new).name,'test:stone')
-- Real V7/ServerMap path: generating a chunk next to a partial blank
-- upper halo must transfer its AIR plane and keep earlier known nodes.
local integrated=runtime()
local gen=integrated:enableMapgenV7Chunks(options,1)
local ifs=disk()
local istore=integrated:attachMapBlockStore(ifs,'v7blank96')
local upper='0,1,0'
local stamp={x=1,y=18,z=1}
assert(integrated.map:create_blank_block(upper))
integrated.map:set_node(stamp,{name='test:marker',param1=5,param2=13})
local status
integrated.api.emerge_area({x=0,y=0,z=0},{x=0,y=0,z=0},
 function(_,action) status=action end)
integrated:step(.1)
eq(status,integrated.api.EMERGE_GENERATED)
assert(gen.lastChunkBorderStats.blitted_halo>=256)
eq(integrated.map:get_node({x=0,y=16,z=0}).name,'air')
eq(integrated.map:get_node(stamp).param2,13)
assert(integrated.map.blank_blocks[upper] and
 not integrated.map.last_active[upper])
assert(istore:flush())
assert(ifs.files[integrated.mapgenBorder:path(upper)])
local nextworld=runtime()
nextworld:enableMapgenV7Chunks(options,1)
nextworld:attachMapBlockStore(ifs,'v7blank96')
local action
nextworld.api.emerge_area({x=0,y=16,z=0},{x=0,y=16,z=0},
 function(_,a) action=a end)
nextworld:step(.1)
eq(action,nextworld.api.EMERGE_GENERATED)
eq(nextworld.api.get_node(stamp).name,'test:marker')
eq(nextworld.api.get_node(stamp).param1,5)
eq(nextworld.api.get_node(stamp).param2,13)
print('LUANTI MMVM PARTIAL BLANK HALO BLIT, CONFLICT AND RESTART PASS')
