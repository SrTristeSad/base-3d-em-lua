-- Luanti 5.18 V7 one-up/down MMVManip terrain handoff.
-- Tests first-writer semantics, nonresident border, persistence and retry.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Border=require('core.mapgen_border')
local Chunk=require('core.mapgen_chunk')
local function constant(n)
 return {offset=n,scale=0,spread={x=16,y=16,z=16},
  seed=1,octaves=1,persist=.5,lacunarity=2}
end
local options={stone='test:stone',water='test:water',
 spflags='nomountains,noridges,nocaverns',
 noise={terrain_base=constant(15),terrain_alt=constant(-20),
  terrain_persist=constant(.5),height_select=constant(1)}}
local function runtime()
 local rt=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1},
  emerge_blocks_per_step=1,active_block_range=0})
 rt.api.register_node('test:stone',{})
 rt.api.register_node('test:water',{})
 rt.api.register_node('test:marker',{})
 return rt
end
local function disk()
 local fs={files={}}
 function fs.read(path)
  return fs.files[path],fs.files[path] and nil or 'not found'
 end
 function fs.write_atomic(path,data)
  fs.files[path]=data
  return true
 end
 return fs
end
local function emit(rt,p)
 local action
 rt.api.emerge_area(p,p,function(_,status) action=status end)
 rt:step(.1)
 return action
end
local size={x=2,y=1,z=2}
local p0={x=0,y=0,z=0}
local up={x=0,y=16,z=0}
local geom=Chunk.geometry({x=0,y=0,z=0},size)
assert(geom.node_max.y==15)
local fs=disk()
local rt=runtime()
local v7=rt:enableMapgenV7Chunks(options,size)
local store=rt:attachMapBlockStore(fs,'border87')
assert(emit(rt,p0)==rt.api.EMERGE_GENERATED)
assert(v7.lastChunkBorderStats.seeded==0)
assert(v7.lastChunkBorderStats.published==2048,
 'two 32x32 overgenerated horizontal planes are transferred')
assert(rt.mapgenBorder:countPending()==2048)
assert(rt.map:get_node({x=0,y=16,z=0}).name=='air')
assert(rt.api.get_node(up).name=='ignore',
 'provisional voxel must NOT mark adjacent mapblock emerged')
assert(rt.map.last_active['0,1,0']==nil)
-- Simulate a pre-existing overgenerated voxel that differs from future
-- terrain. The next terrain pass must preserve it, not regenerate over it.
local block='0,1,0'
local nk='0,16,0'
assert(rt.mapgenBorder.pending[block][nk].name=='air')
rt.mapgenBorder.pending[block][nk]={name='test:marker',param1=5,param2=9}
rt.mapgenBorder.dirty[block]=true
assert(store:flush())
local path=rt.mapgenBorder:path(block)
assert(type(fs.files[path])=='string' and
 fs.files[path]:find('test%%3Amarker'),
 'partial voxel must be persisted in separate border file')
-- Reboot before creating neighboring chunk. Its pending border must
-- be recovered from a disk sidecar, not an invented full mapblock.
local reboot=runtime()
local gen=reboot:enableMapgenV7Chunks(options,size)
reboot:attachMapBlockStore(fs,'border87')
assert(reboot.api.get_node(up).name=='ignore')
assert(reboot.mapgenBorder:countPending()==0,
 'border files should be loaded lazily')
assert(emit(reboot,up)==reboot.api.EMERGE_GENERATED)
assert(gen.lastChunkBorderStats.seeded==1024,
 'upper chunk must inherit known voxels from previous Y+1 plane')
assert(gen.lastChunkBorderStats.retired==1024)
assert(gen.lastChunkBorderStats.published==2048)
local n=reboot.api.get_node(up)
assert(n.name=='test:marker' and n.param1==5 and n.param2==9,
 'later chunk may not overwrite overgenerated border from older chunk')
assert(reboot.mapgenBorder.pending[block][nk]==nil,
 'overlap must retire after destination block is complete')
assert(reboot.map.last_active[block]~=nil)
local loaded_before=gen.generated
assert(emit(reboot,up)==reboot.api.EMERGE_FROM_MEMORY)
assert(gen.generated==loaded_before)
local upper_saved=reboot.mapBlockStore
assert(upper_saved:flush())
local restarted=runtime()
local restart_gen=restarted:enableMapgenV7Chunks(options,size)
restarted:attachMapBlockStore(fs,'border87')
assert(emit(restarted,up)==restarted.api.EMERGE_FROM_DISK)
assert(restarted.api.get_node(up).name=='test:marker')
assert(restart_gen.generated==0)
assert(restarted.mapgenBorder:countPending()==0,
 'completed border is retired and not needed to restore a saved block')
-- Already resident edit in another block: only the missing block should
-- be generated. It must still inherit transferred vertical values.
local fs2=disk()
local mixed=runtime()
local mixed_gen=mixed:enableMapgenV7Chunks(options,size)
mixed:attachMapBlockStore(fs2,'border87mixed')
assert(emit(mixed,p0)==mixed.api.EMERGE_GENERATED)
mixed.mapgenBorder.pending[block][nk]={
 name='test:marker',param1=1,param2=2}
mixed.mapgenBorder.dirty[block]=true
mixed.api.set_node({x=-16,y=20,z=-16},{name='test:water'})
assert(emit(mixed,up)==mixed.api.EMERGE_GENERATED)
assert(mixed_gen.lastChunkBorderStats.isolated==true)
assert(mixed_gen.lastChunkBorderStats.seeded==256,
 'single-mapblock fallback inherits only its own 16x16 border')
assert(mixed.api.get_node(up).name=='test:marker')
assert(mixed.api.get_node({x=-16,y=20,z=-16}).name=='test:water')
assert(mixed.api.get_node({x=-16,y=16,z=0}).name=='ignore')
-- Corrupt boundary sidecar must surface as EMERGE_ERRORED and not mark
-- a chunk generated. No unsafe load() or arbitrary Lua deserialization.
local badfs=disk()
badfs.files['bad/vertical-borders/0_1_0.border']=
 'LUAENGINE BORDER 1\nV 999 16 0 air 0 0\nEND\n'
local bad=runtime()
local badgen=bad:enableMapgenV7Chunks(options,size)
bad:attachMapBlockStore(badfs,'bad')
assert(emit(bad,up)==bad.api.EMERGE_ERRORED)
assert(badgen.generated==0)
assert(bad.map.last_active['0,1,0']==nil)
-- Failure to write sidecars must not mark them saved; retry succeeds.
local failfs=disk()
local retry=runtime()
retry:enableMapgenV7Chunks(options,size)
local reStore=retry:attachMapBlockStore(failfs,'retry87')
assert(emit(retry,p0)==retry.api.EMERGE_GENERATED)
local truewrite=failfs.write_atomic
failfs.write_atomic=function(path,data)
 if path:find('/vertical%-borders/') then return false,'disk full' end
 return truewrite(path,data)
end
assert(not pcall(reStore.flush,reStore))
assert(next(retry.mapgenBorder.dirty)~=nil)
failfs.write_atomic=truewrite
assert(reStore:flush())
assert(next(retry.mapgenBorder.dirty)==nil)
print('LUANTI 5.18 VERTICAL MMVMANIP OVERLAP HANDOFF AND RELOAD PASS')
