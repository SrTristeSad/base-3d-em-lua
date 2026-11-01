-- Native LÖVR GPU bridge for Luanti formspec images.
-- Prefer untouched upstream GUI PNGs from the package; otherwise reuse the
-- world atlas. Parsing, geometry, UVs and cache policy remain pure Lua.
local Atlas=require('core.atlas')
local Sprites={}
Sprites.__index=Sprites
local format={
 {name='VertexPosition',type='vec3'},
 {name='VertexNormal',type='vec3'},
 {name='VertexUV',type='vec2'},
 {name='VertexColor',type='vec4'},
}
local manifest_ok,manifest=pcall(require,'core.formspec_original_manifest')
local originals=manifest_ok and type(manifest)=='table' and manifest or {}
local function finite(n)
 return type(n)=='number' and n==n and
  n~=math.huge and n~=-math.huge
end
local function vertex(x,y,u,v)
 return {x,y,.06,0,0,1,u,v,1,1,1,1}
end
-- Luanti texture modifier indices are 0-based. No texture modifier is
-- approximated as another image: unsupported cases stay in the text fallback.
-- The bracket of the modifier is commonly not closed inside a formspec:
-- "saw.png^[verticalframe:3:1", so both spellings are accepted here.
function Sprites.source(tile)
 if type(tile)~='string' or #tile>256 then
  return nil,'invalid_texture'
 end
 local plain=tile:match('^([%w_.%-]+%.png)$')
 local animated=tile:match('^([%w_.%-]+%.png)%^%[verticalframe:%d+:%d+%]?$')
 local name=plain or animated
 if not name then return nil,'unsupported_texture_modifier' end
 local meta=originals[name]
 if meta and type(meta)=='table' and
  finite(meta.width) and finite(meta.height) and
  meta.width>=1 and meta.height>=1 then
  local v0,v1=0,1
  if animated then
   local count,index=tile:match('^'..name:gsub('%.','%%.')..
    '%^%[verticalframe:(%d+):(%d+)%]?$')
   count,index=tonumber(count),tonumber(index)
   if not count or not index or count<1 or count>512 or index>=count or
    meta.height%count~=0 then
    return nil,'invalid_verticalframe'
   end
   v0,v1=index/count,(index+1)/count
  end
  return {path='visual/formspec/'..name,uv={0,v0,1,v1},
   original=true,width=meta.width,height=meta.height}
 end
 if animated then return nil,'original_animation_texture_not_packaged' end
 if Atlas.index(tile)==1 and Atlas.name(tile)~='missing.png' then
  return nil,'unknown_texture'
 end
 return {path='visual/atlas.png',uv={Atlas.uv(tile)},original=false}
end
function Sprites.quad(tile,x,y,w,h)
 if type(tile)~='string' or not finite(x) or not finite(y) or
  not finite(w) or not finite(h) or w<=0 or h<=0 then
  return nil,'invalid_sprite'
 end
 local src,err=Sprites.source(tile)
 if not src then return nil,err end
 local u0,v0,u1,v1=src.uv[1],src.uv[2],src.uv[3],src.uv[4]
 local x0,x1=x-w/2,x+w/2
 local y0,y1=y-h/2,y+h/2
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
 return setmetatable({graphics=graphics,textures={},cache={},
  frame=0,max_entries=384},Sprites)
end
function Sprites:beginFrame()
 self.frame=self.frame+1
end
function Sprites:draw(pass,tile,x,y,w,h)
 assert(pass and type(pass.mesh)=='function' and
  type(pass.setMaterial)=='function','LÖVR Pass mesh required')
 local src,source_err=Sprites.source(tile)
 if not src then return false,source_err end
 local vertices,err=Sprites.quad(tile,x,y,w,h)
 if not vertices then return false,err end
 local key=table.concat({tile,tostring(x),tostring(y),
  tostring(w),tostring(h)},':')
 local entry=self.cache[key]
 if not entry then
  local buffer=self.graphics.newBuffer(format,vertices)
  entry={buffer=buffer,seen=self.frame}
  self.cache[key]=entry
 else
  entry.seen=self.frame
 end
 local texture=self.textures[src.path]
 if not texture then
  texture=self.graphics.newTexture(src.path)
  self.textures[src.path]=texture
 end
 pass:setMaterial(texture)
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
 -- Hard cap persistent buffers for changing server-authored layouts.
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
 for path,texture in pairs(self.textures) do
  if texture.release then texture:release() end
  self.textures[path]=nil
 end
end
return Sprites
