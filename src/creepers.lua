-- Creepers originais do sandbox: IA, perseguicao, ataque e explosao.
-- Logica independente de LÖVR para permitir testes em Lua comum.
local Creepers = {}
Creepers.__index = Creepers
local sqrt, floor, cos, sin, abs = math.sqrt,math.floor,math.cos,math.sin,math.abs

local function dist2(a,b,x,z)
  local dx,dz=a-x,b-z
  return dx*dx+dz*dz
end

local function validSpawn(world,x,z)
  if not world:within(x,2,z) then return nil end
  local y=world:spawnHeight(x,z)
  if y<=1.0 or y>world.YMAX-2 then return nil end
  if world:get(x,floor(y+1.5),z)~=0 or
    world:get(x,floor(y+2.1),z)~=0 then return nil end
  return y
end

function Creepers.new(world)
  local self=setmetatable({list={},clock=0,lastId=0,world=world,seed=7043},Creepers)
  for _=1,5 do self:spawn() end
  return self
end

function Creepers:random()
  self.seed=(self.seed*16807)%2147483647
  return self.seed/2147483647
end

function Creepers:spawn()
  local w=self.world
  for _=1,80 do
    local x=floor(w.MIN+3+self:random()*(w.SIZE-6))
    local z=floor(w.MIN+3+self:random()*(w.SIZE-6))
    if dist2(x,z,0,0)>11*11 then
      local y=validSpawn(w,x,z)
      if y then
        local near=false
        for _,mob in ipairs(self.list) do
          if mob.active and dist2(mob.x,mob.z,x,z)<4*4 then near=true; break end
        end
        if not near then
          self.lastId=self.lastId+1
          local mob={id=self.lastId,x=x,y=y,z=z,health=4,
            active=true,fuse=0,cooldown=0,respawn=0,phase=self:random()*6.28,
            yaw=0,nextAttack=0}
          table.insert(self.list,mob)
          return mob
        end
      end
    end
  end
  return nil
end

-- Mantem a população de creepers perto do jogador quando ele viaja.
function Creepers:relocate(mob,player)
 local w=self.world
 for _=1,40 do
  local angle=self:random()*math.pi*2
  local dist=14+self:random()*15
  local x=floor(player.x+sin(angle)*dist)
  local z=floor(player.z+cos(angle)*dist)
  if w:within(x,2,z) then
   local y=validSpawn(w,x,z)
   if y and w:get(x,floor(y+.5),z)==0 then
    mob.x,mob.y,mob.z=x,y,z
    mob.nextAttack=self.clock+1.0
    mob.phase=0
    return true
   end
  end
 end
 return false
end

function Creepers:hit(player,damage,classic)
  local ox,oy,oz=player:eye()
  local dx,dy,dz=player:direction()
  local choice,best=nil,4.5
  for _,mob in ipairs(self.list) do
    if mob.active then
      local vx,vy,vz=mob.x-ox,mob.y+1.25-oy,mob.z-oz
      local along=vx*dx+vy*dy+vz*dz
      if along>0 and along<best then
        local d2=vx*vx+vy*vy+vz*vz-along*along
        if d2<.58*.58 then best=along;choice=mob end
      end
    end
  end
  if not choice then return false end
  -- Limite de ataque impede acertar creepers atraves de parede solida.
  local w=self.world
  for t=.15,best-.3,.18 do
    local x=floor(ox+dx*t+.5)
    local y=floor(oy+dy*t+.5)
    local z=floor(oz+dz*t+.5)
    if w:isSolid(x,y,z) then return false end
  end
  if self.clock < choice.cooldown then return true end
  choice.cooldown=self.clock+.33
  choice.health=choice.health-(damage or 1)
  if choice.health<=0 then
    -- Survival Test 0.30: creeper explode APOS a morte, nao por proximidade.
    self:explode(choice,player)
    if classic then classic:award(200) end
  end
  return true
end

local function canWalk(world,x,y,z)
  local bx,bz=floor(x+.5),floor(z+.5)
  local by=floor(y+.15+.5)
  return not world:isSolid(bx,by,bz)
    and not world:isSolid(bx,by+1,bz)
    and world:isSolid(bx,by-1,bz)
end

