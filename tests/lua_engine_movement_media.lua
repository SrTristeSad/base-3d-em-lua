-- Character movement extension: inertia, ground grip, water and ladders.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local runtime=Runtime.new()
local api=runtime.api
local function pos(x,y,z) return {x=x,y=y,z=z} end
api.register_node('test:ground',{groups={}})
api.register_node('test:ice',{groups={slippery=3}})
api.register_node('test:water',{drawtype='liquid',liquidtype='source',
 walkable=false,groups={water=1,liquid=1}})
api.register_node('test:ladder',{drawtype='plantlike',walkable=false,
 climbable=true})
for x=-12,12 do for z=-12,12 do
 api.set_node(pos(x,0,z),{name='test:ground'})
end end
local function new(x,y,z,opts)
 return Physics.new(api,pos(x,y,z),opts)
end
local function step(character,n,input)
 for _=1,n do character:update(.05,input or {}) end
end
local function near(a,b,eps)
 assert(math.abs(a-b)<(eps or 1e-5),
  'expected '..tostring(b)..', got '..tostring(a))
end
-- Acceleration must take more than one physics tick to reach cruise speed.
local runner=new(0,.5,0)
runner:update(.05,{x=1})
assert(runner.velocity.x>0 and runner.velocity.x<runner.speed)
local x0=runner.pos.x
step(runner,6,{x=1})
assert(runner.velocity.x==runner.speed and runner.pos.x>x0+.6,
 'continuous input must accelerate towards target speed')
local x1=runner.pos.x
runner:update(.05,{})
assert(runner.pos.x>x1 and runner.velocity.x>0,
 'releasing movement must decelerate rather than stop instantly')
step(runner,12,{})
near(runner.velocity.x,0)
local stopped=runner.pos.x
step(runner,10,{})
near(runner.pos.x,stopped)
-- Slippery nodes alter acceleration and braking on ground.
for x=-1,5 do api.set_node(pos(x,0,3),{name='test:ice'}) end
local ice=new(0,.5,3)
local stone=new(0,.5,2)
ice:update(.05,{x=1})
stone:update(.05,{x=1})
assert(ice.velocity.x<stone.velocity.x/2,
 'slippery terrain must reduce initial acceleration')
step(ice,12,{x=1})
local before_ice=ice.pos.x
ice:update(.05,{})
local inertial_distance=ice.pos.x-before_ice
local before_stone=stone.pos.x
stone:update(.05,{})
assert(inertial_distance>stone.pos.x-before_stone,
 'slippery surface should preserve momentum')
-- Air acceleration is weaker than ground acceleration.
local aerial=new(0,3,-3)
local grounded=new(0,.5,-3)
aerial:update(.05,{x=1})
grounded:update(.05,{x=1})
assert(aerial.velocity.x<grounded.velocity.x,
 'airborne acceleration must be configurable and lower')
-- Water is physically passable, but slows horizontal movement and falling.
for y=1,4 do api.set_node(pos(-3,y,6),{name='test:water'}) end
local wet=new(-3,.5,6)
wet:update(.05,{x=1,jump=true})
assert(wet.in_liquid and not wet.on_ladder)
assert(wet.velocity.x>0 and wet.velocity.x<runner.speed)
assert(wet.pos.y>.5,'swim key should raise player in water')
step(wet,4,{jump=true})
assert(wet.pos.y>.65,'water should permit sustained upward swimming')
local raised=wet.pos.y
step(wet,15,{})
assert(wet.pos.y<raised+2,'fluid drag and buoyancy must limit vertical velocity')
assert(wet.velocity.y>=-wet.swim_speed-1e-6,
 'swimmer must obey liquid sinking speed')
-- Ladders allow controllable ascent/descent and hanging without gravity.
for y=1,5 do api.set_node(pos(3,y,6),{name='test:ladder'}) end
local climber=new(3,.5,6)
step(climber,5,{jump=true})
assert(climber.on_ladder and climber.pos.y>1,
 'climbable=true must allow upward ladder movement')
local climbed=climber.pos.y
step(climber,3,{})
near(climber.pos.y,climbed)
step(climber,3,{sneak=true})
assert(climber.pos.y<climbed-.2,'sneak must allow ladder descent')
-- Ladder must remain walkable=false and not block normal horizontal movement.
local crossing=new(1,.5,6)
step(crossing,16,{x=1})
assert(crossing.pos.x>3,'climbable ladder must not become a solid wall')
-- Physics of liquids can be opted out for regression/creative game modes.
local old=new(-3,.5,6,{fluid_physics=false,acceleration=0,braking=0})
old:update(.05,{jump=true})
assert(not old.in_liquid,'opt-out should preserve legacy dry physics behavior')
-- Reject invalid tuning instead of producing NaNs or negative accelerations.
assert(not pcall(new,0,.5,0,{acceleration=-1}))
assert(not pcall(new,0,.5,0,{water_drag=0/0}))
print('LUA ENGINE MOVEMENT MEDIA PASS')
