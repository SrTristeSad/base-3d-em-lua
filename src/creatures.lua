-- Fauna do sandbox Classic 0.30: cinco especies e ataques originais simples.
-- Lua puro; desenho em caixas 3D via LÖVR, sem modelos proprietarios.
local Creatures={}
Creatures.__index=Creatures
local sin,cos,sqrt,floor,abs=math.sin,math.cos,math.sqrt,math.floor,math.abs
Creatures.SPECIES={
 Zombie={count=3,hp=5,speed=1.25,hostile=true,damage=3,points=80},
 Skeleton={count=3,hp=4,speed=1.0,hostile=true,damage=2,points=120},
 Spider={count=3,hp=4,speed=3.15,hostile=true,damage=2,points=105},
 Pig={count=3,hp=3,speed=.65,hostile=false,points=10,drop=26},
 Sheep={count=3,hp=3,speed=.67,hostile=false,points=10,drop=19},
}
Creatures.ORDER={'Zombie','Skeleton','Spider','Pig','Sheep'}
local function distance2(x,z,a,b)
 local dx,dz=x-a,z-b
 return dx*dx+dz*dz
end
local function walkable(world,x,y,z)
 local bx,bz=floor(x+.5),floor(z+.5)
 local by=floor(y+.5)
 return world:within(bx,by,bz) and
   world:isSolid(bx,by-1,bz) and
   not world:isSolid(bx,by,bz) and
   not world:isSolid(bx,by+1,bz)
end
local function clearLine(world,ox,oy,oz,dx,dy,dz,length)
 local t=.3
 while t<length-.35 do
  local x,y,z=floor(ox+dx*t+.5),floor(oy+dy*t+.5),floor(oz+dz*t+.5)
  if world:isSolid(x,y,z) then return false end
  t=t+.25
 end
 return true
end
function Creatures.new(world)
 local self=setmetatable({world=world,list={},projectiles={},seed=27071,clock=0},Creatures)
 for _,kind in ipairs(Creatures.ORDER) do
  for _=1,Creatures.SPECIES[kind].count do self:spawn(kind) end
 end
 return self
end
function Creatures:random()
 self.seed=(self.seed*16807)%2147483647
 return self.seed/2147483647
