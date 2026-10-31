-- Testes puros de creepers e explosoes, sem LÖVR ou Vulkan.
package.path='./?.lua;./?/init.lua;'..package.path
lovr={filesystem={read=function() return nil end,
  write=function() return true end}}
local World=require('src.world')
local Creepers=require('src.creepers')
local Player=require('src.player')
local world=World.new()
local mobs=Creepers.new(world)
assert(#mobs.list==5,'Precisamos de cinco creepers iniciais')
local initial={}
for _,mob in ipairs(mobs.list) do
  assert(mob.active and mob.health==4,'Mob nasce invalido')
  assert(world:within(math.floor(mob.x),2,math.floor(mob.z)))
  assert(world:get(math.floor(mob.x),math.floor(mob.y+2),math.floor(mob.z))==0)
  assert(mob.x*mob.x+mob.z*mob.z>11*11,'Creeper nasceu no spawn')
  local k=mob.x..','..mob.z
  assert(not initial[k],'Dois creepers sobrepostos')
  initial[k]=true
end

local p=Player.new(world)
assert(p.health==20 and p.maxHealth==20)
assert(p:damage(5) and p.health==15)
assert(not p:damage(5) and p.health==15,'Invulnerabilidade ignorada')
p.invulnerable=0
assert(p:damage(200) and p.health==0,'Morte deve zerar vida')
p:respawn(world)
assert(p.health==20 and p.invulnerable>0,'Renascimento falhou')
p.invulnerable=0

local mob=mobs.list[1]
p.x,p.y,p.z=mob.x+1,mob.y,mob.z
for _=1,17 do mobs:update(.1,p) end
assert(not mob.active,'Creeper deve explodir em 1.55 segundos')
assert(p.health<20,'Creeper nao causou dano')
assert(mob.respawn>0,'Creeper nao entrou em cooldown de renascimento')
assert(mobs.clock>=1.6)

-- A explosao nunca apaga a camada limite nem destrói a area do spawn.
local bedrock=world:get(12,world.YMIN,12)
local protected=world:get(0,world.YMIN+3,0)
local removed=world:explode(12,0,12,2.45)
assert(removed>0,'Explosao nao quebrou blocos')
assert(world:get(12,world.YMIN,12)==bedrock,'Camada limite foi destruida')
world:explode(0,world.YMIN+3,0,3.5)
assert(world:get(0,world.YMIN+3,0)==protected,'Spawn protegido foi destruido')
local w=World.new()
local target=mobs.list[2]
-- Testa ataque com olhar diretamente para o mob e recarga de 0.33s.
local attacker={
  x=target.x+2,y=target.y,z=target.z,
  eye=function(self) return self.x,self.y+1.25,self.z end,
  direction=function() return -1,0,0 end,
}
for i=1,4 do
  mobs.clock=mobs.clock+.35
  assert(mobs:hit(attacker,1),'Golpe nao reconheceu o alvo')
end
assert(not target.active,'Quatro golpes devem derrotar o creeper')
assert(not mobs:hit(attacker,1),'Creeper morto nao pode ser atacado')
assert(w:get(0,world.YMIN,0)~=0)
print('creepers_basic: OK')
