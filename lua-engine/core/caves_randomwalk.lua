-- Luanti 5.18 CavesRandomWalk path/carving stage port to Lua.
-- Source: src/mapgen/cavegen.cpp 273-607 and src/mapgen/mapgen.cpp
-- getBlockSeed2/generateCavesRandomWalk (LGPL-2.1-or-later).
-- The original chunk-sized VoxelManip, cave flags, biome cave liquids and
-- cross-chunk overgeneration are not yet available; see docs.
local PseudoRandom=require('core.pseudorandom')
local Bit=require('core.bitops')
local Noise=require('core.valuenoise')
local Walk={}
Walk.__index=Walk
local U=4294967296
local floor=math.floor
local abs=math.abs
local max=math.max
local min=math.min
local sqrt=math.sqrt
local function trunc(n)
 return n<0 and math.ceil(n) or floor(n)
end
local function signed(n)
 n=n%U
 return n>=2147483648 and n-U or n
end
local function mul32(a,b)
 a=a%U;b=b%U
 local al,ah=a%65536,floor(a/65536)
 local bl,bh=b%65536,floor(b/65536)
 local low=al*bl
 local high=(floor(low/65536)+ah*bl+al*bh)%65536
 return (low%65536+high*65536)%U
end
-- Mapgen::getBlockSeed2 uses u32 intermediate arithmetic throughout,
-- NOT noise2d's truncated 31-bit result.
function Walk.getBlockSeed2(p,seed)
 local n=(1619*p.x+31337*p.y+52591*p.z+1013*seed)%U
 n=Bit.bxor(n,Bit.rshift(n,13))%U
 local n2=mul32(n,n)
 return (mul32(n,(mul32(n2,60493)+19990303)%U)+1376312589)%U
end
local function vector(x,y,z) return {x=x,y=y,z=z} end
local function vadd(a,b)
 return vector(a.x+b.x,a.y+b.y,a.z+b.z)
end
local function vsub(a,b)
 return vector(a.x-b.x,a.y-b.y,a.z-b.z)
end
local function vmul(a,s)
 return vector(a.x*s,a.y*s,a.z*s)
end
local function vint(a)
 return vector(trunc(a.x),trunc(a.y),trunc(a.z))
end
local function clamp(v,a,b)
 return min(max(v,a),b)
end
local function inside(p,a,b)
 return p.x>=a.x and p.x<=b.x and p.y>=a.y and
  p.y<=b.y and p.z>=a.z and p.z<=b.z
end
local function finite(v)
 return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge
end
local function range(ps,a,b)
 return ps:next(a,b)
end
function Walk.new(config)
 assert(type(config)=='table','randomwalk cave settings required')
 local nmin,nmax=config.node_min,config.node_max
 assert(type(nmin)=='table' and type(nmax)=='table',
  'randomwalk cave chunk bounds required')
 for _,a in ipairs({'x','y','z'}) do
  assert(finite(nmin[a]) and finite(nmax[a]) and
   nmin[a]==floor(nmin[a]) and nmax[a]==floor(nmax[a]) and
   nmax[a]>=nmin[a] and nmax[a]-nmin[a]<=255,
   'invalid randomwalk cave chunk axis')
 end
 local water=config.water_level or 1
 local seed=config.seed or 0
 local large_flood=config.large_cave_flooded or .5
 assert(finite(water) and finite(seed) and finite(large_flood) and
  large_flood>=0 and large_flood<=1,'invalid cave parameters')
 assert(type(config.stone)=='string' and config.stone~='',
  'randomwalk ground material required')
 local self=setmetatable({
  node_min=nmin,node_max=nmax,
  stone=config.stone,water=config.water or 'air',
  lava=config.lava or config.water or 'air',
  seed=seed,water_level=water,large_cave_flooded=large_flood,
  max_stone_height=config.max_stone_height or nmax.y,
  heightmap=config.heightmap,large=false,
  map=config.map,events={},metrics={caves=0,carved=0,sections=0},
  cave_liquid_noise=Noise.world_scalar(seed,{
   offset=0,scale=1,spread={x=150,y=150,z=150},
   seed=776,octaves=3,persist=.6,lacunarity=2
  })
 },Walk)
 assert(type(self.map)=='table' and type(self.map.get_node)=='function' and
  type(self.map.remove_node)=='function','randomwalk map required')
 return self
end
function Walk:_height(x,z)
 if x>=self.node_min.x and x<=self.node_max.x and
    z>=self.node_min.z and z<=self.node_max.z and self.heightmap then
  local v=self.heightmap[(z-self.node_min.z)*
   (self.node_max.x-self.node_min.x+1)+(x-self.node_min.x)+1]
  if v~=nil then return v end
 end
 return nil
