-- Regressao do catalogo de blocos Classic 0.30 e save antigo.
package.path='./?.lua;./?/init.lua;'..package.path
local content=nil
lovr={filesystem={read=function() return content end,write=function(_,s) content=s; return true end}}
local World=require('src.world')
local Classic=require('src.classic')
local Textures=require('src.textures')
local w=World.new()
assert(Textures.MAX_ID==49 and w.MAX_ID==46, 'Catalogo Beta expandiu sem mudar os IDs Classic')
for id=1,Textures.MAX_ID do
 assert(type(Textures.faces[id])=='table' and #Textures.faces[id]==6,'face ausente '..id)
 assert(type(Textures.labels[id])=='string','nome ausente '..id)
 for _,texture in ipairs(Textures.faces[id]) do
  assert(Textures.colors[texture],'cor da textura inexistente '..texture)
 end
end
local found={}
for _,page in ipairs(Textures.pages) do
 assert(#page==8)
 for _,id in ipairs(page) do found[id]=true end
end
assert(found[15] and found[46] and found[26] and found[30])
assert(Textures.setPage(3))
assert(Textures.hotbar[1]==18)
assert(Textures.nextPage(1))
assert(Textures.hotbar[1]==26)
assert(Textures.setPage(1))
assert(Textures.hotbar[1]==1)
assert(w:set(10,12,10,46),'Nao coloca ultimo bloco')
assert(w:get(10,12,10)==46)
assert(w:set(10,12,10,0))
assert(not w:set(10,12,10,47),'Nao pode aceitar ID invalido')
assert(w:set(11,12,10,30))
assert(not w:set(11,12,10,0),'Rocha-mae e inquebravel')
assert(not w:isSolid(10,12,10))
for _,id in ipairs({24,25,26,27,28,29,9}) do
 assert(w:set(10,12,11,id))
 assert(not w:isSolid(10,12,11),'Decoracao ou liquido nao deve bloquear')
end
local naturalOres=0
for x=w.MIN,w.MAX do
 for z=w.MIN,w.MAX do
  for y=w.YMIN,8 do
   local id=w:get(x,y,z)
   if id==12 or id==13 or id==14 then naturalOres=naturalOres+1 end
  end
 end
end
assert(naturalOres>0,'Gerador nao cria minerais')
local survival=Classic.new('survival')
assert(survival:count(15)==10,'TNT inicial Survival Test ausente')
assert(survival:mine(3) and survival:count(10)==1,'Pedra deve dar pedregulho')
assert(survival:mine(12) and survival:count(18)==1,'Ouro deve dar bloco de ouro')
assert(survival:mine(13) and survival:count(19)==1,'Ferro deve dar bloco de ferro')
assert(survival:mine(14) and survival:count(23)==1,'Carvao deve dar laje')
assert(not survival:mine(9) and not survival:mine(30))
survival:grant(26,2)
local hero={health=12,maxHealth=20}
assert(survival:eat(hero) and hero.health==17)
assert(survival:eat(hero) and hero.health==20)
assert(not survival:eat(hero))
local player={x=0,y=8,z=0,yaw=0,pitch=0}
assert(w:save(player,survival))
local loaded=World.new()
assert(loaded:get(11,12,10)==30)
assert(loaded:get(10,12,11)==9)
local saved=Classic.new(loaded.savedMode,loaded.savedItems,loaded.savedScore)
assert(saved:count(10)==1 and saved:count(15)==10)
content='PLAYER 0.000 8.000 0.000 0.000000 0.000000\n'
assert(World.new().savedMode==nil,'Saves antigos devem continuar abrindo')
print('blocks_030: OK')
