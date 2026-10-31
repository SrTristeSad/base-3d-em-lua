-- Fase 6: Mapblock-aligned VoxelManip and mapgen registry tests.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Voxel=require('core.voxel')
local function eq(actual,expected,msg)
 assert(actual==expected,(msg or 'value')..' expected '..tostring(expected)..
  ', got '..tostring(actual))
end
local rt=Runtime.new()
local api=rt.api
api.register_node('test:stone',{groups={cracky=1}})
api.register_node('test:water',{groups={water=1,liquid=1}})
api.register_node('test:dirt',{groups={crumbly=1}})
api.register_alias('old:stone','test:stone')
local stone=api.get_content_id('test:stone')
assert(stone>=128,'registered node content IDs start after builtins')
eq(api.get_content_id('old:stone'),stone,'alias ID')
eq(api.get_name_from_content_id(stone),'test:stone')
eq(api.get_content_id('not:registered'),api.CONTENT_IGNORE)
eq(api.get_name_from_content_id(api.CONTENT_AIR),'air')
eq(api.get_name_from_content_id(api.CONTENT_IGNORE),'ignore')
assert(api.get_content_id('test:water')~=stone)
local bounds={MinEdge={x=-2,y=1,z=0},MaxEdge={x=1,y=2,z=1}}
local area=Voxel.VoxelArea:new(bounds)
eq(area:index(-2,1,0),1)
eq(area:index(-1,1,0),2)
eq(area:index(-2,2,0),5)
eq(area:index(-2,1,1),9)
eq(area:indexp({x=1,y=2,z=1}),16)
eq(area.volume,16)
assert(area:contains(0,1,1))
assert(not area:contains(2,1,1))
local count=0
for index,x,y,z in area:iter() do
 count=count+1
 eq(index,count)
 assert(area:contains(x,y,z))
end
eq(count,16)
assert(not pcall(function() area:index(2,1,1) end))
local pos={x=-1,y=0,z=1}
api.set_node(pos,{name='test:water',param2=8})
api.get_meta(pos):set_string('owner','test')
local vm,lo,hi=api.get_voxel_manip(
 {x=-1,y=0,z=0},{x=1,y=0,z=1})
eq(lo.x,-16)
eq(lo.y,0)
eq(lo.z,0)
eq(hi.x,15)
eq(hi.y,15)
eq(hi.z,15)
local a=Voxel.VoxelArea:new({MinEdge=lo,MaxEdge=hi})
eq(a.volume,32*16*16)
local idx=a:indexp(pos)
local buffer=vm:get_data()
eq(buffer[idx],api.get_content_id('test:water'))
eq(vm:get_param2_data()[idx],8)
buffer[idx]=0
eq(vm:get_data()[idx],api.get_content_id('test:water'),
 'get_data returns an isolated copy')
local p2=vm:get_param2_data()
p2[idx]=37
vm:set_param2_data(p2)
eq(vm:write_to_map(),1,'param2 write')
eq(api.get_node(pos).param2,37)
eq(api.get_meta(pos):get_string('owner'),'test','metadata preserved')
vm:set_node_at({x=0,y=0,z=0},{name='test:stone',param2=6})
eq(vm:get_node_at({x=0,y=0,z=0}).name,'test:stone')
eq(vm:write_to_map(),1,'set_node_at write')
eq(api.get_node({x=0,y=0,z=0}).param2,6)
local updated=vm:get_data()
local index=a:index(1,0,0)
updated[index]=api.get_content_id('test:dirt')
vm:set_data(updated)
updated[index]=0
eq(vm:write_to_map(),1,'data replaced by deep copy')
eq(api.get_node({x=1,y=0,z=0}).name,'test:dirt')
eq(vm:write_to_map(),0,'repeated write')
local p2bad=vm:get_param2_data()
p2bad[idx]=256
assert(not pcall(function() vm:set_param2_data(p2bad) end))
assert(not pcall(function() vm:set_node_at(
 {x=2,y=0,z=0},{name='test:dirt'}) end))
assert(not pcall(function() vm:set_node_at(
 {x=0,y=0,z=0},{name='not:registered'}) end))
assert(not pcall(function() api.get_voxel_manip(
 {x=-100,y=-100,z=-100},{x=100,y=100,z=100}) end))
-- The "ignore" content ID must not erase a loaded node.
local ignore=api.get_voxel_manip({x=0,y=0,z=0},{x=0,y=0,z=0})
ignore:set_node_at({x=0,y=0,z=0},{name='ignore'})
eq(ignore:write_to_map(),0)
eq(api.get_node({x=0,y=0,z=0}).name,'test:stone')
local id=api.register_biome({name='test:plains',heat_point=50,humidity_point=50})
eq(api.get_biome_id('test:plains'),id)
eq(api.get_biome_name(id),'test:plains')
assert(not pcall(function() api.register_biome({name='test:plains'}) end))
api.register_ore({ore='test:stone',wherein='test:dirt',clust_scarcity=8})
api.register_decoration({deco_type='simple',decoration='test:water'})
eq(#api.registered_ores,1)
eq(#api.registered_decorations,1)
assert(api.registered_biomes['test:plains'])
-- Biome / ore registration does not yet generate anything automatically.
eq(api.get_node({x=10,y=0,z=0}).name,'air')
print('lua_engine_voxel: OK')
