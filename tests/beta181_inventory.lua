-- Inventário de 36 espaços e receitas Beta 1.8.1, sem GPU.
package.path='./?.lua;./?/init.lua;'..package.path
local files={}
lovr={filesystem={
 read=function(name) return files[name] end,
 write=function(name,data) files[name]=data;return true end,
 isFile=function(name) return files[name]~=nil end
}}
local Beta=require('src.beta181_items')
local Recipes=require('src.beta181_crafting')
local World=require('src.world')
local UI=require('src.ui')
local function eq(a,b,msg) assert(a==b,(msg or 'Valor diferente')..
 ' esperado '..tostring(b)..' recebeu '..tostring(a)) end
local inv=Beta.new('survival')
eq(inv.SLOT_COUNT,36)
eq(inv.HOTBAR_COUNT,9)
assert(inv:grant(4,2) and inv:count(4)==2)
assert(inv:getSlot(1).count==2)
assert(inv:clickSlot('inventory',1,1,false))
eq(inv.cursor.count,2)
assert(inv:clickSlot('small',1,2,false))
assert(inv:clickSlot('small',1,2,false))
eq(inv.cursor,nil)
local prev,recipe=inv:preview('small')
eq(prev.id,7)
eq(prev.count,4)
eq(recipe,'Tábuas')
assert(inv:takeOutput('small',false))
eq(inv.cursor.id,7)
eq(inv.cursor.count,4)
eq(inv.craft2[1].count,1,
 'Fabricar com dois troncos deve consumir apenas um')
assert(inv:clickSlot('inventory',2,1,false)) -- guardar 4 tábuas
assert(inv:clickSlot('small',1,1,false)) -- pegar tronco restante
assert(inv:clickSlot('inventory',1,1,false))
eq(inv.craft2[1],nil)
eq(inv:getSlot(2).count,4)
-- Divide pilhas: 4 tábuas -> 2 na mão, 2 no slot.
assert(inv:clickSlot('inventory',2,2,false))
eq(inv.cursor.count,2)
eq(inv:getSlot(2).count,2)
assert(inv:clickSlot('small',1,2,false))
assert(inv:clickSlot('small',3,2,false))
eq(inv.cursor,nil)
eq(inv:preview('small').id,280)
assert(inv:takeOutput('small',true),'Shift-click deve fabricar gravetos')
eq(inv:count(280),4)
eq(inv.craft2[1],nil)
eq(inv.craft2[3],nil)
-- Constrói bancada 2x2 usando quatro tábuas.
assert(inv:grant(7,2))
local stacks=inv.slots
local index
for i=1,36 do if stacks[i] and stacks[i].id==7 then
 index=i;break end end
assert(index)
assert(inv:clickSlot('inventory',index,1,false))
eq(inv.cursor.count,4)
for i=1,4 do assert(inv:clickSlot('small',i,2,false)) end
eq(inv.cursor,nil)
eq(inv:preview('small').id,50)
assert(inv:takeOutput('small',false))
eq(inv.cursor.id,50)
assert(inv:clickSlot('inventory',3,1,false))
eq(inv:getSlot(3).id,50)
assert(inv:place(50,3))
eq(inv:getSlot(3),nil)
-- O 3x3 permite picaretas; o 2x2 não.
inv.craft3[1]={id=7,count=1}
inv.craft3[2]={id=7,count=1}
inv.craft3[3]={id=7,count=1}
inv.craft3[5]={id=280,count=1}
inv.craft3[8]={id=280,count=1}
eq(inv:preview('small'),nil)
eq(inv:preview('table').id,270)
assert(inv:takeOutput('table',false))
eq(inv.cursor.id,270)
eq(inv.cursor.count,1)
assert(inv:clickSlot('inventory',6,1,false))
eq(inv:getSlot(6).id,270)
assert(not inv:canPlace(270),'Ferramentas não são blocos')
assert(inv:grant(270,2))
local picks=0
for i=1,36 do
 local stack=inv.slots[i]
 if stack and stack.id==270 then
  eq(stack.count,1,'Ferramentas não empilham')
  picks=picks+1
 end
end
eq(picks,3)
-- Troca, fusão, divisão e Shift entre mochila e barra rápida.
local transfer=Beta.new('survival')
assert(transfer:grant(4,64))
eq(transfer:getSlot(1).count,64)
assert(transfer:shiftClick('inventory',1))
eq(transfer:getSlot(1),nil)
eq(transfer:getSlot(10).count,64)
assert(transfer:shiftClick('inventory',10))
eq(transfer:getSlot(1).count,64)
assert(transfer:grant(4,130))
eq(transfer:count(4),194)
assert(transfer:getSlot(2).count==64 and transfer:getSlot(3).count==64)
local before=transfer:count(4)
assert(transfer:clickSlot('inventory',2,1,false))
assert(transfer:clickSlot('inventory',5,1,false))
eq(transfer:count(4),before)
-- Não cria itens ao tentar tirar crafting com inventário lotado.
local full=Beta.new('survival')
for i=1,36 do full.slots[i]={id=270,count=1} end
full.craft2[1]={id=4,count=1}
eq(full:capacity(7),0)
assert(not full:takeOutput('small',true))
eq(full.craft2[1].count,1)
-- Grids/cursor e disposição dos slots persistem entre jogos.
local world=World.new({seed='inventory-save',generatorVersion='beta181',
 savePath='worlds/inventory-test.sav'})
inv.craft2[1]={id=7,count=2}
inv.craft3[2]={id=280,count=3}
inv.cursor={id=263,count=8}
local ok=world:save({x=1,y=65,z=1,yaw=0,pitch=0},inv)
assert(ok)
local restored=World.new({seed='inventory-save',
 generatorVersion='beta181',savePath='worlds/inventory-test.sav'})
local recovered=Beta.new(restored.savedMode,{
 slots=restored.savedSlots or {},
 craft2=restored.savedCraft2,
 craft3=restored.savedCraft3,
 cursor=restored.savedCursor
})
eq(recovered:getSlot(6).id,270)
eq(recovered.craft2[1].count,2)
eq(recovered.craft3[2].count,3)
eq(recovered.cursor.id,263)
eq(recovered.cursor.count,8)
assert(recovered:close()==nil)
eq(recovered.cursor,nil)
eq(recovered.craft2[1],nil)
eq(recovered.craft3[2],nil)
eq(recovered:count(263),8)
assert(not UI.inventoryHit('playing',420,543,1280,720))
local section,slot=UI.inventoryHit('inventory',420,543,1280,720)
eq(section,'inventory')
eq(slot,1)
section,slot=UI.inventoryHit('inventory',400,205,1280,720)
eq(section,'small')
eq(slot,1)
section,slot=UI.inventoryHit('workbench',400,191,1280,720)
eq(section,'table')
eq(slot,1)
section,slot=UI.inventoryHit('inventory',728,242,1280,720)
eq(section,'output')
print('beta181_inventory: OK')
