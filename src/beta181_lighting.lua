-- Iluminacao e relogio do Overworld Beta 1.8.1.
-- Modelo independente, aproximado. 24000 ticks = 1200s.
-- Luz de tochas e lava colocadas: atenuacao Manhattan sem sombras
-- (oclusao de luz por paredes sera uma fase de propagacao posterior).
local Lighting={}
Lighting.__index=Lighting
Lighting.TICKS_PER_DAY=24000
Lighting.TICKS_PER_SECOND=20
Lighting.INITIAL_TIME=1000
Lighting.EMITTERS={[52]=14,[29]=15}
local floor,max,min,abs=math.floor,math.max,math.min,math.abs
local function key(cx,cy,cz) return cx..':'..cy..':'..cz end
local function coord(x,y,z) return x..','..y..','..z end
local function clamp(x,a,b) return max(a,min(b,x)) end
function Lighting.new(world)
 return setmetatable({world=world,time=Lighting.INITIAL_TIME,day=0,
  buckets={},sources={},sourceCount=0},Lighting)
end
function Lighting:setTime(value,day)
 if type(value)~='number' or value~=value or value==math.huge
    or value==-math.huge then return false end
 self.time=value%self.TICKS_PER_DAY
 if day~=nil and type(day)=='number' and day>=0
    and day<1000000000 then self.day=floor(day) end
 return true
end
function Lighting:tick(dt)
 if type(dt)~='number' or dt~=dt or dt<=0 then return end
 local elapsed=self.time+min(dt,.1)*self.TICKS_PER_SECOND
 if elapsed>=self.TICKS_PER_DAY then
  self.day=self.day+floor(elapsed/self.TICKS_PER_DAY)
 end
 self.time=elapsed%self.TICKS_PER_DAY
end
function Lighting:phase()
 local t=self.time
 if t>=23000 then return 'dawn' end
 if t>=13000 then return 'night' end
 if t>=12000 then return 'dusk' end
 return 'day'
end
function Lighting:dayFactor()
 local t=self.time
 if t<12000 then return 1 end
 if t<13000 then return 1-(t-12000)/1000*.84 end
 if t<23000 then return .16 end
 return .16+(t-23000)/1000*.84
end
function Lighting:skyLevel()
 return clamp(floor(4+self:dayFactor()*11+.5),4,15)
end
function Lighting:skyColor()
 -- Cores de atmosfera do prototipo; o jogo final tera fog por bioma.
 local day=self:dayFactor()
 local haze=math.max(0,1-abs(day-.55)/.4)
 return clamp(.025+.42*day+.19*haze,0,1),
   clamp(.035+.60*day+.06*haze,0,1),
   clamp(.10+.80*day,0,1)
end
function Lighting:updateSource(x,y,z,oldId,newId)
 local position=coord(x,y,z)
 local old=self.sources[position]
 if old then
  local bucketKey=key(floor(x/16),floor(y/16),floor(z/16))
  local bucket=self.buckets[bucketKey]
  if bucket then
   bucket[position]=nil
   if not next(bucket) then self.buckets[bucketKey]=nil end
  end
  self.sources[position]=nil
  self.sourceCount=self.sourceCount-1
 end
 local strength=self.EMITTERS[newId]
 if strength then
  local light={x=x,y=y,z=z,power=strength}
  local bucketKey=key(floor(x/16),floor(y/16),floor(z/16))
  self.buckets[bucketKey]=self.buckets[bucketKey] or {}
  self.buckets[bucketKey][position]=light
  self.sources[position]=light
  self.sourceCount=self.sourceCount+1
 end
end
function Lighting:blockLevel(x,y,z)
 if self.sourceCount==0 then return 0 end
 local cx,cy,cz=floor(x/16),floor(y/16),floor(z/16)
 local level=0
 -- Emissor mais distante de alcance 15 encontra-se em um cubo
 -- de 3x3x3 secoes, mesmo nas coordenadas negativas.
 for dx=-1,1 do for dy=-1,1 do for dz=-1,1 do
  local bucket=self.buckets[key(cx+dx,cy+dy,cz+dz)]
  if bucket then
   for _,light in pairs(bucket) do
    local value=light.power-abs(x-light.x)-abs(y-light.y)-abs(z-light.z)
    if value>level then level=value end
    if level>=15 then return 15 end
   end
  end
 end end end
 return max(0,level)
end
-- Consulta exata do mundo para IA: um eixo sem blocos opacos acima
-- recebe luz do ceu. Agua/folhas sao transmitentes neste prototipo.
function Lighting:skyVisible(x,y,z)
 local world=self.world
 x,y,z=floor(x),floor(y),floor(z)
 if not world:within(x,clamp(y,world.YMIN,world.YMAX),z) then
  return false
 end
 if y>world.YMAX then return true end
 for yy=max(world.YMIN,y+1),world.YMAX do
  local id=world:get(x,yy,z)
  if id~=0 and id~=9 and id~=5 and id~=16
    and id~=24 and id~=25 and id~=26 and id~=27 and id~=28
    and id~=52 then return false end
 end
 return true
end
-- Caminho rapido para reconstruir malhas: altura natural da coluna.
-- Nao modela ainda poços cavados atraves da coluna original.
function Lighting:skyApprox(x,y,z,cache)
 local world=self.world
 if not world.gen then return true end
 local column=x..':'..z
 local h=cache and cache[column]
 if not h then
  h=world.gen:height(x,z)
  if cache then cache[column]=h end
 end
 return y>h
end
function Lighting:level(x,y,z)
 local sky=self:skyVisible(x,y,z) and self:skyLevel() or 0
 return max(sky,self:blockLevel(x,y,z))
end
function Lighting:canSpawnHostile(x,y,z)
 return self:level(x,y,z)<=7
end
function Lighting:sunburns(x,y,z)
 return self:dayFactor()>.78 and self:skyVisible(x,y,z)
end
return Lighting
