-- Luanti 5.18 src/map.cpp: MMVManip::getCoveredBlocks and
-- blitBackAll default !overwrite_generated, scoped to partial Lua halos.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Chunk=require('core.mapgen_chunk')
local Buffer=require('core.mapgen_voxelbuffer')
local Runtime=require('core.runtime')
local function eq(actual,expected,message)
 assert(actual==expected,
  (message or 'value mismatch')..': expected '..tostring(expected)..
  ', got '..tostring(actual))
end
local function rt()
 local v=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1},
  emerge_blocks_per_step=1,active_block_range=0})
 v.api.register_node('test:stone',{})
 v.api.register_node('test:water',{})
 v.api.register_node('test:marker',{})
 return v
end
local function fs()
 local f={files={}}
 function f.read(path)
  return f.files[path],f.files[path] and nil or 'not found'
 end
 function f.write_atomic(path,data) f.files[path]=data;return true end
 return f
end
local function constant(n)
 return {offset=n,scale=0,spread={x=16,y=16,z=16},
  seed=1,octaves=1,persist=.5,lacunarity=2}
end
local opts={stone='test:stone',water='test:water',
 spflags='nomountains,noridges,nocaverns',
 noise={terrain_base=constant(-25),terrain_alt=constant(-25),
  terrain_persist=constant(.5),height_select=constant(1)}}
local g=Chunk.geometry({x=0,y=-1,z=0},{x=2,y=1,z=2})
eq(g.node_min.x,-16);eq(g.node_max.x,15)
eq(g.node_min.y,-16);eq(g.node_max.y,-1)
local world=rt()
world:enableMapgenV7Chunks(opts,{x=2,y=1,z=2})
local disk=fs()
local store=world:attachMapBlockStore(disk,'blit89')
local bb=world.mapgenBorder
local buf=Buffer.new(world.map,g)
assert(next(buf:getCoveredBlocks())==nil,
 'every fresh mapblock initially contains only CONTENT_IGNORE')
-- A known-air column covers the central block AND both vertical neighbors.
buf:begin_terrain_column(0,0,-17,0)
local covered=buf:getCoveredBlocks()
assert(covered['0,-2,0'] and covered['0,-1,0'] and covered['0,0,0'])
eq((function() local n=0 for _ in pairs(covered) do n=n+1 end
 return n end)(),3,'known air column covered blocks')
-- Unlike the previous publishModifiedHalo, a completely new voxel in
-- X-positive halo may be copied back without any earlier border sidecar.
local ore={x=16,y=-5,z=0}
local k=ore.x..','..ore.y..','..ore.z
local block=world.map:blockkey(ore)
eq(block,'1,-1,0')
assert(buf:set_node(ore,{name='test:marker',param1=7,param2=9}))
assert(buf:getCoveredBlocks()[block])
assert(buf:get_flags({x=17,y=-5,z=0})==Buffer.FLAG_NO_DATA)
local copied,blocks=bb:blitBackHalo(buf)
eq(copied,3,'known air plus new X halo node')
eq(blocks,3,'three neighbor blocks actually modified')
assert(bb.pending[block][k].name=='test:marker')
eq(bb.pending[block][k].param1,7)
eq(bb.pending[block][k].param2,9)
assert(bb.pending['0,-2,0']['0,-17,0'].name=='air')
assert(bb.pending['0,0,0']['0,0,0'].name=='air')
assert(world.api.get_node(ore).name=='ignore',
 'partial blit must not emerge a new mapblock')
assert(not world.map.last_active[block])
eq(bb:blitBackHalo(buf),0,'blitting identical data is idempotent')
assert(store:flush())
assert(disk.files[bb:path(block)] and
 disk.files[bb:path(block)]:find('test%%3Amarker'))
-- Restart, generate the neighbor core, and preserve the imported voxel.
local nextworld=rt()
local gen=nextworld:enableMapgenV7Chunks(opts,{x=2,y=1,z=2})
nextworld:attachMapBlockStore(disk,'blit89')
assert(nextworld.api.get_node(ore).name=='ignore')
local action
nextworld.api.emerge_area(ore,ore,function(_,status) action=status end)
nextworld:step(.1)
eq(action,nextworld.api.EMERGE_GENERATED)
assert(gen.lastChunkBorderStats.seeded>=1)
local node=nextworld.api.get_node(ore)
eq(node.name,'test:marker')
eq(node.param1,7);eq(node.param2,9)
assert(nextworld.mapgenBorder.pending[block][k]==nil)
-- A full/generated neighbor takes precedence over a new staged voxel.
local other=rt()
other:enableMapgenV7Chunks(opts,{x=2,y=1,z=2})
other.map:set_node(ore,{name='test:water'})
local overlay=Buffer.new(other.map,g)
assert(overlay:getCoveredBlocks()[block],
 'loaded block is covered even if other positions are implicit air')
assert(not overlay:set_node(ore,{name='test:marker'}))
eq(other.mapgenBorder:blitBackHalo(overlay),0)
eq(other.map:get_node(ore).name,'test:water')
-- An all-air generated block has no explicit nodes, but its loading
-- marker means its entire 16^3 content is known to initialEmerge.
other.map.last_active['1,0,0']=0
assert(overlay:getCoveredBlocks()['1,0,0'],
 'loaded empty mapblock must count as covered')
-- Native default blitBackAll refuses to overwrite a generated block.
local fake=Buffer.new(other.map,g)
local newpos={x=16,y=0,z=1}
assert(not fake:set_node(newpos,{name='test:stone'}))
eq(other.mapgenBorder:blitBackHalo(fake),0)
assert(next(other.mapgenBorder.dirty)==nil)
-- The original 5x5x5 chunk still emits a whole air core with no
-- per-voxel node allocations. Covered blocks include air-filled core.
local native=Chunk.geometry({x=0,y=15,z=0},5)
local sky=Buffer.new(rt().map,native)
for z=native.node_min.z,native.node_max.z do
 for x=native.node_min.x,native.node_max.x do
  sky:begin_terrain_column(x,z,
   native.node_min.y-1,native.node_max.y+1)
 end
end
local skyblocks=sky:getCoveredBlocks()
local n=0 for _ in pairs(skyblocks) do n=n+1 end
eq(n,175,'125 core + 50 vertical halo blocks must be covered')
assert(next(sky.overlay)==nil)
print('LUANTI 5.18 MMVM COVERED BLOCKS AND SAFE FULL-HALO BLIT PASS')
