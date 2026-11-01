-- Phase 35: item AABBs against rotated/connected/leveled node collision
-- shapes, including fast motion and approximate liquid damping.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Nodebox=require('core.nodebox')
local function p(x,y,z) return {x=x,y=y,z=z} end
local function close(actual,expected,msg)
 assert(math.abs(actual-expected)<1e-6,
  (msg or 'value')..': '..tostring(actual)..' vs '..tostring(expected))
end
local function world()
 local rt=Runtime.new({auto_pickup=false})
 local api=rt.api
 api.register_node('test:stone',{})
 api.register_node('test:slab',{drawtype='nodebox',
  node_box={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}}})
 api.register_node('test:thin',{drawtype='nodebox',
  node_box={type='fixed',fixed={-.125,-.5,-.125,.125,.5,.125}}})
 api.register_node('test:rotated',{drawtype='nodebox',paramtype2='4dir',
  node_box={type='fixed',fixed={-.375,-.5,-.125,.375,.5,.125}}})
 api.register_node('test:farbox',{drawtype='nodebox',
  node_box={type='fixed',fixed={-1.2,-.5,-.15,-.9,.5,.15}}})
 api.register_node('test:water',{drawtype='liquid',
  liquidtype='source',walkable=false,buildable_to=true})
 api.register_node('test:glass',{walkable=false,drawtype='glasslike'})
 api.register_node('test:slippery',{groups={slippery=7}})
 api.register_craftitem('test:gem',{})
 return rt,api
end
local function drop(api,x,y,z)
 local obj=api.add_item(p(x,y,z),'test:gem')
 assert(obj)
 return obj
end

-- Even large timesteps must land on the actual top of half-height slabs.
local rt,api=world()
api.set_node(p(0,0,0),{name='test:slab'})
local item=drop(api,0,12,0)
rt:step(4)
close(item:get_pos().y,.16,'slab top, not block top')
close(item:get_velocity().y,0)
rt:step(2)
close(item:get_pos().y,.16,'slab must remain stable on contact')

-- A skinny nodebox occupies only the central part of a voxel.
local rt2,a2=world()
a2.set_node(p(2,3,0),{name='test:thin'})
local thin=drop(a2,0,3,0)
thin:set_velocity(p(50,0,0))
rt2:step(.1)
close(thin:get_pos().x,2-.125-.16,'skinny post impact')
close(thin:get_velocity().x,0)
-- The same voxel may be crossed freely outside the post's Z footprint.
local rt3,a3=world()
a3.set_node(p(2,3,0),{name='test:thin'})
local outside=drop(a3,0,3,.35)
outside:set_velocity(p(50,0,0))
rt3:step(.1)
close(outside:get_pos().x,5,'unoccupied part of nodebox must pass')

