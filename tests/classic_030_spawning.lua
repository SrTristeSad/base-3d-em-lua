-- Spawn por chunks, especies e limites do modo sobrevivencia.
package.path='./?.lua;./?/init.lua;'..package.path
lovr={filesystem={read=function() return nil end,write=function() return true end}}
local World=require('src.world')
local Creatures=require('src.creatures')
local Creepers=require('src.creepers')
local Spawn=require('src.mob_spawning')
local w=World.new({seed='spawn-2009',generatorVersion='classic030'})
local passive=Creatures.new(w,true)
local hostile=Creepers.new(w,true)
assert(#passive.list==0 and #hostile.list==0,'Modo gerenciado nao inicia populacao fixa')
local engine=Spawn.new(w,passive,hostile)
local player={x=0,y=w:spawnHeight(0,0),z=0}
engine:sync(player,3,{mode='creative'})
assert(engine.born==0,'Criativo nao pode criar mobs')
for i=1,20 do engine:sync(player,2.1,{mode='survival'}) end
assert(engine.born>0 and engine.born<=engine.maxCount,
 'Survival deve criar criaturas com limite populacional')
local types={}
for _,mob in ipairs(passive.list) do
 assert(mob.active and mob.health>0 and mob.kind,'Entidade incompleta')
 assert((mob.x-player.x)^2+(mob.z-player.z)^2>=144,'Nasceu perto demais')
 assert(w:within(math.floor(mob.x),math.floor(mob.y),math.floor(mob.z)))
 types[mob.kind]=true
end
for _,mob in ipairs(hostile.list) do
 assert(mob.active and mob.health>0)
 assert((mob.x-player.x)^2+(mob.z-player.z)^2>=144)
 types.Creeper=true
end
assert(engine:activeCount()<=engine.maxCount)
local first=engine.born
for i=1,10 do engine:sync(player,2.1,{mode='survival'}) end
assert(engine.born==first,'Mesmo chunk nao pode gerar mobs sem limite')
player.x,player.z=500,450
for i=1,20 do engine:sync(player,2.1,{mode='survival'}) end
for _,mob in ipairs(passive.list) do
 assert((mob.x-player.x)^2+(mob.z-player.z)^2<=64*64,
 'Nao descarregou entidade distante')
end
for _,mob in ipairs(hostile.list) do
 assert((mob.x-player.x)^2+(mob.z-player.z)^2<=64*64)
end
assert(engine:activeCount()<=engine.maxCount)
assert(engine.born>first,'Outras regioes geram mobs')
-- A mecanica antiga continua funcionando para mundos existentes.
assert(#Creatures.new(World.new()).list>0)
assert(#Creepers.new(World.new()).list>0)
print('classic_030_spawning: OK')
