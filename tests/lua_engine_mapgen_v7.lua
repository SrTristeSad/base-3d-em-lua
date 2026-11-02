-- Source-anchored Luanti 5.18 MapgenV7 base/mountain/river regression.
-- Test both Lua 5.4 and LuaJIT with actual emerge_area + disk storage.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Noise=require('core.valuenoise')
local V7=require('core.mapgen_v7')
local function approx(a,b,margin)
 assert(math.abs(a-b)<=(margin or 1e-8),
  ('V7 noise expected %.17g, got %.17g'):format(b,a))
end
local np=V7.defaults
assert(np.terrain_base.seed==82341 and np.terrain_alt.seed==5934)
assert(np.terrain_persist.seed==539 and np.height_select.seed==4213)
assert(np.mount_height.seed==72449 and np.mountain.seed==5333)
assert(np.ridge.seed==6467 and np.ridge_uwater.seed==85039)
assert(np.cave1.seed==52534 and np.cave2.seed==10325)
local rt=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1}})
rt.api.register_node('audit:stone',{})
rt.api.register_node('audit:water',{})
local v7=V7.new(rt,{stone='audit:stone',water='audit:water'})
assert(v7.flags.mountains and v7.flags.ridges and v7.flags.caverns)
assert(not v7.flags.floatlands)
-- Independently recompute the upstream point sample with 5 noises.
local x,z=33,-19
local world=42
local hn=Noise.world_scalar(world,np.height_select):get_2d({x=x,y=z})
local p=Noise.world_scalar(world,np.terrain_persist):get_2d({x=x,y=z})
local baseparams={}
for k,v in pairs(np.terrain_base) do baseparams[k]=v end
baseparams.persist=p
local altparams={}
for k,v in pairs(np.terrain_alt) do altparams[k]=v end
altparams.persist=p
local base=Noise.world_scalar(world,baseparams):get_2d({x=x,y=z})
local alt=Noise.world_scalar(world,altparams):get_2d({x=x,y=z})
local select=math.min(1,math.max(0,hn))
local expected=(alt>base) and alt or base*select+alt*(1-select)
approx(v7:baseTerrainLevelAtPoint(x,z),expected)
-- Default V7 mountain predicate in original mapgen_v7.cpp.
local y=12
local mounth=max or math.max
local mh=math.max(Noise.world_scalar(world,np.mount_height):get_2d({x=x,y=z}),1)
local mn=Noise.world_scalar(world,np.mountain):get_3d({x=x,y=y,z=z})
assert(v7:getMountainTerrainAtPoint(x,y,z)==(mn-(y/mh)>=0))
-- Identical channel formula to MapgenV7::getRiverChannelFromMap.
local uw=math.abs(Noise.world_scalar(world,np.ridge_uwater):get_2d({x=x,y=z}))*2
local altitude=y-v7.water_level
local ridge=Noise.world_scalar(world,np.ridge):get_3d({x=x,y=y,z=z})
local expected_river=uw<=.2 and
 (ridge*math.max(altitude,0)/7+(.2-uw)*(altitude+17)/2.5>=.6)
assert(v7:getRiverChannelAtPoint(x,y,z)==expected_river)
local v7base=V7.new(rt,{stone='audit:stone',water='audit:water',
 spflags='nomountains,noridges,nocaverns'})
assert(not v7base.flags.mountains and not v7base.flags.ridges)
assert(not v7base:getMountainTerrainAtPoint(0,0,0))
assert(not v7base:getRiverChannelAtPoint(0,0,0))
assert(not pcall(V7.new,rt,{stone='nonexistent',water='audit:water'}))
assert(not pcall(V7.new,rt,{stone='audit:stone',water='audit:water',
 spflags='floatlands'}))
-- Controlled constant-noise values let us validate every 16^3 cell.
local function constant(offset)
 return {offset=offset,scale=0,spread={x=16,y=16,z=16},
  seed=1,octaves=1,persist=.5}
end
local opts={stone='audit:stone',water='audit:water',
 spflags='nomountains,noridges,nocaverns',
 noise={terrain_base=constant(-1),terrain_alt=constant(-1),
  terrain_persist=constant(.5),height_select=constant(1)}}
local rt2=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1},
 active_block_range=0,emerge_blocks_per_step=1})
rt2.api.register_node('audit:stone',{})
rt2.api.register_node('audit:water',{})
local gen=rt2:enableMapgenV7Base(opts)
assert(not pcall(rt2.enableMapgenV7Base,rt2,opts))
assert(gen:baseTerrainLevelAtPoint(123,-456)==-1)
assert(gen:materialAt(5,0,9,-1)=='audit:water')
assert(gen:materialAt(5,1,9,-1)=='audit:water')
assert(gen:materialAt(5,2,9,-1)=='air')
local fs={files={}}
function fs.read(file)
 return fs.files[file],fs.files[file] and nil or 'not found'
end
function fs.write_atomic(file,data) fs.files[file]=data;return true end
local store=rt2:attachMapBlockStore(fs,'v7test')
local generated={}
rt2.api.register_on_generated(function(a,b,seed)
 generated[#generated+1]={a.x,b.x,seed}
end)
local before={x=0,y=0,z=0}
assert(rt2.api.get_node(before).name=='ignore')
local events={}
rt2.api.emerge_area(before,before,function(blockpos,action,left)
 events[#events+1]={blockpos.x,action,left}
end)
assert(#events==0)
rt2:step(.25)
assert(#events==1 and events[1][2]==rt2.api.EMERGE_GENERATED and
 events[1][3]==0)
assert(gen.generated==1)
assert(#generated==1 and generated[1][1]==0 and generated[1][2]==15)
assert(rt2.map.count==512,'only y=0 and y=1 are water in 16^3')
for x=0,15 do for z=0,15 do
 for y=0,15 do
  local node=rt2.api.get_node({x=x,y=y,z=z})
  assert(node.name==((y<=1) and 'audit:water' or 'air'))
 end
end end
assert(store:flush())
assert(fs.files[store:path('0,0,0')])
local rt3=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1},
 emerge_blocks_per_step=1})
rt3.api.register_node('audit:stone',{})
rt3.api.register_node('audit:water',{})
local gen3=rt3:enableMapgenV7Base(opts)
rt3:attachMapBlockStore(fs,'v7test')
local recalled={}
rt3.api.emerge_area(before,before,function(p,action)
 recalled[#recalled+1]=action
end)
rt3:step(.25)
assert(#recalled==1 and recalled[1]==rt3.api.EMERGE_FROM_DISK)
assert(gen3.generated==0,'preexisting disk mapblock must not regenerate')
assert(rt3.map.count==512)
assert(rt3.api.get_node({x=0,y=1,z=0}).name=='audit:water')
assert(rt3.api.get_node({x=0,y=3,z=0}).name=='air')
rt3.api.set_node({x=0,y=3,z=0},{name='audit:stone'})
local revisit={}
rt3.api.emerge_area(before,before,function(p,action)
 revisit[#revisit+1]=action
end)
rt3:step(.25)
assert(revisit[1]==rt3.api.EMERGE_FROM_MEMORY)
assert(rt3.api.get_node({x=0,y=3,z=0}).name=='audit:stone')
assert(gen3.generated==0)
print('LUA ENGINE ORIGINAL MAPGEN V7 RAW TERRAIN PASS')
