-- Phase 72: Luanti day/night light banks and light emitted across voxels.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Map=require('core.map')
local Lighting=require('core.lighting')
local rt=Runtime.new()
local api=rt.api
local function eq(a,b,label)
 assert(a==b,(label or 'value')..': got '..tostring(a)..', expected '..tostring(b))
end
local function p(x,y,z)return {x=x,y=y,z=z}end
eq(api.LIGHT_MAX,14)
eq(api.LIGHT_SUN,15)
eq(api.get_artificial_light(0),0)
eq(api.get_artificial_light(0x20),2)
eq(api.get_artificial_light(0xff),15)
assert(not pcall(api.get_artificial_light,256))
assert(not pcall(api.get_artificial_light,1.4))
eq(Lighting.day_ratio(0),175)
eq(Lighting.day_ratio(.5),1000)
eq(Lighting.day_ratio(.25),937.5)
eq(Lighting.day_ratio(.75),937.5)
eq(Lighting.day_ratio(1),175)
-- Preserve original param1 day and night light nibbles when present.
api.register_node('light:sample',{paramtype='light'})
api.set_node(p(20,0,0),{name='light:sample',param1=0x92})
eq(api.get_node_light(p(20,0,0),.5),2,'day bank')
eq(api.get_node_light(p(20,0,0),0),7,'day/night blend')
api.set_node(p(21,0,0),{name='light:sample',param1=0x0f})
eq(api.get_node_light(p(21,0,0),.5),15,'sunlight bank')
eq(api.get_node_light(p(21,0,0),0),2,'moonlight blend')
-- The Lua engine must not claim that empty sparse terrain has baked sky
-- lighting until the original Luanti mapgen/light updater has been ported.
eq(api.get_node_light(p(100,1,1),.5),0,'unlit sparse map')
-- A torch lights direct neighbors through air with 1 level lost per
-- face-crossing; sources and emitted values are independent of timeofday.
api.register_node('light:torch',{paramtype='light',light_source=14,
 drawtype='torchlike',walkable=false})
api.register_node('light:stone',{})
api.register_node('light:glass',{drawtype='glasslike',paramtype='light'})
local origin=p(0,0,0)
api.set_node(origin,{name='light:torch'})
eq(api.get_node_light(origin,0),14,'light source')
eq(api.get_node_light(p(1,0,0),.5),13,'adjacent air')
eq(api.get_node_light(p(2,0,0),0),12,'propagation through air')
eq(api.get_node_light(p(13,0,0),.5),1,'maximum visible reach')
eq(api.get_node_light(p(14,0,0),.5),0,'attenuation stops at zero')
api.set_node(p(1,0,0),{name='light:glass'})
eq(api.get_node_light(p(2,0,0),.5),12,'glass transmits light')
-- Seal the torch in all six directions; no light can reach the probe.
local seals={
 p(1,0,0),p(-1,0,0),p(0,1,0),
 p(0,-1,0),p(0,0,1),p(0,0,-1)}
for _,pos in ipairs(seals) do
 api.set_node(pos,{name='light:stone'})
end
eq(api.get_node_light(p(2,0,0),.5),0,'opaque barrier')
-- Test invalidation after a direct map edit, rather than only API calls.
rt.map:remove_node(p(1,0,0))
eq(api.get_node_light(p(2,0,0),.5),12,'map revisions invalidate light cache')
-- Mutating a registered node's luminosity must invalidate computed light.
api.override_item('light:torch',{light_source=3})
eq(api.get_node_light(origin,.5),3,'override source')
eq(api.get_node_light(p(2,0,0),.5),1,'override propagated')
api.remove_node(origin)
eq(api.get_node_light(p(1,0,0),.5),0,'removed light source')
-- Replacing a loaded world must never retain old world's illumination.
api.set_node(p(0,0,0),{name='light:torch'})
eq(api.get_node_light(p(1,0,0),.5),2)
rt:replaceMap(Map.new())
eq(api.get_node_light(p(1,0,0),.5),0,'new map cleared light source')
assert(not pcall(api.get_node_light,p(1.5,2,3)))
assert(not pcall(api.get_node_light,p(0,0,0),0/0))
print('LUA ENGINE LUANTI LIGHT BANKS, TORCH FALLOFF AND CACHE INVALIDATION PASS')
