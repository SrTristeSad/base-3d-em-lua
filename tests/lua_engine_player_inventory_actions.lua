-- Fase 59: actual player InvRef moves through original Luanti callback signatures.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local rt=Runtime.new()
local api=rt.api
api.register_craftitem('test:stone',{stack_max=64})
api.register_craftitem('test:other',{stack_max=64})
api.register_craftitem('test:tool',{stack_max=1})
local player={name='Alice'}
function player:get_player_name() return self.name end
rt:connectPlayer(player,Physics.new(api,{x=0,y=2,z=0}))
local inv=player:get_inventory()
inv:set_size('input',2)
inv:set_size('output',2)
inv:set_stack('main',1,'test:stone 12')
local calls={}
api.register_allow_player_inventory_action(function(p,action,i,info)
 assert(p==player and action=='move' and i==inv)
 assert(info.count>=1)
 calls[#calls+1]='allow'
 if info.to_list=='output' then return 0 end
 if info.to_list=='input' then return 3 end
 return nil
end)
api.register_on_player_inventory_action(function(p,action,i,info)
 assert(p==player and action=='move' and i==inv)
 assert(info.count>0)
 assert(i:get_stack(info.to_list,info.to_index):get_count()>=info.count)
 calls[#calls+1]='notify:'..info.count
end)
local function move(from_list,from_index,to_list,to_index,count)
 return rt:movePlayerInventoryStack('Alice',{
  from_list=from_list,from_index=from_index,
  to_list=to_list,to_index=to_index,count=count
 })
end
local ok,n=move('main',1,'input',1,6)
assert(ok and n==3)
assert(inv:get_stack('main',1):get_count()==9)
assert(inv:get_stack('input',1):get_count()==3)
assert(table.concat(calls,',')=='allow,notify:3',
 'Luanti callbacks must see preflight first and successful count afterward')
ok,n=move('main',1,'output',1,3)
assert(not ok and n=='not_allowed' and inv:get_stack('main',1):get_count()==9)
assert(inv:is_empty('output'))
assert(#calls==3,'no change callback for a blocked action')
ok,n=move('main',1,'input',1,4)
assert(ok and n==3 and inv:get_stack('input',1):get_count()==6)
assert(inv:get_stack('main',1):get_count()==6)
-- Callback counts must respect destination free space, not merely requested.
inv:set_stack('input',2,'test:stone 63')
ok,n=move('main',1,'input',2,6)
assert(ok and n==1 and inv:get_stack('input',2):get_count()==64)
assert(inv:get_stack('main',1):get_count()==5)
ok,n=move('main',1,'input',2,3)
assert(not ok and n=='destination_full')
-- A complete swap must pass permission checks in both directions.
inv:set_stack('input',2,'test:other 8')
ok,n=move('main',1,'input',2,5)
assert(not ok and n=='not_allowed')
assert(inv:get_stack('main',1):get_count()==5)
assert(inv:get_stack('input',2):get_count()==8)
local previous=#calls
for _,request in ipairs({
 {from_list='main',from_index=1,to_list='input',to_index=1,count=0},
 {from_list='main',from_index=1,to_list='input',to_index=1,count=-1},
 {from_list='main',from_index=1,to_list='input',to_index=1,count=0/0},
 {from_list='main',from_index=1,to_list='input',to_index=1,count=1.5},
 {from_list='other',from_index=1,to_list='input',to_index=1,count=1},
 {from_list='main',from_index=1,to_list='input',to_index=7,count=1},
 {from_list='main',from_index=1,to_list='main',to_index=1,count=1},
}) do
 local accepted=rt:movePlayerInventoryStack('Alice',request)
 assert(not accepted,'invalid player inventory action must be rejected')
end
assert(#calls==previous,'invalid action never reaches original mod callbacks')
-- Metadata-bearing ItemStacks must not silently merge into a different stack.
local decorated=api.ItemStack('test:stone 4')
decorated:get_meta():set_string('source','A')
inv:set_stack('main',3,decorated)
local another=api.ItemStack('test:stone 1')
another:get_meta():set_string('source','B')
inv:set_stack('input',2,another)
ok,n=move('main',3,'input',2,2)
assert(not ok and n=='not_allowed')
assert(inv:get_stack('main',3):get_meta():get_string('source')=='A')

-- Protection callback that mutates the inventory cannot authorize a stale
-- transfer. Reject after preflight and do not overwrite that modification.
api.register_allow_player_inventory_action(function(_,_,inventory,info)
 if info.to_index==2 and info.to_list=='input' then
  inventory:set_stack('input',2,'test:other 2')
 end
end)
local stale_previous=#calls
inv:set_stack('input',2,'')
ok,n=move('main',1,'input',2,1)
assert(not ok and n=='inventory_changed_during_check')
assert(inv:get_stack('main',1):get_count()==5)
assert(inv:get_stack('input',2):get_name()=='test:other')
assert(#calls==stale_previous+1,'only preflight, never on_change, for stale move')
assert(rt:disconnectPlayer('Alice'))
assert(rt:movePlayerInventoryStack('Alice',{
 from_list='main',from_index=1,to_list='input',to_index=1,count=1
})==false)
print('LUA ENGINE REAL PLAYER INVENTORY MOVE TRANSACTIONS PASS')
