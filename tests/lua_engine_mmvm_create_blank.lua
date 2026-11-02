-- Luanti 5.18 MMVManip::initialEmerge(p_min,p_max,true)
-- ServerMap::emergeBlock(k,true): in-memory, disk, then blank MapBlock
-- of CONTENT_IGNORE with isGenerated()==false.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Map=require('core.map')
local Chunk=require('core.mapgen_chunk')
local Buffer=require('core.mapgen_voxelbuffer')
local Runtime=require('core.runtime')
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': expected '..tostring(b)..
  ', received '..tostring(a))
end
local function keys(t)
 local n=0 for _ in pairs(t) do n=n+1 end return n
end
local g=Chunk.geometry({x=0,y=0,z=0},1)
local center={x=0,y=0,z=0}
local neighbor={x=16,y=0,z=0}
-- New blocks are PRESENT in the map, but have CONTENT_IGNORE nodes;
-- they must not be mistaken for an already-generated air MapBlock.
local m=Map.new()
local vm=Buffer.new(m,g)
eq(vm:initialEmerge(true),27,'one core and 26 neighboring blank blocks')
eq(keys(m.blank_blocks),27)
assert(m.blank_blocks['0,0,0'] and m.blank_blocks['1,0,0'])
eq(m:get_node(center).name,'ignore')
eq(vm:get_node(center).name,'ignore')
eq(vm:get_flags(center),0,'blank is copied with no NO_DATA flag')
eq(vm:getCoveredBlocks()['0,0,0'],true)
eq(vm:getCoveredBlocks()['1,0,0'],true)
assert(not m.revisions['0,0,0'] and not m.last_active['0,0,0'])
assert(vm:terrain_writable(center),
 'new CONTENT_IGNORE block is writable by mapgen, not generated')
assert(vm:set_node(center,{name='test:stone'}))
eq(vm:get_node(center).name,'test:stone')
eq(m:get_node(center).name,'ignore','staged write not committed')
eq(vm:initialEmerge(true),27,'overlapping reemergence is idempotent')
eq(vm:get_node(center).name,'test:stone')
-- Explicit air is a known node within an otherwise CONTENT_IGNORE block.
m:set_node(neighbor,{name='air',param1=0,param2=0})
eq(m:get_node(neighbor).name,'air')
eq(m:get_node({x=17,y=0,z=0}).name,'ignore')
-- Marking a mapblock generated removes its temporary blank identity and
-- makes unspecified voxels ordinary air, without losing explicit terrain.
assert(m:finish_blank_block('1,0,0'))
assert(not m.blank_blocks['1,0,0'])
eq(m:get_node(neighbor).name,'air')
eq(m:get_node({x=17,y=0,z=0}).name,'air')
assert(not m.nodes['16,0,0'],'known AIR is compressed on finish')
eq(vm:get_node(neighbor).name,'ignore',
 'initialEmerge snapshot must not change when live blank is finished')
-- Store support: load a valid complete image first and only create blank
-- blocks for missing mapblocks. Missing blocks are NOT persisted as air.
local fs={files={}}
function fs.read(p) return fs.files[p],fs.files[p] and nil or 'not found' end
function fs.write_atomic(p,data) fs.files[p]=data;return true end
local function runtime()
 return Runtime.new({mapgen={seed=73,mg_name='v7'},
  emerge_blocks_per_step=1,active_block_range=0})
end
local saved=runtime()
local st=saved:attachMapBlockStore(fs,'true93')
saved.map:set_node(neighbor,{name='test:marker',param1=7,param2=9})
assert(st:flush())
local diskfile=fs.files[st:path('1,0,0')]
assert(diskfile and #diskfile>20)
local loaded=runtime()
local ls=loaded:attachMapBlockStore(fs,'true93')
local fromdisk=Buffer.new(loaded.map,g)
eq(fromdisk:initialEmerge(true),27)
eq(ls.loads,1,'disk MapBlock was loaded, not recreated blank')
eq(fromdisk:get_node(neighbor).name,'test:marker')
eq(fromdisk:get_node(neighbor).param1,7)
eq(fromdisk:get_node(neighbor).param2,9)
assert(not loaded.map.blank_blocks['1,0,0'])
assert(loaded.map.blank_blocks['0,0,0'])
assert(not loaded.map.last_active['0,0,0'])
eq(loaded.map:get_node(center).name,'ignore')
local before=ls.loads
assert(ls:flush())
eq(ls.loads,before)
assert(fs.files[ls:path('0,0,0')]==nil,
 'a created blank must not be written as a completed mapblock')
assert(fs.files[ls:path('1,0,0')]==diskfile)
-- A created blank block must still be eligible for the host generator
-- when emerge_area is called. It must NOT be EMERGE_FROM_MEMORY.
loaded:setMapBlockGenerator(function(rt,minp,maxp)
 eq(minp.x,0)
 eq(maxp.x,15)
 -- An empty but successfully generated mapblock is known AIR.
 return true
end)
local action
loaded.api.emerge_area(center,center,function(_,status) action=status end)
loaded:step(.1)
eq(action,loaded.api.EMERGE_GENERATED,
 'blank blocks should still be generated')
assert(not loaded.map.blank_blocks['0,0,0'])
assert(loaded.map.last_active['0,0,0']~=nil)
eq(loaded.api.get_node(center).name,'air')
assert(ls:flush())
assert(fs.files[ls:path('0,0,0')],
 'generated blank is now persisted as known air')
local restart=runtime()
local rs=restart:attachMapBlockStore(fs,'true93')
assert(rs:emerge('0,0,0'))
eq(restart.api.get_node(center).name,'air')
assert(not restart.map.blank_blocks['0,0,0'])
-- Never convert malformed disk data into a new blank.
local badfs={files={}}
function badfs.read(p) return badfs.files[p],badfs.files[p] and nil or 'not found' end
function badfs.write_atomic(p,data) badfs.files[p]=data;return true end
badfs.files['bad93/blocks/1_0_0.map']='CORRUPT'
local bad=runtime()
bad:attachMapBlockStore(badfs,'bad93')
local attempt=Buffer.new(bad.map,g)
assert(not pcall(attempt.initialEmerge,attempt,true),
 'invalid disk image must fail and not be treated as an absent block')
assert(not bad.map.blank_blocks['1,0,0'])
assert(not bad.map.last_active['1,0,0'])
print('LUANTI MMVMANIP INITIAL EMERGE TRUE BLANK BLOCK LIFECYCLE PASS')
