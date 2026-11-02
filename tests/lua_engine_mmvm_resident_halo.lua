-- Luanti 5.18 MMVManip::initialEmerge + blitBackAll resident halo.
-- Check cavegen.cpp::CavesRandomWalk::carveRoute m_area.contains(p)
-- against a previously loaded ground block, never partial sidecars.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Buffer=require('core.mapgen_voxelbuffer')
local Chunk=require('core.mapgen_chunk')
local Walk=require('core.caves_randomwalk')
local PRNG=require('core.pseudorandom')
local function runtime()
 local rt=Runtime.new({mapgen={seed=42,mg_name='v7'},
  emerge_blocks_per_step=1,active_block_range=0})
 rt.api.register_node('test:stone',{})
 rt.api.register_node('test:water',{})
 rt.api.register_node('test:marker',{})
 return rt
end
local function disk()
 local fs={files={}}
 function fs.read(p) return fs.files[p],fs.files[p] and nil or 'not found' end
 function fs.write_atomic(p,s) fs.files[p]=s;return true end
 return fs
end
local geom=Chunk.geometry({x=0,y=-1,z=0},{x=2,y=1,z=2})
local pos={x=16,y=-2,z=0} -- X halo, inside MMVManip, outside core
local rt=runtime()
local store=rt:attachMapBlockStore(disk(),'resident89')
local block=rt.map:blockkey(pos)
local count=0
for z=-4,4 do for y=-5,-1 do for x=16,19 do
 rt.map:set_node({x=x,y=y,z=z},{name='test:stone'})
 count=count+1
end end end
assert(count==180)
-- Normal terrain path is unable to change a loaded mapblock.
local buffer=Buffer.new(rt.map,geom)
assert(buffer:get_node(pos).name=='test:stone')
assert(buffer:get_flags(pos)==0)
assert(not buffer:set_node(pos,{name='air'}))
assert(buffer:terrain_writable(pos)==false)
buffer:mark_imports_clean()
buffer:enable_resident_halo_caves('test:stone')
assert(buffer:can_carve_resident(pos))
local walk=Walk.new({map=buffer,seed=42,node_min=geom.node_min,
 node_max=geom.node_max,stone='test:stone',max_stone_height=10,
 water_level=1})
walk.ps=PRNG.new(1467)
walk.rs=7
walk.orp={x=16,y=-2,z=0}
walk.of={x=0,y=0,z=0}
walk.large=false;walk.flooded=false;walk.large_cave_is_flat=false
walk:_carveRoute({x=0,y=0,z=0},0,false)
buffer:disable_resident_halo_caves()
local changes={}
for k in pairs(buffer.resident_modified) do
 local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
 local p={x=tonumber(x),y=tonumber(y),z=tonumber(z)}
 assert(not buffer:core_contains(p))
 assert(rt.map:get_node(p).name=='test:stone',
  'resident voxel cannot change until MMVManip commit')
 assert(buffer:get_node(p).name=='air')
 changes[#changes+1]=p
end
assert(#changes>0 and #changes==walk.metrics.carved,
 'CavesRandomWalk must carve known resident ground in XYZ halo')
assert(buffer:get_node({x=-32,y=-2,z=0}).name=='ignore')
assert(not buffer:set_node(pos,{name='air'}),
 'disabling resident halo mutation must reject further writes')
-- The staged entries remain valid; commit applies them after preflight.
local core,discarded,written=buffer:commit_core()
assert(core==0 and discarded==0 and written==#changes)
for _,p in ipairs(changes) do
 assert(rt.map:get_node(p).name=='air',
  'blitBackAll must update the already emerged mapblock')
end
assert(rt.map.revisions[block] and rt.map.modified[block])
assert(rt.api.get_node({x=-32,y=-2,z=0}).name=='ignore',
 'unknown halo should not be changed or emerged')
assert(store:flush())
local reboot=runtime()
reboot:attachMapBlockStore(store.fs,'resident89')
local status
reboot.api.emerge_area(pos,pos,function(_,action) status=action end)
reboot:step(.1)
assert(status==reboot.api.EMERGE_FROM_DISK)
-- The route spans both Z=-1 and Z=0 mapblocks; only the requested
-- block is loaded by emerge_area. Explicitly reload the neighboring
-- saved block before asserting both sides of the persisted tunnel.
reboot.api.load_area({x=16,y=-5,z=-4},{x=19,y=-1,z=4})
for _,p in ipairs(changes) do
 assert(reboot.api.get_node(p).name=='air',
  'resident cave modification must survive unload/load')
end
-- Simulate an intervening player edit while a chunk is calculating:
-- no generated core node may be written when preflight detects a conflict.
local concurrent=runtime()
concurrent.map:set_node(pos,{name='test:stone'})
local cb=Buffer.new(concurrent.map,geom)
cb:enable_resident_halo_caves('test:stone')
assert(cb:set_node(pos,{name='air'}))
cb:disable_resident_halo_caves()
assert(cb:set_node({x=0,y=-2,z=0},{name='test:stone'}))
concurrent.map:set_node(pos,{name='test:marker'})
assert(not pcall(cb.commit_core,cb),
 'resident snapshot conflict must abort before committing the core')
assert(concurrent.map:get_node(pos).name=='test:marker')
assert(concurrent.map:get_node({x=0,y=-2,z=0}).name=='air')
-- Same node name with changed param2 is still a conflict.
local params=runtime()
params.map:set_node(pos,{name='test:stone',param2=1})
local pb=Buffer.new(params.map,geom)
pb:enable_resident_halo_caves('test:stone')
assert(pb:set_node(pos,{name='air'}))
params.map:set_node(pos,{name='test:stone',param2=3})
assert(not pcall(pb.commit_core,pb))
assert(params.map:get_node(pos).param2==3)
-- Nodes with metadata or timers cannot be touched by mapgen caves.
local protected=runtime()
protected.map:set_node(pos,{name='test:stone'})
protected.map:get_meta(pos):set_string('owner','player')
local prot=Buffer.new(protected.map,geom)
prot:enable_resident_halo_caves('test:stone')
assert(not prot:can_carve_resident(pos))
assert(not prot:set_node(pos,{name='air'}))
assert(protected.map:get_node(pos).name=='test:stone')
-- If metadata is attached after the cave was staged, preflight aborts.
local late=runtime()
late.map:set_node(pos,{name='test:stone'})
local lb=Buffer.new(late.map,geom)
lb:enable_resident_halo_caves('test:stone')
assert(lb:set_node(pos,{name='air'}))
late.map:get_timer(pos):start(10)
assert(not pcall(lb.commit_core,lb))
assert(late.map:get_node(pos).name=='test:stone')
-- Non-buffered legacy cave path remains core-limited.
local old=runtime()
old.map:set_node(pos,{name='test:stone'})
local legacy=Walk.new({map=old.map,seed=42,node_min=geom.node_min,
 node_max=geom.node_max,stone='test:stone'})
legacy.ps=PRNG.new(1467);legacy.rs=7
legacy.orp={x=16,y=-2,z=0};legacy.of={x=0,y=0,z=0}
legacy.large=false;legacy.flooded=false;legacy.large_cave_is_flat=false
legacy:_carveRoute({x=0,y=0,z=0},0,false)
assert(old.map:get_node(pos).name=='test:stone')
print('LUANTI MMVMANIP RESIDENT HALO CAVE BLIT, CONFLICT AND RELOAD PASS')
