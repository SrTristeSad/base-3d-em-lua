-- Phase 36: embedded-item recovery and real host-player item punches.
-- A game item cannot push players in Luanti (collide_with_objects=false).
-- The host can, however, punch an item and transfer its stack safely.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Character=require('core.physics')
local EntityStorage=require('core.entitystorage')
local function p(x,y,z) return {x=x,y=y,z=z} end
local function approx(a,b)
 assert(math.abs(a-b)<.00005,tostring(a)..' ~= '..tostring(b))
end
local function world(opts)
 local rt=Runtime.new(opts or {auto_pickup=false})
 local api=rt.api
 api.register_node('test:stone',{})
 api.register_node('test:thin',{drawtype='nodebox',
  node_box={type='fixed',fixed={-.125,-.5,-.125,.125,.5,.125}}})
 api.register_node('test:ghost',{walkable=false,drawtype='airlike'})
 api.register_craftitem('test:gem',{})
 api.register_craftitem('test:blocked',{
  on_pickup=function(stack,player,pointed)
   assert(pointed.type=='object' and pointed.ref:get_item():get_name()==
    'test:blocked')
   return nil
  end
 })
 return rt,api
end

-- Item inside a full solid cell must find a free cardinal face.
local rt,api=world()
api.set_node(p(0,0,0),{name='test:stone'})
local embedded=api.add_item(p(0,0,0),'test:gem 4')
rt:step(.01)
approx(embedded:get_pos().x,.66001)
approx(embedded:get_pos().z,0)
assert(not embedded.removed and embedded:get_item():get_count()==4)

-- Reusable nodeboxes are resolved at the same precision as the player.
local skinny,skapi=world()
skapi.set_node(p(0,0,0),{name='test:thin'})
local narrow=skapi.add_item(p(0,0,0),'test:gem')
skinny:step(.01)
approx(narrow:get_pos().x,.28501)

-- The positive X exit may be blocked; try negative X next.
local reversed,rvapi=world()
rvapi.set_node(p(0,0,0),{name='test:stone'})
rvapi.set_node(p(1,0,0),{name='test:stone'})
local diverted=rvapi.add_item(p(0,0,0),'test:gem')
reversed:step(.01)
approx(diverted:get_pos().x,-.66001)

-- Preserve the object if surrounded; retry after a support edit.
local trapped,tapi=world()
tapi.set_node(p(0,0,0),{name='test:stone'})
for _,c in ipairs({p(1,0,0),p(-1,0,0),p(0,0,1),
 p(0,0,-1),p(0,1,0)}) do
 tapi.set_node(c,{name='test:stone'})
end
local blocked=tapi.add_item(p(0,0,0),'test:gem 5')
blocked:set_velocity(p(2,3,4))
trapped:step(.1)
approx(blocked:get_pos().x,0)
approx(blocked:get_pos().y,0)
approx(blocked:get_velocity().x,0)
approx(blocked:get_velocity().y,0)
assert(not blocked.removed and blocked:get_item():get_count()==5)
local saved=EntityStorage.encode(trapped)
local round=world()
EntityStorage.restore(round,saved)
assert(round.api.get_dropped_items()[1].stack:get_count()==5)
-- Opening one side permits safe evacuation without duplicating the stack.
tapi.remove_node(p(1,0,0))
trapped:step(.1)
assert(blocked:get_pos().x>.66 and not blocked.removed)
assert(#tapi.get_dropped_items()==1)

-- A nonwalkable node is not treated as a solid just because it exists.
local intangible,iapi=world()
iapi.set_node(p(0,0,0),{name='test:ghost'})
local floating=iapi.add_item(p(0,0,0),'test:gem')
intangible:step(.01)
approx(floating:get_pos().x,0)
assert(floating:get_pos().y<0)

-- Native items don't physically collide with players. Their ObjectRef
-- interaction must instead be scoped to a live player and item in range.
local game,gapi=world({auto_pickup=false,item_physics=false,pickup_delay=100})
local player={name='Alice'}
function player:get_player_name() return self.name end
local controller=Character.new(gapi,p(0,2,0))
game:connectPlayer(player,controller)
local inv=player:get_inventory()
local far=gapi.add_item(p(5.5,2.5,0),'test:gem 6')
local ok,why=game:punchItemAsPlayer(player,far)
assert(not ok and why=='out_of_reach')
assert(not inv:contains_item('main','test:gem'))
local nearest=gapi.add_item(p(3.5,2.5,0),'test:gem 6')
ok,why=game:punchItemAsPlayer(player,nearest,3)
assert(not ok and why=='out_of_reach',
 'distance to player collision box is authoritative')
local success,count=game:punchItemAsPlayer(player,nearest)
assert(success and count==6 and nearest.removed)
assert(inv:contains_item('main','test:gem 6'))
ok,why=game:punchItemAsPlayer(player,nearest)
assert(not ok and why=='missing_item')
assert(inv:contains_item('main','test:gem 6'),
 'punching a removed item must not duplicate inventory')

-- A foreign-world item must not be collected across sessions.
local foreignrt,foreignapi=world({item_physics=false})
local foreign=foreignapi.add_item(p(0,2.5,0),'test:gem 3')
ok,why=game:punchItemAsPlayer(player,foreign)
assert(not ok and why=='missing_item')
assert(foreign:get_item():get_count()==3)
assert(not pcall(game.punchItemAsPlayer,game,player,far,-2))

-- The same registered callback chain used by auto pickup is used by punch.
local observed={}
gapi.register_on_item_pickup(function(item,hitter,pointed)
 observed[#observed+1]='global:'..hitter:get_player_name()
 assert(pointed.type=='object' and pointed.ref:get_item():get_name()==
  item:get_name())
 return nil
end)
local blocked_item=gapi.add_item(p(.5,2.5,0),'test:blocked 2')
success,count=game:punchItemAsPlayer(player,blocked_item)
assert(success and count==0 and blocked_item:get_item():get_count()==2)
assert(#observed==0,'item on_pickup takes precedence over global callbacks')
-- Partial stack pickup leaves exactly the remainder in the SAME world ref.
for i=1,32 do inv:set_stack('main',i,'test:gem 99') end
inv:set_stack('main',1,'test:gem 97')
local partial=gapi.add_item(p(.5,2.5,0),'test:gem 6')
success,count=game:punchItemAsPlayer(player,partial)
assert(success and count==2)
assert(not partial.removed and partial:get_item():get_count()==4)
assert(inv:get_stack('main',1):get_count()==99)
assert(#observed==1 and observed[1]=='global:Alice')
inv:set_stack('main',2,nil)
success,count=game:punchItemAsPlayer(player,partial)
assert(success and count==4 and partial.removed)
assert(inv:get_stack('main',2):get_count()==4)
assert(#observed==2)

-- Item punches can happen without minimum age, but they must be local.
local touched=gapi.add_item(p(0,2.5,0),'test:gem 2')
assert(touched.age==0)
success,count=game:punchItemAsPlayer(player,touched,0)
assert(success and count==2,'touching the player collision box works')
local old_player_position=player:get_pos()
local moving=gapi.add_item(p(0,2.5,0),'test:gem 1')
game:step(.1)
approx(player:get_pos().x,old_player_position.x)
assert(not moving.removed,'auto pickup disabled')
game:disconnectPlayer('Alice')
assert(not pcall(game.punchItemAsPlayer,game,player,moving))

print('LUA ENGINE PHASE 36 STUCK ITEMS AND PLAYER PUNCH PASS')
