-- Phase 34: swept item collisions and recoverable entity sidecar.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Storage=require('core.storage')
local Entities=require('core.entitystorage')
local function p(x,y,z) return {x=x,y=y,z=z} end
local rt=Runtime.new({auto_pickup=false})
local api=rt.api
api.register_node('test:stone',{})
api.register_node('test:sand',{groups={falling_node=1}})
api.register_craftitem('test:gem',{})
local function close(a,b)
 assert(math.abs(a-b)<.000001,tostring(a)..' ~= '..tostring(b))
end

-- Gravity works without the renderer, and large dt cannot skip the floor.
api.set_node(p(0,0,0),{name='test:stone'})
local item=api.add_item(p(0,18,0),'test:gem 7')
local velocity=item:get_velocity()
assert(velocity.x==0 and velocity.y==0)
velocity.y=42
assert(item:get_velocity().y==0,'get_velocity is defensive copy')
rt:step(.1)
assert(item:get_pos().y<18)
rt:step(10)
close(item:get_pos().y,.66)
assert(item:get_velocity().y==0)
rt:step(.2)
close(item:get_pos().y,.66)
assert(item:get_item():get_count()==7)

-- Sweep sideways through multiple voxels, hitting the first full cube.
api.set_node(p(2,3,0),{name='test:stone'})
local sliding=api.add_item(p(0,3,0),'test:gem')
assert(sliding:set_velocity(p(50,0,0)))
rt:step(.1)
close(sliding:get_pos().x,1.34)
assert(sliding:get_velocity().x==0)
local initial=sliding:get_pos()
assert(not pcall(sliding.set_velocity,sliding,p(0/0,1,0)))
assert(not pcall(sliding.set_velocity,sliding,p(math.huge,0,0)))
assert(not pcall(api.add_item,p(math.huge,0,0),'test:gem'))
close(sliding:get_pos().x,initial.x)

-- The drop snapshot stays detached, including velocity.
local snapshot=api.get_dropped_items()
snapshot[1].pos.x=99
snapshot[1].velocity.x=99
snapshot[1].stack:clear()
assert(item:get_item():get_count()==7 and item:get_pos().x==0)
assert(item:get_velocity().x==0)
assert(not sliding.removed)

-- Rich ItemStack metadata survives a versioned no-eval round trip.
local enchanted=api.ItemStack('test:gem 3')
enchanted:set_wear(17)
enchanted:get_meta():set_string('owner','a b & % unicode é')
local rich=api.add_item(p(6,7,8),enchanted)
rich:set_velocity(p(-2,3,.5))
rt:step(.3)
local saved_age=rich.age
local saved_pos=rich:get_pos()
local saved_velocity=rich:get_velocity()
assert(saved_age>=.3)

-- A falling voxel is saved separately from the map, retaining its timer,
-- node orientation, metadata fields and inventory contents.
local falling_pos=p(9,12,9)
api.set_node(falling_pos,{name='test:sand',param2=23})
api.get_meta(falling_pos):set_string('label','café & chão')
local inv=api.get_meta(falling_pos):get_inventory()
inv:set_size('main',2)
inv:set_stack('main',1,enchanted)
api.get_node_timer(falling_pos):set(30,1.25)
local ok=api.spawn_falling_node(falling_pos)
assert(ok)
rt:step(.15)
-- Snapshot all moving objects at the exact moment the sidecar is saved.
saved_age=rich.age
saved_pos=rich:get_pos()
saved_velocity=rich:get_velocity()
local moving=api.get_falling_nodes()[1]
local payload=Entities.encode(rt)
assert(payload:sub(1,#'LUAENGINE OBJECTS 1\n')=='LUAENGINE OBJECTS 1\n')
local map_data=Storage.encode(rt.map)
local fakefs={}
function fakefs.write(path,data)fakefs[path]=data;return true end
function fakefs.read(path)return fakefs[path] end
assert(Entities.save(rt,'world.objects',fakefs))
assert(fakefs['world.objects']==payload)
assert(fakefs.read('missing')==nil)
local newrt=Runtime.new({auto_pickup=false})
newrt.api.register_node('test:stone',{})
newrt.api.register_node('test:sand',{groups={falling_node=1}})
newrt.api.register_craftitem('test:gem',{})
newrt.map=Storage.decode(map_data)
newrt.map.registry=newrt.registry.items
local restored,falling=Entities.load(newrt,'world.objects',fakefs)
assert(restored==3 and falling==1)
local restored_drops=newrt.api.get_dropped_items()
assert(#restored_drops==3 and restored_drops[3].stack:get_wear()==17)
assert(restored_drops[3].stack:get_meta():get_string('owner')==
 'a b & % unicode é')
close(restored_drops[3].age,saved_age)
close(restored_drops[3].pos.y,saved_pos.y)
close(restored_drops[3].velocity.y,saved_velocity.y)
local saved_fall=newrt.api.get_falling_nodes()[1]
assert(saved_fall.node.name=='test:sand' and saved_fall.node.param2==23)
close(saved_fall.pos.y,moving.pos.y)
assert(#newrt.api.get_falling_nodes()==1)
-- Round-trip is stable to byte level while no world step has run.
assert(Entities.encode(newrt)==payload)
newrt.api.set_node(p(9,0,9),{name='test:stone'})
newrt:step(3)
assert(newrt.api.get_node(p(9,1,9)).name=='test:sand')
assert(newrt.api.get_node(p(9,1,9)).param2==23)
assert(newrt.api.get_meta(p(9,1,9)):get_string('label')=='café & chão')
local got=newrt.api.get_meta(p(9,1,9)):get_inventory():get_stack('main',1)
assert(got:get_name()=='test:gem' and got:get_count()==3 and
 got:get_wear()==17 and got:get_meta():get_string('owner')==
 'a b & % unicode é')
assert(newrt.api.get_node_timer(p(9,1,9)):is_started())

-- Invalid/injected snapshots fail without modifying live entities.
local before=Entities.encode(rt)
local valid_drops=#rt.droppedItems
assert(not pcall(Entities.restore,rt,
 'LUAENGINE OBJECTS 1\nreturn os.execute("echo should-not-run")'))
assert(Entities.encode(rt)==before and #rt.droppedItems==valid_drops)
local evil='LUAENGINE OBJECTS 1\nreturn {drops={{age=1,pos={x=0,y=0,z=0},velocity={x=0,y=0,z=0},stack={name="test:gem",count=-3,wear=0}}},falling={}}'
assert(not pcall(Entities.restore,rt,evil))
assert(Entities.encode(rt)==before)
fakefs['world.objects']='broken save'
local count,reason=Entities.load(newrt,'world.objects',fakefs)
assert(count==nil and type(reason)=='string')
assert(newrt.api.get_dropped_items()[3].stack:get_wear()==17,
 'malformed save must never wipe current runtime drops')
print('LUA ENGINE PHASE 34 ITEM PHYSICS AND ENTITY SAVE PASS')
