local Camera=require('src.camera')
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
  local p = setmetatable({
    x=0,y=world:spawnHeight(0,0),z=0,
    yaw=0,pitch=0,vy=0,grounded=false,
    selected=1,third=false,health=20,maxHealth=20,
    invulnerable=0
  },Player)
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
  self.x,self.z=0,0
  self.y=world:spawnHeight(0,0)
  self.vy=0
  self.grounded=false
  self.health=self.maxHealth
  self.invulnerable=2
end

function Player:direction()
  return Camera.forward(self.yaw,self.pitch)
end

function Player:update(dt,world)
  dt=math.min(dt,.05)
  if self.health<=0 then return end
  self.invulnerable=math.max(0,self.invulnerable-dt)
  local k=lovr.system.isKeyDown
  local forward=(k('w','up') and 1 or 0)-(k('s','down') and 1 or 0)
  local strafe=(k('d','right') and 1 or 0)-(k('a','left') and 1 or 0)
  local length=sqrt(forward*forward+strafe*strafe)
  if length>0 then
    forward,strafe=forward/length,strafe/length
    local speed=k('lshift','rshift') and 7.2 or 4.5
    local dx=(sin(self.yaw)*forward+cos(self.yaw)*strafe)*speed*dt
    local dz=(-cos(self.yaw)*forward+sin(self.yaw)*strafe)*speed*dt
    if not solid(world,self.x+dx,self.y,self.z) then self.x=self.x+dx end
    if not solid(world,self.x,self.y,self.z+dz) then self.z=self.z+dz end
  end
  if self.grounded and k('space') then
    self.vy=7.4
    self.grounded=false
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
  if self.y < -25 then
    self.x,self.z,self.y=0,0,world:spawnHeight(0,0)
    self.vy=0
  end
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
    if not id then return false end
    if classic and not classic:canPlace(id) then return false end
    if world:set(x,y,z,id) then
      if classic then classic:place(id) end
      return true
    end
  end
  return false
end

return Player
