-- Fase 3: desgaste, tempo de mineração, fome e saves Beta 1.8.1.
-- Testes puros Lua; sem janela, GPU ou assets Mojang.
package.path='./?.lua;./?/init.lua;'..package.path
local files={}
lovr={filesystem={
 read=function(path) return files[path] end,
 write=function(path,data) files[path]=data;return true end,
 isFile=function(path) return files[path]~=nil end,
 createDirectory=function() return true end
},system={isKeyDown=function() return false end}}
local Rules=require('src.beta181_survival')
local Beta=require('src.beta181_items')
local World=require('src.world')
local Player=require('src.player')
local function eq(a,b,label)
 assert(a==b,(label or 'diferente')..': '..tostring(a)..' ~= '..tostring(b))
end
-- Tempo e requisitos de ferramentas.
assert(Rules.breakSeconds(3,270)<Rules.breakSeconds(3,nil))
assert(Rules.breakSeconds(3,274)<Rules.breakSeconds(3,270))
assert(Rules.breakSeconds(47,257)<Rules.breakSeconds(47,270))
assert(Rules.breakSeconds(30,nil)==math.huge)
assert(Rules.canHarvest(3,270))
assert(not Rules.canHarvest(3,nil))
assert(not Rules.canHarvest(13,270)) -- ferro exige pedra
assert(Rules.canHarvest(13,274))
assert(not Rules.canHarvest(47,274)) -- diamante exige ferro
assert(Rules.canHarvest(47,257))
eq(Rules.maxDurability(270),59)
eq(Rules.maxDurability(274),131)
eq(Rules.maxDurability(257),250)
-- Inventario sem ferramenta: pedra quebra mas nao dropa.
local bare=Beta.new('survival')
assert(bare:mine(3,1) and bare:count(10)==0)
assert(bare:grant(270,1))
assert(bare:mine(3,1) and bare:count(10)==1)
eq(bare:getSlot(1).damage,1)
assert(bare:mine(13,1) and bare:count(13)==0)
assert(bare:mine(47,1) and bare:count(264)==0)
eq(bare:getSlot(1).damage,3)
-- Ferramenta se quebra na durabilidade definida.
bare.slots[1]={id=270,count=1,damage=58}
assert(bare:wearTool(1,1))
eq(bare:getSlot(1),nil)
assert(bare:grant(274,1))
-- 274 agora encontra o primeiro slot vazio, com dano inicial zero.
eq(bare:getSlot(1).damage,0)
-- Copiar/salvar/restaurar não pode reparar ferramentas danificadas.
bare.slots[1]={id=274,count=1,damage=87}
assert(bare:clickSlot('inventory',1,1,false))
eq(bare.cursor.damage,87)
assert(bare:clickSlot('inventory',9,1,false))
eq(bare:getSlot(9).damage,87)
assert(bare:shiftClick('inventory',9))
eq(bare:getSlot(10).damage,87)
-- Comida repara fome, mas não cura vida imediatamente.
local world=World.new({seed='survival-beta-181',generatorVersion='beta181',
 savePath='worlds/phase3.sav'})
local player=Player.new(world)
player.health=12
player.hunger=14
player.saturation=0
local food=Beta.new('survival')
assert(food:grant(319,2)) -- dois porcos crus
local slot=1
assert(player:beginEating(food))
assert(not player:updateEating(.8,food,true))
eq(player.hunger,14)
assert(not player:updateEating(.5,food,false),'soltar cancela alimento')
eq(player.hunger,14)
eq(food:getSlot(slot).count,2)
assert(player:beginEating(food))
assert(not player:updateEating(.81,food,true))
assert(player:updateEating(.80,food,true))
eq(player.hunger,17)
eq(player.health,12)
eq(food:getSlot(slot).count,1)
assert(player.hunger<20,'Ainda ha fome apos um alimento')
-- A fome usa saturacao antes de gastar pontos visiveis.
player.hunger=18
player.saturation=1
player.exhaustion=0
Rules.consumeExhaustion(player,4)
eq(player.saturation,0)
eq(player.hunger,18)
Rules.consumeExhaustion(player,4)
eq(player.hunger,17)
assert(Rules.eat(player,319))
eq(player.hunger,20)
assert(not Rules.eat(player,319),'não comer com fome cheia')
-- Regenera com fome >=18; fome zero da dano até um HP em modo normal.
player.health=12
player.hunger=20
player.saturation=5
player.foodTimer=0
Rules.tick(player,4.2)
eq(player.health,13)
player.health=4
player.hunger=0
player.foodTimer=0
Rules.tick(player,24)
eq(player.health,1)
-- Minerar exige segurar o botao e olhar para o mesmo alvo.
local testPlayer=Player.new(world)
local minedBlock=3
local target={x=4,y=71,z=8,id=3}
local fake={
 get=function(_,x,y,z) if x==4 and y==71 and z==8 then return minedBlock end return 0 end,
 set=function(_,x,y,z,id)
  if x==4 and y==71 and z==8 and id==0 and minedBlock==3 then
   minedBlock=0;return true
  end
  return false
 end
}
testPlayer.raycast=function() return minedBlock~=0 and target or nil end
local inv=Beta.new('survival')
assert(inv:grant(270,1))
local seconds=Rules.breakSeconds(3,270)
assert(not testPlayer:updateMining(seconds*.6,fake,inv,true))
assert(testPlayer:miningFraction()>.5)
assert(not testPlayer:updateMining(.01,fake,inv,false))
eq(testPlayer:miningFraction(),0)
assert(not testPlayer:updateMining(seconds*.6,fake,inv,true))
assert(testPlayer:updateMining(seconds*.5,fake,inv,true))
eq(minedBlock,0)
eq(inv:count(10),1)
eq(inv:getSlot(1).damage,1)
eq(testPlayer:miningFraction(),0)
assert(not testPlayer:updateMining(1,fake,inv,true))
-- Salvar a condição da picareta, o inventário e os quatro valores de fome.
testPlayer.health=16
testPlayer.hunger=8
testPlayer.saturation=1.25
testPlayer.exhaustion=2.625
inv.slots[1].damage=42
assert(world:save(testPlayer,inv))
local restored=World.new({seed='survival-beta-181',
 generatorVersion='beta181',savePath='worlds/phase3.sav'})
assert(restored.savedStatus)
eq(restored.savedStatus.health,16)
eq(restored.savedStatus.hunger,8)
eq(restored.savedStatus.saturation,1.25)
eq(restored.savedStatus.exhaustion,2.625)
eq(restored.savedSlots[1].id,270)
eq(restored.savedSlots[1].damage,42)
local loaded=Beta.new('survival',{slots=restored.savedSlots})
eq(loaded:getSlot(1).damage,42)
eq(Player.new(restored).hunger,8)
-- Leitura de save Phase 2, sem campos extras.
files['worlds/oldphase2.sav']='PLAYER 1.000 64.000 1.000 0.000000 0.000000\nSLOT 1 270 1\n'
local legacy=World.new({seed='old',generatorVersion='beta181',
 savePath='worlds/oldphase2.sav'})
eq(legacy.savedSlots[1].damage,0)
eq(Player.new(legacy).hunger,20)
print('beta181_survival: OK')
