-- Renderizador de criaturas com mapas UV pixel-art (64x64 ou 64x32).
-- Permite PNGs proprios em assets/skins/mobs/<nome>.png.
-- NENHUMA textura da Mojang e distribuida. Fallback e desenhado aqui.
local MobSkins={}
MobSkins.__index=MobSkins
local sin,floor,abs=math.sin,math.floor,math.abs
local FACES={
 {{1,-1,-1},{1,-1,1},{1,1,1},{1,1,-1}},
 {{-1,-1,1},{-1,-1,-1},{-1,1,-1},{-1,1,1}},
 {{-1,1,-1},{1,1,-1},{1,1,1},{-1,1,1}},
 {{-1,-1,1},{1,-1,1},{1,-1,-1},{-1,-1,-1}},
 {{1,-1,1},{-1,-1,1},{-1,1,1},{1,1,1}},
 {{-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1}}
}
local NORMALS={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},
 {0,0,1},{0,0,-1}}
local TRI={1,2,3,1,3,4}
local UV={{0,1},{1,1},{1,0},{0,0}}
local FORMAT={{'VertexPosition','vec3'},{'VertexNormal','vec3'},
 {'VertexUV','vec2'},{'VertexColor','vec4'}}

local function unwrap(x,y,w,h,d)
 return {
  {x+d+w,y+d,d,h}, -- direita
  {x,y+d,d,h}, -- esquerda
  {x+d,y,w,d}, -- superior
  {x+d+w,y,w,d}, -- inferior
  {x+d+w+d,y+d,w,h}, -- traseira
  {x+d,y+d,w,h} -- frente: -Z
 }
end
MobSkins.unwrap=unwrap

local function meshFor(part)
 local w,h,d=part.w,part.h,part.d
 local rectangles=unwrap(part.u,part.v,part.tw,part.th,part.td)
 local verts={}
 local shade={.84,.84,1,.6,.74,.92}
 for side=1,6 do
  local normal,rect=NORMALS[side],rectangles[side]
  for _,i in ipairs(TRI) do
   local p,uv=FACES[side][i],UV[i]
   local inset=.02
   local ux=(rect[1]+inset+uv[1]*(rect[3]-2*inset))/64
   local uy=(rect[2]+inset+uv[2]*(rect[4]-2*inset))/64
   verts[#verts+1]={
    p[1]*w*.5,p[2]*h*.5,p[3]*d*.5,
    normal[1],normal[2],normal[3],ux,uy,
    shade[side],shade[side],shade[side],1
   }
  end
 end
 return lovr.graphics.newMesh(FORMAT,verts,{storage='gpu'})
end

local function part(x,y,z,w,h,d,u,v,tw,th,td,movement)
 return {x=x,y=y,z=z,w=w,h=h,d=d,
  u=u,v=v,tw=tw,th=th,td=td,movement=movement}
end
local MODELS={
 Creeper={
  part(0,1.50,0,.84,.85,.78,0,0,8,8,8),
  part(0,.77,0,.62,.86,.51,16,16,8,12,4),
  part(-.21,.24,-.22,.30,.48,.32,0,16,4,12,4,-1),
  part(.21,.24,-.22,.30,.48,.32,0,16,4,12,4,1),
  part(-.21,.24,.22,.30,.48,.32,0,16,4,12,4,1),
  part(.21,.24,.22,.30,.48,.32,0,16,4,12,4,-1)
 },
 Zombie={
  part(0,1.96,0,.64,.65,.62,0,0,8,8,8),
  part(0,1.25,0,.64,.90,.39,16,16,8,12,4),
  part(-.49,1.25,0,.29,.90,.35,40,16,4,12,4,1),
  part(.49,1.25,0,.29,.90,.35,40,16,4,12,4,-1),
  part(-.18,.43,0,.30,.87,.37,0,16,4,12,4,-1),
  part(.18,.43,0,.30,.87,.37,0,16,4,12,4,1)
 },
 Skeleton={
  part(0,1.96,0,.60,.62,.59,0,0,8,8,8),
  part(0,1.25,0,.38,.87,.26,16,16,8,12,4),
  part(-.35,1.25,0,.17,.91,.17,40,16,4,12,4,1),
  part(.35,1.25,0,.17,.91,.17,40,16,4,12,4,-1),
  part(-.12,.43,0,.18,.87,.18,0,16,4,12,4,-1),
  part(.12,.43,0,.18,.87,.18,0,16,4,12,4,1)
 },
 Pig={
  part(0,.91,0,.88,.83,1.17,16,16,8,12,4),
  part(0,1.12,-.72,.67,.67,.55,0,0,8,8,8),
  part(0,.97,-1.08,.33,.25,.18,40,16,4,12,4),
  part(-.29,.26,-.38,.24,.52,.26,0,16,4,12,4,1),
  part(.29,.26,-.38,.24,.52,.26,0,16,4,12,4,-1),
  part(-.29,.26,.39,.24,.52,.26,0,16,4,12,4,-1),
  part(.29,.26,.39,.24,.52,.26,0,16,4,12,4,1)
 },
 Sheep={
  part(0,.98,0,.97,.91,1.23,16,16,8,12,4),
  part(0,1.15,-.72,.68,.72,.58,0,0,8,8,8),
  part(-.29,.26,-.39,.26,.52,.29,0,16,4,12,4,1),
  part(.29,.26,-.39,.26,.52,.29,0,16,4,12,4,-1),
  part(-.29,.26,.40,.26,.52,.29,0,16,4,12,4,-1),
  part(.29,.26,.40,.26,.52,.29,0,16,4,12,4,1)
 },
 Spider={
  part(0,.72,.28,1.00,.46,1.04,16,16,8,12,4),
  part(0,.71,-.53,.68,.48,.70,0,0,8,8,8),
  part(-.78,.48,-.54,.73,.14,.15,40,16,4,12,4,1),
  part(.78,.48,-.54,.73,.14,.15,40,16,4,12,4,-1),
  part(-.82,.48,-.18,.76,.14,.15,40,16,4,12,4,-1),
  part(.82,.48,-.18,.76,.14,.15,40,16,4,12,4,1),
  part(-.82,.48,.18,.76,.14,.15,40,16,4,12,4,1),
  part(.82,.48,.18,.76,.14,.15,40,16,4,12,4,-1),
  part(-.78,.48,.54,.73,.14,.15,40,16,4,12,4,-1),
  part(.78,.48,.54,.73,.14,.15,40,16,4,12,4,1)
 }
}
MobSkins.MODELS=MODELS
local COLORS={
 Creeper={.22,.62,.20},Zombie={.29,.57,.30},
 Skeleton={.78,.78,.72},Pig={.88,.52,.56},
 Sheep={.87,.88,.83},Spider={.24,.21,.28}
}
local function paint(img,x0,y0,w,h,r,g,b)
 for y=y0,y0+h-1 do
  for x=x0,x0+w-1 do
   if x>=0 and y>=0 and x<64 and y<64 then
    img:setPixel(x,y,r,g,b,1)
   end
  end
 end
