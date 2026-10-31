-- Fase 6: difusao BFS em torno de paredes, portas e bordas de chunks.
package.path='./?.lua;./?/init.lua;'..package.path
local Light=require('src.beta181_lighting')
local function equal(a,b,label)
 assert(a==b,(label or 'value')..': '..tostring(a)..' != '..tostring(b))
end
local blocks={}
local function pos(x,y,z) return x..','..y..','..z end
local fake={YMIN=0,YMAX=31,CHUNK=16,generatorVersion='beta181'}
function fake:within(x,y,z)
 return y>=0 and y<=31 and x>=-32 and x<=32
   and z>=-32 and z<=32
end
function fake:get(x,y,z)
 return blocks[pos(x,y,z)] or 0
end
function fake:set(x,y,z,id,light)
 local old=self:get(x,y,z)
 blocks[pos(x,y,z)]=id~=0 and id or nil
 return light:onBlockChanged(x,y,z,old,id)
end
local light=Light.new(fake)
fake.lighting=light
-- Uma parede inteira separa duas metades; a luz nao a atravessa.
for y=0,31 do for z=-32,32 do
 blocks[pos(1,y,z)]=3
end end
fake:set(0,15,0,52,light)
equal(light:blockLevel(0,15,0),14,'torch')
equal(light:blockLevel(0,15,1),13,'adjacent open air')
equal(light:blockLevel(1,15,0),0,'opaque wall')
equal(light:blockLevel(2,15,0),0,'behind entire wall')
-- Uma pequena porta permite difusao; obstaculos impõem caminho maior.
fake:set(1,15,0,0,light)
equal(light:blockLevel(2,15,0),12,'open doorway')
fake:set(1,15,0,3,light)
equal(light:blockLevel(2,15,0),0,'doorway blocked again')
-- A difusao encontra um caminho que contorna um unico bloco opaco.
fake:set(0,15,0,0,light)
blocks={}
fake:set(0,15,0,52,light)
fake:set(1,15,0,3,light)
equal(light:blockLevel(2,15,0),10,'detour around stone')
fake:set(1,15,0,0,light)
equal(light:blockLevel(2,15,0),12,'straight path restored')
-- Negativos e fronteiras de chunks (x=-1 / x=0).
fake:set(0,15,0,0,light)
blocks={}
fake:set(-1,15,0,52,light)
equal(light:blockLevel(0,15,0),13,'crossing chunk boundary')
fake:set(0,15,0,3,light)
equal(light:blockLevel(0,15,0),0,'stone on boundary')
equal(light:blockLevel(1,15,0),10,'route around boundary block')
fake:set(-1,15,0,0,light)
equal(light.sourceCount,0)
equal(light:blockLevel(1,15,0),0,'removed torch')
-- Sobreposicao de duas tochas: apagar uma nao apaga a outra.
blocks={}
fake:set(0,15,0,52,light)
fake:set(4,15,0,52,light)
equal(light:blockLevel(2,15,0),12)
fake:set(0,15,0,0,light)
equal(light:blockLevel(2,15,0),12)
fake:set(4,15,0,0,light)
equal(light:blockLevel(2,15,0),0)
-- Salvamento e Classic: regressao da interface de integracao.
local files={}
lovr={filesystem={
 read=function(p) return files[p] end,
 write=function(p,data) files[p]=data; return true end,
 isFile=function(p) return files[p]~=nil end
}}
local World=require('src.world')
local Items=require('src.beta181_items')
local w=World.new({seed='phase6',generatorVersion='beta181',
 savePath='worlds/phase6.sav'})
assert(w:set(5,120,5,52))
assert(w:set(6,120,5,3))
equal(w.lighting:blockLevel(6,120,5),0)
assert(w.dirty['0:7:0'])
assert(w:set(6,120,5,0))
equal(w.lighting:blockLevel(6,120,5),13)
local player={x=5,y=85,z=5,yaw=0,pitch=0}
assert(w:save(player,Items.new('survival')))
local loaded=World.new({seed='phase6',generatorVersion='beta181',
 savePath='worlds/phase6.sav'})
equal(loaded.lighting:blockLevel(6,120,5),13)
local old=World.new({seed='classic',generatorVersion='classic030',
 savePath='worlds/classic.sav'})
equal(old.lighting,nil)
print('beta181_light_occlusion: OK')
