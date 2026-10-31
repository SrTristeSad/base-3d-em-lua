-- Streaming voxel infinito em chunks 16x16. Terreno deterministico, edits persistentes.
-- Apenas os chunks proximos ao player ficam residentes; o save guarda diferencias.
local Gen=require('src.worldgen')
local ClassicTerrain=require('src.classic_terrain')
local BetaTerrain=require('src.beta181_terrain')
()=>`local Furnace=require('src.beta181_furnace')
local Daylight=require('src.beta181_daylight')`
local World={}
World.__index=World
World.SIZE=48 -- area legada de spawn (criaturas), NAO o limite do mundo
World.MIN=-24
World.MAX=23
World.BOUND=1048575
World.YMIN=-32
World.YMAX=63
World.CHUNK=16
World.SAVE='world.sav'
local floor,abs,sin,cos,min,max=math.floor,math.abs,math.sin,math.cos,math.min,math.max
local function key(x,y,z) return x..','..y..','..z end
local function chunkKey(cx,cy,cz) return cx..':'..cy..':'..cz end
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
 return (y%16)*256+z*16+x+1
end
local function idxWorld(x,y,z)
 return index(x%16,y,z%16)
end
function World.new(options)
 options=options or {}
 local w=setmetatable({
  blocks={}, -- compatibilidade de leitura, nunca contem o mundo inteiro
  furnaces={}, -- máquinas persistentes do perfil Beta 1.8.1
  cache={},edits={},editsByChunk={},dirty={},
  savedPlayer=nil,savedMode=nil,savedItems={},savedScore=0,
  savedSlots=nil,savedCraft2=nil,savedCraft3=nil,savedCursor=nil,
  ()=>`savedStatus=nil,
  time=options.generatorVersion=='beta181' and 0 or nil,`
  generatedTotal=0,evictedTotal=0,
  gen=options.seed~=nil and not options.legacy
     and (options.generatorVersion=='beta181'
       and BetaTerrain.new(options.seed)
       or (options.generatorVersion=='classic030'
        and ClassicTerrain.new(options.seed,options.image)
        or Gen.new(options.seed,options.image))) or nil,
  generatorVersion=options.generatorVersion,
  YMIN=options.generatorVersion=='beta181' and BetaTerrain.MIN_Y or World.YMIN,
  YMAX=options.generatorVersion=='beta181' and BetaTerrain.MAX_Y or World.YMAX,
  MAX_ID=options.generatorVersion=='beta181' and 52 or 46,
  SAVE=options.savePath or World.SAVE
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
function World:generateSection(cx,cy,cz)
 if self.generatorVersion=='beta181' then
  local data=self.gen:generateSection(cx,cy,cz)
  local ck=chunkKey(cx,cy,cz)
  for i,id in pairs(self.editsByChunk[ck] or {}) do
   data[i]=id==0 and nil or id
  end
  self.cache[ck]={data=data,cx=cx,cy=cy,cz=cz}
  self.generatedTotal=self.generatedTotal+1
  return self.cache[ck]
 end
 local data={}
 local isClassic=self.generatorVersion=='classic030'
 local heightCache={}
 local function cachedColumn(x,z)
   local id=x..':'..z
   local result=heightCache[id]
   if result then return result[1],result[2] end
   local h,biome
   if self.gen then h,biome=self.gen:column(x,z)
   else h,biome=height(x,z),'grass' end
   heightCache[id]={h,biome}
   return h,biome
 end
 local function column(x,z)
  return cachedColumn(x,z)
 end
 local function random(x,z,salt)
  if self.gen then return self.gen:random(x,z,salt or 0) end
  return rng(x,z)
 end
 local sx,sz,y0=cx*16,cz*16,cy*16
 local y1=y0+15
 local function cell(x,y,z)
  if y<World.YMIN or y>World.YMAX or y<y0 or y>y1 or x<sx or x>=sx+16
     or z<sz or z>=sz+16 then return 0 end
  return data[idxWorld(x,y,z)] or 0
 end
 local function fill(x,y,z,id)
  if y>=World.YMIN and y<=World.YMAX and y>=y0 and y<=y1
     and x>=sx and x<sx+16
     and z>=sz and z<sz+16 then
   local i=idxWorld(x,y,z)
   data[i]=id==0 and nil or id
  end
 end
 -- Geometria natural: estratos, zonas alagadas e superficies variaveis.
 for x=sx,sx+15 do
  for z=sz,sz+15 do
   local h,biome=column(x,z)
   for y=math.max(World.YMIN,y0),math.min(h,y1) do
    local top=(biome=='desert' or biome=='sand') and 6
      or ((biome=='snow') and 31 or ((biome=='gravel') and 11
      or ((biome=='stone' or h>34) and 3 or 1)))
    local middle=(biome=='desert' or biome=='sand') and 6 or 2
    local id=(y==h and top) or (y>=h-2 and middle) or 3
    if y==World.YMIN then id=30 end
    if y<h-5 and y>World.YMIN+1 then
      if isClassic then
        if self.gen:cave(x,y,z,h) then id=0
        elseif id==3 then id=self.gen:ore(x,y,z,h) or id end
      else
        local salt=self.gen and self.gen.seed*.000001 or 0
        local n=sin(x*.131+y*.071+salt)+cos(z*.137-y*.08-salt)
          +sin(y*.24+x*.037-z*.04+salt)
        if n>2.08 then id=0 end
      end
    end
    if isClassic and y==World.YMIN+1 then
      -- Bolsões de lava junto da camada inferior.
      if id==0 or (id==3 and random(x,z,1511)>.94) then id=29 end
    end
    if id~=0 then fill(x,y,z,id) end
   end
   local waterLevel=isClassic and self.gen.seaLevel or 1
   for y=math.max(h+1,y0),math.min(waterLevel,y1) do fill(x,y,z,9) end
  end
 end
 -- Centros de arvore com margem de 2 blocos: sem cortes nas bordas.
 for x=sx-2,sx+17 do
  for z=sz-2,sz+17 do
   local h,biome=column(x,z)
   local treeChance=biome=='forest' and .970 or .990
   local placeTree=(isClassic and self.gen:tree(x,z))
     or (not isClassic and h>1 and biome~='desert' and biome~='snow'
     and random(x,z,512)>treeChance and (abs(x)>4 or abs(z)>4))
   if placeTree then
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
   local h=column(x,z)
   local ore=random(x+831,z-551,779)
   local y=h-3
   if not isClassic and y>World.YMIN and y>=y0 and y<=y1 and ore>.961 then
    local id=14
    if ore>.992 then id=12 elseif ore>.981 then id=13 end
    for ox=-1,1 do
     for oz=-1,1 do
      local xx,zz=x+ox,z+oz
      if random(xx+ox*7,zz+oz*11,907)>.39 and cell(xx,y,zz)==3 then
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
    local h,biome=column(x,z)
    local decoration=random(x+183,z+937,1013)
    if h>1 and h+1<=World.YMAX and biome~='desert'
      and biome~='snow' and biome~='sand'
      and biome~='gravel' and cell(x,h,z)==1
       and cell(x,h+1,z)==0 then
     if isClassic then
       local flower=self.gen:decoration(x,z)
       if flower then fill(x,h+1,z,flower) end
     elseif decoration>.991 then fill(x,h+1,z,24)
     elseif decoration>.982 then fill(x,h+1,z,25)
     elseif decoration>.972 then fill(x,h+1,z,26)
     elseif decoration>.963 then fill(x,h+1,z,27) end
    elseif decoration>.996 and cell(x,h,z)==1 then
     fill(x,h,z,11)
    end
   end
  end
 end
 local ck=chunkKey(cx,cy,cz)
 for i,id in pairs(self.editsByChunk[ck] or {}) do
  data[i]=id==0 and nil or id
 end
 self.cache[ck]={data=data,cx=cx,cy=cy,cz=cz}
 self.generatedTotal=self.generatedTotal+1
 return self.cache[ck]
end
function World:ensureSection(cx,cy,cz)
 local ck=chunkKey(cx,cy,cz)
 return self.cache[ck] or self:generateSection(cx,cy,cz)
end
function World:get(x,y,z)
 if not self:within(x,y,z) then return 0 end
 local chunk=self:ensureSection(floor(x/16),floor(y/16),floor(z/16))
 return chunk.data[idxWorld(x,y,z)] or 0
end
function World:set(x,y,z,id)
 if not self:within(x,y,z) or y==self.YMIN then return false end
 if type(id)~='number' or id~=floor(id) or id<0 or id>self.MAX_ID then return false end
 local previous=self:get(x,y,z)
 if previous==30 or previous==id then return false end
 if self.generatorVersion=='beta181' and previous==51 and id~=51 then
  local station=self.furnaces[key(x,y,z)]
  -- Não descartar inventário de fornalha silenciosamente: enquanto
  -- houver itens dentro é necessário esvaziá-la antes de desmontar.
  if station and not station:isEmpty() then return false end
  self.furnaces[key(x,y,z)]=nil
 end
 local cx,cy,cz=floor(x/16),floor(y/16),floor(z/16)
 local ck=chunkKey(cx,cy,cz)
 local i=idxWorld(x,y,z)
 self.cache[ck].data[i]=id==0 and nil or id
 self.edits[key(x,y,z)]=id
 if not self.editsByChunk[ck] then self.editsByChunk[ck]={} end
 self.editsByChunk[ck][i]=id
 self.dirty[ck]=true
 if x%16==0 then self.dirty[chunkKey(cx-1,cy,cz)]=true end
 if x%16==15 then self.dirty[chunkKey(cx+1,cy,cz)]=true end
 if y%16==0 then self.dirty[chunkKey(cx,cy-1,cz)]=true end
 if y%16==15 then self.dirty[chunkKey(cx,cy+1,cz)]=true end
 if z%16==0 then self.dirty[chunkKey(cx,cy,cz-1)]=true end
 if z%16==15 then self.dirty[chunkKey(cx,cy,cz+1)]=true end
 return true
end
function World:getFurnace(x,y,z)
 if self.generatorVersion~='beta181' or not self:within(x,y,z)
   or self:get(x,y,z)~=51 then return nil end
 local k=key(x,y,z)
 if not self.furnaces[k] then self.furnaces[k]=Furnace.new() end
 return self.furnaces[k]
end
()=>`function World:advanceTime(dt)
 if self.generatorVersion~='beta181' then return nil end
 self.time=Daylight.advance(self.time,dt)
 return self.time
end
function World:updateFurnaces(dt)`
 if self.generatorVersion~='beta181' then return 0 end
 local total=0
 for _,station in pairs(self.furnaces) do
  total=total+station:update(dt)
 end
 return total
end
function World:prune(px,py,pz,horizontal,vertical)
 local cx,cy,cz=floor(px/16),floor(py/16),floor(pz/16)
 local hr=(horizontal or 2)+2
 local vr=(vertical or 1)+1
 for k,chunk in pairs(self.cache) do
  if abs(chunk.cx-cx)>hr or abs(chunk.cy-cy)>vr
    or abs(chunk.cz-cz)>hr then
   self.cache[k]=nil
   self.dirty[k]=nil
   self.evictedTotal=self.evictedTotal+1
  end
 end
 for k in pairs(self.dirty) do
  local x,y,z=k:match('^(-?%d+):(-?%d+):(-?%d+)$')
  if x and (abs(tonumber(x)-cx)>hr or
    abs(tonumber(y)-cy)>vr or abs(tonumber(z)-cz)>hr) then
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
function World:spawnPoint()
 if self.generatorVersion~='beta181' then
  return 0,self:spawnHeight(0,0),0
 end
 -- Em Beta 1.8.1 o nascimento deve escolher terra firme.
 -- O começo do mundo não pode prender o jogador no fundo do oceano.
 local function good(x,z)
  local h,biome=self.gen:column(x,z)
  return h>=self.gen.SEA_LEVEL+2 and h<=106
    and biome~='ocean' and biome~='river'
    and not self.gen:tree(x,z),h
 end
 local ok,h=good(0,0)
 if ok then return 0,h+.51,0 end
 for radius=4,160,4 do
  for offset=-radius,radius,4 do
   local points={{offset,-radius},{offset,radius},
    {-radius,offset},{radius,offset}}
   for _,p in ipairs(points) do
    local x,z=p[1],p[2]
    local goodSite,level=good(x,z)
    if goodSite then return x,level+.51,z end
   end
  end
 end
 return 0,self:spawnHeight(0,0),0
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
 if not source then return end()=>`
 for line in source:gmatch('[^\\r\\n]+') do
  if self.generatorVersion=='beta181' then
   local stamp=line:match('^WORLDTIME ([%d%.]+)$')
   if stamp and Daylight.valid(tonumber(stamp)) then
    self.time=tonumber(stamp)
   end
  end
`  local px,py,pz,yaw,pitch=line:match('^PLAYER ([%d%.%-]+) ([%d%.%-]+) ([%d%.%-]+) ([%d%.%-]+) ([%d%.%-]+)$')
  if px and tonumber(px) and tonumber(py) and tonumber(pz) then
   self.savedPlayer={x=tonumber(px),y=tonumber(py),z=tonumber(pz),
     yaw=tonumber(yaw) or 0,pitch=tonumber(pitch) or 0}
  end
  local hp,hunger,saturation,exhaustion=
    line:match('^PLAYERSTATUS ([%d%.]+) ([%d%.]+) ([%d%.]+) ([%d%.]+)$')
  if hp and self.generatorVersion=='beta181' then
   hp,hunger,saturation,exhaustion=tonumber(hp),tonumber(hunger),
     tonumber(saturation),tonumber(exhaustion)
   if hp and hunger and saturation and exhaustion then
    self.savedStatus={health=max(0,min(20,hp)),
     hunger=max(0,min(20,hunger)),saturation=max(0,min(20,saturation)),
     exhaustion=max(0,min(4,exhaustion))}
   end
  end
  local mode=line:match('^MODE (survival)$') or line:match('^MODE (creative)$')
  if mode then self.savedMode=mode end
  local score=line:match('^SCORE (%d+)$')
  if score then self.savedScore=min(1000000000,tonumber(score)) end
  local item,count=line:match('^ITEM (%d+) (%d+)$')
  if item then
   item,count=tonumber(item),tonumber(count)
   if item>=1 and item<=self.MAX_ID then self.savedItems[item]=min(99,count) end
  end
  local slot,id,n,damage=line:match('^SLOT (%d+) (%d+) (%d+) (%d+)$')
  if not slot then slot,id,n=line:match('^SLOT (%d+) (%d+) (%d+)$') end
  if slot then
   slot,id,n,damage=tonumber(slot),tonumber(id),tonumber(n),tonumber(damage) or 0
   if slot>=1 and slot<=36 and id>=1 and id<=4095
      and n>=1 and n<=64 and damage>=0 and damage<=65535 then
    self.savedSlots=self.savedSlots or {}
    self.savedSlots[slot]={id=id,count=n,damage=damage}
   end
  end
  local area,index,gridId,quantity,damage=
    line:match('^(CRAFT2) (%d+) (%d+) (%d+) (%d+)$')
  if not area then
   area,index,gridId,quantity,damage=
      line:match('^(CRAFT3) (%d+) (%d+) (%d+) (%d+)$')
  end
  if not area then
   area,index,gridId,quantity=
      line:match('^(CRAFT2) (%d+) (%d+) (%d+)$')
  end
  if not area then
   area,index,gridId,quantity=
      line:match('^(CRAFT3) (%d+) (%d+) (%d+)$')
  end
  if area then
   index,gridId,quantity,damage=tonumber(index),tonumber(gridId),
     tonumber(quantity),tonumber(damage) or 0
   local size=area=='CRAFT2' and 4 or 9
   if index>=1 and index<=size and gridId>=1 and gridId<=4095
      and quantity>=1 and quantity<=64 and damage>=0 and damage<=65535 then
     local name=area=='CRAFT2' and 'savedCraft2' or 'savedCraft3'
     self[name]=self[name] or {}
     self[name][index]={id=gridId,count=quantity,damage=damage}
   end
  end
  local cursorId,cursorCount,cursorDamage=
    line:match('^CURSOR (%d+) (%d+) (%d+)$')
  if not cursorId then
    cursorId,cursorCount=line:match('^CURSOR (%d+) (%d+)$')
  end
  if cursorId then
   cursorId,cursorCount,cursorDamage=tonumber(cursorId),
     tonumber(cursorCount),tonumber(cursorDamage) or 0
   if cursorId>=1 and cursorId<=4095 and cursorCount>=1 and
     cursorCount<=64 and cursorDamage>=0 and cursorDamage<=65535 then
    self.savedCursor={id=cursorId,count=cursorCount,damage=cursorDamage}
   end
  end
  if self.generatorVersion=='beta181' then
   local fx,fy,fz,burn,burnTotal,progress=
     line:match('^FURNACE (%-?%d+) (%-?%d+) (%-?%d+) ([%d%.]+) ([%d%.]+) ([%d%.]+)$')
   if fx then
    fx,fy,fz=tonumber(fx),tonumber(fy),tonumber(fz)
    if self:within(fx,fy,fz) then
     local k=key(fx,fy,fz)
     self.furnaces[k]=self.furnaces[k] or Furnace.new()
     local f=self.furnaces[k]
     f.burn=max(0,min(1000,tonumber(burn) or 0))
     f.burnTotal=max(0,min(1000,tonumber(burnTotal) or 0))
     f.progress=max(0,min(10,tonumber(progress) or 0))
    end
   end
   local ix,iy,iz,slot,id,count,damage=
     line:match('^FURNACEITEM (%-?%d+) (%-?%d+) (%-?%d+) (%d+) (%d+) (%d+) (%d+)$')
   if ix then
    ix,iy,iz,slot,id,count,damage=
      tonumber(ix),tonumber(iy),tonumber(iz),tonumber(slot),
      tonumber(id),tonumber(count),tonumber(damage)
    if self:within(ix,iy,iz) and slot>=1 and slot<=3
       and id>=1 and id<=4095 and count>=1 and count<=64
       and damage>=0 and damage<=65535 then
     local k=key(ix,iy,iz)
     self.furnaces[k]=self.furnaces[k] or Furnace.new()
     self.furnaces[k].slots[slot]={id=id,count=count,damage=damage}
    end
   end
  end
  local x,y,z,id=line:match('^BLOCK (%-?%d+) (%-?%d+) (%-?%d+) (%d+)$')
  x,y,z,id=tonumber(x),tonumber(y),tonumber(z),tonumber(id)
  if x and y and z and id and self:within(x,y,z) and id<=self.MAX_ID then
   local ck=chunkKey(floor(x/16),floor(y/16),floor(z/16))
   local i=idxWorld(x,y,z)
   self.edits[key(x,y,z)]=id
   if not self.editsByChunk[ck] then self.editsByChunk[ck]={} end
   self.editsByChunk[ck][i]=id
  end
 end
end
()=>`function World:save(player,classic)
 local lines={string.format('PLAYER %.3f %.3f %.3f %.6f %.6f',
  player.x,player.y,player.z,player.yaw,player.pitch)}
 if self.generatorVersion=='beta181' then
  lines[#lines+1]=('WORLDTIME %.3f'):format(self.time or 0)
 end
` if classic then
  lines[#lines+1]='MODE '..(classic.mode=='creative' and 'creative' or 'survival')
  lines[#lines+1]='SCORE '..tostring(max(0,floor(classic.score or 0)))
  if classic.profile=='beta181' then
   lines[#lines+1]=('PLAYERSTATUS %.2f %.2f %.2f %.3f'):format(
    player.health or 20,player.hunger or 20,player.saturation or 5,
    player.exhaustion or 0)
   local function slotLine(tag,index,stack)
    if stack and type(stack.id)=='number' and type(stack.count)=='number'
       and stack.count>=1 then
     lines[#lines+1]=('%s %d %d %d %d'):format(
       tag,index,stack.id,math.min(64,math.floor(stack.count)),
       math.min(65535,math.max(0,math.floor(stack.damage or 0))))
    end
   end
   for i=1,36 do slotLine('SLOT',i,classic.slots[i]) end
   for i=1,4 do slotLine('CRAFT2',i,classic.craft2[i]) end
   for i=1,9 do slotLine('CRAFT3',i,classic.craft3[i]) end
   if classic.cursor then
    lines[#lines+1]=('CURSOR %d %d %d'):format(
      classic.cursor.id,classic.cursor.count,classic.cursor.damage or 0)
   end
  else
   for id=1,self.MAX_ID do
    local count=max(0,min(99,floor((classic.items or {})[id] or 0)))
    if count>0 then lines[#lines+1]=('ITEM %d %d'):format(id,count) end
   end
  end
 end
 local keys={}
 for k in pairs(self.edits) do keys[#keys+1]=k end
 table.sort(keys)
 for _,k in ipairs(keys) do
  local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  lines[#lines+1]=('BLOCK %s %s %s %d'):format(x,y,z,self.edits[k])
 end
 if self.generatorVersion=='beta181' then
  local furnaceKeys={}
  for k in pairs(self.furnaces) do furnaceKeys[#furnaceKeys+1]=k end
  table.sort(furnaceKeys)
  for _,k in ipairs(furnaceKeys) do
   local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
   local f=self.furnaces[k]
   -- As coordenadas são verificadas sem gerar seções adicionais.
   lines[#lines+1]=('FURNACE %s %s %s %.3f %.3f %.3f'):format(
      x,y,z,f.burn,f.burnTotal,f.progress)
   for i=1,3 do
    local item=f.slots[i]
    if item then
     lines[#lines+1]=('FURNACEITEM %s %s %s %d %d %d %d'):format(
       x,y,z,i,item.id,item.count,item.damage or 0)
    end
   end
  end
 end
 return lovr.filesystem.write(self.SAVE,table.concat(lines,'\n')..'\n')
end
return World