end
function Walk:isPosAboveSurface(p)
 local h=self:_height(p.x,p.z)
 return (h~=nil and h<p.y) or (h==nil and p.y>self.water_level)
end
function Walk:_carveRoute(vec,f,randomize_xz)
 local ps=self.ps
 local start=vadd(vint(self.orp),self.of)
 local fp=vadd(self.orp,vmul(vec,f))
 fp.x=fp.x+.1*range(ps,-10,10)
 fp.z=fp.z+.1*range(ps,-10,10)
 local cp=vint(fp)
 local liquid=nil
 if self.flooded then
  -- Native consults biome cave liquids first. This stage uses only
  -- fallback cave-liquid noise until biomegen is available.
  local n=self.cave_liquid_noise:get_3d(start)
  liquid=(n<.40 and self.node_max.y<self.water_level-256)
   and self.lava or self.water
 end
 local rs=self.rs
 local d0=-trunc(rs/2)
 local d1=d0+rs
 if randomize_xz then
  d0=d0+range(ps,-1,1)
  d1=d1+range(ps,-1,1)
 end
 local flat_floor=not self.large and range(ps,0,2)==2
 for z0=d0,d1 do
  local si=trunc(rs/2)-max(0,abs(z0)-trunc(rs/7)-1)
  local x0=-si-range(ps,0,1)
  -- The C++ for-loop recomputes its RNG-dependent upper bound in
  -- EVERY condition check, including the final failing check.
  while true do
   local xmax=si-1+range(ps,0,1)
   if x0>xmax then break end
   local maxabsxz=max(abs(x0),abs(z0))
   local si2=trunc(rs/2)-max(0,maxabsxz-trunc(rs/7)-1)
   for y0=-si2,si2 do
    local skip=flat_floor and y0<=-trunc(rs/2) and rs<=7
    if not skip and self.large_cave_is_flat and
       rs>7 and abs(y0)>=rs/3 then skip=true end
    if not skip then
     local pos=vector(cp.x+x0+self.of.x,cp.y+y0+self.of.y,
      cp.z+z0+self.of.z)
     -- Native works inside a larger MMVManip area, but this partial
     -- mapblock port must not mutate ungenerated neighboring blocks.
     if inside(pos,self.node_min,self.node_max) and
        self.map:get_node(pos).name==self.stone then
      local material='air'
      if self.large and self.flooded then
       local full_ymin=self.node_min.y-16
       local full_ymax=self.node_max.y+16
       if full_ymin<self.water_level and full_ymax>self.water_level then
        if pos.y<=self.water_level then material=self.water end
       elseif full_ymax<self.water_level and pos.y<start.y-4 then
        material=liquid
       end
      end
      self.map:set_node(pos,{name=material})
      self.metrics.carved=self.metrics.carved+1
     end
    end
   end
   x0=x0+1
  end
 end
end
function Walk:_makeTunnel(dirswitch)
 local ps=self.ps
 if dirswitch and not self.large then
  local dz=(ps:next()%20-10)/10
  local dy=(ps:next()%20-10)/30
  local dx=(ps:next()%20-10)/10
  local factor=range(ps,0,10)/10
  self.main_direction=vector(dx*factor,dy*factor,dz*factor)
 end
 local rs=range(ps,self.min_d,self.max_d)
 self.rs=rs
 local maxlength=rs*self.part_max_length_rs
 local maxlen=vector(maxlength,self.large and trunc(maxlength/2) or
  range(ps,1,maxlength),maxlength)
 local jump=not self.large and range(ps,0,12)==0
 local z=(ps:next()%maxlen.z)-maxlen.z/2
 local y
 if jump then y=(ps:next()%(maxlen.y*2))-maxlen.y
 else y=(ps:next()%maxlen.y)-maxlen.y/2 end
 local x=(ps:next()%maxlen.x)-maxlen.x/2
 local vec=vector(x,y,z)
 local p1=vadd(vint(self.orp),self.of)
 local half=trunc(rs/2)
 p1=vadd(p1,vector(half,half,half))
 local p2=vadd(vint(vec),p1)
 if self:isPosAboveSurface(p1) or self:isPosAboveSurface(p2) then
  return
 end
 vec=vadd(vec,self.main_direction)
 local rp=vadd(self.orp,vec)
 rp.x=clamp(rp.x,0,self.ar.x-1)
 rp.y=clamp(rp.y,self.route_y_min,self.route_y_max-1)
 rp.z=clamp(rp.z,0,self.ar.z-1)
 vec=vsub(rp,self.orp)
 local veclen=sqrt(vec.x*vec.x+vec.y*vec.y+vec.z*vec.z)
 if veclen<.05 then veclen=1 end
 local randomize=range(ps,1,2)==1
 -- Native C++ iterates f from 0 to <1 with step 1/veclen.
 local step=1/veclen
 local f=0
 while f<1 do
  self:_carveRoute(vec,f,randomize)
  f=f+step
  self.metrics.sections=self.metrics.sections+1
 end
 self.orp=rp
