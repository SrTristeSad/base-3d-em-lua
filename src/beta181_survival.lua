-- Reconstrucao independente de regras Beta 1.8.1 para ferramentas e fome.
-- IDs do motor sao proprios: os blocos herdados do Classic nao usam os
-- mesmos numeros dos IDs oficiais Minecraft. Nao ha ativos Mojang.
local M={}
local max,min,ceil=math.max,math.min,math.ceil
M.tools={
 [270]={kind='pick',tier=0,speed=2,durability=59},
 [274]={kind='pick',tier=1,speed=4,durability=131},
 [257]={kind='pick',tier=2,speed=6,durability=250},
 [278]={kind='pick',tier=3,speed=8,durability=1561},
 [271]={kind='axe',tier=0,speed=2,durability=59},
 [275]={kind='axe',tier=1,speed=4,durability=131},
 [258]={kind='axe',tier=2,speed=6,durability=250},
 [279]={kind='axe',tier=3,speed=8,durability=1561},
 [269]={kind='shovel',tier=0,speed=2,durability=59},
 [273]={kind='shovel',tier=1,speed=4,durability=131},
 [256]={kind='shovel',tier=2,speed=6,durability=250},
 [277]={kind='shovel',tier=3,speed=8,durability=1561},
 [268]={kind='sword',tier=0,speed=1,durability=59},
 [272]={kind='sword',tier=1,speed=1,durability=131},
 [267]={kind='sword',tier=2,speed=1,durability=250},
 [276]={kind='sword',tier=3,speed=1,durability=1561}
}
-- Durezas representativas; outros blocos da base tem fallback conservador.
M.blocks={
 [1]={hardness=.6,kind='shovel'},[2]={hardness=.5,kind='shovel'},
 [3]={hardness=1.5,kind='pick',tier=0},[4]={hardness=2,kind='axe'},
 [5]={hardness=.2,kind='shears'},[6]={hardness=.5,kind='shovel'},
 [7]={hardness=2,kind='axe'},[8]={hardness=2,kind='pick',tier=0},
 [10]={hardness=2,kind='pick',tier=0},[11]={hardness=.6,kind='shovel'},
 [12]={hardness=3,kind='pick',tier=2},-- ouro exige ferro
 [13]={hardness=3,kind='pick',tier=1},-- ferro exige pedra
 [14]={hardness=3,kind='pick',tier=0},
 [15]={hardness=0,kind='any'},[16]={hardness=.3,kind='any'},
 [18]={hardness=3,kind='pick',tier=2},
 [19]={hardness=5,kind='pick',tier=1},
 [22]={hardness=50,kind='pick',tier=3},-- obsidiana
 [29]={hardness=-1},[30]={hardness=-1},-- lava/bedrock
 [47]={hardness=3,kind='pick',tier=2},
 [48]={hardness=3,kind='pick',tier=2},
 [49]={hardness=3,kind='pick',tier=1},
 [50]={hardness=2.5,kind='axe'},
 [51]={hardness=3.5,kind='pick',tier=0},
 [52]={hardness=0,kind='any'}
}
-- O numero de pontos de fome e a saturacao seguem a nomenclatura
-- de dois pontos por icone. Por exemplo porco cru = 3 pontos.
M.food={
 [260]={hunger=4,saturation=2.4},
 [297]={hunger=5,saturation=6},
 [319]={hunger=3,saturation=1.8},
 [320]={hunger=8,saturation=12.8},
 [363]={hunger=3,saturation=1.8},
 [364]={hunger=8,saturation=12.8},
 [365]={hunger=2,saturation=1.2},
 [366]={hunger=6,saturation=7.2}
}
M.EAT_SECONDS=1.6
local function data(block)
 return M.blocks[block] or {hardness=1,kind='any'}
end
function M.tool(id)
 return M.tools[id]
end
function M.foodData(id)
 return M.food[id]
end
function M.canHarvest(block,toolId)
 local b=data(block)
 if b.hardness<0 then return false end
 if not b.tier then return true end
 local tool=M.tools[toolId]
 return tool~=nil and tool.kind=='pick' and tool.tier>=b.tier
end
function M.breakSeconds(block,toolId,creative)
 if creative then return data(block).hardness<0 and math.huge or 0 end
 local b=data(block)
 if b.hardness<0 then return math.huge end
 if b.hardness==0 then return .05 end
 local tool=M.tools[toolId]
 local correct=tool and tool.kind==b.kind
 local speed=correct and tool.speed or 1
 -- Divisor 30 para ferramenta correta com tier suficiente,
 -- 100 para ferramenta errada/sem tier; 20 ticks por segundo.
 local can=M.canHarvest(block,toolId)
 local damagePerTick=correct and can and speed/(b.hardness*30)
   or 1/(b.hardness*100)
 return math.max(.05,1/(damagePerTick*20))
end
function M.maxDurability(id)
 return M.tools[id] and M.tools[id].durability or nil
end
function M.usesDurability(id) return M.tools[id]~=nil end
function M.consumeExhaustion(player,amount)
 if not player or type(amount)~='number' or amount<=0 then return end
 player.exhaustion=(player.exhaustion or 0)+amount
 while player.exhaustion>=4 do
  player.exhaustion=player.exhaustion-4
  if (player.saturation or 0)>0 then
   player.saturation=max(0,player.saturation-1)
  else
   player.hunger=max(0,(player.hunger or 20)-1)
  end
 end
end
function M.eat(player,foodId)
 local food=M.food[foodId]
 if not food or not player or (player.hunger or 20)>=20 then return false end
 player.hunger=min(20,(player.hunger or 20)+food.hunger)
 player.saturation=min(player.hunger,(player.saturation or 0)+food.saturation)
 return true
end
function M.tick(player,dt)
 if not player or player.health<=0 then return end
 if type(dt)~='number' or dt<=0 then return end
 player.foodTimer=(player.foodTimer or 0)+dt
 if player.foodTimer>=4 then
  -- Um pulso a cada 80 ticks: Beta 1.8 usa regeneracao somente
  -- com fome >= 18, e dano de fome em nivel 0.
  local pulses=math.floor(player.foodTimer/4)
  player.foodTimer=player.foodTimer-pulses*4
  for _=1,min(pulses,20) do
   if player.hunger>=18 and player.health<player.maxHealth then
    player.health=min(player.maxHealth,player.health+1)
    M.consumeExhaustion(player,3)
   elseif player.hunger==0 and player.health>1 then
    -- Dificuldade normal: fome sozinha nao mata.
    player.health=player.health-1
   end
  end
 end
end
return M
