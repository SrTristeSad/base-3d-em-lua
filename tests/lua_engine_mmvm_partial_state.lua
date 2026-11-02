-- Luanti 5.18 MapBlock: CONTENT_IGNORE / !isGenerated snapshots
-- must retain nodes, metadata, inventories and timers across disk reload.
-- Lua adapter uses explicit partial images, never a generated MapBlock.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Buffer=require('core.mapgen_voxelbuffer')
local Chunk=require('core.mapgen_chunk')
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
end
local function fs()
 local disk={files={}}
 function disk.read(path)
  return disk.files[path],disk.files[path] and nil or 'not found'
 end
 function disk.write_atomic(path,data) disk.files[path]=data;return true end
 return disk
end
local function runtime()
 local rt=Runtime.new({mapgen={seed=97,mg_name='v7',water_level=1},
  active_block_range=0,emerge_blocks_per_step=1})
 for _,name in ipairs({'test:stone','test:water','test:marker','test:gem'}) do
  rt.api.register_node(name,{})
 end
 return rt
end
local function constant(v)
 return {offset=v,scale=0,spread={x=16,y=16,z=16},
  seed=1,octaves=1,persist=.5,lacunarity=2}
end
local opts={stone='test:stone',water='test:water',
 spflags='nomountains,noridges,nocaverns',
 noise={terrain_base=constant(-25),terrain_alt=constant(-25),
  terrain_persist=constant(.5),height_select=constant(1)}}
local function emit(rt,p)
 local action
 rt.api.emerge_area(p,p,function(_,a) action=a end)
 rt:step(.1)
 return action
end
local d=fs()
local w=runtime()
local store=w:attachMapBlockStore(d,'partial97')
local k='-1,0,0'
local p={x=-16,y=0,z=0}
local air={x=-15,y=0,z=0}
local unknown={x=-14,y=0,z=0}
local mpos={x=-13,y=2,z=3}
assert(w.map:create_blank_block(k))
w.map:set_node(p,{name='test:marker',param1=7,param2=9})
w.map:set_node(air,{name='air',param1=0,param2=0})
w.api.get_meta(mpos):set_string('owner','player & builder')
local inv=w.api.get_meta(mpos):get_inventory()
inv:set_size('main',2)
assert(inv:set_stack('main',1,'test:gem 4'))
w.api.get_node_timer(mpos):set(15,2.25)
eq(w.map:get_node(unknown).name,'ignore')
local ok,count=store:flush()
assert(ok and count==0,'partial state is not a completed mapblock')
assert(d.files[store:partial_path(k)])
assert(d.files[store:path(k)]==nil)
local restart=runtime()
local loaded=restart:attachMapBlockStore(d,'partial97')
-- Ordinary load_area/emerge should not claim a completed MapBlock.
eq(restart.api.get_node(p).name,'ignore')
assert(loaded:emerge(k)==false)
local loadok,created=loaded:load_or_create_blank(k)
assert(loadok and not created,'existing partial must be restored, not replaced')
assert(restart.map.blank_blocks[k])
eq(restart.map:get_node(p).name,'test:marker')
eq(restart.map:get_node(p).param1,7)
eq(restart.map:get_node(p).param2,9)
eq(restart.map:get_node(air).name,'air','explicit AIR(0,0) preserved')
assert(restart.map.nodes['-15,0,0'],'known AIR not compressed to IGNORE')
eq(restart.map:get_node(unknown).name,'ignore')
eq(restart.api.get_meta(mpos):get_string('owner'),'player & builder')
local got=restart.api.get_meta(mpos):get_inventory():get_stack('main',1)
eq(got:get_name(),'test:gem')
eq(got:get_count(),4)
eq(restart.api.get_node_timer(mpos):get_timeout(),15)
eq(restart.api.get_node_timer(mpos):get_elapsed(),2.25)
-- An initialEmerge(true) snapshot sees the restored partial nodes.
local vm=Buffer.new(restart.map,Chunk.geometry({x=-1,y=0,z=0},1))
vm:initialEmerge(true)
eq(vm:get_node(p).name,'test:marker')
eq(vm:get_node(air).name,'air')
eq(vm:get_node(unknown).name,'ignore')
assert(vm:terrain_writable(unknown))
assert(not vm:terrain_writable(p))
-- Full disk images take priority over stale partial data on restart.
assert(restart.map:finish_blank_block(k))
restart.map.last_active[k]=restart.clock
assert(loaded:flush())
assert(d.files[loaded:path(k)] and d.files[loaded:partial_path(k)])
local complete=runtime()
local cstore=complete:attachMapBlockStore(d,'partial97')
local isok,isnew=cstore:load_or_create_blank(k)
assert(isok and not isnew)
assert(not complete.map.blank_blocks[k])
eq(complete.map:get_node(p).name,'test:marker')
eq(complete.api.get_meta(mpos):get_string('owner'),'player & builder')
eq(complete.api.get_node_timer(mpos):get_timeout(),15)
-- Corrupt/foreign partial images are rejected before live mutations.
local broken=fs()
broken.files['bad97/blocks/-1_0_0.map.partial']=
 'LUAENGINE 1\nN 0 0 0 test%3Amarker 0 0\nEND\n'
