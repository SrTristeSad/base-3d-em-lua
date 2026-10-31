-- Classic 0.30 Survival: corpo a corpo, explosao ao morrer, sem pavio moderno.
package.path='./?.lua;./?/init.lua;'..package.path
lovr={filesystem={read=function() return nil end,write=function() return true end}}
local World=require('src.world')
local Player=require('src.player')
local Classic=require('src.classic')
local Creepers=require('src.creepers')
local world=World.new()
local mobs=Creepers.new(world)
local classic=Classic.new('survival')
assert(#mobs.list==5,'Precisamos de 5 creepers iniciais')
for _,mob in ipairs(mobs.list) do
  assert(mob.active and mob.health==4)
  assert(world:within(math.floor(mob.x),2,math.floor(mob.z)))
  assert(mob.x^2+mob.z^2>11*11,'Creeper nasceu no spawn')
end
local mob=mobs.list[1]
local player=Player.new(world)
player.x,player.y,player.z=mob.x+1,mob.y,mob.z
for _=1,17 do mobs:update(.1,player,classic) end
assert(mob.active,'Classic 0.30 nao pode explodir por aproximacao')
assert(player.health<20,'Ataque corpo a corpo nao causou dano')
local t=mobs.clock
local frozen=mobs.list[1].phase
mobs:update(1,player,Classic.new('creative'))
assert(mobs.clock==t and mob.phase==frozen,'Mobs nao devem rodar no Criativo')

local attacker={
 x=mob.x+2,y=mob.y,z=mob.z,health=20,
 eye=function(self) return self.x,self.y+1.25,self.z end,
 direction=function() return -1,0,0 end,
 damage=function(self,n) self.health=self.health-n end,
}
for i=1,4 do
  mobs.clock=mobs.clock+.35
  assert(mobs:hit(attacker,1,classic),'Golpe nao encontrou creeper '..i)
end
assert(not mob.active,'Quatro golpes devem matar o creeper')
assert(mob.respawn>0,'Creeper nao foi colocado em respawn')
assert(classic.score==100,'Pontuacao classica de combate ausente')
assert(attacker.health<20,'Explosao na morte nao causou dano')
assert(not mobs:hit(attacker,1,classic),'Mob morto nao deve ser golpeado')
local bedrock=world:get(12,world.YMIN,12)
world:explode(12,0,12,2.45)
assert(world:get(12,world.YMIN,12)==bedrock,'Camada limite alterada')
local protected=world:get(0,world.YMIN+3,0)
world:explode(0,world.YMIN+3,0,3.5)
assert(world:get(0,world.YMIN+3,0)==protected,'Spawn destruido')
print('creepers_basic: OK')
