-- Phase 55: placeable workbench and genuine 3x3 crafting inventory.
-- Lua 5.4/LuaJIT, no LÖVR GPU or filesystem required.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local UI=require('core.demoinventory')
local Profile=require('core.playerstorage')
local function p(x,y,z)return {x=x,y=y,z=z}end
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
end
local function session()
 local rt=Runtime.new({auto_pickup=false,item_physics=false})
 local api=rt.api
 api.register_node('test:wood',{description='Wood'})
 api.register_node('test:plank',{description='Planks'})
 api.register_node('test:table',{description='Crafting Table'})
 api.register_craftitem('test:stick',{description='Stick'})
 api.register_tool('test:pick',{description='Wooden Pickaxe',stack_max=1})
 api.register_craft({type='shapeless',recipe={'test:wood'},
  output='test:plank 4'})
 api.register_craft({output='test:table',recipe={
  {'test:plank','test:plank'}, {'test:plank','test:plank'}}})
 api.register_craft({output='test:pick',recipe={
  {'test:plank','test:plank','test:plank'},
  {'','test:stick',''},{'','test:stick',''}}})
 local player={get_player_name=function()return 'solo' end}
 local controller=Physics.new(api,p(0,4,0),{profile='luanti'})
 rt:connectPlayer(player,controller)
 local ui=UI.new(player,api)
 return rt,api,player,controller,ui
