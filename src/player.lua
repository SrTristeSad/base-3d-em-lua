local Camera=require('src.camera')
local Rules=require('src.beta181_survival')
local FluidPhysics=require('src.beta181_fluid_physics')
local Player = {}
Player.__index = Player
local sin,cos,floor,sqrt = math.sin,math.cos,math.floor,math.sqrt
local function solid(world,px,py,pz)
  for x=floor(px-.28+.5),floor(px+.28+.5) do
    for y=floor(py+.02+.5),floor(py+1.76+.5) do
      for z=floor(pz-.28+.5),floor(pz+.28+.5) do
        if world:isSolid(x,y,z) then return true end
      end
    end
  end
  return false
end

function Player.new(world)
  local spawnX,spawnY,spawnZ=world:spawnPoint()
  local p = setmetatable({
    x=spawnX,y=spawnY,z=spawnZ,
    yaw=0,pitch=0,vy=0,grounded=false,
    selected=1,third=false,health=20,maxHealth=20,
    hunger=20,saturation=5,exhaustion=0,foodTimer=0,
    mining=nil,eating=nil,sprinting=false,
    invulnerable=0,
    maxAir=15,air=15,airDamageTimer=0,lavaTimer=0,
    inWater=false,inLava=false,underwater=false
  },Player)
  local status=world.savedStatus
  if world.generatorVersion=='beta181' and status then
    p.health=math.max(1,math.min(20,status.health or 20))
    p.hunger=math.max(0,math.min(20,status.hunger or 20))
    p.saturation=math.max(0,math.min(p.hunger,status.saturation or 5))
    p.exhaustion=math.max(0,math.min(3.999,status.exhaustion or 0))
  end
  if world.generatorVersion=='beta181' and world.savedAir then
    p.air=math.max(0,math.min(p.maxAir,world.savedAir))
  end
  local saved=world.savedPlayer
  if saved and math.abs(saved.x)<=world.BOUND-4 and
    math.abs(saved.z)<=world.BOUND-4 and
    saved.y>=world.YMIN and saved.y<=world.YMAX then
    p.x,p.y,p.z,p.yaw,p.pitch=saved.x,saved.y,saved.z,saved.yaw,saved.pitch
  end
  return p
end

-- A resistencia temporaria evita varios danos no mesmo instante.
function Player:damage(amount)
  if self.health<=0 or self.invulnerable>0 then return false end
  if type(amount)~='number' or amount<=0 or amount~=amount then return false end
  self.health=math.max(0,self.health-math.floor(amount+.5))
  self.invulnerable=.65
  return true
end

function Player:respawn(world)
  self.x,self.y,self.z=world:spawnPoint()
  self.vy=0
  self.grounded=false
  self.health=self.maxHealth
  self.invulnerable=2
  self.hunger,self.saturation,self.exhaustion,self.foodTimer=20,5,0,0
  self.mining,self.eating=nil,nil
  self.air,self.airDamageTimer,self.lavaTimer=self.maxAir,0,0
  self.inWater,self.inLava,self.underwater=false,false,false
end

function Player:direction()
  return Camera.forward(self.yaw,self.pitch)
end

