-- Luanti 5.18 src/map.cpp:858-892 getCoveredBlocks:
-- every block-aligned MMVManip block must be present, with false
-- for exclusively VOXELFLAG_NO_DATA voxels and true for any data.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Map=require('core.map')
local Buffer=require('core.mapgen_voxelbuffer')
local Chunk=require('core.mapgen_chunk')
local Border=require('core.mapgen_border')
local Runtime=require('core.runtime')
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
end
local function nkeys(t)
 local n=0 for _ in pairs(t) do n=n+1 end return n
end
local function runtime()
 local rt=Runtime.new({mapgen={seed=99,mg_name='v7'},
  active_block_range=0})
 rt.api.register_node('test:stone',{})
 return rt
end
local g=Chunk.geometry({x=0,y=0,z=0},1)
local core={x=0,y=0,z=0}
local blank={x=-16,y=0,z=0}
local miss={x=0,y=0,z=16}
local unknown={x=0,y=16,z=0}
local coreblock='0,0,0'
local blankblock='-1,0,0'
local missblock='0,0,1'
local unknownblock='0,1,0'
local outside='9,9,9'
local w=runtime()
local map=w.map
map:set_node(core,{name='test:stone'})
assert(map:create_blank_block(blankblock))
local buf=Buffer.new(map,g)
-- Before initialEmerge, the legacy Lua staging adapter exposes
-- existing live-map blocks sparsely; the full 3x3x3 boolean table only
-- applies after the explicit initialEmerge snapshot.
eq(nkeys(buf:getCoveredBlocks()),1)
eq(buf:getCoveredBlocks()[coreblock],true)
eq(buf:initialEmerge(false),2)
local covered=buf:getCoveredBlocks()
eq(nkeys(covered),27,'3x3x3 emerged VoxelArea must include false entries')
eq(covered[coreblock],true,'generated mapblock has data')
eq(covered[blankblock],true,
 'loaded CONTENT_IGNORE blank still has zeroed NO_DATA flags')
eq(covered[missblock],false,'unloaded mapblock is NO_DATA')
eq(covered[unknownblock],false)
eq(covered[outside],nil,'outside area is not enumerated')
eq(buf:get_flags(miss),Buffer.FLAG_NO_DATA)
eq(buf:get_flags(blank),0)
-- Direct flags can already carry NO_DATA. It must not be added twice,
-- which would accidentally set CHECKED1 and clear the unknown bit.
local key=miss.x..','..miss.y..','..miss.z
buf.flags[key]=Buffer.FLAG_NO_DATA
eq(buf:get_flags(miss),Buffer.FLAG_NO_DATA)
buf.flags[key]=Buffer.FLAG_NO_DATA+Buffer.FLAG_CHECKED2
eq(buf:get_flags(miss),Buffer.FLAG_NO_DATA+Buffer.FLAG_CHECKED2)
buf.flags[key]=nil
-- A live map write after initialEmerge must not retroactively change
-- the snapshot's NO_DATA coverage.
map:set_node(miss,{name='test:stone'})
eq(buf:getCoveredBlocks()[missblock],false,
 'source edits are not imported until an explicit reemergence')
eq(buf:get_node(miss).name,'ignore')
-- Native initialEmerge skips only the blocks with true coverage;
-- a previously NO_DATA block is imported when the method is repeated.
eq(buf:initialEmerge(false),3)
eq(buf:getCoveredBlocks()[missblock],true)
eq(buf:get_node(miss).name,'test:stone')
-- Expansion must enumerate every coordinate of the enlarged VoxelArea,
-- including negative blocks that were not loaded from the source.
eq(buf:initialEmerge(false,{x=-2,y=0,z=0},{x=-2,y=0,z=0}),3)
local expanded=buf:getCoveredBlocks()
eq(nkeys(expanded),36,'4x3x3 expanded VoxelArea')
eq(expanded['-2,0,0'],false)
eq(expanded['-2,-1,-1'],false)
eq(expanded[missblock],true)
-- A newly staged explicit node is data even if its block was NO_DATA.
assert(buf:stage_vmanip_node(unknown,{name='air',param1=8,param2=9}))
eq(buf:getCoveredBlocks()[unknownblock],true)
eq(buf:get_flags(unknown),0)
eq(map:get_node(unknown).name,'air',
 'staging cannot mutate the live map')
-- False entries must not trigger validation for concurrent blank
-- mapblocks that were not imported into the MMVManip snapshot.
local safe=runtime()
local sb=Buffer.new(safe.map,g)
sb:initialEmerge(false)
assert(safe.map:create_blank_block(blankblock))
safe.map:set_node(blank,{name='test:stone'})
assert(sb:validate_blank_halo())
eq(sb:getCoveredBlocks()[blankblock],false)
-- False entries must not cause blitBackAll to emerge blank neighbors.
local written,changed,created=sb:blitBackAll()
eq(next(written),nil)
eq(changed,0)
eq(created,0)
assert(not safe.map.blank_blocks[unknownblock])
-- The halo's copy path likewise skips all unknown false blocks,
-- even if those were loaded concurrently in the source map.
local border=Border.new(safe)
eq(border:blitBackHalo(sb),0)
eq(next(border.dirty),nil)
-- A plain staged terrain air column flips just the corresponding
-- covered Y-blocks to true and retains the other false entries.
local terrain=Buffer.new(Map.new(),g)
terrain:initialEmerge(false)
terrain:begin_terrain_column(0,0,-16,16)
local covers=terrain:getCoveredBlocks()
eq(nkeys(covers),27)
eq(covers['0,-1,0'],true)
eq(covers['0,0,0'],true)
eq(covers['0,1,0'],true)
eq(covers['1,0,0'],false)
assert(terrain:get_node({x=0,y=16,z=0}).name=='air')
-- Generated blank-core snapshots are considered covered even when
-- every MapNode inside remains CONTENT_IGNORE.
local blank_only=Map.new()
assert(blank_only:create_blank_block(coreblock))
local all_ignore=Buffer.new(blank_only,g)
all_ignore:initialEmerge(false)
eq(all_ignore:getCoveredBlocks()[coreblock],true)
eq(all_ignore:get_node(core).name,'ignore')
eq(all_ignore:get_flags(core),0)
print('LUANTI 5.18 MMVM COVERED BLOCKS FALSE NO_DATA AND SNAPSHOT PASS')
