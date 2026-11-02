-- Luanti 5.18 mapblock.h: MapBlock::setIsUnderground always marks
-- WRITE_NEEDED; mapblock.cpp serializes the persisted underground bit.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Map=require('core.map')
local Storage=require('core.storage')
local Runtime=require('core.runtime')
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
end
local function disk()
 local fs={files={},fail_path=nil}
 function fs.read(path)
  return fs.files[path],fs.files[path] and nil or 'not found'
 end
 function fs.write_atomic(path,data)
  if path==fs.fail_path then return nil,'simulated write failure' end
  fs.files[path]=data
  return true
 end
 return fs
end
local function runtime()
 local r=Runtime.new({active_block_range=0})
 r.api.register_node('test:rock',{})
 return r
end
local full='1,0,0'
local partial='-1,0,0'
local rock={x=16,y=0,z=0}
local marker={x=-16,y=0,z=0}
local map=Map.new()
eq(map:get_mapblock_is_underground(full),false)
assert(not pcall(map.set_mapblock_is_underground,map,full,true))
assert(not pcall(map.set_mapblock_is_underground,map,'01,0,0',true))
assert(not pcall(map.set_mapblock_is_underground,map,full,1))
map:set_node(rock,{name='test:rock'})
map.last_active[full]=0
assert(map:create_blank_block(partial))
assert(map:set_mapblock_is_underground(full,true))
eq(map:get_mapblock_is_underground(full),true)
eq(map:get_mapblock_is_underground(partial),false)
eq(map.modified[full],true)
map.modified={}
eq(map:set_mapblock_is_underground(full,true),false)
eq(map.modified[full],true,
 'native setter marks WRITE_NEEDED even with identical value')
map.modified={}
assert(map:set_mapblock_is_underground(full,false))
eq(map.underground[full],nil,'default is a sparse false flag')
eq(map.modified[full],true)
-- Full-word light-completion flags are independent from underground.
assert(map:set_mapblock_lighting_complete(full,0))
assert(map:set_mapblock_is_underground(full,true))
eq(map:get_mapblock_lighting_complete(full),0)
eq(map:get_mapblock_is_underground(full),true)
-- Full-world LUAENGINE 1 preserves the optional U flag and Q record
-- without migrating the existing file header.
local image=Storage.encode(map)
assert(image:find('\nU 1 0 0 1\n',1,true))
assert(image:find('\nQ 1 0 0 0\n',1,true))
local decoded=Storage.decode(image)
eq(decoded:get_mapblock_is_underground(full),true)
eq(decoded:get_mapblock_lighting_complete(full),0)
eq(decoded:get_mapblock_is_underground(partial),false)
assert(map:set_mapblock_is_underground(full,false))
local legacy=Storage.encode(map)
assert(not legacy:find('\nU ',1,true))
eq(Storage.decode(legacy):get_mapblock_is_underground(full),false)
-- U is a canonical mapblock coordinate plus a literal 1.
for _,line in ipairs({
 'U 1 0 0 0','U 1 0 0 false','U 1 0 0 2',
 'U 1 0 0 1 garbage','U 01 0 0 1',
 'U 0 -0 0 1','U 1939 0 0 1','U 0 0 0 -1'
}) do
 assert(not pcall(Storage.decode,'LUAENGINE 1\n'..line..'\nEND\n'),
  'invalid underground record accepted: '..line)
end
assert(not pcall(Storage.decode,
 'LUAENGINE 1\nQ 0 -0 0 2\nEND\n'),
 'Q record also requires canonical coordinates under LuaJIT')
assert(not pcall(Storage.decode,
 'LUAENGINE 1\nU 0 0 0 1\nU 0 0 0 1\nEND\n'),
 'duplicate U flags must be rejected')
-- A per-block flag cannot be placed in the global streaming header.
local globalfs=disk()
globalfs.files['world102/world.map']='LUAENGINE 1\nU 1 0 0 1\nEND\n'
local rejected=runtime()
assert(not pcall(rejected.attachMapBlockStore,rejected,globalfs,'world102'))
assert(rejected.map.mapBlockStore==nil)
assert(next(rejected.map.underground)==nil)
-- Complete and partial mapblocks store their own flags independently.
local fs=disk()
local w=runtime()
local store=w:attachMapBlockStore(fs,'underground102')
w.map:set_node(rock,{name='test:rock',param1=4,param2=9})
w.map.last_active[full]=0
assert(w.map:create_blank_block(partial))
w.map:set_node(marker,{name='air',param1=0,param2=0})
w.map:get_meta(marker):set_string('owner','builder')
w.map:get_timer(marker):set(9,2)
assert(w.map:set_mapblock_is_underground(full,true))
assert(w.map:set_mapblock_is_underground(partial,true))
assert(w.map:set_mapblock_lighting_complete(partial,0))
local ok,count=store:flush()
assert(ok and count==1)
assert(fs.files[store:path(full)]:find('\nU 1 0 0 1\n',1,true))
assert(fs.files[store:partial_path(partial)]:find(
 '\nU -1 0 0 1\n',1,true))