end
local rt,api,player,ctrl,ui=session()
local inv=player:get_inventory()
eq(inv:get_size('craft'),4)
eq(inv:get_width('craft'),2)
eq(inv:get_size('craft_table'),0)
inv:set_stack('main',1,'test:wood 3')
inv:set_stack('main',2,'test:plank 9')
inv:set_stack('main',3,'test:stick 5')
-- Personal 2x2 crafting remains available without a workbench.
assert(ui:toggle())
ui:select(1)
assert(ui:put(1))
eq(ui:preview():get_name(),'test:plank')
assert(ui:toggle()==false)
assert(ui:openWorkbench())
eq(inv:get_size('craft_table'),9)
eq(inv:get_width('craft_table'),3)
assert(ui.workbench and ui.open)
eq(#ui:craft_slots(),9)
assert(ui:preview():is_empty())
eq(inv:get_stack('craft',1):get_name(),'test:wood')
-- Recipes requiring a third column cannot run on the personal 2x2 grid.
ui:select(2)
for _,slot in ipairs({1,2,3}) do assert(ui:put(slot))end
ui:select(3)
for _,slot in ipairs({5,8}) do assert(ui:put(slot))end
eq(ui:preview():get_name(),'test:pick')
eq(ui:preview():get_count(),1)
eq(inv:get_stack('main',2):get_count(),6)
eq(inv:get_stack('main',3):get_count(),3)
-- Real on-screen hitboxes cover all 9 cells in 3 separate rows.
local layout=ui:layout(1280,720)
local kind,index=ui:hit(1280,720,
 layout.craftLeft+2.5*layout.tile,
 layout.craftTop+2.5*layout.tile)
eq(kind,'craft')
eq(index,9)
local kind2,index2=ui:hit(1280,720,layout.resultX,layout.resultY)
eq(kind2,'result')
eq(index2,1)
local kind3,index3=ui:hit(1280,720,
 layout.mainLeft+7.5*layout.tile,
 layout.mainTop+3.5*layout.tile)
eq(kind3,'main')
eq(index3,32)
-- Fabricating through the shared craft transaction is atomic.
local ok,result=ui:click(1280,720,layout.resultX,layout.resultY,1)
assert(ok)
eq(result:get_name(),'test:pick')
assert(inv:contains_item('main','test:pick'))
for i=1,9 do assert(inv:get_stack('craft_table',i):is_empty())end
eq(inv:get_stack('craft',1):get_name(),'test:wood')
-- Testing workbench 3x3 input above/below bounds.
assert(not ui:put(0))
assert(not ui:put(10))
assert(not ui:take(10))
assert(not ui:put(1.5))
ui:select(2)
assert(ui:put(9))
eq(inv:get_stack('craft_table',9):get_name(),'test:plank')
assert(ui:click(1280,720,layout.craftLeft+2.5*layout.tile,
 layout.craftTop+2.5*layout.tile,2))
assert(inv:get_stack('craft_table',9):is_empty())
-- Keep a pending ingredient in BOTH independent crafting grids.
ui:select(3)
assert(ui:put(9))
eq(inv:get_stack('craft_table',9):get_name(),'test:stick')
assert(ui:toggle()==false)
assert(not ui.workbench)
assert(ui:toggle())
eq(ui:preview():get_name(),'test:plank')
eq(#ui:craft_slots(),4)
assert(not ui:put(5))
eq(inv:get_stack('craft_table',9):get_name(),'test:stick')
-- No data may vanish on save/reload, including both craft grids.
local profile=Profile.encode(player,ctrl,.25,-.1)
local decoded=Profile.decode(profile)
eq(decoded.craft[1].name,'test:wood')
eq(decoded.craft_table[9].name,'test:stick')
local next_rt,next_api,next_player,next_ctrl,next_ui=session()
Profile.restore(next_player,next_ctrl,profile)
local next_inv=next_player:get_inventory()
eq(next_inv:get_stack('craft',1):get_name(),'test:wood')
eq(next_inv:get_stack('craft_table',9):get_name(),'test:stick')
eq(next_inv:get_size('craft_table'),9)
eq(next_inv:get_width('craft_table'),3)
eq(Profile.encode(next_player,next_ctrl,.25,-.1),profile)
assert(next_ui:openWorkbench())
eq(#next_ui:craft_slots(),9)
eq(next_ui:craft_slots()[9].name,'test:stick')
-- A previous profile with only 2x2 crafting must clear a stale 3x3
-- grid when restored over a connected player session.
local older_rt,older_api,older_player,older_ctrl,older_ui=session()
local old_profile=Profile.encode(older_player,older_ctrl,0,0)
assert(Profile.decode(old_profile).craft_table==nil)
Profile.restore(next_player,next_ctrl,old_profile)
assert(next_player:get_inventory():get_stack('craft_table',9):is_empty())
assert(next_player:get_inventory():get_stack('craft',1):is_empty())
-- Invalid 3x3 data is validated BEFORE any inventory mutation.
local unchanged=Profile.encode(next_player,next_ctrl,0,0)
local corrupt='LUAENGINE PLAYER 1\nreturn {pos={x=0,y=1,z=0},yaw=0,'..
 'pitch=0,size=32,wield=1,items={},craft_table={[9]=true}}'
assert(not pcall(Profile.restore,next_player,next_ctrl,corrupt))
eq(Profile.encode(next_player,next_ctrl,0,0),unchanged)
-- Full backpack refuses 3x3 recipe without consuming ingredients.
local full_rt,full_api,full_player,full_ctrl,full_ui=session()
local full=full_player:get_inventory()
for i=1,32 do full:set_stack('main',i,'test:wood 99')end
full:set_stack('main',1,'test:plank 5')
full:set_stack('main',2,'test:stick 3')
full_ui:openWorkbench()
full_ui:select(1)
for _,slot in ipairs({1,2,3})do assert(full_ui:put(slot))end
full_ui:select(2)
assert(full_ui:put(5))
assert(full_ui:put(8))
eq(full_ui:preview():get_name(),'test:pick')
local before_planks=full:get_stack('main',1):get_count()
local refused,reason=full_ui:craft()
assert(not refused and reason=='output full')
eq(full:get_stack('main',1):get_count(),before_planks)
eq(full:get_stack('craft_table',1):get_name(),'test:plank')
eq(full:get_stack('craft_table',8):get_name(),'test:stick')
-- View draws nine workbench cells plus result and main inventory.
local before=_G.lovr
_G.lovr={math={newMat4=function()return {identity=true}end}}
local calls,pass={},{}
for _,method in ipairs({'push','pop','setViewPose','setProjection',
 'setDepthTest','setMaterial','setColor','plane','text'})do
 pass[method]=function(_,...)calls[#calls+1]={method=method,args={...}}end
end
full_ui:draw(pass,1280,720)
_G.lovr=before
eq(calls[1].method,'push')
eq(calls[#calls].method,'pop')
local planes=0
for _,call in ipairs(calls)do
 if call.method=='plane' then planes=planes+1 end
end
eq(planes,43,'workbench + 9 ingredients + result + 32 slots')
print('LUA ENGINE PHASE 55 3X3 CRAFTING TABLE PASS')
