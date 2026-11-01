-- Luanti 5.18.0 PlayerHPChangeReason and callback order regression.
-- Run on both Lua 5.4 and LuaJIT.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local function pos(x,y,z) return {x=x,y=y,z=z} end

local rt=Runtime.new()
local api=rt.api
local player={name='Alex'}
function player:get_player_name() return self.name end
local controller=Physics.new(api,pos(0,2,0),{profile='luanti'})
local deaths,observed={},{}
api.register_on_dieplayer(function(p,reason)
 assert(p==player and p:get_hp()==0,'death callback sees committed zero HP')
 deaths[#deaths+1]=reason
end)
api.register_on_player_hpchange(function(p,delta,reason)
 assert(p==player)
 observed[#observed+1]={delta=delta,type=reason.type,from=reason.from,
  extra=reason.extra}
end)
rt:connectPlayer(player,controller)
assert(player:get_hp()==20 and player:get_properties().hp_max==20)
assert(type(api.registered_on_player_hpchanges)=='table')
assert(type(api.registered_on_player_hpchange)=='function')

local reason={type='fall',extra='origin'}
player:set_hp(-3,reason)
assert(player:get_hp()==0 and #deaths==1)
assert(observed[1].delta==-23,'unclamped delta must reach HP callbacks')
assert(observed[1].type=='fall' and observed[1].from=='mod' and
 observed[1].extra=='origin')
assert(deaths[1].type=='fall' and deaths[1].extra=='origin')
assert(reason.from==nil,'callback reason normalization must not mutate caller')
player:set_hp(-11)
assert(player:get_hp()==0 and #observed==1 and #deaths==1,
 'damage to already-dead player must be ignored')
player:set_hp(22)
assert(player:get_hp()==20 and observed[2].delta==22)
player:set_hp(80000)
assert(player:get_hp()==20 and observed[3].delta==79980,
 'healing at maximum must still notify listeners')
assert(#deaths==1)
assert(not pcall(player.set_hp,player,0/0))
assert(not pcall(player.set_hp,player,3.5))
assert(not pcall(player.set_hp,player,10,'bad reason'))
assert(player:get_hp()==20)

-- Luanti uses hp_max from player properties, not a hard-coded 20 HP limit.
player:set_properties({hp_max=30})
assert(player:get_properties().hp_max==30)
player:set_hp(25)
assert(player:get_hp()==25 and observed[4].delta==5)
assert(not pcall(player.set_properties,player,{hp_max=65536,stepheight=.3}))
assert(player:get_properties().hp_max==30,
 'invalid property update must remain atomic')
player:set_properties({hp_max=22})
assert(player:get_hp()==22)
assert(not pcall(player.set_properties,player,{hp_max=0}))
assert(player:get_hp()==22)

-- Modifiers execute newest-first and loggers see final delta.
local ordered=Runtime.new()
local log={}
ordered.api.register_on_player_hpchange(function(_,d)
 log[#log+1]='older'
 return d-1
end,true)
ordered.api.register_on_player_hpchange(function(_,d)
 log[#log+1]='newer'
 return d*2
end,true)
ordered.api.register_on_player_hpchange(function(_,d)
 log[#log+1]='logger'
 assert(d==-11)
end)
local delta=ordered.api.registered_on_player_hpchange({},-5,
 {type='set_hp',from='mod'})
assert(delta==-11 and table.concat(log,',')=='newer,older,logger')
local stopped=Runtime.new()
local count=0
stopped.api.register_on_player_hpchange(function()
 count=count+1
 return 999
end,true)
stopped.api.register_on_player_hpchange(function(_,d)
 count=count+1
 return d-2,true
end,true)
stopped.api.register_on_player_hpchange(function(_,d)
 count=count+1
 assert(d==-5)
end)
assert(stopped.api.registered_on_player_hpchange({},-3,{})==-5)
assert(count==2,'modifier stop skips older modifiers but not loggers')
assert(not pcall(ordered.api.registered_on_player_hpchange,{},0/0,{}))
ordered.api.register_on_player_hpchange(function()return nil end,true)
assert(not pcall(ordered.api.registered_on_player_hpchange,{},1,{}),
 'a missing numeric modifier result must fail')

-- Native hosts retain their own HP transport; this bridge may not override it.
local native={name='Native',own_hp=12}
function native:get_player_name() return self.name end
function native:get_hp() return self.own_hp end
function native:set_hp(n) self.own_hp=n end
rt:connectPlayer(native,Physics.new(api,pos(2,2,0)))
native:set_hp(9)
assert(native:get_hp()==9)
assert(rt:disconnectPlayer('Native'))
assert(native:get_hp()==9 and type(native.set_hp)=='function')

assert(rt:disconnectPlayer('Alex'))
assert(player.get_hp==nil and player.set_hp==nil and
 player.get_properties==nil,'Lua health APIs must detach from host player')
assert(not pcall(function() player:set_hp(10) end))
print('LUA ENGINE PLAYER HP AND LUANTI CALLBACKS PASS')
