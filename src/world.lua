-- Streaming voxel infinito em chunks 16x16. Terreno deterministico, edits persistentes.
-- Apenas os chunks proximos ao player ficam residentes; o save guarda diferencias.
local World={}
World.__index=World
World.SIZE=48 -- area legada de spawn (criaturas), NAO o limite do mundo
World.MIN=-24
World.MAX=23
World.BOUND=1048575
World.YMIN=-4
World.YMAX=19
World.CHUNK=16
World.SAVE='world.sav'
local floor,abs,sin,cos,min,max=math.floor,math.abs,math.sin,math.cos,math.min,math.max
local function key(x,y,z) return x..','..y..','..z end
local function chunkKey(cx,cz) return cx..':'..cz end
local function height(x,z)
 local h=3+sin(x*.14)*2+cos(z*.13)*2+sin((x+z)*.09)*1.5
 return max(-2,min(8,floor(h)))
end
local function rng(x,z)
 local n=sin(x*127.1+z*311.7+37.1)*43758.5453
 return n-floor(n)
end
local function index(x,y,z)
 -- Dentro de um chunk, coordenadas x e z passam a estar em 0..15.
 return (y-World.YMIN)*256+z*16+x+1
end
local function idxWorld(x,y,z)
 return index(x%16,y,z%16)
end
function World.new()
 local w=setmetatable({
  blocks={}, -- compatibilidade de leitura, nunca contem o mundo inteiro
  cache={},edits={},editsByChunk={},dirty={['0:0']=true},
  savedPlayer=nil,savedMode=nil,savedItems={},savedScore=0,
  generatedTotal=0,evictedTotal=0
 },World)
 w:load()
 return w
end
function World:within(x,y,z)
 return type(x)=='number' and type(y)=='number' and type(z)=='number'
   and x==floor(x) and y==floor(y) and z==floor(z)
   and abs(x)<=self.BOUND and abs(z)<=self.BOUND
   and y>=self.YMIN and y<=self.YMAX
end
-- Gera um bloco novo na memoria de chunk, sem inserir no save.
function World:generateChunk(cx,cz)
 local data={}
 local sx,sz=cx*16,cz*16
 local function cell(x,y,z)
  if y<World.YMIN or y>World.YMAX or x<sx or x>=sx+16
     or z<sz or z>=sz+16 then return 0 end
  return data[idxWorld(x,y,z)] or 0
 end
 local function fill(x,y,z,id)
  if y>=World.YMIN and y<=World.YMAX and x>=sx and x<sx+16
     and z>=sz and z<sz+16 then
   local i=idxWorld(x,y,z)
   data[i]=id==0 and nil or id
  end
 end
 -- Geometria natural: estratos, zonas alagadas e superficies variaveis.
 for x=sx,sx+15 do
  for z=sz,sz+15 do
   local h=height(x,z)
   for y=World.YMIN,h do
    fill(x,y,z,(y==h and 1) or (y>=h-2 and 2) or 3)
   end
   for y=h+1,1 do fill(x,y,z,9) end
  end
 end
 -- Centros de arvore com margem de 2 blocos: sem cortes nas bordas.
 for x=sx-2,sx+17 do
  for z=sz-2,sz+17 do
   local h=height(x,z)
   if h>1 and rng(x,z)>.987 and (abs(x)>4 or abs(z)>4) then
    for y=h+1,h+4 do fill(x,y,z,4) end
    for yy=h+3,h+5 do
     for xx=x-2,x+2 do
      for zz=z-2,z+2 do
       local distance=abs(xx-x)+abs(zz-z)
       if distance<(yy==h+5 and 3 or 4) and cell(xx,yy,zz)==0 then
        fill(xx,yy,zz,5)
       end
      end
     end
    end
   end
  end
 end
 -- Veios minerais: centros adjacentes tambem atravessam fronteiras.
 for x=sx-1,sx+16 do
  for z=sz-1,sz+16 do
   local h=height(x,z)
   local ore=rng(x+831,z-551)
   local y=h-3
   if y>World.YMIN and ore>.961 then
    local id=14
    if ore>.992 then id=12 elseif ore>.981 then id=13 end
    for ox=-1,1 do
     for oz=-1,1 do
      local xx,zz=x+ox,z+oz
      if rng(xx+ox*7,zz+oz*11)>.39 and cell(xx,y,zz)==3 then
       fill(xx,y,zz,id)
      end
     end
    end
   end
  end
 end
 -- Flores e cogumelos fora da area de spawn.
 for x=sx,sx+15 do
  for z=sz,sz+15 do
   if abs(x)>4 or abs(z)>4 then
    local h=height(x,z)
    local decoration=rng(x+183,z+937)
    if h>1 and h+1<=World.YMAX and cell(x,h,z)==1
       and cell(x,h+1,z)==0 then
     if decoration>.991 then fill(x,h+1,z,24)
     elseif decoration>.982 then fill(x,h+1,z,25)
     elseif decoration>.972 then fill(x,h+1,z,26)
     elseif decoration>.963 then fill(x,h+1,z,27) end
    elseif decoration>.996 and cell(x,h,z)==1 then
     fill(x,h,z,11)
    end
   end
  end
 end
 local ck=chunkKey(cx,cz)
 for i,id in pairs(self.editsByChunk[ck] or {}) do
  data[i]=id==0 and nil or id
 end
 self.cache[ck]={data=data,cx=cx,cz=cz}
 self.generatedTotal=self.generatedTotal+1
 return self.cache[ck]