assert(fs.files[store:partial_path(partial)]:find(
 '\nQ -1 0 0 0\n',1,true))
assert(not fs.files[store:path(partial)])
local resumed=runtime()
local load=resumed:attachMapBlockStore(fs,'underground102')
assert(load:emerge(full))
assert(load:load_or_create_blank(partial))
eq(resumed.map:get_mapblock_is_underground(full),true)
eq(resumed.map:get_mapblock_is_underground(partial),true)
eq(resumed.map:get_mapblock_lighting_complete(partial),0)
eq(resumed.map:get_node(marker).name,'air')
eq(resumed.map:get_meta(marker):get_string('owner'),'builder')
eq(resumed.map:get_timer(marker):get_elapsed(),2)
assert(resumed.map.blank_blocks[partial])
assert(load:unload(full))
eq(resumed.map:get_mapblock_is_underground(full),false)
assert(load:emerge(full))
eq(resumed.map:get_mapblock_is_underground(full),true)
-- Reset both custom flags to their defaults and verify that flush
-- REPLACES the previous .map.partial, rather than reviving stale data.
assert(resumed.map:set_mapblock_is_underground(partial,false))
assert(resumed.map:set_mapblock_lighting_complete(partial,65535))
assert(load:flush())
local partialsave=fs.files[load:partial_path(partial)]
assert(not partialsave:find('\nU ',1,true))
assert(not partialsave:find('\nQ ',1,true))
local clear=runtime()
local clearstore=clear:attachMapBlockStore(fs,'underground102')
assert(clearstore:load_or_create_blank(partial))
eq(clear.map:get_mapblock_is_underground(partial),false)
eq(clear.map:get_mapblock_lighting_complete(partial),65535)
eq(clear.map:get_meta(marker):get_string('owner'),'builder')
eq(clear.map:get_timer(marker):get_elapsed(),2)
assert(clear.map.blank_blocks[partial])
-- Empty CONTENT_IGNORE partial blocks with flag-only content must also
-- persist. A subsequent reset writes an empty image, not stale U=true.
local bare=runtime()
local barefs=disk()
local barestore=bare:attachMapBlockStore(barefs,'empty102')
assert(bare.map:create_blank_block(partial))
assert(bare.map:set_mapblock_is_underground(partial,true))
assert(barestore:flush())
assert(barefs.files[barestore:partial_path(partial)]:find(
 '\nU -1 0 0 1\n',1,true))
assert(bare.map:set_mapblock_is_underground(partial,false))
assert(barestore:flush())
assert(not barefs.files[barestore:partial_path(partial)]:find(
 '\nU ',1,true))
local reboot=runtime()
local boot=reboot:attachMapBlockStore(barefs,'empty102')
assert(boot:load_or_create_blank(partial))
eq(reboot.map:get_mapblock_is_underground(partial),false)
eq(reboot.map:get_node(marker).name,'ignore')
-- Foreign flag records abort before any nodes/timers/flags are restored.
for _,which in ipairs({'complete','partial'}) do
 local corrupted=runtime()
 local badfs=disk()
 local badstore=corrupted:attachMapBlockStore(badfs,'bad102')
 local target=which=='complete' and full or partial
 local src=which=='complete' and store:path(full) or
  store:partial_path(partial)
 local path=which=='complete' and badstore:path(full) or
  badstore:partial_path(partial)
 badfs.files[path]=fs.files[src]..'' -- text from a valid image
 badfs.files[path]=badfs.files[path]:gsub(
  '\nU %-?%d+ 0 0 1\n','\nU 3 0 0 1\n')
 if which=='partial' then
  -- The saved partial was reset above; inject a foreign U before END.
  badfs.files[path]=badfs.files[path]:gsub(
   '\nEND\n','\nU 3 0 0 1\nEND\n')
 end
 assert(not pcall(badstore.load_or_create_blank,badstore,target))
 assert(next(corrupted.map.nodes)==nil)
 assert(next(corrupted.map.underground)==nil)
 assert(not corrupted.map.blank_blocks[target])
end
-- Atomic write failure must retain the latest resident flag value.
local faulty=runtime()
local failedfs=disk()
local failed=faulty:attachMapBlockStore(failedfs,'fault102')
assert(faulty.map:create_blank_block(partial))
assert(faulty.map:set_mapblock_is_underground(partial,true))
failedfs.fail_path=failed:partial_path(partial)
assert(not pcall(failed.flush,failed))
eq(faulty.map:get_mapblock_is_underground(partial),true)
failedfs.fail_path=nil
assert(failed:flush())
-- Completing a partial block retains its underground flag until it is
-- reserialized as a fully generated MapBlock.
assert(w.map:finish_blank_block(partial))
w.map.last_active[partial]=0
assert(store:flush())
local complete=runtime()
local cstore=complete:attachMapBlockStore(fs,'underground102')
assert(cstore:emerge(partial))
assert(not complete.map.blank_blocks[partial])
eq(complete.map:get_mapblock_is_underground(partial),true)
print('LUANTI MAPBLOCK UNDERGROUND FLAG AND STREAMING PASS')
