-- Headless character physics using actual Lua node collision definitions.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local function near(actual,expected,epsilon,label)
 assert(math.abs(actual-expected)<(epsilon or 1e-5),
  (label or 'coordinate')..': expected '..expected..', got '..actual)
end
local function xyz(x,y,z)return {x=x,y=y,z=z} end
local rt=Runtime.new()
local api=rt.api
api.register_node('test:stone',{tiles={'default_stone.png'},groups={cracky=1}})
api.register_node('test:water',{drawtype='liquid',walkable=false})
api.register_node('test:flower',{drawtype='plantlike',walkable=false})
api.register_node('test:slab',{drawtype='nodebox',
 node_box={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}},
 collision_box={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}}})
api.register_node('test:tall',{drawtype='nodebox',
 node_box={type='fixed',fixed={-.5,-.5,-.5,.5,.35,.5}},
 collision_box={type='fixed',fixed={-.5,-.5,-.5,.5,.35,.5}}})
api.register_node('test:fence',{drawtype='nodebox',
 node_box={type='fixed',fixed={-.15,-.5,-.15,.15,.5,.15}},
 collision_box={type='fixed',fixed={-.15,-.5,-.15,.15,1.01,.15}}})
local function ground(z)
 for x=-6,25 do api.set_node(xyz(x,0,z),{name='test:stone'}) end
end
for z=-6,10 do ground(z) end
local function character(x,y,z,opts)
 -- Earlier Fase 19 collision assertions intentionally test constant-speed
 -- sweeps. Keep that configuration explicit; later tests cover inertia.
 opts=opts or {}
 opts.acceleration=opts.acceleration==nil and 0 or opts.acceleration
 opts.braking=opts.braking==nil and 0 or opts.braking
 opts.air_acceleration=opts.air_acceleration==nil and 0 or opts.air_acceleration
 opts.fluid_physics=false
 return Physics.new(api,xyz(x,y,z),opts)
end
local function advance(p,count,dt,input)
 for _=1,count do p:update(dt or .05,input or {}) end
 return p.pos
end
-- A character dropped onto normal blocks must settle exactly on top.
local falling=character(0,5,0)
advance(falling,60,.05)
near(falling.pos.y,.5,1e-5,'gravity landing')
assert(falling.grounded and falling.velocity.y==0)
near(falling:eye().y,falling.pos.y+falling.eyeheight)
advance(falling,20,.05)
near(falling.pos.y,.5,1e-5,'stationary ground contact')
-- Jump can only start while on ground; gravity returns us to that ground.
falling:update(.05,{jump=true})
assert(falling.pos.y>.5 and not falling.grounded)
local rising=falling.pos.y
falling:update(.05,{jump=true})
assert(falling.pos.y>rising,'holding jump must not cancel ascent')
advance(falling,80,.05)
near(falling.pos.y,.5,1e-5,'jump landing')
assert(falling.grounded)
-- Solids block horizontal sweeps even with large frame deltas / sprint.
for y=1,3 do api.set_node(xyz(2,y,0),{name='test:stone'}) end
local wall=character(0,.5,0)
advance(wall,20,.05,{x=1})
near(wall.pos.x,1.2,1e-5,'wall horizontal collision')
wall:update(.5,{x=1,sprint=true})
near(wall.pos.x,1.2,1e-5,'high-speed solid collision')
local no_tunnel=character(0,.5,0,{speed=60})
no_tunnel:update(.2,{x=1})
assert(no_tunnel.pos.x<=1.2+1e-5,'sweep cannot tunnel through wall')
-- Water and plants are visually present but NOT physical obstacles.
api.set_node(xyz(1,1,2),{name='test:water'})
api.set_node(xyz(2,1,2),{name='test:flower'})
local passthrough=character(0,.5,2)
advance(passthrough,14,.05,{x=1})
assert(passthrough.pos.x>2,'nonwalkable nodes must be traversable')
near(passthrough.pos.y,.5,1e-5)
-- Slabs at node y=1 are .5 above the top of normal ground (y=.5).
api.set_node(xyz(1,1,4),{name='test:slab'})
local steps=character(0,.5,4)
advance(steps,5,.05,{x=1})
assert(steps.pos.x>.7,'half-block step should be climbable')
near(steps.pos.y,1,1e-5,'climbed slab top')
advance(steps,15,.05,{x=1})
near(steps.pos.y,.5,1e-5,'step-down to floor')
-- An obstacle higher than max stepheight must not be climbed.
api.set_node(xyz(1,1,6),{name='test:tall'})
local tall=character(0,.5,6)
advance(tall,10,.05,{x=1})
assert(tall.pos.x<=.2+1e-5,'high steps must block movement')
near(tall.pos.y,.5,1e-5)
-- A low ceiling prevents raising the body to pass over a half slab.
api.set_node(xyz(1,1,8),{name='test:slab'})
api.set_node(xyz(0,3,8),{name='test:stone'})
local blocked_step=character(0,.5,8)
advance(blocked_step,10,.05,{x=1})
assert(blocked_step.pos.x<=.2+1e-5,'cannot step through a low ceiling')
-- Dedicated collision boxes differ from the decorative node mesh.
api.set_node(xyz(1,1,-2),{name='test:fence'})
local fence=character(0,.5,-2)
advance(fence,14,.05,{x=1})
assert(fence.pos.x<=.55+1e-5,'tall fence collision prevents stepping over')
-- A rotating node changes the queried collision shape.
api.register_node('test:rotated',{drawtype='nodebox',paramtype2='4dir',
 node_box={type='fixed',fixed={-.5,-.5,-.125,.5,.5,.125}},
 collision_box={type='fixed',fixed={-.5,-.5,-.125,.5,.5,.125}}})
api.set_node(xyz(8,1,0),{name='test:rotated',param2=0})
local horizontal=character(6,.5,0)
advance(horizontal,10,.05,{x=1})
assert(horizontal.pos.x<=7.2+1e-5)
-- The same shape rotated must have a narrower X footprint.
api.set_node(xyz(8,1,0),{name='test:rotated',param2=1})
local rotated=character(6,.5,0)
advance(rotated,10,.05,{x=1})
assert(rotated.pos.x>horizontal.pos.x+.2)
-- Character refuses invalid positions / time parameters.
assert(not pcall(Physics.new,api,{x=0,y=0,z=0},{radius=-1}))
assert(not pcall(falling.update,falling,-.2,{}))
print('LUA ENGINE CHARACTER PHYSICS PASS')
