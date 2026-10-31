-- Regras do Classic 0.30: dois modos, drops, limite 99 e persistencia.
package.path='./?.lua;./?/init.lua;'..package.path
local file=nil
lovr={filesystem={
  read=function() return file end,
  write=function(_,value) file=value; return true end,
}}
local Classic=require('src.classic')
local World=require('src.world')
local Player=require('src.player')
local s=Classic.new('survival')
assert(s.mode=='survival' and s:count(2)==0 and not s:canPlace(2))
s:mine(1)
assert(s:count(2)==1 and s:count(1)==0,'Grama deve dar terra')
s:mine(4)
assert(s:count(7)==1,'Tronco deve fornecer tabuas')
assert(s:place(2) and s:count(2)==0)
assert(not s:place(2),'Nao pode construir sem blocos')
for _=1,150 do s:mine(3) end
assert(s:count(3)==99,'Pilha maxima deve ser 99')
s:award(100)
assert(s.score==100)
local c=Classic.new('creative')
assert(c:canPlace(2) and c:place(2) and c:count(2)==nil)
assert(c:mine(4) and c.score==0)
assert(Classic.new('desconhecido').mode=='survival','Modo invalido aceito')

local world=World.new()
local actor={x=0,y=world:spawnHeight(0,0),z=0,yaw=.5,pitch=0}
assert(world:save(actor,s))
local reload=World.new()
local persisted=Classic.new(reload.savedMode,reload.savedItems,reload.savedScore)
assert(persisted.mode=='survival')
assert(persisted.score==100 and persisted:count(3)==99)
assert(persisted:count(7)==1)
-- Na base antiga, saves sem MODE/ITEM continuam validos.
file='PLAYER 1.000 5.000 1.000 0.000000 0.000000\n'
local legacy=World.new()
assert(legacy.savedMode==nil and next(legacy.savedItems)==nil)

file=nil
local world2=World.new()
local px,py,pz=10,12,10
assert(world2:set(px,py,pz,1))
local p=setmetatable({x=0,y=6,z=0,selected=2},Player)
function p:raycast()
  return {x=px,y=py,z=pz,id=world2:get(px,py,pz)},
    {x=px,y=py+1,z=pz}
end
local inv=Classic.new('survival')
assert(p:edit(world2,1,{1,2},inv))
assert(world2:get(px,py,pz)==0 and inv:count(2)==1)
assert(not p:edit(world2,2,{1,2},Classic.new('survival')),
  'Nao pode colocar bloco sem estoque')
-- Simula interacao com um alvo vizinho para colocar terra.
assert(world2:set(px,py,pz,3))
assert(p:edit(world2,2,{1,2},inv))
assert(world2:get(px,py+1,pz)==2 and inv:count(2)==0)
assert(not p:edit(world2,2,{1,2},inv),
  'Duplicacao por clique de bloco')
print('classic_basic: OK')
