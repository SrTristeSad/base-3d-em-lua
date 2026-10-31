-- Cinco especies Classicas com IA e combate, TNT com pavio e corrente de explosoes.
package.path='./?.lua;./?/init.lua;'..package.path
lovr={filesystem={read=function() return nil end,write=function() return true end}}
local World=require('src.world')
local Classic=require('src.classic')
local Creatures=require('src.creatures')
local TNT=require('src.tnt')
local world=World.new()
local animals=Creatures.new(world)
local types={}
for _,mob in ipairs(animals.list) do types[mob.kind]=true end
for _,name in ipairs(Creatures.ORDER) do
 assert(types[name],'Nao surgiu criatura '..name)
 assert(Creatures.SPECIES[name].points>0)
end
local survival=Classic.new('survival')
local creative=Classic.new('creative')
local fakePlayer={x=12,y=14,z=10,health=20,maxHealth=20,
 eye=function(self) return self.x,self.y+1.15,self.z end,
 direction=function() return -1,0,0 end,
 damage=function(self,n) self.health=self.health-n end}
local z={kind='Zombie',x=10,y=14,z=10,health=5,active=true,
 nextHit=0,nextAttack=999,respawn=0,phase=0,yaw=0,turn=1}
animals.list={z}
for i=1,5 do
 animals.clock=animals.clock+.35
 assert(animals:hit(fakePlayer,survival),'Acerto do zumbi falhou '..i)
end
assert(not z.active and survival.score==80,'Zumbi nao morreu ou nao marcou pontos')
local pig={kind='Pig',x=10,y=14,z=10,health=3,active=true,
 nextHit=0,nextAttack=999,respawn=0,phase=0,yaw=0,turn=1}
animals.list={pig}
for i=1,3 do
 animals.clock=animals.clock+.35
 assert(animals:hit(fakePlayer,survival),'Golpe no porco falhou')
end
assert(survival.score==90 and survival:count(26)==2,'Porco deve soltar cogumelos')
local sheep={kind='Sheep',x=10,y=14,z=10,health=3,active=true,
 nextHit=0,nextAttack=999,respawn=0,phase=0,yaw=0,turn=1}
animals.list={sheep}
for i=1,3 do
 animals.clock=animals.clock+.35
 assert(animals:hit(fakePlayer,survival))
end
assert(survival.score==100 and survival:count(19)==1,'Ovelha deve soltar la')
local skeleton={kind='Skeleton',x=6,y=14,z=10,health=4,active=true,
 nextHit=0,nextAttack=0,respawn=0,phase=0,yaw=0,turn=1}
animals.list={skeleton}
animals:fire(skeleton,fakePlayer)
assert(#animals.projectiles==1,'Esqueleto deve atirar flecha')
local at=animals.clock
animals:update(.1,fakePlayer,creative)
assert(at==animals.clock,'No Criativo criaturas devem ficar pausadas')
local oldhp=fakePlayer.health
for _=1,30 do animals:update(.1,fakePlayer,survival) end
assert(fakePlayer.health<=oldhp,'Projeteis nao devem curar jogador')
local tnt=TNT.new(world)
assert(world:set(12,12,12,15))
assert(world:set(14,12,12,15))
assert(world:set(13,12,12,7))
assert(tnt:ignite(12,12,12,1.2))
assert(world:get(12,12,12)==0)
local survivor={x=20,y=14,z=20,health=20,damage=function(self,n) self.health=self.health-n end}
for _=1,15 do tnt:update(.1,survivor,survival) end
assert(world:get(13,12,12)==0,'TNT nao destruiu construcao')
assert(world:get(14,12,12)==0,'TNT nao provocou reacao em cadeia')
assert(#tnt.list>=1,'TNT proxima nao entrou no pavio')
for _=1,10 do tnt:update(.1,survivor,survival) end
assert(#tnt.list==0,'TNT encadeada nao terminou')
assert(not tnt:ignite(14,12,12),'Nao se pode acender ar')
print('creatures_030: OK')
