-- Gerador deterministico v1: seed numerica/textual + imagem de referencia.
-- Apenas pixels de uma imagem (PNG/JPG) entram na topografia. Sem dependencia de OS.
local Gen={}
Gen.__index=Gen
local floor,min,max,abs,sin,cos=math.floor,math.min,math.max,math.abs,math.sin,math.cos
local MOD=2147483647
local function clamp(n,a,b) return max(a,min(b,n)) end
function Gen.seed(text)
 text=tostring(text or '0')
 if text:match('^%-?%d+$') and #text<16 then
  local n=tonumber(text)
  if n then return floor(abs(n))%(MOD-1)+1 end
 end
 local h=146959810
 for i=1,#text do h=(h*131+text:byte(i))%MOD end
 return h>0 and h or 1
end
local function hash(seed,x,z,salt)
 local a=(seed+((x%MOD)*92821)%MOD+((z%MOD)*68917)%MOD+salt*347)%MOD
 a=(a*48271)%MOD
 return a/MOD
end
local function smooth(t) return t*t*(3-2*t) end
local function lerp(a,b,t) return a+(b-a)*t end
local function noise(seed,x,z,scale,salt)
 local a,b=x/scale,z/scale
 local ix,iz=floor(a),floor(b)
 local u,v=smooth(a-ix),smooth(b-iz)
 return lerp(
  lerp(hash(seed,ix,iz,salt),hash(seed,ix+1,iz,salt),u),
  lerp(hash(seed,ix,iz+1,salt),hash(seed,ix+1,iz+1,salt),u),v
 )*2-1
end
local function rgb(num)
 return floor(num/65536)%256,floor(num/256)%256,num%256
end
-- A amostra 64x64 e fixa: mesma foto e mesmo seed criam o mesmo mundo.
function Gen.fromImage(image)
 if not image then return nil,'Imagem invalida' end
 local width,height=image:getDimensions()
 if not width or not height or width<1 or height<1 or width>16384 or height>16384 then
  return nil,'A imagem precisa ter 1..16384 pixels de largura e altura'
 end
 local pixels={}
 local hashValue=1
 for z=0,63 do
  for x=0,63 do
   local px=min(width-1,floor((x+.5)*width/64))
   local pz=min(height-1,floor((z+.5)*height/64))
   local r,g,b=image:getPixel(px,pz)
   r=clamp(floor((r or 0)*255+.5),0,255)
   g=clamp(floor((g or 0)*255+.5),0,255)
   b=clamp(floor((b or 0)*255+.5),0,255)
   local packed=r*65536+g*256+b
   pixels[z*64+x+1]=packed
   hashValue=(hashValue*131+packed)%MOD
  end
 end
 return {pixels=pixels,hash=hashValue,size=64}
end
function Gen.encodeImage(map)
 if not map or not map.pixels or #map.pixels~=4096 then return nil end
 local lines={'IMAGE64 '..tostring(map.hash)}
 for z=0,63 do
  local row={}
  for x=0,63 do row[#row+1]=('%06x'):format(map.pixels[z*64+x+1]) end
  lines[#lines+1]=table.concat(row)
 end
 return table.concat(lines,'\n')..'\n'
end
function Gen.decodeImage(data)
 if type(data)~='string' then return nil,'Amostra de imagem ausente' end
 local rows={}
 for line in data:gmatch('[^\r\n]+') do rows[#rows+1]=line end
 if #rows~=65 or not rows[1]:match('^IMAGE64 %d+$') then
  return nil,'Arquivo de imagem do mundo invalido'
 end
 local pixels={}
 local h=1
 for z=0,63 do
  local row=rows[z+2]
  if #row~=64*6 or row:find('[^0-9a-f]') then
   return nil,'Pixels invalidos'
  end
  for x=0,63 do
   local n=tonumber(row:sub(x*6+1,x*6+6),16)
   pixels[#pixels+1]=n
   h=(h*131+n)%MOD
  end
 end
 if h~=tonumber(rows[1]:match('^IMAGE64 (%d+)$')) then
  return nil,'Hash da imagem nao confere'
 end
 return {pixels=pixels,hash=h,size=64}
end
local function sample(map,x,z)
 local gx=x/22
 local gz=z/22
 local ix,iz=floor(gx),floor(gz)
 local u,v=smooth(gx-ix),smooth(gz-iz)
 local p=map.pixels
 local function at(a,b)
  local n=p[(b%64)*64+(a%64)+1]
  local r,g,blue=rgb(n)
  return r/255,g/255,blue/255
 end
 local r0,g0,b0=at(ix,iz)
 local r1,g1,b1=at(ix+1,iz)
 local r2,g2,b2=at(ix,iz+1)
 local r3,g3,b3=at(ix+1,iz+1)
 return lerp(lerp(r0,r1,u),lerp(r2,r3,u),v),
   lerp(lerp(g0,g1,u),lerp(g2,g3,u),v),
   lerp(lerp(b0,b1,u),lerp(b2,b3,u),v)
end
function Gen.new(seed,image)
 return setmetatable({seed=Gen.seed(seed),image=image},Gen)
end
function Gen:column(x,z)
 local seed=self.seed
 local continental=noise(seed,x,z,172,11)
 local hills=noise(seed,x,z,67,19)
 local detail=noise(seed,x,z,23,29)
 local ridges=abs(noise(seed,x,z,88,47))
 local temp=noise(seed,x,z,280,73)
 local moisture=noise(seed,x,z,225,97)
 local imageHeight=0
 local biome
 if self.image then
  local r,g,b=sample(self.image,x,z)
  local brightness=(r+g+b)/3
  local green=g-max(r,b)
  local blue=b-max(r,g)
  imageHeight=(brightness-.5)*23+(r-b)*5
  if blue>.08 then
   imageHeight=imageHeight-7
   biome='water'
  elseif green>.05 then biome='forest'
  elseif r>.66 and g>.48 and b<.51 then biome='desert'
  elseif brightness>.78 and abs(r-g)<.13 then biome='snow'
  else biome='grass' end
 else
  if temp<-.44 then biome='snow'
  elseif moisture<-.3 and temp>.08 then biome='desert'
  elseif moisture>.10 then biome='forest'
  else biome='grass' end
 end
 local base=4+continental*13+hills*7+detail*2+ridges*6+imageHeight
 local y=clamp(floor(base+.5),-18,49)
 return y,biome
end
function Gen:height(x,z)
 return (self:column(x,z))
end
function Gen:random(x,z,salt)
 return hash(self.seed,x,z,salt or 0)
end
return Gen
