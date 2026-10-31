-- Avatar voxel, formato de skin de jogador 64x64.
-- UVs seguem o layout clássico de personagem com braços de quatro pixels.
local Avatar = {}
Avatar.__index = Avatar
local format={{'VertexPosition','vec3'},{'VertexNormal','vec3'},{'VertexUV','vec2'}}
local faceOffsets={
  {{1,-1,-1},{1,-1,1},{1,1,1},{1,1,-1}},
  {{-1,-1,1},{-1,-1,-1},{-1,1,-1},{-1,1,1}},
  {{-1,1,-1},{1,1,-1},{1,1,1},{-1,1,1}},
  {{-1,-1,1},{1,-1,1},{1,-1,-1},{-1,-1,-1}},
  {{1,-1,1},{-1,-1,1},{-1,1,1},{1,1,1}},
  {{-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1}}
}
local normals={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
local orders={1,2,3,1,3,4}
local uvs={{0,1},{1,1},{1,0},{0,0}}

local function part(vertices,px,py,pz,w,h,d,rects)
  for face=1,6 do
    local rect,normal=rects[face],normals[face]
    for _,i in ipairs(orders) do
      local v=faceOffsets[face][i]
      local uv=uvs[i]
      vertices[#vertices+1]={
        px+v[1]*w/2,py+v[2]*h/2,pz+v[3]*d/2,
        normal[1],normal[2],normal[3],
        (rect[1]+uv[1]*rect[3])/64,
        (rect[2]+uv[2]*rect[4])/64
      }
    end
  end
end

local function faceRect(x,y,w,h,d)
  -- Layout clássico: lateral esquerda, frente, lateral direita, trás; topo/fundo acima.
  return {
    {x+w+d,y+d,d,h}, {x,y+d,d,h},
    {x+d,y,w,d}, {x+d+w,y,w,d},
    {x+d,y+d,w,h}, {x+2*d+w,y+d,w,h}
  }
end

local function defaultSkin()
  local img=lovr.data.newImage(64,64)
  for y=0,63 do
    for x=0,63 do img:setPixel(x,y,.82,.63,.44,1) end
  end
  local function paint(x0,y0,w,h,r,g,b)
    for y=y0,y0+h-1 do
      for x=x0,x0+w-1 do img:setPixel(x,y,r,g,b,1) end
    end
  end
  paint(16,16,24,16,.16,.45,.79)
  paint(40,16,16,16,.16,.45,.79)
  paint(0,16,16,16,.19,.25,.36)
  paint(0,48,32,16,.19,.25,.36)
  paint(32,48,32,16,.16,.45,.79)
  paint(0,0,32,8,.20,.14,.10)
  paint(8,8,8,2,.20,.14,.10)
  paint(9,12,1,1,.09,.11,.14)
  paint(14,12,1,1,.09,.11,.14)
  return img
end

function Avatar.new()
  local texture
  if lovr.filesystem.isFile('assets/skins/player.png') then
    local ok,t=pcall(lovr.graphics.newTexture,'assets/skins/player.png')
    if ok then texture=t else print('Skin invalida:',t) end
  end
  if not texture then texture=lovr.graphics.newTexture(defaultSkin()) end
  local verts={}
  part(verts,0,1.70,0,.5,.5,.5,faceRect(0,0,8,8,8))
  part(verts,0,1.07,0,.5,.75,.25,faceRect(16,16,8,12,4))
  part(verts,-.375,1.07,0,.25,.75,.25,faceRect(40,16,4,12,4))
  part(verts,.375,1.07,0,.25,.75,.25,faceRect(32,48,4,12,4))
  part(verts,-.125,.375,0,.25,.75,.25,faceRect(0,16,4,12,4))
  part(verts,.125,.375,0,.25,.75,.25,faceRect(16,48,4,12,4))
  local mesh=lovr.graphics.newMesh(format,verts,{storage='gpu'})
  mesh:setMaterial(texture)
  return setmetatable({mesh=mesh},Avatar)
end

function Avatar:draw(pass,player)
  pass:push()
  pass:translate(player.x,player.y,player.z)
  pass:rotate(player.yaw,0,1,0)
  pass:setColor(1,1,1)
  pass:draw(self.mesh)
  pass:pop()
end
return Avatar
