-- Inventário Beta 1.8.1: 9 hotbar + 27 espaços, cursor e crafting 2x2/3x3.
-- IDs de blocos do protótipo permanecem estáveis; novos itens utilizam
-- IDs de itens históricos da Java onde possível, sem recursos proprietários.
local Crafting=require('src.beta181_crafting')
local Rules=require('src.beta181_survival')
local Beta={}
Beta.__index=Beta
Beta.profile='beta181'
Beta.MAX_ID=52
Beta.MAX_STACK=64
Beta.SLOT_COUNT=36
Beta.HOTBAR_COUNT=9
Beta.labels={
 [1]='Grama',[2]='Terra',[3]='Rocha',[4]='Tronco',[5]='Folhas',
 [6]='Areia',[7]='Tábuas',[9]='Água',[10]='Pedregulho',
 [11]='Cascalho',[12]='Minério de ouro',[13]='Minério de ferro',
 [14]='Minério de carvão',[15]='TNT',[16]='Vidro',
 [29]='Lava',[30]='Rocha-mãe',[31]='Lã',[47]='Minério de diamante',
 [48]='Minério de redstone',[49]='Minério de lápis',
 [50]='Bancada de trabalho',[51]='Fornalha',[52]='Tocha',
 [263]='Carvão',[264]='Diamante',[280]='Graveto',
 [268]='Espada de madeira',[270]='Picareta de madeira',
 [271]='Machado de madeira',[272]='Espada de pedra',
 [274]='Picareta de pedra',[275]='Machado de pedra',
 [296]='Trigo',[297]='Pão',[319]='Porco cru',[320]='Porco assado',
 [266]='Lingote de ouro',[260]='Maçã',[256]='Pá de ferro',[257]='Picareta de ferro',
 [258]='Machado de ferro',[265]='Lingote de ferro',
 [267]='Espada de ferro',[269]='Pá de madeira',[273]='Pá de pedra',
 [276]='Espada de diamante',[277]='Pá de diamante',
 [278]='Picareta de diamante',[279]='Machado de diamante',
 [363]='Carne bovina crua',[364]='Bife',[365]='Frango cru',
 [366]='Frango assado',[367]='Carne podre',[331]='Redstone',[351]='Lápis-lazúli'
}
Beta.unstackable={}
for id in pairs(Rules.tools) do Beta.unstackable[id]=true end
Beta.DROPS={
 [1]=2,[3]=10,[14]=263,[47]=264,[48]=331,[49]=351
}
local function valid(id)
 return type(id)=='number' and id==math.floor(id)
   and id>=1 and (id<=Beta.MAX_ID or Beta.labels[id]~=nil)
end
local function copy(stack)
 if stack then return {id=stack.id,count=stack.count,damage=stack.damage or 0} end
end
local function stackLimit(id)
 return Beta.unstackable[id] and 1 or 64
end
local function array()
 local t={}
 return t
