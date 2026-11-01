-- Phase 9: node drops from original definitions and atomic expected results.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local rt=Runtime.new()
local api=rt.api
api.register_node('core:stone',{description='Stone',
 drop='core:cobble',groups={cracky=2}})
api.register_node('core:no_drop',{drop=''})
api.register_node('core:glass',{})
api.register_node('core:ore',{drop={
 max_items=1,items={{items={'core:gem 3'},rarity=2},
 {items={'core:gem 4'}}}}})
api.register_node('core:snow',{drop={items={
 {items={'core:snowball 2'},tools={'core:shovel'}},
 {items={'core:snowball'},rarity=2}}}})
api.register_alias('old:stone','core:stone')
local function eq(a,b)
 assert(a==b,'expected '..tostring(b)..' but got '..tostring(a))
end
local function first(t) return t[1] end
eq(first(api.get_node_drops('core:stone')),'core:cobble')
eq(first(api.get_node_drops('old:stone')),'core:cobble')
eq(#api.get_node_drops('core:no_drop'),0)
eq(first(api.get_node_drops('core:glass')),'core:glass')
eq(#api.get_node_drops('missing:node'),0)
local a=api.get_node_drops('core:ore','',function(n)return n end)
eq(first(a),'core:gem 4')
eq(#a,1)
local b=api.get_node_drops('core:ore','',function()return 1 end)
eq(first(b),'core:gem 3')
eq(#b,1)
local snow=api.get_node_drops('core:snow','core:shovel',function(n)return n end)
eq(first(snow),'core:snowball 2')
local other=api.get_node_drops('core:snow','core:sword',function(n)return n end)
eq(#other,0)
assert(not pcall(api.get_node_drops,'core:ore','',function()return 0 end))
assert(not pcall(api.get_node_drops,'core:ore','',function()return 3 end))
local p={x=3,y=1,z=-1}
api.set_node(p,{name='core:stone'})
eq(api.get_node_drops(api.get_node(p).name)[1],'core:cobble')
eq(api.get_node(p).name,'core:stone')
print('lua_engine_nodedrops: OK')