end
function World:ensureChunk(cx,cz)
 local ck=chunkKey(cx,cz)
 return self.cache[ck] or self:generateChunk(cx,cz)
end
function World:get(x,y,z)
 if not self:within(x,y,z) then return 0 end
 local chunk=self:ensureChunk(floor(x/16),floor(z/16))
 return chunk.data[idxWorld(x,y,z)] or 0
end
function World:set(x,y,z,id)
 if not self:within(x,y,z) or y==self.YMIN then return false end
 if type(id)~='number' or id~=floor(id) or id<0 or id>46 then return false end
 if self:get(x,y,z)==30 or self:get(x,y,z)==id then return false end
 local cx,cz=floor(x/16),floor(z/16)
 local ck=chunkKey(cx,cz)
 local i=idxWorld(x,y,z)
 self.cache[ck].data[i]=id==0 and nil or id
 self.edits[key(x,y,z)]=id
 if not self.editsByChunk[ck] then self.editsByChunk[ck]={} end
 self.editsByChunk[ck][i]=id
 self.dirty[ck]=true
 -- Remalha somente vizinhos afetados por uma face de borda.
 if x%16==0 then self.dirty[chunkKey(cx-1,cz)]=true end
 if x%16==15 then self.dirty[chunkKey(cx+1,cz)]=true end
 if z%16==0 then self.dirty[chunkKey(cx,cz-1)]=true end
 if z%16==15 then self.dirty[chunkKey(cx,cz+1)]=true end
 return true
end
function World:prune(centerX,centerZ,half)
 -- Mantem uma borda extra no cache de dados para a malha enxergar vizinhos.
 local cx,cz=floor(centerX/16),floor(centerZ/16)
 local range=(half or 2)+2
 for k,chunk in pairs(self.cache) do
  if abs(chunk.cx-cx)>range or abs(chunk.cz-cz)>range then
   self.cache[k]=nil
   self.dirty[k]=nil
   self.evictedTotal=self.evictedTotal+1
  end
 end
 for k in pairs(self.dirty) do
  local x,z=k:match('^(-?%d+):(-?%d+)$')
  if x and (abs(tonumber(x)-cx)>range or abs(tonumber(z)-cz)>range) then
   self.dirty[k]=nil
  end
 end
end
function World:cacheCount()
 local n=0
 for _ in pairs(self.cache) do n=n+1 end
 return n
