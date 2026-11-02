-- Luanti 5.18 fractal VALUE noise, not gradient Perlin noise.
-- Algorithm reference: luanti-org/luanti tag 5.18.0 src/noise.cpp,
-- src/noise.h, src/script/lua_api/l_noise.cpp (BSD-2-Clause / LGPL APIs).
-- Arithmetic is portable across Lua 5.4 and LuaJIT; float rounding in C++
-- remains an identified source of possible last-bit differences.
local Bit=require('core.bitops')
local Noise={}
local floor=math.floor
local abs=math.abs
local U31=2147483648
local U16=65536
local function finite(v)
 return type(v)=='number' and v==v and
  v~=math.huge and v~=-math.huge
end
local function integer(n,low,high)
 return finite(n) and n==floor(n) and n>=low and n<=high
end
-- Lossless low-31-bit multiplication. A raw n*n*n overflows the exact 53-bit
-- double mantissa of LuaJIT and cannot reproduce C++ unsigned overflow.
local function mul31(a,b)
 a=a%U31;b=b%U31
 local lo=a%U16
 local hi=floor(a/U16)
 local blo=b%U16
 local bhi=floor(b/U16)
 local carry=(hi*blo+lo*bhi)%32768
 return (lo*blo+carry*U16)%U31
end
local function lattice(x,y,z,seed,three)
 local n=(1619*x+31337*y+(three and 52591*z or 0)+1013*seed)%U31
 n=Bit.bxor(n,Bit.rshift(n,13))%U31
 local n2=mul31(n,n)
 local cubic=mul31(n2,60493)
 return 1-(mul31(n,(cubic+19990303)%U31)+1376312589)%U31/1073741824
end
local function ease(t)
 return t*t*t*(t*(6*t-15)+10)
end
local function mix(a,b,t)
 return a+(b-a)*t
end
local function value2(x,y,seed,eased)
 -- Upstream myfloor for negative integral coordinates chooses x-1 rather
 -- than x. This still samples the same lattice point at t=1.
 local x0=x<0 and math.ceil(x)-1 or floor(x)
 local y0=y<0 and math.ceil(y)-1 or floor(y)
 local u,v=x-x0,y-y0
 if eased then u=ease(u);v=ease(v) end
 return mix(mix(lattice(x0,y0,0,seed,false),
  lattice(x0+1,y0,0,seed,false),u),
  mix(lattice(x0,y0+1,0,seed,false),
  lattice(x0+1,y0+1,0,seed,false),u),v)
end
local function value3(x,y,z,seed,eased)
 local x0=x<0 and math.ceil(x)-1 or floor(x)
 local y0=y<0 and math.ceil(y)-1 or floor(y)
 local z0=z<0 and math.ceil(z)-1 or floor(z)
 local u,v,w=x-x0,y-y0,z-z0
 if eased then u=ease(u);v=ease(v);w=ease(w) end
 local function face(zslice)
  return mix(
   mix(lattice(x0,y0,zslice,seed,true),
    lattice(x0+1,y0,zslice,seed,true),u),
   mix(lattice(x0,y0+1,zslice,seed,true),
    lattice(x0+1,y0+1,zslice,seed,true),u),v)
 end
 return mix(face(z0),face(z0+1),w)
