-- Native Luanti 5.18 5x5x5 mapblock chunk and implicit known-air columns.
-- Tests full 80x80x80 core without allocating 512000 Lua air node entries.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Chunk=require('core.mapgen_chunk')
local Buffer=require('core.mapgen_voxelbuffer')
local Runtime=require('core.runtime')
local Map=require('core.map')
local Walk=require('core.caves_randomwalk')
local function eq3(p,x,y,z)
 assert(p.x==x and p.y==y and p.z==z,
  ('expected %d,%d,%d; got %d,%d,%d'):format(x,y,z,p.x,p.y,p.z))
end
local g=Chunk.geometry({x=0,y=15,z=0},5)
eq3(g.block_min,-2,13,-2)
eq3(g.block_max,2,17,2)
eq3(g.node_min,-32,208,-32)
eq3(g.node_max,47,287,47)
eq3(g.full_node_min,-48,192,-48)
eq3(g.full_node_max,63,303,63)
assert(#Chunk.each_block(g)==125)
local m=Map.new()
local buf=Buffer.new(m,g)
buf:begin_terrain_column(0,0,207,288)
assert(buf.air_columns_count==1)
assert(buf:get_node({x=0,y=207,z=0}).name=='air')
assert(buf:get_node({x=0,y=208,z=0}).name=='air')
assert(buf:get_node({x=0,y=288,z=0}).name=='air')
assert(buf:get_flags({x=0,y=208,z=0})==0)
assert(buf:get_node({x=0,y=206,z=0}).name=='ignore')
assert(buf:get_flags({x=0,y=206,z=0})==Buffer.FLAG_NO_DATA)
assert(buf:get_node({x=1,y=208,z=0}).name=='ignore')
assert(buf:terrain_writable({x=0,y=208,z=0}))
assert(buf:set_node({x=0,y=208,z=0},{name='air'}))
assert(next(buf.overlay)==nil and buf.writes==0,
 'known air must never allocate one Lua table per sky voxel')
assert(buf:set_node({x=0,y=208,z=0},{name='test:stone'}))
assert(buf:get_node({x=0,y=208,z=0}).name=='test:stone')
assert(buf:remove_node({x=0,y=208,z=0}))
assert(buf:get_node({x=0,y=208,z=0}).name=='air')
assert(buf.writes==2,'cave-like removal must explicitly override stone')
assert(not pcall(buf.begin_terrain_column,buf,0,0,207,288))
-- Loading a saved mapblock means its air is known even without an
-- explicit node entry; the world must always take precedence.
local existing=Map.new()
existing.last_active['0,13,0']=0
existing:set_node({x=0,y=208,z=0},{name='test:water'})
local seen=Buffer.new(existing,g)
seen:begin_terrain_column(0,0,207,288)
assert(seen:get_node({x=0,y=208,z=0}).name=='test:water')
assert(seen:get_node({x=1,y=208,z=0}).name=='air')
assert(not seen:terrain_writable({x=0,y=208,z=0}))
assert(not seen:set_node({x=0,y=208,z=0},{name='test:stone'}))
local function constant(n)
 return {offset=n,scale=0,spread={x=16,y=16,z=16},
  seed=1,octaves=1,persist=.5,lacunarity=2}
end
local opts={stone='test:stone',water='test:water',
 spflags='nomountains,noridges,nocaverns',
 noise={terrain_base=constant(-20),terrain_alt=constant(-20),
  terrain_persist=constant(.5),height_select=constant(1)}}
local function runtime()
 local rt=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1},
  emerge_blocks_per_step=1,active_block_range=0})
 rt.api.register_node('test:stone',{})
 rt.api.register_node('test:water',{})
 return rt
end
local fs={files={}}
function fs.read(path)
 return fs.files[path],fs.files[path] and nil or 'not found'
end
function fs.write_atomic(path,content)
 fs.files[path]=content
 return true
end
local rt=runtime()
local v7=rt:enableMapgenV7Chunks(opts) -- default 5^3, original Luanti
local store=rt:attachMapBlockStore(fs,'chunk86')
local callback={}
rt.api.register_on_generated(function(minp,maxp,blockseed)
 callback[#callback+1]={minp=minp,maxp=maxp,seed=blockseed}
end)
local req={x=0,y=240,z=0}
local action
rt.api.emerge_area(req,req,function(_,status) action=status end)
rt:step(.1)
assert(action==rt.api.EMERGE_GENERATED)
assert(v7.generated==1 and v7.generatedMapBlocks==125)
assert(v7.lastChunkVoxelStats.air_columns==6400)
assert(v7.lastChunkVoxelStats.generated_writes==0,
 'all-sky chunk must not stage 512000 explicit air nodes')
assert(v7.lastChunkVoxelStats.core_nodes==0)
assert(v7.lastChunkVoxelStats.border_discarded==0)
assert(v7.lastChunkVoxelStats.buffer_volume==112*112*112)
assert(rt.map.count==0,'generated air must remain sparse in the live map')
assert(#callback==1)
eq3(callback[1].minp,-32,208,-32)
eq3(callback[1].maxp,47,287,47)
assert(callback[1].seed==Walk.getBlockSeed2(g.full_node_min,42))
assert(#rt.api.get_loaded_blocks()==125)
assert(rt.api.get_node({x=-32,y=208,z=-32}).name=='air')
assert(rt.api.get_node({x=47,y=287,z=47}).name=='air')
assert(rt.api.get_node({x=0,y=207,z=0}).name=='ignore',
 'one-down generation is not prematurely committed')
local second
rt.api.emerge_area({x=-32,y=208,z=-32},{x=-32,y=208,z=-32},
 function(_,status) second=status end)
rt:step(.1)
assert(second==rt.api.EMERGE_FROM_MEMORY)
assert(v7.generated==1)
assert(store:flush())
assert(type(fs.files[store:path('0,15,0')])=='string')
assert(type(fs.files[store:path('-2,13,-2')])=='string')
assert(type(fs.files[store:path('2,17,2')])=='string')
-- Empty generated mapblocks must stay recognized after reloading them.
local rt2=runtime()
local v72=rt2:enableMapgenV7Chunks(opts)
rt2:attachMapBlockStore(fs,'chunk86')
local disk
rt2.api.emerge_area(req,req,function(_,status) disk=status end)
rt2:step(.1)
assert(disk==rt2.api.EMERGE_FROM_DISK)
assert(v72.generated==0)
assert(rt2.api.get_node(req).name=='air')
assert(rt2.api.get_node({x=47,y=287,z=47}).name=='ignore',
 'adjacent empty block must not appear loaded from a different disk block')
print('LUANTI 5.18 ORIGINAL 5x5x5 CHUNK, IMPLICIT AIR, STREAMING PASS')
