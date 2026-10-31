-- Testes puros da Fase 4: fornalhas persistentes, combustíveis e GUI.
package.path='./?.lua;./?/init.lua;'..package.path
local files={}
lovr={filesystem={
 read=function(path) return files[path] end,
 write=function(path,data) files[path]=data;return true end,
 isFile=function(path) return files[path]~=nil end
}}
local Furnace=require('src.beta181_furnace')
local Items=require('src.beta181_items')
local World=require('src.world')
local UI=require('src.ui')
local function eq(a,b,label)
 assert(a==b,(label or 'value')..': '..tostring(a)..' ~= '..tostring(b))
end
local function stack(id,count)
 return {id=id,count=count,damage=0}
end
eq(Furnace.SECONDS_PER_ITEM,10)
eq(Furnace.fuels[263],80)
eq(Furnace.fuels[4],15)
eq(Furnace.recipes[13],265)
eq(Furnace.recipes[12],266)
eq(Furnace.recipes[319],320)
eq(Furnace.recipes[6],16)
-- 1 unidade de carvão funde 8 minérios, mesmo em uma atualização grande.
local f=Furnace.new()
f.slots[1]=stack(13,9)
f.slots[2]=stack(263,1)
eq(f:update(9),0)
eq(f.slots[2],nil)
eq(f.burn,71)
eq(f.progress,9)
eq(f:update(1),1)
eq(f.slots[3].id,265)
eq(f.slots[3].count,1)
eq(f.slots[1].count,8)
eq(f.burn,70)
eq(f:update(70),7)
eq(f.slots[3].count,8)
eq(f.slots[1].count,1)
eq(f.burn,0)
eq(f:update(100),0)
eq(f.progress,0)
eq(f.slots[1].count,1)
assert(not f:canSmelt() == false)
-- Combustível que já foi aceso continua queimando mesmo sem entrada.
local coal=Furnace.new()
coal.slots[1]=stack(319,1)
coal.slots[2]=stack(263,1)
eq(coal:update(10),1)
eq(coal.slots[3].id,320)
eq(coal:update(70),0)
eq(coal.burn,0)
-- Resultado cheio não deve consumir carvão.
local blocked=Furnace.new()
blocked.slots[1]=stack(12,3)
blocked.slots[2]=stack(263,1)
blocked.slots[3]=stack(266,64)
eq(blocked:update(20),0)
eq(blocked.slots[2].count,1)
eq(blocked.progress,0)
assert(not blocked:canSmelt())
blocked.slots[3].count=63
eq(blocked:update(10),1)
eq(blocked.slots[3].count,64)
-- Entrada inválida não é consumida.
local wrong=Furnace.new()
wrong.slots[1]=stack(264,5)
wrong.slots[2]=stack(263,1)
eq(wrong:update(20),0)
eq(wrong.slots[1].count,5)
eq(wrong.slots[2].count,1)
-- Receitas de vidro e comida.
for _,pair in ipairs({{6,16},{319,320},{363,364},{365,366},{12,266}}) do
 local test=Furnace.new()
 test.slots[1]=stack(pair[1],1)
 test.slots[2]=stack(7,1)
 eq(test:update(10),1)
 eq(test.slots[3].id,pair[2])
end
-- Integracao com inventario: input somente fundivel; fuel somente combustível.
local inv=Items.new('survival')
local ui=Furnace.new()
inv.openFurnace=ui
assert(inv:grant(13,3))
assert(inv:grant(263,1))
assert(inv:grant(264,1))
assert(inv:clickSlot('inventory',1,1,false))
eq(inv.cursor.id,13)
assert(not inv:clickSlot('furnace',2,1,false),
 'Minério não deve entrar no slot de combustível')
assert(inv:clickSlot('furnace',1,1,false))
eq(inv.cursor,nil)
eq(ui.slots[1].id,13)
eq(ui.slots[1].count,3)
assert(inv:clickSlot('inventory',2,1,false))
eq(inv.cursor.id,263)
assert(not inv:clickSlot('furnace',3,1,false),
 'Slot de saída não aceita itens')