end
function World:explode(px,py,pz,radius)
 radius=max(.5,min(4,radius or 2))
 local removed=0
 local r=math.ceil(radius)
 for x=floor(px)-r,floor(px)+r do
  for y=floor(py)-r,floor(py)+r do
   for z=floor(pz)-r,floor(pz)+r do
    local dx,dy,dz=x-px,y-py,z-pz
    local id=self:get(x,y,z)
    if id~=0 and id~=9 and id~=29 and id~=30 and y>self.YMIN
       and not (abs(x)<3 and abs(z)<3)
       and dx*dx+dy*dy+dz*dz<=radius*radius then
      if self:set(x,y,z,0) then removed=removed+1 end
    end
   end
  end
 end
 return removed
end
function World:isSolid(x,y,z)
 local id=self:get(x,y,z)
 return id~=0 and id~=5 and id~=9 and id~=24 and id~=25
    and id~=26 and id~=27 and id~=28 and id~=29
end
function World:spawnHeight(x,z)
 x,z=floor(x),floor(z)
 for y=self.YMAX,self.YMIN,-1 do
  if self:isSolid(x,y,z) and not self:isSolid(x,y+1,z)
     and not self:isSolid(x,y+2,z) then return y+.51 end
 end
 return 10
end
function World:load()
 local source=lovr.filesystem.read(self.SAVE)
 if not source then return end
 for line in source:gmatch('[^\r\n]+') do
  local px,py,pz,yaw,pitch=line:match('^PLAYER ([%d%.%-]+) ([%d%.%-]+) ([%d%.%-]+) ([%d%.%-]+) ([%d%.%-]+)$')
  if px and tonumber(px) and tonumber(py) and tonumber(pz) then
   self.savedPlayer={x=tonumber(px),y=tonumber(py),z=tonumber(pz),
     yaw=tonumber(yaw) or 0,pitch=tonumber(pitch) or 0}
  end
  local mode=line:match('^MODE (survival)$') or line:match('^MODE (creative)$')
  if mode then self.savedMode=mode end
  local score=line:match('^SCORE (%d+)$')
  if score then self.savedScore=min(1000000000,tonumber(score)) end
  local item,count=line:match('^ITEM (%d+) (%d+)$')
  if item then
   item,count=tonumber(item),tonumber(count)
   if item>=1 and item<=46 then self.savedItems[item]=min(99,count) end
  end
  local x,y,z,id=line:match('^BLOCK (%-?%d+) (%-?%d+) (%-?%d+) (%d+)$')
  x,y,z,id=tonumber(x),tonumber(y),tonumber(z),tonumber(id)
  if x and y and z and id and self:within(x,y,z) and id<=46 then
   local ck=chunkKey(floor(x/16),floor(z/16))
   local i=idxWorld(x,y,z)
   self.edits[key(x,y,z)]=id
   if not self.editsByChunk[ck] then self.editsByChunk[ck]={} end
   self.editsByChunk[ck][i]=id
  end
 end
end
function World:save(player,classic)
 local lines={string.format('PLAYER %.3f %.3f %.3f %.6f %.6f',
  player.x,player.y,player.z,player.yaw,player.pitch)}
 if classic then
  lines[#lines+1]='MODE '..(classic.mode=='creative' and 'creative' or 'survival')
  lines[#lines+1]='SCORE '..tostring(max(0,floor(classic.score or 0)))
  for id=1,46 do
   local count=max(0,min(99,floor((classic.items or {})[id] or 0)))
   if count>0 then lines[#lines+1]=('ITEM %d %d'):format(id,count) end
  end
 end
 local keys={}
 for k in pairs(self.edits) do keys[#keys+1]=k end
 table.sort(keys)
 for _,k in ipairs(keys) do
  local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  lines[#lines+1]=('BLOCK %s %s %s %d'):format(x,y,z,self.edits[k])
 end
 return lovr.filesystem.write(self.SAVE,table.concat(lines,'\n')..'\n')
end
return World
