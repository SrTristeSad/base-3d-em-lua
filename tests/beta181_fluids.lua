-- Fase 9: agua, lava, queda, propagacao, save e compatibilidade.
package.path='./?.lua;./?/init.lua;'..package.path
local files={}
lovr={filesystem={
 read=function(p) return files[p] end,
 write=function(p,body) files[p]=body;return true end,
 isFile=function(p) return files[p]~=nil end,
 createDirectory=function() return true end
}}
local World=require('src.world')
local Items=require('src.beta181_items')
local Mesher=require('src.mesher')
local function eq(a,b,label)
 assert(a==b,(label or 'valor')..': '..tostring(a)..' != '..tostring(b))
end
local function newWorld(name)
 return World.new({seed='phase9-'..name,generatorVersion='beta181',
  savePath='worlds/phase9-'..name..'.sav'})
end
local function tick(w,n,dt)
 for i=1,n do w:updateFluids(dt or .3) end
end
local w=newWorld('water')
-- Piso artificial acima do terreno natural. Sem lava natural aqui.
for x=-10,10 do for z=-10,10 do assert(w:set(x,122,z,3)) end end
assert(w:set(0,123,0,9),'agua colocada')
eq(w.fluids:get(0,123,0),nil,'fonte nao tem estado de corrente')
eq(w:get(1,123,0),0,'agua inicialmente parada')
tick(w,1)
eq(w:get(1,123,0),9,'espalhamento lateral')
local state=w.fluids:get(1,123,0)
assert(state and state.level==1 and not state.falling,'profundidade 1')
tick(w,8)
eq(w:get(7,123,0),9,'alcance de 7 blocos')
eq(w:get(8,123,0),0,'limite horizontal')
eq(w.fluids:get(7,123,0).level,7)
assert(w:set(0,123,0,0),'remover fonte')
tick(w,50)
eq(w:get(1,123,0),0,'fluxo deve recuar sem fonte')
eq(w:get(7,123,0),0,'fluxo residual recuou')
-- Fonte que cai verticalmente e expande ao encontrar piso.
local falling=newWorld('falling')
assert(falling:set(0,125,0,9))
tick(falling,1)
eq(falling:get(0,124,0),9,'cai um bloco')
local drop=falling.fluids:get(0,124,0)
assert(drop and drop.falling,'queda marcada no estado')
eq(falling:get(1,125,0),0,'queda tem prioridade lateral')
tick(falling,1)
eq(falling:get(0,123,0),9,'queda continua')
-- Teste de obstrucao e retrigger por escavacao.
local walls=newWorld('wall')
for x=-2,2 do for z=-2,2 do
 assert(walls:set(x,124,z,3)) end end
assert(walls:set(0,125,0,9))
assert(walls:set(1,125,0,3))
tick(walls,1)
eq(walls:get(1,125,0),3,'parede segura agua')
assert(walls:set(1,125,0,0),'abrir parede')
tick(walls,2)
eq(walls:get(1,125,0),9,'abertura reativa fonte')
-- Lava e mais lenta e possui alcance lateral menor.
local lava=newWorld('lava')
for x=-5,5 do for z=-5,5 do
 assert(lava:set(x,122,z,3)) end end
assert(lava:set(0,123,0,29))
tick(lava,2,.5)
eq(lava:get(1,123,0),0,'lava demora')
tick(lava,1,.5)
eq(lava:get(1,123,0),29,'lava avanca apos atraso')
tick(lava,10,.5)
eq(lava:get(3,123,0),29,'alcance lava 3')
eq(lava:get(4,123,0),0,'limite lava 3')
-- Mistura: agua encostando na fonte de lava forma obsidiana (ID 22).
local mix=newWorld('mix')
assert(mix:set(0,125,0,29))
assert(mix:set(1,125,0,9))
tick(mix,6,.5)
eq(mix:get(0,125,0),22,'lava fonte vira obsidiana')
-- Corrente de lava em contato com agua forma pedregulho (ID 10).
local mixFlow=newWorld('mixflow')
assert(mixFlow:set(0,125,0,29,{level=1,falling=false}))
assert(mixFlow:set(1,125,0,9))
tick(mixFlow,6,.5)
eq(mixFlow:get(0,125,0),10,'lava corrente vira pedregulho')
-- A malha separa niveis de fluidos e rebaixa os vertices superiores.
local model={
 CHUNK=16,generatorVersion='beta181',
 fluids={get=function(_,x,y,z)
  if x==0 and y==0 and z==0 then
   return {id=9,level=4,falling=false}
  end
 end},
 get=function(_,x,y,z)
  return (x==0 and y==0 and z==0) and 9 or 0
 end
}
local groups,count=Mesher.buildData(model,0,0,0,
 {[9]={'water','water','water','water','water','water'}})
eq(count,6)
local topFound=false
for name,vertices in pairs(groups) do
 if name=='water@f4' then
  for _,v in ipairs(vertices) do
   if math.abs(v[2]-0)<.001 then topFound=true end
  end
 end
end
assert(topFound,'topo da corrente deve ficar mais baixo')
-- Save: FLUID preserva nivel e queda, sem alterar bloco ou DAYTIME.
assert(walls:save({x=0,y=85,z=0,yaw=0,pitch=0},
 Items.new('survival')))
local saved=files['worlds/phase9-wall.sav']
assert(saved:find('FLUID ',1,true),'estado de fluido persistente')
local restored=newWorld('wall')
eq(restored:get(1,125,0),9,'fluxo restaurado')
assert(restored.fluids:get(1,125,0),'nivel restaurado')
assert(restored.fluids:pendingCount()>0,'fluxo restaurado volta a ser processado')
-- Classic 0.30 nao recebe simulacao, e saves antigos continuam validos.
local classic=World.new({seed='classic9',generatorVersion='classic030'})
eq(classic.fluids,nil)
eq(classic:updateFluids(.25),0)
local old=newWorld('ancient')
eq(old.fluids:pendingCount(),0)
print('beta181_fluids: OK')
