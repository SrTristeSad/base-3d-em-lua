-- Simulacao deterministica e limitada de fluidos para o perfil Beta 1.8.1.
-- IDs internos: agua=9, lava=29, pedra=3, pedregulho=10, obsidiana=22.
-- Fontes naturais ficam paradas ate uma edicao proxima reativar a regiao.
local Fluids={}
Fluids.__index=Fluids
Fluids.WATER=9
Fluids.LAVA=29
Fluids.DELAY={[9]=.25,[29]=1.5}
Fluids.REACH={[9]=7,[29]=3}
local floor=math.floor
local DIRS={{1,0,0},{-1,0,0},{0,0,1},{0,0,-1}}
local function key(x,y,z) return x..','..y..','..z end
local function fluid(id) return id==9 or id==29 end
function Fluids.new(world)
 return setmetatable({world=world,states={},
  queues={[9]={},[29]={}},pending={[9]={},[29]={}},
  heads={[9]=1,[29]=1},clock={[9]=0,[29]=0},
  changed=0,processed=0,activeLimit=48},Fluids)
end
function Fluids:get(x,y,z)
 return self.states[key(x,y,z)]
end
function Fluids:stateEqual(a,b)
 return a and b and a.id==b.id and a.level==b.level
    and a.falling==b.falling
end
function Fluids:setState(x,y,z,id,meta)
 local k=key(x,y,z)
 if fluid(id) and meta then
  self.states[k]={id=id,level=meta.level,
    falling=not not meta.falling}
 else
  self.states[k]=nil
 end
end
function Fluids:restore(x,y,z,id,level,falling)
 if not self.world:within(x,y,z) or not fluid(id)
  or type(level)~='number' or level<0 or
    level>self.REACH[id] or level~=floor(level) then return false end
 self:setState(x,y,z,id,{level=level,falling=falling})
 return true
end
function Fluids:resume()
 for k,meta in pairs(self.states) do
  local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  x,y,z=tonumber(x),tonumber(y),tonumber(z)
  if self.world.edits[k]==meta.id then
   self:schedule(x,y,z,meta.id)
  else
   self.states[k]=nil
  end
 end
