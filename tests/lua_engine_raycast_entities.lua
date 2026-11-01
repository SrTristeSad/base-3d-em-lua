-- Phase 37: selection-box raycast, item ObjectRefs, occlusion and
-- genuine host-player line-of-sight pickup in Lua 5.4 and LuaJIT.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Character=require('core.physics')
local function p(x,y,z) return {x=x,y=y,z=z} end
local function near(a,b)assert(math.abs(a-b)<.000001,
 tostring(a)..' != '..tostring(b)) end
local function world()
 local rt=Runtime.new({auto_pickup=false,item_physics=false})
 local a=rt.api
 a.register_node('test:stone',{})
 a.register_node('test:slab',{
  drawtype='nodebox',node_box={type='fixed',
   fixed={-.5,-.5,-.5,.5,0,.5}}})
 a.register_node('test:sign',{walkable=false,pointable=false})
 a.register_node('test:liquid',{
  walkable=false,liquidtype='source'})
 a.register_node('test:target',{selection_box={type='fixed',
  fixed={-.125,-.5,-.125,.125,.5,.125}}})
 a.register_node('test:sand',{groups={falling_node=1}})
 a.register_craftitem('test:gem',{})
 return rt,a
end

local rt,api=world()
local from=p(0,2,0)
local along=p(1,0,0)
api.set_node(p(3,2,0),{name='test:stone'})
local hit=assert(rt:raycast(from,along,6))
assert(hit.type=='node' and hit.under.x==3 and hit.above.x==2)
near(hit.distance,2.5)
near(hit.intersection_point.x,2.5)
-- Ray direction normalization, length limit, non-zero vectors.
near(rt:raycast(from,p(90,0,0),6).distance,2.5)
assert(not pcall(rt.raycast,rt,from,p(0,0,0),6))
assert(not pcall(rt.raycast,rt,from,along,65))
assert(not pcall(rt.raycast,rt,p(0/0,2,0),along,6))

-- The closest item wins unless a node is in front. ObjectRef identity is
-- never replaced by a snapshot and the ray does not mutate the item.
local front=api.add_item(p(1.5,2,0),'test:gem 4')
local closest=rt:raycast(from,along,6)
assert(closest.type=='object' and closest.ref==front)
assert(closest.distance>1 and closest.distance<1.5)
assert(front:get_item():get_count()==4)
assert(rt:raycast(from,along,6,{objects=false}).type=='node')
local behind=api.add_item(p(4,2,0),'test:gem')
assert(rt:raycast(from,along,6).ref==front)
front:remove()
assert(rt:raycast(from,along,6).type=='node',
 'items behind solid nodes must not be selected')
local iterator=api.raycast(from,p(6,2,0),true,false)
local first=iterator()
local second=iterator()
assert(first.type=='node' and first.under.x==3)
assert(second.type=='object' and second.ref==behind)
assert(iterator()==nil)
-- Default native-style API includes object hits.
local with_default=api.raycast(from,p(6,2,0))
assert(with_default().type=='node')
assert(with_default().type=='object')
-- Zero-length endpoint is empty, never a crash.
assert(api.raycast(from,from)()==nil)

-- Pointable and liquids flags are distinct from walkability.
local rt2,a2=world()
a2.set_node(p(1,2,0),{name='test:sign'})
a2.set_node(p(2,2,0),{name='test:liquid'})
a2.set_node(p(3,2,0),{name='test:stone'})
assert(rt2:raycast(from,along,6).under.x==3)
assert(rt2:raycast(from,along,6,{liquids=true}).under.x==2)
local node_it=a2.raycast(from,p(5,2,0),false,true)
assert(node_it().under.x==2)
assert(node_it().under.x==3)
assert(node_it()==nil)

-- Selection geometry, not collision geometry or full voxel size, decides
-- whether the player points at a slab or the solid block behind it.
local rt3,a3=world()
a3.set_node(p(2,2,0),{name='test:slab'})
a3.set_node(p(3,2,0),{name='test:stone'})
assert(rt3:raycast(p(0,2.3,0),along,6).under.x==3)
assert(rt3:raycast(p(0,1.9,0),along,6).under.x==2)
a3.remove_node(p(2,2,0))
a3.set_node(p(2,2,0),{name='test:target'})
assert(rt3:raycast(p(0,2,.35),along,6)==nil,
 'a ray beside narrow selection box must not target its whole node')
assert(rt3:raycast(p(0,2,0),along,6).under.x==2)

-- A falling world object is ray-visible but NOT a dropped-item punch.
local rt4,a4=world()
a4.set_node(p(2,2,0),{name='test:sand'})
local ok,obj=a4.spawn_falling_node(p(2,2,0))
assert(ok and obj)
local fall=assert(rt4:raycast(from,along,6))
assert(fall.type=='object' and fall.ref==obj)
assert(fall.distance==1.5)

-- Ranged host interactions recompute the first line-of-sight hit.
local game,g=world()
local alice={name='Alice'}
function alice:get_player_name() return self.name end
game:connectPlayer(alice,Character.new(g,p(0,2,0)))
local eye=p(0,3.6,0)
local item=g.add_item(p(2,3.6,0),'test:gem 5')
local yes,count=game:punchItemAlongRay(alice,eye,along,4)
assert(yes and count==5 and item.removed)
assert(alice:get_inventory():contains_item('main','test:gem 5'))
local occluded=g.add_item(p(3,3.6,0),'test:gem 2')
g.set_node(p(1,4,0),{name='test:stone'})
local no,reason=game:punchItemAlongRay(alice,eye,along,4)
assert(not no and reason=='not_item')
assert(not occluded.removed)
assert(not alice:get_inventory():contains_item('main','test:gem 7'))
g.remove_node(p(1,4,0))
no,reason=game:punchItemAlongRay(alice,eye,p(-1,0,0),4)
assert(not no and reason=='not_item')
assert(not occluded.removed)
no,reason=game:punchItemAlongRay(alice,p(30,3.6,0),along,4)
assert(not no and reason=='invalid_origin')
no,reason=game:punchItemAlongRay(alice,eye,along,2)
assert(not no and reason=='not_item',
 'item further than ray reach cannot be touched')
yes,count=game:punchItemAlongRay(alice,eye,along,4)
assert(yes and count==2 and occluded.removed)
assert(alice:get_inventory():contains_item('main','test:gem 7'))

-- Full inventory preserves world item and prevents duplicate pickups.
for i=1,32 do
 alice:get_inventory():set_stack('main',i,'test:gem 99')
end
local rest=g.add_item(p(2,3.6,0),'test:gem 8')
yes,count=game:punchItemAlongRay(alice,eye,along,4)
assert(yes and count==0 and not rest.removed)
assert(rest:get_item():get_count()==8)
alice:get_inventory():set_stack('main',1,'test:gem 95')
yes,count=game:punchItemAlongRay(alice,eye,along,4)
assert(yes and count==4 and rest:get_item():get_count()==4)
assert(alice:get_inventory():get_stack('main',1):get_count()==99)
alice:get_inventory():set_stack('main',2,nil)
yes,count=game:punchItemAlongRay(alice,eye,along,4)
assert(yes and count==4 and rest.removed)
assert(alice:get_inventory():get_stack('main',2):get_count()==4)
game:disconnectPlayer('Alice')
assert(not pcall(game.punchItemAlongRay,game,alice,eye,along,4))
print('LUA ENGINE PHASE 37 OBJECT RAYCAST AND MOUSE PICKUP PASS')
