-- Luanti 5.18 cavegen.cpp noise intersection/cavern depth regressions.
-- This verifies the explicitly scoped raw-stone cave stage, not the full
-- biome-aware native chunk generator or CavesRandomWalk.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Map=require('core.map')
local V7=require('core.mapgen_v7')
local Cave=require('core.cave_noise')
local function constant(offset)
 return {offset=offset,scale=0,spread={x=16,y=16,z=16},
  seed=11,octaves=1,persist=.5,lacunarity=2}
end
local noise={
 cave1=constant(0),cave2=constant(0),cavern=constant(1)}
local cave=Cave.new(42,{noise=noise})
assert(Cave.contour(0)==1 and Cave.contour(.8)>.199 and
 Cave.contour(1)==0 and Cave.contour(-2)==0)
assert(cave:tunnelAt(1,-10,4))
assert(cave:tunnelAt(-123,10,99))
local carve,near,strength=cave:cavernAt(2,-256,5)
assert(not carve and not near and strength==0)
carve,near,strength=cave:cavernAt(2,-512,5)
assert(carve and near and strength==1)
carve,near,strength=cave:cavernAt(2,-448,5)
assert(not carve and near and math.abs(strength-.75)<1e-8,
 'check corrected near-cavern range in setup')
