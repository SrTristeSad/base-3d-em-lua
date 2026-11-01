-- Sneaking on real node collision surfaces; preserves Phase 19/20 physics.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local rt=Runtime.new()
local api=rt.api
local function pos(x,y,z) return {x=x,y=y,z=z} end
api.register_node('test:stone',{groups={}})
api.register_node('test:half',{drawtype='nodebox',
 node_box={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}},
 collision_box={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}}})
api.register_node('test:water',{walkable=false,liquidtype='source',groups={water=1}})
api.register_node('test:ladder',{walkable=false,climbable=true})
local function tick(player,count,input)
 for _=1,count do player:update(.05,input or {}) end
end
local function close(a,b,tolerance)
 assert(math.abs(a-b)<(tolerance or 1e-4),
  'expected '..tostring(b)..' but received '..tostring(a))
end
-- A one-block-wide beam allows edging along its length but not walking
-- sideways off of it with sneak held.
for z=-3,3 do
 api.set_node(pos(0,0,z),{name='test:stone'})
end
local guard=Physics.new(api,pos(0,.5,0))
tick(guard,12,{x=1,sneak=true,sprint=true})
assert(guard.sneaking and guard.grounded)
assert(guard.pos.x>.45 and guard.pos.x<.56,
 'sneak keeps player center near the true edge')
assert(guard.velocity.x==0,'blocked edge movement must cancel outward velocity')
assert(guard.view_offset<0 and guard.view_offset>=-guard.sneak_eye_offset)
close(guard:eye().y,guard.pos.y+guard.eyeheight+guard.view_offset)
local oldx,oldz=guard.pos.x,guard.pos.z
tick(guard,6,{x=1,z=1,sneak=true})
assert(guard.pos.z>oldz+.2,'edge guard must preserve tangent movement')
assert(guard.pos.x<.56,'diagonal movement cannot exit platform')
close(guard.pos.y,.5)
-- Sneaking must not protect unsupported players. Normal movement crosses
-- the platform boundary, at which point ordinary gravity makes them fall.
local walking=Physics.new(api,pos(0,.5,0))
tick(walking,10,{x=1})
assert(walking.pos.x>1,'normal walking should cross an unguarded edge')
assert(walking.pos.y<.5,'character should fall once ground support ends')
-- Release of sneak restores walking speed and eye height gradually.
local last=guard.view_offset
guard:update(.05,{})
assert(guard.view_offset>last and guard.view_offset<=0,
 'crouched camera should recover smoothly')
tick(guard,15,{})
close(guard.view_offset,0)
local walkspeed=guard.speed
guard:update(.05,{x=-1,sneak=true})
assert(guard.sneaking and guard.sneak_speed<walkspeed,
 'crouching must lower maximum horizontal speed')
-- Creative-mode option: crouch changes speed but does not hold edges.
local unguarded=Physics.new(api,pos(0,.5,0),{
 acceleration=0,braking=0,sneak_edge_guard=false})
tick(unguarded,10,{x=1,sneak=true})
assert(unguarded.pos.x>.6,'edge guard opt-out should permit walking off')
-- A slab is a real physical support surface, not a phantom full cube.
api.set_node(pos(3,0,0),{name='test:half'})
local slab=Physics.new(api,pos(3,0,0))
tick(slab,8,{x=1,sneak=true})
assert(slab.pos.x>.45 and slab.pos.x<.56,
 'sneak guard must work on a half-height collision_box')
-- Holding Ctrl is reserved for descending in liquid and on a ladder.
for y=1,4 do
 api.set_node(pos(7,y,0),{name='test:water'})
 api.set_node(pos(9,y,0),{name='test:ladder'})
end
local swimming=Physics.new(api,pos(7,.5,0))
swimming:update(.05,{sneak=true})
assert(swimming.in_liquid and not swimming.sneaking,
 'water descent must not engage crouch edge guard')
local climbing=Physics.new(api,pos(9,.5,0))
climbing:update(.05,{sneak=true})
assert(climbing.on_ladder and not climbing.sneaking,
 'ladder descent must not engage crouch edge guard')
-- Disabled or nonphysical collision geometry must not provide fake support.
api.set_node(pos(12,0,0),{name='test:water'})
local no_ground=Physics.new(api,pos(12,.5,0))
assert(not no_ground:supportAt(no_ground.pos))
-- Input constraints avoid NaNs in sneak physics and camera.
assert(not pcall(Physics.new,api,pos(0,.5,0),{sneak_eye_offset=2}))
assert(not pcall(Physics.new,api,pos(0,.5,0),{sneak_camera_rate=-1}))
assert(not pcall(Physics.new,api,pos(0,.5,0),{sneak_speed=0/0}))
print('LUA ENGINE SNEAK EDGE PHYSICS PASS')
