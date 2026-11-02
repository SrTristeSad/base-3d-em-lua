-- Phase 73: sunlight in actually generated Lua map columns.
-- Unlike an empty sparse world, generated chunks can be tested for open sky.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Storage=require('core.storage')
local Lighting=require('core.lighting')
local Map=require('core.map')
local rt=Runtime.new()
local api=rt.api
local function p(x,y,z) return {x=x,y=y,z=z} end
local function eq(value,expected,label)
 assert(value==expected,(label or 'value')..': got '..tostring(value)..
  ', expected '..tostring(expected))
end
api.register_node('sun:stone',{tiles={'default_stone.png'}})
api.register_node('sun:glass',{drawtype='glasslike',
 paramtype='light',sunlight_propagates=true})
api.register_node('sun:dark_glass',{drawtype='glasslike',paramtype='light',
 sunlight_propagates=false})
-- Non-generated positions must never be mistaken for a sunlit sky.
eq(api.get_natural_light(p(7,6,7),.5),nil,'unloaded sky')
eq(api.get_node_light(p(7,6,7),.5),0,'unloaded legacy light')
-- This flag is persisted by the real Lua Worldgen. Simulate a completed
-- terrain chunk without inventing terrain nodes.
rt.map.generatedChunks['0,0']=42
eq(api.get_natural_light(p(7,6,7),.5),15,'direct sunlight')
eq(api.get_natural_light(p(7,6,7),0),2,'nighttime natural light')
eq(api.get_node_light(p(7,6,7),.5),15,'sunlight in node light')
eq(api.get_node_light(p(7,6,7),0),2,'moonlight in node light')
eq(api.get_natural_light(p(7,32,7),.5),nil,'not generated upper slab')
eq(api.get_natural_light(p(16,6,7),.5),nil,'not generated next chunk')
eq(api.get_natural_light(p(7,-17,7),.5),nil,'not generated lower slab')
local q=p(7,5,7)
local roof=p(7,6,7)
api.set_node(roof,{name='sun:stone'})
eq(rt.lighting:direct_sun(7,5,7),false,'stone roof blocks vertical sky')
eq(api.get_natural_light(q,.5),14,'skylight around roof')
eq(api.get_natural_light(q,0),2,'moonlight around roof')
-- A glasslike node WITHOUT sunlight_propagates must block direct sky.
api.swap_node(roof,{name='sun:dark_glass'})
eq(rt.lighting:direct_sun(7,5,7),false,'glasslike alone not sunlight flag')
api.swap_node(roof,{name='sun:glass'})
eq(rt.lighting:direct_sun(7,5,7),true,'sunlight_propagates allows direct sky')
eq(api.get_natural_light(q,.5),15,'glass lets in sunlight')
-- Surround a cave cell on all six sides: it is no longer lit.
local walls={p(7,6,7),p(7,4,7),p(6,5,7),
 p(8,5,7),p(7,5,6),p(7,5,8)}
for _,v in ipairs(walls) do
 api.swap_node(v,{name='sun:stone'})
end
eq(api.get_natural_light(q,.5),0,'sealed cavern')
eq(api.get_node_light(q,.5),0,'node light in sealed cavern')
-- Edit only the roof, leaving walls: sun enters vertically and instantly
-- invalidates old sky cache (no delayed or imaginary generation).
api.remove_node(roof)
eq(api.get_natural_light(q,.5),15,'sunlight after roof removal')
-- Replacing a skylight-transmitting definition must invalidate both caches.
api.set_node(roof,{name='sun:glass'})
eq(api.get_natural_light(q,.5),15)
api.override_item('sun:glass',{sunlight_propagates=false})
eq(api.get_natural_light(q,.5),0,'definition override invalidation')
api.override_item('sun:glass',{sunlight_propagates=true})
eq(api.get_natural_light(q,.5),15,'definition restore invalidation')
-- Geometry written directly through Map also invalidates cached sunlight.
rt.map:set_node(roof,{name='sun:stone'})
eq(api.get_natural_light(q,.5),0,'raw map node edit')
rt.map:remove_node(roof)
eq(api.get_natural_light(q,.5),15,'raw map deletion')
-- Persistence must preserve the generated-chunk domain and geometry.
local encoded=Storage.encode(rt.map)
local decoded=Storage.decode(encoded)
rt:replaceMap(decoded)
eq(rt.map.generatedChunks['0,0'],42)
eq(api.get_natural_light(q,.5),15,'sun after world load')
rt:replaceMap(Map.new())
eq(api.get_natural_light(q,.5),nil,'world replacement clears sunlight')
eq(api.get_node_light(q,.5),0,'world replacement clears node light')
assert(not pcall(api.get_natural_light,p(1.5,0,0),.5))
assert(not pcall(api.get_natural_light,p(0,0,0),0/0))
assert(not pcall(api.get_node_light,p(0,0,0),0/0))
-- Checking source implementation's clock curve ensures the returned
-- integer day/night blend is tied to Luanti's original ratio.
eq(Lighting.day_ratio(.5),1000)
eq(Lighting.day_ratio(0),175)
print('LUA ENGINE GENERATED SUNLIGHT AND CAVE OCCLUSION PASS')
