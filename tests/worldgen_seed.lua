-- Seeds Beta 1.8.1; só leitura de mundos antigos com imagens.
package.path='./?.lua;./?/init.lua;'..package.path
local files={['maps/demo.png']='unused old image'}
lovr={filesystem={
 read=function(path) return files[path] end,
 write=function(path,data) files[path]=data;return true end,
 isFile=function(path) return files[path]~=nil end,
 createDirectory=function() return true end
},data={newImage=function(path)
 return {getDimensions=function() return 16,16 end,
  getPixel=function(_,x,y)
   return x<8 and .1 or .9,.5,.2,1
  end,release=function() end}
end}}
local Gen=require('src.worldgen')
local Worlds=require('src.worlds')
local World=require('src.world')
assert(Gen.seed('hello')==Gen.seed('hello'))
assert(Gen.seed('hello')~=Gen.seed('world'))
local g,g2=Gen.new('839203'),Gen.new('839203')
local changed=0
for x=-220,220,35 do for z=-200,200,40 do
 assert(g:height(x,z)==g2:height(x,z))
 if g:height(x,z)~=Gen.new('839204'):height(x,z) then changed=changed+1 end
end end
assert(changed>30)
local green=Gen.fromImage(lovr.data.newImage('maps/demo.png'))
local encoded=Gen.encodeImage(green)
local decoded,err=Gen.decodeImage(encoded)
assert(decoded and decoded.hash==green.hash and decoded.pixels[1]==green.pixels[1],err)
assert(not Gen.decodeImage(encoded:sub(1,-10)..'abcdef'))
-- Registro antigo com 5 colunas deve continuar abrindo sua imagem salva.
files['worlds/index.txt']='1|Antigo com foto|abc 123|creative|'..green.hash..'\n'
files['worlds/000001.map']=encoded
local legacy=Worlds.list()[1]
assert(legacy.id==1 and legacy.generatorVersion==nil and legacy.imageHash==green.hash)
local oldOpt,oldErr=Worlds.open(legacy)
assert(oldOpt and oldOpt.image.hash==green.hash,oldErr)
local wLegacy=World.new(oldOpt)
assert(wLegacy.gen:height(35,-20)==Gen.new('abc 123',green):height(35,-20))
-- Novos mundos são Beta e recusarão novas fotos.
local noImage,reason=Worlds.create('Rejeitar','a','maps/demo.png','creative')
assert(not noImage and reason:find('imagem'))
local a,ea=Worlds.create('Novo','abc 123','','survival')
local b,eb=Worlds.create('Outro','abc 123','','creative')
local c,ec=Worlds.create('Outro seed','def 987','','survival')
assert(a and b and c and ea.id==2 and eb.id==3 and ec.id==4)
assert(a.generatorVersion=='beta181' and a.image==nil)
assert(b.generatorVersion=='beta181' and c.generatorVersion=='beta181')
assert(a.savePath=='worlds/000002.sav')
assert(files['worlds/000002.map']==nil)
local wa,wb,wc=World.new(a),World.new(b),World.new(c)
assert(wa.gen.style=='beta181')
local differences=0
for x=-100,100,10 do for z=-80,80,16 do
 assert(wa.gen:height(x,z)==wb.gen:height(x,z))
 if wa.gen:height(x,z)~=wc.gen:height(x,z) then differences=differences+1 end
end end
assert(differences>15)
local p={x=0,y=wa:spawnHeight(0,0),z=0,yaw=0,pitch=0}
assert(wa:set(1,110,1,7) and wa:save(p))
local reloaded=World.new(Worlds.open(ea))
assert(reloaded:get(1,110,1)==7)
assert(reloaded.savedPlayer.x==0)
local items=Worlds.list()
assert(#items==4 and items[1].name=='Antigo com foto')
assert(Worlds.open(items[1]).image.hash==green.hash)
assert(files['world.sav']==nil)
files['world.sav']='PLAYER 0.000 7.000 0.000 0.000000 0.000000\n'
assert(Worlds.list()[1].id==0 and Worlds.open(Worlds.list()[1]).legacy)
print('worldgen_seed: OK')