function Player:update(dt,world,inventory)
  dt=math.max(0,math.min(dt,.05))
  if self.health<=0 then return end
  self.invulnerable=math.max(0,self.invulnerable-dt)
  local k=lovr.system.isKeyDown
  local forward=(k('w','up') and 1 or 0)-(k('s','down') and 1 or 0)
  local strafe=(k('d','right') and 1 or 0)-(k('a','left') and 1 or 0)
  local length=sqrt(forward*forward+strafe*strafe)
  local beta=inventory and inventory.profile=='beta181' and
    inventory.mode=='survival'
  local fluid=FluidPhysics.environment(world,self)
  local inLiquid=fluid.water or fluid.lava
  local sprinting=length>0 and not inLiquid and k('lshift','rshift') and
    (not beta or self.hunger>6)
  self.sprinting=sprinting
  local speed=fluid.lava and 1.4 or (fluid.water and 2.5
    or (sprinting and 7.2 or 4.5))
  local dx,dz=0,0
  if length>0 then
    forward,strafe=forward/length,strafe/length
    dx=(sin(self.yaw)*forward+cos(self.yaw)*strafe)*speed*dt
    dz=(-cos(self.yaw)*forward+sin(self.yaw)*strafe)*speed*dt
  end
  -- A correnteza atua mesmo sem WASD. Correntes naturais
  -- estacionarias nao criam deslocamento artificial.
  if inLiquid then
    local drift=fluid.lava and .35 or 1.1
    dx=dx+fluid.currentX*drift*dt
    dz=dz+fluid.currentZ*drift*dt
  end
  local oldX,oldZ=self.x,self.z
  if dx~=0 and not solid(world,self.x+dx,self.y,self.z) then
    self.x=self.x+dx
  end
  if dz~=0 and not solid(world,self.x,self.y,self.z+dz) then
    self.z=self.z+dz
  end
  if beta and length>0 then
    local dist=sqrt((self.x-oldX)^2+(self.z-oldZ)^2)
    Rules.consumeExhaustion(self,dist*(sprinting and .1 or .01))
  end
  if inLiquid then
    -- A agua amortece queda; segurar espaco impulsiona para cima,
    -- inclusive ao longo de uma coluna vertical de fluido.
    local gravity=fluid.lava and 3.1 or 4.8
    local terminal=fluid.lava and -1.4 or -2.3
    if k('space') then
      self.vy=math.min(3.3,self.vy+16*dt)
    else
      self.vy=math.max(terminal,(self.vy-gravity*dt)*(1-2.2*dt))
    end
  else
    if self.grounded and k('space') then
      self.vy=7.4
      self.grounded=false
      if beta then
        Rules.consumeExhaustion(self,sprinting and .8 or .2)
      end
    end
    self.vy=self.vy-19.6*dt
  end
  -- Correntes em queda empurram para baixo.
  if inLiquid and fluid.currentY<0 then
    self.vy=math.max(-3,self.vy+fluid.currentY*3*dt)
  end
  local step=self.vy*dt
  if solid(world,self.x,self.y+step,self.z) then
    if step<0 then self.grounded=true end
    self.vy=0
  else
    self.y=self.y+step
    self.grounded=false
  end
  if self.y < world.YMIN-5 then
    self.x,self.y,self.z=world:spawnPoint()
    self.vy=0
  end
  -- Riscos ambientais usam a POSICAO APOS movimentacao.
  local present=FluidPhysics.environment(world,self)
  self.inWater,self.inLava,self.underwater=
    present.water,present.lava,present.underwater
  if world.generatorVersion=='beta181' then
    if self.underwater then
      self.air=math.max(0,(self.air or self.maxAir)-dt)
      if self.air<=0 then
        self.airDamageTimer=self.airDamageTimer+dt
        if self.airDamageTimer>=1 then
          self.airDamageTimer=self.airDamageTimer-1
          if beta then self:damage(2) end
        end
      end
    else
      self.air=self.maxAir
      self.airDamageTimer=0
    end
    if self.inLava then
      self.lavaTimer=self.lavaTimer+dt
      if self.lavaTimer>=.75 then
        self.lavaTimer=self.lavaTimer-.75
        if beta then self:damage(4) end
      end
    else
      self.lavaTimer=0
    end
  end
  if beta then Rules.tick(self,dt) end
end
function Player:eye()
  return self.x,self.y+1.61,self.z
end

function Player:camera(world)
  local x,y,z=self:eye()
  local dx,dy,dz=self:direction()
  if not self.third then
    return x,y,z,x+dx,y+dy,z+dz
  end
  local cx,cy,cz=Camera.thirdPerson(world,x,y,z,dx,dy,dz,3.6)
  return cx,cy,cz,x+dx*.7,y+dy*.7,z+dz*.7
end

function Player:raycast(world,maxdist)
  local ox,oy,oz=self:eye()
  local dx,dy,dz=self:direction()
  local last,seen={},''
  for t=0,maxdist,.06 do
    local x=floor(ox+dx*t+.5)
    local y=floor(oy+dy*t+.5)
    local z=floor(oz+dz*t+.5)
    local k=x..','..y..','..z
    if k~=seen then
      seen=k
      local id=world:get(x,y,z)
      if id~=0 and id~=9 then
        return {x=x,y=y,z=z,id=id},last
      end
      last={x=x,y=y,z=z}
    end
  end
  return nil,nil