function Creepers:explode(mob,player)
  mob.active=false
  mob.respawn=15
  mob.fuse=0
  local dx,dy,dz=player.x-mob.x,player.y+1-mob.y-1,player.z-mob.z
  local distance=sqrt(dx*dx+dy*dy+dz*dz)
  if distance<4.2 then
    local amount=math.floor((1-distance/4.2)*15+.5)
    if amount>0 and player.damage then player:damage(amount) end
  end
  return self.world:explode(mob.x,mob.y+.8,mob.z,2.45)
end

function Creepers:update(dt,player,classic)
  if classic and classic.mode=='creative' then return end
  dt=math.max(0,math.min(dt,.1))
  self.clock=self.clock+dt
  local w=self.world
  for _,mob in ipairs(self.list) do
    if not mob.active then
      mob.respawn=mob.respawn-dt
      if mob.respawn<=0 then
        local nextMob=self:spawn()
        -- Nao cresce o numero de entidades: o antigo slot e eliminado.
        mob.remove=true
        if not nextMob then mob.respawn=3;mob.remove=false end
      end
    else
      if dist2(mob.x,mob.z,player.x,player.z)>48*48 then
        self:relocate(mob,player)
      end
      local d2=dist2(mob.x,mob.z,player.x,player.z)
      local d=sqrt(d2)
      local dy=abs((mob.y+1)-(player.y+1))
      -- No Classic 0.30, o monstro ataca corpo a corpo. Sua explosao
      -- acontece quando e derrotado em combate, sem temporizador de proximidade.
      if d<1.65 and dy<2.2 and self.clock>=mob.nextAttack then
        mob.nextAttack=self.clock+1.2
        if player.damage then player:damage(2) end
      end
      if mob.active and d>1.32 and d<17 and dy<3 then
        local vx,vz=(player.x-mob.x)/d,(player.z-mob.z)/d
        mob.yaw=math.atan2 and math.atan2(vx,-vz) or math.atan(vx,-vz)
        local move=dt*1.65
        local nx,nz=mob.x+vx*move,mob.z+vz*move
        local success=false
        if canWalk(w,nx,mob.y,nz) then
          mob.x,mob.z=nx,nz;success=true
        elseif canWalk(w,nx,mob.y,mob.z) then
          mob.x=nx;success=true
        elseif canWalk(w,mob.x,mob.y,nz) then
          mob.z=nz;success=true
        end
        if success then mob.phase=mob.phase+dt*9 end
      end
    end
  end
  -- Remover de tras para frente, sem alterar pares durante iteracao.
  for i=#self.list,1,-1 do
    if self.list[i].remove then table.remove(self.list,i) end
  end
end

local function cube(pass,x,y,z,w,h,d,r,g,b)
  pass:setColor(r,g,b)
  pass:box(x,y,z,w,h,d)
end

function Creepers:draw(pass,px,pz,radius,skins)
  pass:setMaterial()
  for _,mob in ipairs(self.list) do
    if mob.active and dist2(mob.x,mob.z,px,pz)<(radius or 28)^2 then
      if not (skins and skins:draw(pass,mob,'Creeper')) then
      pass:push()
      pass:translate(mob.x,mob.y,mob.z)
      pass:rotate(mob.yaw,0,1,0)
      local flash=mob.fuse>0 and floor(mob.fuse*9)%2==0
      local r,g,b=.24,.66,.21
      if flash then r,g,b=.90,.95,.83 end
      local bob=sin(mob.phase)*.025
      cube(pass,0,1.45+bob,0,.86,.86,.78,r,g,b)
      cube(pass,0,.74+bob,0,.62,.91,.53,r*.83,g*.84,b*.83)
      local walk=sin(mob.phase)*.095
      for _,side in ipairs({-1,1}) do
        for _,front in ipairs({-1,1}) do
          local lift=side*front*walk
          cube(pass,side*.215,.22+lift,front*.23,.34,.46,.34,
            r*.73,g*.75,b*.71)
        end
      end
      -- Rosto desenhado no plano frontal do cubo, sem texturas oficiais.
      cube(pass,-.205,1.59+bob,-.395,.15,.185,.022,.055,.09,.045)
      cube(pass,.205,1.59+bob,-.395,.15,.185,.022,.055,.09,.045)
      cube(pass,0,1.27+bob,-.395,.16,.22,.022,.055,.09,.045)
      cube(pass,-.12,1.16+bob,-.395,.11,.16,.022,.055,.09,.045)
      cube(pass,.12,1.16+bob,-.395,.11,.16,.022,.055,.09,.045)
      pass:pop()
      end
    end
  end
  pass:setColor(1,1,1)
end
return Creepers
