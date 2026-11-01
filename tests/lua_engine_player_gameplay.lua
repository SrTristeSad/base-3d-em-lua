-- Phase 25: live player inventory/wield and node interactions, Lua 5.4/JIT.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local Inventory=require('core.inventory')
local rt=Runtime.new()
local api=rt.api
local function p(x,y,z)return {x=x,y=y,z=z} end
api.register_node('test:stone',{drop='test:cobble'})
api.register_node('test:cobble',{})
api.register_node('test:decor',{on_construct=function(pos)
 assert(pos.x==20)
end})
api.register_node('test:locked',{can_dig=function(pos,player)
 assert(player:get_player_name()=='Alice')
 return false
end})
api.register_node('test:unbreakable',{diggable=false})
api.register_node('test:custom',{on_dig=function()error('must not be called')end})
api.register_node('test:ore',{drop={items={{items={'test:gem 2'},
 tools={'test:pick'}}}}})
api.register_craftitem('test:gem',{})
api.register_tool('test:pick',{stack_max=1})
local events={}
api.register_on_dignode(function(pos,old,digger)
 assert(digger:get_player_name()=='Alice')
 events[#events+1]='dig:'..old.name
end)
api.register_on_placenode(function(pos,node,placer,old,itemstack)
 assert(placer:get_player_name()=='Alice')
 assert(itemstack and type(itemstack.get_count)=='function')
 assert(old.name=='air' and node.name=='test:decor')
 events[#events+1]='place:'..node.name
end)
local host={name='Alice'}
function host:get_player_name()return self.name end
rt:connectPlayer(host,Physics.new(api,p(0,3,0)))
local inv=host:get_inventory()
assert(inv and inv:get_size('main')==32)
assert(inv:get_location().type=='player')
assert(api.get_inventory({type='player',name='Alice'})==inv)
assert(host:get_wield_list()=='main')
assert(host:get_wield_index()==1)
assert(host:get_wielded_item():is_empty())
inv:set_stack('main',1,'test:pick')
inv:set_stack('main',2,'test:decor 3')
assert(host:get_wielded_item():get_name()=='test:pick')
local item=host:get_wielded_item()
item:clear()
assert(host:get_wielded_item():get_name()=='test:pick',
 'wielded item must be returned by value')
assert(not pcall(host.set_wield_index,host,0))
assert(not pcall(host.set_wield_index,host,33))
host:set_wield_index(2)
assert(host:get_wield_index()==2)
assert(host:get_wielded_item():get_count()==3)
assert(host:set_wielded_item('test:decor 2'))
assert(inv:get_stack('main',2):get_count()==2)
host:set_wield_index(1)
local old=p(5,2,0)
api.set_node(old,{name='test:stone'})
local ok,drop=rt:digNodeAsPlayer(host,old)
assert(ok and #drop==1 and drop[1]=='test:cobble')
assert(api.get_node(old).name=='air')
assert(inv:contains_item('main','test:cobble'))
assert(host:get_wielded_item():get_name()=='test:pick',
 'digging must not automatically destroy wielded tool')
assert(events[1]=='dig:test:stone')
api.set_node(old,{name='test:ore'})
assert(rt:digNodeAsPlayer(host,old))
assert(inv:contains_item('main','test:gem 2'),
 'tool conditional drop should use wielded item')
host:set_wield_index(2)
local place=p(20,3,0)
assert(rt:placeNodeAsPlayer(host,place))
assert(api.get_node(place).name=='test:decor')
assert(host:get_wielded_item():get_count()==1)
assert(events[#events]=='place:test:decor')
local before=host:get_wielded_item():get_count()
local placed,why=rt:placeNodeAsPlayer(host,place)
assert(not placed and why=='occupied')
assert(host:get_wielded_item():get_count()==before)
host:set_wield_index(9)
local empty,reason=rt:placeNodeAsPlayer(host,p(21,3,0))
assert(not empty and reason=='empty_hand')
host:set_wielded_item('test:gem 1')
local notnode,reason=rt:placeNodeAsPlayer(host,p(21,3,0))
assert(not notnode and reason=='not_placeable_node')
-- Every destructive rejection must leave the block in place.
for name,expected in pairs({
 ['test:locked']='can_dig',['test:unbreakable']='not_diggable',
 ['test:custom']='custom_on_dig_unsupported'
}) do
 local location=p(10,4,0)
 api.set_node(location,{name=name})
 local result,code=rt:digNodeAsPlayer(host,location)
 assert(not result and code==expected,name..' rejected: '..tostring(code))
 assert(api.get_node(location).name==name)
end
-- Do not remove a node when drops cannot fit into ANY stack.
for i=1,32 do inv:set_stack('main',i,'test:decor 99') end
local full=p(16,4,0)
api.set_node(full,{name='test:stone'})
local result,why=rt:digNodeAsPlayer(host,full)
assert(not result and why=='inventory_full')
assert(api.get_node(full).name=='test:stone')
-- A formerly full inventory accepts the drop immediately after space exists.
inv:set_stack('main',32,nil)
assert(rt:digNodeAsPlayer(host,full))
assert(inv:get_stack('main',32):get_name()=='test:cobble')
-- Protection policy is evaluated BEFORE mutations or consuming stack.
api.is_protected=function() return true end
inv:set_stack('main',1,'test:decor 2')
host:set_wield_index(1)
local protected=p(23,4,0)
api.set_node(protected,{name='test:stone'})
local result,why=rt:digNodeAsPlayer(host,protected)
assert(not result and why=='protected')
result,why=rt:placeNodeAsPlayer(host,p(24,4,0))
assert(not result and why=='protected')
assert(host:get_wielded_item():get_count()==2)
api.is_protected=function()return false end
-- Native inventory owner is NOT replaced by the runtime.
local native_inv=Inventory.new(rt.registry.items,{type='player',name='Bob'})
native_inv:set_size('main',3)
local bob={name='Bob'}
function bob:get_player_name()return self.name end
function bob:get_inventory()return native_inv end
rt:connectPlayer(bob,Physics.new(api,p(0,2,0)))
assert(bob:get_inventory()==native_inv)
assert(api.get_inventory({type='player',name='Bob'})==native_inv)
bob:set_wielded_item('test:decor 2')
assert(native_inv:get_stack('main',1):get_count()==2)
assert(rt:disconnectPlayer('Bob'))
assert(bob.get_inventory and bob.get_wielded_item==nil)
-- Only a connected host object can mutate the world.
assert(not pcall(rt.digNodeAsPlayer,rt,bob,p(5,2,0)))
assert(rt:disconnectPlayer('Alice'))
assert(host.get_inventory==nil and host.get_wielded_item==nil)
assert(host.set_wield_index==nil)
assert(api.get_inventory({type='player',name='Alice'})==nil)
print('LUA ENGINE PLAYER INVENTORY AND NODE ACTIONS PASS')
