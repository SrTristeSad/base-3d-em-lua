-- Beta 1.8.1 Overworld: primeira reconstrução independente.
-- NÃO é o algoritmo original da Mojang. Usa ruído fractal próprio e
-- parâmetros documentados: altura 0..127, mar até Y=62, grandes oceanos,
-- rios, planícies, pântanos, florestas, taiga sem neve e Extreme Hills.
local Seeds=require('src.worldgen')
local Terrain={}
Terrain.__index=Terrain
Terrain.style='beta181'
Terrain.MIN_Y=0
Terrain.MAX_Y=127
Terrain.SEA_LEVEL=62
local floor,abs,min,max=math.floor,math.abs,math.min,math.max
local function clamp(x,a,b) return max(a,min(b,x)) end
local function smooth(t) return t*t*(3-2*t) end
local function lerp(a,b,t) return a+(b-a)*t end
function Terrain.new(seed)
 return setmetatable({seed=Seeds.seed(seed),style='beta181',
   seaLevel=Terrain.SEA_LEVEL},Terrain)
end
function Terrain:random(x,z,salt)
 local MOD=2147483647
 local a=(self.seed*48271+((x%MOD)*92821)%MOD+
  ((z%MOD)*68917)%MOD+(salt or 0)*347)%MOD
 a=(a*11939+104729)%MOD
 a=(a*48271+17389)%MOD
 return a/MOD
end
function Terrain:noise(x,z,scale,salt)
 local a,b=x/scale,z/scale
 local ix,iz=floor(a),floor(b)
 local u,v=smooth(a-ix),smooth(b-iz)
 local function h(xx,zz) return self:random(xx,zz,salt)*2-1 end
 return lerp(lerp(h(ix,iz),h(ix+1,iz),u),
  lerp(h(ix,iz+1),h(ix+1,iz+1),u),v)
end
-- Value noise 3D inteiramente determinístico; sem estado de PRNG.
function Terrain:noise3(x,y,z,scale,salt)
 local ax,ay,az=x/scale,y/scale,z/scale
 local ix,iy,iz=floor(ax),floor(ay),floor(az)
 local u,v,w=smooth(ax-ix),smooth(ay-iy),smooth(az-iz)
 local function h(xx,yy,zz)
  return self:random(xx+yy*107,zz-yy*233,salt)*2-1
 end
 local function edge(yy,zz)
  return lerp(h(ix,yy,zz),h(ix+1,yy,zz),u)
 end
 return lerp(
  lerp(edge(iy,iz),edge(iy+1,iz),v),
  lerp(edge(iy,iz+1),edge(iy+1,iz+1),v),w)
end
function Terrain:biome(x,z)
 local continental=self:noise(x,z,720,101)*.70+
    self:noise(x,z,300,103)*.30
 -- A Biome 1.8: grandes massas de terra, rios como bioma independente.
 if continental<-.13 then return 'ocean' end
 local river=abs(self:noise(x,z,160,107)*.75+
   self:noise(x,z,67,109)*.25)
 if river<.045 then return 'river' end
 local t=self:noise(x,z,360,211)+self:noise(x,z,160,213)*.25
 local m=self:noise(x,z,380,227)+self:noise(x,z,160,229)*.25
 local mountain=self:noise(x,z,360,251)
 if mountain>.29 and continental>.10 then return 'extreme_hills' end
 if t> .26 and m<.02 then return 'desert' end
 if t<-.25 then return 'taiga' end
 if m>.32 and continental<.28 then return 'swamp' end
 if m>.02 then return 'forest' end
 return 'plains'
end
function Terrain:column(x,z)
 local biome=self:biome(x,z)
 local continental=self:noise(x,z,720,101)*.70+
    self:noise(x,z,300,103)*.30
 local rolling=self:noise(x,z,130,301)*4.1+
   self:noise(x,z,49,303)*2.2+
   self:noise(x,z,18,305)*.9
 local h
 if biome=='ocean' then
  h=46+continental*21+rolling*.45
 elseif biome=='river' then
  h=58+rolling*.20
 elseif biome=='swamp' then
  h=63+rolling*.35
 elseif biome=='extreme_hills' then
  local ridge=abs(self:noise(x,z,110,307))
  local height=self:noise(x,z,73,311)
  h=75+continental*9+ridge*24+height*9+rolling*.5
 elseif biome=='desert' then
  h=66+continental*5+rolling*.48
 else
  h=66+continental*8+rolling
 end
 return clamp(floor(h+.5),30,119),biome
end
function Terrain:height(x,z)
 return (self:column(x,z))
end
function Terrain:cave(x,y,z,h)
 if y<=4 or y>=min(92,h-6) then return false end
 -- Dois campos cruzados abrem corredores; o segundo só é calculado
 -- quando o primeiro está perto de zero, para poupar processamento.
 local a=self:noise3(x,y,z,30,401)
 if abs(a)>.095 then return false end
 local b=self:noise3(x+800,y-130,z+700,23,409)
 return abs(b)<.20
