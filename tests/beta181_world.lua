-- Fase 1 da reconstrução Beta 1.8.1: terreno, seed, limites e saves.
package.path='./?.lua;./?/init.lua;'..package.path
local files={}
lovr={filesystem={
 read=function(path) return files[path] end,
 write=function(path,data) files[path]=data;return true end,
 isFile=function(path) return files[path]~=nil end,
 createDirectory=function() return true end
}}
local Terrain=require('src.beta181_terrain')
local World=require('src.world')
local Worlds=require('src.worlds')
local Items=require('src.beta181_items')
local Textures=require('src.textures')
local seed='beta-181-foundation'
local a,b,c=Terrain.new(seed),Terrain.new(seed),Terrain.new('seed-diferente')
assert(a.MIN_Y==0 and a.MAX_Y==127 and a.SEA_LEVEL==62)
local biomes,changed,mountains,water,land= {},0,0,0,0
for x=-2000,2000,100 do
 for z=-2000,2000,100 do
  local h,biome=a:column(x,z)
  local h2,biome2=b:column(x,z)
  assert(h==h2 and biome==biome2,'Mesmo seed gerou terreno diferente')
  assert(h>=30 and h<=119,'Altura fora do limite 128')
  if h~=c:height(x,z) then changed=changed+1 end
  biomes[biome]=true
  if h>=88 then mountains=mountains+1 end
  if h<62 then water=water+1 else land=land+1 end
 end
end
assert(changed>100 and water>20 and land>20,'Faltou variação por seed/continentes')
assert(biomes.ocean and biomes.river and biomes.plains and
 biomes.forest and biomes.desert and biomes.taiga and
 biomes.extreme_hills and biomes.swamp,'Biomas Beta ausentes')
assert(mountains>0,'Extreme Hills deveria ser elevado')
assert(a:biome(0,0)==b:biome(0,0))
local foundOre={}
for x=-30,30,3 do for z=-30,30,3 do
 for y=4,55,4 do
  local id=a:ore(x,y,z)
  if id then foundOre[id]=true end
 end
end end
assert(foundOre[14] and foundOre[13] and foundOre[12],'Veios esperados ausentes')
local options,entry=Worlds.create('Novo mundo','origem beta','', 'survival')
assert(entry and entry.generatorVersion=='beta181' and options.generatorVersion=='beta181')
assert(not Worlds.create('Foto','teste','maps/figura.png','survival'))
assert(not files['worlds/000001.map'],'Mundo novo não usa PNG/JPG')
local world=World.new(options)
assert(world.YMIN==0 and world.YMAX==127 and world.MAX_ID==52)
assert(not world:within(0,-1,0) and not world:within(0,128,0))
assert(world:get(0,0,0)==30,'Camada inferior deve ser rocha-mãe')
assert(world:get(0,127,0)==0,'Mundo deve estar vazio em Y 127')
local spawnX,spawnY,spawnZ=world:spawnPoint()
local h,biome=world.gen:column(spawnX,spawnZ)
assert(spawnY>62 and biome~='ocean' and biome~='river',
  'Spawn do jogador ficou embaixo do oceano')
assert(math.abs(spawnX)<=160 and math.abs(spawnZ)<=160)
for x=-64,64,16 do for z=-64,64,16 do
 local level=world.gen:height(x,z)
 if level<62 then
  assert(world:get(x,62,z)==9,'Oceano não chegou a Y=62')
 end
end end
assert(world:set(1,109,1,47),'O novo mundo não suporta minério Beta')
assert(world:get(1,109,1)==47)
assert(world:save({x=spawnX,y=spawnY,z=spawnZ,yaw=0,pitch=0},
 Items.new('survival',{[47]=3})))
local restored=World.new(Worlds.open(entry))
assert(restored:get(1,109,1)==47,'Edição de bloco não persistiu')
assert(restored.savedSlots and restored.savedSlots[1] and
 restored.savedSlots[1].id==47 and restored.savedSlots[1].count==3,
 'Inventário por slot do minério novo não persistiu')
assert(restored.gen:height(300,-175)==world.gen:height(300,-175))
assert(world:cacheCount()>0)
local beta=Items.new('survival')
assert(beta.MAX_STACK==64 and not beta:canPlace(47))
assert(beta:mine(47) and beta:count(264)==1,
 'Minério de diamante deve soltar diamante, não minério')
assert(not beta:canPlace(264),'Diamante é um item')
beta:grant(47,1)
assert(beta:place(47) and beta:count(47)==0)
beta:grant(47,999)
assert(beta:count(47)==999,'Pilhas de 64 devem ocupar slots diferentes')
assert(Items.new('creative'):count(47)==nil)
Textures.setProfile('beta181')
assert(#Textures.hotbar==9 and Textures.faces[47] and Textures.faces[49])
Textures.setProfile('classic030')
assert(#Textures.hotbar==8)
local old=World.new({seed='classic-world',generatorVersion='classic030'})
assert(old.YMIN==-32 and old.YMAX==63 and old.MAX_ID==46)
assert(not old:within(0,127,0))
print('beta181_world: OK')
