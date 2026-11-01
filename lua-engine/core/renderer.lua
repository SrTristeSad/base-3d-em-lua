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
 return setmetatable({graphics=graphics,cache={},dynamic_cache={},
  dynamic_registry=nil,map=nil,texture=nil,frame=0,rebuilt=0,
  drawcalls=0,dynamic_drawcalls=0,dynamic_rebuilt=0},R)
end
local function release_cache(cache)
 for _,entry in pairs(cache) do
  if entry.buffer and entry.buffer.release then entry.buffer:release() end
 end
end
function R:reset()
 release_cache(self.cache)
 release_cache(self.dynamic_cache)
 self.cache={}
 self.dynamic_cache={}
 self.dynamic_registry=nil
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
-- Dynamic objects have their own origin-centered meshes. World mapblock
-- buffers do not contain these nodes after core.spawn_falling_node, so the
-- draw pass must not rebuild the static map mesh for each falling frame.
local function in_range(pos,camera,radius)
 local x,y,z=pos.x-camera.x,pos.y-camera.y,pos.z-camera.z
 return x*x+y*y+z*z<=radius*radius
end
local function cache_mesh(self,key,vertices)
 local entry=self.dynamic_cache[key]
 if not entry then
  entry={buffer=#vertices>0 and self.graphics.newBuffer(format,vertices)
   or nil,seen=self.frame}
  self.dynamic_cache[key]=entry
  self.dynamic_rebuilt=self.dynamic_rebuilt+1
 end
 entry.seen=self.frame
 return entry.buffer
end
-- Called after draw() by the LÖVR host. Works with mock Pass implementations
-- and does not call LÖVR directly from the Lua gameplay runtime.
function R:draw_dynamic(pass,runtime,camera,radius)
 assert(pass and type(pass.mesh)=='function',
  'draw_dynamic needs a LÖVR-compatible Pass')
 assert(type(runtime)=='table' and type(runtime.registry)=='table'
  and type(runtime.api)=='table','runtime required for dynamic rendering')
 assert(type(camera)=='table','camera position required')
 radius=radius or 20
 assert(type(radius)=='number' and radius>=0,
  'dynamic draw radius must be nonnegative')
 if self.dynamic_registry and self.dynamic_registry~=runtime.registry.nodes then
  release_cache(self.dynamic_cache)
  self.dynamic_cache={}
 end
 self.dynamic_registry=runtime.registry.nodes
 self.dynamic_drawcalls=0
 if not self.texture then
  self.texture=self.graphics.newTexture('visual/atlas.png')
 end
 pass:setSampler('nearest')
 pass:setMaterial(self.texture)
 pass:setColor(1,1,1,1)
 local falling=runtime.api.get_falling_nodes()
 for _,obj in ipairs(falling) do
  if in_range(obj.pos,camera,radius) then
   local node=obj.node
   local key='node:'..node.name..':'..(node.param1 or 0)..':'..
    (node.param2 or 0)
   local entry=self.dynamic_cache[key]
   local buffer=entry and entry.buffer or nil
   if not entry then
    local vertices=Mesher.single_node(node,runtime.registry.nodes)
    buffer=cache_mesh(self,key,vertices)
   else entry.seen=self.frame end
   if buffer then
    pass:mesh(buffer,obj.pos.x,obj.pos.y,obj.pos.z)
    self.dynamic_drawcalls=self.dynamic_drawcalls+1
   end
  end
 end
 local dropped=runtime.api.get_dropped_items()
 for _,obj in ipairs(dropped) do
  if in_range(obj.pos,camera,radius) then
   local stack=obj.stack
   local name=stack:get_name()
   local definition=runtime.registry.items[name]
   local tile=definition and (definition.inventory_image or
     definition.wield_image) or nil
   local node_def=runtime.registry.nodes[name]
   if node_def and (not tile or tile=='') then
    tile=(node_def.tiles and (node_def.tiles[1] or node_def.tiles[3]))
      or 'missing.png'
   end
   if not tile or tile=='' then tile='missing.png' end
   local key='item:'..name..':'..tostring(tile)
   local entry=self.dynamic_cache[key]
   local buffer=entry and entry.buffer or nil
   if not entry then
    local vertices=Mesher.item_cube(tile,.32)
    buffer=cache_mesh(self,key,vertices)
   else entry.seen=self.frame end
   if buffer then
    -- Raised slightly to make collected-size item cubes visible above soil.
    pass:mesh(buffer,obj.pos.x,obj.pos.y+.15,obj.pos.z)
    self.dynamic_drawcalls=self.dynamic_drawcalls+1
   end
  end
 end
 -- Never grow GPU buffers forever when mods introduce many transient items.
 for id,entry in pairs(self.dynamic_cache) do
  if self.frame-entry.seen>600 then
   if entry.buffer and entry.buffer.release then entry.buffer:release() end
   self.dynamic_cache[id]=nil
  end
 end
 pass:setMaterial()
end
return R
