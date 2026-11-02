-- Luanti 5.18 MapBlock::setTimestamp, setTimestampNoChangedFlag,
-- getDiskTimestamp and raiseModified disk timestamp capture.
-- All tests must pass in both Lua 5.4 and LuaJIT.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Map=require('core.map')
local Runtime=require('core.runtime')
local Storage=require('core.storage')
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
end
local function disk()
 local fs={files={},fail=nil}
 function fs.read(path)
  return fs.files[path],fs.files[path] and nil or 'not found'
 end
 function fs.write_atomic(path,content)
  if path==fs.fail then return nil,'simulated atomic disk failure' end
  fs.files[path]=content
  return true
 end
 return fs
end
local function runtime()
 local rt=Runtime.new({active_block_range=0})
 rt.api.register_node('test:rock',{})
 return rt
end
local U=4294967295
local a='0,0,0'
local b='-1,0,0'
local p={x=0,y=0,z=0}
local q={x=-16,y=0,z=0}
local map=Map.new()
eq(map.BLOCK_TIMESTAMP_UNDEFINED,U)
eq(map:get_mapblock_timestamp(a),U)
eq(map:get_mapblock_disk_timestamp(a),U)
assert(not pcall(map.set_mapblock_timestamp,map,a,0))
assert(not pcall(map.set_mapblock_timestamp_no_changed_flag,map,a,0))
assert(not pcall(map.get_mapblock_timestamp,map,'01,0,0'))
assert(not pcall(map.set_mapblock_timestamp,map,'0,-0,0',1))
for _,invalid in ipairs({-1,1.5,math.huge,4294967296,'0'}) do
 assert(not pcall(map.set_mapblock_timestamp,map,a,invalid))
end
assert(map:create_blank_block(a))
-- NoChangedFlag mutates only the timestamp, never dirty state.
assert(map:set_mapblock_timestamp_no_changed_flag(a,41))
eq(map:get_mapblock_timestamp(a),41)
eq(map:get_mapblock_disk_timestamp(a),U)
eq(map:get_mapblock_modified_state(a),0)
eq(map.modified[a],nil)
assert(map:set_mapblock_timestamp(a,42))
eq(map:get_mapblock_timestamp(a),42)
eq(map:get_mapblock_disk_timestamp(a),42,
 'raising CLEAN to WRITE_AT_UNLOAD captures the new timestamp')
eq(map:get_mapblock_modified_state(a),2)
eq(map:get_mapblock_modified_reason(a),map.MOD_REASON_SET_TIMESTAMP)
-- Same severity does not recapture the deprecated disk timestamp.
map:set_mapblock_timestamp(a,43)
eq(map:get_mapblock_timestamp(a),43)
eq(map:get_mapblock_disk_timestamp(a),42)
eq(map:get_mapblock_modified_reason(a),32)
-- Higher severity should replace SET_TIMESTAMP and capture current time.
map:set_node(p,{name='test:rock'})
eq(map:get_mapblock_modified_state(a),4)
eq(map:get_mapblock_modified_reason(a),16)
eq(map:get_mapblock_disk_timestamp(a),43)
map:set_mapblock_timestamp(a,44)
eq(map:get_mapblock_modified_state(a),4)
eq(map:get_mapblock_modified_reason(a),16,
 'lower severity never replaces SET_NODE')
eq(map:get_mapblock_disk_timestamp(a),43)
map:reset_mapblock_modified(a)
eq(map:get_mapblock_disk_timestamp(a),43,
 'native resetModified never changes disk timestamp')
