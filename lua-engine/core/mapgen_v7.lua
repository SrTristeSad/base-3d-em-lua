-- Partial, source-derived Luanti 5.18 Mapgen V7 terrain implementation.
-- Reference: src/mapgen/mapgen_v7.cpp (LGPL-2.1-or-later).
-- Implements baseTerrainLevelAtPoint, mountain and river predicates, and
-- corresponding raw node placement. Cave, biome, ore, dungeon and decoration
-- passes are NOT implemented. No independent procedural terrain algorithm.
local Noise=require('core.valuenoise')
local CaveNoise=require('core.cave_noise')
local RandomWalk=require('core.caves_randomwalk')
local Chunk=require('core.mapgen_chunk')
local Map=require('core.map')
local V7={}
V7.__index=V7
local floor=math.floor
local max=math.max
local abs=math.abs
local function finite(x)
 return type(x)=='number' and x==x and x~=math.huge and x~=-math.huge
end
local function np(offset,scale,spread,seed,octaves,persist,lacunarity)
 return {offset=offset,scale=scale,
  spread={x=spread.x,y=spread.y,z=spread.z},
  seed=seed,octaves=octaves,persist=persist,lacunarity=lacunarity or 2}
end
-- Identical numeric defaults to MapgenV7Params::MapgenV7Params() in 5.18.
local defaults={
 terrain_base=np(4,70,{x=600,y=600,z=600},82341,5,.6),
 terrain_alt=np(4,25,{x=600,y=600,z=600},5934,5,.6),
 terrain_persist=np(.6,.1,{x=2000,y=2000,z=2000},539,3,.6),
 height_select=np(-8,16,{x=500,y=500,z=500},4213,6,.7),
 filler_depth=np(0,1.2,{x=150,y=150,z=150},261,3,.7),
 mount_height=np(256,112,{x=1000,y=1000,z=1000},72449,3,.6),
 ridge_uwater=np(0,1,{x=1000,y=1000,z=1000},85039,5,.6),
 mountain=np(-.6,1,{x=250,y=350,z=250},5333,5,.63),
 ridge=np(0,1,{x=100,y=100,z=100},6467,4,.75),
 floatland=np(0,.7,{x=384,y=96,z=384},1009,4,.75,1.618),
 cave1=np(0,12,{x=61,y=61,z=61},52534,3,.5),
 cave2=np(0,12,{x=67,y=67,z=67},10325,3,.5),
 cavern=np(0,1,{x=384,y=128,z=384},723,5,.63),
 dungeons=np(.9,.5,{x=500,y=500,z=500},0,2,.8)
}
local function deep_copy(p)
 return {offset=p.offset,scale=p.scale,
  spread={x=p.spread.x,y=p.spread.y,z=p.spread.z},
  seed=p.seed,octaves=p.octaves,persist=p.persist,
  lacunarity=p.lacunarity}
end
local known={mountains=true,ridges=true,caverns=true,floatlands=true}
local function flags(v)
 if v==nil then v='mountains,ridges,caverns' end
 assert(type(v)=='string','mgv7 flags must be a string')
 local out={}
 for token in v:gmatch('[^,%s]+') do
  local enabled=true
  if token:sub(1,2)=='no' then
   enabled=false;token=token:sub(3)
  end
  assert(known[token],'unsupported Mapgen V7 flag: '..token)
  out[token]=enabled
 end
 -- A partial port must not silently emulate floatlands using another shape.
 assert(not out.floatlands,'Mapgen V7 floatlands not yet implemented')
 return out
end
local function validated_name(rt,name,kind)
 assert(type(name)=='string' and name~='' and
  rt.registry.nodes[name],
  'Mapgen V7 '..kind..' requires a registered node name')
 return name
