-- Phase 54: actual 32-slot inventory UI + 2x2 crafting on a connected
-- player. Exercises real recipe consumption, overflow and profile reload.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local InventoryUI=require('core.demoinventory')
local PlayerStorage=require('core.playerstorage')
local function p(x,y,z)return {x=x,y=y,z=z} end
local function eq(a,b,msg)
 assert(a==b,(msg or 'value')..': '..tostring(a)..' ~= '..tostring(b))
end
local function new()
 local rt=Runtime.new({auto_pickup=false,item_physics=false})
 local api=rt.api
 api.register_node('test:wood',{description='Wood',groups={choppy=1}})
 api.register_node('test:planks',{description='Planks',groups={choppy=2}})
 api.register_node('test:stone',{description='Stone'})
 api.register_node('test:slab',{description='Slab'})
 api.register_craftitem('test:bucket',{description='Bucket'})
 api.register_craftitem('test:water',{description='Water bucket'})
 api.register_craft({type='shapeless',recipe={'test:wood'},
  output='test:planks 4'})
 api.register_craft({recipe={{'test:stone','test:stone'}},
  output='test:slab 4'})
 api.register_craft({type='shapeless',recipe={'test:water'},
  output='test:bucket',replacements={{'test:water','test:water'}}})
 local player={get_player_name=function()return 'solo' end}
 local ctrl=Physics.new(api,p(0,3,0),{profile='luanti'})
 rt:connectPlayer(player,ctrl)
 local ui=InventoryUI.new(player,api)
 return rt,api,player,ctrl,ui
end
local rt,api,player,ctrl,ui=new()
local inv=player:get_inventory()
eq(inv:get_size('main'),32)
eq(inv:get_size('craft'),4)
eq(inv:get_width('craft'),2)
assert(ui:toggle())
inv:set_stack('main',1,'test:wood 3')
inv:set_stack('main',2,'test:stone 4')
inv:set_stack('main',3,'test:water 2')
-- Moving one item to the grid must preserve other inventory stacks.
assert(ui:select(1))
assert(ui:put(1))
eq(inv:get_stack('main',1):get_count(),2)
eq(inv:get_stack('craft',1):get_name(),'test:wood')
eq(inv:get_stack('craft',1):get_count(),1)
eq(ui:preview():get_name(),'test:planks')
eq(ui:preview():get_count(),4)
local crafted,item=ui:craft()
assert(crafted)
eq(item:get_count(),4)
eq(inv:get_stack('main',1):get_count(),2)
assert(inv:contains_item('main','test:planks 4'))
assert(inv:get_stack('craft',1):is_empty())
-- Mouse hit testing uses exactly the same positions as the drawn cells.
local w,h=1280,720
local layout=ui:layout(w,h)
local kind,index=ui:hit(w,h,
 layout.mainLeft+(1.5)*layout.tile,
 layout.mainTop+.5*layout.tile)
eq(kind,'main');eq(index,2)
local ok=ui:click(w,h,
 layout.mainLeft+(1.5)*layout.tile,
 layout.mainTop+.5*layout.tile,1)
assert(ok and ui.selected==2)
-- Click the first and second grid cells to create a two-stone slab.
assert(ui:click(w,h,layout.craftLeft+.5*layout.tile,
 layout.craftTop+.5*layout.tile,1))
assert(ui:click(w,h,layout.craftLeft+1.5*layout.tile,
 layout.craftTop+.5*layout.tile,1))
eq(ui:preview():get_name(),'test:slab')
eq(inv:get_stack('main',2):get_count(),2)
local produced=ui:click(w,h,layout.resultX,layout.resultY,1)
assert(produced)
assert(inv:contains_item('main','test:slab 4'))
assert(inv:get_stack('craft',1):is_empty())
assert(inv:get_stack('craft',2):is_empty())
-- Right-click craft cell returns an ingredient without duplicating it.
assert(ui:put(3))
eq(inv:get_stack('main',2):get_count(),1)
assert(ui:click(w,h,layout.craftLeft+.5*layout.tile,
 layout.craftTop+1.5*layout.tile,2))
