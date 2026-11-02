-- Luanti 5.18 src/map.cpp::MMVManip::initialEmerge(false)
-- Verify loaded MapBlock snapshot, NO_DATA, known implicit air and that
-- mutations after emergence cannot alter a generator's prior view.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Map=require('core.map')
local Buffer=require('core.mapgen_voxelbuffer')
local Chunk=require('core.mapgen_chunk')
local Runtime=require('core.runtime')
local geom=Chunk.geometry({x=0,y=-1,z=0},{x=2,y=1,z=2})
assert(geom.node_min.x==-16 and geom.node_max.x==15)
local world=Map.new()
local resident={x=16,y=-2,z=0}
local empty={x=16,y=-2,z=1}
local meta={x=17,y=-2,z=0}
local timer={x=-17,y=-2,z=0}
local unknown={x=0,y=-2,z=16}
world:set_node(resident,{name='test:stone',param1=7,param2=9})
world:get_meta(meta):set_string('owner','sample')
world:get_timer(timer):start(12)
world.last_active['0,0,0']=0 -- already loaded and entirely air
local area=Buffer.new(world,geom)
assert(area:initialEmerge(false)==3,
 'one edited block, one timer-only and one known-empty block')
assert(area.initial_loaded_count==3)
assert(area:get_node(resident).name=='test:stone')
local prior=area:get_node(resident)
assert(prior.param1==7 and prior.param2==9)
assert(area:get_node(empty).name=='air')
assert(area:get_node(timer).name=='air')
assert(area:get_node({x=0,y=0,z=0}).name=='air')
assert(area:get_flags(empty)==0)
assert(area:get_flags(timer)==0)
assert(area:get_node(unknown).name=='ignore')
assert(area:get_flags(unknown)==Buffer.FLAG_NO_DATA)
assert(not area:terrain_writable(meta),
 'metadata-only air block must be known and protected')
assert(not area:terrain_writable(timer),
 'timer-only air block must be known and protected')
assert(area:getCoveredBlocks()['1,-1,0'])
assert(area:getCoveredBlocks()['-2,-1,0'])
assert(area:getCoveredBlocks()['0,0,0'])
assert(not area:getCoveredBlocks()['0,-1,1'])
assert(not pcall(area.initialEmerge,area,false),
 'initialEmerge should not silently overwrite an active snapshot')
assert(not pcall(Buffer.initialEmerge,Buffer.new(world,geom),true),
 'load_if_inexistent=true unsupported, never invent loaded mapblocks')
-- Native initialEmerge copies nodes. Changes to the real world after
-- that point cannot retroactively change the generated workspace.
world:set_node(resident,{name='test:marker',param1=1,param2=2})
assert(area:get_node(resident).name=='test:stone')
assert(area:get_node(resident).param2==9)
local later={x=0,y=-2,z=16}
world:set_node(later,{name='test:marker'})
assert(area:get_node(later).name=='ignore',
 'new blocks after initialEmerge remain unknown in the snapshot')
assert(not area:getCoveredBlocks()['0,-1,1'])
-- Concurrent changes to resident cave edits are validated BEFORE
-- any generated core data is transferred to the live map.
local fresh=Map.new()
fresh:set_node(resident,{name='test:stone'})
local cave=Buffer.new(fresh,geom)
assert(cave:initialEmerge(false)==1)
cave:enable_resident_halo_caves('test:stone')
assert(cave:set_node(resident,{name='air'}))
cave:disable_resident_halo_caves()
assert(cave:set_node({x=0,y=-2,z=0},{name='test:stone'}))
fresh:set_node(resident,{name='test:marker'})
assert(not pcall(cave.commit_core,cave))
assert(fresh:get_node(resident).name=='test:marker')
assert(fresh:get_node({x=0,y=-2,z=0}).name=='air')
-- Loading a sidecar is not equivalent to loading a complete MapBlock.
-- initialEmerge(false) must never hit the disk-backed mapblock store.
local disk={files={}}
function disk.read(path)
 return disk.files[path],disk.files[path] and nil or 'not found'
end
function disk.write_atomic(path,data)
 disk.files[path]=data
 return true
end
local function runtime()
 return Runtime.new({mapgen={seed=42},active_block_range=0})
end
local server=runtime()
local store=server:attachMapBlockStore(disk,'initial91')
server.map:set_node(resident,{name='test:stone'})
assert(store:flush())
local reboot=runtime()
local persisted=reboot:attachMapBlockStore(disk,'initial91')
local restored=Buffer.new(reboot.map,geom)
assert(restored:initialEmerge(false)==0,
 'disk-backed blocks are not resident until actually emerged')
assert(restored:get_node(resident).name=='ignore')
assert(persisted.loads==0,'initialEmerge(false) must not perform disk IO')
assert(persisted:emerge('1,-1,0'))
local loaded=Buffer.new(reboot.map,geom)
assert(loaded:initialEmerge(false)==1)
assert(loaded:get_node(resident).name=='test:stone')
-- Mapgen V7 must invoke initialEmerge for its real staged chunk path.
local function constant(value)
 return {offset=value,scale=0,spread={x=16,y=16,z=16},
  seed=1,octaves=1,persist=.5,lacunarity=2}
end
local config={stone='test:stone',water='test:water',
 spflags='nomountains,noridges,nocaverns',
 noise={terrain_base=constant(-25),terrain_alt=constant(-25),
  terrain_persist=constant(.5),height_select=constant(1)}}
local rt=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1},
 emerge_blocks_per_step=1,active_block_range=0})
rt.api.register_node('test:stone',{})
rt.api.register_node('test:water',{})
local gen=rt:enableMapgenV7Chunks(config,{x=2,y=1,z=2})
-- halo metadata-only block should be seen as loaded, but must not
-- be mistaken for a generated mapblock in the new chunk's core.
rt.map:get_meta({x=16,y=0,z=0}):set_string('test','data')
local status
rt.api.emerge_area({x=0,y=0,z=0},{x=0,y=0,z=0},
 function(_,a) status=a end)
rt:step(.1)
assert(status==rt.api.EMERGE_GENERATED)
assert(gen.generatedMapBlocks==4)
assert(rt.map:get_meta({x=16,y=0,z=0}):get_string('test')=='data')
assert(rt.map.last_active['1,0,0']==nil,
 'halo metadata block must not be marked fully generated')
print('LUANTI 5.18 MMVMANIP INITIAL EMERGE SNAPSHOT AND NO-DISK PASS')
