-- Phase 29: original Luanti builtin item placement and preserved drops.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local rt=Runtime.new()
local api=rt.api
local function p(x,y,z) return {x=x,y=y,z=z} end
local function pointed(under,above)
 return {type='node',under=under,above=above}
end
local player={name='Alice'}
function player:get_player_name() return self.name end
local sneak=false
function player:get_player_control() return {sneak=sneak} end
rt:connectPlayer(player,Physics.new(api,p(0,2,0)))
local inv=player:get_inventory()
api.register_node('test:wall',{paramtype2='wallmounted'})
api.register_node('test:chest',{paramtype2='facedir'})
api.register_node('test:4dir',{paramtype2='4dir'})
api.register_node('test:fixed',{place_param2=9,paramtype2='wallmounted'})
api.register_node('test:colored',{paramtype2='colorwallmounted'})
api.register_node('test:replaceable',{buildable_to=true})
api.register_node('test:marker',{})
api.register_craftitem('test:gem',{})
assert(api.dir_to_wallmounted(p(0,-1,0))==1)
assert(api.dir_to_wallmounted(p(0,1,0))==0)
assert(api.dir_to_wallmounted(p(1,0,0))==2)
assert(api.dir_to_wallmounted(p(-1,0,0))==3)
assert(api.dir_to_wallmounted(p(0,0,1))==4)
assert(api.dir_to_wallmounted(p(0,0,-1))==5)
assert(api.dir_to_facedir(p(1,0,0))==1)
assert(api.dir_to_facedir(p(-1,0,0))==3)
assert(api.dir_to_fourdir(p(0,0,-1))==2)

-- A default placement helper returns the *position* (not a boolean).
local side=p(2,2,1)
local pt=pointed(p(3,2,1),side) -- mounting towards +X
local remaining,placed=api.item_place_node(api.ItemStack('test:wall 3'),player,pt)
assert(placed and placed.x==2 and placed.y==2)
assert(api.get_node(side).name=='test:wall' and
 api.get_node(side).param2==2)
assert(remaining:get_count()==2)
local already,where=api.item_place_node(remaining,player,pt)
assert(where==nil and already:get_count()==2)

-- Explicit param2 overrides wallmounted calculation.
local above=p(3,3,1)
local dest=p(3,4,1)
remaining,placed=api.item_place_node(remaining,player,
 pointed(above,dest),5)
assert(placed and api.get_node(dest).param2==5)
local fixed=p(5,4,1)
remaining,placed=api.item_place_node(api.ItemStack('test:fixed'),player,
 pointed(p(5,3,1),fixed),3)
assert(placed and api.get_node(fixed).param2==9)
-- Player relative position determines facedir; 4dir is horizontal too.
local chest=p(8,2,1)
remaining,placed=api.item_place_node(api.ItemStack('test:chest'),player,
 pointed(p(8,1,1),chest))
assert(placed and api.get_node(chest).param2==1)
local fourth=p(-7,2,1)
remaining,placed=api.item_place_node(api.ItemStack('test:4dir'),player,
 pointed(p(-7,1,1),fourth))
assert(placed and api.get_node(fourth).param2==3)

-- Palette index is copied from ItemStack metadata into param2's high bits.
local colored=p(10,2,1)
local colored_stack=api.ItemStack('test:colored')
colored_stack:get_meta():set_int('palette_index',27)
remaining,placed=api.item_place_node(colored_stack,player,
 pointed(p(10,1,1),colored))
assert(placed and api.get_node(colored).param2==25,
 'palette index 27 occupies high bits, floor mount has value 1')

