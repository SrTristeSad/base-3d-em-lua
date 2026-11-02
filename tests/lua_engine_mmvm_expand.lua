-- Luanti 5.18 src/map.cpp::MMVManip::initialEmerge repeated/expanded.
-- Covers addArea geometry, old known-cell preservation, fresh MapBlocks
-- and no overwrite of an already-covered partial MapBlock.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Buffer=require('core.mapgen_voxelbuffer')
local Chunk=require('core.mapgen_chunk')
local Map=require('core.map')
local Runtime=require('core.runtime')
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
end
local geom=Chunk.geometry({x=0,y=0,z=0},1)
local map=Map.new()
local known={x=0,y=1,z=0}
local staged={x=16,y=1,z=0}
local unknown={x=17,y=1,z=0}
map:set_node(known,{name='test:stone',param1=11,param2=12})
map.last_active['-1,0,0']=0
local buf=Buffer.new(map,geom)
assert(buf:set_node(staged,{name='test:staged'}))
eq(buf:initialEmerge(false),2,'initial loaded mapblocks')
eq(buf:get_node(known).name,'test:stone')
eq(buf:get_node(staged).name,'test:staged')
eq(buf:get_node(unknown).name,'ignore')
assert(buf:mark_cave(known))
eq(buf:get_flags(known),Buffer.FLAG_CHECKED1)
local idx=buf:index(staged)
local oldcount=buf.voxel_count
eq(buf.sx,48,'initial X dimension')
-- A newly loaded MapBlock may be copied when the area expands.
local extra={x=32,y=1,z=0}
local negative={x=-32,y=0,z=0}
map:set_node(extra,{name='test:extra',param1=2,param2=3})
map:set_node(negative,{name='test:negative'})
-- This block is only PARTIALLY known through a staged voxel. Luanti
-- getCoveredBlocks says it must be skipped, even though the world now
-- contains nodes in the same block.
map:set_node(unknown,{name='test:late'})
eq(buf:initialEmerge(false,{x=1,y=0,z=0},{x=2,y=0,z=0}),3,
 'only the new X=2 block imported')
eq(buf.geometry.full_node_min.x,-16)
eq(buf.geometry.full_node_max.x,47)
eq(buf.sx,64)
assert(buf.voxel_count>oldcount)
assert(buf:index(staged)~=idx or buf.sx~=48)
eq(buf:get_node(known).name,'test:stone')
eq(buf:get_node(staged).name,'test:staged')
eq(buf:get_node(unknown).name,'ignore',
 'partially covered block must not be overwritten by late world load')
eq(buf:get_flags(unknown),Buffer.FLAG_NO_DATA)
eq(buf:get_flags(known),Buffer.FLAG_CHECKED1)
eq(buf:get_node(extra).name,'test:extra')
eq(buf:get_node(extra).param1,2)
eq(buf:get_node(extra).param2,3)
assert(buf:getCoveredBlocks()['2,0,0'])
assert(not buf.initial_blocks['1,0,0'])
-- Expand in the opposite direction. Source position is captured only
-- when the corresponding block comes within the requested extent.
eq(buf:initialEmerge(false,{x=-2,y=0,z=0},{x=-2,y=0,z=0}),4)
eq(buf.geometry.full_node_min.x,-32)
eq(buf.geometry.full_node_max.x,47)
eq(buf:get_node(negative).name,'test:negative')
eq(buf:get_node(extra).name,'test:extra')
assert(buf:getCoveredBlocks()['-2,0,0'])
-- Preserve the initial snapshot even if the live Map changes later.
map:set_node(known,{name='test:late'})
map:set_node(extra,{name='test:late'})
eq(buf:initialEmerge(false,{x=0,y=0,z=0},{x=2,y=0,z=0}),4)
eq(buf:get_node(known).name,'test:stone')
eq(buf:get_node(extra).name,'test:extra')
eq(buf:get_node(staged).name,'test:staged')
eq(buf:get_flags(known),Buffer.FLAG_CHECKED1)
-- Enlarging in another axis must rebase the x-fastest VoxelArea index
-- without losing any node content. Check address calculation explicitly.
local before=buf:index(known)
eq(buf:initialEmerge(false,{x=0,y=-2,z=0},{x=0,y=-2,z=0}),4)
eq(buf.geometry.full_node_min.y,-32)
assert(buf:index(known)~=before)
eq(buf:get_node(known).name,'test:stone')
eq(buf:get_node({x=0,y=-32,z=0}).name,'ignore')
-- Newly loaded empty MapBlocks are known air, not VOID/CONTENT_IGNORE.
map.last_active['0,-2,0']=0
eq(buf:initialEmerge(false,{x=0,y=-2,z=0},{x=0,y=-2,z=0}),5)
eq(buf:get_node({x=0,y=-32,z=0}).name,'air')
eq(buf:get_flags({x=0,y=-32,z=0}),0)
-- Re-emerging a known air block must not replace it with later data.
map:set_node({x=1,y=-32,z=1},{name='test:late'})
eq(buf:initialEmerge(false,{x=0,y=-2,z=0},{x=0,y=-2,z=0}),5)
eq(buf:get_node({x=1,y=-32,z=1}).name,'air')
-- Expansion outside the supported world and unsupported true mode are
-- rejected before changing either the area or its loaded snapshots.
local maxx=buf.geometry.full_node_max.x
assert(not pcall(buf.initialEmerge,buf,true,{x=3,y=0,z=0},{x=3,y=0,z=0}))
assert(not pcall(buf.initialEmerge,buf,false,{x=1938,y=0,z=0},{x=1938,y=0,z=0}))
assert(not pcall(buf.initialEmerge,buf,false,{x=0,y=0,z=0},nil))
eq(buf.geometry.full_node_max.x,maxx)
eq(buf:get_node(known).name,'test:stone')
-- A disk-resident but not loaded block is deliberately left unknown:
-- initialEmerge(false) does not issue hidden storage reads.
local fs={files={}}
function fs.read(p) return fs.files[p],fs.files[p] and nil or 'not found' end
function fs.write_atomic(p,s) fs.files[p]=s return true end
local function runtime()
 return Runtime.new({mapgen={seed=4},active_block_range=0})
end
local rt=runtime()
local store=rt:attachMapBlockStore(fs,'expand92')
rt.map:set_node(extra,{name='test:extra'})
assert(store:flush())
local reboot=runtime()
local diskstore=reboot:attachMapBlockStore(fs,'expand92')
local gm=Chunk.geometry({x=0,y=0,z=0},1)
local unloaded=Buffer.new(reboot.map,gm)
eq(unloaded:initialEmerge(false,{x=2,y=0,z=0},{x=2,y=0,z=0}),0)
eq(unloaded:get_node(extra).name,'ignore')
eq(diskstore.loads,0)
assert(diskstore:emerge('2,0,0'))
eq(unloaded:initialEmerge(false,{x=2,y=0,z=0},{x=2,y=0,z=0}),1)
eq(unloaded:get_node(extra).name,'test:extra')
eq(diskstore.loads,1)
print('LUANTI 5.18 MMVMANIP EXPAND INITIAL EMERGE OVERLAP PASS')
