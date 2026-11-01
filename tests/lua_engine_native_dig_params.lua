-- Phase 28: native dig parameters and delegated interaction regressions.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local Digging=require('core.digging')
local rt=Runtime.new()
local api=rt.api
local function p(x,y,z) return {x=x,y=y,z=z} end

-- Reference: Luanti src/tool.cpp getDigParams/calculateResultWear.
local groupcaps={cracky={times={[1]=2.4},maxlevel=3,uses=130}}
local result=api.get_dig_params({cracky=1,level=1},{groupcaps=groupcaps},0)
assert(result.diggable and result.time==1.2 and result.main_group=='cracky')
assert(result.wear==56, '130 * 3^2 uses must produce 56 wear on first dig')
local native={groupcaps={cracky={times={[1]=1},maxlevel=0,uses=130}}}
assert(api.get_dig_params({cracky=1},native,0).wear==504)
assert(api.get_dig_params({cracky=1},native,57455).wear==504)
assert(api.get_dig_params({cracky=1},native,57456).wear==505)
assert(Digging.calculate_wear(0,0)==0)
assert(api.get_dig_params({cracky=1},{groupcaps={
 cracky={times={[1]=1},maxlevel=0,uses=0}}}).wear==0)
assert(api.get_dig_params({dig_immediate=2},{groupcaps={}}).time==.5)
assert(api.get_dig_params({dig_immediate=3},{groupcaps={}}).time==0)
assert(not api.get_dig_params({dig_immediate=1},{groupcaps={}}).diggable)
assert(api.get_dig_params({dig_immediate=2},{groupcaps={
 dig_immediate={times={[2]=.75},maxlevel=0,uses=0}
}}).time==.75)
assert(not api.get_dig_params({cracky=1,level=5},{groupcaps=groupcaps}).diggable)
assert(not pcall(api.get_dig_params,{},{},0/0))

local player={name='Alice'}
function player:get_player_name() return self.name end
local sneak=false
function player:get_player_control() return {sneak=sneak} end
rt:connectPlayer(player,Physics.new(api,p(0,2,0)))
local inv=player:get_inventory()
api.register_craftitem('test:gem',{})
api.register_node('test:ore',{groups={cracky=1},drop='test:gem'})
api.register_node('test:delegate',{groups={cracky=1},drop='test:gem',
 on_dig=function(pos,node,digger)
  return api.node_dig(pos,node,digger)
 end})
api.register_tool('test:pick',{tool_capabilities={groupcaps={
 cracky={times={[1]=.1},maxlevel=0,uses=2}
}}})
local site=p(1,2,1)
api.set_node(site,{name='test:delegate'})
player:set_wielded_item('test:pick')
assert(rt:beginDigNodeAsPlayer(player,site))
assert(rt:advanceDigNodeAsPlayer(player,.1))
assert(api.get_node(site).name=='air')
assert(player:get_wielded_item():get_wear()==32768,
 'delegated core.node_dig must not incur wear twice')
assert(inv:contains_item('main','test:gem'))
local site2=p(2,2,1)
api.set_node(site2,{name='test:ore'})
assert(rt:beginDigNodeAsPlayer(player,site2))
assert(rt:advanceDigNodeAsPlayer(player,.1))
assert(player:get_wielded_item():is_empty())

local after_use_calls=0
api.register_tool('test:special',{tool_capabilities={groupcaps={
 cracky={times={[1]=.1},maxlevel=0,uses=2}
}},after_use=function(stack,digger,node,dp)
 assert(digger==player and node.name=='test:ore')
 assert(dp.diggable and dp.wear==32768 and dp.main_group=='cracky')
 after_use_calls=after_use_calls+1
 stack:set_wear(123)
 return stack
end})
player:set_wielded_item('test:special')
local site3=p(3,2,1)
api.set_node(site3,{name='test:ore'})
assert(rt:digNodeAsPlayer(player,site3))
assert(after_use_calls==1 and player:get_wielded_item():get_wear()==123)

api.register_node('test:snow',{buildable_to=true})
api.register_node('test:brick',{})
local place_count=0
api.register_on_placenode(function(pos,node,placer,old)
 assert(placer==player and node.name=='test:brick')
 place_count=place_count+1
 if old.name=='test:snow' then return true end
end)
local under=p(5,2,1)
local above=p(5,3,1)
api.set_node(under,{name='test:snow'})
player:set_wielded_item('test:brick 2')
assert(rt:placeNodeAsPlayer(player,above,{type='node',under=under,above=above}))
assert(api.get_node(under).name=='test:brick' and
 api.get_node(above).name=='air')
assert(player:get_wielded_item():get_count()==2,
 'on_placenode returning true prevents taking a stack')
assert(place_count==1)

local clicks=0
api.register_node('test:panel',{on_rightclick=function()
 clicks=clicks+1
end})
local panel=p(7,2,1)
local over=p(7,3,1)
api.set_node(panel,{name='test:panel'})
player:set_wielded_item('test:brick 2')
sneak=true
assert(rt:placeNodeAsPlayer(player,over,{type='node',under=panel,above=over}))
assert(clicks==0 and api.get_node(over).name=='test:brick')
assert(player:get_wielded_item():get_count()==1)
sneak=false
assert(rt:placeNodeAsPlayer(player,p(7,4,1),{
 type='node',under=panel,above=p(7,4,1)}))
assert(clicks==1)
rt:disconnectPlayer('Alice')
print('LUA ENGINE NATIVE DIG PARAMS AND INTERACTIONS PASS')
