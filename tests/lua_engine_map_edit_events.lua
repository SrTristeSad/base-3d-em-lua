-- Luanti 5.18 src/map.h: MapEditEventType, MapEventReceiver, dispatchEvent.
-- High-level node edits dispatch events. Low-level map writes, timers and
-- streaming imports do not pretend to be high-level MapEditEvents.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Map=require('core.map')
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
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
local function runtime()
 local rt=Runtime.new({active_block_range=0})
 rt.api.register_node('test:stone',{})
 rt.api.register_node('test:lamp',{})
 return rt
end
local rt=runtime()
local map=rt.map
eq(map.MEET_ADDNODE,0)
eq(map.MEET_REMOVENODE,1)
eq(map.MEET_SWAPNODE,2)
eq(map.MEET_BLOCK_NODE_METADATA_CHANGED,3)
eq(map.MEET_OTHER,4)
local p={x=-1,y=0,z=16}
local k='-1,0,1'
local received={}
local function capture(e)
 received[#received+1]=e
end
local receiver={calls=0}
function receiver:onMapEditEvent(e)
 self.calls=self.calls+1
 -- Each callback owns an independent event snapshot.
 e.modified_blocks[1].x=500
 if e.p then e.p.x=500 end
 if e.n then e.n.name='changed:by_receiver' end
end
assert(not pcall(map.add_event_receiver,map,nil))
assert(not pcall(map.add_event_receiver,map,{}))
assert(map:add_event_receiver(receiver))
assert(map:add_event_receiver(capture))
eq(map:add_event_receiver(receiver),false)
eq(map:add_event_receiver(capture),false)
-- Map:set_node is a raw worldgen/streaming operation and has no event.
map:set_node(p,{name='test:stone'})
eq(#received,0)
eq(receiver.calls,0)
-- The public set_node operation emits ADDNODE after applying the write.
eq(rt.api.set_node(p,{name='test:lamp',param1=5,param2=7}),true)
eq(#received,1)
eq(receiver.calls,1)
local event=received[1]
eq(event.type,map.MEET_ADDNODE)
eq(event.p.x,-1)
eq(event.p.z,16)
eq(event.n.name,'test:lamp')
eq(event.n.param1,5)
eq(event.n.param2,7)
eq(event.modified_blocks[1].x,-1)
eq(event.modified_blocks[1].y,0)
eq(event.modified_blocks[1].z,1)
eq(event.is_private_change,false)
eq(event.low_priority,false)
eq(map:get_node(p).name,'test:lamp')
-- Receiver payloads must not alias caller positions or one another.
eq(p.x,-1)
eq(rt.api.swap_node(p,{name='test:stone',param1=1}),true)
eq(received[2].type,map.MEET_SWAPNODE)
eq(received[2].n.name,'test:stone')
eq(map:get_node(p).name,'test:stone')
-- Read-only metadata, timer and inventory operations never dispatch.
local meta=rt.api.get_meta(p)
eq(meta:get_string('owner'),'')
eq(meta:get_inventory():get_size('main'),0)
eq(rt.api.get_node_timer(p):is_started(),false)
eq(#received,2)
-- Each metadata scalar write gets one metadata event, and the native
-- default is_private_change remains false (privacy not implemented yet).
meta:set_string('owner','builder')
eq(#received,3)
eq(received[3].type,map.MEET_BLOCK_NODE_METADATA_CHANGED)
eq(received[3].p.x,-1)
eq(received[3].modified_blocks[1].x,-1)
eq(received[3].is_private_change,false)
eq(map:get_mapblock_modified_reason(k),64+16)
meta:set_int('count',3)
eq(#received,4)
meta:set_float('rate',2.5)
eq(#received,5)
local inv=meta:get_inventory()
inv:set_size('main',2)
eq(#received,6)
inv:set_stack('main',1,'test:stone 3')
eq(#received,7)
inv:get_stack('main',1)
inv:get_list('main')
eq(#received,7)
-- from_table contains multiple inventory writes, but is ONE user edit.
meta:from_table({fields={owner='replaced'},inventory={
 main={size=2,width=2,stacks={'test:stone 4',false}}
}})
eq(#received,8)
eq(received[8].type,map.MEET_BLOCK_NODE_METADATA_CHANGED)
eq(meta:get_string('owner'),'replaced')
eq(meta:get_inventory():get_stack('main',1):get_count(),4)
-- Timer lifecycle is tracked for durability, but Luanti has no
-- dedicated MapEditEventType for NodeTimerRef methods.
local timer=rt.api.get_node_timer(p)
timer:start(2)
timer:set(2,0.5)
timer:stop()
eq(#received,8)
-- Implicit metadata removal belongs to the node event: no duplicate
-- metadata event should accompany a high-level remove_node.
eq(rt.api.remove_node(p),true)
eq(#received,9)
eq(received[9].type,map.MEET_REMOVENODE)
eq(received[9].n.name,'air')
eq(rt.api.get_meta(p):get_string('owner'),'')
-- Manual metadata changes can pass a privacy flag; no private-field
-- tracking is inferred by the partial Lua metadata implementation.
map:report_node_metadata_change(p,true)
eq(#received,10)
eq(received[10].type,map.MEET_BLOCK_NODE_METADATA_CHANGED)
eq(received[10].is_private_change,true)
-- C++ MEET_OTHER represents arbitrary modified MapBlocks, not a
-- fabricated single-node edit. Multi-block position vectors survive.
local other={type=map.MEET_OTHER,
 modified_blocks={{x=-1,y=0,z=1},{x=0,y=0,z=1}},
 low_priority=true}
eq(map:dispatch_event(other),2)
eq(#received,11)
eq(received[11].type,map.MEET_OTHER)
eq(received[11].p,nil)
eq(received[11].modified_blocks[1].x,-1)
eq(received[11].modified_blocks[2].x,0)
eq(received[11].low_priority,true)
eq(other.modified_blocks[1].x,-1)
-- Invalid events must be rejected before invoking any listener.
for _,bad in ipairs({
 {type=-1,p=p},
 {type=5,p=p},
 {type=map.MEET_ADDNODE},
 {type=map.MEET_ADDNODE,p={x=1.5,y=0,z=0}},
 {type=map.MEET_OTHER,modified_blocks={{x=1939,y=0,z=0}}},
 {type=map.MEET_OTHER,low_priority='yes'},
 {type=map.MEET_OTHER,is_private_change='no'},
 {type=map.MEET_SWAPNODE,p=p,n={name='',param1=0}},
 {type=map.MEET_ADDNODE,p=p,n={name='test:stone',param1=256}}
}) do
 assert(not pcall(map.dispatch_event,map,bad),
  'accepted malformed MapEditEvent')
end
eq(#received,11)
-- Removing another receiver during dispatch skips it without corrupting
-- iteration. A receiver added during dispatch starts only next event.
local order={}
local first,second,third
first=function(e)
 order[#order+1]='first'
 map:remove_event_receiver(second)
 if third then map:add_event_receiver(third) end
end
second=function(e) order[#order+1]='second' end
third=function(e) order[#order+1]='third' end
assert(map:remove_event_receiver(receiver))
assert(map:remove_event_receiver(capture))
eq(map:remove_event_receiver(capture),false)
assert(map:add_event_receiver(first))
assert(map:add_event_receiver(second))
eq(map:dispatch_event({type=map.MEET_OTHER}),1)
eq(table.concat(order,','),'first')
eq(map:dispatch_event({type=map.MEET_OTHER}),2)
eq(table.concat(order,','),'first,first,third')
assert(map:remove_event_receiver(first))
assert(map:remove_event_receiver(third))
-- A receiver can remove itself; nested dispatch uses a separate snapshot.
local nested=0
local once
once=function(e)
 nested=nested+1
 map:remove_event_receiver(once)
 map:dispatch_event({type=map.MEET_OTHER})
end
assert(map:add_event_receiver(once))
eq(map:dispatch_event({type=map.MEET_OTHER}),1)
eq(nested,1)
eq(map:dispatch_event({type=map.MEET_OTHER}),0)
-- A failed listener cannot roll back a node edit already committed.
local failing=function() error('observer failure') end
map:add_event_receiver(failing)
assert(not pcall(rt.api.swap_node,p,{name='test:stone',param1=6}))
eq(map:get_node(p).param1,6)
map:remove_event_receiver(failing)
-- Node callbacks still precede the public add-node event.
local callbacks={}
rt.api.register_node('test:callback',{
 on_construct=function(pos)
  callbacks[#callbacks+1]='construct'
 end
})
map:add_event_receiver(function(e)
 if e.type==map.MEET_ADDNODE then
  callbacks[#callbacks+1]='event'
 end
end)
rt.api.set_node(p,{name='test:callback'})
eq(table.concat(callbacks,','),'construct,event')
-- A streaming disk import must be silent to MapEditEvent receivers.
local sf=disk()
local source=runtime()
local dest='1,0,0'
local dp={x=16,y=0,z=0}
local ds=source:attachMapBlockStore(sf,'event106')
source.map:set_node(dp,{name='test:stone'})
source.map.last_active[dest]=0
source.api.get_meta(dp):set_string('owner','fromdisk')
source.api.get_node_timer(dp):start(5)
assert(ds:flush())
local loaded=runtime()
local count=0
loaded.map:add_event_receiver(function() count=count+1 end)
local recovered=loaded:attachMapBlockStore(sf,'event106')
assert(recovered:emerge(dest))
eq(count,0,'complete block import must not emit edit events')
eq(loaded.api.get_meta(dp):get_string('owner'),'fromdisk')
eq(loaded.api.get_node_timer(dp):is_started(),true)
-- Partial CONTENT_IGNORE block metadata and timer import also silent.
local bp={x=-16,y=0,z=0}
local bk='-1,0,0'
local partial=runtime()
local ps=partial:attachMapBlockStore(sf,'eventpartial106')
assert(partial.map:create_blank_block(bk))
partial.api.get_meta(bp):set_string('owner','partial')
partial.api.get_node_timer(bp):start(3)
assert(ps:flush())
local after=runtime()
local events=0
after.map:add_event_receiver(function() events=events+1 end)
local ap=after:attachMapBlockStore(sf,'eventpartial106')
assert(ap:load_or_create_blank(bk))
eq(events,0,'partial block import must not emit edit events')
eq(after.api.get_meta(bp):get_string('owner'),'partial')
eq(after.api.get_node_timer(bp):is_started(),true)
-- Event subscriptions belong to Map instances. Replacing the map
-- doesn't leak receiver entries from the discarded map.
local replacement=Map.new()
loaded:replaceMap(replacement)
eq(loaded.map:dispatch_event({type=loaded.map.MEET_OTHER}),0)
print('LUANTI MAP EDIT EVENT RECEIVER AND STREAMING REGRESSION PASS')
