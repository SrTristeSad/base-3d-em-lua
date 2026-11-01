-- Boots ORIGINAL, unmodified VoxeLibre stonecutter and formspec helpers.
-- This checks a real interaction path, not merely callback registration.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local Loader=require('core.modloader')
local Environment=require('core.modenvironment')
local root=(arg and arg[1]) or 'games/voxelibre'
root=root:gsub('/$','')

local function read(path)
 local file=assert(io.open(path,'rb'),'missing original mod: '..path)
 local contents=file:read('*a')
 file:close()
 return contents
end

local paths={
 mcl_init='mods/CORE/mcl_init',
 vl_unittests='mods/CORE/vl_unittests',
 mcl_util='mods/CORE/mcl_util',
 mcl_sounds='mods/CORE/mcl_sounds',
 mcl_formspec='mods/HUD/mcl_formspec',
 mcl_stonecutter='mods/ITEMS/mcl_stonecutter'
}
local mods={}
for name,subpath in pairs(paths) do
 local dir=root..'/'..subpath
 local def=Loader.parse(read(dir..'/mod.conf'))
 assert(def.name==name)
 def.path=dir
 mods[#mods+1]=def
end
local rt=Runtime.new({mapgen={seed=42,mg_name='v7'},
 game_info={path=root,title='VoxeLibre'}})
local runner=Environment.new(rt)
rt.opts.executeMod=function(path,name)return runner:executeMod(path,name)end
local ok,results=Loader.load(rt,Loader.plan(mods))
if not ok then
 local failures={}
 for _,v in ipairs(results) do
  if not v.ok then failures[#failures+1]=v.name..': '..v.error end
 end
 error(table.concat(failures,'\n'))
end
local g=runner.globals
assert(type(g.mcl_stonecutter.show_stonecutter_form)=='function')
assert(type(g.mcl_formspec.get_itemslot_bg_v4)=='function')
rt.api.register_node('probe:raw_stone',{})
rt.api.register_node('probe:slab',{})
g.mcl_stonecutter.register_recipe('probe:raw_stone','probe:slab',2)

-- The host supplies a real identity and look direction. The runtime gives it
-- Lua-owned inventory/metadata without replacing host methods.
local player={name='TestPlayer'}
function player:get_player_name()return self.name end
function player:get_look_dir()return {x=0,y=0,z=1} end
local controller=Physics.new(rt.api,{x=1,y=4,z=1})
assert(rt:connectPlayer(player,controller)==player)
local inv=player:get_inventory()
assert(inv:get_size('stonecutter_input')==1)
assert(inv:get_size('stonecutter_output')==1)
inv:set_stack('main',1,'probe:raw_stone 3')
g.mcl_stonecutter.show_stonecutter_form(player)
local current=rt:getPlayerFormspec('TestPlayer')
assert(current and current.formname=='mcl_stonecutter:stonecutter')
assert(current.formspec:find('list[current_player;stonecutter_input;',1,true))
assert(not current.formspec:find('item_image_button[',1,true),
 'empty stonecutter should not offer recipes before player inserts input')
assert(#current.elements>10,'genuine stonecutter uses nested rich formspec elements')
-- The original mod receives a real player InvRef on_move event and redraws
-- its source list instead of accepting fabricated direct inventory edits.
local moved,amount=rt:movePlayerInventoryStack('TestPlayer',{
 from_list='main',from_index=1,to_list='stonecutter_input',
 to_index=1,count=3})
assert(moved and amount==3)
assert(inv:get_stack('main',1):is_empty())
assert(inv:get_stack('stonecutter_input',1):get_count()==3)
assert(rt:getPlayerFormspec('TestPlayer').formspec:find(
 'item_image_button[',1,true),'upstream input move should refresh choices')
local denied,why=rt:movePlayerInventoryStack('TestPlayer',{
 from_list='stonecutter_input',from_index=1,
 to_list='stonecutter_output',to_index=1,count=1})
assert(not denied and why=='not_allowed','stonecutter protects output list')
assert(rt:receiveFormFields('TestPlayer','mcl_stonecutter:stonecutter',
 {probe__slab='2'}))
assert(player:get_meta():get_string('mcl_stonecutter:selected')=='probe:slab')
assert(inv:get_stack('stonecutter_output',1):get_name()=='probe:slab')
assert(inv:get_stack('stonecutter_output',1):get_count()==2)
-- A real output -> player InvRef move consumes input via original
-- on_player_inventory_action and recalculates the GUI.
moved,amount=rt:movePlayerInventoryStack('TestPlayer',{
 from_list='stonecutter_output',from_index=1,
 to_list='main',to_index=2,count=2})
assert(moved and amount==2,'original output must transfer to player')
assert(inv:get_stack('main',2):get_name()=='probe:slab')
assert(inv:get_stack('main',2):get_count()==2)
assert(inv:get_stack('stonecutter_input',1):get_count()==2,
 'upstream on_move must consume exactly one input for 2 outputs')
assert(inv:get_stack('stonecutter_output',1):get_count()==2)
-- Luanti's other original inventory callback, on_player_inventory_action
-- "take", must consume raw material when an output is taken into a host
-- cursor and then put into the player's inventory.
local taken
moved,taken=rt:takePlayerInventoryStack('TestPlayer',{
 listname='stonecutter_output',index=1,count=2})
assert(moved and taken:get_name()=='probe:slab' and taken:get_count()==2)
assert(inv:get_stack('stonecutter_input',1):get_count()==1,
 'upstream stonecutter take callback must consume another raw stone')
moved,amount=rt:putPlayerInventoryStack('TestPlayer',{
 listname='main',index=3,stack=taken})
assert(moved and amount==2 and taken:is_empty())
assert(inv:get_stack('main',3):get_name()=='probe:slab')
assert(inv:get_stack('main',3):get_count()==2)
assert(rt:getPlayerFormspec('TestPlayer').formspec:find(
 'mcl_inventory_button9_pressed.png',1,true),
 'original mod must update selected-button style')
-- Switch to 64-unit output using the untouched upstream UI callback.
assert(rt:receiveFormFields('TestPlayer','mcl_stonecutter:stonecutter',
 {__switch_stack='true'}))
assert(player:get_meta():get_int('mcl_stonecutter:switch_stack')==1)
assert(rt:receiveFormFields('TestPlayer','mcl_stonecutter:stonecutter',
 {__switch_stack='true'}))
assert(player:get_meta():get_int('mcl_stonecutter:switch_stack')==64)
assert(inv:get_stack('stonecutter_output',1):get_count()==2)
-- Client close must run the original inventory-return callback.
assert(rt:receiveFormFields('TestPlayer','mcl_stonecutter:stonecutter',
 {quit='true'}))
assert(rt:getPlayerFormspec('TestPlayer')==nil)
assert(inv:get_stack('stonecutter_input',1):is_empty())
assert(inv:get_stack('stonecutter_output',1):is_empty())
assert(inv:contains_item('main','probe:raw_stone 1'),
 'stonecutter quit must move the remaining actual input to inventory')
assert(rt:disconnectPlayer('TestPlayer'))
print(('ORIGINAL VOXELIBRE STONECUTTER FORMSPEC PASS: %d modules, %d source files')
 :format(#results,runner.read_count))