end
function V7.new(runtime,config)
 assert(runtime and runtime.registry and runtime.map,
  'Mapgen V7 needs a Lua engine runtime')
 config=config or {}
 assert(type(config)=='table','Mapgen V7 options required')
 local world=runtime.opts.mapgen or {}
 local seed=tonumber(config.seed or world.seed or runtime.opts.seed or 0)
 assert(finite(seed) and seed==floor(seed) and abs(seed)<=2147483647,
  'invalid mapgen V7 seed in Lua engine')
 local water=tonumber(config.water_level or world.water_level or 1)
 assert(finite(water) and water==floor(water) and abs(water)<=31000,
  'invalid mapgen V7 water level')
 local zero=config.mount_zero_level or 0
 assert(finite(zero) and zero==floor(zero) and abs(zero)<=31000,
  'invalid Mapgen V7 mount zero level')
 local names={
  stone=validated_name(runtime,config.stone,'stone'),
  water=validated_name(runtime,config.water,'water')}
 assert(names.stone~='air' and names.stone~='ignore' and
  names.water~='air' and names.water~='ignore',
  'Mapgen V7 material names must be nonempty terrain nodes')
 local self=setmetatable({
  runtime=runtime,worldseed=seed,water_level=water,mount_zero_level=zero,
  names=names,flags=flags(config.spflags or world.mgv7_spflags),
  noise={},noise_caves=config.noise_caves==true,
  randomwalk_caves=config.randomwalk_caves==true,
  randomwalk_settings={
   large_cave_depth=config.large_cave_depth,
   small_cave_num_min=config.small_cave_num_min,
   small_cave_num_max=config.small_cave_num_max,
   large_cave_num_min=config.large_cave_num_min,
   large_cave_num_max=config.large_cave_num_max
  },
  lava=config.lava,generated=0},V7)
 for id,p in pairs(defaults) do
  local custom=config.noise and config.noise[id]
  -- Lua noise implementation already validates octaves, spreads and flags.
  self.noise[id]=Noise.world_scalar(seed,custom or deep_copy(p))
 end
 if self.noise_caves then
  local caveparams={}
  for _,id in ipairs({'cave1','cave2','cavern'}) do
   caveparams[id]=config.noise and config.noise[id] or deep_copy(defaults[id])
  end
  self.caveNoise=CaveNoise.new(seed,{
   noise=caveparams,cave_width=config.cave_width,
   cavern_limit=config.cavern_limit,cavern_taper=config.cavern_taper,
   cavern_threshold=config.cavern_threshold
  })
 end
 return self
end
function V7:baseTerrainLevelAtPoint(x,z)
 local n=self.noise
 -- Upstream applies persistence noise to base+alt octave gains separately
 -- at every x/z, THEN clamps the height selector, not persistence.
 local selector=n.height_select:get_2d({x=x,y=z})
 selector=math.min(1,max(0,selector))
 local persist=n.terrain_persist:get_2d({x=x,y=z})
 n.terrain_base.params.persist=persist
 n.terrain_alt.params.persist=persist
 local base=n.terrain_base:get_2d({x=x,y=z})
 local alt=n.terrain_alt:get_2d({x=x,y=z})
 if alt>base then return alt end
 return base*selector+alt*(1-selector)
end
function V7:getMountainTerrainAtPoint(x,y,z)
 if self.flags.mountains==false then return false end
 local height=max(self.noise.mount_height:get_2d({x=x,y=z}),1)
 local gradient=-(y-self.mount_zero_level)/height
 local density=self.noise.mountain:get_3d({x=x,y=y,z=z})
 return density+gradient>=0
end
function V7:getRiverChannelAtPoint(x,y,z)
 if self.flags.ridges==false then return false end
 -- getRiverChannelFromMap() from upstream mapgen_v7.cpp, no waterway
 -- shortcuts or different river noise functions.
 local width=.2
 local abswater=abs(self.noise.ridge_uwater:get_2d({x=x,y=z}))*2
 if abswater>width then return false end
 local altitude=y-self.water_level
 local height_mod=(altitude+17)/2.5
 local width_mod=width-abswater
 local ridge=self.noise.ridge:get_3d({x=x,y=y,z=z})*
  max(altitude,0)/7
 return ridge+width_mod*height_mod>=.6
end
function V7:materialAt(x,y,z,base_height)
 local h=base_height or self:baseTerrainLevelAtPoint(x,z)
 -- Upstream generates rivers for a whole mapchunk if its maximum Y
 -- reaches water_level - 16, rather than checking each node's Y.
 local block_max_y=floor(y/16)*16+15
 local river=block_max_y>=self.water_level-16 and
  self:getRiverChannelAtPoint(x,y,z) or false
 if y<=h and not river then return self.names.stone end
 if self:getMountainTerrainAtPoint(x,y,z) and not river then
  return self.names.stone
 end
 if y<=self.water_level then return self.names.water end
 return 'air'
end
function V7:generateBlock(minp,maxp)
 assert(type(minp)=='table' and type(maxp)=='table',
  'Mapgen V7 bounds required')
 for _,axis in ipairs({'x','y','z'}) do
  assert(finite(minp[axis]) and finite(maxp[axis]) and
   minp[axis]==floor(minp[axis]) and
   minp[axis]%16==0 and maxp[axis]==minp[axis]+15 and
   abs(minp[axis])<=31000 and abs(maxp[axis])<=31000,
   'Mapgen V7 only accepts aligned 16x16x16 mapblocks')
 end
 local map=self.runtime.map
 local id=map:blockkey(minp)
 -- Emitted mapblocks cannot overwrite resident edits or prior generation.
 if map.revisions[id] or map.last_active[id] or map.lbm_applied[id] then
  return false
 end
 return self:_generateRegion(map,minp,maxp,{
  x=minp.x-16,y=minp.y-16,z=minp.z-16})