end
function Walk:makeCave(ps,large)
 assert(type(ps)=='table' and type(ps.next)=='function',
  'shared Luanti PseudoRandom required')
 self.ps=ps
 self.large=large==true
 self.flooded=range(ps,1,1000)<=self.large_cave_flooded*1000
 -- Note: the original optionally selects a biome-specific cave liquid.
 -- With no BiomeGen, preserve the historical cave noise fallback.
 local dswitch=range(ps,1,14)
 if self.large then
  self.part_max_length_rs=range(ps,2,4)
  self.tunnel_routepoints=range(ps,5,range(ps,15,30))
  self.min_d=5
  self.max_d=range(ps,7,range(ps,8,24))
 else
  self.part_max_length_rs=range(ps,2,9)
  self.tunnel_routepoints=range(ps,10,range(ps,15,30))
  self.min_d=2
  self.max_d=range(ps,2,6)
 end
 self.large_cave_is_flat=range(ps,0,1)==0
 self.main_direction=vector(0,0,0)
 local minp,maxp=self.node_min,self.node_max
 local ext=vector(maxp.x-minp.x+1,maxp.y-minp.y+1,maxp.z-minp.z+1)
 local insure=2
 local more=max(16-trunc(self.max_d/2)-insure,1)
 self.ar=vector(ext.x+2*more,ext.y+2*more,ext.z+2*more)
 self.of=vector(minp.x-more,minp.y-more,minp.z-more)
 self.route_y_min=0
 self.route_y_max=clamp(
  -self.of.y+self.max_stone_height+
  trunc(self.max_d/2)+7,0,self.ar.y-1)
 if self.large then
  local minpos=0
  if minp.y<self.water_level and maxp.y>self.water_level then
   minpos=self.water_level-trunc(self.max_d/3)-self.of.y
   self.route_y_max=self.water_level+
    trunc(self.max_d/3)-self.of.y
  end
  self.route_y_min=clamp(range(ps,minpos,minpos+self.max_d),
   0,self.route_y_max)
 end
 local ymin=clamp(self.route_y_min,0,self.ar.y-1)
 local ymax=clamp(self.route_y_max,ymin,self.ar.y-1)
 self.orp=vector(0,0,0)
 self.orp.z=ps:next()%self.ar.z+.5
 self.orp.y=range(ps,ymin,ymax)+.5
 self.orp.x=ps:next()%self.ar.x+.5
 local begin=vadd(self.of,vint(self.orp))
 self.events[#self.events+1]={type=self.large and
  'large_cave_begin' or 'cave_begin',pos=begin}
 self.metrics.caves=self.metrics.caves+1
 for j=0,self.tunnel_routepoints-1 do
  self:_makeTunnel(j%dswitch==0)
 end
 self.events[#self.events+1]={type=self.large and
  'large_cave_end' or 'cave_end',
  pos=vadd(self.of,vint(self.orp))}
 return self.metrics
end
function Walk:generate(blockseed,settings)
 settings=settings or {}
 local maxstone=self.max_stone_height
 local large_ymax=settings.large_cave_depth or -33
 local small_min=settings.small_cave_num_min or 0
 local small_max=settings.small_cave_num_max or 0
 local large_min=settings.large_cave_num_min or 0
 local large_max=settings.large_cave_num_max or 2
 for _,pair in ipairs({{small_min,small_max},{large_min,large_max}}) do
  assert(type(pair[1])=='number' and type(pair[2])=='number' and
   pair[1]==floor(pair[1]) and pair[2]==floor(pair[2]) and
   pair[1]>=0 and pair[2]>=pair[1] and pair[2]<=64,
   'invalid MapgenBasic randomwalk cave count')
 end
 if self.node_min.y>maxstone then return self.metrics end
 local ps=PseudoRandom.new(signed((blockseed+21343)%U))
 local num_small=range(ps,small_min,small_max)
 for i=1,num_small do self:makeCave(ps,false) end
 if self.node_max.y>large_ymax then return self.metrics end
 local num_large=range(ps,large_min,large_max)
 for i=1,num_large do self:makeCave(ps,true) end
 return self.metrics
end
Walk.signed=signed
Walk.mul32=mul32
return Walk
