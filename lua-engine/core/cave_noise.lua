-- Luanti 5.18 cave noise predicates and stone-only excavation.
-- Reference: src/mapgen/cavegen.cpp (CavesNoiseIntersection, CavernsNoise)
-- and src/mapgen/mapgen.cpp (MapgenBasic::generateCaves*).
-- SPDX-License-Identifier: LGPL-2.1-or-later
--
-- This is the mathematically faithful NOISE carve stage on the currently
-- generated mapblock. The native chunk-sized VoxelManip + biome transitions,
-- 1-down overgeneration, cave entrance floors/roofs and CavesRandomWalk
-- remain separate, unported stages: do not label this full cave generation.
local Noise=require('core.valuenoise')
local Cave={}
Cave.__index=Cave
local floor=math.floor
local abs=math.abs
local min=math.min
local function finite(n)
 return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge
end
local function contour(v)
 -- cavegen.cpp::contour: abs(v) >= 1 gives no contribution.
 local a=abs(v)
 if a>=1 then return 0 end
 return 1-a
end
function Cave.new(seed,params)
 assert(type(params)=='table','cave noise parameters required')
 local width=params.cave_width==nil and .09 or params.cave_width
 local limit=params.cavern_limit==nil and -256 or params.cavern_limit
 local taper=params.cavern_taper==nil and 256 or params.cavern_taper
 local threshold=params.cavern_threshold==nil and .7 or params.cavern_threshold
 assert(finite(width) and width>=0,'invalid cave width')
 assert(finite(limit) and finite(taper) and taper>0 and
  finite(threshold),'invalid cavern parameters')
 local n=params.noise
 assert(type(n)=='table' and n.cave1 and n.cave2 and n.cavern,
  'cave1, cave2 and cavern NoiseParams required')
 return setmetatable({
  cave1=Noise.world_scalar(seed,n.cave1),
  cave2=Noise.world_scalar(seed,n.cave2),
  cavern=Noise.world_scalar(seed,n.cavern),
  cave_width=width,cavern_limit=limit,
  cavern_taper=taper,cavern_threshold=threshold
 },Cave)
end
function Cave:tunnelAt(x,y,z)
 if self.cave_width>=10 then return false end
 local p={x=x,y=y,z=z}
 local d1=contour(self.cave1:get_3d(p))
 local d2=contour(self.cave2:get_3d(p))
 return d1*d2>self.cave_width
end
function Cave:cavernAt(x,y,z)
 -- Cavegen::CavernsNoise uses 1-down overgeneration, descending y;
 -- the same position-specific amplitude is sampled here.
 local amp=min((self.cavern_limit-y)/self.cavern_taper,1)
 local strength=abs(self.cavern:get_3d({x=x,y=y,z=z}))*amp
 local near=strength>self.cavern_threshold-.1
 local carve=strength>self.cavern_threshold
 return carve,near,strength
end
function Cave:carve(map,minp,maxp,ground_name,options)
 assert(map and type(map.get_node)=='function' and
  type(map.remove_node)=='function','cave stage requires Map')
 assert(type(minp)=='table' and type(maxp)=='table',
  'cave stage bounds required')
 assert(type(ground_name)=='string' and ground_name~='',
  'cave stage needs a ground node')
 options=options or {}
 local max_stone_y=options.max_stone_y or maxp.y
 local tunnels_enabled=max_stone_y>=minp.y and self.cave_width<10
 local caverns_enabled=options.caverns and max_stone_y>=minp.y and
  minp.y<=self.cavern_limit
 local metrics={tunnels=0,caverns=0,near_cavern=false}
 if not tunnels_enabled and not caverns_enabled then return metrics end
 -- Native MapgenV7 order: noise-intersection tunnels, then caverns.
 -- CavesNoiseIntersection also depends on biomemap for surface replacement;
 -- since this port does not yet generate biomes, carve ONLY the raw ground
 -- node, never liquids or user-modified/foreign materials.
 for z=minp.z,maxp.z do for x=minp.x,maxp.x do
  for y=maxp.y,minp.y,-1 do
   local pos={x=x,y=y,z=z}
   if map:get_node(pos).name==ground_name and tunnels_enabled and
      self:tunnelAt(x,y,z) then
    map:remove_node(pos)
    metrics.tunnels=metrics.tunnels+1
   end
  end
 end end
 if caverns_enabled then
  for z=minp.z,maxp.z do for x=minp.x,maxp.x do
   for y=maxp.y,minp.y,-1 do
    local excavate,near=self:cavernAt(x,y,z)
    if near then metrics.near_cavern=true end
    if excavate then
     local pos={x=x,y=y,z=z}
     if map:get_node(pos).name==ground_name then
      map:remove_node(pos)
      metrics.caverns=metrics.caverns+1
     end
    end
   end
  end end
 end
 return metrics
end
Cave.contour=contour
return Cave
