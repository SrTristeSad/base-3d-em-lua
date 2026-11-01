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
local View=require('core.formspecview')
local view=View.new(rt,'TestPlayer')
local w,h=1300,850
local function locate(kind,predicate)
 local layout=assert(view:layout(w,h))
 for _,c in ipairs(layout.controls) do
  if c.kind==kind and predicate(c) then return c end
 end
 error('original stonecutter missing visual control '..kind)
end
local function click(c,button)
 return view:click(w,h,c.x+c.w/2,c.y+c.h/2,button or 1)
end
local current=assert(view:session())
assert(current.formname=='mcl_stonecutter:stonecutter')
assert(current.formspec:find('list[current_player;stonecutter_input;',1,true))
local main1=locate('slot',function(c)
 return c.list=='main' and c.index==1 end)
local input=locate('slot',function(c)
 return c.list=='stonecutter_input' and c.index==1 end)
assert(click(main1)=='true' or view.selected~=nil)
-- The second actual mouse click performs a real InvRef move.  The unmodified
-- upstream mod sees on_player_inventory_action and re-sends the formspec.
local moved,count=click(input)
assert(moved and count==3)
assert(inv:get_stack('main',1):is_empty())
assert(inv:get_stack('stonecutter_input',1):get_count()==3)
local recipe=locate('button',function(c)
 return c.field=='probe__slab' and c.item=='probe:slab'
end)
assert(click(recipe))
assert(player:get_meta():get_string('mcl_stonecutter:selected')=='probe:slab')
assert(inv:get_stack('stonecutter_output',1):get_count()==2)
local output=locate('slot',function(c)
 return c.list=='stonecutter_output' and c.index==1 end)
local main2=locate('slot',function(c)
 return c.list=='main' and c.index==2 end)
assert(click(output))
moved,count=click(main2)
assert(moved and count==2)
assert(inv:get_stack('main',2):get_name()=='probe:slab')
assert(inv:get_stack('stonecutter_input',1):get_count()==2,
 'original VoxeLibre must consume one stone from visual output move')
local toggle=locate('button',function(c)return c.field=='__switch_stack' end)
assert(click(toggle))
assert(player:get_meta():get_int('mcl_stonecutter:switch_stack')==1)
assert(click(locate('button',function(c)
 return c.field=='__switch_stack' end)))
assert(player:get_meta():get_int('mcl_stonecutter:switch_stack')==64)
assert(inv:get_stack('stonecutter_output',1):get_count()==4)
-- Actual LÖVR draw uses the original formspec layout. Images are currently
-- flat placeholders; the source UI geometry and interactions are authentic.
local old=_G.lovr
_G.lovr={math={newMat4=function()return {} end}}
local commands={}
local pass={}
for _,name in ipairs({'push','pop','setViewPose','setProjection',
 'setDepthTest','setMaterial','setColor','plane','text'}) do
 pass[name]=function(_,...)commands[#commands+1]=name end
end
assert(view:draw(pass,w,h))
_G.lovr=old
assert(commands[1]=='push' and commands[#commands]=='pop')
assert(#commands>20)
assert(view:close())
assert(view:session()==nil)
assert(inv:get_stack('stonecutter_input',1):is_empty())
assert(inv:get_stack('stonecutter_output',1):is_empty())
assert(inv:contains_item('main','probe:raw_stone 2'))
assert(rt:disconnectPlayer('TestPlayer'))
print(('ORIGINAL VOXELIBRE STONECUTTER VISUAL PASS: %d modules, %d source files')
 :format(#results,runner.read_count))
