-- Regras originais da nossa referencia: Minecraft Classic 0.30.
-- Survival tem itens finitos (ate 99 por pilha), Creative e ilimitado.
-- Nao inclui nem copia codigo de Minecraft; roda em Lua comum.
local Classic = {}
Classic.__index = Classic
Classic.MAX_STACK=99
Classic.MODES={survival=true,creative=true}
-- O Survival Test converte alguns blocos em seus drops historicos:
-- grama -> terra, tronco -> tabuas, rocha -> pedra.
Classic.DROPS={
  [1]=2, [2]=2, [3]=3, [4]=7, [5]=5,
  [6]=6, [7]=7, [8]=8,
}
function Classic.new(mode,items,score)
  if not Classic.MODES[mode] then mode='survival' end
  local self=setmetatable({mode=mode,items={},score=math.max(0,math.floor(tonumber(score) or 0))},Classic)
  if type(items)=='table' then
    for id,count in pairs(items) do
      id=tonumber(id)
      count=tonumber(count)
      if id and id%1==0 and id>=1 and id<=8
        and count and count>=0 and count==count then
        self.items[id]=math.min(Classic.MAX_STACK,math.floor(count))
      end
    end
  end
  return self
end
function Classic:canPlace(id)
  if self.mode=='creative' then return true end
  return (self.items[id] or 0)>0
end
function Classic:mine(blockId)
  if self.mode=='creative' then return true end
  local item=Classic.DROPS[blockId]
  if not item then return true end
  self.items[item]=math.min(self.MAX_STACK,(self.items[item] or 0)+1)
  return true
end
function Classic:place(id)
  if self.mode=='creative' then return true end
  if not self:canPlace(id) then return false end
  self.items[id]=self.items[id]-1
  return true
end
function Classic:refund(id)
  if self.mode=='survival' and id then
    self.items[id]=math.min(self.MAX_STACK,(self.items[id] or 0)+1)
  end
end
function Classic:award(points)
  if self.mode~='survival' then return end
  self.score=self.score+math.max(0,math.floor(points or 0))
end
function Classic:count(id)
  if self.mode=='creative' then return nil end
  return self.items[id] or 0
end
return Classic
