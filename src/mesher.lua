-- Streaming + greedy meshing (GPU). Uma malha por material em cada chunk.
-- Gera uma face apenas quando visivel e funde superficies retangulares iguais.
local Mesher={}
Mesher.__index=Mesher
local floor,abs=math.floor,math.abs
local SIDES={
 {1,0,0,.82},{-1,0,0,.82},{0,1,0,1},{0,-1,0,.55},
 {0,0,1,.72},{0,0,-1,.72}
}
local CORNERS={
 {{1,-1,-1},{1,-1,1},{1,1,1},{1,1,-1}},
 {{-1,-1,1},{-1,-1,-1},{-1,1,-1},{-1,1,1}},
 {{-1,1,-1},{1,1,-1},{1,1,1},{-1,1,1}},
 {{-1,-1,1},{1,-1,1},{1,-1,-1},{-1,-1,-1}},
 {{1,-1,1},{-1,-1,1},{-1,1,1},{1,1,1}},
 {{-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1}}
}
local UV={{0,1},{1,1},{1,0},{0,0}}
local TRI={1,2,3,1,3,4}
local FORMAT={
 {'VertexPosition','vec3'},{'VertexNormal','vec3'},
 {'VertexUV','vec2'},{'VertexColor','vec4'}
}
local function ck(cx,cy,cz) return cx..':'..cy..':'..cz end
local function visible(block,neighbor)
 if block==0 then return false end
 return neighbor==0 or (neighbor==9 and block~=9)
    or (neighbor==5 and block~=5)
    or (neighbor>=24 and neighbor<=28 and block~=neighbor)
    or (neighbor==29 and block~=29)
end
local function push(groups,material,face,fixed,u,v,width,height)
 local verts=groups[material]
 if not verts then verts={};groups[material]=verts end
 local x,y,z,dx,dy,dz
 if face<=2 then
  x,y,z=fixed,v+(height-1)/2,u+(width-1)/2
  dx,dy,dz=1,height,width
 elseif face<=4 then
  x,y,z=u+(width-1)/2,fixed,v+(height-1)/2
  dx,dy,dz=width,1,height
 else
  x,y,z=u+(width-1)/2,v+(height-1)/2,fixed
  dx,dy,dz=width,height,1
 end
 local dir=SIDES[face]
 for _,i in ipairs(TRI) do
  local c=CORNERS[face][i]
  verts[#verts+1]={
   x+c[1]*dx*.5,y+c[2]*dy*.5,z+c[3]*dz*.5,
   dir[1],dir[2],dir[3],UV[i][1]*width,UV[i][2]*height,
   dir[4],dir[4],dir[4],1
  }
 end
end
function Mesher.buildData(world,cx,cy,cz,faces)
 local groups={}
 local total=0
 local x0,y0,z0=cx*world.CHUNK,cy*world.CHUNK,cz*world.CHUNK
 local lighting=world.generatorVersion=='beta181' and world.lighting
 local columnCache={}
 for face,dir in ipairs(SIDES) do
  local fixedMin,fixedMax,us,vs,uCount,vCount
  if face<=2 then
   fixedMin,fixedMax=x0,x0+15
   us,vs=z0,y0
   uCount,vCount=16,16
  elseif face<=4 then
   fixedMin,fixedMax=y0,y0+15
   us,vs=x0,z0
   uCount,vCount=16,16
  else
   fixedMin,fixedMax=z0,z0+15
   us,vs=x0,y0
   uCount,vCount=16,16
  end
  for fixed=fixedMin,fixedMax do
   local mask={}
   for v=0,vCount-1 do
    for u=0,uCount-1 do
     local x,y,z
     if face<=2 then x,y,z=fixed,vs+v,us+u
     elseif face<=4 then x,y,z=us+u,fixed,vs+v
     else x,y,z=us+u,vs+v,fixed end
     local id=world:get(x,y,z)
     local neighbor=world:get(x+dir[1],y+dir[2],z+dir[3])
     if visible(id,neighbor) then
      local row=faces[id]
      if row then
       local material=row[face]
       if lighting then
        -- Separa faces com iluminacao distinta sem regenerar a malha
        -- a cada segundo: so o multiplicador de luz solar muda.
        local sky=lighting.skyLight
          and lighting:skyLight(x+dir[1],y+dir[2],z+dir[3])
          or (lighting:skyApprox(x+dir[1],y+dir[2],z+dir[3],
            columnCache) and 15 or 0)
        local skyBucket=math.min(5,math.floor((sky+1)/3))
        local light=lighting:blockLevel(x+dir[1],y+dir[2],z+dir[3])
        local bucket=math.min(3,math.floor((light+2)/4))
        material=material..'#'..skyBucket..'#'..bucket
       end
       mask[v*uCount+u+1]=material
      end
     end
    end
   end
   for v=0,vCount-1 do
    local u=0
    while u<uCount do
     local index=v*uCount+u+1
     local material=mask[index]
     if material then
      local width=1
      while u+width<uCount and
        mask[v*uCount+u+width+1]==material do width=width+1 end
      local height=1
      local more=true
      while v+height<vCount and more do
       for dx=0,width-1 do
        if mask[(v+height)*uCount+u+dx+1]~=material then
         more=false;break
        end
       end
       if more then height=height+1 end
      end
      for dy=0,height-1 do
       for dx=0,width-1 do
        mask[(v+dy)*uCount+u+dx+1]=nil
       end
      end
      push(groups,material,face,fixed,us+u,vs+v,width,height)
      total=total+1
      u=u+width
     else
      u=u+1
     end
    end
   end
  end
 end
 return groups,total
