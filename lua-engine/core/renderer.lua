-- GPU bridge for pure Lua mapblock mesher, LÖVR 0.19 Pass:mesh.
-- Rendering is independent of Luanti C++; the LÖVR GPU remains a native API.
local Mesher=require('core.mesher')
local R={}
R.__index=R
local format={
 {name='VertexPosition',type='vec3'},
 {name='VertexNormal',type='vec3'},
 {name='VertexUV',type='vec2'},
 {name='VertexColor',type='vec4'},
}
local floor=math.floor
local function key(x,y,z) return x..','..y..','..z end
function R.new(graphics)
 assert(graphics and type(graphics.newBuffer)=='function',
  'renderer requires LÖVR graphics')
 return setmetatable({graphics=graphics,cache={},map=nil,
  texture=nil,frame=0,rebuilt=0,drawcalls=0},R)
end
function R:reset()
 for _,entry in pairs(self.cache) do
  if entry.buffer and entry.buffer.release then entry.buffer:release() end
 end
 self.cache={}
 self.map=nil
end
function R:refresh(map,registry,cx,cy,cz)
 if map~=self.map then
  self:reset()
  self.map=map
 end
 local id=key(cx,cy,cz)
 local rev=Mesher.fingerprint(map,cx,cy,cz)
 local entry=self.cache[id]
 if entry and entry.revision==rev and entry.registry==registry then
  entry.seen=self.frame
  return entry
 end
 local vertices,stats=Mesher.build(map,registry,cx,cy,cz)
 local buffer=nil
 if #vertices>0 then
  buffer=self.graphics.newBuffer(format,vertices)
 end
 if entry and entry.buffer and entry.buffer.release then
  entry.buffer:release()
 end
 entry={buffer=buffer,revision=rev,registry=registry,
  stats=stats,seen=self.frame}
 self.cache[id]=entry
 self.rebuilt=self.rebuilt+1
 return entry
end
function R:draw(pass,map,registry,camera,radius)
 assert(pass and type(pass.mesh)=='function','draw needs LÖVR pass')
 assert(type(camera)=='table','camera position required')
 radius=radius or 20
 local cr=math.max(1,math.ceil(radius/16))
 local cx,cy,cz=floor(camera.x/16),floor(camera.y/16),floor(camera.z/16)
 self.frame=self.frame+1
 self.drawcalls=0
 if not self.texture then
  self.texture=self.graphics.newTexture('visual/atlas.png')
 end
 pass:setSampler('nearest')
 pass:setMaterial(self.texture)
 pass:setColor(1,1,1,1)
 for x=cx-cr,cx+cr do
  for y=cy-cr,cy+cr do
   for z=cz-cr,cz+cr do
    local entry=self:refresh(map,registry,x,y,z)
    if entry.buffer then
     -- Vertices are already in world space, so no extra node transforms.
     pass:mesh(entry.buffer,0,0,0)
     self.drawcalls=self.drawcalls+1
    end
   end
  end
 end
 -- Keep cache bounded when players fly across the world.
 for id,entry in pairs(self.cache) do
  if self.frame-entry.seen>2 then
   if entry.buffer and entry.buffer.release then entry.buffer:release() end
   self.cache[id]=nil
  end
 end
 pass:setMaterial()
end
return R
