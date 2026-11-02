-- Tests the actual lifecycle around connected player positions, not
-- isolated calls to Runtime:activateMapBlock. Lua 5.4 and LuaJIT.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Storage=require('core.storage')
local rt=Runtime.new({active_block_range=0})
local api=rt.api
local fixed,loaded,timer_events,abms={},{},{},{}
api.register_node('audit:legacy',{groups={old=1}})
api.register_node('audit:fixed',{groups={active=1}})
api.register_node('audit:clock',{on_timer=function(pos,elapsed)
 timer_events[#timer_events+1]={x=pos.x,elapsed=elapsed}
 return true
end})
api.register_lbm({name='audit:upgrade',nodenames='group:old',
 action=function(pos,node,dtime)
  assert(node.name=='audit:legacy')
  fixed[#fixed+1]={x=pos.x,dtime=dtime}
  api.swap_node(pos,{name='audit:fixed'})
 end})
api.register_lbm({name='audit:notify',nodenames='audit:fixed',
 run_at_every_load=true,action=function(pos,node,dtime)
  loaded[#loaded+1]={x=pos.x,dtime=dtime}
 end})
api.register_abm({nodenames={'audit:fixed'},interval=1,chance=1,
 action=function(pos) abms[#abms+1]=pos.x end})
local zero={x=0,y=0,z=0}
local far={x=16,y=0,z=0}
api.set_node(zero,{name='audit:legacy'})
api.set_node(far,{name='audit:legacy'})
api.set_node({x=1,y=0,z=0},{name='audit:clock'})
api.set_node({x=17,y=0,z=0},{name='audit:clock'})
api.get_node_timer({x=1,y=0,z=0}):start(2)
api.get_node_timer({x=17,y=0,z=0}):start(2)
local playerpos={x=0,y=0,z=0}
local player={get_player_name=function() return 'Alice' end,
 get_pos=function() return playerpos end}
rt:connectPlayer(player)
assert(not rt:isMapBlockActive(zero))
rt:step(1)
assert(rt:isMapBlockActive(zero) and not rt:isMapBlockActive(far))
assert(#fixed==1 and fixed[1].x==0 and fixed[1].dtime==0)
assert(#loaded==1 and loaded[1].x==0 and loaded[1].dtime==0)
assert(#abms==1 and abms[1]==0)
assert(api.get_node_timer({x=1,y=0,z=0}):get_elapsed()==1)
assert(api.get_node_timer({x=17,y=0,z=0}):get_elapsed()==0)
playerpos={x=16,y=0,z=0}
rt:step(1)
assert(not rt:isMapBlockActive(zero) and rt:isMapBlockActive(far))
assert(#fixed==2 and fixed[2].x==16 and fixed[2].dtime==0)
assert(#loaded==2 and loaded[2].x==16)
assert(#abms==2 and abms[2]==16)
assert(api.get_node_timer({x=17,y=0,z=0}):get_elapsed()==1)
-- Leaving resident blocks must make timer/ABM execution stop.
playerpos={x=160,y=0,z=0}
rt:step(4)
assert(not rt:isMapBlockActive(far))
assert(#timer_events==0 and #abms==2)
assert(rt.map.last_active['1,0,0']==2)
playerpos={x=16,y=0,z=0}
rt:step(.5)
-- Four seconds since last activity: once, before regular frame advance.
assert(#timer_events==1 and timer_events[1].x==17)
assert(timer_events[1].elapsed==5)
assert(#fixed==2 and #loaded==3 and loaded[3].dtime==4)
assert(api.get_node_timer({x=17,y=0,z=0}):get_elapsed()==.5)
assert(rt.map.last_active['1,0,0']==6.5)
assert(rt.map.game_time==6.5)
-- Persist timestamps and clock, then resume a different runtime.
local encoded=Storage.encode(rt.map)
assert(encoded:find('C 6.5',1,true))
assert(encoded:find('B 1 0 0 6.5',1,true))
local restored=Storage.decode(encoded)
assert(restored.game_time==6.5 and restored.last_active['1,0,0']==6.5)
local rt2=Runtime.new({active_block_range=0})
rt2.api.register_node('audit:legacy',{groups={old=1}})
rt2.api.register_node('audit:fixed',{groups={active=1}})
rt2.api.register_node('audit:clock',{on_timer=function() return true end})
local migrated,reactivated=0,{}
rt2.api.register_lbm({name='audit:upgrade',nodenames='group:old',
 action=function() migrated=migrated+1 end})
rt2.api.register_lbm({name='audit:notify',nodenames='audit:fixed',
 run_at_every_load=true,action=function(_,_,dt)
  reactivated[#reactivated+1]=dt
 end})
rt2:replaceMap(restored)
assert(rt2.clock==6.5)
local pos2={x=0,y=0,z=0}
local player2={get_player_name=function() return 'Bob' end,
 get_pos=function() return pos2 end}
rt2:connectPlayer(player2)
rt2:step(.5)
assert(#reactivated==1 and reactivated[1]==5.5,
 'offline elapsed time must use persisted mapblock timestamp')
assert(migrated==0,'one-shot LBM must remain consumed after reload')
-- A second positioned player holds the old mapblock active.
pos2={x=16,y=0,z=0}
local second={get_player_name=function() return 'Carol' end,
 get_pos=function() return {x=0,y=0,z=0} end}
rt2:connectPlayer(second)
rt2:step(1)
assert(rt2:isMapBlockActive(zero) and rt2:isMapBlockActive(far))
assert(rt2:disconnectPlayer('Carol'))
assert(not rt2:isMapBlockActive(zero) and rt2:isMapBlockActive(far))
assert(rt2:disconnectPlayer('Bob'))
assert(not rt2:isMapBlockActive(far))
local old=Storage.decode('LUAENGINE 1\nN 0 0 0 audit%3Alegacy 0 0\nEND\n')
assert(old.game_time==0 and next(old.last_active)==nil)
assert(not pcall(Storage.decode,'LUAENGINE 1\nC 1\nC 2\nEND\n'))
assert(not pcall(Storage.decode,'LUAENGINE 1\nC 1\nB 0 0 0 2\nEND\n'))
assert(not pcall(Storage.decode,'LUAENGINE 1\nB 0 0 0 -1\nEND\n'))
print('LUA ENGINE RESIDENT ACTIVE MAPBLOCKS PASS')