-- Four-direction orientation must use the authoritative nodebox resolver.
for _,orientation in ipairs({0,1,2,3}) do
 local rotated_rt,rotated_api=world()
 rotated_api.set_node(p(2,3,0),{name='test:rotated',param2=orientation})
 local node=rotated_api.get_node(p(2,3,0))
 local boxes=Nodebox.boxes(rotated_rt.registry.nodes[node.name],node,
  rotated_rt.map,p(2,3,0),rotated_rt.registry.nodes,'collision_box')
 assert(#boxes==1)
 local swept=drop(rotated_api,0,3,0)
 swept:set_velocity(p(50,0,0))
 rotated_rt:step(.1)
 close(swept:get_pos().x,2+boxes[1][1]-.16,
  'orientation '..orientation..' precise collision boundary')
end

-- Leveled height and wallmounted orientation affect the physical hit.
local levels_rt,levels_api=world()
levels_api.register_node('test:leveled',{
 drawtype='nodebox',paramtype2='leveled',
 node_box={type='leveled',fixed={-.5,-.5,-.5,.5,.5,.5}}
})
levels_api.set_node(p(0,0,0),{name='test:leveled',param2=32})
local leveled=drop(levels_api,0,8,0)
levels_rt:step(3)
close(leveled:get_pos().y,.16,'leveled half-height landing')
local wall_rt,wall_api=world()
wall_api.register_node('test:wallmounted',{
 drawtype='nodebox',paramtype2='wallmounted',
 node_box={type='wallmounted',
  wall_top={-.3,.375,-.1,.3,.5,.1},
  wall_bottom={-.3,-.5,-.1,.3,-.375,.1},
  wall_side={-.5,-.3,-.1,-.375,.3,.1}}
})
wall_api.set_node(p(2,3,0),{name='test:wallmounted',param2=2})
local mounted=drop(wall_api,0,3,0)
mounted:set_velocity(p(50,0,0))
wall_rt:step(.1)
close(mounted:get_pos().x,2+.375-.16,'wallmounted +X bracket')

-- A connected fence rail extends collision laterally, even when its
-- connecting node itself is nonwalkable and would not block the item.
local fence_rt,fence_api=world()
fence_api.register_node('test:anchor',{walkable=false})
fence_api.register_node('test:fence',{
 drawtype='nodebox',connects_to={'test:anchor'},
 node_box={type='connected',
  fixed={-.125,-.5,-.125,.125,.5,.125},
  connect_right={.125,-.125,-.125,.5,.125,.125}}
})
fence_api.set_node(p(2,3,0),{name='test:fence'})
fence_api.set_node(p(3,3,0),{name='test:anchor'})
local rail=drop(fence_api,2.35,3,-2)
rail:set_velocity(p(0,0,30))
fence_rt:step(.1)
close(rail:get_pos().z,-.125-.16,'connected fence arm')

-- The collision broadphase includes nodeboxes extending outside own cells.
local rt4,a4=world()
a4.set_node(p(3,3,0),{name='test:farbox'})
local protruding=drop(a4,0,3,0)
protruding:set_velocity(p(50,0,0))
rt4:step(.1)
close(protruding:get_pos().x,3-1.2-.16,'protruding nodebox hit')

-- Liquids do not become solids but damp horizontal and vertical motion.
local wet_rt,wet_api=world()
local air_rt,air_api=world()
for y=2,6 do
 wet_api.set_node(p(0,y,0),{name='test:water'})
end
local wet=drop(wet_api,0,4,0)
local dry=drop(air_api,0,4,0)
wet:set_velocity(p(1,0,0))
dry:set_velocity(p(1,0,0))
wet_rt:step(.2)
air_rt:step(.2)
assert(wet:get_pos().y>dry:get_pos().y,
 'a submerged item must descend more slowly')
assert(wet:get_pos().x<dry:get_pos().x,
 'liquid damping must reduce horizontal travel')
assert(wet:get_velocity().y>dry:get_velocity().y,
 'effective liquid gravity and drag must reduce falling speed')
local rt5,a5=world()
a5.set_node(p(0,3,0),{name='test:glass'})
local passable=drop(a5,0,5,0)
rt5:step(2)
assert(passable:get_pos().y<3,'nonwalkable glass must not block items')

-- Invalid tuning is rejected, but a zero drag option is accepted.
local rt6,a6=world()
rt6.opts.item_liquid_drag=-1
a6.set_node(p(0,3,0),{name='test:water'})
drop(a6,0,3,0)
assert(not pcall(function() rt6:step(.1) end))
rt6.opts.item_liquid_drag=0
assert(pcall(function() rt6:step(.1) end))

-- Skating surfaces retain more horizontal speed than ordinary ground.
local base_rt,base_api=world()
local ice_rt,ice_api=world()
base_api.set_node(p(0,0,0),{name='test:stone'})
ice_api.set_node(p(0,0,0),{name='test:slippery'})
local base=drop(base_api,0,.66,0)
local ice=drop(ice_api,0,.66,0)
base:set_velocity(p(2,0,0))
ice:set_velocity(p(2,0,0))
base_rt:step(.1)
ice_rt:step(.1)
assert(ice:get_velocity().x>base:get_velocity().x,
 'slippery node groups must retain more horizontal velocity')

-- Item geometry in the new physics path must survive sidecar restore.
local Storage=require('core.entitystorage')
local serialized=Storage.encode(wet_rt)
local wet_restored,restored_api=world()
local drops,falling=Storage.restore(wet_restored,serialized)
assert(drops==1 and falling==0)
local old=wet:get_pos()
local new=restored_api.get_dropped_items()[1].pos
close(old.x,new.x)
close(old.y,new.y)
close(old.z,new.z)
close(wet:get_velocity().x,restored_api.get_dropped_items()[1].velocity.x)
print('LUA ENGINE PHASE 35 NODEBOX AND LIQUID ITEM PHYSICS PASS')