end

-- Beta: minerar exige segurar o botão, apontar para o mesmo bloco e
-- manter a mesma ferramenta. Soltar o botão ou mudar o alvo zera a barra.
function Player:stopMining()
 self.mining=nil
end
function Player:updateMining(dt,world,inventory,held)
 if not held or not inventory or inventory.profile~='beta181'
   or inventory.mode~='survival' then
  self.mining=nil
  return false
 end
 local hit=self:raycast(world,5)
 if not hit or not inventory:canMine(hit.id) then
  self.mining=nil
  return false
 end
 local stack=inventory:getSlot(self.selected)
 local toolId=stack and stack.id
 local key=hit.x..':'..hit.y..':'..hit.z..':'..hit.id..':'..
   tostring(self.selected)..':'..tostring(toolId or 0)
 if not self.mining or self.mining.key~=key then
  self.mining={key=key,x=hit.x,y=hit.y,z=hit.z,id=hit.id,
    progress=0,time=Rules.breakSeconds(hit.id,toolId,false)}
 end
 local m=self.mining
 if m.time==math.huge then return false end
 m.progress=math.min(m.time,m.progress+math.max(0,dt))
 if m.progress<m.time then return false end
 self.mining=nil
 if world:get(hit.x,hit.y,hit.z)~=hit.id then return false end
 if world:set(hit.x,hit.y,hit.z,0) then
  inventory:mine(hit.id,self.selected)
  Rules.consumeExhaustion(self,.025)
  return true
 end
 return false
end
function Player:beginEating(inventory)
 if not inventory or inventory.mode~='survival' then return false end
 local stack=inventory:getSlot(self.selected)
 if not stack or not Rules.foodData(stack.id) or self.hunger>=20 then
  return false
 end
 self.eating={slot=self.selected,id=stack.id,elapsed=0}
 return true
end
function Player:stopEating()
 self.eating=nil
end
function Player:updateEating(dt,inventory,held)
 if not self.eating then return false end
 local eat=self.eating
 local stack=inventory and inventory:getSlot(eat.slot)
 if not held or not stack or stack.id~=eat.id or
   self.selected~=eat.slot or self.hunger>=20 then
  self.eating=nil
  return false
 end
 eat.elapsed=eat.elapsed+math.max(0,dt)
 if eat.elapsed<Rules.EAT_SECONDS then return false end
 self.eating=nil
 return inventory:consumeFood(eat.slot,self)
end
function Player:miningFraction()
 local m=self.mining
 if not m or not m.time or m.time==math.huge or m.time<=0 then
  return 0
 end
 return math.min(1,m.progress/m.time)
end

function Player:edit(world,button,hotbar,classic,tnt)
  local hit,prev=self:raycast(world,6)
  if button==1 and hit then
    local id=hit.id
    if classic and not classic:canMine(id) then return false end
    if tnt and id==15 and classic and classic.mode=='survival' then
      return tnt:ignite(hit.x,hit.y,hit.z)
    end
    if world:set(hit.x,hit.y,hit.z,0) then
      if classic then classic:mine(id) end
      return true
    end
  elseif button==2 and hit and prev then
    local x,y,z=prev.x,prev.y,prev.z
    if math.abs(x-self.x)<.8 and math.abs(z-self.z)<.8
      and y<self.y+1.8 and y>self.y-1 then return false end
    local id=hotbar[self.selected]
    if classic and classic.profile=='beta181'
      and classic.mode=='survival' then
      local stack=classic:getSlot(self.selected)
      id=stack and stack.id
    end
    if not id or id>world.MAX_ID then return false end
    if classic and not classic:canPlace(id) then return false end
    if world:set(x,y,z,id) then
      if classic then classic:place(id,
        classic.profile=='beta181' and self.selected or nil) end
      return true
    end
  end
  return false
end

return Player