end
local function flags(raw)
 if raw==nil then return 1 end
 if type(raw)=='number' then
  assert(integer(raw,0,31),'invalid noise flag bits')
  return raw
 end
 assert(type(raw)=='string' or type(raw)=='table','noise flags must be string/table')
 local parts={}
 if type(raw)=='table' then
  for _,v in ipairs(raw) do parts[#parts+1]=v end
 else
  for part in raw:gmatch('[^,%s]+') do parts[#parts+1]=part end
 end
 local bits=0
 for _,part in ipairs(parts) do
  assert(type(part)=='string','invalid noise flag')
  local negative=part:sub(1,2)=='no'
  local name=negative and part:sub(3) or part
  local flag=({defaults=1,eased=2,absvalue=4,pointbuffer=8,simplex=16})[name]
  assert(flag,'unsupported noise flag: '..part)
  if negative then
   bits=Bit.band(bits,Bit.bnot(flag))
  else
   bits=Bit.bor(bits,flag)
  end
 end
 return bits
end
local function copy_params(params)
 assert(type(params)=='table','NoiseParams must be a table')
 local spread=params.spread or {x=250,y=250,z=250}
 assert(type(spread)=='table','invalid noise spread')
 local p={
  offset=params.offset==nil and 0 or params.offset,
  scale=params.scale==nil and 1 or params.scale,
  seed=params.seed==nil and 12345 or params.seed,
  octaves=params.octaves==nil and 3 or params.octaves,
  persist=params.persistence or params.persist or .6,
  lacunarity=params.lacunarity==nil and 2 or params.lacunarity,
  spread={
   x=spread.x,y=spread.y,z=spread.z==nil and spread.x or spread.z
  },
  flags=flags(params.flags)
 }
 assert(finite(p.offset) and finite(p.scale),'invalid noise offset/scale')
 assert(integer(p.seed,-2147483648,2147483647),'invalid noise seed')
 assert(integer(p.octaves,1,24),'invalid noise octave count')
 assert(finite(p.persist) and p.persist~=0 and
  finite(p.lacunarity) and p.lacunarity>=1,'invalid noise persistence/lacunarity')
 assert(finite(p.spread.x) and finite(p.spread.y) and
  finite(p.spread.z) and p.spread.x>0 and
  p.spread.y>0 and p.spread.z>0,'invalid noise spread')
 local highest=p.lacunarity^(p.octaves-1)
 assert(finite(highest) and p.spread.x/highest>=1 and
  p.spread.y/highest>=1 and p.spread.z/highest>=1,
  'noise octave wavelength below one node')
 return p
end
local function parameters(a,b,c,d)
 if type(a)=='table' then return copy_params(a) end
 assert(integer(a,-2147483648,2147483647)
  and integer(b,1,24) and finite(c) and finite(d) and d>0,
  'invalid deprecated value noise arguments')
 return copy_params({seed=a,octaves=b,persist=c,
  spread={x=d,y=d,z=d}})
end
local function seedadd(a,b)
 -- The engine's noise source uses s32 seed arithmetic for world+noise seed.
 local n=(a+b)%4294967296
 return n>=2147483648 and n-4294967296 or n
end
local function calculate(p,x,y,z,three)
 assert(finite(x) and finite(y) and
  (not three or finite(z)),'invalid noise position')
 local total,frequency,gain=0,1,1
 local seed=p.seed
 local eased=Bit.band(p.flags,three and 2 or 3)~=0
 local absolute=Bit.band(p.flags,4)~=0
 for octave=0,p.octaves-1 do
  local v
  if three then
   v=value3(x/p.spread.x*frequency,
    y/p.spread.y*frequency,z/p.spread.z*frequency,
    seedadd(seed,octave),eased)
  else
   v=value2(x/p.spread.x*frequency,
    y/p.spread.y*frequency,seedadd(seed,octave),eased)
  end
  if absolute then v=abs(v) end
  total=total+gain*v
  frequency=frequency*p.lacunarity
  gain=gain*p.persist
 end
 return p.offset+total*p.scale
end
local Scalar={}
Scalar.__index=Scalar
function Scalar:get_2d(p)
 assert(type(p)=='table','2D value noise position required')
 return calculate(self.params,p.x,p.y,nil,false)
end
function Scalar:get_3d(p)
 assert(type(p)=='table','3D value noise position required')
 return calculate(self.params,p.x,p.y,p.z,true)
end
Scalar.get2d=Scalar.get_2d
Scalar.get3d=Scalar.get_3d
local Map={}
Map.__index=Map
local function position(p,three)
 assert(type(p)=='table' and finite(p.x) and finite(p.y) and
  (not three or finite(p.z)),'invalid noise map origin')
 return p
end
function Map:_calc(p,three)
 p=position(p,three)
 if three then assert(self.sz>1,'3D map requires z size > 1') end
 local out={}
 local i=0
 if three then
  for z=0,self.sz-1 do for y=0,self.sy-1 do
   for x=0,self.sx-1 do
    i=i+1
    out[i]=calculate(self.params,p.x+x,p.y+y,p.z+z,true)
   end
  end end
 else
  for y=0,self.sy-1 do for x=0,self.sx-1 do
   i=i+1
   out[i]=calculate(self.params,p.x+x,p.y+y,nil,false)
  end end
 end
 self.result=out
 self.last_is_3d=three
 return out
end
local function fill(buffer,source)
 local out=type(buffer)=='table' and buffer or {}
 for i=1,#source do out[i]=source[i] end
 return out
end
function Map:calc_2d_map(p) self:_calc(p,false) end
function Map:calc_3d_map(p)
 if self.sz<=1 then return nil end
 self:_calc(p,true)
end
function Map:get_2d_map_flat(p,buffer)
 return fill(buffer,self:_calc(p,false))
end
function Map:get_3d_map_flat(p,buffer)
 if self.sz<=1 then return nil end
 return fill(buffer,self:_calc(p,true))
end
function Map:get_2d_map(p)
 local flat=self:_calc(p,false)
 local out={}
 local i=0
 for y=1,self.sy do
  out[y]={}
  for x=1,self.sx do
   i=i+1;out[y][x]=flat[i]
  end
 end
 return out
end
function Map:get_3d_map(p)
 if self.sz<=1 then return nil end
 local flat=self:_calc(p,true)
 local out={}
 local i=0
 for z=1,self.sz do
  out[z]={}
  for y=1,self.sy do
   out[z][y]={}
   for x=1,self.sx do
    i=i+1;out[z][y][x]=flat[i]
   end
  end
 end
 return out
end
function Map:get_map_slice(offset,size,buffer)
 assert(self.result,'calc_2d_map or calc_3d_map required before slicing')
 assert(type(offset)=='table' and type(size)=='table',
  'noise map slice offset and size required')
 local ox,oy,oz=offset.x,offset.y,offset.z or 0
 local sx,sy,sz=size.x,size.y,size.z or 1
 assert(integer(ox,0,self.sx-1) and integer(oy,0,self.sy-1)
  and integer(oz,0,self.last_is_3d and self.sz-1 or 0)
  and integer(sx,1,self.sx) and integer(sy,1,self.sy)
  and integer(sz,1,self.last_is_3d and self.sz or 1)
  and ox+sx<=self.sx and oy+sy<=self.sy
  and oz+sz<=(self.last_is_3d and self.sz or 1),
  'noise map slice outside last computed map')
 local out={}
 for z=oz,oz+sz-1 do for y=oy,oy+sy-1 do
  for x=ox,ox+sx-1 do
   local i=z*self.sx*self.sy+y*self.sx+x+1
   out[#out+1]=self.result[i]
  end
 end end
 return fill(buffer,out)
end
Map.get2dMap=Map.get_2d_map
Map.get3dMap=Map.get_3d_map
Map.get2dMap_flat=Map.get_2d_map_flat
Map.get3dMap_flat=Map.get_3d_map_flat
Map.calc2dMap=Map.calc_2d_map
Map.calc3dMap=Map.calc_3d_map
Map.getMapSlice=Map.get_map_slice
function Noise.scalar(params,world_seed)
 local p=parameters(params)
 p.seed=seedadd(p.seed,world_seed or 0)
 return setmetatable({params=p},Scalar)
end
function Noise.map(params,size,world_seed)
 if type(params)~='table' then return nil end
 local p=parameters(params)
 assert(type(size)=='table','noise map size required')
 local sx,sy,sz=size.x,size.y,size.z or 1
 assert(integer(sx,1,32767) and integer(sy,1,32767)
  and integer(sz,1,32767) and sx*sy*sz<=262144,
  'noise map size exceeds engine limits')
 p.seed=seedadd(p.seed,world_seed or 0)
 return setmetatable({params=p,sx=sx,sy=sy,sz=sz},Map)
end
function Noise.world_scalar(world_seed,...)
 local p=parameters(...)
 p.seed=seedadd(p.seed,world_seed or 0)
 return setmetatable({params=p},Scalar)
end
function Noise.global_scalar(...)
 local p=parameters(...)
 return setmetatable({params=p},Scalar)
end
function Noise.global_map(params,size)
 return Noise.map(params,size,0)
end
Noise._lattice=lattice
return Noise
