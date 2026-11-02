-- Durable segmented mapblock stream: Lua 5.4 / LuaJIT.
-- Exercises actual departure and arrival through Runtime:step.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Storage=require('core.storage')
local Map=require('core.map')
local fs={files={},fail_path=nil}
function fs.read(path)
 if fs.files[path]==nil then return nil,'not found' end
 return fs.files[path]
end
function fs.write_atomic(path,data)
 if path==fs.fail_path then return nil,'simulated disk failure' end
 fs.files[path]=data
 return true
end
local pos={x=0,y=0,z=0}
local center={x=0,y=0,z=0}
local neighbor={x=16,y=0,z=0}
local rt=Runtime.new({active_block_range=0})
rt.api.register_node('audit:old',{groups={legacy=1}})
rt.api.register_node('audit:updated',{})
rt.api.register_node('audit:timer',{on_timer=function(p,elapsed)
 rt.timer_calls[#rt.timer_calls+1]={x=p.x,elapsed=elapsed}
 return false
end})
rt.api.register_craftitem('audit:gem',{})
rt.timer_calls={}
local once,repeated={},{}
rt.api.register_lbm({name='audit:upgrade',nodenames={'audit:old'},
 action=function(p)
  once[#once+1]=p.x
  rt.api.swap_node(p,{name='audit:updated'})
 end})
rt.api.register_lbm({name='audit:visit',nodenames={'audit:updated'},
 run_at_every_load=true,action=function(p,node,elapsed)
  repeated[#repeated+1]={x=p.x,elapsed=elapsed}
 end})
rt.api.set_node(center,{name='audit:old'})
rt.api.set_node(neighbor,{name='audit:old'})
rt.api.set_node({x=1,y=0,z=0},{name='audit:timer'})
rt.api.get_node_timer({x=1,y=0,z=0}):set(2,.25)
local meta=rt.api.get_meta(center)
meta:set_string('owner','Alice & Bob')
local inv=meta:get_inventory()
inv:set_size('main',2)
assert(inv:set_stack('main',1,'audit:gem 2'))
rt.map.generatedChunks['0,0']=42
local store=rt:attachMapBlockStore(fs,'worldA')
local player={get_player_name=function() return 'Alice' end,
 get_pos=function() return pos end}
rt:connectPlayer(player)
rt:step(1)
assert(#once==1 and once[1]==0)
assert(#repeated==1 and repeated[1].x==0)
assert(rt.map.count==3)
pos={x=16,y=0,z=0}
rt:step(1)
assert(#once==2 and once[2]==16)
assert(rt.map.count==1,'inactive mapblock node data must leave RAM')
assert(not rt.map.nodes['0,0,0'])
assert(not rt.map.metadata['0,0,0'] and not rt.map.timers['1,0,0'])
assert(store.unloads==1 and store.loads==0)
assert(fs.files['worldA/world.map'])
local blockpath=store:path('0,0,0')
assert(fs.files[blockpath] and fs.files[blockpath]:find('audit%3Aold',1,true)==nil)
assert(fs.files[blockpath]:find('Alice%20%26%20Bob',1,true))
assert(fs.files[blockpath]:find('I 0 0 0 main 1 audit%3Agem 2 0',1,true))
-- Independent world metadata survives segmented node eviction.
local world=Storage.decode(fs.files['worldA/world.map'])
assert(world.game_time==1 and world.generatedChunks['0,0']==42)
assert(next(world.nodes)==nil)
pos={x=160,y=0,z=0}
rt:step(4)
assert(rt.map.count==0 and store.unloads==2)
assert(store:resident('0,0,0')==false)
-- No active data is in RAM, but disk contains both mapblocks.
assert(not pcall(Storage.encode,rt.map),
 'full-map persistence must reject a partially loaded streaming world')
pos={x=0,y=0,z=0}
rt:step(.5)
assert(store.loads==1 and rt.api.get_node(center).name=='audit:updated')
assert(rt.api.get_meta(center):get_string('owner')=='Alice & Bob')
local loadedinv=rt.api.get_meta(center):get_inventory()
assert(loadedinv:get_stack('main',1):get_name()=='audit:gem')
assert(loadedinv:get_stack('main',1):get_count()==2)
assert(rt.map.count==2)
assert(#once==2,'one-shot LBM must not re-run after disk roundtrip')
assert(#repeated==3 and repeated[3].elapsed==5)
assert(#rt.timer_calls==1 and rt.timer_calls[1].elapsed==6.25)
assert(rt.map.game_time==6.5)
assert(store:flush())
assert(fs.files[blockpath] and Storage.decode(fs.files[blockpath]).last_active['0,0,0']==6.5)
-- A new process reads the persistent world clock + generated chunk flags.
local rt2=Runtime.new({active_block_range=0})
rt2.api.register_node('audit:old',{})
rt2.api.register_node('audit:updated',{})
rt2.api.register_node('audit:timer',{})
rt2.api.register_craftitem('audit:gem',{})
local store2=rt2:attachMapBlockStore(fs,'worldA')
assert(rt2.clock==6.5)
assert(rt2.map.generatedChunks['0,0']==42)
local p2={x=16,y=0,z=0}
rt2:connectPlayer({get_player_name=function() return 'Bob' end,
 get_pos=function() return p2 end})
rt2:step(.25)
assert(rt2.api.get_node(neighbor).name=='audit:updated')
assert(store2.loads==1)
assert(rt2.map.last_active['1,0,0']==6.75)
-- Host can move negative into distinct signed-key mapblock.
assert(store2:path('-1,-1,0')=='worldA/blocks/-1_-1_0.map')
-- Atomic failure cannot evict live RAM state.
local rf=Runtime.new({active_block_range=0})
rf.api.register_node('audit:old',{})
rf.api.set_node({x=-1,y=0,z=0},{name='audit:old'})
local sf=rf:attachMapBlockStore(fs,'worldFail')
fs.fail_path=sf:path('-1,0,0')
assert(not pcall(sf.unload,sf,'-1,0,0'))
assert(rf.api.get_node({x=-1,y=0,z=0}).name=='audit:old')
assert(sf:resident('-1,0,0') and rf.map.count==1)
fs.fail_path=nil
assert(sf:unload('-1,0,0') and rf.map.count==0)
-- Read corruption and cross-mapblock records are rejected before mutation.
local foreign=Map.new()
foreign:set_node({x=0,y=0,z=0},{name='audit:old'})
foreign.last_active['2,0,0']=0
fs.files[sf:path('2,0,0')]=Storage.encode(foreign)
assert(not pcall(sf.emerge,sf,'2,0,0'))
assert(rf.map.count==0)
-- The exposed block path must not accept directory traversal.
assert(not pcall(sf.path,sf,'../../tmp'))
assert(not pcall(rf.attachMapBlockStore,rf,fs,'../unsafe'))
print('LUA ENGINE PERSISTENT MAPBLOCK STREAMING PASS')
