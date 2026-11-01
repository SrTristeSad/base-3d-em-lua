-- Verify original Luanti player physics entry points on host-owned players.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local function p(x,y,z)return {x=x,y=y,z=z} end
local rt=Runtime.new()
local api=rt.api
api.register_node('test:stone',{})
for x=-2,12 do api.set_node(p(x,0,0),{name='test:stone'}) end
local first={name='Alice',extra='host-owned'}
function first:get_player_name() return self.name end
local second={name='Bob'}
function second:get_player_name() return self.name end
local steps={}
local seen_on_join={}
api.register_on_joinplayer(function(player)
 steps[#steps+1]='join:'..player:get_player_name()
 assert(api.get_player_by_name(player:get_player_name())==player,
  'on_joinplayer must see the identical host-owned player')
 if player:get_player_name()=='Alice' then
  assert(type(player.set_physics_override)=='function')
  local overrides=player:get_physics_override()
  assert(overrides.speed==1 and overrides.jump==1)
  player:set_physics_override({speed=2,jump=1.5})
  seen_on_join[player]=true
 end
end)
api.register_on_leaveplayer(function(player)
 steps[#steps+1]='leave:'..player:get_player_name()
 if player==first then
  assert(player:get_physics_override().speed==2,
   'leave callback must retain the active physics binding')
 end
end)
local alice_controller=Physics.new(api,p(0,.5,0),{profile='luanti'})
local connected=rt:connectPlayer(first,alice_controller)
assert(connected==first and seen_on_join[first])
assert(api.get_player_by_name('Alice')==first)
assert(#api.get_connected_players()==1)
assert(first.extra=='host-owned')
local state=first:get_physics_override()
assert(state.speed==2 and state.jump==1.5)
assert(alice_controller:get_physics_override().speed==2)
state.speed=123
assert(first:get_physics_override().speed==2,
 'player physics getter must return an independent copy')
-- Changes made by a mod feed the same controller used by the host.
first:set_physics_override({gravity=.5})
assert(alice_controller:get_physics_override().gravity==.5)
alice_controller:update(.05,{x=1})
assert(alice_controller.velocity.x>0)
-- Failure is transactional and preserves previous live settings.
assert(not pcall(function()
 first:set_physics_override({speed=10,gravity=-2})
end))
assert(first:get_physics_override().speed==2)
-- A second binding to the same player must be rejected.
assert(not pcall(function()
 rt:bindPlayerPhysics('Alice',Physics.new(api,p(0,.5,0)))
end))
local bob_controller=Physics.new(api,p(1,.5,0))
assert(rt:connectPlayer(second,bob_controller)==second)
local players=api.get_connected_players()
assert(#players==2 and players[1]==first and players[2]==second)
assert(second:get_physics_override().speed==1)
assert(rt:disconnectPlayer('Alice'))
assert(api.get_player_by_name('Alice')==nil)
assert(first.set_physics_override==nil and first.get_physics_override==nil,
 'disconnect must restore host player table')
assert(alice_controller:get_physics_override().speed==2,
 'disconnect must not mutate an independently owned controller')
assert(not rt:disconnectPlayer('Alice'))
-- A disconnected host object can be reused with a NEW controller.
local reuse=Physics.new(api,p(0,.5,0))
rt:connectPlayer(first,reuse)
assert(first:get_physics_override().speed==2,
 'the on_joinplayer mod should still update reused player physics')
assert(rt:disconnectPlayer('Alice'))
assert(rt:disconnectPlayer('Bob'))
assert(#api.get_connected_players()==0)
assert(#steps==6,'two joins for Alice and one for Bob, with matching leaves')
-- Binding can be added later, after a player has connected.
local charlie={name='Charlie'}
function charlie:get_player_name()return self.name end
rt:connectPlayer(charlie)
assert(charlie.get_physics_override==nil)
local third=Physics.new(api,p(3,.5,0))
assert(rt:bindPlayerPhysics('Charlie',third)==charlie)
charlie:set_physics_override({speed=3})
assert(third:get_physics_override().speed==3)
assert(rt:disconnectPlayer('Charlie'))
assert(charlie.get_physics_override==nil)
-- Do not override a host's own C++/custom physics implementation.
local native={name='Native',own=0}
function native:get_player_name()return self.name end
function native:get_physics_override()return {speed=self.own} end
function native:set_physics_override(v)self.own=v.speed end
assert(not pcall(function()
 rt:connectPlayer(native,Physics.new(api,p(1,.5,0)))
end))
assert(api.get_player_by_name('Native')==nil)
assert(native.set_physics_override and native.get_physics_override)
native:set_physics_override({speed=9})
assert(native:get_physics_override().speed==9)
rt:connectPlayer(native)
assert(native:get_physics_override().speed==9)
rt:disconnectPlayer('Native')
assert(native:get_physics_override().speed==9)
-- Cross-runtime controller must not be accepted.
local other=Runtime.new()
local foreign=Physics.new(other.api,p(0,.5,0))
assert(not pcall(function()
 rt:connectPlayer({get_player_name=function()return 'Foreign' end},foreign)
end))
assert(api.get_player_by_name('Foreign')==nil)
-- Failure in a join callback releases the binding and disconnects player.
api.register_on_joinplayer(function(player)
 if player:get_player_name()=='Failing' then error('intentional join failure') end
end)
local failing={name='Failing'}
function failing:get_player_name()return self.name end
assert(not pcall(function()
 rt:connectPlayer(failing,Physics.new(api,p(0,.5,0)))
end))
assert(api.get_player_by_name('Failing')==nil)
assert(failing.set_physics_override==nil and failing.get_physics_override==nil)
print('LUA ENGINE HOST PLAYER PHYSICS BRIDGE PASS')
