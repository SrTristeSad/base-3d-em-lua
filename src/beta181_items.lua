-- Inventário provisório de blocos para os primeiros testes Beta 1.8.1.
-- NÃO representa ainda os 36 slots, crafting, fome e ferramentas originais.
-- Separado de Classic para não aplicar pontuação/TNT de Survival Test à Beta.
local Beta={}
Beta.__index=Beta
Beta.MAX_ID=49
Beta.MAX_STACK=64
Beta.DROPS={
 [1]=2,[2]=2,[3]=10,[4]=4,[5]=5,[6]=6,[7]=7,[8]=8,
 [10]=10,[11]=11,[12]=12,[13]=13,[14]=14,[15]=15,
 [16]=16,[17]=17,[18]=18,[19]=19,[20]=20,[21]=21,
 [22]=22,[23]=23,[24]=24,[25]=25,[26]=26,[27]=27,[28]=28,
 [31]=31,[32]=32,[33]=33,[34]=34,[35]=35,[36]=36,
 [37]=37,[38]=38,[39]=39,[40]=40,[41]=41,[42]=42,
 [43]=43,[44]=44,[45]=45,[46]=46,[47]=47,[48]=48,[49]=49
}
local function valid(id)
 return type(id)=='number' and id==math.floor(id)
    and id>=1 and id<=Beta.MAX_ID
end
function Beta.new(mode,items)
 local self=setmetatable({mode=mode=='creative' and 'creative' or 'survival',
  items={},score=0,profile='beta181'},Beta)
 if items then
  for id,count in pairs(items) do
   id,count=tonumber(id),tonumber(count)
   if valid(id) and type(count)=='number' and count==count and count>=0 then
    self.items[id]=math.min(self.MAX_STACK,math.floor(count))
   end
  end
 end
 return self
end
function Beta:canMine(id)
 return valid(id) and id~=9 and id~=29 and id~=30
end
function Beta:grant(id,amount)
 if self.mode=='creative' then return true end
 if not valid(id) then return false end
 amount=math.floor(tonumber(amount) or 0)
 if amount<=0 then return false end
 self.items[id]=math.min(self.MAX_STACK,(self.items[id] or 0)+amount)
 return true
end
function Beta:mine(id)
 if not self:canMine(id) then return false end
 if self.mode=='survival' then
  local drop=self.DROPS[id]
  if drop then self:grant(drop,1) end
 end
 return true
end
function Beta:canPlace(id)
 if not valid(id) then return false end
 return self.mode=='creative' or (self.items[id] or 0)>0
end
function Beta:place(id)
 if not self:canPlace(id) then return false end
 if self.mode=='survival' then self.items[id]=self.items[id]-1 end
 return true
end
function Beta:refund(id) return self:grant(id,1) end
function Beta:award() end
function Beta:count(id)
 if self.mode=='creative' then return nil end
 return self.items[id] or 0
end
-- Fome e alimentação serão introduzidas com o sistema real de itens.
function Beta:eat() return false end
return Beta