end
function Creatures:spawn(kind)
 local w=self.world
 local data=self.SPECIES[kind]
 if not data then return nil end
 for _=1,100 do
  local x=floor(w.MIN+3+self:random()*(w.SIZE-6))
  local z=floor(w.MIN+3+self:random()*(w.SIZE-6))
  if distance2(x,z,0,0)>8*8 then
   local y=w:spawnHeight(x,z)
   if y>1 and y<w.YMAX-3 and walkable(w,x,y,z) then
    local occupied=false
    for _,mob in ipairs(self.list) do
     if mob.active and distance2(x,z,mob.x,mob.z)<6*6 then
      occupied=true;break
     end
    end
    if not occupied then
     local mob={
      kind=kind,x=x,y=y,z=z,health=data.hp,active=true,
      respawn=0,phase=self:random()*6.28,yaw=self:random()*6.28,
      turn=1+self:random()*4,nextAttack=0,nextHit=0
     }
     self.list[#self.list+1]=mob
     return mob
    end
   end
  end
 end
 return nil
end
function Creatures:count()
 local active=0
 for _,mob in ipairs(self.list) do
  if mob.active then active=active+1 end
 end
 return active
end
function Creatures:hit(player,classic)
 local ox,oy,oz=player:eye()
 local dx,dy,dz=player:direction()
 local nearest,best=nil,4.4
 for _,mob in ipairs(self.list) do
  if mob.active then
   local height=mob.kind=='Spider' and .65 or 1.15
   local vx,vy,vz=mob.x-ox,mob.y+height-oy,mob.z-oz
   local along=vx*dx+vy*dy+vz*dz
   local perpendicular=vx*vx+vy*vy+vz*vz-along*along
   if along>.1 and along<best and perpendicular<.7*.7 then
    if clearLine(self.world,ox,oy,oz,dx,dy,dz,along) then
     best=along;nearest=mob
    end
   end
  end
 end
 if not nearest then return false end
 if self.clock<nearest.nextHit then return true end
 nearest.nextHit=self.clock+.28
 nearest.health=nearest.health-1
 if nearest.health<=0 then
  nearest.active=false
  nearest.respawn=17
  if classic then
   local data=self.SPECIES[nearest.kind]
   classic:award(data.points)
   if data.drop then
    classic:grant(data.drop,nearest.kind=='Pig' and 2 or 1)
   end
  end
 end
 return true
end
function Creatures:fire(mob,player)
 local ox,oy,oz=mob.x,mob.y+1.35,mob.z
 local dx,dy,dz=player.x-ox,player.y+1.0-oy,player.z-oz
 local d=sqrt(dx*dx+dy*dy+dz*dz)
 if d<.2 or d>13 then return end
 dx,dy,dz=dx/d,dy/d,dz/d
 if not clearLine(self.world,ox,oy,oz,dx,dy,dz,d) then return end
 self.projectiles[#self.projectiles+1]={
  x=ox,y=oy,z=oz,vx=dx*9,vy=dy*9,vz=dz*9,ttl=2
 }
end
function Creatures:update(dt,player,classic)
 if classic and classic.mode=='creative' then return end
 dt=math.max(0,math.min(dt,.1))
 self.clock=self.clock+dt
 local w=self.world
 for _,mob in ipairs(self.list) do
  local data=self.SPECIES[mob.kind]
  if not mob.active then
   mob.respawn=mob.respawn-dt
   if mob.respawn<=0 then
    -- Reposiciona no slot existente sem ampliar a lista.
    local found=false
    for _=1,60 do
     local x=floor(w.MIN+3+self:random()*(w.SIZE-6))
     local z=floor(w.MIN+3+self:random()*(w.SIZE-6))
     local y=w:spawnHeight(x,z)
     if distance2(x,z,0,0)>8*8 and walkable(w,x,y,z) then
      mob.x,mob.y,mob.z=x,y,z
      mob.health=data.hp
      mob.active=true
      mob.turn=1+self:random()*4
      mob.nextAttack=self.clock+1.0
      found=true
      break
     end
    end
    if not found then mob.respawn=3 end
   end
  else
   local distSq=distance2(player.x,player.z,mob.x,mob.z)
   local distance=sqrt(distSq)
   local dy=abs(player.y-mob.y)
   local vx,vz=0,0
   local shouldMove=false
   if data.hostile and distance<16 and dy<3 then
    if distance>.85 then
     vx=(player.x-mob.x)/math.max(.01,distance)
     vz=(player.z-mob.z)/math.max(.01,distance)
     shouldMove=true
    end
    if mob.kind=='Skeleton' then
     if distance<12 and self.clock>=mob.nextAttack then
      mob.nextAttack=self.clock+2.3
      self:fire(mob,player)
     end
    elseif distance<1.7 and self.clock>=mob.nextAttack then
     mob.nextAttack=self.clock+(mob.kind=='Spider' and .9 or 1.25)
     if player.damage then player:damage(data.damage) end
    end
   elseif not data.hostile then
    mob.turn=mob.turn-dt
    if mob.turn<=0 then
     mob.yaw=self:random()*math.pi*2
     mob.turn=1.4+self:random()*4
    end
    vx,vz=sin(mob.yaw),-cos(mob.yaw)
    shouldMove=true
   end
   if shouldMove then
    if data.hostile then
     mob.yaw=(math.atan2 or math.atan)(vx,-vz)
    end
    local step=data.speed*dt
    if walkable(w,mob.x+vx*step,mob.y,mob.z+vz*step) then
     mob.x=mob.x+vx*step
     mob.z=mob.z+vz*step
     mob.phase=mob.phase+step*8
    elseif not data.hostile then
     mob.yaw=mob.yaw+1.3
     mob.turn=.2
    end
   end
  end
 end
 for i=#self.projectiles,1,-1 do
  local a=self.projectiles[i]
  local ox,oy,oz=a.x,a.y,a.z
  local nx,ny,nz=ox+a.vx*dt,oy+a.vy*dt,oz+a.vz*dt
  a.ttl=a.ttl-dt
  local hit=false
  for fraction=1,3 do
   local t=fraction/3
   local x,y,z=ox+(nx-ox)*t,oy+(ny-oy)*t,oz+(nz-oz)*t
   if w:isSolid(floor(x+.5),floor(y+.5),floor(z+.5)) then
    hit=true;break
   end
   if distance2(x,z,player.x,player.z)<.65*.65 and
      abs(y-(player.y+1))<1.1 then
    if player.damage then player:damage(2) end
    hit=true;break
   end
  end
  if hit or a.ttl<=0 then table.remove(self.projectiles,i)
  else a.x,a.y,a.z=nx,ny,nz end
 end
end
local function cube(pass,x,y,z,w,h,d,r,g,b)
 pass:setColor(r,g,b)
 pass:box(x,y,z,w,h,d)
end
function Creatures:draw(pass,px,pz,radius)
 pass:setMaterial()
 local limit=(radius or 34)^2
 for _,mob in ipairs(self.list) do
  if mob.active and distance2(mob.x,mob.z,px,pz)<limit then
   pass:push()
   pass:translate(mob.x,mob.y,mob.z)
   pass:rotate(mob.yaw,0,1,0)
   local k=mob.kind
   local stride=sin(mob.phase)*.10
   if k=='Spider' then
    cube(pass,0,.65,.2,1,.44,1,.24,.19,.25)
    cube(pass,0,.69,-.52,.68,.46,.68,.19,.17,.22)
    for _,side in ipairs({-1,1}) do
     for i=1,4 do
      cube(pass,side*(.63+i*.13),.47,-.76+i*.32,.58,.12,.13,.18,.15,.20)
     end
    end
    cube(pass,-.19,.78,-.87,.12,.12,.03,.90,.16,.14)
    cube(pass,.19,.78,-.87,.12,.12,.03,.90,.16,.14)
   elseif k=='Pig' or k=='Sheep' then
    local r,g,b=.87,.57,.58
    if k=='Sheep' then r,g,b=.90,.90,.86 end
    cube(pass,0,.91,0,.90,.83,1.20,r,g,b)
    cube(pass,0,1.12,-.72,.67,.69,.58,r,g,b)
    cube(pass,0,.99,-1.07,.34,.28,.18,
      k=='Pig' and .97 or .70,k=='Pig' and .48 or .64,
      k=='Pig' and .58 or .61)
    for _,side in ipairs({-1,1}) do
     for _,front in ipairs({-1,1}) do
      cube(pass,side*.27,.29+stride*side*front,front*.38,
        .28,.57,.31,r*.78,g*.78,b*.78)
     end
     cube(pass,side*.18,1.25,-1.02,.07,.09,.04,.16,.15,.16)
    end
   else
    local r,g,b=.38,.63,.36
    if k=='Skeleton' then r,g,b=.83,.83,.78 end
    cube(pass,0,1.29,0,.68,.91,.38,r,g,b)
    cube(pass,0,2.0,0,.62,.60,.61,
      k=='Zombie' and .31 or .85,k=='Zombie' and .59 or .86,
      k=='Zombie' and .30 or .80)
    for _,side in ipairs({-1,1}) do
     cube(pass,side*.49,1.28,0,.30,.89,.35,r*.85,g*.85,b*.84)
     cube(pass,side*.18,.46+stride*side,0,.29,.91,.34,
       k=='Zombie' and .24 or .84,k=='Zombie' and .29 or .85,
       k=='Zombie' and .55 or .79)
     cube(pass,side*.15,2.07,-.316,.10,.12,.035,.08,.10,.11)
    end
   end
   pass:pop()
  end
 end
 for _,a in ipairs(self.projectiles) do
  cube(pass,a.x,a.y,a.z,.13,.13,.47,.72,.67,.85)
 end
 pass:setColor(1,1,1)
end
return Creatures
