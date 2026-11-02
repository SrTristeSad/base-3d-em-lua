-- Luanti 5.18 MapBlock::m_lighting_complete (mapblock.h).
-- Per-bank directions 0..5, default 0xffff, dirty-on-change, and
-- durable complete/partial MapBlocks without claiming native light solve.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Map=require('core.map')
local Storage=require('core.storage')
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
end
local function disk()
 local fs={files={},fail_path=nil}
 function fs.read(path)
  return fs.files[path],fs.files[path] and nil or 'not found'
 end
 function fs.write_atomic(path,data)
  if path==fs.fail_path then return nil,'disk full' end
  fs.files[path]=data
  return true
 end
 return fs
end
local function runtime()
 local rt=Runtime.new({active_block_range=0})
 rt.api.register_node('test:lamp',{})
 return rt
end
local full='1,0,0'
local part='-1,0,0'
local fp={x=16,y=0,z=0}
local pp={x=-16,y=0,z=0}
local map=Map.new()
eq(map:get_mapblock_lighting_complete(full),65535)
for _,bank in ipairs({'day','night',0,1}) do
 for d=0,5 do
  eq(map:is_mapblock_lighting_complete(full,bank,d),true)
 end
end
assert(not pcall(map.set_mapblock_lighting_complete,map,full,65535),
 'cannot set flags without a resident MapBlock')
assert(not pcall(map.set_mapblock_lighting_complete_direction,map,
 full,'day',0,true),'direction no-op cannot create a missing mapblock')
map:set_node(fp,{name='test:lamp'})
assert(map:create_blank_block(part))
eq(map:get_mapblock_lighting_complete(part),65535,
 'transient CONTENT_IGNORE mapblocks also start complete flags')
eq(map:set_mapblock_lighting_complete(full,65535),false,
 'setting identical full-word flags does not dirty MapBlock')
eq(map.modified[full],true,'node write was already modified')
map.modified={}
assert(map:set_mapblock_lighting_complete_direction(full,'day',0,false))
eq(map:get_mapblock_lighting_complete(full),65534)
eq(map:is_mapblock_lighting_complete(full,'day',0),false)
eq(map:is_mapblock_lighting_complete(full,'night',0),true)
eq(map.modified[full],true,'flag transition marks MapBlock dirty')
map.modified={}
eq(map:set_mapblock_lighting_complete_direction(full,0,0,false),false)
eq(next(map.modified),nil,'no-op lighting flag must not dirty')
assert(map:set_mapblock_lighting_complete_direction(full,1,5,false))
eq(map:get_mapblock_lighting_complete(full),63486,
 'night bit 11 clears alongside day bit 0')
assert(map:is_mapblock_lighting_complete(full,'night',4))
assert(map:set_mapblock_lighting_complete_direction(full,'night',5,true))
eq(map:get_mapblock_lighting_complete(full),65534)
assert(map:set_mapblock_lighting_complete(full,0))
for _,bank in ipairs({'day','night'}) do
 for d=0,5 do
  eq(map:is_mapblock_lighting_complete(full,bank,d),false)
 end
end
assert(map:set_mapblock_lighting_complete(full,61440),
 'upper reserved 4 bits of the native u16 must be preserved')
eq(map:get_mapblock_lighting_complete(full),61440)
assert(map:set_mapblock_lighting_complete_direction(full,'day',3,true))
eq(map:get_mapblock_lighting_complete(full),61448)
assert(map:set_mapblock_lighting_complete(full,65535))
eq(map.lighting_complete[full],nil,
 'default u16 is represented implicitly')
map.modified={}
assert(not map:set_mapblock_lighting_complete(full,65535))
eq(next(map.modified),nil)
for _,bad in ipairs({-1,65536,0.5,math.huge}) do
 assert(not pcall(map.set_mapblock_lighting_complete,map,full,bad))
end
for _,bank in ipairs({'both','',-1,2}) do
 assert(not pcall(map.is_mapblock_lighting_complete,map,full,bank,0))
end
for _,dir in ipairs({-1,6,1.5}) do
 assert(not pcall(map.is_mapblock_lighting_complete,map,full,'day',dir))
end
assert(not pcall(map.set_mapblock_lighting_complete_direction,map,
 full,'day',0,'false'))
assert(not pcall(map.get_mapblock_lighting_complete,map,'01,0,0'))
-- Q record in LUAENGINE 1 is optional; default-world saves stay unchanged.
local legacy=Storage.encode(map)
assert(not legacy:find('\nQ ',1,true))
local old=Storage.decode(legacy)
eq(old:get_mapblock_lighting_complete(full),65535)
-- The full-world encoder and decoder preserve a sparse nondefault Q record.
map:set_mapblock_lighting_complete(full,63486)
map:set_mapblock_lighting_complete_direction(part,'night',0,false)
eq(map:get_mapblock_lighting_complete(part),65471)
local save=Storage.encode(map)
assert(save:find('\nQ 1 0 0 63486\n',1,true))
assert(save:find('\nQ -1 0 0 65471\n',1,true))
local decoded=Storage.decode(save)
eq(decoded:get_mapblock_lighting_complete(full),63486)
eq(decoded:get_mapblock_lighting_complete(part),65471)
eq(decoded:is_mapblock_lighting_complete(part,'night',0),false)
-- Malformed or foreign/cross-block Q records are rejected before import.
local bads={
 'Q 1 0 0 65536','Q 1 0 0 -1','Q 1 0 0 1.5',
 'Q 1 0 0 nonsense','Q 1 0 0 12 garbage',
 'Q 1939 0 0 12','Q 01 0 0 12'
}
for _,line in ipairs(bads) do
 assert(not pcall(Storage.decode,'LUAENGINE 1\n'..line..'\nEND\n'),
  'invalid Q accepted: '..line)