end
function Mesher.new(world,textures,faces)
 return setmetatable({world=world,textures=textures,faces=faces,
  chunks={},quads=0,rebuilds=0,pending=0,visibleCount=0},Mesher)
end
function Mesher:rebuild(cx,cy,cz)
 local groups,quads=Mesher.buildData(self.world,cx,cy,cz,self.faces)
 local id=ck(cx,cy,cz)
 local old=self.chunks[id]
 if old then
  for _,mesh in ipairs(old.meshes) do mesh:release() end
  self.quads=self.quads-old.quads
 end
 local meshes,lights={},{}
 for material,vertices in pairs(groups) do
  if #vertices>0 then
   local name,sky,bucket=material:match('^(.-)#(%d+)#(%d+)$')
   local mesh=lovr.graphics.newMesh(FORMAT,vertices,{storage='gpu'})
   mesh:setMaterial(self.textures[name or material])
   meshes[#meshes+1]=mesh
   if sky then
    lights[#meshes]={sky=math.min(15,tonumber(sky)*3),
     block=tonumber(bucket)*4}
   end
  end
 end
 self.chunks[id]={meshes=meshes,lightInfo=lights,quads=quads,
  cx=cx,cy=cy,cz=cz}
 self.quads=self.quads+quads
 self.rebuilds=self.rebuilds+1
 self.world.dirty[id]=nil
end
-- JANELA CUBICA: 4x4 seções horizontais x 3 seções verticais
-- (16x16x16 blocos por secao). Prioridade para as mais proximas.
function Mesher:sync(px,py,pz,view,budget)
 px,py,pz=px or 0,py or 0,pz or 0
 local half=1+math.max(1,math.min(3,view or 1))
 budget=budget or 2
 local minX,minZ=floor((px-half*16)/16),floor((pz-half*16)/16)
 local limit=half*2
 local desired={}
 local queue={}
 local centerX,centerY,centerZ=floor(px/16),floor(py/16),floor(pz/16)
 local bottom=math.max(floor(self.world.YMIN/16),centerY-1)
 local top=math.min(floor(self.world.YMAX/16),centerY+1)
 if self.world.generatorVersion=='beta181' then
  -- Overworld 128 blocos: inclui mais terreno abaixo do nível do jogador
  -- para evitar oceano flutuando sobre um vazio não renderizado.
  bottom=math.max(0,centerY-3)
  top=math.min(floor(self.world.YMAX/16),centerY+2)
 end
 for cy=bottom,top do
  for i=0,limit-1 do
   for j=0,limit-1 do
    local cx,cz=minX+i,minZ+j
    local k=ck(cx,cy,cz)
    desired[k]=true
    if not self.chunks[k] or self.world.dirty[k] then
     local priority=(cx-centerX)^2+(cy-centerY)^2+(cz-centerZ)^2
     queue[#queue+1]={cx=cx,cy=cy,cz=cz,key=k,priority=priority}
    end
   end
  end
 end
 for k,chunk in pairs(self.chunks) do
  if not desired[k] then
   for _,mesh in ipairs(chunk.meshes) do mesh:release() end
   self.quads=self.quads-chunk.quads
   self.chunks[k]=nil
  end
 end
 table.sort(queue,function(a,b)
  if a.priority~=b.priority then return a.priority<b.priority end
  return a.key<b.key
 end)
 self.pending=#queue
 local loaded=0
 for i=1,math.min(#queue,math.max(0,budget)) do
  self:rebuild(queue[i].cx,queue[i].cy,queue[i].cz)
  loaded=loaded+1
 end
 self.pending=self.pending-loaded
 if self.world.generatorVersion=='beta181' then
  self.world:prune(px,py,pz,half,3)
 else
  self.world:prune(px,py,pz,half,1)
 end
 local n=0
 for _ in pairs(self.chunks) do n=n+1 end
 self.visibleCount=n
 return loaded
end
function Mesher:draw(pass)
 local lighting=self.world.lighting
 local daytime=lighting and lighting:dayFactor() or 1
 for _,chunk in pairs(self.chunks) do
  for i,mesh in ipairs(chunk.meshes) do
   local info=chunk.lightInfo and chunk.lightInfo[i]
   if lighting and info then
    local block=math.min(1,(info.block or 0)/15)
    local ambient=.13+(daytime-.13)*(info.sky or 0)/15
    local light=math.max(ambient,.12+block*.85)
    pass:setColor(light,light,light,1)
   end
   pass:draw(mesh)
  end
 end
 if lighting then pass:setColor(1,1,1,1) end
end
return Mesher