end
function Fluids:schedule(x,y,z,id)
 if not self.world:within(x,y,z) then return false end
 id=id or self.world:get(x,y,z)
 if not fluid(id) then return false end
 local k=key(x,y,z)
 if self.pending[id][k] then return false end
 self.pending[id][k]=true
 local q=self.queues[id]
 q[#q+1]={x,y,z,k}
 return true
end
function Fluids:onBlockChanged(x,y,z,oldId,newId)
 if fluid(oldId) or fluid(newId) then
  if fluid(newId) then self:schedule(x,y,z,newId) end
 end
 -- Reagir a edicoes de qualquer bloco, pois uma parede pode abrir
 -- uma passagem ou destruir o suporte de uma corrente.
 local around={{0,1,0},{0,-1,0},
  {1,0,0},{-1,0,0},{0,0,1},{0,0,-1}}
 for _,d in ipairs(around) do
  local nx,ny,nz=x+d[1],y+d[2],z+d[3]
  if self.world:within(nx,ny,nz) then
   self:schedule(nx,ny,nz)
  end
 end
end
local function replaceable(id)
 return id==0 or (id>=24 and id<=28)
end
function Fluids:touchesWater(x,y,z)
 local around={{0,1,0},{1,0,0},{-1,0,0},
  {0,0,1},{0,0,-1}}
 for _,d in ipairs(around) do
  local nx,ny,nz=x+d[1],y+d[2],z+d[3]
  if self.world:within(nx,ny,nz) and
     self.world:get(nx,ny,nz)==9 then return true end
 end
 return false
end
function Fluids:trySpread(x,y,z,id,level,falling,fromAbove)
 if not self.world:within(x,y,z) or y==self.world.YMIN then
  return false
 end
 local other=self.world:get(x,y,z)
 if (id==9 and other==29) then
  local target=self:get(x,y,z)
  return self.world:set(x,y,z,target and 10 or 22)
 elseif id==29 and other==9 then
  -- Queda de lava sobre agua forma pedra; contato lateral,
  -- pedregulho. Estes resultados usam IDs do catalogo interno.
  return self.world:set(x,y,z,fromAbove and 3 or 10)
 end
 if replaceable(other) then
  return self.world:set(x,y,z,id,{level=level,falling=falling})
 end
 if other~=id then return false end
 local previous=self:get(x,y,z)
 if not previous then return false end -- nao substituir uma fonte
 if falling and not previous.falling then
  return self.world:set(x,y,z,id,{level=0,falling=true})
 end
 if not falling and not previous.falling and level<previous.level then
  return self.world:set(x,y,z,id,{level=level,falling=false})
 end
 return false
end
function Fluids:recalculate(x,y,z,id,state)
 local world=self.world
 local reach=self.REACH[id]
 if world:within(x,y+1,z) and world:get(x,y+1,z)==id then
  return {level=0,falling=true}
 end
 local best=reach+1
 for _,d in ipairs(DIRS) do
  local nx,nz=x+d[1],z+d[3]
  if world:within(nx,y,nz) and world:get(nx,y,nz)==id then
   local other=self:get(nx,y,nz)
   local level=other and (other.falling and 0 or other.level) or 0
   if level+1<best then best=level+1 end
  end
 end
 if best<=reach then return {level=best,falling=false} end
 return nil
end
function Fluids:process(x,y,z)
 local world=self.world
 local id=world:get(x,y,z)
 if not fluid(id) then return end
 local state=self:get(x,y,z)
 if id==29 and self:touchesWater(x,y,z) then
  world:set(x,y,z,state and 10 or 22)
  return
 end
 if state then
  local wanted=self:recalculate(x,y,z,id,state)
  if not wanted then
   world:set(x,y,z,0)
   return
  end
  if not self:stateEqual(state,{id=id,
     level=wanted.level,falling=wanted.falling}) then
   world:set(x,y,z,id,wanted)
   state=wanted
  end
 end
 if y>world.YMIN then
  local below=world:get(x,y-1,z)
  if replaceable(below) or (id==9 and below==29)
    or (id==29 and below==9) then
   self:trySpread(x,y-1,z,id,0,true,true)
   -- Prioridade vertical: nao criar uma frente lateral no ar.
   return
  end
 end
 local level=state and (state.falling and 0 or state.level) or 0
 local nextLevel=level+1
 if nextLevel>self.REACH[id] then return end
 for _,d in ipairs(DIRS) do
  self:trySpread(x+d[1],y,z+d[3],id,nextLevel,false,false)
 end
end
function Fluids:step(dt,budget)
 if type(dt)~='number' or dt~=dt or dt<=0 then return 0 end
 budget=math.max(1,math.floor(budget or self.activeLimit))
 local used=0
 for _,id in ipairs({9,29}) do
  -- Atrasos independentes: lava avanca mais devagar.
  self.clock[id]=self.clock[id]+math.min(dt,.5)
  if self.clock[id]>=self.DELAY[id] then
   self.clock[id]=self.clock[id]%self.DELAY[id]
   local queue=self.queues[id]
   local head=self.heads[id]
   -- Divida o orcamento para nao deixar a lava sem turnos.
   local quota=id==9 and math.ceil(budget*.65) or budget-used
   local limit=math.min(quota,budget-used,#queue-head+1)
   for _=1,limit do
    local entry=queue[head]
    head=head+1
    self.pending[id][entry[4]]=nil
    self:process(entry[1],entry[2],entry[3])
    used=used+1
   end
   if head>#queue then
    self.queues[id]={}
    self.heads[id]=1
   elseif head>256 and head>floor(#queue/2) then
    local remaining={}
    for i=head,#queue do remaining[#remaining+1]=queue[i] end
    self.queues[id]=remaining
    self.heads[id]=1
   else
    self.heads[id]=head
   end
  end
  if used>=budget then break end
 end
 self.processed=self.processed+used
 return used
end
function Fluids:pendingCount()
 local total=0
 for _,id in ipairs({9,29}) do
  total=total+#self.queues[id]-self.heads[id]+1
 end
 return total
end
return Fluids
