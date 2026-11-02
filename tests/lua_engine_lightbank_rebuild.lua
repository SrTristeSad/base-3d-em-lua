-- Phase 75: actual per-mapblock packed day/night bank rebuild.
-- Sunlight is stored in the low nibble, torch light in the high nibble.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Map=require('core.map')
local Storage=require('core.storage')
local rt=Runtime.new()
local api=rt.api
local function p(x,y,z) return {x=x,y=y,z=z} end
local function eq(actual,wanted,what)
 assert(actual==wanted,(what or 'value')..': '..tostring(actual)..' ~= '..tostring(wanted))
end
local function index(x,y,z)
 return 1+(x%16)*256+(y%16)*16+(z%16)
end
api.register_node('bank:stone',{tiles={'default_stone.png'}})
api.register_node('bank:lamp',{light_source=3,drawtype='torchlike',paramtype='light'})
local first=p(1,0,1)
eq(api.fix_light(first,first),false,'unloaded map cannot be relit')
assert(next(rt.map.lightbanks)==nil,'failed fix_light must not mutate map')
rt.map.generatedChunks['0,0']=42
local before=rt.map.geometry_revision
eq(api.fix_light(first,first),true,'one generated mapblock')
eq(rt.map.geometry_revision,before,'baking must not edit geometry')
local block=rt.map.lightbanks['0,0,0']
assert(block and #block.values>0,'mapblock owns packed banks')
eq(block.values[index(1,0,1)],15,'direct sun day nibble only')
eq(api.get_node_light(first,.5),15,'baked daylight')
eq(api.get_node_light(first,0),2,'moonlight not stored as night bank')
-- A valid baked zero represents darkness, not a missing cache value.
api.set_node(p(5,5,5),{name='bank:stone'})
eq(api.fix_light(first,first),true)
eq(rt.map.lightbanks['0,0,0'].values[index(5,5,5)],nil,
 'dark solid node has an implicit zero bank')
eq(api.get_node_light(p(5,5,5),.5),0)
-- Ensure read-path truly consumes the baked mapblock, rather than
-- recomputing a lighting query and pretending the cache is used.
local original=rt.lighting.raw_banks
rt.lighting.raw_banks=function()
 error('lighting bypassed the baked bank')
end
eq(api.get_node_light(first,.5),15,'baked bank read')
rt.lighting.raw_banks=original
-- Artificial light must update the NIGHT nibble independently of
-- sunlight; dark cave banks do not borrow the night sky ratio.
local lamp=p(6,1,5)
api.set_node(lamp,{name='bank:lamp'})
eq(api.fix_light(first,first),true,'relight after lamp placement')
local lit=rt.map.lightbanks['0,0,0']
local packed=lit.values[index(7,1,5)]
assert(type(packed)=='number' and packed<=255)
eq(packed%16,15,'sunlight bank')
eq(math.floor(packed/16),2,'artificial night bank')
eq(api.get_node_light(p(7,1,5),0),4,
 'night blends sunlight 175/1000 with the independent torch bank')
local revision=lit.map_revision
-- A changed node invalidates previously baked data immediately,
-- even before another explicit relight.
api.remove_node(lamp)
assert(rt.map.geometry_revision~=revision)
eq(api.get_node_light(p(7,1,5),0),2,'stale torch bank ignored')
eq(api.fix_light(first,first),true,'relight after lamp removal')
eq(math.floor((rt.map.lightbanks['0,0,0'].values[index(7,1,5)] or 0)/16),
 0,'artificial bank removed')
-- Updating definitions also invalidates banks without changing geometry.
api.set_node(lamp,{name='bank:lamp'})
eq(api.fix_light(first,first),true)
local unchanged=rt.map.geometry_revision
api.override_item('bank:lamp',{light_source=1})
eq(rt.map.geometry_revision,unchanged)
eq(api.get_node_light(p(7,1,5),0),2,'light definition revision invalidates')
-- Validate every block BEFORE changing any of them; a crossing into
-- ungenerated x/z terrain must fail without replacing previous bank.
local previous=rt.map.lightbanks['0,0,0']
eq(api.fix_light(first,p(16,1,1)),false,'not all blocks generated')
eq(rt.map.lightbanks['0,0,0'],previous,'failed multi-block fix is atomic')
assert(not pcall(api.fix_light,p(1,1,1),p(1,0,1)),
 'reversed corners rejected')
eq(api.fix_light(p(0,32,0),p(0,32,0)),false,
 'outside generated slab cannot be relit')
-- The light cache is runtime-derived, never accidentally persisted to a
-- world format that cannot encode a lightbank without its geometry.
local serialized=Storage.encode(rt.map)
local restored=Storage.decode(serialized)
assert(next(restored.lightbanks or {})==nil)
rt:replaceMap(restored)
eq(api.fix_light(first,first),true,'rebuild banks after loading')
eq(api.get_node_light(first,.5),15)
rt:replaceMap(Map.new())
eq(api.fix_light(first,first),false,'new world is not marked generated')
print('LUA ENGINE NATIVE-STYLE LIGHTBANK REBUILD PASS')
