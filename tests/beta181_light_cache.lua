-- Fase 8: cache solar por secao, LRU e invalidacao localizada.
package.path='./?.lua;./?/init.lua;'..package.path
local Light=require('src.beta181_lighting')
local function eq(a,b,label)
 assert(a==b,(label or 'valor')..': '..tostring(a)..' ~= '..tostring(b))
end
local blocks={}
local function cell(x,y,z) return x..','..y..','..z end
local w={YMIN=0,YMAX=31,CHUNK=16,generatorVersion='beta181'}
function w:within(x,y,z)
 return x>=-400 and x<=400 and z>=-400 and z<=400
   and y>=0 and y<=31
end
function w:get(x,y,z) return blocks[cell(x,y,z)] or 0 end
function w:set(x,y,z,id)
 local old=self:get(x,y,z)
 blocks[cell(x,y,z)]=id~=0 and id or nil
 return self.lighting:onBlockChanged(x,y,z,old,id)
end
local light=Light.new(w)
w.lighting=light
eq(light:skyLight(0,10,0),15)
eq(light:skyCacheStats().entries,1)
eq(light:skyCacheStats().misses,1)
eq(light:skyLight(0,10,0),15)
eq(light:skyCacheStats().hits,1,'hit')
eq(light:skyCacheStats().misses,1,'sem novo miss')
-- A travessia da borda nao descarta a secao anterior.
eq(light:skyLight(16,10,0),15)
eq(light:skyCacheStats().sections,2)
light:pruneSky(16,0)
eq(light:skyLight(0,10,0),15)
eq(light:skyCacheStats().hits,2,'cache vizinho preservado')
-- Construir em x=0 conserva a luz em x=96.
eq(light:skyLight(96,10,0),15)
local hits=light:skyCacheStats().hits
w:set(0,20,0,3)
eq(light:skyLight(96,10,0),15)
eq(light:skyCacheStats().hits,hits+1,'regiao remota intacta')
eq(light:skyLight(0,10,0),14,'teto altera iluminacao lateral')
w:set(0,20,0,0)
eq(light:skyLight(0,10,0),15,'poco reaberto')
-- O periodo noturno nao modifica o cache geometrico.
light:setTime(18000)
hits=light:skyCacheStats().hits
eq(light:skyLight(0,10,0),15)
eq(light:skyCacheStats().hits,hits+1,'tempo nao invalida')
assert(light:level(0,10,0)<15)
-- Com capacidade artificial pequena, descarta secao LRU.
light:clearSkyCache()
light.skyCacheLimit=5
for i=0,3 do eq(light:skyLight(i,10,0),15) end
eq(light:skyCacheStats().entries,4)
eq(light:skyLight(32,10,0),15)
eq(light:skyLight(48,10,0),15)
assert(light:skyCacheStats().entries<=5,'limite por secao')
eq(light:skyCacheStats().sections,2)
local misses=light:skyCacheStats().misses
eq(light:skyLight(0,10,0),15)
eq(light:skyCacheStats().misses,misses+1,'secao removida recalculada')
-- Coordenadas negativas e descarte apos viagem longa.
light.skyCacheLimit=12000
light:clearSkyCache()
eq(light:skyLight(-1,10,0),15)
eq(light:skyLight(16,10,0),15)
light:pruneSky(16,0)
hits=light:skyCacheStats().hits
eq(light:skyLight(-1,10,0),15)
eq(light:skyCacheStats().hits,hits+1,'borda negativa preservada')
light:pruneSky(304,0)
eq(light:skyCacheStats().sections,0,'secoes antigas descartadas')
-- Luz artificial e a regra de seus emissores permanecem intactas.
w:set(-1,10,0,52)
eq(light:blockLevel(0,10,0),13)
w:set(-1,10,0,0)
eq(light:blockLevel(0,10,0),0)
print('beta181_light_cache: OK')
