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
  local id,name,seed,mode,hash=line:match('^(%d+)|([^|]*)|([^|]*)|([^|]*)|(%d+)$')
  if id and mode and (mode=='creative' or mode=='survival') then
   local number=tonumber(id)
   if number and number>=1 and number<=100000 then
    items[#items+1]={id=number,name=name,seed=seed,mode=mode,
      imageHash=tonumber(hash),legacy=false}
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
  rows[#rows+1]=('%d|%s|%s|%s|%d'):format(it.id,
    clean(it.name,40),clean(it.seed,60),it.mode,it.imageHash or 0)
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
   legacy=false,name=info.name,mode=info.mode}
end
function Worlds.create(name,seed,imagePath,mode)
 ensureDir()
 name=clean(name,40):match('^%s*(.-)%s*$')
 if name=='' then name='Novo Mundo' end
 seed=clean(seed,60):match('^%s*(.-)%s*$')
 if seed=='' then seed=tostring(os.time()) end
 mode=mode=='creative' and 'creative' or 'survival'
 local image
 if imagePath and imagePath~='' then
  imagePath=clean(imagePath,110)
  -- Nunca ler um caminho absoluto ou atravessar diretorios do computador.
  if imagePath:find('..',1,true) or imagePath:sub(1,1)=='/'
    or imagePath:find('\\',1,true) or imagePath:find(':',1,true)
    or imagePath:find('[%c]') then
   return nil,'Nome de imagem invalido; use maps/foto.png'
  end
  if not lovr.filesystem.isFile(imagePath) then
   return nil,'Nao achei '..imagePath..'; copie o PNG/JPG para a pasta maps'
  end
  if not lovr.data or not lovr.data.newImage then
   return nil,'Carregamento de imagem indisponivel'
  end
  local ok,picture=pcall(lovr.data.newImage,imagePath)
  if not ok or not picture then
   return nil,'Nao consegui abrir PNG/JPG: '..tostring(picture)
  end
  local err
  image,err=Gen.fromImage(picture)
  if picture.release then picture:release() end
  if not image then return nil,err end
 end
 local items=readIndex()
 if #items>=96 then return nil,'Limite de 96 mundos atingido' end
 local nextId=1
 for _,it in ipairs(items) do nextId=math.max(nextId,it.id+1) end
 if nextId>100000 then return nil,'Limite de identificadores atingido' end
 local entry={id=nextId,name=name,seed=seed,mode=mode,
   imageHash=image and image.hash or 0,legacy=false}
 if image then
  local raw=Gen.encodeImage(image)
  local ok=lovr.filesystem.write(Worlds.file(nextId,'map'),raw)
  if not ok then return nil,'Nao foi possivel salvar os pixels da imagem' end
 end
 items[#items+1]=entry
 if not writeIndex(items) then return nil,'Nao foi possivel salvar a lista de mundos' end
 return Worlds.open(entry),entry
end
return Worlds
