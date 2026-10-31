-- Mecanicas essenciais do Survival Test / Creative 0.30, sem assets proprietarios.
local Classic={}
Classic.__index=Classic
Classic.MAX_STACK=99
Classic.MAX_ID=46
Classic.MODES={survival=true,creative=true}
-- Preserva o mapeamento original dos oito blocos do prototipo.
-- Drops adaptados aos materiais historicos do Survival Test.
Classic.DROPS={
 [1]=2,[2]=2,[3]=10,[4]=7,[5]=28,[6]=6,[7]=7,[8]=8,
 [10]=10,[11]=11,[12]=18,[13]=19,[14]=23,[15]=15,
 [16]=16,[17]=17,[18]=18,[19]=19,[20]=20,[21]=21,
 [22]=10,[23]=23,[24]=24,[25]=25,[26]=26,[27]=27,[28]=28
}
for id=31,46 do Classic.DROPS[id]=id end
local function validItem(id)
 return type(id)=='number' and id==math.floor(id) and id>=1 and id<=Classic.MAX_ID
end
function Classic.new(mode,items,score)
 if not Classic.MODES[mode] then mode='survival' end
 local self=setmetatable({mode=mode,items={},
  score=math.max(0,math.floor(tonumber(score) or 0))},Classic)
 if type(items)=='table' then
  for id,count in pairs(items) do
   id,count=tonumber(id),tonumber(count)
   if validItem(id) and type(count)=='number' and count>=0
    and count==count then
    self.items[id]=math.min(Classic.MAX_STACK,math.floor(count))
   end
  end
 elseif mode=='survival' then
  -- O Classic Survival Test fornecia TNT inicial ao jogador.
  self.items[15]=10
 end
 return self
end
function Classic:canMine(id)
 return id~=0 and id~=9 and id~=29 and id~=30
end
function Classic:grant(id,amount)
 if self.mode=='creative' then return true end
 if not validItem(id) then return false end
 amount=math.floor(tonumber(amount) or 0)
 if amount<=0 then return false end
 self.items[id]=math.min(self.MAX_STACK,(self.items[id] or 0)+amount)
 return true
end
function Classic:mine(blockId)
 if not self:canMine(blockId) then return false end
 if self.mode=='creative' then return true end
 local drop=self.DROPS[blockId]
 if drop then self:grant(drop,1) end
 return true
end
function Classic:canPlace(id)
 if not validItem(id) then return false end
 if self.mode=='creative' then return true end
 return (self.items[id] or 0)>0
end
function Classic:place(id)
 if not self:canPlace(id) then return false end
 if self.mode=='survival' then self.items[id]=self.items[id]-1 end
 return true
end
function Classic:refund(id)
 if self.mode=='survival' then return self:grant(id,1) end
 return true
end
function Classic:award(points)
 if self.mode~='survival' then return end
 self.score=self.score+math.max(0,math.floor(tonumber(points) or 0))
end
function Classic:count(id)
 if self.mode=='creative' then return nil end
 return self.items[id] or 0
end
function Classic:eat(player)
 if self.mode~='survival' or not player or player.health<=0 or
   player.health>=player.maxHealth then return false end
 local id=(self.items[26] or 0)>0 and 26 or
   ((self.items[27] or 0)>0 and 27 or nil)
 if not id then return false end
 self.items[id]=self.items[id]-1
 player.health=math.min(player.maxHealth,player.health+(id==26 and 5 or 3))
 return true
end
return Classic
