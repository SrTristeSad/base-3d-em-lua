-- Luanti 5.18 mapgen MMVManip: CONTENT_IGNORE, known air,
-- x-fastest indices, cave flag, one-up/one-down overgeneration, core commit.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Chunk=require('core.mapgen_chunk')
local Buffer=require('core.mapgen_voxelbuffer')
local Map=require('core.map')
local Runtime=require('core.runtime')
local V7=require('core.mapgen_v7')
local Walk=require('core.caves_randomwalk')
local PseudoRandom=require('core.pseudorandom')
local geom=Chunk.geometry({x=0,y=0,z=0},{x=2,y=1,z=2})
local map=Map.new()
local buf=Buffer.new(map,geom)
local origin=geom.full_node_min
assert(buf.voxel_count==64*48*64)
assert(buf:index(origin)==1,'x-fastest 1-based voxel index')
assert(buf:index({x=origin.x+1,y=origin.y,z=origin.z})==2)
assert(buf:index({x=origin.x,y=origin.y+1,z=origin.z})==65)
assert(buf:index({x=origin.x,y=origin.y,z=origin.z+1})==64*48+1)
assert(buf:get_node({x=0,y=0,z=0}).name=='ignore')
assert(buf:get_flags({x=0,y=0,z=0})==Buffer.FLAG_NO_DATA)
assert(buf:get_node({x=-32,y=-16,z=-32}).name=='ignore')
assert(not pcall(buf.get_node,buf,{x=-33,y=0,z=0}))
assert(not buf:mark_cave({x=0,y=0,z=0}),
 'Cave flag must not imply data exists in an unknown voxel')
local p={x=0,y=0,z=0}
assert(buf:set_node(p,{name='air'}))
assert(buf:get_node(p).name=='air',
 'explicit generated air must not be conflated with CONTENT_IGNORE')
assert(buf:get_flags(p)==0)
assert(buf:mark_cave(p))
assert(buf:get_flags(p)==Buffer.FLAG_CHECKED1)
assert(not pcall(buf.set_node,buf,p,{name='ignore'}))
assert(buf:set_node(p,{name='test:stone'}))
assert(buf:get_flags(p)==0,
 'new node data clears prior transient checked flag')
-- Existing mapblock border must preserve known air as well as real nodes.
local shell={x=0,y=-1,z=0}
map:set_node(shell,{name='test:water'})
local guarded=Buffer.new(map,geom)
assert(guarded:get_node(shell).name=='test:water')
assert(guarded:get_node({x=1,y=-1,z=0}).name=='air')
assert(guarded:get_flags({x=1,y=-1,z=0})==0)
assert(not guarded:set_node(shell,{name='test:stone'}))
assert(not guarded:set_node({x=1,y=-1,z=0},{name='test:stone'}))
assert(guarded:get_node(shell).name=='test:water')
-- Unknown border is valid in the MMVManip workspace and never committed.
local outer={x=0,y=16,z=0}
assert(guarded:set_node(outer,{name='test:stone'}))
local interior={x=0,y=0,z=0}
assert(guarded:set_node(interior,{name='test:stone'}))
local core_count,border_count=guarded:commit_core()
assert(core_count==1 and border_count==1)
assert(map:get_node(interior).name=='test:stone')
assert(map:get_node(outer).name=='air')
assert(map:get_node(shell).name=='test:water')
assert(not pcall(guarded.commit_core,guarded),
 'commit must reject replay over generated core mapblocks')
local function constant(v)
 return {offset=v,scale=0,spread={x=16,y=16,z=16},
  seed=1,octaves=1,persist=.5,lacunarity=2}
end
local opts={stone='test:stone',water='test:water',
 spflags='nomountains,noridges,nocaverns',
 noise={terrain_base=constant(60),terrain_alt=constant(-20),
  terrain_persist=constant(.5),height_select=constant(1)}}
local rt=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1},
 emerge_blocks_per_step=1})
rt.api.register_node('test:stone',{})
rt.api.register_node('test:water',{})
local v7=V7.new(rt,opts)
local stage=Buffer.new(rt.map,geom)
v7:_generateRegion(stage,geom.node_min,geom.node_max,
 geom.full_node_min)
