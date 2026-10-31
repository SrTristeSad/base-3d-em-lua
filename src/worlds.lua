-- Catalogo de mundos independentes. Os arquivos de imagem entram como amostra
-- persistente 64x64, e cada mundo tem seu proprio save de blocos.
local Gen=require('src.worldgen')
local Worlds={}
local DIR='worlds'
local INDEX='worlds/index.txt'
local function clean(value,limit)
 return tostring(value or ''):gsub('[\r\n|]',' '):sub(1,limit)
end
local function readIndex()
 local items={}
 local data=lovr.filesystem.read(INDEX) or ''
 for line in data:gmatch('[^\r\n]+') do
  local id,name,seed,mode,hash,version=
    line:match('^(%d+)|([^|]*)|([^|]*)|([^|]*)|(%d+)|([%w_]+)$')
  if not id then
    id,name,seed,mode,hash=line:match('^(%d+)|([^|]*)|([^|]*)|([^|]*)|(%d+)$')
  end
  if id and mode and (mode=='creative' or mode=='survival') then
   local number=tonumber(id)
   if number and number>=1 and number<=100000 then
    items[#items+1]={id=number,name=name,seed=seed,mode=mode,
      imageHash=tonumber(hash),legacy=false,
      generatorVersion=(version=='classic030' or version=='beta181') and version or nil}
   end
  end
 end
 table.sort(items,function(a,b) return a.id<b.id end)
 return items
end
local function ensureDir()
 lovr.filesystem.createDirectory(DIR)
 lovr.filesystem.createDirectory('maps')
end
function Worlds.file(id,ext)
 return ('worlds/%06d.%s'):format(id,ext)
end
function Worlds.list()
 local items=readIndex()
 if lovr.filesystem.isFile('world.sav') then
  table.insert(items,1,{id=0,name='Mundo antigo',seed='0',
    mode='survival',imageHash=0,legacy=true})
 end
 return items
end
local function writeIndex(items)
 local rows={}
 for _,it in ipairs(items) do
  rows[#rows+1]=('%d|%s|%s|%s|%d|%s'):format(it.id,
    clean(it.name,40),clean(it.seed,60),it.mode,it.imageHash or 0,
    it.generatorVersion or 'legacy')
 end
 local old=lovr.filesystem.read(INDEX)
 if old then lovr.filesystem.write('worlds/index.bak',old) end
 return lovr.filesystem.write(INDEX,table.concat(rows,'\n')..'\n')
end
function Worlds.open(info)
 if info.legacy or info.id==0 then
  return {savePath='world.sav',legacy=true,name=info.name or 'Mundo antigo',
    mode=info.mode or 'survival'}
 end
 local map
 if info.imageHash and info.imageHash>0 then
  local raw=lovr.filesystem.read(Worlds.file(info.id,'map'))
  local err
  map,err=Gen.decodeImage(raw)
  if not map then return nil,'Imagem do mundo nao pode ser restaurada: '..(err or '') end
  if map.hash~=info.imageHash then return nil,'A imagem salva nao confere com o mundo' end
 end
 return {savePath=Worlds.file(info.id,'sav'),seed=info.seed,image=map,
   legacy=false,name=info.name,mode=info.mode,
   generatorVersion=info.generatorVersion}
end
function Worlds.create(name,seed,imagePath,mode)
 ensureDir()
 name=clean(name,40):match('^%s*(.-)%s*$')
 if name=='' then name='Novo Mundo' end
 seed=clean(seed,60):match('^%s*(.-)%s*$')
 if seed=='' then seed=tostring(os.time()) end
 mode=mode=='creative' and 'creative' or 'survival'
 -- Só seeds para mundos novos: imagens ficam apenas como leitura de saves antigos.
 if imagePath and imagePath~='' then
  return nil,'Geracao por imagem foi removida. Crie um mundo usando seed.'
 end
 local items=readIndex()
 if #items>=96 then return nil,'Limite de 96 mundos atingido' end
 local nextId=1
 for _,it in ipairs(items) do nextId=math.max(nextId,it.id+1) end
 if nextId>100000 then return nil,'Limite de identificadores atingido' end
 local entry={id=nextId,name=name,seed=seed,mode=mode,
   imageHash=0,legacy=false,generatorVersion='beta181'}
 items[#items+1]=entry
 if not writeIndex(items) then return nil,'Nao foi possivel salvar a lista de mundos' end
 return Worlds.open(entry),entry
end
return Worlds
