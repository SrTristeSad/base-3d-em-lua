-- Luz, relógio, geração de mobs e efeitos solares da Beta 1.8.1.
-- Executa em Lua puro, sem GPU; não valida shaders/imagens finais.
package.path='./?.lua;./?/init.lua;'..package.path
local files={}
lovr={filesystem={
 read=function(path) return files[path] end,
 write=function(path,body) files[path]=body;return true end,
 isFile=function(path) return files[path]~=nil end,
 createDirectory=function() return true end
}}
local Light=require('src.beta181_lighting')
local World=require('src.world')
local Items=require('src.beta181_items')
local Mesher=require('src.mesher')
local Creatures=require('src.creatures')
local Spawn=require('src.mob_spawning')
local function eq(actual,expected,reason)
 assert(actual==expected,(reason or 'diferente')..
   ': esperado '..tostring(expected)..', obtido '..tostring(actual))
end
local fake={
 YMIN=0,YMAX=127,CHUNK=16,gen={height=function() return 64 end},
 generatorVersion='beta181',
 within=function(_,x,y,z)
  return y>=0 and y<=127 and x>=-1000 and z>=-1000
 end,
 get=function(_,x,y,z)
  if y==80 and x==0 and z==0 then return 3 end
  return 0
 end
}
local light=Light.new(fake)
fake.lighting=light
eq(Light.TICKS_PER_DAY,24000)
eq(Light.TICKS_PER_SECOND,20)
assert(light:setTime(6000))
eq(light:phase(),'day')
eq(light:skyLevel(),15)
assert(light:dayFactor()>.99)
eq(light:level(0,81,0),15)
assert(not light:skyVisible(0,70,0),'Telhado bloqueia luz solar direta')
eq(light:level(0,70,0),14) -- iluminado lateralmente ao redor do teto
assert(light:sunburns(0,81,0))
assert(not light:sunburns(0,70,0))
assert(light:setTime(12500))
eq(light:phase(),'dusk')
assert(light:dayFactor()<.6 and light:dayFactor()>.5)
assert(light:setTime(18000))
eq(light:phase(),'night')
eq(light:skyLevel(),6) -- este modelo usa ambiente minimo .16
assert(not light:canSpawnHostile(0,81,0) == false)
assert(not light:sunburns(0,81,0))
assert(light:setTime(23000))
eq(light:phase(),'dawn')
assert(light:setTime(23998,4))
light:tick(.1)
eq(light.time,0)
eq(light.day,5)
light:tick(-10)
eq(light.time,0)
assert(not light:setTime(0/0),'NaN não pode entrar no relógio')
local r,g,b=light:skyColor()
assert(r>=0 and r<=1 and g>=0 and g<=1 and b>=0 and b<=1)
-- Propagação aproximada para tochas posicionadas em seções distintas.
light:updateSource(-1,64,0,0,52)
eq(light.sourceCount,1)
eq(light:blockLevel(-1,64,0),14)
eq(light:blockLevel(0,64,0),13)
eq(light:blockLevel(13,64,0),0)
assert(light:level(-1,64,0)>=14)
light:updateSource(-1,64,0,52,0)
eq(light.sourceCount,0)
eq(light:blockLevel(0,64,0),0)
-- Construir e destruir tochas atualiza índice e malhas vizinhas.
local world=World.new({seed='fase-5',generatorVersion='beta181',
 savePath='worlds/phase5.sav'})
assert(world.lighting)
assert(world:set(2,124,2,52))
eq(world.lighting:blockLevel(2,124,2),14)
assert(world.dirty['0:7:0'])
assert(world.dirty['1:7:0'])
assert(world:set(2,124,2,0))
eq(world.lighting:blockLevel(2,124,2),0)
assert(world:set(2,124,2,52))
assert(world.lighting:setTime(23999,7))
world.lighting:tick(.1)
eq(world.lighting.day,8)
local player={x=1,y=85,z=2,yaw=0,pitch=0,health=20,
 hunger=20,saturation=5,exhaustion=0}
assert(world:save(player,Items.new('survival')))
assert(files['worlds/phase5.sav']:find('DAYTIME 1.000 8',1,true))
local restored=World.new({seed='fase-5',generatorVersion='beta181',
 savePath='worlds/phase5.sav'})
