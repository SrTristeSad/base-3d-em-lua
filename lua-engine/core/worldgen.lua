-- Deterministic chunk generator for the independent Lua voxel demo.
-- NOT the Minecraft or VoxeLibre terrain algorithm.
-- Worldgen uses fixed 16x16 x/z chunks and a bounded y=-16..31 layer.
local Worldgen={}
Worldgen.__index=Worldgen
local floor=math.floor
local PRIME=2147483647
local function hash(seed,x,y,z)
 local n=(seed + x*374761 + y*668265 + z*1274129)%PRIME
 n=(n*1664525+1013904223)%PRIME
 n=(n*1664525+1013904223)%PRIME
 return n/PRIME
end
local function smooth(t) return t*t*(3-2*t) end
local function mix(a,b,t) return a+(b-a)*t end
local function noise2(seed,x,z)
 local ix,iz=floor(x),floor(z)
 local fx,fz=smooth(x-ix),smooth(z-iz)
 local a=mix(hash(seed,ix,0,iz),hash(seed,ix+1,0,iz),fx)
 local b=mix(hash(seed,ix,0,iz+1),hash(seed,ix+1,0,iz+1),fx)
 return mix(a,b,fz)*2-1
end
local function noise3(seed,x,y,z)
 local ix,iy,iz=floor(x),floor(y),floor(z)
 local fx,fy,fz=smooth(x-ix),smooth(y-iy),smooth(z-iz)
 local function side(h)
  local a=mix(hash(seed,ix,iy,iz+h),hash(seed,ix+1,iy,iz+h),fx)
  local b=mix(hash(seed,ix,iy+1,iz+h),hash(seed,ix+1,iy+1,iz+h),fx)
  return mix(a,b,fy)
 end
 return mix(side(0),side(1),fz)
end
local defaults={
 grass='lua:grass',dirt='lua:dirt',stone='lua:stone',
 sand='lua:sand',water='lua:water',wood='lua:wood',
 leaves='lua:leaves',ore='lua:coal_ore'
}
local function valid_integer(n,lo,hi)
 return type(n)=='number' and n==floor(n) and n>=lo and n<=hi
end
local function biome(self,x,z)
 local moisture=noise2(self.seed+523,x/64,z/64)
 if moisture<-.24 then return 'desert' end
 if moisture>.19 then return 'forest' end
 return 'plains'
end
local function height(self,x,z)
 return floor(6+noise2(self.seed+41,x/38,z/38)*7+
  noise2(self.seed+83,x/13,z/13)*2)
end
local function treelocation(self,x,z)
 if biome(self,x,z)~='forest' or height(self,x,z)<=3 then return false end
 return hash(self.seed+991,x,7,z)>.985
end
local function node(self,x,y,z,h,b)
 if y>h then
  if y<=3 then return self.nodes.water end
  return 'air'
 end
 if y==h then
  return b=='desert' and self.nodes.sand or self.nodes.grass
 end
 if y>=h-3 then
  return b=='desert' and self.nodes.sand or self.nodes.dirt
 end
 if y>-14 and y<h-4 and
  noise3(self.seed+311,x/12,y/10,z/12)>.79 then
  return 'air'
 end
 if y<1 and hash(self.seed+773,x,y,z)>.979 then
  return self.nodes.ore
 end
 return self.nodes.stone
end
function Worldgen.new(runtime,opts)
 assert(runtime and runtime.api and runtime.map,
  'Worldgen requires a runtime')
 opts=opts or {}
 local seed=opts.seed or 42
 assert(valid_integer(seed,0,2147483646),'invalid world seed')
 local names={}
 for key,value in pairs(defaults) do
  names[key]=opts.nodes and opts.nodes[key] or value
  assert(type(names[key])=='string','invalid terrain node')
  assert(runtime.api.registered_nodes[names[key]],
   'node not registered for worldgen: '..names[key])
 end
 runtime.map.generatedChunks=runtime.map.generatedChunks or {}
 return setmetatable({runtime=runtime,seed=seed,nodes=names},Worldgen)
end
function Worldgen:biome(x,z)
 assert(valid_integer(x,-31000,31000) and valid_integer(z,-31000,31000))
 return biome(self,x,z)
end
function Worldgen:height(x,z)
 assert(valid_integer(x,-31000,31000) and valid_integer(z,-31000,31000))
 return height(self,x,z)
end
function Worldgen:generate(cx,cz)
 assert(valid_integer(cx,-1936,1936) and
  valid_integer(cz,-1936,1936),'chunk outside supported map')
 local id=cx..','..cz
 local generated=self.runtime.map.generatedChunks
 if generated[id]~=nil then
  assert(generated[id]==self.seed,
   'world seed changed for an already-generated chunk')
  return false,0
 end
 local minx,minz=cx*16,cz*16
 local lo={x=minx,y=-16,z=minz}
 local hi={x=minx+15,y=31,z=minz+15}
 local manip=self.runtime.api.get_voxel_manip(lo,hi)
 -- Edit only requested chunk, and leave preexisting player-placed nodes.
 -- A previously deleted block remains deleted because chunk generation
 -- flags are stored in the world save format.
 for x=minx,minx+15 do for z=minz,minz+15 do
  local h,b=height(self,x,z),biome(self,x,z)
  for y=-16,31 do
   local p={x=x,y=y,z=z}
   if manip:get_node_at(p).name=='air' then
    local n=node(self,x,y,z,h,b)
    if n~='air' then manip:set_node_at(p,{name=n}) end
   end
  end
 end end
 -- Deterministically reconstruct trees whose trunks are also outside
 -- this chunk; identical output regardless of neighboring chunk order.
 for tx=minx-2,minx+17 do for tz=minz-2,minz+17 do
  if treelocation(self,tx,tz) then
   local base=height(self,tx,tz)
   for dx=-2,2 do for dz=-2,2 do
    local x,z=tx+dx,tz+dz
    if x>=minx and x<=minx+15 and z>=minz and z<=minz+15 then
     for y=base+2,base+5 do
      local thin=(y==base+5)
      if (not thin or (math.abs(dx)<=1 and math.abs(dz)<=1))
        and (math.abs(dx)+math.abs(dz)<=3) and y<=31 then
       local p={x=x,y=y,z=z}
       if manip:get_node_at(p).name=='air' then
        manip:set_node_at(p,{name=self.nodes.leaves})
       end
      end
     end
    end
   end end
   if tx>=minx and tx<=minx+15 and tz>=minz and tz<=minz+15 then
    for y=base+1,math.min(31,base+4) do
     local p={x=tx,y=y,z=tz}
     if manip:get_node_at(p).name=='air' or
      manip:get_node_at(p).name==self.nodes.leaves then
      manip:set_node_at(p,{name=self.nodes.wood})
     end
    end
   end
  end
 end end
 local writes=manip:write_to_map()
 generated[id]=self.seed
 self.runtime:generate(lo,hi,self.seed)
 return true,writes
end
return Worldgen
