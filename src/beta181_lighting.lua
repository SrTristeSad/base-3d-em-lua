-- Iluminacao e relogio do Overworld Beta 1.8.1.
-- Modelo independente, aproximado. 24000 ticks = 1200s.
-- Luz artificial por BFS; luz solar por colunas reais e difusao limitada.
local Lighting={}
Lighting.__index=Lighting
Lighting.TICKS_PER_DAY=24000
Lighting.TICKS_PER_SECOND=20
Lighting.INITIAL_TIME=1000
Lighting.EMITTERS={[52]=14,[29]=15}
local floor,max,min,abs=math.floor,math.max,math.min,math.abs
local function key(cx,cy,cz) return cx..':'..cy..':'..cz end
local function coord(x,y,z) return x..','..y..','..z end
local function clamp(x,a,b) return max(a,min(b,x)) end
function Lighting.new(world)
 return setmetatable({world=world,time=Lighting.INITIAL_TIME,day=0,
  buckets={},sources={},sourceCount=0,
  skyColumns={},skyColumnCount=0,skyCache={},skyCacheCount=0,
  skyCacheLimit=12000,skyColumnLimit=10000},Lighting)
end
function Lighting:setTime(value,day)
 if type(value)~='number' or value~=value or value==math.huge
    or value==-math.huge then return false end
 self.time=value%self.TICKS_PER_DAY
 if day~=nil and type(day)=='number' and day>=0
    and day<1000000000 then self.day=floor(day) end
 return true
end
function Lighting:tick(dt)
 if type(dt)~='number' or dt~=dt or dt<=0 then return end
 local elapsed=self.time+min(dt,.1)*self.TICKS_PER_SECOND
 if elapsed>=self.TICKS_PER_DAY then
  self.day=self.day+floor(elapsed/self.TICKS_PER_DAY)
 end
 self.time=elapsed%self.TICKS_PER_DAY
end
function Lighting:phase()
 local t=self.time
 if t>=23000 then return 'dawn' end
 if t>=13000 then return 'night' end
 if t>=12000 then return 'dusk' end
 return 'day'
end
function Lighting:dayFactor()
 local t=self.time
 if t<12000 then return 1 end
 if t<13000 then return 1-(t-12000)/1000*.84 end
 if t<23000 then return .16 end
 return .16+(t-23000)/1000*.84
end
function Lighting:skyLevel()
 return clamp(floor(4+self:dayFactor()*11+.5),4,15)
end
function Lighting:skyColor()
 -- Cores de atmosfera do prototipo; o jogo final tera fog por bioma.
 local day=self:dayFactor()
 local haze=math.max(0,1-abs(day-.55)/.4)
 return clamp(.025+.42*day+.19*haze,0,1),
   clamp(.035+.60*day+.06*haze,0,1),
   clamp(.10+.80*day,0,1)
end
-- IDs transparentes no catalogo interno do jogo (nao IDs Mojang).
-- O emissor pode ocupar um bloco proprio; os vizinhos precisam transmitir luz.
function Lighting.transmits(id)
 return id==0 or id==5 or id==9 or id==16 or id==29 or id==52
   or (id>=24 and id<=28)
