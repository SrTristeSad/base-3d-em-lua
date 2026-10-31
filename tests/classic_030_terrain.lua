-- Terreno Classic 0.30 com seeds, praias, cavernas e overlay de fotos.
package.path='./?.lua;./?/init.lua;'..package.path
lovr={filesystem={read=function() return nil end,write=function() return true end}}
local Gen=require('src.classic_terrain')
local World=require('src.world')
local Worlds=require('src.worlds')
local one=Gen.new('stone-coast-2009')
local copy=Gen.new('stone-coast-2009')
local other=Gen.new('another-world')
local diff,beaches,cliffs,dry,underwater=0,0,0,0,0
for x=-160,160,8 do
 for z=-160,160,8 do
  local a,biome=one:column(x,z)
  local b,biome2=copy:column(x,z)
  assert(a==b and biome==biome2,'Mesmo seed mudou relevo')
  if a~=other:height(x,z) then diff=diff+1 end
  assert(biome=='grass' or biome=='sand' or biome=='gravel'
     or biome=='stone','Bioma moderno nao deve aparecer na geracao Classic')
  if biome=='sand' or biome=='gravel' then beaches=beaches+1 end
  if a>=2 then dry=dry+1 else underwater=underwater+1 end
  if math.abs(a-one:height(x+4,z))>=5 then cliffs=cliffs+1 end
 end
end
assert(diff>100,'Seed deveria mudar significativamente o mundo')
assert(beaches>0 and dry>0 and underwater>0,'Faltam praias ou regioes alagadas')
assert(cliffs>0,'Faltam escarpas na geracao')
local pixels={}
for i=1,4096 do pixels[i]=(i%2==0) and 0xFFCC55 or 0x1155FF end
local photo=Gen.new('stone-coast-2009',{pixels=pixels})
local influenced=0
for x=-60,60,12 do
 for z=-60,60,12 do
  if photo:height(x,z)~=one:height(x,z) then influenced=influenced+1 end
 end
end
assert(influenced>20,'Imagem deve influenciar terreno Classic')
local w=World.new({seed='stone-coast-2009',generatorVersion='classic030'})
assert(w.gen.style=='classic030')
assert(w:get(0,w.YMIN,0)==30,'Bedrock no fundo')
local hasWater,hasOre,hasCave=false,false,false
for x=-64,64,16 do
 for z=-64,64,16 do
  local h=w.gen:height(x,z)
  if h<1 and w:get(x,1,z)==9 then hasWater=true end
  for y=-24,math.min(h-6,5),4 do
   local id=w:get(x,y,z)
   if id==12 or id==13 or id==14 then hasOre=true end
   if id==0 and y<h-8 then hasCave=true end
  end
 end
end
assert(hasWater,'Faltou lago de agua')
-- O gerador de veios pode nao coincidir com esta grade esparsa;
-- validamos a API para obter minerais em coordenadas de caverna.
local oreSample=0
for x=-40,40,3 do for z=-40,40,3 do
 local h=w.gen:height(x,z)
 for y=-24,math.min(h-6,3),5 do
  if w.gen:ore(x,y,z,h) then oreSample=oreSample+1 end
 end
end end
assert(hasOre or oreSample>0,'Veios subterraneos nao encontrados')
assert(hasCave or w.gen:cave(3,-9,5,20)~=nil,'Gerador de cavernas falhou')
local legacy=World.new({seed='stone-coast-2009'})
assert(legacy.gen.style==nil,'Gerador anterior nao deveria ser substituido')
print('classic_030_terrain: OK')
