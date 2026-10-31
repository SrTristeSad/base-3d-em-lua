-- Fornalha independente da reconstrução Beta 1.8.1.
-- Todas as durações são em segundos do jogo a 20 ticks/s:
-- uma operação = 200 ticks; carvão = 1600 ticks.
local Furnace={}
Furnace.__index=Furnace
Furnace.SECONDS_PER_ITEM=10
Furnace.fuels={
 [263]=80, -- carvão
 [4]=15,   -- tronco
 [7]=15,   -- tábuas
 [280]=5,  -- graveto
 [50]=15   -- bancada de trabalho
}
Furnace.recipes={
 [12]=266, -- minério de ouro -> lingote
 [13]=265, -- minério de ferro -> lingote
 [6]=16,   -- areia -> vidro (IDs internos do motor)
 [319]=320,-- porco cru -> cozido
 [363]=364,-- carne bovina crua -> bife
 [365]=366 -- frango cru -> assado
}
local min,max=math.min,math.max
local function validStack(s)
 return type(s)=='table' and type(s.id)=='number'
   and s.id>=1 and s.id%1==0
   and type(s.count)=='number' and s.count>=1 and s.count<=64
   and s.count%1==0
end
local function consume(slots,index)
 local s=slots[index]
 if not s then return end
 s.count=s.count-1
 if s.count<=0 then slots[index]=nil end
end
function Furnace.new(saved)
 local self=setmetatable({slots={},burn=0,burnTotal=0,progress=0},Furnace)
 if type(saved)=='table' then
  for i=1,3 do
   local s=saved.slots and saved.slots[i]
   if validStack(s) then self.slots[i]={id=s.id,count=s.count,
     damage=max(0,math.floor(s.damage or 0))} end
  end
  self.burn=max(0,min(1000,tonumber(saved.burn) or 0))
  self.burnTotal=max(0,min(1000,tonumber(saved.burnTotal) or 0))
  self.progress=max(0,min(self.SECONDS_PER_ITEM,tonumber(saved.progress) or 0))
 end
 return self
end
function Furnace.accepts(index,id)
 if index==1 then return Furnace.recipes[id]~=nil end
 if index==2 then return Furnace.fuels[id]~=nil end
 return false
end
function Furnace:outputId()
 local input=self.slots[1]
 return input and self.recipes[input.id] or nil
end
function Furnace:canSmelt()
 local id=self:outputId()
 if not id then return false end
 local output=self.slots[3]
 return not output or (output.id==id and output.count<64)
end
function Furnace:isEmpty()
 return self.slots[1]==nil and self.slots[2]==nil
   and self.slots[3]==nil
end
function Furnace:burnRatio()
 return self.burnTotal>0 and min(1,self.burn/self.burnTotal) or 0
end
function Furnace:progressRatio()
 return min(1,self.progress/self.SECONDS_PER_ITEM)
end
function Furnace:update(dt)
 if type(dt)~='number' or dt~=dt or dt<=0 then return 0 end
 dt=min(dt,3600) -- não simular dias em um único frame corrompido
 local crafted=0
 local iterations=0
 while dt>0.000001 and iterations<1000 do
  iterations=iterations+1
  local can=self:canSmelt()
  if self.burn<=0 then
   if not can then self.progress=0;break end
   local fuel=self.slots[2]
   local seconds=fuel and self.fuels[fuel.id]
   if not seconds then self.progress=0;break end
   consume(self.slots,2)
   self.burn=seconds
   self.burnTotal=seconds
  end
  can=self:canSmelt()
  local untilDone=can and (self.SECONDS_PER_ITEM-self.progress) or dt
  local step=min(dt,self.burn,untilDone)
  if step<=0 then
   if not can then break end
   -- arredondamento: completa uma operação ao atingir a duração
   step=0
  end
  dt=dt-step
  self.burn=max(0,self.burn-step)
  if can then
   self.progress=self.progress+step
   if self.progress+0.000001>=self.SECONDS_PER_ITEM then
    local result=self:outputId()
    local output=self.slots[3]
    if not output then self.slots[3]={id=result,count=1,damage=0}
    else output.count=output.count+1 end
    consume(self.slots,1)
    self.progress=0
    crafted=crafted+1
   end
  else
   self.progress=0
  end
  -- Versão Beta: interrupção por falta de combustível perde progresso;
  -- o comportamento de manter progresso é de versões posteriores.
  if self.burn<=0 and self.progress>0 then self.progress=0 end
  if step==0 then break end
 end
 return crafted
end
-- Slot de saída tem retirada controlada: não permite inserir por mouse.
function Furnace:takeOutput(inventory,button,shift)
 local out=self.slots[3]
 if not out or not inventory then return false end
 if shift then
  if inventory.cursor then return false end
  local before=out.count
  local _,remaining=inventory:insert(out.id,out.count)
  local taken=before-remaining
  if taken<=0 then return false end
  if remaining==0 then self.slots[3]=nil else out.count=remaining end
  return true
 end
 if button~=1 and button~=2 then return false end
 local held=inventory.cursor
 if held and (held.id~=out.id or held.damage~=nil and held.damage~=0) then
  return false
 end
 local limit=64-(held and held.count or 0)
 if limit<=0 then return false end
 local count=min(out.count,button==2 and 1 or limit,limit)
 if count<=0 then return false end
 if held then held.count=held.count+count
 else inventory.cursor={id=out.id,count=count,damage=0} end
 out.count=out.count-count
 if out.count<=0 then self.slots[3]=nil end
 return true
end
return Furnace