eq(inv:get_stack('main',2):get_count(),2)
assert(inv:get_stack('craft',3):is_empty())
assert(not ui:take(3))
-- Reject incompatible overwrites and empty source selections.
ui:select(1)
assert(ui:put(1))
ui:select(2)
local before_stone=inv:get_stack('main',2):get_count()
local impossible,why=ui:put(1)
assert(not impossible and why=='craft cell contains a different item')
eq(inv:get_stack('main',2):get_count(),before_stone)
-- A crafting recipe is not a valid result if the output cannot fit.
assert(ui:take(1))
for i=1,32 do inv:set_stack('main',i,'test:stone 99') end
inv:set_stack('main',1,'test:wood 3')
ui:select(1)
assert(ui:put(1))
local success,reason=ui:craft()
assert(not success and reason=='output full')
eq(inv:get_stack('craft',1):get_name(),'test:wood')
eq(inv:get_stack('craft',1):get_count(),1)
eq(inv:get_stack('main',1):get_count(),2)
-- Grid ingredient cannot be returned if every main slot is full.
inv:set_stack('main',1,'test:stone 99')
local returned,why=ui:take(1)
assert(not returned and why=='main inventory full')
eq(inv:get_stack('craft',1):get_name(),'test:wood')
-- A player save must include the pending ingredient and survive reload.
player:set_wield_index(2)
local old=PlayerStorage.encode(player,ctrl,1.25,.125)
local restored_rt,restored_api,restored_player,restored_ctrl,restored_ui=new()
local state=PlayerStorage.restore(restored_player,restored_ctrl,old)
eq(state.craft[1].name,'test:wood')
eq(restored_player:get_inventory():get_stack('craft',1):get_name(),'test:wood')
eq(restored_player:get_inventory():get_stack('main',1):get_name(),'test:stone')
eq(restored_player:get_wield_index(),2)
eq(PlayerStorage.encode(restored_player,restored_ctrl,1.25,.125),old)
-- No ingredients consumed from an incompatible old profile.
local old_rt,old_api,old_player,old_ctrl=new()
old_player:get_inventory():set_stack('main',1,'test:wood 5')
-- Simulate a Phase 53 player whose inventory has no crafting list.
old_player:get_inventory():set_size('craft',0)
local emptyprofile=PlayerStorage.encode(old_player,old_ctrl,0,0)
local decoded=PlayerStorage.decode(emptyprofile)
assert(decoded.craft==nil,'old saved profiles without a craft grid must load')
local load_old=PlayerStorage.restore(restored_player,restored_ctrl,emptyprofile)
assert(load_old.craft==nil)
assert(restored_player:get_inventory():get_stack('craft',1):is_empty(),
 'old profile must start with an empty grid, not stale ingredients')
-- A malformed crafting slot must not overwrite anything.
local current=PlayerStorage.encode(restored_player,restored_ctrl,0,0)
local corrupt='LUAENGINE PLAYER 1\nreturn {pos={x=0,y=1,z=0},yaw=0,'..
 'pitch=0,size=32,wield=1,items={},craft={[1]=true}}'
assert(not pcall(PlayerStorage.restore,restored_player,restored_ctrl,corrupt))
eq(PlayerStorage.encode(restored_player,restored_ctrl,0,0),current)
-- The HUD draw and hit regions must agree and always leave Pass state.
local original_lovr=_G.lovr
_G.lovr={math={newMat4=function()return {identity=true} end}}
local calls={}
local pass={}
for _,name in ipairs({'push','pop','setViewPose','setProjection',
 'setDepthTest','setMaterial','setColor','plane','text'}) do
 pass[name]=function(_,...)calls[#calls+1]={name=name,args={...}} end
end
ui:draw(pass,w,h)
_G.lovr=original_lovr
eq(calls[1].name,'push')
eq(calls[#calls].name,'pop')
local rects=0
for _,entry in ipairs(calls) do
 if entry.name=='plane' then rects=rects+1 end
end
eq(rects,38,'one menu background, 4 crafting slots, result, 32 inventory')
assert(not pcall(ui.draw,ui,pass,0,h))
assert(ui:toggle()==false)
assert(not ui:click(w,h,100,100,1))
print('LUA ENGINE PHASE 54 PLAYABLE INVENTORY CRAFTING PASS')