end
function Terrain:ore(x,y,z)
 -- IDs 12/13/14 já existiam na base; 47..49 são novos blocos da Beta.
 -- Veios são locais e independentes da ordem de geração de chunks.
 if y<=2 or y>=112 then return nil end
 local cx,cy,cz=floor(x/4),floor(y/4),floor(z/4)
 local a=self:random(cx*11+cy*17,cz*19-cy*7,503)
 if a<.76 then return nil end
 local centerX=cx*4+floor(self:random(cx,cz+cy,521)*4)
 local centerY=cy*4+floor(self:random(cx+cy,cz,523)*4)
 local centerZ=cz*4+floor(self:random(cx-cy,cz,527)*4)
 local dx,dy,dz=x-centerX,y-centerY,z-centerZ
 if dx*dx+dy*dy+dz*dz>6 then return nil end
 if a>.988 and y<=16 then return 47 end -- diamante
 if a>.971 and y<=16 then return 48 end -- redstone
 if a>.949 and y<=32 then return 49 end -- lapis-lazuli
 if a>.91 and y<=32 then return 12 end -- ouro
 if a>.83 and y<=64 then return 13 end -- ferro
 return 14 -- carvão
end
function Terrain:tree(x,z)
 local h,b=self:column(x,z)
 if b~='forest' and b~='taiga' and b~='swamp'
  and b~='plains' then return nil end
 if h<=self.SEA_LEVEL or h>111 then return nil end
 local threshold=b=='forest' and .965 or
   (b=='taiga' and .968 or (b=='swamp' and .985 or .996))
 if self:random(x,z,701)<=threshold then return nil end
 -- Evita árvores densas em uma mesma área sem depender da ordem
 -- de carregamento do terreno.
 for dx=-2,2 do for dz=-2,2 do
  if dx~=0 or dz~=0 then
   if self:random(x+dx,z+dz,701)>self:random(x,z,701)
     and self:random(x+dx,z+dz,701)>threshold then
    return nil
   end
  end
 end end
 return b=='taiga' and 'spruce' or (b=='swamp' and 'swamp' or 'oak')
end
function Terrain:decoration(x,z)
 local h,b=self:column(x,z)
 if h<=self.SEA_LEVEL or b=='desert' or b=='ocean' or b=='river' then return nil end
 local n=self:random(x,z,751)
 if n>.996 then return 24 end
 if n>.992 then return 25 end
 if n>.988 then return 26 end
 if n>.984 then return 27 end
 return nil
end
local function idx(x,y,z)
 return (y%16)*256+(z%16)*16+(x%16)+1
end
function Terrain:generateSection(cx,cy,cz)
 local data={}
 local sx,sy,sz=cx*16,cy*16,cz*16
 local maxY=min(sy+15,self.MAX_Y)
 if sy>self.MAX_Y or maxY<self.MIN_Y then return data end
 local heights={}
 local function column(x,z)
  local k=x..':'..z
  if heights[k] then return heights[k][1],heights[k][2] end
  local h,b=self:column(x,z)
  heights[k]={h,b}
  return h,b
 end
 local function set(x,y,z,id,onlyAir)
  if x<sx or x>=sx+16 or z<sz or z>=sz+16
    or y<sy or y>sy+15 or y<self.MIN_Y or y>self.MAX_Y then return end
  local index=idx(x,y,z)
  if not onlyAir or data[index]==nil then data[index]=id end
 end
 for x=sx,sx+15 do
  for z=sz,sz+15 do
   local h,b=column(x,z)
   local surface=(b=='desert' and 6) or
      ((b=='ocean' or b=='river') and 11 or 1)
   local filler=(b=='desert' and 6) or 2
   -- Surface, filler, pedra, minérios e água.
   for y=max(self.MIN_Y,sy),min(h,maxY) do
    local id
    if y==0 or (y<=4 and self:random(x+y*23,z-y*17,557)<(5-y)*.19)
      then id=30
    elseif y==h then id=surface
    elseif y>=h-3 then id=filler
    else id=3 end
    if id==3 then
      if self:cave(x,y,z,h) then id=0
      else id=self:ore(x,y,z) or 3 end
    end
    if id~=0 then set(x,y,z,id) end
   end
   for y=max(sy,h+1),min(maxY,self.SEA_LEVEL) do
    set(x,y,z,9)
   end
  end
 end
 -- Árvores de centros externos, determinísticas em fronteiras de seção.
 for x=sx-3,sx+18 do
  for z=sz-3,sz+18 do
   local kind=self:tree(x,z)
   if kind then
    local ground=column(x,z)
    local trunk=kind=='spruce' and 6 or 5
    local top=ground+trunk
    for y=ground+1,top do set(x,y,z,4) end
    for y=top-3,top+1 do
     local r=(y==top+1 or y==top-3) and 1 or 2
     if kind=='spruce' then
      r=(y==top+1) and 0 or ((top-y)%2==0 and 2 or 1)
     end
     for xx=x-r,x+r do for zz=z-r,z+r do
      if abs(xx-x)+abs(zz-z)<r*2+1 then
       set(xx,y,zz,5,true)
      end
     end end
    end
   end
  end
 end
 for x=sx,sx+15 do for z=sz,sz+15 do
  local h,b=column(x,z)
  if h+1>=sy and h+1<=maxY then
   local plant=self:decoration(x,z)
   if plant then set(x,h+1,z,plant,true) end
  end
 end end
 return data
end
return Terrain
