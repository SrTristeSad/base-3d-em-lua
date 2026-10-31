-- Fase 7: telhados, pocos, entradas laterais e regressao de saves.
package.path='./?.lua;./?/init.lua;'..package.path
local Lighting=require('src.beta181_lighting')
local Mesher=require('src.mesher')
local function eq(a,b,label)
 assert(a==b,(label or 'value')..': '..tostring(a)..' ~= '..tostring(b))
end
local blocks={}
local function key(x,y,z) return x..','..y..','..z end
local fake={YMIN=0,YMAX=31,CHUNK=16,generatorVersion='beta181'}
function fake:within(x,y,z)
 return x>=-20 and x<=20 and z>=-20 and z<=20 and y>=0 and y<=31
end
function fake:get(x,y,z) return blocks[key(x,y,z)] or 0 end
function fake:set(x,y,z,id)
 local old=self:get(x,y,z)
 blocks[key(x,y,z)]=id~=0 and id or nil
 self.lighting:onBlockChanged(x,y,z,old,id)
end
local light=Lighting.new(fake)
fake.lighting=light
eq(light:skyLight(0,10,0),15,'sunlit shaft')
eq(light:skyLight(0,0,0),15,'deep open well')
fake:set(0,20,0,3)
eq(light:skyLight(0,20,0),0,'opaque roof')
eq(light:skyVisible(0,10,0),false,'direct sun blocked')
eq(light:skyTop(0,0),20,'roof top')
eq(light:skyLight(0,19,0),14,'sideways sunlight')
fake:set(0,20,0,0)
eq(light:skyLight(0,10,0),15,'sunlight restored after mining')
-- Uma sala de 3x3 vedada por quatro paredes, teto e piso.
blocks={}
light.skyColumns={}
light.skyColumnCount=0
light:clearSkyCache()
for x=-2,2 do for z=-2,2 do
 fake:set(x,8,z,3)
 fake:set(x,12,z,3)
end end
for y=9,11 do
 for x=-2,2 do
  fake:set(x,y,-2,3)
  fake:set(x,y,2,3)
 end
 for z=-2,2 do
  fake:set(-2,y,z,3)
  fake:set(2,y,z,3)
 end
end
eq(light:skyLight(0,10,0),0,'sealed room')
fake:set(0,12,0,0)
eq(light:skyVisible(0,10,0),true,'roof opening')
eq(light:skyLight(0,10,0),15,'sun at bottom of well')
fake:set(0,12,0,3)
eq(light:skyLight(0,10,0),0,'well covered')
fake:set(2,10,0,0)
eq(light:skyLight(1,10,0),13,'sun through doorway')
eq(light:skyLight(0,10,0),12,'light attenuated in room')
fake:set(2,10,0,3)
eq(light:skyLight(0,10,0),0,'doorway sealed')
-- Coordenadas negativas e invalidacao da coluna.
blocks={}
light.skyColumns={}
light.skyColumnCount=0
light:clearSkyCache()
fake:set(-1,25,0,3)
eq(light:skyTop(-1,0),25,'negative border roof')
fake:set(-1,25,0,0)
eq(light:skyTop(-1,0),-1,'negative border roof removed')
eq(light:skyLight(-1,24,0),15,'negative chunk sky')
light:setTime(18000)
assert(light:skyLevel()<15,'night should dim sunlight')
eq(light:skyLight(-1,24,0),15,'geometry independent of clock')
assert(light:level(-1,24,0)<15)
-- Greedy mesher deve preservar classes de luz solar distintas.
local fakeMesh={
 CHUNK=16,generatorVersion='beta181',lighting={
  skyLight=function(_,x,y,z) return x>=1 and 15 or 3 end,
  blockLevel=function() return 0 end
 },
 get=function(_,x,y,z)
  return x==0 and y==0 and z==0 and 3 or 0
 end
}
local groups,quads=Mesher.buildData(fakeMesh,0,0,0,
 {[3]={'stone','stone','stone','stone','stone','stone'}})
eq(quads,6)
local n=0
for material in pairs(groups) do
 assert(material:match('^stone#%d+#%d+$'),material)
 n=n+1
end
assert(n>=2,'sunlit and shaded groups must differ')
-- Compatibilidade de estado persistente e perfil Classic.
local files={}
lovr={filesystem={
 read=function(p) return files[p] end,
 write=function(p,s) files[p]=s;return true end,
 isFile=function(p) return files[p]~=nil end
}}
local World=require('src.world')
local Items=require('src.beta181_items')
local opts={seed='phase7',generatorVersion='beta181',
 savePath='worlds/phase7.sav'}
local w=World.new(opts)
assert(w:set(3,126,3,3))
eq(w.lighting:skyVisible(3,125,3),false,'roof placed in world')
assert(w:set(3,126,3,0))
eq(w.lighting:skyVisible(3,125,3),true,'shaft opened in world')
local player={x=3,y=85,z=3,yaw=0,pitch=0}
assert(w:save(player,Items.new('survival')))
local restored=World.new(opts)
eq(restored.lighting:skyVisible(3,125,3),true,'save restores skylight')
local classic=World.new({seed='old',generatorVersion='classic030'})
eq(classic.lighting,nil)
print('beta181_skylight: OK')
