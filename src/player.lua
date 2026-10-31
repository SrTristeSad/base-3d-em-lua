local Camera=require('src.camera')
local Rules=require('src.beta181_survival')
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
    invulnerable=0
  },Player)
  local status=world.savedStatus
  if world.generatorVersion=='beta181' and status then
    p.health=math.max(1,math.min(20,status.health or 20))
    p.hunger=math.max(0,math.min(20,status.hunger or 20))
    p.saturation=math.max(0,math.min(p.hunger,status.saturation or 5))
    p.exhaustion=math.max(0,math.min(3.999,status.exhaustion or 0))
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
  local sprinting=length>0 and k('lshift','rshift') and
    (not beta or self.hunger>6)
  self.sprinting=sprinting
  if length>0 then
    forward,strafe=forward/length,strafe/length
    local speed=sprinting and 7.2 or 4.5
    local dx=(sin(self.yaw)*forward+cos(self.yaw)*strafe)*speed*dt
    local dz=(-cos(self.yaw)*forward+sin(self.yaw)*strafe)*speed*dt
    local oldX,oldZ=self.x,self.z
    if not solid(world,self.x+dx,self.y,self.z) then self.x=self.x+dx end
    if not solid(world,self.x,self.y,self.z+dz) then self.z=self.z+dz end
    if beta then
      local dist=sqrt((self.x-oldX)^2+(self.z-oldZ)^2)
      Rules.consumeExhaustion(self,dist*(sprinting and .1 or .01))
    end
  end
  if self.grounded and k('space') then
    self.vy=7.4
    self.grounded=false
    if beta then
      Rules.consumeExhaustion(self,sprinting and .8 or .2)
    end
  end
  self.vy=self.vy-19.6*dt
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
