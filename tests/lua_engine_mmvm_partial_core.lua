-- Luanti 5.18 MMVManip: finishing partially populated but ungenerated
-- MapBlocks must preserve old known nodes and reject concurrent writes.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Map=require('core.map')
local Buffer=require('core.mapgen_voxelbuffer')
local Chunk=require('core.mapgen_chunk')
local Runtime=require('core.runtime')
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
end
local g=Chunk.geometry({x=0,y=0,z=0},1)
local old={x=0,y=0,z=0}
local air={x=1,y=0,z=0}
local fresh={x=2,y=0,z=0}
local unknown={x=3,y=0,z=0}
local m=Map.new()
assert(m:create_blank_block('0,0,0'))
assert(m:set_node(old,{name='test:marker',param1=3,param2=5}))
assert(m:set_node(air,{name='air'}))
assert(m.revisions['0,0,0'] and m.blank_blocks['0,0,0'])
local oldrev=m.revisions['0,0,0']
local buffer=Buffer.new(m,g)
eq(buffer:initialEmerge(false),1)
assert(buffer.initial_blank_blocks['0,0,0'])
eq(buffer.initial_block_revisions['0,0,0'],oldrev)
eq(buffer:get_node(old).name,'test:marker')
eq(buffer:get_node(old).param2,5)
eq(buffer:get_node(air).name,'air')
eq(buffer:get_node(unknown).name,'ignore')
assert(not buffer:terrain_writable(old))
assert(not buffer:terrain_writable(air))
assert(buffer:terrain_writable(fresh))
assert(not buffer:set_node(old,{name='test:stone'}))
assert(not buffer:set_node(air,{name='test:stone'}))
assert(buffer:set_node(fresh,{name='test:stone'}))
local copied=buffer:commit_core()
eq(copied,1)
eq(m:get_node(old).name,'test:marker')
eq(m:get_node(old).param1,3)
eq(m:get_node(old).param2,5)
eq(m:get_node(air).name,'air')
eq(m:get_node(fresh).name,'test:stone')
assert(m.blank_blocks['0,0,0'])
eq(m:get_node(unknown).name,'ignore',
 'not yet generated: unspecified nodes remain CONTENT_IGNORE')
assert(m:finish_blank_block('0,0,0'))
assert(not m.blank_blocks['0,0,0'])
eq(m:get_node(unknown).name,'air')
eq(m:get_node(old).name,'test:marker')
eq(m:get_node(fresh).name,'test:stone')
assert(not m.nodes['1,0,0'],
 'explicit temporary AIR must compress when block is completed')
-- A node modified after the initialEmerge snapshot invalidates a staged
-- core. Preflight must run before writing ANY staged voxel.
local concurrent=Map.new()
assert(concurrent:create_blank_block('0,0,0'))
concurrent:set_node(old,{name='test:marker'})
local stage=Buffer.new(concurrent,g)
eq(stage:initialEmerge(false),1)
assert(stage:set_node(fresh,{name='test:stone'}))
concurrent:set_node(unknown,{name='test:other'})
assert(not pcall(stage.commit_core,stage))
eq(concurrent:get_node(fresh).name,'ignore',
 'failed preflight must not partially commit the generated core')
eq(concurrent:get_node(unknown).name,'test:other')
assert(concurrent.blank_blocks['0,0,0'])
-- If the block was completed by another caller, do not write to it.
local finished=Map.new()
assert(finished:create_blank_block('0,0,0'))
local stale=Buffer.new(finished,g)
eq(stale:initialEmerge(false),1)
assert(stale:set_node(fresh,{name='test:stone'}))
assert(finished:finish_blank_block('0,0,0'))
finished.last_active['0,0,0']=0
assert(not pcall(stale.commit_core,stale))
eq(finished:get_node(fresh).name,'air')
-- End-to-end Mapgen V7: an existing partial blank must not prevent
-- generation and must never erase its already written marker/params.
local function constant(v)
 return {offset=v,scale=0,spread={x=16,y=16,z=16},
  seed=1,octaves=1,persist=.5,lacunarity=2}
end
local rt=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1},
 emerge_blocks_per_step=1,active_block_range=0})
rt.api.register_node('test:stone',{})
rt.api.register_node('test:water',{})
rt.api.register_node('test:marker',{})
rt.api.register_node('test:other',{})
local cfg={stone='test:stone',water='test:water',
 spflags='nomountains,noridges,nocaverns',
 noise={terrain_base=constant(10),terrain_alt=constant(10),
  terrain_persist=constant(.5),height_select=constant(1)}}
local gen=rt:enableMapgenV7Chunks(cfg,{x=1,y=1,z=1})
local fs={files={}}
function fs.read(p)
 return fs.files[p],fs.files[p] and nil or 'not found'
end
function fs.write_atomic(p,data) fs.files[p]=data;return true end
local store=rt:attachMapBlockStore(fs,'partial94')
assert(rt.map:create_blank_block('0,0,0'))
assert(rt.map:set_node(old,{name='test:marker',param1=4,param2=6}))
assert(store:unload('0,0,0')==false)
assert(not fs.files[store:path('0,0,0')],
 'partially generated CONTENT_IGNORE blocks are not saved as complete')
local status
rt.api.emerge_area(old,old,function(_,a) status=a end)
rt:step(.1)
eq(status,rt.api.EMERGE_GENERATED)
eq(rt.api.get_node(old).name,'test:marker')
eq(rt.api.get_node(old).param1,4)
eq(rt.api.get_node(old).param2,6)
eq(rt.api.get_node({x=5,y=1,z=5}).name,'test:stone')
assert(gen.generatedMapBlocks==1)
assert(not rt.map.blank_blocks['0,0,0'])
assert(rt.map.last_active['0,0,0']~=nil)
assert(store:flush())
local boot=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1},
 emerge_blocks_per_step=1,active_block_range=0})
boot.api.register_node('test:stone',{})
boot.api.register_node('test:water',{})
boot.api.register_node('test:marker',{})
boot:attachMapBlockStore(fs,'partial94')
assert(boot.mapBlockStore:emerge('0,0,0'))
eq(boot.api.get_node(old).name,'test:marker')
eq(boot.api.get_node(old).param2,6)
eq(boot.api.get_node({x=5,y=1,z=5}).name,'test:stone')
print('LUANTI MMVMANIP PARTIAL BLANK CORE PRESERVATION PASS')
