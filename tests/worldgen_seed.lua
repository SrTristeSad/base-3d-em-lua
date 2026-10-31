-- World seeds, map snapshots, registry and reproducibility without graphical LÖVR.
package.path='./?.lua;./?/init.lua;'..package.path
local files={['maps/demo.png']='image-bytes', ['maps/different.jpg']='other-image'}
lovr={filesystem={
 read=function(path) return files[path] end,
 write=function(path,data) files[path]=data;return true end,
 isFile=function(path) return files[path]~=nil end,
 createDirectory=function() return true end,
},data={newImage=function(path)
 if path=='maps/demo.png' then
  return {getDimensions=function() return 16,16 end,
   getPixel=function(_,x,y)
    if x<8 then return .1,.8,.18,1 end
    return .7,.65,.2,1
   end,
   release=function() end}
 elseif path=='maps/different.jpg' then
  return {getDimensions=function() return 9,15 end,
   getPixel=function(_,x,y) return .12,.21,.9,1 end,
   release=function() end}
 end
 error('invalid image')
end}}
local Gen=require('src.worldgen')
local Worlds=require('src.worlds')
local World=require('src.world')
assert(Gen.seed('hello')==Gen.seed('hello'))
assert(Gen.seed('hello')~=Gen.seed('world'))
local g=Gen.new('839203')
local g2=Gen.new('839203')
local changed=0
for x=-220,220,35 do
 for z=-200,200,40 do
  assert(g:height(x,z)==g2:height(x,z),'seed igual criou outro mundo')
  if g:height(x,z)~=Gen.new('839204'):height(x,z) then changed=changed+1 end
 end
end
assert(changed>30,'sementes diferentes nao mudaram relevo')
local green=Gen.fromImage(lovr.data.newImage('maps/demo.png'))
local imageEncoded=Gen.encodeImage(green)
local decoded,err=Gen.decodeImage(imageEncoded)
assert(decoded and decoded.hash==green.hash and decoded.pixels[1]==green.pixels[1],err)
assert(not Gen.decodeImage(imageEncoded:sub(1,-10)..'abcdef'),'corrupcao nao detectada')
local opts,entry=Worlds.create('Meu mapa','abc 123','maps/demo.png','creative')
assert(opts and entry and entry.id==1 and opts.image.hash==green.hash)
assert(files['worlds/000001.map']~=nil and opts.savePath=='worlds/000001.sav')
local opts2,entry2=Worlds.create('Outro mapa','abc 123','maps/demo.png','creative')
assert(opts2 and entry2.id==2 and opts2.image.hash==green.hash)
local opts3,entry3=Worlds.create('Terceiro mapa','abc 123','maps/different.jpg','survival')
assert(opts3 and entry3.id==3 and opts3.image.hash~=green.hash)
local normal,plain=Worlds.create('Seed','abc 123','','survival')
assert(normal and plain.id==4 and normal.image==nil)
assert(#Worlds.list()==4 and Worlds.list()[2].name=='Outro mapa')
assert(not Worlds.create('Ilegal','42','../etc/passwd','survival'))
assert(not Worlds.create('Nao existe','42','maps/missing.png','survival'))
files['maps/demo.png']=nil
local loaded,loadErr=Worlds.open(entry)
assert(loaded and loaded.image.hash==entry.imageHash,loadErr)
local w=World.new(opts)
local other=World.new(opts2)
local different=World.new(opts3)
local plainWorld=World.new(normal)
local variations=0
for x=-100,100,10 do
 for z=-80,80,16 do
  local aa=w.gen:height(x,z)
  assert(aa==other.gen:height(x,z),'Mesma imagem e seed divergiram')
  if aa~=different.gen:height(x,z) then variations=variations+1 end
 end
end
assert(variations>15,'Cores de imagem nao influenciaram topografia')
assert(plainWorld.gen and plainWorld.gen.seed==Gen.seed('abc 123'))
local p={x=1,y=w:spawnHeight(0,0),z=2,yaw=0,pitch=0}
assert(w:set(1,45,1,7) and w:save(p))
local restored=World.new(loaded)
assert(restored:get(1,45,1)==7 and restored.savedPlayer.x==1)
assert(restored.gen:height(50,-30)==w.gen:height(50,-30))
assert(files['world.sav']==nil,'Mundo novo sobrescreveu save antigo')
files['world.sav']='PLAYER 0.000 7.000 0.000 0.000000 0.000000\n'
local items=Worlds.list()
assert(items[1].legacy and items[1].id==0)
local legacy=Worlds.open(items[1])
assert(legacy.legacy and legacy.savePath=='world.sav' and legacy.seed==nil)
print('worldgen_seed: OK')
