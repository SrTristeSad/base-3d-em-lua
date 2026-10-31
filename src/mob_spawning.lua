-- Nascimento de criaturas por regioes, inspirado no Survival Test 0.30.
-- Mobs chegam em pequenos grupos; a logica nao copia taxas exatas de Mojang.
local Spawn={}
Spawn.__index=Spawn
local floor,abs,sin,cos=math.floor,math.abs,math.sin,math.cos
local TYPES={'Pig','Sheep','Zombie','Skeleton','Spider','Creeper'}
local PASSIVE={'Pig','Sheep'}
local HOSTILE={'Zombie','Skeleton','Spider','Creeper'}
function Spawn.new(world,creatures,creepers)
 return setmetatable({world=world,creatures=creatures,creepers=creepers,
  timer=0,visited={},groups=0,born=0,maxCount=26,range=3,
  phaseMark=nil},Spawn)
end
local function valid(world,x,y,z)
 local by=floor(y+.5)
 if by<world.YMIN+2 or by>world.YMAX-3 then return false end
 if not world:isSolid(x,by-1,z) then return false end
 if world:isSolid(x,by,z) or world:isSolid(x,by+1,z) then return false end
 if world:get(x,by-1,z)==9 or world:get(x,by-1,z)==29 then return false end
 return true
end
local function distanceSq(x,z,player)
 return (x-player.x)^2+(z-player.z)^2
end
function Spawn:random(x,z,salt)
 return self.world.gen:random(x,z,salt)
end
function Spawn:activeCount()
 local count=0
 for _,m in ipairs(self.creatures.list) do if m.active then count=count+1 end end
 for _,m in ipairs(self.creepers.list) do if m.active then count=count+1 end end
 return count
end
function Spawn:create(kind,x,y,z,phase)
 if kind=='Creeper' then
  local c=self.creepers
  c.lastId=c.lastId+1
  c.list[#c.list+1]={id=c.lastId,x=x,y=y,z=z,health=4,
   active=true,fuse=0,cooldown=0,respawn=0,phase=phase,yaw=0,nextAttack=0}
 else
  local c=self.creatures
  local spec=c.SPECIES[kind]
  if not spec then return end
  c.list[#c.list+1]={kind=kind,x=x,y=y,z=z,health=spec.hp,
   active=true,respawn=0,phase=phase,yaw=0,turn=2,
   nextAttack=0,nextHit=0}
 end
 self.born=self.born+1
end
function Spawn:group(cx,cz,player)
 local probability=self:random(cx,cz,1101)
 if probability<.43 then return 0 end
 local count=1+floor(self:random(cx,cz,1123)*3)
 local spawned=0
 local originX=cx*16+2+floor(self:random(cx,cz,1131)*12)
 local originZ=cz*16+2+floor(self:random(cx,cz,1139)*12)
 local lighting=self.world.lighting
 local kind
 if lighting then
  local centerY=self.world:spawnHeight(originX,originZ)
  local dark=lighting:canSpawnHostile(originX,floor(centerY+.5),originZ)
  local pool=dark and HOSTILE or PASSIVE
  kind=pool[math.min(#pool,floor(self:random(cx,cz,1109)*#pool)+1)]
 else
  kind=TYPES[math.min(6,floor(self:random(cx,cz,1109)*6)+1)]
 end
 for i=1,count do
  if self:activeCount()>=self.maxCount then break end
  local x=originX+floor(self:random(cx+i,cz,1147)*7)-3
  local z=originZ+floor(self:random(cx,cz+i,1151)*7)-3
  local dsq=distanceSq(x,z,player)
  if dsq>=12*12 and dsq<=55*55 then
   local y=self.world:spawnHeight(x,z)
   if valid(self.world,x,y,z) then
    local allowed=true
    if lighting then
     local atY=floor(y+.5)
     local hostile=kind~='Pig' and kind~='Sheep'
     if hostile then
      allowed=lighting:canSpawnHostile(x,atY,z)
     else
      allowed=lighting:level(x,atY,z)>=9
        and self.world:get(x,atY-1,z)==1
     end
    end
    local occupied=not allowed
    for _,mob in ipairs(self.creatures.list) do
     if mob.active and (mob.x-x)^2+(mob.z-z)^2<2.25 then occupied=true end
    end
    for _,mob in ipairs(self.creepers.list) do
     if mob.active and (mob.x-x)^2+(mob.z-z)^2<2.25 then occupied=true end
    end
    if not occupied then
     self:create(kind,x,y,z,self:random(x,z,1171)*6.28)
     spawned=spawned+1
    end
   end
  end
 end
 if spawned>0 then self.groups=self.groups+1 end
 return spawned
end
function Spawn:sync(player,dt,classic)
 if classic and classic.mode=='creative' then return end
 local lighting=self.world.lighting
 if lighting then
  local mark=lighting:skyLevel()>=9 and 'bright' or 'dark'
  if mark~=self.phaseMark then
   -- Regiões já visitadas durante o dia podem gerar mobs à noite.
   -- Não reabre tentativas a cada segundo, só na transição.
   self.phaseMark=mark
   self.visited={}
  end
 end
 self.timer=self.timer+(dt or 0)
 if self.timer<2.0 then return end
 self.timer=0
 local cx,cz=floor(player.x/16),floor(player.z/16)
 -- Entidades fora da janela desaparecem do simulador, nao sao teleportadas.
 local function prune(list)
  for i=#list,1,-1 do
   local m=list[i]
   if not m.active or distanceSq(m.x,m.z,player)>64*64 then
    table.remove(list,i)
   end
  end
 end
 prune(self.creatures.list)
 prune(self.creepers.list)
 for k in pairs(self.visited) do
  local x,z=k:match('^(-?%d+):(-?%d+)$')
  if x and (abs(tonumber(x)-cx)>self.range+2 or
     abs(tonumber(z)-cz)>self.range+2) then
   self.visited[k]=nil
  end
 end
 -- Da prioridade aos chunks proximos; cada area e tentada uma vez ate sair.
 local regions={}
 for z=cz-self.range,cz+self.range do
  for x=cx-self.range,cx+self.range do
   local dsq=(x-cx)^2+(z-cz)^2
   if dsq<=self.range*self.range then
    regions[#regions+1]={x=x,z=z,d2=dsq}
   end
  end
 end
 table.sort(regions,function(a,b)
  if a.d2~=b.d2 then return a.d2<b.d2 end
  if a.x~=b.x then return a.x<b.x end
  return a.z<b.z
 end)
 local attempts=0
 for _,region in ipairs(regions) do
  local k=region.x..':'..region.z
  if not self.visited[k] and attempts<5 then
   self.visited[k]=true
   self:group(region.x,region.z,player)
   attempts=attempts+1
  end
 end
end
return Spawn
