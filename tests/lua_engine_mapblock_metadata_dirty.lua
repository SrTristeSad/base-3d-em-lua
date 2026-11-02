-- Phase 105: node metadata/inventory and timer writes track MapBlock
-- modified state and survive both complete and CONTENT_IGNORE partial saves.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Storage=require('core.storage')
local Inventory=require('core.inventory')
local function eq(a,b,msg)
 assert(a==b,(msg or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
end
local function disk()
 local fs={files={},fail=nil}
 function fs.read(path)
  return fs.files[path],fs.files[path] and nil or 'not found'
 end
 function fs.write_atomic(path,data)
  if path==fs.fail then return false,'disk full' end
  fs.files[path]=data
  return true
 end
 return fs
end
local function runtime()
 local rt=Runtime.new({active_block_range=0})
 rt.api.register_node('test:stone',{})
 rt.api.register_node('test:timer',{})
 return rt
end
local k='-1,0,0'
local pos={x=-16,y=0,z=0}
local fs=disk()
local rt=runtime()
local store=rt:attachMapBlockStore(fs,'metadata105')
assert(rt.map:create_blank_block(k))
local meta=rt.api.get_meta(pos)
-- Reading and constructing empty references does not dirty a MapBlock.
eq(meta:get_string('owner'),'')
local inv=meta:get_inventory()
eq(inv:get_size('main'),0)
local timer=rt.api.get_node_timer(pos)
eq(timer:is_started(),false)
eq(rt.map:get_mapblock_modified_state(k),0)
eq(next(rt.map.modified),nil)
-- Metadata changes are WRITE_NEEDED + REPORT_META_CHANGE (bit 6).
meta:set_string('owner','builder')
eq(rt.map:get_mapblock_modified_state(k),4)
eq(rt.map:get_mapblock_modified_reason(k),64)
eq(rt.map:get_mapblock_modified_reason_string(k),'reportMetadataChange')
rt.map:reset_mapblock_modified(k)
meta:set_int('count',7)
eq(rt.map:get_mapblock_modified_reason(k),64)
rt.map:reset_mapblock_modified(k)
meta:set_float('rate',2.5)
eq(rt.map:get_mapblock_modified_reason(k),64)
rt.map:reset_mapblock_modified(k)
-- Node inventory writes through the same metadata-change notification.
assert(inv:set_size('main',3))
eq(rt.map:get_mapblock_modified_state(k),4)
eq(rt.map:get_mapblock_modified_reason(k),64)
rt.map:reset_mapblock_modified(k)
inv:set_width('main',3)
eq(rt.map:get_mapblock_modified_reason(k),64)
rt.map:reset_mapblock_modified(k)
assert(inv:set_stack('main',1,'test:stone 4'))
eq(rt.map:get_mapblock_modified_reason(k),64)
rt.map:reset_mapblock_modified(k)
eq(inv:add_item('main','test:stone 2'):get_count(),0)
eq(rt.map:get_mapblock_modified_reason(k),64)
rt.map:reset_mapblock_modified(k)
eq(inv:remove_item('main','test:stone 3'):get_count(),3)
eq(rt.map:get_mapblock_modified_reason(k),64)
rt.map:reset_mapblock_modified(k)
-- Read-only inventory methods, invalid set_stack and detached inventories
-- must not modify node metadata.
inv:get_stack('main',1)
inv:get_list('main')
inv:get_lists()
inv:contains_item('main','test:stone 1')
inv:room_for_item('main','test:stone 1')
assert(inv:set_stack('main',99,'test:stone')==false)
eq(rt.map:get_mapblock_modified_state(k),0)
local separate=Inventory.new(rt.registry.items)
separate:set_size('main',2)
separate:set_stack('main',1,'test:stone 1')
eq(rt.map:get_mapblock_modified_state(k),0)
-- set_list, set_lists and from_table also notify the node owner.
inv:set_list('main',{'test:stone 3',nil,nil})
eq(rt.map:get_mapblock_modified_reason(k),64)
rt.map:reset_mapblock_modified(k)
inv:set_lists({main={'test:stone 2'}})
eq(rt.map:get_mapblock_modified_reason(k),64)
rt.map:reset_mapblock_modified(k)
inv:from_table({main={size=2,width=2,stacks={
 {name='test:stone',count=5},false}}})
eq(rt.map:get_mapblock_modified_reason(k),64)
rt.map:reset_mapblock_modified(k)
-- Native NodeTimer methods have no dedicated ModReason: use UNKNOWN
-- with WRITE_AT_UNLOAD as an adapter durability signal, not META_CHANGE.
timer:start(8)
eq(rt.map:get_mapblock_modified_state(k),2)
eq(rt.map:get_mapblock_modified_reason(k),262144)
rt.map:reset_mapblock_modified(k)
timer:set(8,2)
eq(rt.map:get_mapblock_modified_reason(k),262144)
rt.map:reset_mapblock_modified(k)
timer:stop()
eq(rt.map:get_mapblock_modified_reason(k),262144)
rt.map:reset_mapblock_modified(k)
timer:stop()
eq(rt.map:get_mapblock_modified_state(k),0,'stopping absent timer is no-op')
timer:set(8,2)
eq(rt.map:get_mapblock_modified_state(k),2)
-- Replacing lower-severity timer reason with metadata reason:
meta:set_string('owner','after timer')
eq(rt.map:get_mapblock_modified_state(k),4)
eq(rt.map:get_mapblock_modified_reason(k),64)
local ok,written=store:flush()
assert(ok and written==0)
eq(rt.map:get_mapblock_modified_state(k),0)
local image=fs.files[store:partial_path(k)]
assert(image:find('after%20timer',1,true))
assert(image:find('\nT -16 0 0 8 2\n',1,true))
local snapshot=Storage.decode(image,{partial_block=k})
eq(snapshot:get_mapblock_modified_state(k),0,
 'save decoder must reset metadata and timer dirty state')
eq(snapshot:get_mapblock_modified_reason(k),0)
-- An interrupted sidecar write retains both the existing disk image
-- and the dirty reason, even when the mutation clears the last field.
meta:from_table({fields={}})
eq(rt.map:get_mapblock_modified_state(k),4)
eq(rt.map:get_mapblock_modified_reason(k),64)
timer:stop()
eq(rt.map:get_mapblock_modified_reason(k),64)
fs.fail=store:partial_path(k)
assert(not pcall(store.flush,store))
eq(rt.map:get_mapblock_modified_reason(k),64)
eq(fs.files[store:partial_path(k)],image)
fs.fail=nil
assert(store:flush())
eq(rt.map:get_mapblock_modified_state(k),0)
local cleared=fs.files[store:partial_path(k)]
assert(not cleared:find('\nM ',1,true))
assert(not cleared:find('\nL ',1,true))
assert(not cleared:find('\nT ',1,true))
local reload=runtime()
local reloaded=reload:attachMapBlockStore(fs,'metadata105')
assert(reloaded:load_or_create_blank(k))
assert(reload.map.blank_blocks[k])
eq(reload.api.get_meta(pos):get_string('owner'),'')
eq(reload.api.get_meta(pos):get_inventory():get_size('main'),0)
eq(reload.api.get_node_timer(pos):is_started(),false)
eq(reload.map:get_mapblock_modified_state(k),0)
-- Recreate inventory and timer inside a partial block; disk reload
-- must restore without treating the import as a new user modification.
local newmeta=reload.api.get_meta(pos)
newmeta:set_string('owner','survives')
local newinv=newmeta:get_inventory()
newinv:set_size('main',2)
newinv:set_stack('main',1,'test:stone 6')
reload.api.get_node_timer(pos):set(12,3)
assert(reloaded:flush())
local resumed=runtime()
local nextstore=resumed:attachMapBlockStore(fs,'metadata105')
assert(nextstore:load_or_create_blank(k))
eq(resumed.api.get_meta(pos):get_string('owner'),'survives')
eq(resumed.api.get_meta(pos):get_inventory():get_stack('main',1):get_count(),6)
eq(resumed.api.get_node_timer(pos):get_elapsed(),3)
eq(resumed.map:get_mapblock_modified_state(k),0)
eq(resumed.map:get_mapblock_modified_reason(k),0)
-- Replacing an already known AIR(0,0) in a blank block does not
-- change the sparse node; it still has to persist metadata/timer removal.
resumed.map:set_node(pos,{name='air',param1=0,param2=0})
assert(nextstore:flush())
resumed.map:reset_mapblock_modified(k)
resumed.api.set_node(pos,{name='air',param1=0,param2=0})
eq(resumed.map:get_mapblock_modified_state(k),4)
eq(resumed.map:get_mapblock_modified_reason(k),64)
assert(nextstore:flush())
local gone=runtime()
local gonestore=gone:attachMapBlockStore(fs,'metadata105')
assert(gonestore:load_or_create_blank(k))
eq(gone.api.get_meta(pos):get_string('owner'),'')
eq(gone.api.get_node_timer(pos):is_started(),false)
eq(gone.map:get_node(pos).name,'air')
-- A complete MapBlock can be evicted after inventory-only edits:
-- the following image includes the last stack value.
local full='0,0,0'
local fp={x=0,y=0,z=0}
local complete=runtime()
local ds=disk()
local cs=complete:attachMapBlockStore(ds,'complete105')
complete.map:set_node(fp,{name='test:stone'})
complete.map.last_active[full]=0
assert(cs:flush())
local cm=complete.api.get_meta(fp)
local ci=cm:get_inventory()
ci:set_size('main',1)
ci:set_stack('main',1,'test:stone 9')
eq(complete.map:get_mapblock_modified_reason(full),64)
assert(cs:unload(full))
eq(complete.map:get_mapblock_modified_state(full),0)
assert(cs:emerge(full))
eq(complete.map:get_mapblock_modified_state(full),0)
eq(complete.api.get_meta(fp):get_inventory():get_stack('main',1):get_count(),9)
-- Timer expiry is another deletion path, and must not leave an old
-- timer reappearing from the persisted image.
local expired=runtime()
local ef=disk()
local es=expired:attachMapBlockStore(ef,'expiry105')
expired.map:set_node(fp,{name='test:timer'})
expired.map.last_active[full]=0
expired.api.get_node_timer(fp):start(1)
assert(es:flush())
expired:step(1.1)
eq(expired.api.get_node_timer(fp):is_started(),false)
eq(expired.map:get_mapblock_modified_state(full),2)
eq(expired.map:get_mapblock_modified_reason(full),262144)
assert(es:flush())
local check=runtime()
local checkstore=check:attachMapBlockStore(ef,'expiry105')
assert(checkstore:emerge(full))
eq(check.api.get_node_timer(fp):is_started(),false)
print('LUANTI MAPBLOCK METADATA INVENTORY TIMER DURABILITY PASS')
