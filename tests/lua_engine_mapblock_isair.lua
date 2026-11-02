-- Luanti 5.18 src/mapblock.cpp actuallyUpdateIsAir/expireIsAirCache
-- All 4096 MapNode CONTENT_AIR values determine isAir, not param1 or
-- param2, metadata, timers, luminosity or neighboring blocks.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Map=require('core.map')
local Runtime=require('core.runtime')
local Buffer=require('core.mapgen_voxelbuffer')
local Chunk=require('core.mapgen_chunk')
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
end
local map=Map.new()
local p={x=0,y=0,z=0}
local q={x=16,y=0,z=0}
local neg={x=-1,y=0,z=0}
local block='0,0,0'
local neighbor='1,0,0'
local negative='-1,0,0'
eq(map:is_mapblock_air(block),nil,'unloaded block is not an air MapBlock')
assert(not pcall(map.is_mapblock_air,map,'0,00,0'))
assert(not pcall(map.is_mapblock_air,map,'../../etc'))
map:set_node(p,{name='test:stone'})
eq(map:is_mapblock_air(block),false)
local scans=map.block_air_scans
eq(map:is_mapblock_air(block),false)
eq(map.block_air_scans,scans,'lazy cache hit avoids second full scan')
map:set_node(p,{name='air',param1=17,param2=29})
eq(map.block_air_cache[block],nil,'Map:set_node expires cache')
eq(map:is_mapblock_air(block),true,'AIR with parameters remains AIR')
map:set_node(p,{name='air',param1=17,param2=29})
eq(map.block_air_cache[block],nil,
 'even identical MapNode writes expire native-style isAir cache')
eq(map:is_mapblock_air(block),true)
map:set_node(q,{name='test:stone'})
eq(map:is_mapblock_air(block),true,'neighbor edits leave cached isAir valid')
eq(map:is_mapblock_air(neighbor),false)
map:set_node(neg,{name='test:stone'})
eq(map:is_mapblock_air(negative),false,'signed block division')
map:set_node(neg,{name='air'})
eq(map:is_mapblock_air(negative),true,'zero-param AIR is sparse')
-- Node metadata and timers do not change the CONTENT_AIR predicate.
map:get_meta({x=1,y=0,z=0}):set_string('owner','tester')
map:get_timer({x=1,y=0,z=0}):start(7)
eq(map:is_mapblock_air(block),true)
eq(map:is_mapblock_air('5,0,0'),nil)
map:get_meta({x=80,y=0,z=0}):set_string('owner','metadata only')
eq(map:is_mapblock_air('5,0,0'),true,
 'metadata-only resident mapblock has implicit known AIR')
-- New blank MapBlocks consist entirely of CONTENT_IGNORE, not AIR.
local partial=Map.new()
assert(partial:create_blank_block(negative))
eq(partial:is_mapblock_air(negative),false)
local blankscans=partial.block_air_scans
eq(partial:is_mapblock_air(negative),false)
eq(partial.block_air_scans,blankscans)
partial:set_node(neg,{name='air',param1=1,param2=2})
eq(partial:is_mapblock_air(negative),false,
 'single known AIR does not fill a 16^3 unknown blank block')
-- Every position must be AIR (and no CONTENT_IGNORE remains).
for z=0,15 do for y=0,15 do for x=-16,-1 do
 partial:set_node({x=x,y=y,z=z},{name='air'})
end end end
eq(partial:is_mapblock_air(negative),true,
 'explicit full 4096-cell AIR is an all-air ungenerated MapBlock')
assert(partial.blank_blocks[negative])
partial:set_node(neg,{name='test:stone'})
eq(partial:is_mapblock_air(negative),false)
partial:set_node(neg,{name='air'})
eq(partial:is_mapblock_air(negative),true)
assert(partial:finish_blank_block(negative))
eq(partial.block_air_cache[negative],nil,
 'completing transient blank block expires CONTENT_IGNORE cache')
eq(partial:is_mapblock_air(negative),true)
eq(partial:get_node({x=-2,y=0,z=0}).name,'air')
assert(partial.count==0,'zero-param AIR pruned on completion')
-- A partly-known blank block transitions from false to true upon
-- successful finalization; implicit IGNORE becomes sparse AIR.
local transition=Map.new()
assert(transition:create_blank_block(block))
eq(transition:is_mapblock_air(block),false)
assert(transition:finish_blank_block(block))
transition.last_active[block]=0
eq(transition:is_mapblock_air(block),true)
-- Full blitBackAll explicitly expires the cache even if all nodes
-- are byte-identical. This mirrors MapBlock::expireIsAirCache().
local r=Runtime.new({mapgen={seed=100,mg_name='v7'}})
r.api.register_node('test:stone',{})
r.map:set_node(p,{name='test:stone'})
r.map.last_active[block]=0
eq(r.map:is_mapblock_air(block),false)
local geo=Chunk.geometry({x=0,y=0,z=0},1)
local vm=Buffer.new(r.map,geo)
vm:initialEmerge(false)
local before=r.map.block_air_scans
local changed,n=vm:blitBackAll(true)
assert(changed[block])
eq(n,0)
eq(r.map.block_air_cache[block],nil,
 'MMVManip blit must expire cache even for identical copyTo')
eq(r.map:is_mapblock_air(block),false)
eq(r.map.block_air_scans,before+1)
-- Streaming: unloading must drop cached values so an absent block
-- is not accidentally read as air after its disk data changes.
local disk={files={}}
function disk.read(path)
 return disk.files[path],disk.files[path] and nil or 'not found'
end
function disk.write_atomic(path,data) disk.files[path]=data;return true end
local rt=Runtime.new({active_block_range=0})
rt.api.register_node('test:stone',{})
rt.map:set_node({x=-16,y=0,z=0},{name='air',param1=1})
rt.map.last_active[negative]=0
local store=rt:attachMapBlockStore(disk,'air100')
eq(rt.map:is_mapblock_air(negative),true)
assert(store:unload(negative))
eq(rt.map.block_air_cache[negative],nil)
eq(rt.map:is_mapblock_air(negative),nil)
-- Disk-backed reemergence reconstructs cache lazily from real MapNodes.
assert(store:emerge(negative))
eq(rt.map:is_mapblock_air(negative),true)
rt.map:set_node({x=-16,y=0,z=0},{name='test:stone'})
eq(rt.map:is_mapblock_air(negative),false)
assert(store:unload(negative))
eq(rt.map:is_mapblock_air(negative),nil)
assert(store:emerge(negative))
eq(rt.map:is_mapblock_air(negative),false)
-- No air-cache records are added to the backward-compatible save.
assert(not disk.files[store:path(negative)]:find('IS_AIR',1,true))
print('LUANTI MAPBLOCK ISAIR CACHE, BLIT INVALIDATION AND STREAMING PASS')