eq(map:get_mapblock_timestamp(a),44)
assert(map:set_mapblock_timestamp_no_changed_flag(a,U))
eq(map.block_timestamps[a],nil)
eq(map:get_mapblock_timestamp(a),U)
eq(map:get_mapblock_modified_state(a),0)
-- setTimestamp always raises even on an identical u32.
map:set_mapblock_timestamp(a,U)
eq(map:get_mapblock_modified_state(a),2)
eq(map:get_mapblock_disk_timestamp(a),U)
map:reset_mapblock_modified(a)
assert(map:set_mapblock_timestamp_no_changed_flag(a,4000000000))
eq(map:get_mapblock_timestamp(a),4000000000)
-- Full LUAENGINE 1 save keeps B activity and optional P u32 separate.
map.last_active[a]=1.25
map.game_time=13.75
local encoded=Storage.encode(map)
assert(encoded:find('\nP 0 0 0 4000000000\n',1,true))
assert(encoded:find('\nB 0 0 0 1.25\n',1,true))
local loaded=Storage.decode(encoded)
eq(loaded.block_timestamps[a],4000000000)
eq(loaded:get_mapblock_timestamp(a),4000000000)
eq(loaded.last_active[a],1.25)
eq(loaded.game_time,13.75)
map:set_mapblock_timestamp_no_changed_flag(a,U)
assert(not Storage.encode(map):find('\nP ',1,true))
-- Old saves are accepted with native undefined timestamp.
local old=Storage.decode('LUAENGINE 1\nB 0 0 0 1.25\nC 13.75\nEND\n')
eq(old:get_mapblock_timestamp(a),U)
eq(old.last_active[a],1.25)
for _,line in ipairs({
 'P 0 0 0 -1','P 0 0 0 4294967295',
 'P 0 0 0 4294967296','P 0 0 0 1.5',
 'P 0 0 0 garbage','P 0 0 0 1 extra',
 'P 00 0 0 1','P 0 -0 0 1',
 'P 1939 0 0 1','P 0 0 0 01'
}) do
 assert(not pcall(Storage.decode,'LUAENGINE 1\n'..line..'\nEND\n'),
  'malformed P accepted: '..line)
end
assert(not pcall(Storage.decode,
 'LUAENGINE 1\nP 0 0 0 1\nP 0 0 0 2\nEND\n'),
 'duplicate P records must reject save')
-- Global world header cannot smuggle per-MapBlock timestamps.
local fs=disk()
fs.files['bad104/world.map']='LUAENGINE 1\nP 0 0 0 77\nEND\n'
local illegal=runtime()
assert(not pcall(illegal.attachMapBlockStore,illegal,fs,'bad104'))
eq(illegal.map.mapBlockStore,nil)
-- Persist a generated block with B=1.25 and P=4000000000,
-- plus a partial CONTENT_IGNORE block with P=0 and explicit AIR.
local rt=runtime()
local store=rt:attachMapBlockStore(fs,'world104')
rt.clock=13.75
rt.map.game_time=13.75
rt.map:set_node(p,{name='test:rock'})
rt.map.last_active[a]=1.25
rt.map:reset_mapblock_modified(a)
rt.map:set_mapblock_timestamp(a,4000000000)
assert(rt.map:create_blank_block(b))
rt.map:set_node(q,{name='air',param1=0,param2=0})
rt.map:reset_mapblock_modified(b)
rt.map:set_mapblock_timestamp(b,0)
eq(rt.map:get_mapblock_disk_timestamp(b),0)
local ok,count=store:flush()
assert(ok and count==1)
eq(rt.map:get_mapblock_modified_state(a),0)
eq(rt.map:get_mapblock_modified_state(b),0)
eq(rt.map:get_mapblock_disk_timestamp(a),4000000000)
assert(fs.files[store:path(a)]:find(
 '\nP 0 0 0 4000000000\n',1,true))
assert(fs.files[store:path(a)]:find(
 '\nB 0 0 0 1.25\n',1,true))
assert(fs.files[store:partial_path(b)]:find(
 '\nP -1 0 0 0\n',1,true))
