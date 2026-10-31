-- Testes do carregamento dinamico 64x64 sem GPU nem LÖVR.
package.path='./?.lua;./?/init.lua;'..package.path
local saved
lovr={filesystem={read=function() return saved end,
 write=function(_,s) saved=s;return true end},
 graphics={newMesh=function(_,vertices)
  local mesh={released=false}
  function mesh:setMaterial(m) self.material=m end
  function mesh:release() self.released=true end
  return mesh
 end}}
local World=require('src.world')
local Mesher=require('src.mesher')
local w=World.new()
assert(w:cacheCount()==0,'Mundo novo nao deve alocar todo o terreno')
assert(w:get(0,-4,0)~=0 and w:get(500,-4,-500)~=0,
 'Terreno nao gera fora do quadrado inicial')
assert(w:cacheCount()<=2)
local p={x=0,y=w:spawnHeight(0,0),z=0,yaw=0,pitch=0}
local targetX,targetZ=480,-432
local base=w:get(targetX,6,targetZ)
assert(w:set(targetX,6,targetZ,7))
assert(w:get(targetX,6,targetZ)==7)
w:prune(0,0,2)
assert(w:cacheCount()<=81,'Chunk distante nao foi descarregado')
assert(w:get(targetX,6,targetZ)==7,'Edicao desapareceu ao regenerar chunk')
assert(w:save(p))
local reload=World.new()
assert(reload:get(targetX,6,targetZ)==7,'Alteracao distante nao persistiu')
assert(reload.savedPlayer and reload.savedPlayer.x==0)
local mock={
 CHUNK=16,YMIN=0,YMAX=0,
 get=function(_,x,y,z)
  return y==0 and x>=0 and x<=15 and z>=0 and z<=15 and 3 or 0
 end
}
local groups,quads=Mesher.buildData(mock,0,0,
 {[3]={'stone','stone','stone','stone','stone','stone'}})
assert(quads==6,'Greedy meshing de plataforma 16x16 deveria gerar 6 quads; resultado '..quads)
assert(#groups.stone==36,'Cada quad precisa apenas de 6 vertices')
local mesher=Mesher.new(reload,{},{})
-- Use somente faces de pedra ficticias para evitar acessos a texturas GPU reais.
mesher.faces=require('src.textures').faces
mesher.textures=setmetatable({}, {__index=function(_,k) return k end})
local loaded=0
for _=1,8 do loaded=loaded+mesher:sync(0,0,1,2) end
assert(loaded==16,'A janela 64x64 deve conter exatamente 16 chunks')
assert(mesher.visibleCount==16 and mesher.pending==0)
assert(mesher.quads>0 and mesher.rebuilds==16)
local first=mesher.chunks['0:0'].meshes[1]
assert(first and not first.released)
for _=1,8 do mesher:sync(320,-320,1,2) end
assert(mesher.visibleCount==16,'Chunks distantes devem ser removidos da GPU')
assert(not mesher.chunks['0:0'] and first.released,
 'Malhas anteriores precisam liberar VRAM')
assert(reload:cacheCount()<=81,'Cache de dados cresceu indefinidamente')
assert(reload.evictedTotal>0,'Nenhum chunk de dados foi descarregado')
assert(reload:get(targetX,6,targetZ)==7)
print('streaming_64: OK')