end
local DIRECTIONS={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
-- Calcula um campo BFS por emissor. A luz percorre apenas blocos
-- transparentes e nao atravessa paredes. A distancia e por passos;
-- caminhos em volta de obstaculos sao permitidos e mais fracos.
-- Este campo e criado sob demanda para evitar gerar chunks de
-- fontes distantes durante o carregamento de saves antigos.
function Lighting:buildField(light)
 local world=self.world
 local levels={[coord(light.x,light.y,light.z)]=light.power}
 local queue={{light.x,light.y,light.z,light.power}}
 local head=1
 while head<=#queue do
  local node=queue[head]
  head=head+1
  local strength=node[4]-1
  if strength>0 then
   for i=1,6 do
    local dir=DIRECTIONS[i]
    local x,y,z=node[1]+dir[1],node[2]+dir[2],node[3]+dir[3]
    if world:within(x,y,z) then
     local k=coord(x,y,z)
     if (levels[k] or 0)<strength and
        Lighting.transmits(world:get(x,y,z)) then
      levels[k]=strength
      queue[#queue+1]={x,y,z,strength}
     end
    end
   end
  end
 end
 light.field=levels
 return levels
end
-- Retorna as fontes cujo alcance maximo inclui a edicao.
-- O cache de cada fonte afetada e invalidado sem recalcular o mundo todo.
function Lighting:invalidateNear(x,y,z)
 local result={}
 local cx,cy,cz=floor(x/16),floor(y/16),floor(z/16)
 for dx=-1,1 do for dy=-1,1 do for dz=-1,1 do
  local bucket=self.buckets[key(cx+dx,cy+dy,cz+dz)]
  if bucket then
   for _,light in pairs(bucket) do
    if abs(x-light.x)+abs(y-light.y)+abs(z-light.z)<light.power then
     light.field=nil
     result[#result+1]=light
    end
   end
  end
 end end end
 return result
end
-- Interface mantida para o carregador de saves e testes anteriores.
-- O indice e alterado sem fazer BFS durante World:load().
function Lighting:updateSource(x,y,z,oldId,newId)
 local position=coord(x,y,z)
 local old=self.sources[position]
 local affected={}
 if old then
  local bucketKey=key(floor(x/16),floor(y/16),floor(z/16))
  local bucket=self.buckets[bucketKey]
  if bucket then
   bucket[position]=nil
   if not next(bucket) then self.buckets[bucketKey]=nil end
  end
  self.sources[position]=nil
  self.sourceCount=self.sourceCount-1
  affected[#affected+1]=old
 end
 local strength=self.EMITTERS[newId]
 if strength then
  local source={x=x,y=y,z=z,power=strength,field=nil}
  local bucketKey=key(floor(x/16),floor(y/16),floor(z/16))
  self.buckets[bucketKey]=self.buckets[bucketKey] or {}
  self.buckets[bucketKey][position]=source
  self.sources[position]=source
  self.sourceCount=self.sourceCount+1
  affected[#affected+1]=source
 end
 -- A transicao entre um bloco emissor e outro pode afetar vizinhos.
 local nearby=self:invalidateNear(x,y,z)
 for _,v in ipairs(nearby) do affected[#affected+1]=v end
 return affected
end
-- Tambem reage a construcoes SEM luz: fechar ou abrir uma passagem
-- precisa alterar a propagacao das fontes instaladas ao redor.
function Lighting:onBlockChanged(x,y,z,oldId,newId)
 if self.EMITTERS[oldId] or self.EMITTERS[newId] then
  if Lighting.transmits(oldId)~=Lighting.transmits(newId) then
   self:invalidateSky(x,z)
  end
  return self:updateSource(x,y,z,oldId,newId)
 end
 if Lighting.transmits(oldId)~=Lighting.transmits(newId) then
  self:invalidateSky(x,z)
  return self:invalidateNear(x,y,z)
 end
 return {}
end
function Lighting:blockLevel(x,y,z)
 if self.sourceCount==0 then return 0 end
 local cx,cy,cz=floor(x/16),floor(y/16),floor(z/16)
 local position=coord(x,y,z)
 local level=0
 -- Nenhum emissor alcanca um bloco fora de sua propria secao
 -- e das 26 secoes vizinhas: o raio maximo de emissao e 15.
 for dx=-1,1 do for dy=-1,1 do for dz=-1,1 do
  local bucket=self.buckets[key(cx+dx,cy+dy,cz+dz)]
  if bucket then
   for _,light in pairs(bucket) do
    if abs(x-light.x)+abs(y-light.y)+abs(z-light.z)<light.power then
     local field=light.field or self:buildField(light)
     local value=field[position] or 0
     if value>level then level=value end
     if level>=15 then return 15 end
    end
   end
  end
 end end end
 return level
end
-- Topo opaco real de cada coluna, incluindo edicoes de jogadores.
-- Cache indexado por coordenadas absolutas e invalidado por edicoes.
function Lighting:skyTop(x,z)
 x,z=floor(x),floor(z)
 local k=x..':'..z
 local value=self.skyColumns[k]
 if value~=nil then return value end
 local world=self.world
 local top=world.YMIN-1
 for y=world.YMAX,world.YMIN,-1 do
  if not Lighting.transmits(world:get(x,y,z)) then
   top=y
   break
  end
 end
 if self.skyColumnCount>=self.skyColumnLimit then
  self.skyColumns={}
  self.skyColumnCount=0
 end
 self.skyColumns[k]=top
 self.skyColumnCount=self.skyColumnCount+1
 return top
end
function Lighting:skyVisible(x,y,z)
 local world=self.world
 x,y,z=floor(x),floor(y),floor(z)
 if not world:within(x,clamp(y,world.YMIN,world.YMAX),z) then
  return false
 end
 if y>world.YMAX then return true end
 if y<world.YMIN then return false end
 return y>self:skyTop(x,z)
end
function Lighting:skyApprox(x,y,z,cache)
 -- Mantem API anterior e agora respeita teto construido ou cavado.
 local k=x..':'..z
 if cache and cache[k]~=nil then return y>cache[k] end
 local top=self:skyTop(x,z)
 if cache then cache[k]=top end
 return y>top
end
-- Calcula luz do ceu por caminho livre atraves de voxels
-- transparentes. Colunas abertas tem 15 ao longo de toda a altura;
-- desvios horizontais/verticais custam um nivel por passo.
-- O BFS inverso para no primeiro ponto de ceu direto (distancia
-- minima). Raio 14 limita CPU, memoria e alcance da iluminacao.
function Lighting:skyLight(x,y,z)
 local world=self.world
 x,y,z=floor(x),floor(y),floor(z)
 if y>world.YMAX then
  return world:within(x,world.YMAX,z) and 15 or 0
 end
 if not world:within(x,y,z) or
    not Lighting.transmits(world:get(x,y,z)) then return 0 end
 local position=coord(x,y,z)
 local previous=self.skyCache[position]
 if previous~=nil then return previous end
 local answer=0
 if self:skyVisible(x,y,z) then
  answer=15
 else
  local queue={{x,y,z,0}}
  local visited={[position]=true}
  local head=1
  while head<=#queue do
   local cell=queue[head]
   head=head+1
   local distance=cell[4]+1
   if distance<=14 then
    for i=1,6 do
     local direction=DIRECTIONS[i]
     local nx,ny,nz=cell[1]+direction[1],
       cell[2]+direction[2],cell[3]+direction[3]
     if world:within(nx,ny,nz) then
      local nk=coord(nx,ny,nz)
      if not visited[nk] then
       visited[nk]=true
       if Lighting.transmits(world:get(nx,ny,nz)) then
        if self:skyVisible(nx,ny,nz) then
         answer=15-distance
         break
        end
        queue[#queue+1]={nx,ny,nz,distance}
       end
      end
     end
    end
   end
   if answer>0 then break end
  end
 end
 if self.skyCacheCount>=self.skyCacheLimit then
  self.skyCache={}
  self.skyCacheCount=0
 end
 self.skyCache[position]=answer
 self.skyCacheCount=self.skyCacheCount+1
 return answer
end
function Lighting:invalidateSky(x,z)
 local k=floor(x)..':'..floor(z)
 if self.skyColumns[k]~=nil then
  self.skyColumns[k]=nil
  self.skyColumnCount=math.max(0,self.skyColumnCount-1)
 end
 -- Uma edicao muda indiretamente a difusao por varios corredores.
 self.skyCache={}
 self.skyCacheCount=0
end
function Lighting:pruneSky(px,pz)
 local cx,cz=floor(px/16),floor(pz/16)
 if self.skyChunkX==cx and self.skyChunkZ==cz then return end
 self.skyChunkX,self.skyChunkZ=cx,cz
 -- Limite nas consultas de regioes que ja sairam do streaming.
 self.skyCache={}
 self.skyCacheCount=0
 if self.skyColumnCount<2048 then return end
 local filtered,count={},0
 for k,top in pairs(self.skyColumns) do
  local x,z=k:match('^(%-?%d+):(%-?%d+)$')
  if x and abs(floor(tonumber(x)/16)-cx)<=6
    and abs(floor(tonumber(z)/16)-cz)<=6 then
   filtered[k]=top
   count=count+1
  end
 end
 self.skyColumns,self.skyColumnCount=filtered,count
end
function Lighting:level(x,y,z)
 local sky=floor(self:skyLight(x,y,z)*self:skyLevel()/15+.5)
 return max(sky,self:blockLevel(x,y,z))
end
function Lighting:canSpawnHostile(x,y,z)
 return self:level(x,y,z)<=7
end
function Lighting:sunburns(x,y,z)
 return self:dayFactor()>.78 and self:skyVisible(x,y,z)
end
return Lighting