local resumed=runtime()
local reloaded=resumed:attachMapBlockStore(fs,'world104')
assert(reloaded:emerge(a))
assert(reloaded:load_or_create_blank(b))
eq(resumed.map.last_active[a],1.25)
eq(resumed.map:get_mapblock_timestamp(a),4000000000)
eq(resumed.map:get_mapblock_disk_timestamp(a),4000000000)
eq(resumed.map:get_mapblock_modified_state(a),0)
eq(resumed.map:get_mapblock_timestamp(b),0)
eq(resumed.map:get_mapblock_disk_timestamp(b),0)
eq(resumed.map:get_node(q).name,'air')
eq(resumed.map:get_node({x=-15,y=0,z=0}).name,'ignore')
assert(resumed.map.blank_blocks[b])
-- Setter at identical value makes WRITE_AT_UNLOAD. Failed atomic
-- write preserves both the original disk image and dirty diagnostics.
local initial=fs.files[reloaded:partial_path(b)]
resumed.map:set_mapblock_timestamp(b,7)
eq(resumed.map:get_mapblock_modified_state(b),2)
eq(resumed.map:get_mapblock_disk_timestamp(b),7)
fs.fail=reloaded:partial_path(b)
assert(not pcall(reloaded.flush,reloaded))
eq(fs.files[reloaded:partial_path(b)],initial)
eq(resumed.map:get_mapblock_modified_state(b),2)
eq(resumed.map:get_mapblock_modified_reason(b),32)
fs.fail=nil
assert(reloaded:flush())
eq(resumed.map:get_mapblock_modified_state(b),0)
eq(resumed.map:get_mapblock_disk_timestamp(b),7)
local after=runtime()
local afterstore=after:attachMapBlockStore(fs,'world104')
assert(afterstore:load_or_create_blank(b))
eq(after.map:get_mapblock_timestamp(b),7)
eq(after.map:get_mapblock_disk_timestamp(b),7)
-- Reset to undefined must remove the old P record, even without
-- changing a node; a subsequent restart must not resurrect 7.
after.map:set_mapblock_timestamp(b,U)
assert(afterstore:flush())
assert(not fs.files[afterstore:partial_path(b)]:find('\nP ',1,true))
local restart=runtime()
local rs=restart:attachMapBlockStore(fs,'world104')
assert(rs:load_or_create_blank(b))
eq(restart.map:get_mapblock_timestamp(b),U)
eq(restart.map:get_mapblock_disk_timestamp(b),U)
-- A foreign timestamp record fails validation BEFORE nodes are loaded.
for _,partial in ipairs({false,true}) do
 local broken=disk()
 local r=runtime()
 local st=r:attachMapBlockStore(broken,'foreign104')
 local target=partial and b or a
 local orig=partial and store:partial_path(b) or store:path(a)
 local dest=partial and st:partial_path(b) or st:path(a)
 broken.files[dest]=fs.files[orig]:gsub(
  '\nP %-?%d+ 0 0 %d+\n','\nP 3 0 0 12\n')
 if partial and not broken.files[dest]:find('\nP ',1,true) then
  broken.files[dest]=fs.files[store:partial_path(b)]:gsub(
   '\nEND\n','\nP 3 0 0 12\nEND\n')
 end
 assert(not pcall(st.load_or_create_blank,st,target))
 eq(next(r.map.nodes),nil)
 eq(next(r.map.block_timestamps),nil)
 assert(not r.map.blank_blocks[target])
end
-- A completed streamed MapBlock can be evicted and reloaded cleanly.
resumed.map:set_mapblock_timestamp(a,100)
assert(reloaded:unload(a))
eq(resumed.map:get_mapblock_timestamp(a),U)
eq(resumed.map:get_mapblock_disk_timestamp(a),U)
assert(reloaded:emerge(a))
eq(resumed.map:get_mapblock_timestamp(a),100)
eq(resumed.map:get_mapblock_disk_timestamp(a),100)
eq(resumed.map.last_active[a],1.25,
 'streaming snapshot preserves the LBM last_active independently from P')
print('LUANTI MAPBLOCK TIMESTAMP AND DISK STATUS STREAMING PASS')