-- A mod can call core.item_place to invoke on_rightclick or default place.
local clicked=0
api.register_node('test:panel',{on_rightclick=function(pos,node,clicker,stack)
 assert(clicker==player and node.name=='test:panel')
 clicked=clicked+1
 stack:take_item()
 return stack
end})
local panel=p(12,1,1)
api.set_node(panel,{name='test:panel'})
local top=p(12,2,1)
local item=api.ItemStack('test:marker 2')
remaining,placed=api.item_place(item,player,pointed(panel,top))
assert(clicked==1 and placed==nil and remaining:get_count()==1)
assert(item:get_count()==2,'Lua ItemStack passed by value remains unchanged')
sneak=true
remaining,placed=api.item_place(item,player,pointed(panel,top))
assert(clicked==1 and placed and placed.y==2 and
 api.get_node(top).name=='test:marker')
assert(remaining:get_count()==1)
sneak=false
-- An already occupied above cannot block placement INTO buildable_to under.
local replace=p(15,1,1)
api.set_node(replace,{name='test:replaceable'})
api.get_meta(replace):set_string('old','leak')
api.get_node_timer(replace):start(3)
api.set_node(p(15,2,1),{name='test:marker'})
remaining,placed=api.item_place_node(api.ItemStack('test:wall'),player,
 pointed(replace,p(15,2,1)))
assert(placed and placed.y==1 and api.get_node(replace).name=='test:wall')
assert(api.get_meta(replace):get_string('old')=='' and
 not api.get_node_timer(replace):is_started(),
 'replacing buildable_to must clear the old metadata and timer')
-- The host path supports the same under-position replacement.
local replace2=p(16,1,1)
api.set_node(replace2,{name='test:replaceable'})
api.set_node(p(16,2,1),{name='test:marker'})
player:set_wielded_item('test:wall 2')
assert(rt:placeNodeAsPlayer(player,p(16,2,1),
 pointed(replace2,p(16,2,1))))
assert(api.get_node(replace2).name=='test:wall')
assert(player:get_wielded_item():get_count()==1)

-- Preserve metadata receives a copy of old fields and mutable drop stacks.
local preserved=0
local did_dig=0
api.register_node('test:ore',{drop='test:gem',
 preserve_metadata=function(pos,old,oldfields,drops)
  assert(old.name=='test:ore' and pos.x==20 and oldfields.owner=='Alice')
  preserved=preserved+1
  oldfields.owner='MUTATED'
  local meta=drops[1]:get_meta()
  meta:set_string('source','kept')
  meta:set_string('owner',oldfields.owner)
 end,
 after_dig_node=function(pos,node,oldmeta,digger)
  assert(digger==player and node.name=='test:ore')
  assert(oldmeta.fields.owner=='Alice',
   'preserve_metadata cannot change captured original metadata')
  assert(api.get_meta(pos):get_string('owner')=='')
  did_dig=did_dig+1
 end
})
local ore=p(20,2,1)
api.set_node(ore,{name='test:ore'})
api.get_meta(ore):set_string('owner','Alice')
local ok,drops=rt:digNodeAsPlayer(player,ore)
assert(ok and #drops==1 and type(drops[1])=='table')
assert(preserved==1 and did_dig==1)
assert(api.get_node(ore).name=='air')
local found
for _,stack in ipairs(inv:get_list('main')) do
 if stack:get_name()=='test:gem' and
  stack:get_meta():get_string('source')=='kept' then found=stack end
end
assert(found and found:get_meta():get_string('owner')=='MUTATED')
-- A failed inventory preflight does not remove a node or grant its drops.
for i=1,inv:get_size('main') do
 inv:set_stack('main',i,'test:marker 99')
end
api.set_node(ore,{name='test:ore'})
api.get_meta(ore):set_string('owner','Alice')
local blocked,reason=rt:digNodeAsPlayer(player,ore)
assert(not blocked and reason=='inventory_full')
assert(api.get_node(ore).name=='test:ore')
assert(api.get_meta(ore):get_string('owner')=='Alice')
assert(did_dig==1)
rt:disconnectPlayer('Alice')
print('LUA ENGINE PHASE 29 PLACEMENT AND METADATA PASS')