assert(stage:get_node({x=0,y=-1,z=0}).name=='test:stone',
 'original generates bottom extra Y layer')
assert(stage:get_node({x=0,y=16,z=0}).name=='test:stone',
 'original generates top extra Y layer')
assert(stage:get_node({x=0,y=17,z=0}).name=='ignore',
 'no terrain written outside one-up overgeneration')
assert(stage:get_node({x=-17,y=0,z=0}).name=='ignore',
 'x/z border is reserved, not fabricated as terrain')
local copied,discarded=stage:commit_core()
assert(copied==32*16*32)
assert(discarded==2*32*32)
assert(rt.map.count==32*16*32)
assert(rt.map:get_node({x=0,y=-1,z=0}).name=='air',
 'one-down border must not falsely mark neighbor mapblock generated')
assert(rt.map.last_active['0,-1,0']==nil)
-- Small CavesRandomWalk writes CHECKED1 for excavated positions in the
-- MMVManip buffer; it must not persist across block commits.
local cave_rt=Runtime.new({mapgen={seed=42}})
cave_rt.api.register_node('test:stone',{})
local cavespace=Buffer.new(cave_rt.map,geom)
for z=6,10 do for x=6,10 do for y=6,10 do
 cavespace:set_node({x=x,y=y,z=z},{name='test:stone'})
end end end
local walk=Walk.new({map=cavespace,seed=42,
 node_min=geom.node_min,node_max=geom.node_max,
 stone='test:stone',max_stone_height=20,
 water_level=1,heightmap={}})
walk.ps=PseudoRandom.new(1467)
walk.rs=3
walk.orp={x=8.5,y=8.5,z=8.5}
walk.of={x=0,y=0,z=0}
walk.large=false;walk.flooded=false;walk.large_cave_is_flat=false
walk:_carveRoute({x=0,y=0,z=0},0,false)
assert(walk.metrics.carved>0)
local flags_found=0
for z=6,10 do for x=6,10 do for y=6,10 do
 local node={x=x,y=y,z=z}
 if cavespace:get_flags(node)==Buffer.FLAG_CHECKED1 then
  assert(cavespace:get_node(node).name=='air')
  flags_found=flags_found+1
 end
end end end
assert(flags_found>0)
-- Existing resident core must remain unchanged and prevent staged commit.
local collide=Map.new()
collide:set_node({x=0,y=0,z=0},{name='test:water'})
local blocked=Buffer.new(collide,geom)
assert(not blocked:set_node({x=1,y=0,z=0},{name='air'}))
assert(not pcall(blocked.commit_core,blocked))
assert(collide:get_node({x=0,y=0,z=0}).name=='test:water')
-- Public opt-in chunk path reports how many extended border nodes
-- were discarded rather than incorrectly exporting partial mapblocks.
local rt2=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1},
 emerge_blocks_per_step=1})
rt2.api.register_node('test:stone',{})
rt2.api.register_node('test:water',{})
local gen=rt2:enableMapgenV7Chunks(opts,{x=2,y=1,z=2})
local action
rt2.api.emerge_area({x=0,y=0,z=0},{x=0,y=0,z=0},
 function(_,a) action=a end)
rt2:step(.1)
assert(action==rt2.api.EMERGE_GENERATED)
assert(gen.lastChunkVoxelStats.core_nodes==32*16*32)
assert(gen.lastChunkVoxelStats.border_discarded==2*32*32)
assert(gen.lastChunkVoxelStats.buffer_volume==64*48*64)
assert(gen.generatedMapBlocks==4)
assert(#rt2.api.get_loaded_blocks()==4)
-- The non-streamed runtime preserves historical implicit-air reads.
-- Validate mapblock metadata rather than treating implicit air as loaded.
assert(rt2.map.revisions['0,-1,0']==nil and
 rt2.map.last_active['0,-1,0']==nil and
 rt2.map.lbm_applied['0,-1,0']==nil,
 'extended border must stay ungenerated')
print('LUANTI 5.18 MMVMANIP CORE, CONTENT_IGNORE, CAVE FLAGS, OVERGENERATION PASS')
