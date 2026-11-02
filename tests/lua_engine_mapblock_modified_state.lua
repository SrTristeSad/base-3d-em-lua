-- Luanti 5.18 src/mapblock.h raiseModified and src/modifiedstate.h:
-- severity increases replace reasons, equal severity accumulates,
-- lower severity leaves the existing reasons unchanged.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Map=require('core.map')
local Runtime=require('core.runtime')
local Buffer=require('core.mapgen_voxelbuffer')
local Chunk=require('core.mapgen_chunk')
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
end
local function fsnew()
 local fs={files={},fail_path=nil}
 function fs.read(p) return fs.files[p],fs.files[p] and nil or 'not found' end
 function fs.write_atomic(p,d)
  if fs.fail_path==p then return nil,'disk full' end
  fs.files[p]=d
  return true
 end
 return fs
end
local function runtime()
 local rt=Runtime.new({active_block_range=0,mapgen={seed=103,mg_name='v7'}})
 rt.api.register_node('test:stone',{})
 return rt
end
local p={x=-16,y=0,z=0}
local block='-1,0,0'
local m=Map.new()
eq(m.MOD_STATE_CLEAN,0)
eq(m.MOD_STATE_WRITE_AT_UNLOAD,2)
eq(m.MOD_STATE_WRITE_NEEDED,4)
eq(m.MOD_REASON_SET_NODE,16)
eq(m.MOD_REASON_VMANIP,131072)
eq(m.MOD_REASON_SET_IS_UNDERGROUND,2)
eq(m.MOD_REASON_SET_LIGHTING_COMPLETE,4)
eq(m:get_mapblock_modified_state(block),0)
eq(m:get_mapblock_modified_reason(block),0)
eq(m:get_mapblock_modified_reason_string(block),'')
assert(not pcall(m.raise_mapblock_modified,m,block,1,4))
assert(not pcall(m.raise_mapblock_modified,m,block,2,-1))
assert(not pcall(m.raise_mapblock_modified,m,block,2,2^19))
assert(not pcall(m.raise_mapblock_modified,m,'01,0,0',4,16))
-- A real setNode transition marks WRITE_NEEDED and reason SET_NODE.
m:set_node(p,{name='test:stone'})
eq(m:get_mapblock_modified_state(block),4)
eq(m:get_mapblock_modified_reason(block),16)
eq(m:get_mapblock_modified_reason_string(block),'setNode')
m:reset_mapblock_modified(block)
eq(m:get_mapblock_modified_state(block),0)
eq(m:get_mapblock_modified_reason(block),0)
eq(m.modified[block],nil)
-- A light flag transition marks WRITE_AT_UNLOAD and does not
-- necessarily change MapNode geometry.
assert(m:set_mapblock_lighting_complete_direction(block,'day',0,false))
eq(m:get_mapblock_modified_state(block),2)
eq(m:get_mapblock_modified_reason(block),4)
m:reset_mapblock_modified(block)
assert(m:set_mapblock_lighting_complete_direction(block,'night',0,false))
eq(m:get_mapblock_modified_state(block),2)
eq(m:get_mapblock_modified_reason_string(block),'setLightingComplete')
-- Raising WRITE_NEEDED replaces any prior WRITE_AT_UNLOAD reason.
assert(m:set_mapblock_is_underground(block,true))
eq(m:get_mapblock_modified_state(block),4)
eq(m:get_mapblock_modified_reason(block),2)
eq(m:get_mapblock_modified_reason_string(block),'setIsUnderground')
-- A second WRITE_NEEDED accumulates the node-change reason.
m:set_node(p,{name='air'})
eq(m:get_mapblock_modified_state(block),4)
eq(m:get_mapblock_modified_reason(block),18)
eq(m:get_mapblock_modified_reason_string(block),
 'setIsUnderground, setNode')
-- Lower-severity light changes must NOT join a WRITE_NEEDED reason.
assert(m:set_mapblock_lighting_complete_direction(block,'day',0,true))
eq(m:get_mapblock_modified_state(block),4)
eq(m:get_mapblock_modified_reason(block),18)
-- Same-level VMANIP adds its reason without dropping earlier reasons.
eq(m:raise_mapblock_modified(block,4,131072),4)
eq(m:get_mapblock_modified_reason(block),131090)
eq(m:get_mapblock_modified_reason_string(block),
 'setIsUnderground, setNode, MMVManip::blitBackAll')
