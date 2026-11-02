-- Original Luanti 5.18 Mapgen::getBlockSeed2 and CavesRandomWalk tests.
-- Native C++ reference: src/mapgen/mapgen.cpp, cavegen.cpp, noise.h.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Walk=require('core.caves_randomwalk')
local Map=require('core.map')
local Runtime=require('core.runtime')
local PseudoRandom=require('core.pseudorandom')
-- Golden u32 outputs independently evaluated from source C++ polynomial,
-- including unsigned overflow at intermediate steps.
local seeds={
 {{x=0,y=0,z=0},0,1376312589},
 {{x=-16,y=-16,z=-16},42,2935758449},
 {{x=80,y=-32,z=32},123,2703646241},
 {{x=-31000,y=15000,z=3010},-17,3115400849},
 {{x=16,y=16,z=16},1,252334003}
}
for _,v in ipairs(seeds) do
 assert(Walk.getBlockSeed2(v[1],v[2])==v[3],
  'Mapgen getBlockSeed2 must preserve unsigned 32-bit overflow')
end
assert(Walk.signed(2935758449)==-1359208847)
assert(Walk.mul32(4294967295,4294967295)==1)
assert(Walk.mul32(65536,65536)==0)
local function sample_map()
 local m=Map.new()
 for z=0,15 do for x=0,15 do for y=0,15 do
  m:set_node({x=x,y=y,z=z},{name='test:stone'})
 end end end
 return m
end
local function configured(m)
 local hm={}
 for i=1,256 do hm[i]=15 end
 return Walk.new({
  map=m,seed=42,node_min={x=0,y=0,z=0},
  node_max={x=15,y=15,z=15},max_stone_height=32,
  heightmap=hm,stone='test:stone',water='test:water',water_level=1
 })
end
local w1=configured(sample_map())
local m2=sample_map()
local w2=configured(m2)
local blockseed=Walk.getBlockSeed2({x=-16,y=-16,z=-16},42)
local settings={
 small_cave_num_min=1,small_cave_num_max=1,
 large_cave_num_min=0,large_cave_num_max=0
}
local a=w1:generate(blockseed,settings)
local b=w2:generate(blockseed,settings)
assert(a.caves==1 and b.caves==1)
assert(a.carved==b.carved and a.sections==b.sections)
assert(#w1.events==2 and #w2.events==2)
assert(w1.events[1].type=='cave_begin')
assert(w1.events[2].type=='cave_end')
for i=1,#w1.events do
 assert(w1.events[i].type==w2.events[i].type)
 for _,axis in ipairs({'x','y','z'}) do
  assert(w1.events[i].pos[axis]==w2.events[i].pos[axis],
   'randomwalk route and PRNG must be reproducible from identical seeds')
 end
end
for z=0,15 do for x=0,15 do for y=0,15 do
 local p={x=x,y=y,z=z}
 assert(w1.map:get_node(p).name==m2:get_node(p).name)
end end end
-- Direct raw stone carving verifies the tunnel cross-section independent
-- of whether a PRNG-start point is outside this small 16³ test mapblock.
local carve_map=sample_map()
local w=configured(carve_map)
w.ps=PseudoRandom.new(1467)
w.rs=3
w.orp={x=8.5,y=8.5,z=8.5}
w.of={x=0,y=0,z=0}
w.large=false
w.flooded=false
w.large_cave_is_flat=false
w:_carveRoute({x=0,y=0,z=0},0,false)
assert(w.metrics.carved>0)
assert(carve_map.count<4096)
assert(carve_map:get_node({x=0,y=0,z=0}).name=='test:stone')
-- Preserve non-ground nodes even when the walking volume intersects them.
local preserve_map=sample_map()
preserve_map:set_node({x=8,y=8,z=8},{name='test:water'})
local wp=configured(preserve_map)
wp.ps=PseudoRandom.new(1467)
wp.rs=3;wp.orp={x=8.5,y=8.5,z=8.5}
wp.of={x=0,y=0,z=0}
wp.large=false;wp.flooded=false;wp.large_cave_is_flat=false
wp:_carveRoute({x=0,y=0,z=0},0,false)
assert(preserve_map:get_node({x=8,y=8,z=8}).name=='test:water')
-- No randomwalk caves with both counts zero: map unchanged.
local empty=configured(sample_map())
local zero=empty:generate(blockseed,{
 small_cave_num_min=0,small_cave_num_max=0,
 large_cave_num_min=0,large_cave_num_max=0})
assert(zero.caves==0 and zero.carved==0 and #empty.events==0)
assert(empty.map.count==4096)
assert(not pcall(empty.generate,empty,blockseed,{
 small_cave_num_min=2,small_cave_num_max=1}))
-- Above-ground start/end rejection: chosen high relative to heightmap.
local high=configured(sample_map())
assert(high:isPosAboveSurface({x=0,y=16,z=0}))
assert(not high:isPosAboveSurface({x=0,y=15,z=0}))
assert(high:isPosAboveSurface({x=50,y=2,z=50}))
-- Large caves are gated at native large_cave_depth=-33.
local deep=configured(sample_map())
local skip=deep:generate(blockseed,{
 small_cave_num_min=0,small_cave_num_max=0,
 large_cave_num_min=1,large_cave_num_max=1})
assert(skip.caves==0)
-- V7 runtime opt-in: original PRNG itinerary gets attached only when
-- randomwalk_caves=true; these tests do not imply full mapgen 1:1.
local function constant(n)
 return {offset=n,scale=0,spread={x=16,y=16,z=16},
  seed=9,octaves=1,persist=.5,lacunarity=2}
end
local opts={stone='test:stone',water='test:water',
 spflags='nomountains,noridges,nocaverns',
 randomwalk_caves=true,
 small_cave_num_min=1,small_cave_num_max=1,
 large_cave_num_min=0,large_cave_num_max=0,
 noise={terrain_base=constant(40),terrain_alt=constant(-10),
  terrain_persist=constant(.5),height_select=constant(1)}}
local function runtime()
 local rt=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1},
  emerge_blocks_per_step=1})
 rt.api.register_node('test:stone',{})
 rt.api.register_node('test:water',{})
 return rt
end
local rt=runtime()
local v7=rt:enableMapgenV7Base(opts)
local fs={files={}}
function fs.read(path)
 return fs.files[path],fs.files[path] and nil or 'not found'
end
function fs.write_atomic(path,data) fs.files[path]=data;return true end
local store=rt:attachMapBlockStore(fs,'v7random')
local got={}
rt.api.emerge_area({x=0,y=0,z=0},{x=0,y=0,z=0},
 function(p,action,remain) got[#got+1]={action,remain} end)
rt:step(.1)
assert(#got==1 and got[1][1]==rt.api.EMERGE_GENERATED)
assert(v7.generated==1 and v7.lastRandomWalkMetrics.caves==1)
assert(#v7.lastRandomWalkEvents==2)
assert(store:flush())
local rt2=runtime()
local v72=rt2:enableMapgenV7Base(opts)
rt2:attachMapBlockStore(fs,'v7random')
local event
rt2.api.emerge_area({x=0,y=0,z=0},{x=0,y=0,z=0},
 function(p,action) event=action end)
rt2:step(.1)
assert(event==rt2.api.EMERGE_FROM_DISK)
assert(v72.generated==0,'persisted mapblock must not be regenerated')
for z=0,15 do for x=0,15 do for y=0,15 do
 local p={x=x,y=y,z=z}
 assert(rt.api.get_node(p).name==rt2.api.get_node(p).name)
end end end
print('LUANTI 5.18 CAVES RANDOMWALK SEED AND ROUTE CORE PASS')
