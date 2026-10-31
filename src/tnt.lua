-- TNT classica: acender, desarmar (ao acertar entidade) e explosao encadeada.
local TNT={}
TNT.__index=TNT
local sqrt,floor=math.sqrt,math.floor
function TNT.new(world)
 return setmetatable({world=world,list={},time=0},TNT)
end
function TNT:ignite(x,y,z,fuse)
 if self.world:get(x,y,z)~=15 then return false end
 if not self.world:set(x,y,z,0) then return false end
 self.list[#self.list+1]={x=x,y=y,z=z,fuse=fuse or 2.3,active=true}
 return true
end
local function inCone(player,x,y,z)
 local ox,oy,oz=player:eye()
 local dx,dy,dz=player:direction()
 local vx,vy,vz=x-ox,y-oy,z-oz
 local along=vx*dx+vy*dy+vz*dz
 return along>.1 and along<5 and
  vx*vx+vy*vy+vz*vz-along*along<.65*.65
end
function TNT:defuse(player,classic)
 local nearest,best
 local ox,oy,oz=player:eye()
 for _,t in ipairs(self.list) do
  if t.active and inCone(player,t.x,t.y,t.z) then
   local dist=(t.x-ox)^2+(t.y-oy)^2+(t.z-oz)^2
   if not best or dist<best then nearest,best=t,dist end
  end
 end
 if not nearest then return false end
 nearest.active=false
 if classic then classic:grant(15,1) end
 return true
end
function TNT:explode(explosion,player)
 local ex,ey,ez=explosion.x,explosion.y,explosion.z
 local w=self.world
 -- TNT proxima tambem e acionada. Sem invalidar a lista durante a iteracao.
 for x=ex-3,ex+3 do
  for y=ey-3,ey+3 do
   for z=ez-3,ez+3 do
    if w:get(x,y,z)==15 and (x-ex)^2+(y-ey)^2+(z-ez)^2<=9 then
     self:ignite(x,y,z,.35)
    end
   end
  end
 end
 w:explode(ex,ey,ez,3.2)
 local dx,dy,dz=player.x-ex,player.y+1-ey,player.z-ez
 local distance=sqrt(dx*dx+dy*dy+dz*dz)
 if distance<4.8 and player.damage then
  player:damage(math.max(1,floor((1-distance/4.8)*14+.5)))
 end
end
function TNT:update(dt,player,classic)
 if classic and classic.mode=='creative' then return end
 dt=math.max(0,math.min(dt,.1))
 self.time=self.time+dt
 for i=#self.list,1,-1 do
  local t=self.list[i]
  if not t.active then
   table.remove(self.list,i)
  else
   t.fuse=t.fuse-dt
   if t.fuse<=0 then
    t.active=false
    self:explode(t,player)
    table.remove(self.list,i)
   end
  end
 end
end
function TNT:draw(pass,px,pz,radius)
 pass:setMaterial()
 for _,t in ipairs(self.list) do
  if t.active and (t.x-px)^2+(t.z-pz)^2<(radius or 35)^2 then
   local white=(floor(t.fuse*8)%2)==0
   if white then pass:setColor(1,.95,.83)
   else pass:setColor(.84,.17,.13) end
   pass:box(t.x,t.y,t.z,.96,.96,.96)
   pass:setColor(.18,.15,.12)
   pass:box(t.x,t.y,t.z,.98,.20,.99)
  end
 end
 pass:setColor(1,1,1)
end
return TNT
