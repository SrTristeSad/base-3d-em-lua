-- Phase 24: host players expose a safe, documented subset of ObjectRef.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local function vec(x,y,z)return {x=x,y=y,z=z} end
local rt=Runtime.new()
local api=rt.api
api.register_node('probe:stone',{})
local controller=Physics.new(api,vec(0,2,0),{profile='luanti'})
local player={name='Alice',host_tag='preserved'}
function player:get_player_name()return self.name end
local joined=false
api.register_on_joinplayer(function(p)
 if p~=player then return end
 assert(p:get_pos().y==2)
 assert(p:get_velocity().x==0)
 assert(p:get_properties().physical)
 assert(not p:get_player_control().jump)
 joined=true
end)
assert(rt:connectPlayer(player,controller)==player)
assert(joined and player.host_tag=='preserved')
assert(api.get_connected_players()[1]==player)
assert(api.get_player_by_name('Alice')==player)
-- Position is copied in both directions and updates the actual controller.
local newpos=vec(5,8,-3)
assert(player:set_pos(newpos))
newpos.x=200
assert(controller.pos.x==5 and controller.pos.y==8)
local result=player:get_pos()
result.z=200
assert(player:get_pos().z==-3)
assert(not controller.grounded)
assert(not pcall(player.set_pos,player,{x=0,y=0,z=0/0}))
assert(controller.pos.x==5)
-- Velocity setters and impulses are applied to the simulated controller.
local speed=vec(1,2,-1)
player:set_velocity(speed)
speed.x=999
assert(controller.velocity.x==1 and controller.velocity.y==2)
local v=player:get_velocity()
v.y=888
assert(player:get_velocity().y==2)
player:add_velocity(vec(2,-1,3))
local v2=player:get_velocity()
assert(v2.x==3 and v2.y==1 and v2.z==2)
assert(not pcall(player.add_velocity,player,{x=math.huge,y=0,z=0}))
assert(player:get_velocity().x==3)
-- Controls are supplied by the session host, not inferred from world-space dx/dz.
local controls={up=true,jump=true,sneak=false,aux1=true}
rt:updatePlayerControls('Alice',controls)
controls.jump=false
local read=player:get_player_control()
assert(read.up and read.jump and read.aux1)
assert(read.left==false and read.down==false and read.place==false)
read.up=false
assert(player:get_player_control().up)
assert(not pcall(rt.updatePlayerControls,rt,'Alice',{jump=1}))
assert(not pcall(rt.updatePlayerControls,rt,'Alice',{nonexistent=true}))
assert(player:get_player_control().jump)
rt:updatePlayerControls('Alice',{left=true})
assert(player:get_player_control().left)
assert(not player:get_player_control().jump)
-- Property queries use copies and a deliberately restricted subset.
local props=player:get_properties()
assert(props.physical and props.eye_height==1.62)
assert(props.collisionbox[1]==-.3 and props.collisionbox[5]==1.8)
props.collisionbox[4]=99
assert(player:get_properties().collisionbox[4]==.3)
player:set_properties({
 collisionbox={-.25,0,-.25,.25,1.6,.25},
 eye_height=1.5,stepheight=.45,
})
local changed=player:get_properties()
assert(changed.collisionbox[4]==.25 and changed.collisionbox[5]==1.6)
assert(changed.eye_height==1.5 and changed.stepheight==.45)
assert(controller.radius==.25 and controller.height==1.6)
-- Invalid mixed updates are atomic.
assert(not pcall(player.set_properties,player,
 {stepheight=.7,eye_height=4}))
assert(player:get_properties().stepheight==.45)
assert(not pcall(player.set_properties,player,{physical=false}))
assert(not pcall(player.set_properties,player,{visual_size={x=2,y=2}}))
assert(not pcall(player.set_properties,player,
 {collisionbox={-.5,0,-.3,.5,1.7,.3}}))
assert(player:get_properties().collisionbox[4]==.25)
-- Host-native methods retain priority; they are not silently replaced.
local custom={name='Native',x=10}
function custom:get_player_name() return self.name end
function custom:get_pos() return vec(self.x,42,0) end
function custom:set_pos(p)self.x=p.x end
local nativephysics=Physics.new(api,vec(0,0,0))
rt:connectPlayer(custom,nativephysics)
assert(custom:get_pos().x==10 and custom:get_pos().y==42)
custom:set_pos(vec(9,0,0))
assert(custom.x==9 and nativephysics.pos.x==0)
assert(type(custom.get_player_control)=='function')
assert(rt:disconnectPlayer('Native'))
assert(custom.get_pos and custom.set_pos)
assert(custom.get_velocity==nil and custom.get_player_control==nil)
-- Disconnect removes installed APIs and clears host controls controller.
assert(rt:disconnectPlayer('Alice'))
assert(api.get_player_by_name('Alice')==nil)
for _,method in ipairs({
 'get_pos','set_pos','get_velocity','set_velocity','add_velocity',
 'get_player_control','get_properties','set_properties',
 'get_physics_override','set_physics_override'
}) do
 assert(player[method]==nil,'leaked injected ObjectRef method '..method)
end
assert(rt.playerPhysicsControllers.Alice==nil)
assert(not pcall(rt.updatePlayerControls,rt,'Alice',{up=true}))
assert(controller:get_pos().x==5,'host controller must not be destroyed')
-- Explicitly reject control queries made with incorrect self.
local again=Physics.new(api,vec(0,1,0))
rt:connectPlayer(player,again)
assert(not pcall(player.get_pos,custom))
assert(rt:disconnectPlayer('Alice'))
-- Transactional rollback if join callback fails after methods exist.
api.register_on_joinplayer(function(p)
 if p:get_player_name()=='Fail' then
  assert(p.get_pos and p.get_player_control and p.get_properties)
  error('intentional player join failure')
 end
end)
local fail={name='Fail'}
function fail:get_player_name()return self.name end
assert(not pcall(rt.connectPlayer,rt,fail,Physics.new(api,vec(0,0,0))))
assert(not api.get_player_by_name('Fail'))
assert(fail.get_pos==nil and fail.get_player_control==nil)
assert(rt.playerPhysicsControllers.Fail==nil)
print('LUA ENGINE PLAYER OBJECTREF STATE PASS')
