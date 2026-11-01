-- LÖVR formspec sprite bridge backed by the SAME generated VoxeLibre atlas
-- used by the world mesher. The source engine, atlas lookup and geometry
-- remain Lua; the native LÖVR graphics API only allocates/draws GPU buffers.
local Atlas=require('core.atlas')
local Sprites={}
Sprites.__index=Sprites
local vertex_format={
 {name='VertexPosition',type='vec3'},
 {name='VertexNormal',type='vec3'},
 {name='VertexUV',type='vec2'},
 {name='VertexColor',type='vec4'},
}
local function finite(n)
 return type(n)=='number' and n==n and
  n~=math.huge and n~=-math.huge
end
local function vertex(x,y,u,v)
 return {x,y,.06,0,0,1,u,v,1,1,1,1}
end
-- Independent function so headless API tests can verify exact atlas UVs,
-- screen geometry and triangle winding without a GPU.
function Sprites.quad(tile,x,y,w,h)
 if type(tile)~='string' or not finite(x) or not finite(y) or
  not finite(w) or not finite(h) or w<=0 or h<=0 then
  return nil,'invalid_sprite'
 end
 if Atlas.index(tile)==1 and Atlas.name(tile)~='missing.png' then
  return nil,'unknown_texture'
 end
 local u0,v0,u1,v1=Atlas.uv(tile)
 local x0,x1=x-w/2,x+w/2
 local y0,y1=y-h/2,y+h/2
 -- Top-left, bottom-left, bottom-right, top-right in formspec coordinates.
 local corners={
  vertex(x0,y0,u0,v0),vertex(x0,y1,u0,v1),
  vertex(x1,y1,u1,v1),vertex(x1,y0,u1,v0),
 }
 return {corners[1],corners[2],corners[3],
  corners[1],corners[3],corners[4]}
end
function Sprites.new(graphics)
 assert(type(graphics)=='table' and
  type(graphics.newBuffer)=='function' and
  type(graphics.newTexture)=='function','LÖVR graphics required')
 return setmetatable({graphics=graphics,texture=nil,cache={},
  frame=0,max_entries=384},Sprites)
end
function Sprites:beginFrame()
 self.frame=self.frame+1
end
function Sprites:draw(pass,tile,x,y,w,h)
 assert(pass and type(pass.mesh)=='function' and
  type(pass.setMaterial)=='function','LÖVR Pass mesh required')
 local vertices,err=Sprites.quad(tile,x,y,w,h)
 if not vertices then return false,err end
 local key=table.concat({tile,tostring(x),tostring(y),
  tostring(w),tostring(h)},':')
 local entry=self.cache[key]
 if not entry then
  -- Only build a GPU quad the first time this exact sprite/layout is used.
  -- Source-only tests never need to create graphics resources.
  local buffer=self.graphics.newBuffer(vertex_format,vertices)
  entry={buffer=buffer,seen=self.frame}
  self.cache[key]=entry
 else
  entry.seen=self.frame
 end
 if not self.texture then
  self.texture=self.graphics.newTexture('visual/atlas.png')
 end
 pass:setMaterial(self.texture)
 pass:setColor(1,1,1,1)
 pass:mesh(entry.buffer,0,0,0)
 pass:setMaterial()
 return true
end
function Sprites:endFrame()
 local remaining=0
 for key,entry in pairs(self.cache) do
  if self.frame-entry.seen>2 then
   if entry.buffer.release then entry.buffer:release() end
   self.cache[key]=nil
  else remaining=remaining+1 end
 end
 -- Hard cap so malicious formspecs cannot create unlimited persistent
 -- GPU buffers by continuously moving sprites around.
 if remaining>self.max_entries then
  for key,entry in pairs(self.cache) do
   if entry.seen~=self.frame then
    if entry.buffer.release then entry.buffer:release() end
    self.cache[key]=nil;remaining=remaining-1
    if remaining<=self.max_entries then break end
   end
  end
 end
end
function Sprites:release()
 for key,entry in pairs(self.cache) do
  if entry.buffer.release then entry.buffer:release() end
  self.cache[key]=nil
 end
 if self.texture and self.texture.release then self.texture:release() end
 self.texture=nil
end
return Sprites