local bad=runtime()
local badstore=bad:attachMapBlockStore(broken,'bad97')
assert(not pcall(badstore.load_or_create_blank,badstore,k))
assert(not bad.map.blank_blocks[k] and not bad.map.revisions[k])
assert(next(bad.map.nodes)==nil and next(bad.map.metadata)==nil)
-- Invalid partial files cannot make a block appear fully generated.
broken.files[badstore:partial_path(k)]='CORRUPT'
assert(not pcall(badstore.load_or_create_blank,badstore,k))
assert(not bad.map.blank_blocks[k])
-- Failed writes must not discard resident metadata or timers.
local fault=fs()
local failed=runtime()
local fstore=failed:attachMapBlockStore(fault,'fault97')
assert(failed.map:create_blank_block(k))
failed.api.get_meta(mpos):set_string('keep','yes')
failed.api.get_node_timer(mpos):start(8)
local atomic=fault.write_atomic
fault.write_atomic=function(path,data)
 if path==fstore:partial_path(k) then return false,'disk full' end
 return atomic(path,data)
end
assert(not pcall(fstore.flush,fstore))
eq(failed.api.get_meta(mpos):get_string('keep'),'yes')
assert(failed.api.get_node_timer(mpos):is_started())
fault.write_atomic=atomic
assert(fstore:flush())
-- End-to-end V7: a saved blank core is restored before terrain generation.
local corefs=fs()
local core=runtime()
local corestore=core:attachMapBlockStore(corefs,'v7core97')
assert(core.map:create_blank_block(k))
core.map:set_node(p,{name='test:marker',param1=5,param2=13})
core.api.get_meta(mpos):set_string('core','persistent')
core.api.get_node_timer(mpos):set(12,1.5)
assert(corestore:flush())
local resumed=runtime()
resumed:enableMapgenV7Chunks(opts,1)
resumed:attachMapBlockStore(corefs,'v7core97')
eq(emit(resumed,p),resumed.api.EMERGE_GENERATED)
eq(resumed.api.get_node(p).name,'test:marker')
eq(resumed.api.get_node(p).param2,13)
eq(resumed.api.get_meta(mpos):get_string('core'),'persistent')
assert(math.abs(resumed.api.get_node_timer(mpos):get_elapsed()-1.6)<1e-6,
 'timer must retain elapsed state and advance by the emerge tick')
assert(not resumed.map.blank_blocks[k])
-- A neighboring saved partial halo is loaded before the real MMVManip
-- initialEmerge, retaining its timer and inventory when the core is built.
local halo_disk=fs()
local halo=runtime()
local hs=halo:attachMapBlockStore(halo_disk,'v7halo97')
local upper='0,1,0'
local up={x=0,y=17,z=0}
assert(halo.map:create_blank_block(upper))
halo.map:set_node(up,{name='test:marker',param1=4,param2=6})
halo.api.get_meta(up):set_string('owner','upper')
halo.api.get_node_timer(up):set(31,4)
assert(hs:flush())
local neighbor=runtime()
neighbor:enableMapgenV7Chunks(opts,1)
local ns=neighbor:attachMapBlockStore(halo_disk,'v7halo97')
eq(emit(neighbor,{x=0,y=0,z=0}),neighbor.api.EMERGE_GENERATED)
assert(neighbor.map.blank_blocks[upper])
eq(neighbor.map:get_node(up).name,'test:marker')
eq(neighbor.api.get_meta(up):get_string('owner'),'upper')
eq(neighbor.api.get_node_timer(up):get_timeout(),31)
assert(ns:flush())
local upper_restart=runtime()
upper_restart:enableMapgenV7Chunks(opts,1)
upper_restart:attachMapBlockStore(halo_disk,'v7halo97')
eq(emit(upper_restart,{x=0,y=16,z=0}),upper_restart.api.EMERGE_GENERATED)
eq(upper_restart.api.get_node(up).name,'test:marker')
eq(upper_restart.api.get_meta(up):get_string('owner'),'upper')
assert(math.abs(upper_restart.api.get_node_timer(up):get_elapsed()-4.2)<1e-6,
 'timer continues across two generation steps and a restart')
print('LUANTI MMVM PARTIAL MAPBLOCK META/TIMERS INVENTORY AND RESTART PASS')
