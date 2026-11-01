-- Luanti Lua Engine phase 3: crafting behavior and transactional safety.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Engine=require('core.runtime')
local Inventory=require('core.inventory')
local Craft=require('core.crafting')
local function eq(a,b,msg)
 assert(a==b,(msg or 'value')..' expected '..tostring(b)..' got '..tostring(a))
end
local rt=Engine.new()
local api=rt.api
for name,groups in pairs({
 ['game:oak']={wood=1,tree=1},['game:birch']={wood=1,tree=1},
 ['game:iron']={metal=1},['game:stone']={rock=1},
 ['game:shroom_red']={fungus=1},['game:shroom_brown']={fungus=1},
 ['game:bucket']={container=1},
 ['game:milk']={liquid=1},
}) do api.register_craftitem(name,{groups=groups}) end
for _,name in ipairs({'game:plank','game:stick','game:workbench',
 'game:soup','game:ingot','game:coal','game:charcoal','game:ash',
 'game:torch','game:water_bucket','game:metal_box','game:tool'}) do
 api.register_craftitem(name,{stack_max=name=='game:tool' and 1 or 99})
end
api.register_alias('legacy:iron','game:iron')
local function stacks(width,names,method)
 local t={}
 for i=1,#names do t[i]=api.ItemStack(names[i] or '') end
 return {width=width,method=method or 'normal',items=t}
end
local function craft(input,expected)
 local o,dec=api.get_craft_result(input)
 eq(o.item:get_name(),expected,'output')
 return o,dec
end
api.register_craft({output='game:plank 4',recipe={{'group:wood'}}})
api.register_craft({output='game:stick 4',recipe={{'game:plank'},
 {'game:plank'}}})
api.register_craft({output='game:workbench',recipe={
 {'game:plank','game:plank'},{'game:plank','game:plank'}}})
api.register_craft({type='shapeless',output='game:soup',
 recipe={'game:shroom_red','game:shroom_brown','game:bucket'}})
api.register_craft({type='shapeless',output='game:ash',
 recipe={'game:oak','game:iron'}})
api.register_craft({output='game:metal_box',
 recipe={{'group:metal','group:metal'}}})
api.register_craft({output='game:ingot',recipe={{'legacy:iron'}}})
api.register_craft({output='game:charcoal',
 recipe={{'game:oak','game:iron'}}})
api.register_craft({type='cooking',output='game:charcoal',
 recipe='game:oak',cooktime=12})
api.register_craft({type='fuel',recipe='group:wood',burntime=7})
api.register_craft({type='shapeless',output='game:water_bucket',
 recipe={'game:milk'},replacements={{'game:milk','game:bucket'}}})
api.register_craft({type='shapeless',output='game:torch 4',
 recipe={'game:coal','game:stick'}})
