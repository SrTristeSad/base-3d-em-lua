-- Phase 33: nearby automatic pickup, partial transfer, callbacks and metadata.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local function p(x,y,z) return {x=x,y=y,z=z} end
local rt=Runtime.new()
local api=rt.api
api.register_craftitem('test:gem',{})
api.register_craftitem('test:filler',{})
api.register_craftitem('test:rare',{})
api.register_craftitem('test:blocked',{
 on_pickup=function(stack,picker,pointed)
  assert(stack:get_name()=='test:blocked' and
   picker:get_player_name()=='Alice')
  assert(pointed.type=='object' and pointed.ref:get_item():get_name()=='test:blocked')
  return nil -- Mod explicitly declines pickup.
 end
})
local alice={name='Alice'}
function alice:get_player_name() return self.name end
rt:connectPlayer(alice,Physics.new(api,p(0,2,0)))
local inv=alice:get_inventory()
local near=p(.3,2.5,0)
local far=p(30,2.5,0)
local first=api.add_item(near,'test:gem 8')
assert(first and first:get_item():get_count()==8)
assert(api.get_dropped_items()[1].age==0)
rt:step(.2)
assert(first:get_item():get_count()==8 and not inv:contains_item('main','test:gem'),
 'pickup delay must prevent immediate same-frame collection')
rt:step(.2)
assert(inv:contains_item('main','test:gem 8') and
 #api.get_dropped_items()==0,'nearby item must enter player inventory')
assert(first.removed and not first:set_item('test:gem 1'))
first:remove()

-- Only the free space in the partial stack can be collected.
for i=1,32 do inv:set_stack('main',i,'test:filler 99') end
inv:set_stack('main',4,'test:gem 98')
local partial=api.add_item(near,'test:gem 10')
rt:step(.4)
assert(inv:get_stack('main',4):get_count()==99)
assert(not partial.removed and partial:get_item():get_count()==9,
 'nine leftover items must stay as the very same world object')
assert(#api.get_dropped_items()==1)
rt:step(.4)
assert(partial:get_item():get_count()==9 and
 inv:get_stack('main',4):get_count()==99,
 'full inventory must not duplicate or consume the remainder')
inv:set_stack('main',5,nil)
assert(rt:pickupItemsAsPlayer(alice)==9)
assert(partial.removed and inv:get_stack('main',5):get_count()==9)
assert(#api.get_dropped_items()==0)
assert(not pcall(rt.pickupItemsAsPlayer,rt,alice,-2))

-- Metadata and wear determine whether a drop can merge with a stack.
for i=1,32 do inv:set_stack('main',i,'test:filler 99') end
local marked=api.ItemStack('test:rare 3')
marked:get_meta():set_string('owner','Alice')
inv:set_stack('main',2,marked)
local matching=marked:copy()
matching:set_count(4)
local meta_drop=api.add_item(near,matching)
rt:step(.4)
assert(meta_drop and meta_drop.removed)
assert(inv:get_stack('main',2):get_count()==7)
assert(inv:get_stack('main',2):get_meta():get_string('owner')=='Alice')
local other=api.ItemStack('test:rare 2')
other:get_meta():set_string('owner','Bob')
local separate=api.add_item(near,other)
rt:step(.4)
assert(not separate.removed and separate:get_item():get_count()==2,
 'different metadata must not merge into an occupied stack')
inv:set_stack('main',3,nil)
rt:step(.1)
assert(separate.removed and inv:get_stack('main',3):get_count()==2)
assert(inv:get_stack('main',3):get_meta():get_string('owner')=='Bob')

-- Out-of-range drops must not be collected even after a long delay.
local distant=api.add_item(far,'test:gem 6')
rt:step(1)
assert(not distant.removed and distant:get_item():get_count()==6)

-- Registered callbacks use Luanti ordering; returning an ItemStack
-- intercepts default pickup, while nil delegates to the inventory.
local visits={}
api.register_on_item_pickup(function(item,picker,pointed)
 visits[#visits+1]='first:'..item:get_name()
 assert(pointed.type=='object' and pointed.ref:get_pos().x==.3)
 return nil
end)
api.register_on_item_pickup(function(item)
 visits[#visits+1]='second:'..item:get_name()
 if item:get_name()=='test:rare' then return item end
end)
assert(api.registered_on_item_pickups==rt.callbacks.on_item_pickup)
inv:set_stack('main',1,nil)
local withheld=api.add_item(near,'test:rare 2')
rt:step(.4)
assert(not withheld.removed and withheld:get_item():get_count()==2)
assert(inv:get_stack('main',1):is_empty())
assert(visits[1]=='first:test:rare' and visits[2]=='second:test:rare')
local ordinary=api.add_item(near,'test:gem 3')
rt:step(.4)
assert(ordinary.removed and inv:contains_item('main','test:gem 3'))
local blocked=api.add_item(near,'test:blocked 2')
rt:step(.4)
assert(not blocked.removed and blocked:get_item():get_count()==2,
 'custom item on_pickup returning nil must keep item in world')
blocked:set_item('test:gem 2')
rt:step(.1)
assert(blocked.removed)
-- Delegation also works when calling core.item_pickup directly.
local picked=api.item_pickup(api.ItemStack('test:gem 2'),alice,{
 type='object',ref=ordinary})
assert(picked:is_empty() and inv:contains_item('main','test:gem 7'))

-- When automatic pickup is disabled, the host can invoke a manual action.
local rt2=Runtime.new({auto_pickup=false,pickup_delay=0,pickup_radius=.7})
local a=rt2.api
a.register_craftitem('test:gem',{})
local bob={name='Bob'}
function bob:get_player_name()return self.name end
rt2:connectPlayer(bob,Physics.new(a,p(0,2,0)))
local bobj=a.add_item(p(.6,2.5,0),'test:gem 5')
rt2:step(1)
assert(not bobj.removed and bob:get_inventory():is_empty('main'))
assert(rt2:pickupItemsAsPlayer(bob,.5)==0)
assert(rt2:pickupItemsAsPlayer(bob,.7)==5)
assert(bobj.removed and bob:get_inventory():contains_item('main','test:gem 5'))
assert(not pcall(rt2.pickupItemsAsPlayer,rt2,alice,.7),
 'a disconnected or foreign player cannot collect from another world')
rt2:disconnectPlayer('Bob')

-- Multiple connected players compete deterministically, never duplicate.
local rt3=Runtime.new({pickup_delay=0})
local a3=rt3.api
a3.register_craftitem('test:gem',{})
local z={name='Zed'}
local b={name='Anna'}
function z:get_player_name() return self.name end
function b:get_player_name() return self.name end
rt3:connectPlayer(z,Physics.new(a3,p(0,2,0)))
rt3:connectPlayer(b,Physics.new(a3,p(0,2,0)))
a3.add_item(near,'test:gem 4')
rt3:step(.01)
assert(b:get_inventory():contains_item('main','test:gem 4'))
assert(not z:get_inventory():contains_item('main','test:gem'))
assert(#a3.get_dropped_items()==0)
rt3:disconnectPlayer('Zed')
rt3:disconnectPlayer('Anna')

rt:disconnectPlayer('Alice')
assert(not pcall(rt.pickupItemsAsPlayer,rt,alice))
print('LUA ENGINE PHASE 33 ITEM PICKUP PASS')
