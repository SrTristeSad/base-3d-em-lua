-- Fase 10: nataçao, correnteza, ar e dano da lava em Lua puro.
package.path='./?.lua;./?/init.lua;'..package.path
local files={}
local keys={}
lovr={system={isKeyDown=function(...)
 for i=1,select('#',...) do
  if keys[select(i,...)] then return true end
 end
 return false
end},filesystem={
 read=function(p) return files[p] end,
 write=function(p,s) files[p]=s;return true end,
 isFile=function(p) return files[p]~=nil end
}}
local Physics=require('src.beta181_fluid_physics')
local Player=require('src.player')
local World=require('src.world')
local Items=require('src.beta181_items')
local function eq(a,b,label)
 assert(a==b,(label or 'value')..': '..tostring(a)..' ~= '..tostring(b))
end
local world={generatorVersion='beta181',YMIN=0,YMAX=127,BOUND=1000}
function world:spawnPoint() return 0,10,0 end
function world:within(x,y,z)
 return y>=0 and y<=127
end
function world:get(x,y,z)
 if y>=10 and y<=12 and z==0 then
  if x>=-3 and x<=3 then return 9 end
  if x>=20 and x<=24 then return 29 end
 end
 return 0
end
function world:isSolid(x,y,z) return y<=9 end
local survival={profile='beta181',mode='survival'}
local creative={profile='beta181',mode='creative'}
local wet=Player.new(world)
eq(wet.air,15)
eq(Physics.sample(world,0,11.61,0).id,9,'eye water')
assert(Physics.environment(world,wet).underwater)
local dry=Player.new(world)
dry.x=10
wet:update(.05,world,survival)
dry:update(.05,world,survival)
assert(wet.vy>dry.vy,'water must reduce gravity')
eq(wet.inWater,true,'wet feet')
eq(dry.inWater,false,'dry feet')
-- Sem correnteza, a agua natural parada nao desloca na horizontal.
local resting=wet.x
for i=1,5 do wet:update(.05,world,survival) end
eq(wet.x,resting,'still water')
-- Movimento reduzido sob agua, sprint desabilitado.
keys={w=true,lshift=true}
wet.x,wet.y,wet.z=0,10,0
dry.x,dry.y,dry.z=10,10,0
wet:update(.05,world,survival)
dry:update(.05,world,survival)
assert(dry.x==10,'forward is z axis; x unchanged')
assert(math.abs(dry.z)>math.abs(wet.z),'sprint must be faster on land')
eq(wet.sprinting,false,'water blocks sprint')
keys={space=true}
wet.x,wet.y,wet.z,wet.vy=0,10,0,0
wet:update(.05,world,survival)
assert(wet.vy>0,'space raises submerged player')
keys={}
-- Ar cai na agua profunda e volta ao chegar a superficie.
local diver=Player.new(world)
diver.hunger=10
for i=1,320 do diver:update(.05,world,survival) end
eq(diver.air,0,'air exhausted after 15 sec')
assert(diver.health<20,'drowning inflicts damage')
diver.x=10
diver:update(.05,world,survival)
eq(diver.air,15,'breath restored at surface')
eq(diver.underwater,false)
-- Lava inflige dano periodico, mas modo criativo nao perde vida.
local victim=Player.new(world)
victim.x=20
victim.hunger=10
for i=1,16 do victim:update(.05,world,survival) end
eq(victim.inLava,true)
eq(victim.health,16,'lava damage after .75 sec')
victim.x=10
victim:update(.05,world,survival)
eq(victim.inLava,false)
eq(victim.lavaTimer,0,'lava timer cleared after exiting')
local builder=Player.new(world)
builder.x=20
for i=1,40 do builder:update(.05,world,creative) end
eq(builder.health,20,'no lava damage in creative')
-- Correntes propagadas criam impulso na direcao do nivel maior.
local flow={
 generatorVersion='beta181',
 get=function(_,x,y,z)
  if y==10 and z==0 and (x==0 or x==1) then return 9 end
  return 0
 end,
 within=function() return true end,
 fluids={get=function(_,x,y,z)
  if y==10 and z==0 then
   if x==0 then return {id=9,level=0,falling=false} end
   if x==1 then return {id=9,level=1,falling=false} end
  end
 end}
}
local sample=Physics.sample(flow,0,10.1,0)
local vx,vy,vz=Physics.current(flow,sample)
assert(vx>0 and vy==0 and vz==0,'current eastward')
local still={generatorVersion='beta181',
 get=function() return 9 end,within=function() return true end}
local calm=Physics.sample(still,0,10,0)
local cx,cy,cz=Physics.current(still,calm)
eq(cx,0)
eq(cy,0)
eq(cz,0)
-- Blocos com corrente superficial rasa nao submergem os olhos.
local shallow={generatorVersion='beta181',
 get=function() return 9 end,
 fluids={get=function() return {id=9,level=7,falling=false} end}}
eq(Physics.sample(shallow,0,10.4,0),nil,'shallow flow surface')
assert(Physics.sample(shallow,0,9.56,0),'foot inside shallow current')
-- O estado respiratorio nao altera saves antigos.
local opts={seed='phase10',generatorVersion='beta181',
 savePath='worlds/phase10.sav'}
local savedWorld=World.new(opts)
local p=Player.new(savedWorld)
p.air=7.625
assert(savedWorld:save(p,Items.new('survival')))
assert(files['worlds/phase10.sav']:find('PLAYERAIR 7.625',1,true))
local restored=World.new(opts)
eq(restored.savedAir,7.625)
eq(Player.new(restored).air,7.625)
files['worlds/old-air.sav']='PLAYER 0.000 70.000 0.000 0.000000 0.000000\n'
local legacy=World.new({seed='legacy10',generatorVersion='beta181',
 savePath='worlds/old-air.sav'})
eq(Player.new(legacy).air,15)
local classic={generatorVersion='classic030',YMIN=-32,YMAX=63,BOUND=1000,
 spawnPoint=function() return 0,10,0 end,
 get=function() return 9 end,isSolid=function() return false end}
local oldPlayer=Player.new(classic)
oldPlayer:update(.05,classic,{profile='classic030',mode='survival'})
eq(oldPlayer.inWater,false,'Classic gravity remains unchanged')
eq(oldPlayer.air,15)
print('beta181_fluid_player: OK')
