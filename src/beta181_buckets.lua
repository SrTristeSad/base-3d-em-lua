-- Baldes da Beta 1.8.1. IDs de itens Java: vazio=325, agua=326, lava=327.
-- Mantem separada a logica de uso e as interacoes com o mouse.
local Buckets={}
Buckets.EMPTY=325
Buckets.WATER=326
Buckets.LAVA=327
local floor=math.floor
local function cell(v) return floor(v+.5) end
local function isBucket(id)
 return id==325 or id==326 or id==327
end
local function selected(player,inventory,hotbar)
 if not inventory or inventory.profile~='beta181' then return nil end
 if inventory.mode=='creative' then
  return hotbar and hotbar[player.selected] or nil
 end
 local stack=inventory:getSlot(player.selected)
 if not stack or stack.count~=1 then return nil end
 return stack.id
end
-- Primeira celula nao-vazia em uma linha de visada. A coordenada
-- anterior so pode ser usada se for ar, nunca se atravesse liquidos
-- ou paredes para colocar uma fonte atras deles.
function Buckets.target(player,world,range)
 local ox,oy,oz=player:eye()
 local dx,dy,dz=player:direction()
 local previous,seen=nil,nil
 for distance=0,range or 5,.06 do
  local x,y,z=cell(ox+dx*distance),
    cell(oy+dy*distance),cell(oz+dz*distance)
  local k=x..','..y..','..z
  if k~=seen then
   seen=k
   if not world:within(x,y,z) then return nil end
   local id=world:get(x,y,z)
   if id~=0 then
    return {x=x,y=y,z=z,id=id},previous
   end
   previous={x=x,y=y,z=z}
  end
 end
 return nil
end
local function intersectsPlayer(player,p)
 return math.abs(p.x-player.x)<.8 and
   math.abs(p.z-player.z)<.8 and
   p.y<player.y+1.8 and p.y>player.y-1
end
-- Retorno (handled,success): balde selecionado consome o clique
-- mesmo que a coleta ou colocacao nao tenha sido possivel.
function Buckets.use(world,player,inventory,hotbar)
 if not world or world.generatorVersion~='beta181' or
    not player or not inventory then return false,false end
 local id=selected(player,inventory,hotbar)
 if not isBucket(id) then return false,false end
 local creative=inventory.mode=='creative'
 local target,previous=Buckets.target(player,world,5)
 if not target then return true,false end
 if id==325 then
  -- Balde vazio precisa de fonte de agua ou lava, nao de corrente.
  if creative or (target.id~=9 and target.id~=29) then
   return true,false
  end
  if world.fluids and world.fluids:get(target.x,target.y,target.z) then
   return true,false
  end
  if not inventory:canReplaceBucket(player.selected,id) then
   return true,false
  end
  if not world:set(target.x,target.y,target.z,0) then return true,false end
  local filled=target.id==9 and 326 or 327
  -- A substituicao nao pode falhar apos a checagem, mas em caso
  -- de estado externo inconsistente preservamos o fluido.
  if not inventory:replaceBucket(player.selected,id,filled) then
   world:set(target.x,target.y,target.z,target.id)
   return true,false
  end
  return true,true
 end
 if target.id==9 or target.id==29 or not previous or
    not world:within(previous.x,previous.y,previous.z) or
    intersectsPlayer(player,previous) or
    world:get(previous.x,previous.y,previous.z)~=0 then
  return true,false
 end
 if not creative and not inventory:canReplaceBucket(player.selected,id) then
  return true,false
 end
 local block=id==326 and 9 or 29
 if not world:set(previous.x,previous.y,previous.z,block) then
  return true,false
 end
 if not creative and not inventory:replaceBucket(player.selected,id,325) then
  world:set(previous.x,previous.y,previous.z,0)
  return true,false
 end
 return true,true
end
return Buckets