eq(m:raise_mapblock_modified(block,2,4),4)
eq(m:get_mapblock_modified_reason(block),131090)
eq(m:raise_mapblock_modified(block,4,131072),4)
eq(m:get_mapblock_modified_reason(block),131090)
m:reset_mapblock_modified(block)
eq(m:get_mapblock_modified_reason_string(block),'')
-- When a higher severity arrives, it REPLACES all lower motives.
eq(m:raise_mapblock_modified(block,2,4),2)
eq(m:raise_mapblock_modified(block,4,131072),4)
eq(m:get_mapblock_modified_reason(block),131072)
m:reset_mapblock_modified(block)
-- Idempotent native setIsUnderground is a write regardless of value;
-- idempotent setLightingComplete makes no modification.
eq(m:set_mapblock_is_underground(block,true),false)
eq(m:get_mapblock_modified_state(block),4)
eq(m:get_mapblock_modified_reason(block),2)
m:reset_mapblock_modified(block)
eq(m:set_mapblock_lighting_complete(block,
 m:get_mapblock_lighting_complete(block)),false)
eq(m:get_mapblock_modified_state(block),0)
-- Native MapBlock::copyFrom does not generate SET_NODE reasons;
-- identical and changed blits must mark VMANIP at WRITE_NEEDED.
local rt=runtime()
rt.map:set_node({x=0,y=0,z=0},{name='test:stone'})
local core='0,0,0'
rt.map:reset_mapblock_modified(core)
local v=Buffer.new(rt.map,Chunk.geometry({x=0,y=0,z=0},1))
v:initialEmerge(false)
local modified,changed=v:blitBackAll(true)
eq(changed,0)
eq(modified[core],true)
eq(rt.map:get_mapblock_modified_state(core),4)
eq(rt.map:get_mapblock_modified_reason(core),131072)
-- With a staged change, the same VMANIP reason is still the sole
-- reason for that clean destination's new dirty state.
rt.map:reset_mapblock_modified(core)
local vm=Buffer.new(rt.map,Chunk.geometry({x=0,y=0,z=0},1))
vm:initialEmerge(false)
assert(vm:stage_vmanip_node({x=0,y=0,z=0},
 {name='air',param1=3,param2=5}))
local changedblocks,nchanged=vm:blitBackAll(true)
assert(changedblocks[core])
eq(nchanged,1)
eq(rt.map:get_mapblock_modified_state(core),4)
eq(rt.map:get_mapblock_modified_reason(core),131072)
eq(rt.map:get_node({x=0,y=0,z=0}).param1,3)
-- A transient blank MapBlock that just changed lighting flags should
-- only require WRITE_AT_UNLOAD, then clear after durable flush.
local fs=fsnew()
local life=runtime()
local store=life:attachMapBlockStore(fs,'mod103')
assert(life.map:create_blank_block(block))
assert(life.map:set_mapblock_lighting_complete_direction(
 block,'night',5,false))
eq(life.map:get_mapblock_modified_state(block),2)
eq(life.map:get_mapblock_modified_reason(block),4)
fs.fail_path=store:partial_path(block)
assert(not pcall(store.flush,store),
 'an interrupted atomic partial write must not reset dirty state')
eq(life.map:get_mapblock_modified_state(block),2)
eq(life.map:get_mapblock_modified_reason(block),4)
fs.fail_path=nil
assert(store:flush())
eq(life.map:get_mapblock_modified_state(block),0)
eq(life.map:get_mapblock_modified_reason(block),0)
eq(life.map.modified[block],nil)
local reboot=runtime()
local old=reboot:attachMapBlockStore(fs,'mod103')
assert(old:load_or_create_blank(block))
eq(reboot.map:get_mapblock_modified_state(block),0,
 'disk import must not count as a new write')
eq(reboot.map:get_mapblock_lighting_complete(block),63487)
reboot.map:set_node(p,{name='test:stone'})
eq(reboot.map:get_mapblock_modified_state(block),4)
assert(old:flush())
eq(reboot.map:get_mapblock_modified_state(block),0)
-- Complete mapblocks also restore as CLEAN after disk load/unload.
assert(reboot.map:finish_blank_block(block))
reboot.map.last_active[block]=0
reboot.map:set_node(p,{name='test:stone',param1=1})
eq(reboot.map:get_mapblock_modified_state(block),4)
assert(old:flush())
eq(reboot.map:get_mapblock_modified_state(block),0)
reboot.map:set_node(p,{name='test:stone',param1=2})
eq(reboot.map:get_mapblock_modified_state(block),4)
assert(old:unload(block))
eq(reboot.map:get_mapblock_modified_state(block),0)
assert(old:emerge(block))
eq(reboot.map:get_mapblock_modified_state(block),0)
eq(reboot.map:get_node(p).param1,2)
-- Full saves retain their existing structure; the new dirty state
-- and reason table are transient and deliberately never serialized.
assert(not fs.files[old:path(block)]:find('MOD_REASON_',1,true))
print('LUANTI MAPBLOCK MODIFIED STATE, REASONS AND DURABILITY PASS')
