-- Physics overrides and actual nodebox support material, pure Lua.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local rt=Runtime.new()
local api=rt.api
local function p(x,y,z) return {x=x,y=y,z=z} end
local function near(a,b,tolerance)
 assert(math.abs(a-b)<(tolerance or 1e-6),
  tostring(a)..' differs from '..tostring(b))
end
api.register_node('test:stone',{groups={}})
api.register_node('test:slippery_slab',{drawtype='nodebox',
 groups={slippery=3},
 node_box={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}},
 collision_box={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}}})
api.register_node('test:flat_slab',{drawtype='nodebox',groups={},
 node_box={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}},
 collision_box={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}}})
api.register_node('test:thin_ice',{drawtype='nodebox',
 groups={slippery=5},
 node_box={type='fixed',fixed={-.5,-.5,-.5,-.2,0,.5}},
 collision_box={type='fixed',fixed={-.5,-.5,-.5,-.2,0,.5}}})
for x=-3,20 do
 api.set_node(p(x,-1,0),{name='test:stone'})
end
api.set_node(p(1,0,0),{name='test:slippery_slab'})
api.set_node(p(4,0,0),{name='test:flat_slab'})
api.set_node(p(9,0,0),{name='test:thin_ice'})
-- Luanti movement defaults are opt-in; do not silently change old game tests.
local spec=Physics.new(api,p(0,-.5,0),{profile='luanti'})
near(spec.speed,4)
near(spec.sprint_speed,20)
near(spec.sneak_speed,1.35)
near(spec.acceleration,3)
near(spec.air_acceleration,2)
near(spec.jump_speed,6.5)
near(spec.gravity,9.81)
near(spec.climb_speed,3)
assert(not pcall(Physics.new,api,p(0,0,0),{profile='other'}))
-- Returned state must be a COPY, and overrides must be partial updates.
local overrides=spec:get_physics_override()
assert(overrides.speed==1 and overrides.speed_walk==1 and
 overrides.sneak and overrides.jump==1 and overrides.new_move)
overrides.speed=99
assert(spec:get_physics_override().speed==1)
spec:set_physics_override({speed=2,speed_walk=1.5,acceleration_default=2})
local override=spec:get_physics_override()
assert(override.speed==2 and override.speed_walk==1.5 and
 override.jump==1 and override.acceleration_default==2)
-- Global speed scales acceleration as well as walk and fast speeds.
local ordinary=Physics.new(api,p(-1,-.5,0),{profile='luanti'})
ordinary:update(.05,{x=1})
spec:update(.05,{x=1})
near(ordinary.velocity.x,.15)
near(spec.velocity.x,.6)
-- Once acceleration completes, walk speed = base walk * speed * speed_walk.
for i=1,50 do spec:update(.05,{x=1}) end
near(spec.velocity.x,12)
-- A failed mixed-field update must leave all existing values untouched.
local before=spec:get_physics_override()
assert(not pcall(function()
 spec:set_physics_override({speed=3,jump=-1})
end))
assert(spec:get_physics_override().speed==before.speed)
assert(not pcall(function()
 spec:set_physics_override({acceleration_air=0/0})
end))
assert(not pcall(function()
 spec:set_physics_override({liquid_fluidity=.5})
end))
assert(not pcall(function()
 spec:set_physics_override({fly=true})
end))
assert(not pcall(function()
 spec:set_physics_override({sneak=1})
end))
-- Disabling sneak must prevent edge protection even when input requests it.
local denied=Physics.new(api,p(-1,-.5,0))
denied:set_physics_override({sneak=false})
denied:update(.05,{sneak=true,x=1})
assert(not denied.sneaking)
denied:set_physics_override({sneak=true})
denied:update(.05,{sneak=true,x=1})
assert(denied.sneaking)
-- Independent gravity and jump overrides affect vertical motion.
local jumping=Physics.new(api,p(-2,-.5,0),{profile='luanti'})
jumping:set_physics_override({jump=2,gravity=.5})
jumping:update(.05,{jump=true})
near(jumping.velocity.y,13-9.81*.5*.05)
local floating=Physics.new(api,p(12,4,0),{profile='luanti'})
floating:set_physics_override({gravity=0})
floating:update(.5,{})
near(floating.pos.y,4)
-- Ground material is found using collision geometry, NOT a guessed node
-- center beneath the player. At y=0 a slab's supporting top is in y=0.
local slick=Physics.new(api,p(1,0,0))
assert(slick:ground_material()==api.registered_nodes['test:slippery_slab'])
near(slick:surface_friction(),.25)
local normal=Physics.new(api,p(4,0,0))
near(normal:surface_friction(),1)
slick:update(.05,{x=1})
normal:update(.05,{x=1})
assert(slick.velocity.x<normal.velocity.x/2,
 'slippery nodebox must reduce ground acceleration')
-- Feet overlap the thin support even though its center lies in the next
-- cell: friction should use the ACTUAL rectangle under the feet.
local corner=Physics.new(api,p(9.94,0,0))
assert(corner:ground_material()==nil,
 'no overlap with a narrow plate should not create phantom traction')
local supported=Physics.new(api,p(9.94,0,0),{radius=.5})
-- Narrow plate ends at 8.8; player at 9.94 does not touch it.
assert(supported:ground_material()==nil)
local partial=Physics.new(api,p(8.92,0,0))
assert(partial:ground_material()==api.registered_nodes['test:thin_ice'],
 'partial overlap must resolve the slippery collision surface')
near(partial:surface_friction(),1/6)
assert(not pcall(Physics.new,api,p(0,0,0),{gravity=-1}))
print('LUA ENGINE PLAYER OVERRIDES AND MATERIALS PASS')
