-- Luanti 5.18 cavegen.cpp noise intersection/cavern depth regressions.
-- This verifies the explicitly scoped raw-stone cave stage, not the full
-- biome-aware native chunk generator or CavesRandomWalk.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Map=require('core.map')
local V7=require('core.mapgen_v7')
local Cave=require('core.cave_noise')
local function constant(offset)
 return {offset=offset,scale=0,spread={x=16,y=16,z=16},
  seed=11,octaves=1,persist=.5,lacunarity=2}
end
local noise={
 cave1=constant(0),cave2=constant(0),cavern=constant(1)}
local cave=Cave.new(42,{noise=noise})
assert(Cave.contour(0)==1 and Cave.contour(.8)>.199 and
 Cave.contour(1)==0 and Cave.contour(-2)==0)
assert(cave:tunnelAt(1,-10,4))
assert(cave:tunnelAt(-123,10,99))
local carve,near,strength=cave:cavernAt(2,-256,5)
assert(not carve and not near and strength==0)
carve,near,strength=cave:cavernAt(2,-512,5)
assert(carve and near and strength==1)
carve,near,strength=cave:cavernAt(2,-416,5)
assert(not carve and near and math.abs(strength-.625)<1e-8,
 'CavernsNoise uses depth taper with distinct near and carve thresholds')

-- Cavern pass must leave water and foreign nodes intact.
local nocave=Cave.new(42,{noise={
 cave1=constant(2),cave2=constant(2),cavern=constant(1)}})
assert(not nocave:tunnelAt(2,-512,5))
local map=Map.new()
local stone={x=0,y=-512,z=0}
local water={x=1,y=-512,z=0}
local foreign={x=0,y=-511,z=0}
map:set_node(stone,{name='test:stone'})
map:set_node(water,{name='test:water'})
map:set_node(foreign,{name='test:ore'})
local metrics=nocave:carve(map,{x=0,y=-512,z=0},{x=1,y=-511,z=0},
 'test:stone',{max_stone_y=50,caverns=true})
assert(metrics.caverns==1 and metrics.tunnels==0 and metrics.near_cavern)
assert(map:get_node(stone).name=='air')
assert(map:get_node(water).name=='test:water')
assert(map:get_node(foreign).name=='test:ore')
-- Strict compare: equal contour threshold is not a cave.
local exact=Cave.new(42,{noise=noise,cave_width=1})
assert(not exact:tunnelAt(2,0,3))
assert(not Cave.new(42,{noise=noise,cave_width=10}):tunnelAt(2,0,3))
assert(not pcall(Cave.new,42,{noise=noise,cavern_taper=0}))
assert(not pcall(Cave.new,42,{noise=noise,cave_width=-.1}))
assert(not pcall(Cave.new,42,{noise={cave1=constant(0)}}))
-- The raw V7 generator is explicitly opt-in for cave excavation.
local rt=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1},
 emerge_blocks_per_step=1,active_block_range=0})
rt.api.register_node('test:stone',{})
rt.api.register_node('test:water',{})
local options={stone='test:stone',water='test:water',
 spflags='nomountains,noridges,nocaverns',
 noise_caves=true,
 noise={terrain_base=constant(64),terrain_alt=constant(-64),
  terrain_persist=constant(.5),height_select=constant(1),
  cave1=constant(0),cave2=constant(0),cavern=constant(1)}}
local v7=rt:enableMapgenV7Base(options)
assert(v7.caveNoise and v7.noise_caves)
local fs={files={}}
function fs.read(path)
 return fs.files[path],fs.files[path] and nil or 'not found'
end
function fs.write_atomic(path,data) fs.files[path]=data;return true end
local store=rt:attachMapBlockStore(fs,'cavev7')
local a={x=0,y=0,z=0}
local events={}
rt.api.emerge_area(a,a,function(pos,action,remaining)
 events[#events+1]={action,remaining}
end)
assert(rt.api.get_node(a).name=='ignore')
rt:step(.1)
assert(#events==1 and events[1][1]==rt.api.EMERGE_GENERATED)
assert(v7.generated==1)
assert(v7.lastCaveMetrics.tunnels==4096)
assert(v7.lastCaveMetrics.caverns==0)
assert(rt.map.count==0,'a generated empty cave block must remain distinguishable from unknown')
assert(rt.api.get_node(a).name=='air')
assert(rt.api.get_node_or_nil(a).name=='air')
assert(store:resident('0,0,0'))
assert(store:flush())
assert(type(fs.files[store:path('0,0,0')])=='string')
local rt2=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1},
 emerge_blocks_per_step=1})
rt2.api.register_node('test:stone',{})
rt2.api.register_node('test:water',{})
local v72=rt2:enableMapgenV7Base(options)
rt2:attachMapBlockStore(fs,'cavev7')
local events2={}
rt2.api.emerge_area(a,a,function(pos,action)
 events2[#events2+1]=action
end)
rt2:step(.1)
assert(events2[1]==rt2.api.EMERGE_FROM_DISK)
assert(rt2.api.get_node(a).name=='air')
assert(v72.generated==0,'empty cave block must not regenerate after reload')
-- Default phase81 behavior remains unchanged without explicit noise_caves.
local baseline=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1}})
baseline.api.register_node('test:stone',{})
baseline.api.register_node('test:water',{})
local unmodified=baseline:enableMapgenV7Base({
 stone='test:stone',water='test:water',
 spflags='nomountains,noridges,nocaverns',
 noise={terrain_base=constant(64),terrain_alt=constant(-64),
  terrain_persist=constant(.5),height_select=constant(1)}})
assert(unmodified.caveNoise==nil)
assert(unmodified:generateBlock({x=0,y=0,z=0},{x=15,y=15,z=15}))
assert(baseline.map.count==4096)
assert(baseline.api.get_node(a).name=='test:stone')
-- With tunnels disabled and caverns enabled, deep stone is excavated.
local deep=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1}})
deep.api.register_node('test:stone',{})
deep.api.register_node('test:water',{})
local deepopts={stone='test:stone',water='test:water',
 spflags='nomountains,noridges,caverns',noise_caves=true,
 cave_width=10,
 noise={terrain_base=constant(-400),terrain_alt=constant(-450),
 terrain_persist=constant(.5),height_select=constant(1),
 cave1=constant(0),cave2=constant(0),cavern=constant(1)}}
local deepv7=deep:enableMapgenV7Base(deepopts)
assert(deepv7:generateBlock({x=0,y=-512,z=0},{x=15,y=-497,z=15}))
assert(deepv7.lastCaveMetrics.tunnels==0)
assert(deepv7.lastCaveMetrics.caverns==4096)
assert(deepv7.lastCaveMetrics.near_cavern)
assert(deep.map.count==0)
print('LUA ENGINE LUANTI 5.18 NOISE CAVES AND CAVERNS PASS')
