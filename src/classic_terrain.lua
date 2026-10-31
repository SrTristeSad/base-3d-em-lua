-- Geracao Classic 0.30 (reconstrucao independente orientada ao relevo de 2009).
-- Preserva Cubic Chunks, seeds e foto-opcional. Nao reproduz codigo Mojang.
local Gen=require('src.worldgen')
local Terrain={}
Terrain.__index=Terrain
local floor,abs,min,max=math.floor,math.abs,math.min,math.max
local function smooth(t) return t*t*(3-2*t) end
local function interpolate(a,b,t) return a+(b-a)*smooth(t) end
function Terrain.new(seed,image)
 return setmetatable({
  seed=Gen.seed(seed),image=image,seaLevel=1,style='classic030',
  version=1
 },Terrain)
end
function Terrain:random(x,z,salt)
 -- Usa o RNG deterministico do projeto sem estados mutaveis.
 local n=(self.seed+(x%2147483647)*92821+
   (z%2147483647)*68917+(salt or 0)*347)%2147483647
 n=(n*11939+104729)%2147483647
 n=(n*48271+17389)%2147483647
 return n/2147483647
end
function Terrain:noise(x,z,scale,salt)
 local a,b=x/scale,z/scale
 local ix,iz=floor(a),floor(b)
 local r00=self:random(ix,iz,salt)
 local r10=self:random(ix+1,iz,salt)
 local r01=self:random(ix,iz+1,salt)
 local r11=self:random(ix+1,iz+1,salt)
 return interpolate(interpolate(r00,r10,a-ix),
                    interpolate(r01,r11,a-ix),b-iz)*2-1
end
local function imageInfluence(image,x,z)
 if not image or not image.pixels then return 0,0 end
 local u,v=x/28,z/28
 local ix,iz=floor(u),floor(v)
 local function rgb(a,b)
  local value=image.pixels[(b%64)*64+(a%64)+1] or 0
  local r=floor(value/65536)%256
  local g=floor(value/256)%256
  local blue=value%256
  return r/255,g/255,blue/255
 end
 local r00,g00,b00=rgb(ix,iz)
 local r10,g10,b10=rgb(ix+1,iz)
 local r01,g01,b01=rgb(ix,iz+1)
 local r11,g11,b11=rgb(ix+1,iz+1)
 local function blend(a,b,c,d)
  return interpolate(interpolate(a,b,u-ix),interpolate(c,d,u-ix),v-iz)
 end
 local red=blend(r00,r10,r01,r11)
 local green=blend(g00,g10,g01,g11)
 local blue=blend(b00,b10,b01,b11)
 local luminosity=(red+green+blue)/3
 -- Cores azuis criam bacias; manchas claras elevam encostas.
 return (luminosity-.5)*12+(red-blue)*5,blue-green
end
function Terrain:column(x,z)
 -- Continentes baixos, planaltos, escarpas que lembram a fase Classic.
 local continents=self:noise(x,z,112,17)
 local hills=self:noise(x,z,38,23)
 local sharp=self:noise(x,z,76,31)
 local irregular=self:noise(x,z,13,37)
 local rise=max(0,abs(sharp)-.21)*28
 local photo,blue=imageInfluence(self.image,x,z)
 local h=3+continents*15+hills*8+rise+irregular*1.8+photo
 h=max(-19,min(49,floor(h+.5)))
 -- Praias estreitas nas margens d'agua; sem biomas modernos no modo Classic.
 local wet=self:noise(x,z,29,61)
 local surface='grass'
 if h<=self.seaLevel+2 then
  if h<=self.seaLevel-2 and wet<-.2 then surface='gravel'
  elseif h>=self.seaLevel-3 and wet>-.55 then surface='sand' end
 end
 if h>29 and self:noise(x,z,14,39)<-.2 then surface='stone' end
 if blue>.17 and h<self.seaLevel+4 then surface='sand' end
 return h,surface
end
function Terrain:height(x,z)
 return (self:column(x,z))
end
function Terrain:cave(x,y,z,surface)
 if y>=surface-3 or y<=-31 then return false end
 -- Tunel de secao arredondada, com camadas maiores conforme profundidade.
 -- Coordenadas globais permitem cavernas continuas cruzando chunks.
 local offset=self:noise(x,z,44,73)*7
 local centre=-9+offset
 local radius=1.5+max(0,-y-7)*.043
 local worm=self:noise(x+floor(y/5),z,50,83)*6
 local axis=abs(self:noise(x+worm,z-y*.46,38,89))
 return abs(y-centre)<radius and axis<.23
end
function Terrain:ore(x,y,z,surface)
 if y>=surface-2 or y<=-31 then return nil end
 local cellX,cellY,cellZ=floor(x/4),floor(y/4),floor(z/4)
 local p=self:random(cellX*11+cellY*3,cellZ*7-cellY*13,97)
 local threshold=.73
 if p<threshold then return nil end
 local ore=14
 if p>.965 and y<5 then ore=12
 elseif p>.88 and y<20 then ore=13 end
 local centreX=cellX*4+1
 local centreY=cellY*4+1
 local centreZ=cellZ*4+1
 if (x-centreX)^2+(y-centreY)^2+(z-centreZ)^2<=6 then
  return ore
 end
 return nil
end
function Terrain:tree(x,z)
 local y,surface=self:column(x,z)
 if surface~='grass' or y<self.seaLevel+1 or y>40 then return false end
 if abs(x)<=4 and abs(z)<=4 then return false end
 return self:random(x,z,313)>.985
end
function Terrain:decoration(x,z)
 local y,surface=self:column(x,z)
 if surface~='grass' or y<=self.seaLevel+1 then return nil end
 local p=self:random(x,z,499)
 if p>.996 then return 24
 elseif p>.992 then return 25
 elseif p>.988 then return 26
 elseif p>.984 then return 27 end
 return nil
end
return Terrain
