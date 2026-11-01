-- Phase 31: support loss, falling objects, swept gravity and retained drops.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Stack=require('core.itemstack')
local rt=Runtime.new()
local api=rt.api
local function p(x,y,z) return {x=x,y=y,z=z} end
api.register_node('test:stone',{})
api.register_node('test:sand',{groups={falling_node=1},
 on_construct=function(pos)
  api.get_meta(pos):set_string('created','yes')
 end})
api.register_node('test:torch',{paramtype2='wallmounted',
 groups={attached_node=1},drop='test:torch'})
api.register_node('test:flower',{groups={attached_node=3},
 drop='test:seed',
 preserve_metadata=function(pos,node,fields,drops)
  assert(node.name=='test:flower' and fields.author=='Alice')
  drops[1]:get_meta():set_string('owner',fields.author)
  fields.author='modified'
 end})
api.register_craftitem('test:seed',{})
api.register_node('test:liquid',{walkable=false,liquidtype='source',
 buildable_to=true})
api.register_node('test:float_sand',{groups={falling_node=1,float=1}})

-- Bare core.set_node is raw map manipulation: it doesn't perform
-- registered_on_placenode/falling callbacks by itself.
local unsupported=p(2,2,1)
api.set_node(unsupported,{name='test:torch',param2=1})
assert(api.get_node(unsupported).name=='test:torch')
assert(api.check_single_for_falling(unsupported))
assert(api.get_node(unsupported).name=='air')
local drops=api.get_dropped_items()
assert(#drops==1 and drops[1].stack:get_name()=='test:torch')
drops[1].stack:clear()
assert(api.get_dropped_items()[1].stack:get_name()=='test:torch',
 'host snapshots must not expose mutable internal item stacks')
assert(not api.check_single_for_falling(unsupported))

-- Supported wall-mounted torch must survive checks.
api.set_node(p(4,2,1),{name='test:stone'})
api.set_node(p(3,2,1),{name='test:torch',param2=2})
assert(not api.check_single_for_falling(p(3,2,1)))
assert(api.get_node(p(3,2,1)).name=='test:torch')
-- core.dig_node automatically triggers falling for affected neighbors.
assert(api.dig_node(p(4,2,1)))
assert(api.get_node(p(3,2,1)).name=='air')
assert(#api.get_dropped_items()==2)
assert(api.get_dropped_items()[2].stack:get_name()=='test:torch')

-- The attached node's metadata is preserved in dropped ItemStack data.
local flower=p(6,2,1)
api.set_node(p(6,1,1),{name='test:stone'})
api.set_node(flower,{name='test:flower'})
api.get_meta(flower):set_string('author','Alice')
assert(api.dig_node(p(6,1,1)))
assert(api.get_node(flower).name=='air')
assert(api.get_meta(flower):get_string('author')=='')
local found=api.get_dropped_items()[3]
assert(found and found.stack:get_name()=='test:seed')
assert(found.stack:get_meta():get_string('owner')=='Alice')

-- Native order rechecks dependent nodes when supports drop.
api.register_node('test:upper',{groups={attached_node=3}})
local base=p(8,1,1)
local middle=p(8,2,1)
local top=p(8,3,1)
api.set_node(base,{name='test:stone'})
api.set_node(middle,{name='test:upper'})
api.set_node(top,{name='test:upper'})
assert(api.dig_node(base))
assert(api.get_node(middle).name=='air' and
 api.get_node(top).name=='air',
 'support failure must propagate upwards through dependent attachments')
assert(#api.get_dropped_items()==5)

-- A falling node transfers its old param2, metadata and timer to its landing.
local ground=p(10,0,1)
local support=p(10,3,1)
local sand=p(10,4,1)
api.set_node(ground,{name='test:stone'})
api.set_node(support,{name='test:stone'})
api.set_node(sand,{name='test:sand',param2=7})
api.get_meta(sand):set_string('owner','Bob')
api.get_node_timer(sand):set(12,2)
assert(api.dig_node(support))
assert(api.get_node(sand).name=='air')
local falling=api.get_falling_nodes()
assert(#falling==1 and falling[1].node.name=='test:sand')
assert(falling[1].node.param2==7 and falling[1].pos.y==4)
falling[1].pos.y=-99
assert(api.get_falling_nodes()[1].pos.y==4)
rt:step(.1)
assert(#api.get_falling_nodes()==1 and
 api.get_falling_nodes()[1].pos.y<4)
rt:step(1)
assert(#api.get_falling_nodes()==0)
local landed=p(10,1,1)
assert(api.get_node(landed).name=='test:sand')
assert(api.get_node(landed).param2==7)
assert(api.get_meta(landed):get_string('owner')=='Bob')
assert(api.get_meta(landed):get_string('created')=='',
 'original metadata overrides on_construct metadata when landing')
local timer=api.get_node_timer(landed)
assert(timer:is_started() and timer:get_timeout()==12 and
 timer:get_elapsed()>=2,
 'falling object must preserve the original node timer')

-- Fast steps must not tunnel below a solid floor.
api.set_node(p(12,0,1),{name='test:stone'})
api.set_node(p(12,20,1),{name='test:sand'})
assert(api.spawn_falling_node(p(12,20,1)))
rt:step(10)
assert(api.get_node(p(12,1,1)).name=='test:sand')
assert(#api.get_falling_nodes()==0)

-- Float group refuses to pass through source liquid.
api.set_node(p(14,1,1),{name='test:liquid'})
api.set_node(p(14,2,1),{name='test:float_sand'})
assert(not api.check_single_for_falling(p(14,2,1)))
assert(api.get_node(p(14,2,1)).name=='test:float_sand')

-- core.add_item holds metadata-bearing ItemStacks as real Lua values,
-- not lossy strings. It exposes a host-visible drop record and removal.
local stack=Stack.new('test:seed',rt.registry.items)
stack:get_meta():set_string('enchantment','preserved')
local object=api.add_item(p(15,2,1),stack)
assert(object and object:get_item():get_meta():get_string('enchantment')==
 'preserved')
local before=#api.get_dropped_items()
object:remove()
assert(#api.get_dropped_items()==before-1)
object:remove()
assert(#api.get_dropped_items()==before-1)
print('LUA ENGINE FALLING NODES AND ATTACHED DROPS PASS')