end
assert(not pcall(Storage.decode,
 'LUAENGINE 1\nQ 0 0 0 0\nQ 0 0 0 1\nEND\n'))
-- The streaming world header may contain global time/chunk markers,
-- never a per-mapblock lighting-complete Q record. Reject it at attach
-- time before changing the runtime clock or residency.
do
 local malicious=disk()
 malicious.files['globalQ101/world.map']=
  'LUAENGINE 1\nQ 1 0 0 0\nEND\n'
 local isolated=runtime()
 assert(not pcall(isolated.attachMapBlockStore,isolated,
  malicious,'globalQ101'))
 eq(next(isolated.map.lighting_complete),nil)
 eq(isolated.map.mapBlockStore,nil)
end
-- Legacy images with no Q must restore the native 0xFFFF default
-- even after a complete segmented disk unload/emerge round trip.
do
 local legacyfs=disk()
 local oldruntime=runtime()
 oldruntime.map:set_node(fp,{name='test:lamp'})
 oldruntime.map.last_active[full]=0
 local oldstore=oldruntime:attachMapBlockStore(legacyfs,'oldQ101')
 assert(oldstore:flush())
 assert(not legacyfs.files[oldstore:path(full)]:find(
  '\nQ ',1,true))
 local after=runtime()
 local restored=after:attachMapBlockStore(legacyfs,'oldQ101')
 assert(restored:emerge(full))
 eq(after.map:get_mapblock_lighting_complete(full),65535)
 assert(after.map:is_mapblock_lighting_complete(full,'night',5))
end
-- Streaming full and partial records remain isolated to their own block.
local fs=disk()
local world=runtime()
local store=world:attachMapBlockStore(fs,'light101')
world.map:set_node(fp,{name='test:lamp',param1=7,param2=8})
world.map.last_active[full]=0
assert(world.map:create_blank_block(part))
world.map:set_node(pp,{name='air',param1=0,param2=0})
world.map:get_meta(pp):set_string('owner','player')
world.map:get_timer(pp):set(10,2.5)
assert(world.map:set_mapblock_lighting_complete(full,63486))
assert(world.map:set_mapblock_lighting_complete_direction(
 part,'night',4,false))
eq(world.map:get_mapblock_lighting_complete(part),64511)
local ok,n=store:flush()
assert(ok and n==1)
assert(fs.files[store:path(full)]:find('\nQ 1 0 0 63486\n',1,true))
assert(fs.files[store:partial_path(part)]:find(
 '\nQ -1 0 0 64511\n',1,true))
assert(not fs.files[store:path(part)])
-- Independent process reloads exact flags and preserves ungenerated status.
local nextworld=runtime()
local nextstore=nextworld:attachMapBlockStore(fs,'light101')
assert(nextstore:emerge(full))
assert(nextstore:load_or_create_blank(part))
eq(nextworld.map:get_mapblock_lighting_complete(full),63486)
eq(nextworld.map:get_mapblock_lighting_complete(part),64511)
assert(nextworld.map.blank_blocks[part])
eq(nextworld.map:get_node(pp).name,'air')
eq(nextworld.map:get_meta(pp):get_string('owner'),'player')
eq(nextworld.map:get_timer(pp):get_elapsed(),2.5)
assert(not nextworld.map.blank_blocks[full])
assert(nextstore:unload(full))
eq(nextworld.map.lighting_complete[full],nil,
 'eviction must discard resident lighting flags')
eq(nextworld.map:get_mapblock_lighting_complete(full),65535)
assert(nextstore:emerge(full))
eq(nextworld.map:get_mapblock_lighting_complete(full),63486)
-- A foreign Q entry in a complete or partial image must reject the
-- whole image before any resident metadata/nodes/flags are mutated.
for _,kind in ipairs({'full','partial'}) do
 local probe=runtime()
 local readfs=disk()
 local ps=probe:attachMapBlockStore(readfs,'corrupt101')
 local target=kind=='full' and full or part
 local src=kind=='full' and store:path(full) or store:partial_path(part)
 local path=kind=='full' and ps:path(full) or ps:partial_path(part)
 readfs.files[path]=fs.files[src]:gsub('Q %-?%d+ 0 0 %d+',
  'Q 3 0 0 1')
 assert(not pcall(ps.load_or_create_blank,ps,target),
  'foreign lighting flags must reject full/partial image')
 eq(next(probe.map.lighting_complete),nil)
 eq(next(probe.map.nodes),nil)
 assert(not probe.map.blank_blocks[target])
end
-- In an atomic-write failure, the changed flags remain live and can
-- be persisted on a later successful flush.
local failure=runtime()
local failfs=disk()
local failed=failure:attachMapBlockStore(failfs,'fail101')
assert(failure.map:create_blank_block(part))
assert(failure.map:set_mapblock_lighting_complete(part,0))
failfs.fail_path=failed:partial_path(part)
assert(not pcall(failed.flush,failed))
eq(failure.map:get_mapblock_lighting_complete(part),0)
failfs.fail_path=nil
assert(failed:flush())
assert(failfs.files[failed:partial_path(part)])
-- Transition from partial to generated retains the lighting flags.
assert(nextworld.map:finish_blank_block(part))
nextworld.map.last_active[part]=0
assert(nextstore:flush())
local complete=runtime()
local cs=complete:attachMapBlockStore(fs,'light101')
assert(cs:emerge(part))
assert(not complete.map.blank_blocks[part])
eq(complete.map:get_mapblock_lighting_complete(part),64511)
print('LUANTI MAPBLOCK LIGHTING COMPLETE FLAGS AND STREAMING PASS')