eq(restored.lighting.time,1)
eq(restored.lighting.day,8)
eq(restored.lighting.sourceCount,1)
eq(restored.lighting:blockLevel(2,124,2),14)
-- Registros antigos sem relógio iniciam dia zero, sem conversão.
files['worlds/prelight.sav']='PLAYER 0.000 70.000 0.000 0.000000 0.000000\n'
local old=World.new({seed='pre',generatorVersion='beta181',
 savePath='worlds/prelight.sav'})
eq(old.lighting.time,Light.INITIAL_TIME)
eq(old.lighting.day,0)
local classic=World.new({seed='old-classic',generatorVersion='classic030'})
eq(classic.lighting,nil)
-- A geometria antiga permanece intacta em perfis Classic.
local meshWorld={
 CHUNK=16,generatorVersion='beta181',lighting={
  skyApprox=function(_,x,y,z) return y>0 end,
  blockLevel=function(_,x,y,z) return x==0 and 14 or 0 end
 },
 get=function(_,x,y,z) return (x==0 and y==0 and z==0) and 3 or 0 end
}
local group,count=Mesher.buildData(meshWorld,0,0,0,{[3]={
 'stone','stone','stone','stone','stone','stone'
}})
eq(count,6)
local lit=0
for name in pairs(group) do
 assert(name:match('^stone#%d+#%d+$'),name)
 lit=lit+1
end
assert(lit>=2,'Malhas precisam separar faces com luz diferente')
-- Regra de nascimento: passive claro, hostil escuro, tochas bloqueiam.
local land={
 YMIN=0,YMAX=127,
 generatorVersion='beta181',
 within=function(_,x,y,z) return y>=0 and y<=127 end,
 spawnHeight=function() return 70 end,
 isSolid=function(_,x,y,z) return y==69 end,
 get=function(_,x,y,z) return y==69 and 1 or 0 end,
 gen={random=function() return .9 end, height=function() return 69 end}
}
land.lighting=Light.new(land)
local function makeSpawn()
 local c=Creatures.new(land,true)
 local mobs={list={},lastId=0}
 return Spawn.new(land,c,mobs),c,mobs
end
assert(land.lighting:setTime(6000))
local passive,fa=makeSpawn()
assert(passive:group(1,1,{x=0,z=0})>0)
for _,m in ipairs(fa.list) do
 assert(m.kind=='Sheep' or m.kind=='Pig')
end
assert(land.lighting:setTime(18000))
local hostile,fc,fcreep=makeSpawn()
assert(hostile:group(1,1,{x=0,z=0})>0)
assert(#fcreep.list+#fc.list>0)
for _,m in ipairs(fc.list) do
 assert(m.kind~='Pig' and m.kind~='Sheep')
end
-- Verifica o reset da janela quando escurece.
local cycle=Spawn.new(land,Creatures.new(land,true),{list={},lastId=0})
cycle.phaseMark='bright';cycle.visited={['1:1']=true}
cycle:sync({x=0,z=0},0,Items.new('survival'))
eq(cycle.phaseMark,'dark')
assert(cycle.visited['1:1']==nil)
-- Queima de zumbi e esqueleto ao sol; sob cobertura ou à noite não queimam.
local burningWorld={
 generatorVersion='beta181',lighting=Light.new(fake)
}
local zombies=Creatures.new(burningWorld,true)
zombies.list={{kind='Zombie',x=0,y=82,z=0,health=5,active=true,
 phase=0,yaw=0,turn=2,nextAttack=0,nextHit=0}}
local farPlayer={x=500,y=82,z=500,damage=function() return false end}
assert(burningWorld.lighting:setTime(6000))
for i=1,10 do zombies:update(.1,farPlayer,Items.new('survival')) end
eq(zombies.list[1].health,4)
assert(burningWorld.lighting:setTime(18000))
for i=1,10 do zombies:update(.1,farPlayer,Items.new('survival')) end
eq(zombies.list[1].health,4)
zombies.list[1].y=70
assert(burningWorld.lighting:setTime(6000))
for i=1,10 do zombies:update(.1,farPlayer,Items.new('survival')) end
eq(zombies.list[1].health,4)
print('beta181_lighting: OK')
