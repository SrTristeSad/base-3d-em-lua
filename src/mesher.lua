local Mesher = {}
Mesher.__index = Mesher
local directions = {
  { 1,0,0, .82 }, {-1,0,0, .82 }, {0,1,0,1}, {0,-1,0,.55},
  {0,0,1,.72}, {0,0,-1,.72}
}
local corners = {
  { {1,-1,-1},{1,-1,1},{1,1,1},{1,1,-1} },
  { {-1,-1,1},{-1,-1,-1},{-1,1,-1},{-1,1,1} },
  { {-1,1,-1},{1,1,-1},{1,1,1},{-1,1,1} },
  { {-1,-1,1},{1,-1,1},{1,-1,-1},{-1,-1,-1} },
  { {1,-1,1},{-1,-1,1},{-1,1,1},{1,1,1} },
  { {-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1} }
}
local uv = { {0,1},{1,1},{1,0},{0,0} }
local triangles = {1,2,3,1,3,4}
local format = {
  {'VertexPosition','vec3'}, {'VertexNormal','vec3'},
  {'VertexUV','vec2'}, {'VertexColor','vec4'}
}
local function pushQuad(v, x,y,z, face)
  local d,quad = directions[face],corners[face]
  for _, i in ipairs(triangles) do
    local c = quad[i]
    v[#v+1] = {x+c[1]*.5,y+c[2]*.5,z+c[3]*.5,
      d[1],d[2],d[3],uv[i][1],uv[i][2],d[4],d[4],d[4],1}
  end
end

function Mesher.new(world, textures, faces)
  return setmetatable({world=world, textures=textures, faces=faces, chunks={}}, Mesher)
end

function Mesher:rebuild(cx,cz)
  local w=self.world
  local groups={}
  for x=cx*w.CHUNK,(cx+1)*w.CHUNK-1 do
    for z=cz*w.CHUNK,(cz+1)*w.CHUNK-1 do
      if x>=w.MIN and x<=w.MAX and z>=w.MIN and z<=w.MAX then
        for y=w.YMIN,w.YMAX do
          local id = w:get(x,y,z)
          if id~=0 then
            for face,d in ipairs(directions) do
              local other = w:get(x+d[1],y+d[2],z+d[3])
              -- Leaves and water are opaque in this starter build.
              if other==0 then
                local material=self.faces[id][face]
                local verts=groups[material]
                if not verts then verts={}; groups[material]=verts end
                pushQuad(verts,x,y,z,face)
              end
            end
          end
        end
      end
    end
  end
  local id=cx..':'..cz
  if self.chunks[id] then
    for _,mesh in pairs(self.chunks[id]) do mesh:release() end
  end
  local meshes={}
  for material, vertices in pairs(groups) do
    if #vertices>0 then
      local mesh=lovr.graphics.newMesh(format,vertices,{storage='gpu'})
      mesh:setMaterial(self.textures[material])
      meshes[#meshes+1]=mesh
    end
  end
  self.chunks[id]=meshes
  w.dirty[id]=nil
end

function Mesher:sync()
  for key in pairs(self.world.dirty) do
    local cx,cz=key:match('^(-?%d+):(-?%d+)$')
    self:rebuild(tonumber(cx),tonumber(cz))
  end
end

function Mesher:draw(pass,px,pz,radius)
  local cx,cz = math.floor(px/16),math.floor(pz/16)
  for key,meshes in pairs(self.chunks) do
    local x,z=key:match('^(-?%d+):(-?%d+)$')
    if math.abs(tonumber(x)-cx)<=radius and math.abs(tonumber(z)-cz)<=radius then
      for _,mesh in ipairs(meshes) do pass:draw(mesh) end
    end
  end
end
return Mesher
