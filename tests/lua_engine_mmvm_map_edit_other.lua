-- Luanti 5.18 src/script/lua_api/l_vmanip.cpp:write_to_map emits
-- one MEET_OTHER with the set collected by MMVManip::blitBackAll.
-- src/map.cpp:894 raw blitBackAll itself dispatches no MapEditEvent.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Map=require('core.map')
local Runtime=require('core.runtime')
local Buffer=require('core.mapgen_voxelbuffer')
local Chunk=require('core.mapgen_chunk')
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
end
local function fsnew()
 local fs={files={}}
 function fs.read(p)
  return fs.files[p],fs.files[p] and nil or 'not found'
 end
 function fs.write_atomic(p,d)
  fs.files[p]=d
  return true
 end
 return fs
end
local function runtime()
 local rt=Runtime.new({active_block_range=0})
 rt.api.register_node('test:stone',{})
 rt.api.register_node('test:gem',{})
 return rt
end
local geom=Chunk.geometry({x=0,y=0,z=0},1)
local core='0,0,0'
local neg='-1,0,0'
local north='0,0,1'
local pcore={x=0,y=0,z=0}
local pneg={x=-16,y=0,z=0}
local pnorth={x=0,y=0,z=16}
-- Explicit helper validates the WHOLE set before dispatch. Sorting is
-- numeric x/y/z, not lexicographic strings with negative signs.
local m=Map.new()
local events={}
local receiver=function(e) events[#events+1]=e end
m:add_event_receiver(receiver)
eq(m:dispatch_modified_blocks_event({
 ['10,0,0']=true,['2,0,0']=true,['-2,0,0']=true,
 ['-10,0,0']=true},true),1)
local e=events[1]
eq(e.type,m.MEET_OTHER)
eq(e.p,nil)
eq(e.n.name,'air')
eq(e.low_priority,true)
eq(e.is_private_change,false)
eq(#e.modified_blocks,4)
eq(e.modified_blocks[1].x,-10)
eq(e.modified_blocks[2].x,-2)
eq(e.modified_blocks[3].x,2)
eq(e.modified_blocks[4].x,10)
eq(m:get_mapblock_modified_state('10,0,0'),0,
 'event emission is not a mutation or write request')
-- Default helper skips empty changes, but native write_to_map sends
-- an empty MEET_OTHER after a legitimate no-write invocation.
eq(m:dispatch_modified_blocks_event({}),0)
eq(#events,1)
eq(m:dispatch_modified_blocks_event({},false,true),1)
eq(#events,2)
eq(#events[2].modified_blocks,0)
for _,set in ipairs({
 {['0,0,0']=false},
 {['0,0,0']=1},
 {['-0,0,0']=true},
 {['01,0,0']=true},
 {['1939,0,0']=true},
 {['bad']=true},
 {['0,0,0']=true,['oops']=true}
}) do
 assert(not pcall(m.dispatch_modified_blocks_event,m,set),
  'invalid modified mapblock set passed validation')
end
assert(not pcall(m.dispatch_modified_blocks_event,m,nil))
assert(not pcall(m.dispatch_modified_blocks_event,m,{},'yes'))
assert(not pcall(m.dispatch_modified_blocks_event,m,{},false,'yes'))
eq(#events,2,'preflight failure cannot dispatch partial events')
-- The canonical MapBlock parser is shared with earlier state APIs.
-- Reject signed zero on LuaJIT as well as Lua 5.4.
assert(not pcall(m.get_mapblock_modified_state,m,'-0,0,0'))
assert(not pcall(m.get_mapblock_modified_reason,m,'0,-0,0'))
assert(not pcall(m.get_mapblock_timestamp,m,'0,0,-0'))
assert(not pcall(m.get_mapblock_lighting_complete,m,'-0,0,0'))
eq(m:dispatch_modified_blocks_event({['0,0,0']=true},false),1)
eq(events[3].modified_blocks[1].x,0)
assert(m:remove_event_receiver(receiver))
eq(m:dispatch_modified_blocks_event({['0,0,0']=true}),0)
eq(#events,3)
-- Full streaming integration: core is already generated; one partial
-- negative block and one new positive block are copied on write_to_map.
local rt=runtime()
local fs=fsnew()
local store=rt:attachMapBlockStore(fs,'events107')
rt.map:set_node(pcore,{name='test:stone'})
rt.map.last_active[core]=0
assert(rt.map:create_blank_block(neg))
local list={}
rt.map:add_event_receiver(function(event)
 list[#list+1]=event
end)
local vm=Buffer.new(rt.map,geom)
eq(vm:initialEmerge(false),2)
assert(vm:stage_vmanip_node(pcore,{name='test:gem'}))
assert(vm:stage_vmanip_node(pneg,{name='test:gem',param1=4}))
assert(vm:stage_vmanip_node(pnorth,{name='test:gem',param2=5}))
eq(#list,0,'staging and initialEmerge are silent')
local blocks,changed,created=vm:write_to_map()
eq(changed,2)
eq(created,1)
eq(#list,1,'one event for whole blit, never per voxel')
eq(blocks[core],nil)
eq(blocks[neg],true)
eq(blocks[north],true)
local group=list[1]
eq(group.type,rt.map.MEET_OTHER)
eq(group.p,nil)
eq(group.n.name,'air')
eq(group.low_priority,false)
eq(#group.modified_blocks,2)
eq(group.modified_blocks[1].x,-1)
eq(group.modified_blocks[2].x,0)
eq(group.modified_blocks[2].z,1)
eq(rt.map:get_node(pcore).name,'test:stone',
 'default write_to_map cannot overwrite generated blocks')
eq(rt.map:get_node(pneg).param1,4)
eq(rt.map:get_node(pnorth).param2,5)
eq(rt.map:get_mapblock_modified_reason(neg),131072)
eq(rt.map:get_mapblock_modified_reason(north),131072)
assert(rt.map.blank_blocks[neg] and rt.map.blank_blocks[north])
assert(not pcall(vm.write_to_map,vm),
 'a committed MMVManip buffer cannot dispatch twice')
eq(#list,1)
-- Flushing partial MapBlocks and reloading them is a disk import, not
-- a high-level write_to_map event.
assert(store:flush())
local resumed=runtime()
local imported=0
resumed.map:add_event_receiver(function() imported=imported+1 end)
local rs=resumed:attachMapBlockStore(fs,'events107')
assert(rs:load_or_create_blank(neg))
assert(rs:load_or_create_blank(north))
eq(imported,0)
eq(resumed.map:get_node(pneg).param1,4)
eq(resumed.map:get_node(pnorth).param2,5)
-- Raw blitBackAll remains silent even if listeners exist.
local raw=runtime()
raw.map:set_node(pcore,{name='test:stone'})
raw.map.last_active[core]=0
local observed=0
raw.map:add_event_receiver(function() observed=observed+1 end)
local vraw=Buffer.new(raw.map,geom)
vraw:initialEmerge(false)
assert(vraw:stage_vmanip_node(pcore,{name='test:gem'}))
local rawset,rawn=vraw:blitBackAll(true)
eq(rawset[core],true)
eq(rawn,1)
eq(raw.map:get_node(pcore).name,'test:gem')
eq(observed,0,'low-level MMVManip blit must not emit events')
-- High-level write_to_map(true) overwrites a generated block, and
-- a bit-identical snapshot still marks it modified and reports it.
local high=runtime()
high.map:set_node(pcore,{name='test:stone'})
high.map.last_active[core]=0
high.map:reset_mapblock_modified(core)
local high_events={}
high.map:add_event_receiver(function(event)
 high_events[#high_events+1]=event
end)
local same=Buffer.new(high.map,geom)
same:initialEmerge(false)
local samenodes,number=same:write_to_map(true)
eq(number,0)
eq(samenodes[core],true)
eq(#high_events,1)
eq(#high_events[1].modified_blocks,1)
eq(high_events[1].modified_blocks[1].x,0)
eq(high.map:get_mapblock_modified_state(core),4)
eq(high.map:get_mapblock_modified_reason(core),131072)
-- Conversely, all-covered-generated with default overwrite=false
-- emits the EMPTY MEET_OTHER that the upstream l_write_to_map emits.
local skipped=Buffer.new(high.map,geom)
skipped:initialEmerge(false)
local none,zero,created_none=skipped:write_to_map(false)
eq(none[core],nil)
eq(zero,0)
eq(created_none,0)
eq(#high_events,2)
eq(high_events[2].type,high.map.MEET_OTHER)
eq(#high_events[2].modified_blocks,0)
-- Snapshot preflight rejects races before committing or publishing.
local conflict=runtime()
conflict.map:set_node(pcore,{name='test:stone'})
conflict.map.last_active[core]=0
assert(conflict.map:create_blank_block(neg))
local failures=0
conflict.map:add_event_receiver(function() failures=failures+1 end)
local race=Buffer.new(conflict.map,geom)
race:initialEmerge(false)
race:stage_vmanip_node(pneg,{name='test:gem'})
race:stage_vmanip_node(pcore,{name='test:gem'})
conflict.map:set_node(pcore,{name='test:gem'})
assert(not pcall(race.write_to_map,race,true))
eq(failures,0)
eq(conflict.map:get_node(pneg).name,'ignore')
eq(conflict.map:get_node(pcore).name,'test:gem')
-- A listener failure is propagated AFTER the copy; it cannot
-- revert the committed nodes, nor permit a second blit.
local post=runtime()
post.map:set_node(pcore,{name='test:stone'})
post.map.last_active[core]=0
post.map:add_event_receiver(function() error('listener failure') end)
local doomed=Buffer.new(post.map,geom)
doomed:initialEmerge(false)
doomed:stage_vmanip_node(pcore,{name='test:gem'})
assert(not pcall(doomed.write_to_map,doomed,true))
eq(post.map:get_node(pcore).name,'test:gem')
eq(doomed.blit_done,true)
assert(not pcall(doomed.write_to_map,doomed,true))
print('LUANTI 5.18 GROUPED MMVM WRITE_TO_MAP EDIT EVENT PASS')