assert(inv:clickSlot('furnace',2,1,false))
eq(inv.cursor,nil)
eq(ui.slots[2].id,263)
eq(ui:update(10),1)
assert(inv:clickSlot('furnace',3,1,false))
eq(inv.cursor.id,265)
eq(inv.cursor.count,1)
eq(ui.slots[3],nil)
assert(inv:clickSlot('inventory',4,1,false))
eq(inv:getSlot(4).id,265)
eq(inv.cursor,nil)
eq(ui:update(20),2)
eq(ui.slots[3].count,2)
assert(inv:clickSlot('furnace',3,1,true))
eq(ui.slots[3],nil)
eq(inv:count(265),3)
-- Ctrl/Shift transferências preservam itens.
assert(inv:clickSlot('furnace',1,1,true)==false)
local noSpace=Items.new('survival')
for i=1,36 do noSpace.slots[i]=stack(270,1) end
local res=Furnace.new()
res.slots[3]=stack(265,64)
assert(not res:takeOutput(noSpace,1,true))
eq(res.slots[3].count,64)
assert(not res:takeOutput(noSpace,1,false)==false)
eq(noSpace.cursor.id,265)
noSpace.cursor=nil
-- Estado real de mundo + save + reabrir bloco sem converter mundo Classic.
local world=World.new({seed='furnace-beta',
 generatorVersion='beta181',savePath='worlds/furnaces.sav'})
local x,y,z=5,112,7
assert(world:set(x,y,z,51))
local station=world:getFurnace(x,y,z)
assert(station and world:getFurnace(x,y,z)==station)
station.slots[1]=stack(13,2)
station.slots[2]=stack(263,1)
eq(world:updateFurnaces(3.5),0)
eq(station.progress,3.5)
eq(station.burn,76.5)
assert(not world:set(x,y,z,0),
 'Não pode destruir fornalha ainda cheia e perder itens')
local p={x=0,y=80,z=0,yaw=0,pitch=0,health=20,hunger=20,
 saturation=5,exhaustion=0}
assert(world:save(p,inv))
local restored=World.new({seed='furnace-beta',
 generatorVersion='beta181',savePath='worlds/furnaces.sav'})
eq(restored:get(x,y,z),51)
local loaded=restored:getFurnace(x,y,z)
assert(loaded)
eq(loaded.progress,3.5)
eq(loaded.burn,76.5)
eq(loaded.slots[1].count,2)
eq(loaded.slots[2],nil)
eq(restored:updateFurnaces(6.5),1)
eq(loaded.slots[3].id,265)
eq(loaded.slots[3].count,1)
-- Após retirar o restante dos itens, o bloco pode ser quebrado.
loaded.slots[1]=nil
loaded.slots[2]=nil
loaded.slots[3]=nil
assert(restored:set(x,y,z,0))
eq(restored:getFurnace(x,y,z),nil)
eq(restored.furnaces[x..','..y..','..z],nil)
-- Leitura sem registro de fornalha mantém blocos da fase anterior.
files['worlds/phase3legacy.sav']=('PLAYER 0.000 80.000 0.000 0.000000 0.000000\n'..
 'BLOCK 5 112 7 51\n')
local old=World.new({seed='phase3',generatorVersion='beta181',
 savePath='worlds/phase3legacy.sav'})
assert(old:getFurnace(x,y,z) and old:getFurnace(x,y,z):isEmpty())
local classic=World.new({seed='classic',generatorVersion='classic030'})
eq(classic:getFurnace(x,y,z),nil)
-- Zonas do mouse usam a mesma geometria desenhada na UI.
local section,slot=UI.inventoryHit('furnace',460,211,1280,720)
eq(section,'furnace')
eq(slot,1)
section,slot=UI.inventoryHit('furnace',460,279,1280,720)
eq(section,'furnace')
eq(slot,2)
section,slot=UI.inventoryHit('furnace',738,244,1280,720)
eq(section,'furnace')
eq(slot,3)
section,slot=UI.inventoryHit('furnace',420,543,1280,720)
eq(section,'inventory')
eq(slot,1)
print('beta181_furnace: OK')
