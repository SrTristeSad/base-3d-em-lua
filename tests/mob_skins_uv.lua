-- UV Atlas de mobs: seis especies, textura 64x32/64x64 e fallback.
package.path='./?.lua;./?/init.lua;'..package.path
local images,meshes=0,0
local changed=false
local custom='assets/skins/mobs/zombie.png'
local function newImage(w,h)
 if type(w)=='string' then
  assert(w==custom)
  return {getDimensions=function() return 64,32 end,
   release=function() changed=true end}
 end
 images=images+1
 assert(w==64 and h==64)
 return {setPixel=function(_,x,y,r,g,b,a)
  assert(x>=0 and x<64 and y>=0 and y<64)
 end}
end
lovr={
 filesystem={isFile=function(_,path)
  -- A API e chamada como funcao com um argumento: o caminho.
  return (_==custom or path==custom)
 end},
 data={newImage=newImage},
 graphics={
  newTexture=function(input)
   return {input=input,release=function(self) self.released=true end}
  end,
  newMesh=function(fmt,verts,opts)
   meshes=meshes+1
   assert(#fmt==4 and #verts==36)
   for _,v in ipairs(verts) do
    assert(v[7]>=0 and v[7]<=1 and v[8]>=0 and v[8]<=1,
      'UV esta fora do atlas')
   end
   return {vertices=verts,
     setMaterial=function(self,t) self.material=t end,
     release=function(self) self.released=true end}
  end
 }
}
local Skin=require('src.mob_skins')
local names={'Zombie','Skeleton','Spider','Pig','Sheep','Creeper'}
local rects=Skin.unwrap(0,0,8,8,8)
assert(rects[6][1]==8 and rects[6][2]==8 and rects[6][3]==8,
 'Frente deve iniciar em (8,8) na textura classica')
local renderer=Skin.new()
assert(images==5,'Cinco fallback skins pixeladas originais esperadas')
assert(renderer.custom.Zombie and not renderer.custom.Creeper)
assert(changed,'Imagem importada nao teve metadados verificados')
local pass={draws=0,push=function() end,pop=function() end,
 translate=function() end,rotate=function() end,setColor=function() end,
 draw=function(self,mesh,x,y,z)
  assert(mesh.material,'Mesh sem textura')
  self.draws=self.draws+1
 end}
for _,name in ipairs(names) do
 local mob={kind=name,x=10,y=2,z=7,yaw=0,phase=.5,active=true}
 assert(renderer:draw(pass,mob,name))
end
assert(pass.draws>30,'Modelos nao possuem partes articulaveis suficientes')
assert(not renderer:draw(pass,{x=0,y=0,z=0},'Unknown'))
local first=renderer.entries.Pig.meshes[1]
renderer:release()
assert(first.released)
print('mob_skins_uv: OK')