end
function Beta.new(mode,saved)
 local self=setmetatable({mode=mode=='creative' and 'creative' or 'survival',
  slots=array(),craft2=array(),craft3=array(),cursor=nil,score=0},Beta)
 if type(saved)=='table' then
  if type(saved.slots)=='table' then
   for i=1,36 do
    local stack=saved.slots[i]
    if type(stack)=='table' and valid(stack.id) and
      type(stack.count)=='number' and stack.count>=1 then
      self.slots[i]={id=stack.id,
        count=math.min(stackLimit(stack.id),math.floor(stack.count)),
        damage=math.min(65535,math.max(0,math.floor(tonumber(stack.damage) or 0)))}
    end
   end
   for _,key in ipairs({'craft2','craft3'}) do
    local width=key=='craft2' and 2 or 3
    for i=1,width*width do
     local stack=saved[key] and saved[key][i]
     if type(stack)=='table' and valid(stack.id) and
       type(stack.count)=='number' and stack.count>=1 then
      self[key][i]={id=stack.id,
        count=math.min(stackLimit(stack.id),math.floor(stack.count)),
        damage=math.min(65535,math.max(0,math.floor(tonumber(stack.damage) or 0)))}
     end
    end
   end
   if type(saved.cursor)=='table' and valid(saved.cursor.id)
      and type(saved.cursor.count)=='number' and saved.cursor.count>=1 then
    self.cursor={id=saved.cursor.id,
      count=math.min(stackLimit(saved.cursor.id),math.floor(saved.cursor.count)),
      damage=math.min(65535,math.max(0,math.floor(tonumber(saved.cursor.damage) or 0)))}
   end
  else
   -- Migração do inventário provisório de pilhas agrupadas por ID.
   local ids={}
   for id in pairs(saved) do
    if type(id)=='number' and valid(id) then ids[#ids+1]=id end
   end
   table.sort(ids)
   for _,id in ipairs(ids) do
    self:grant(id,saved[id])
   end
  end
 end
 return self
end
function Beta:label(id)
 return self.labels[id] or ('Item '..tostring(id or '?'))
end
function Beta:getSlot(index)
 if type(index)~='number' or index%1~=0
    or index<1 or index>36 then return nil end
 return self.slots[index]
end
function Beta:getGrid(which)
 return which=='table' and self.craft3 or self.craft2,
   which=='table' and 3 or 2
end
function Beta:getArea(section)
 if section=='inventory' then return self.slots,36 end
 if section=='small' then return self.craft2,4 end
 if section=='table' then return self.craft3,9 end
 if section=='furnace' and self.openFurnace then
   return self.openFurnace.slots,3
 end
 return nil,0
end
function Beta:count(id)
 if self.mode=='creative' then return nil end
 local total=0
 for i=1,36 do
  local s=self.slots[i]
  if s and s.id==id then total=total+s.count end
 end
 return total
end
function Beta:insert(id,amount,from,to,damage)
 if not valid(id) then return false,amount end
 amount=math.floor(tonumber(amount) or 0)
 if amount<=0 then return false,amount end
 from,to=from or 1,to or 36
 local remaining=amount
 local limit=stackLimit(id)
 for i=from,to do
  local s=self.slots[i]
  if s and s.id==id and s.count<limit and
     (not Beta.unstackable[id]) then
   local n=math.min(remaining,limit-s.count)
   s.count=s.count+n
   remaining=remaining-n
   if remaining==0 then return true,0 end
  end
 end
 for i=from,to do
  if not self.slots[i] then
   local n=math.min(remaining,limit)
   self.slots[i]={id=id,count=n,damage=damage or 0}
   remaining=remaining-n
   if remaining==0 then return true,0 end
  end
 end
 return remaining==0,remaining
end
function Beta:capacity(id)
 if not valid(id) then return 0 end
 local cap=0
 local maxStack=stackLimit(id)
 for i=1,36 do
  local s=self.slots[i]
  if not s then cap=cap+maxStack
  elseif s.id==id then cap=cap+maxStack-s.count end
 end
 return cap
end
function Beta:grant(id,amount)
 if self.mode=='creative' then return true,0 end
 return self:insert(id,amount)
end
function Beta:canMine(id)
 return valid(id) and id~=9 and id~=29 and id~=30
end
function Beta:mine(id,slot)
 if not self:canMine(id) then return false end
 if self.mode=='creative' then return true end
 local held=self:getSlot(slot or 1)
 local toolId=held and held.id or nil
 if Rules.canHarvest(id,toolId) then
  self:grant(self.DROPS[id] or id,1)
 end
 self:wearTool(slot or 1,1)
 return true
end
function Beta:wearTool(index,amount)
 if self.mode=='creative' then return false end
 local stack=self:getSlot(index)
 if not stack then return false end
 local durability=Rules.maxDurability(stack.id)
 if not durability then return false end
 stack.damage=(stack.damage or 0)+(amount or 1)
 if stack.damage>=durability then
  self.slots[index]=nil
  return true -- ferramenta se quebrou
 end
 return false
end
function Beta:toolDamage(index)
 local stack=self:getSlot(index)
 if not stack then return 0,nil end
 return stack.damage or 0,Rules.maxDurability(stack.id)
end
function Beta:consumeFood(index,player)
 if self.mode~='survival' then return false end
 local stack=self:getSlot(index)
 if not stack or not Rules.foodData(stack.id) then return false end
 if not Rules.eat(player,stack.id) then return false end
 self:consumeSlot(index,1)
 return true
end
function Beta:canPlace(id)
 return valid(id) and id<=self.MAX_ID and
   id~=9 and id~=29 and id~=30 and
   (self.mode=='creative' or self:count(id)>0)
end
function Beta:consumeSlot(index,count)
 if self.mode=='creative' then return true end
 local s=self:getSlot(index)
 count=count or 1
 if not s or s.count<count then return false end
 s.count=s.count-count
 if s.count==0 then self.slots[index]=nil end
 return true
end
function Beta:place(id,index)
 if not self:canPlace(id) then return false end
 if self.mode=='creative' then return true end
 if index then
  local s=self:getSlot(index)
  if not s or s.id~=id then return false end
  return self:consumeSlot(index,1)
 end
 for i=1,36 do
  local s=self.slots[i]
  if s and s.id==id then return self:consumeSlot(i,1) end
 end
 return false
end
function Beta:refund(id) return self:grant(id,1) end
function Beta:award() end
-- Retorna ingredientes da grade ao inventário quando houver espaço;
-- se estiver cheio, mantém itens na grade salva, sem excluí-los.
function Beta:close()
 if self.cursor and self:capacity(self.cursor.id)>=self.cursor.count then
  self:insert(self.cursor.id,self.cursor.count,nil,nil,self.cursor.damage)
  self.cursor=nil
 end
 for _,grid in ipairs({self.craft2,self.craft3}) do
  for i=1,9 do
   local s=grid[i]
   if s and self:capacity(s.id)>=s.count then
    self:insert(s.id,s.count,nil,nil,s.damage)
    grid[i]=nil
   end
  end
 end
end
local function validSlot(section,index)
 return section=='inventory' and index>=1 and index<=36
   or section=='small' and index>=1 and index<=4
   or section=='table' and index>=1 and index<=9
   or section=='furnace' and index>=1 and index<=3
end
function Beta:shiftClick(section,index)
 local area=self:getArea(section)
 local item=area and area[index]
 if not item then return false end
 if section=='inventory' then
  local from,to=index<=9 and 10 or 1,index<=9 and 36 or 9
  local before=item.count
  local _,left=self:insert(item.id,item.count,from,to,item.damage)
  if left==before then return false end
  if left==0 then area[index]=nil else item.count=left end
  return true
 end
 local _,left=self:insert(item.id,item.count,nil,nil,item.damage)
 if left==item.count then return false end
 if left==0 then area[index]=nil else item.count=left end
 return true
end
function Beta:clickSlot(section,index,button,shift)
 local area,size=self:getArea(section)
 if not area or type(index)~='number' or index%1~=0 or
   not validSlot(section,index) then return false end
 if button~=1 and button~=2 then return false end
 if section=='furnace' and index==3 then
   return self.openFurnace:takeOutput(self,button,shift)
 end
 if shift and not self.cursor then return self:shiftClick(section,index) end
 local current=area[index]
 local held=self.cursor
 if not held then
  if not current then return false end
  if button==1 then
   self.cursor=current
   area[index]=nil
  else
   local amount=math.ceil(current.count/2)
   self.cursor={id=current.id,count=amount,damage=current.damage or 0}
   current.count=current.count-amount
   if current.count==0 then area[index]=nil end
  end
  return true
 end
 if section=='furnace' and not self.openFurnace.accepts(index,held.id) then
  return false
 end
 if not current then
  local n=button==1 and held.count or 1
  area[index]={id=held.id,count=n,damage=held.damage or 0}
  held.count=held.count-n
  if held.count<=0 then self.cursor=nil end
  return true
 end
 if current.id==held.id then
  local maxStack=stackLimit(held.id)
  local n=math.min(maxStack-current.count,button==1 and held.count or 1)
  if n<=0 then return false end
  current.count=current.count+n
  held.count=held.count-n
  if held.count<=0 then self.cursor=nil end
  return true
 end
 if button==1 then
  area[index],self.cursor=held,current
  return true
 end
 return false
end
function Beta:preview(section)
 local grid,width=self:getGrid(section)
 local r=Crafting.match(grid,width)
 if r then return {id=r.output,count=r.count},r.name end
 return nil
end
function Beta:takeOutput(section,shift)
 local grid,width=self:getGrid(section)
 local crafted=0
 for _=1,64 do
  local r=Crafting.match(grid,width)
  if not r then break end
  if shift then
   if self:capacity(r.output)<r.count then break end
   self:insert(r.output,r.count)
  else
   if self.cursor and (self.cursor.id~=r.output or
       self.cursor.count+r.count>stackLimit(r.output)) then break end
   if self.cursor then self.cursor.count=self.cursor.count+r.count
   else self.cursor={id=r.output,count=r.count} end
  end
  Crafting.consume(grid,width)
  crafted=crafted+1
  if not shift then break end
 end
 return crafted>0,crafted
end
function Beta:eat(player,index) return self:consumeFood(index or 1,player) end
return Beta
