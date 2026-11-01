-- Phase 30: anchored node placement and configured creative tool wear.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local rt=Runtime.new()
local api=rt.api
local function p(x,y,z) return {x=x,y=y,z=z} end
local function pt(under,above)
 return {type='node',under=under,above=above}
end
local player={name='Alice'}
function player:get_player_name() return self.name end
rt:connectPlayer(player,Physics.new(api,p(0,2,0)))
api.register_node('test:stone',{groups={cracky=1}})
api.register_node('test:soft',{walkable=false})
api.register_node('test:floor',{groups={attached_node=3}})
api.register_node('test:ceiling',{groups={attached_node=4}})
api.register_node('test:wall',{groups={attached_node=1},paramtype2='wallmounted'})
api.register_node('test:rotated',{groups={attached_node=1},paramtype2='wallmounted',
 place_param2=6})
api.register_node('test:face',{groups={attached_node=2},paramtype2='facedir'})
api.register_node('test:four',{groups={attached_node=2},paramtype2='4dir'})
api.register_node('test:colorface',{groups={attached_node=2},
 paramtype2='colorfacedir'})
local success_count=0
api.register_on_placenode(function() success_count=success_count+1 end)

local function put(name,under,above,param2)
 local stack=api.ItemStack(name..' 2')
 local leftover,dest=api.item_place_node(stack,player,pt(under,above),param2)
 return leftover,dest
end
-- Inverse orientation tables follow Luanti's directiontables.cpp.
local function eq(a,b)
 assert(a and a.x==b.x and a.y==b.y and a.z==b.z)
end
eq(api.facedir_to_dir(0),p(0,0,1))
eq(api.facedir_to_dir(1),p(1,0,0))
eq(api.facedir_to_dir(4),p(0,-1,0))
eq(api.facedir_to_dir(6),p(0,1,0))
eq(api.facedir_to_dir(13),p(0,-1,0))
eq(api.facedir_to_dir(21),p(-1,0,0))
assert(api.facedir_to_dir(24)==nil)
eq(api.fourdir_to_dir(3),p(-1,0,0))
assert(api.fourdir_to_dir(4)==nil)
eq(api.wallmounted_to_dir(0),p(0,1,0))
eq(api.wallmounted_to_dir(7),p(0,-1,0))
assert(api.wallmounted_to_dir(8)==nil)

-- Floor-mounted node with no support is rejected with no side effects.
local under=p(2,1,1)
local above=p(2,2,1)
local remain,where=put('test:floor',under,above)
assert(where==nil and remain:get_count()==2)
assert(api.get_node(above).name=='air' and success_count==0)
api.set_node(under,{name='test:soft'})
remain,where=put('test:floor',under,above)
assert(where==nil and remain:get_count()==2)
api.set_node(under,{name='test:stone'})
remain,where=put('test:floor',under,above)
assert(where and where.y==above.y and remain:get_count()==1)
assert(api.get_node(above).name=='test:floor' and success_count==1)

-- Ceiling support must be walkable at +Y.
local ceiling=p(4,3,1)
local hanging=p(4,2,1)
remain,where=put('test:ceiling',p(4,1,1),hanging)
assert(where==nil)
api.set_node(ceiling,{name='test:stone'})
remain,where=put('test:ceiling',p(4,1,1),hanging)
assert(where and api.get_node(hanging).name=='test:ceiling')
-- Wallmounted directions check corresponding solid side, not just floor.
local wallnode=p(6,2,1)
local wallblock=p(7,2,1)
remain,where=put('test:wall',wallblock,wallnode)
assert(where==nil)
api.set_node(wallblock,{name='test:stone'})
remain,where=put('test:wall',wallblock,wallnode)
assert(where and api.get_node(wallnode).param2==2)

-- Vertical wallmounted value 6 attaches to ceiling.
local rotated=p(8,2,1)
api.set_node(p(8,3,1),{name='test:stone'})
remain,where=put('test:rotated',p(8,1,1),rotated)
assert(where and api.get_node(rotated).param2==6)
-- Group 2 facedir checks its back vector including 6d rotations.
local fnode=p(10,2,1)
remain,where=put('test:face',p(10,1,1),fnode,1)
assert(where==nil)
api.set_node(p(11,2,1),{name='test:stone'})
remain,where=put('test:face',p(10,1,1),fnode,1)
assert(where and api.get_node(fnode).param2==1)
local upside=p(12,2,1)
api.set_node(p(12,3,1),{name='test:stone'})
remain,where=put('test:face',p(12,1,1),upside,6)
assert(where and api.get_node(upside).param2==6)
-- colorfacedir gets orientation from the lowest five bits only.
local colored=p(14,2,1)
api.set_node(p(15,2,1),{name='test:stone'})
remain,where=put('test:colorface',p(14,1,1),colored,33)
assert(where and api.get_node(colored).param2==33)
local fourth=p(16,2,1)
api.set_node(p(15,2,1),{name='test:stone'})
remain,where=put('test:four',p(16,1,1),fourth,3)
assert(where and api.get_node(fourth).param2==3)

-- Legacy host placement is subject to the identical validation.
local host=p(18,2,1)
player:set_wielded_item('test:floor 2')
local ok,why=rt:placeNodeAsPlayer(player,host,pt(p(18,1,1),host))
assert(not ok and why=='place_failed')
assert(player:get_wielded_item():get_count()==2)
api.set_node(p(18,1,1),{name='test:stone'})
assert(rt:placeNodeAsPlayer(player,host,pt(p(18,1,1),host)))
assert(player:get_wielded_item():get_count()==1)

rt:disconnectPlayer('Alice')
-- Creative mode is an opt-in host policy; no wear in native default dig.
local creative=Runtime.new({creative_mode=true,creative_players={Bob=false}})
local a=creative.api
a.register_node('test:ore',{groups={cracky=1}})
a.register_tool('test:pick',{tool_capabilities={groupcaps={
 cracky={times={[1]=.1},uses=2,maxlevel=0}}}})
local bob={name='Bob'}
function bob:get_player_name()return self.name end
creative:connectPlayer(bob,Physics.new(a,p(0,2,0)))
assert(not a.is_creative_enabled('Bob'))
assert(a.is_creative_enabled('Other'))
bob:set_wielded_item('test:pick')
a.set_node(p(2,2,2),{name='test:ore'})
assert(creative:digNodeAsPlayer(bob,p(2,2,2)))
assert(bob:get_wielded_item():get_wear()==32768)
creative.opts.creative_players.Bob=true
assert(a.is_creative_enabled('Bob'))
a.set_node(p(3,2,2),{name='test:ore'})
assert(creative:digNodeAsPlayer(bob,p(3,2,2)))
assert(bob:get_wielded_item():get_wear()==32768,
 'creative mode must not apply any further wear')
creative.opts.creative_enabled=function(name) return name=='Bob' end
assert(a.is_creative_enabled('Bob') and not a.is_creative_enabled('Other'))
creative:disconnectPlayer('Bob')
print('LUA ENGINE PHASE 30 ATTACHMENT AND CREATIVE PASS')
