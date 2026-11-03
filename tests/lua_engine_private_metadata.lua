-- Luanti NodeMetaRef get_keys, mark_as_private, per-field edit
-- notifications, and private disk persistence in full/partial MapBlocks.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Storage=require('core.storage')
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': '..tostring(a)..' vs '..tostring(b))
end
local function fsnew()
 local fs={files={}}
 function fs.read(path) return fs.files[path],fs.files[path] and nil or 'not found' end
 function fs.write_atomic(path,data) fs.files[path]=data;return true end
 return fs
end
local function runtime()
 local r=Runtime.new({active_block_range=0})
 r.api.register_node('test:stone',{})
 return r
end
local rt=runtime()
local fs=fsnew()
local store=rt:attachMapBlockStore(fs,'private-meta')
local pos={x=-16,y=0,z=0}
local block='-1,0,0'
assert(rt.map:create_blank_block(block))
local events={}
rt.map:add_event_receiver(function(e) events[#events+1]=e end)
local meta=rt.api.get_meta(pos)
eq(#meta:get_keys(),0)
meta:set_string('name','public')
eq(#events,1)
eq(events[1].is_private_change,false)
rt.map:reset_mapblock_modified(block)
meta:set_string('name','public')
eq(#events,1,'idempotent field write is not a metadata change')
eq(rt.map:get_mapblock_modified_state(block),0)
meta:mark_as_private({'name','future'})
eq(#events,2)
eq(events[2].is_private_change,false)
meta:mark_as_private('name')
eq(#events,2,'marking private twice does not modify')
meta:set_string('name','secret')
eq(#events,3)
eq(events[3].is_private_change,true)
meta:set_string('future','invisible')
eq(events[4].is_private_change,true,
 'a pre-marked absent key becomes private when created')
meta:set_int('count',7)
meta:set_float('rate',1.5)
local names=meta:get_keys()
eq(table.concat(names,','),'count,future,name,rate')
eq(meta:contains('name'),true)
local public=meta:to_table()
eq(public.fields.name,'secret')
eq(public.private,nil,'private field markers are not exposed by to_table')
-- Empty value removes the key. A marked key may be absent in memory;
-- disk serialization only writes V for fields still present.
meta:set_string('name','')
eq(meta:contains('name'),false)
eq(events[#events].is_private_change,true)
assert(store:flush())
local partial=fs.files[store:partial_path(block)]
assert(partial:find('\nV -16 0 0 future\n',1,true))
assert(not partial:find('\nV -16 0 0 name\n',1,true))
local decoded=Storage.decode(partial,{partial_block=block})
eq(decoded.metadata['-16,0,0'].private.future,true)
eq(decoded.metadata['-16,0,0'].private.name,nil)
eq(decoded:get_mapblock_modified_state(block),0)
local recovered=runtime()
local recovered_events=0
recovered.map:add_event_receiver(function() recovered_events=recovered_events+1 end)
local store2=recovered:attachMapBlockStore(fs,'private-meta')
assert(store2:load_or_create_blank(block))
eq(recovered_events,0,'restoring private fields is not a user edit')
local restored=recovered.api.get_meta(pos)
eq(restored:get_string('future'),'invisible')
eq(restored:get_string('name'),'')
local flags={}
recovered.map:add_event_receiver(function(e)
 if e.type==recovered.map.MEET_BLOCK_NODE_METADATA_CHANGED then
  flags[#flags+1]=e.is_private_change
 end
end)
restored:set_string('future','retained')
eq(flags[#flags],true)
restored:set_string('name','new public value')
eq(flags[#flags],false)
restored:from_table({fields={owner='after reset'}})
eq(flags[#flags],false)
eq(restored:get_string('future'),'')
eq(restored:get_string('owner'),'after reset')
eq(#restored:get_keys(),1)
assert(store2:flush())
local final=fs.files[store2:partial_path(block)]
assert(not final:find('\nV ',1,true),
 'from_table clears private markers as in the native API')
local restarted=runtime()
local store3=restarted:attachMapBlockStore(fs,'private-meta')
assert(store3:load_or_create_blank(block))
eq(restarted.api.get_meta(pos):get_string('owner'),'after reset')
eq(next(restarted.map.metadata['-16,0,0'].private),nil)
for _,save in ipairs({
 'LUAENGINE 1\nV 0 0 0 orphan\nEND\n',
 'LUAENGINE 1\nM 0 0 0 owner value\nV 0 0 0 owner\nV 0 0 0 owner\nEND\n'
}) do
 assert(not pcall(Storage.decode,save),
  'invalid private metadata record was accepted')
end
-- Full MapBlock path persists privacy too.
local full=runtime()
local ffs=fsnew()
local fullstore=full:attachMapBlockStore(ffs,'full-private')
local here={x=0,y=0,z=0}
local fk='0,0,0'
full.map:set_node(here,{name='test:stone'})
full.map.last_active[fk]=0
local fullmeta=full.api.get_meta(here)
fullmeta:set_string('password_hint','not a real password')
fullmeta:mark_as_private('password_hint')
assert(fullstore:flush())
local resumed=runtime()
local resstore=resumed:attachMapBlockStore(ffs,'full-private')
assert(resstore:emerge(fk))
eq(resumed.map.metadata['0,0,0'].private.password_hint,true)
eq(resumed.map:get_mapblock_modified_state(fk),0)
print('NATIVE NODE META PRIVATE FIELDS AND STREAMING PASS')
