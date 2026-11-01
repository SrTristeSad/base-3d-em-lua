-- Lua engine Phase 60: same-inventory Luanti swaps plus put/take callbacks.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local rt=Runtime.new()
local api=rt.api
api.register_craftitem('test:a',{stack_max=64})
api.register_craftitem('test:b',{stack_max=64})
api.register_craftitem('test:tool',{stack_max=1})
local player={name='UIPlayer'}
function player:get_player_name()return self.name end
assert(rt:connectPlayer(player,Physics.new(api,{x=0,y=2,z=0})))
local inv=player:get_inventory()
inv:set_size('protected',2)
inv:set_size('limited',2)
inv:set_stack('main',1,'test:a 9')
inv:set_stack('main',2,'test:b 4')
inv:set_stack('protected',1,'test:b 2')
inv:set_stack('main',5,'test:tool')
local events={}
api.register_allow_player_inventory_action(function(who,action,inventory,info)
 assert(who==player and inventory==inv)
 if action=='move' then
  assert(info.from_list and info.to_list)
  events[#events+1]='allow:move:'..info.count
  if info.to_list=='protected' then return 0 end
  if info.to_list=='limited' then return 2 end
 elseif action=='take' or action=='put' then
  assert(type(info.stack)=='table' and info.stack.get_count)
  assert(type(info.listname)=='string' and info.index>=1)
  events[#events+1]='allow:'..action..':'..info.stack:get_count()
  if info.listname=='protected' then return 0 end
  if action=='take' then return 3 end
  return 2
 else error('unexpected action '..tostring(action)) end
end)
api.register_on_player_inventory_action(function(who,action,inventory,info)
 assert(who==player and inventory==inv)
 if action=='move' then
  assert(info.from_list and info.to_list and info.count>0)
  events[#events+1]='on:move:'..info.count
 else
  assert(info.stack and info.stack:get_count()>0)
  events[#events+1]='on:'..action..':'..info.stack:get_count()
 end
end)
local function move(fl,fi,tl,ti,count)
 return rt:movePlayerInventoryStack('UIPlayer',{
  from_list=fl,from_index=fi,to_list=tl,to_index=ti,count=count})
end

-- Luanti swaps the FULL stack if a requested move cannot fit another item.
-- A request for a single item does not split either stack during swap.
local ok,count=move('main',1,'main',2,1)
assert(ok and count==9)
assert(inv:get_stack('main',1):get_name()=='test:b')
assert(inv:get_stack('main',1):get_count()==4)
assert(inv:get_stack('main',2):get_name()=='test:a')
assert(inv:get_stack('main',2):get_count()==9)
assert(table.concat(events,',')=='allow:move:9,allow:move:4,on:move:9,on:move:4',
 'Luanti swap must check both directions then notify both directions')
local before=#events

-- Second direction restriction forbids full swap, even when first permits.
ok,count=move('main',2,'limited',1,6)
assert(ok and count==2,'empty destination obeys destination allow restriction')
assert(inv:get_stack('main',2):get_count()==7)
assert(inv:get_stack('limited',1):get_count()==2)
inv:set_stack('limited',2,'test:b 8')
ok,count=move('main',2,'limited',2,1)
assert(not ok and count=='not_allowed')
assert(inv:get_stack('main',2):get_count()==7)
assert(inv:get_stack('limited',2):get_count()==8)
assert(events[#events]=='allow:move:8',
 'the reverse swap must also run its own allow-move callback')

ok,count=move('main',1,'protected',1,1)
assert(not ok and count=='not_allowed')
assert(inv:get_stack('protected',1):get_count()==2)

-- Taking a stack returns a real ItemStack and notifies the mod only on
-- success, after reducing the player's source slot.
local taken
before=#events
ok,taken=rt:takePlayerInventoryStack('UIPlayer',{
 listname='main',index=2,count=5})
assert(ok and taken:get_name()=='test:a' and taken:get_count()==3)
assert(inv:get_stack('main',2):get_count()==4)
assert(events[before+1]=='allow:take:5')
assert(events[before+2]=='on:take:3')
assert(not rt:takePlayerInventoryStack('UIPlayer',{
 listname='protected',index=1,count=2}))
assert(inv:get_stack('protected',1):get_count()==2)

-- Put consumes the EXACT host-owned ItemStack, with no duplicate copies;
-- callback limits may be smaller than requested.
before=#events
ok,count=rt:putPlayerInventoryStack('UIPlayer',{
 listname='main',index=3,stack=taken,count=3})
assert(ok and count==2)
assert(inv:get_stack('main',3):get_count()==2)
assert(taken:get_count()==1)
assert(events[before+1]=='allow:put:3')
assert(events[before+2]=='on:put:2')
ok,count=rt:putPlayerInventoryStack('UIPlayer',{
 listname='main',index=3,stack=taken})
assert(ok and count==1 and taken:is_empty())
assert(inv:get_stack('main',3):get_count()==3)
assert(not rt:putPlayerInventoryStack('UIPlayer',{
 listname='main',index=3,stack=taken}))

-- Metadata and wear are transferred without erasure or inappropriate merges.
local meta=api.ItemStack('test:a 5')
meta:get_meta():set_string('marker','persistent')
inv:set_stack('main',6,meta)
ok,taken=rt:takePlayerInventoryStack('UIPlayer',{
 listname='main',index=6,count=2})
assert(ok and taken:get_meta():get_string('marker')=='persistent')
assert(taken:get_count()==2)
assert(inv:get_stack('main',6):get_meta():get_string('marker')=='persistent')
ok,count=rt:putPlayerInventoryStack('UIPlayer',{
 listname='main',index=7,stack=taken})
assert(ok and count==2 and taken:is_empty())
assert(inv:get_stack('main',7):get_meta():get_string('marker')=='persistent')

-- Disallowed transactions leave host-held item and inventory unchanged.
local denied=api.ItemStack('test:a 4')
before=#events
ok,count=rt:putPlayerInventoryStack('UIPlayer',{
 listname='protected',index=2,stack=denied})
assert(not ok and count=='not_allowed')
assert(denied:get_count()==4 and inv:get_stack('protected',2):is_empty())
assert(#events==before+1)

-- A callback changing the source during the preflight cannot overwrite
-- that change, grant unrelated items, or fire on-success notifications.
api.register_allow_player_inventory_action(function(_,action,inventory,info)
 if action=='take' and info.index==8 then
  inventory:set_stack('main',8,'test:b 2')
 elseif action=='put' and info.index==9 then
  inventory:set_stack('main',9,'test:b 2')
 end
end)
inv:set_stack('main',8,'test:a 5')
before=#events
ok,count=rt:takePlayerInventoryStack('UIPlayer',{
 listname='main',index=8,count=2})
assert(not ok and count=='inventory_changed_during_check')
assert(inv:get_stack('main',8):get_name()=='test:b')
assert(#events==before+1 and events[#events]=='allow:take:2')
local held=api.ItemStack('test:a 4')
before=#events
ok,count=rt:putPlayerInventoryStack('UIPlayer',{
 listname='main',index=9,stack=held})
assert(not ok and count=='inventory_changed_during_check')
assert(held:get_count()==4 and inv:get_stack('main',9):get_name()=='test:b')
assert(#events==before+1 and events[#events]=='allow:put:4')
assert(rt:disconnectPlayer('UIPlayer'))
assert(rt:takePlayerInventoryStack('UIPlayer',{
 listname='main',index=1,count=1})==false)
print('LUA ENGINE INVENTORY SWAP, PUT AND TAKE PASS')