end
-- All terrain and caves are computed across ONE core region. This makes
-- CavesRandomWalk share its RNG stream and uninterrupted route across
-- neighboring mapblocks of the same chunk.
function V7:_generateRegion(map,minp,maxp,full_node_min)
 local stone_surface_max_y=-31000
 for z=minp.z,maxp.z do for x=minp.x,maxp.x do
  local level=self:baseTerrainLevelAtPoint(x,z)
  -- Original MapgenV7::generateTerrain assigns this float to s16.
  local surface=level<0 and math.ceil(level) or floor(level)
  if surface>stone_surface_max_y then stone_surface_max_y=surface end
  for y=minp.y,maxp.y do
   local name=self:materialAt(x,y,z,level)
   if name~='air' then map:set_node({x=x,y=y,z=z},{name=name}) end
  end
 end end
 local heightmap
 if self.randomwalk_caves then
  -- Original MapgenV7: updateHeightmap happens after raw terrain, BEFORE
  -- any cave stage. A column without stone receives -31000.
  heightmap={}
  for z=minp.z,maxp.z do for x=minp.x,maxp.x do
   local h=-31000
   for y=maxp.y,minp.y,-1 do
    if map:get_node({x=x,y=y,z=z}).name==self.names.stone then
     h=y;break
    end
   end
   heightmap[#heightmap+1]=h
  end end
 end
 if self.caveNoise then
  self.lastCaveMetrics=self.caveNoise:carve(map,minp,maxp,self.names.stone,{
   max_stone_y=stone_surface_max_y,
   caverns=self.flags.caverns==true
  })
 end
 if self.randomwalk_caves then
  local walk=RandomWalk.new({
   map=map,node_min=minp,node_max=maxp,
   heightmap=heightmap,seed=self.worldseed,
   water_level=self.water_level,stone=self.names.stone,
   water=self.names.water,lava=self.lava,
   max_stone_height=stone_surface_max_y
  })
  local seed=RandomWalk.getBlockSeed2(full_node_min or {
   x=minp.x-16,y=minp.y-16,z=minp.z-16},self.worldseed)
  local rw=self.randomwalk_settings
  local large_ymax=rw.large_cave_depth or -33
  if self.lastCaveMetrics and self.lastCaveMetrics.near_cavern then
   large_ymax=-31000 -- MapgenV7 suppresses near-cavern randomwalk caves.
  end
  self.lastRandomWalkMetrics=walk:generate(seed,{
   small_cave_num_min=rw.small_cave_num_min,
   small_cave_num_max=rw.small_cave_num_max,
   large_cave_num_min=rw.large_cave_num_min,
   large_cave_num_max=rw.large_cave_num_max,
   large_cave_depth=large_ymax
  })
  self.lastRandomWalkEvents=walk.events
 end
 self.generated=self.generated+1
 return true
end
-- Opt-in multi-mapblock generation. Work is staged in a separate sparse Map
-- and copied only after all noise/cave stages succeed. A partially existing
-- or disk-backed chunk falls back to the original single-block generator.
-- This prevents rewriting user edits and persisted blocks.
function V7:generateChunk(minp,maxp,chunk_size)
 local geom=Chunk.geometry({
  x=floor(minp.x/16),y=floor(minp.y/16),z=floor(minp.z/16)
 },chunk_size)
 assert(minp.x>=geom.node_min.x and minp.x<=geom.node_max.x and
  minp.y>=geom.node_min.y and minp.y<=geom.node_max.y and
  minp.z>=geom.node_min.z and minp.z<=geom.node_max.z,
  'mapblock not contained in requested chunk')
 local map=self.runtime.map
 local store=self.runtime.mapBlockStore
 local blocks=Chunk.each_block(geom)
 local has_existing=false
 for _,b in ipairs(blocks) do
  if store and not store:resident(b.key) then
   -- Do not mistake a disk-resident neighbor for an ungenerated block.
   store:emerge(b.key)
  end
  if (store and store:resident(b.key)) or map.revisions[b.key]
   or map.last_active[b.key] or map.lbm_applied[b.key] then
   has_existing=true
  end
 end
 if has_existing then
  return self:generateBlock(minp,maxp)
 end
 local stage=Map.new(self.runtime.registry.items)
 self:_generateRegion(stage,geom.node_min,geom.node_max,
  geom.full_node_min)
 -- Copy the fully computed interior only. No nodes are written to the
 -- expanded border: that space is reserved for the later MMVManip port.
 for k,node in pairs(stage.nodes) do
  local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  map:set_node({x=tonumber(x),y=tonumber(y),z=tonumber(z)},node)
 end
 self.lastChunkGeometry=geom
 self.generatedMapBlocks=(self.generatedMapBlocks or 0)+#blocks
 return true,{minp=geom.node_min,maxp=geom.node_max,
  blockseed=RandomWalk.getBlockSeed2(geom.full_node_min,self.worldseed)}
end
V7.defaults=defaults
return V7