local o,d=craft(stacks(2,{'game:birch'}),'game:plank')
eq(o.item:get_count(),4)
assert(d.items[1]:is_empty())
o,d=craft(stacks(3,{
 '','','','',
 'game:plank','','',
 'game:plank',''
}),'game:stick')
eq(o.item:get_count(),4)
eq(d.items[5]:get_count(),0)
eq(d.items[8]:get_count(),0)
o,d=craft(stacks(3,{
 'game:plank','game:plank','',
 'game:plank','game:plank','',
 '','',''
}),'game:workbench')
eq(o.item:get_count(),1)
o,d=craft(stacks(3,{
 'game:bucket','','game:shroom_brown',
 '','','game:shroom_red','','',''
}),'game:soup')
eq(o.item:get_count(),1)
eq(#d.items,9)
for _,a in ipairs({1,3,6}) do eq(d.items[a]:get_count(),0) end
o,d=craft(stacks(2,{'game:oak','game:iron'}),'game:charcoal')
-- a shaped recipe outranks the shapeless recipe
o,d=craft(stacks(2,{'game:iron','game:oak'}),'game:ash')
-- exact ingredient takes precedence over group ingredient
o,d=craft(stacks(2,{'game:iron'}),'game:ingot')
o,d=craft(stacks(2,{'game:iron','game:iron'}),'game:metal_box')
local noMatch=api.get_craft_result(stacks(2,{'game:stone'}))
assert(noMatch.item:is_empty())
eq(noMatch.time,0)
local smoke,used=craft(stacks(0,{'game:oak'},'cooking'),'game:charcoal')
eq(smoke.time,12)
eq(used.items[1]:get_count(),0)
local flame,usedfuel=api.get_craft_result(stacks(0,{'game:birch'},'fuel'))
assert(flame.item:is_empty())
eq(flame.time,7)
eq(usedfuel.items[1]:get_count(),0)
local filled,changed=craft(stacks(2,{'game:milk'}),'game:water_bucket')
eq(changed.items[1]:get_name(),'game:bucket')
eq(#filled.replacements,0)
filled,changed=craft(stacks(2,{'game:milk 2'}),'game:water_bucket')
eq(changed.items[1]:get_name(),'game:milk')
eq(changed.items[1]:get_count(),1)
eq(filled.replacements[1]:get_name(),'game:bucket')
eq(#api.get_all_craft_recipes('game:charcoal'),2)
eq(api.get_craft_recipe('unknown').width,0)
eq(api.get_craft_recipe('game:workbench').width,2)
eq(api.get_craft_recipe('game:soup').width,0)
assert(not pcall(api.register_craft,{type='toolrepair',output='game:tool'}))
assert(not pcall(api.register_craft,{output='game:plank',recipe={}}))
-- Output full: no ingredient consumed and no partial modifications.
local inv=Inventory.new(api.registered_items)
inv:set_size('craft',4)
inv:set_width('craft',2)
inv:set_size('main',1)
inv:set_stack('craft',1,'game:oak 2')
inv:set_stack('main',1,'game:tool')
local ok,why=api.lua_engine_craft_inventory(inv,'craft','main')
assert(not ok)
eq(why,'output full')
eq(inv:get_stack('craft',1):get_count(),2)
inv:set_stack('main',1,nil)
ok,why=api.lua_engine_craft_inventory(inv,'craft','main')
assert(ok)
eq(why:get_name(),'game:plank')
eq(inv:get_stack('craft',1):get_count(),1)
eq(inv:get_stack('main',1):get_count(),4)
-- metadata and wear are preserved for ingredients with count > 1
local more=api.ItemStack('game:milk 2')
more:get_meta():set_string('origin','farm')
inv:set_stack('craft',1,more)
inv:set_size('main',2)
inv:set_stack('main',1,nil)
ok,why=api.lua_engine_craft_inventory(inv,'craft','main')
assert(ok)
eq(inv:get_stack('craft',1):get_meta():get_string('origin'),'farm')
eq(inv:get_stack('craft',1):get_count(),1)
eq(inv:get_stack('main',1):get_name(),'game:water_bucket')
eq(inv:get_stack('main',1):get_count(),1)
-- Lack of room for replacement prevents an otherwise valid craft.
inv:set_size('main',1)
inv:set_stack('main',1,'game:water_bucket 98')
inv:set_stack('craft',1,'game:milk 2')
local before=inv:get_stack('craft',1):get_count()
ok,why=api.lua_engine_craft_inventory(inv,'craft','main')
assert(not ok)
eq(why,'replacements full')
eq(inv:get_stack('craft',1):get_count(),before)
-- Overflow from multi-count inputs does fit in an expanded output inventory.
inv:set_size('main',3)
inv:set_stack('main',1,nil)
inv:set_stack('craft',1,'game:milk 2')
ok,why=api.lua_engine_craft_inventory(inv,'craft','main')
assert(ok)
eq(inv:get_stack('main',1):get_name(),'game:water_bucket')
eq(inv:get_stack('main',2):get_name(),'game:bucket')
-- Zero-width and irregular shaped crafting should not cause an infinite loop.
assert(not pcall(api.get_craft_result,{method='invalid',width=2,items={}}))
assert(not pcall(api.get_craft_result,{method='normal',width=-3,items={}}))
-- Luanti toolrepair: two equal tools, fixed 65536 wear scale.
api.register_tool('game:pick',{groups={}})
api.register_tool('game:blocked_pick',{groups={disable_repair=1}})
api.register_tool('game:axe',{groups={}})
api.register_craft({type='toolrepair',additional_wear=-0.02})
local function repair(a,b)
 return api.get_craft_result({method='normal',width=2,items={a,b}})
end
local repaired,used=repair({name='game:pick',wear=50000},
 {name='game:pick',wear=50000})
eq(repaired.item:get_name(),'game:pick','toolrepair output')
eq(repaired.item:get_wear(),33153,'toolrepair bonus and rounding')
assert(used.items[1]:is_empty() and used.items[2]:is_empty())
local no_repair=repair('game:pick','game:axe')
assert(no_repair.item:is_empty(),'different tools cannot repair')
no_repair=repair({name='game:blocked_pick',wear=50000},
 {name='game:blocked_pick',wear=50000})
assert(no_repair.item:is_empty(),'disable_repair must block recipe')
no_repair=repair('game:oak','game:oak')
assert(no_repair.item:is_empty(),'craftitems cannot use toolrepair')
repaired=repair({name='game:pick',wear=100},
 {name='game:pick',wear=500})
eq(repaired.item:get_wear(),0,'repair wear clamped to zero')
assert(not pcall(api.register_craft,{type='toolrepair',additional_wear=0/0}),
 'invalid tool repair bonus must be rejected')
print('lua_engine_crafting: OK')