end
local function fallback(kind)
 local img=lovr.data.newImage(64,64)
 local base=COLORS[kind]
 for y=0,63 do
  for x=0,63 do
   local fluct=((x*23+y*37+x*y*3+((x*7+y*11)%19))%17)/17
   local modifier=.81+fluct*.32
   img:setPixel(x,y,math.min(1,base[1]*modifier),
    math.min(1,base[2]*modifier),math.min(1,base[3]*modifier),1)
  end
 end
 local dark={.065,.085,.065}
 if kind=='Skeleton' then dark={.14,.15,.15}
 elseif kind=='Pig' then dark={.24,.13,.16}
 elseif kind=='Spider' then dark={.80,.14,.12} end
 -- Rect do rosto (-Z): x=8..15, y=8..15 no modelo padrao.
 paint(img,9,10,2,2,dark[1],dark[2],dark[3])
 paint(img,13,10,2,2,dark[1],dark[2],dark[3])
 if kind=='Creeper' then
  paint(img,11,12,2,3,.06,.08,.045)
  paint(img,10,14,1,2,.06,.08,.045)
  paint(img,13,14,1,2,.06,.08,.045)
 elseif kind=='Pig' then
  paint(img,10,12,4,2,.94,.35,.42)
  paint(img,11,12,1,1,.42,.17,.20)
  paint(img,13,12,1,1,.42,.17,.20)
 elseif kind=='Sheep' then
  paint(img,10,13,4,2,.61,.52,.47)
 else
  paint(img,10,14,4,1,dark[1],dark[2],dark[3])
 end
 if kind=='Zombie' then
  paint(img,18,20,8,9,.28,.40,.68)
 elseif kind=='Skeleton' then
  paint(img,18,20,8,9,.76,.77,.73)
 elseif kind=='Pig' then
  paint(img,18,20,8,9,.88,.55,.55)
 elseif kind=='Sheep' then
  paint(img,18,20,8,9,.87,.87,.86)
 end
 return img
end

function MobSkins.new()
 local self=setmetatable({entries={},custom={}},MobSkins)
 for kind,parts in pairs(MODELS) do
  local filename='assets/skins/mobs/'..kind:lower()..'.png'
  local texture
  if lovr.filesystem.isFile(filename) then
   local ok,img=pcall(lovr.data.newImage,filename)
   if ok and img then
    local w,h=img:getDimensions()
    if w==64 and (h==32 or h==64) then
     local success,value=pcall(lovr.graphics.newTexture,filename)
     if success then texture=value;self.custom[kind]=true end
    else print('Skin de mob deve ter 64x32 ou 64x64:',filename) end
    if img.release then img:release() end
   end
  end
  if not texture then texture=lovr.graphics.newTexture(fallback(kind)) end
  local meshes={}
  for i,p in ipairs(parts) do
   local mesh=meshFor(p)
   mesh:setMaterial(texture)
   meshes[i]=mesh
  end
  self.entries[kind]={meshes=meshes,parts=parts,texture=texture}
 end
 return self
end

function MobSkins:draw(pass,mob,kind)
 local entry=self.entries[kind]
 if not entry then return false end
 pass:push()
 pass:translate(mob.x,mob.y,mob.z)
 pass:rotate(mob.yaw or 0,0,1,0)
 pass:setColor(1,1,1)
 for i,p in ipairs(entry.parts) do
  local sway=p.movement and sin(mob.phase or 0)*.09*p.movement or 0
  pass:draw(entry.meshes[i],p.x,p.y+sway,p.z)
 end
 pass:pop()
 return true
end
function MobSkins:release()
 for _,entry in pairs(self.entries) do
  for _,mesh in ipairs(entry.meshes) do mesh:release() end
  if entry.texture and entry.texture.release then entry.texture:release() end
 end
end
return MobSkins
