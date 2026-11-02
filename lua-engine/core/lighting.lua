-- Luanti 5.18 light banks, day/night blending and a conservative
-- Lua-only light-source propagation for the sparse world runtime.
--
-- The original engine stores propagated light in param1 during map updates.
-- Until that map lighting engine is ported, *emitted artificial light* is
-- traced on demand through registered light-passing nodes; no fake sunlight
-- is injected into unloaded or ungenerated chunks.
local Lighting={}
Lighting.__index=Lighting
local floor=math.floor
local max,min=math.max,math.min
local abs=math.abs
local dirs={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
local function level(v)
 if type(v)~='number' or v~=v then return 0 end
 return max(0,min(14,floor(v)))
end
local function finite(v)
 return type(v)=='number' and v==v and
  v~=math.huge and v~=-math.huge
end
-- Original src/daynightratio.h smooth mode (float intermediates).
local phases={
 {t=4375,value=175},{t=4625,value=175},
 {t=4875,value=250},{t=5125,value=350},
 {t=5375,value=500},{t=5625,value=675},
 {t=5875,value=875},{t=6125,value=1000},
 {t=6375,value=1000}
}
function Lighting.day_ratio(timeofday)
 assert(finite(timeofday),'timeofday must be finite')
 local t=(timeofday%1)*24000
 if t>12000 then t=24000-t end
 if t<=4625 then return 175 end
 if t>=6125 then return 1000 end
 for i=2,#phases do
  local upper=phases[i]
  if t<upper.t then
   local lower=phases[i-1]
   local f=(t-lower.t)/(upper.t-lower.t)
   return lower.value+(upper.value-lower.value)*f
  end
 end
 return 1000
end
function Lighting.artificial(param1)
 assert(type(param1)=='number' and param1==floor(param1) and
  param1>=0 and param1<=255,'param1 must be a byte')
 return floor(param1/16)
end
local function blend(ratio,day,night)
 return min(15,floor((ratio*day+(1000-ratio)*night)/1000))
end
local function transparent(name,def)
 if name=='air' then return true end
 if name=='ignore' then return false end
 return def and (def.paramtype=='light' or
  def.drawtype=='airlike' or def.drawtype=='plantlike' or
  def.drawtype=='glasslike' or def.drawtype=='liquid' or
  def.drawtype=='flowingliquid') or false
end
local function position_key(x,y,z)
 return x..','..y..','..z
end
-- The present Lua demo generator marks x/z 16-cell columns generated
-- for y=-16..31.  Do not claim sunlight in unknown/unloaded terrain.
local function generated(map,x,y,z)
 if x < -31000 or x > 31000 or z < -31000 or z > 31000 or
  y < -16 or y > 31 then return false end
 local k=floor(x/16)..','..floor(z/16)
 return map.generatedChunks and map.generatedChunks[k]~=nil
end
local function sun_passes(name,def)
 -- Luanti's sunlight_propagates flag controls vertical sunlight:
 -- transparent-looking nodes without the flag may still block it.
 return name=='air' or
  (name~='ignore' and def and def.sunlight_propagates==true)
end
function Lighting.new(runtime)
 return setmetatable({runtime=runtime,map=nil,revision=nil,
  registry_revision=nil,cache={},count=0,checks=0,
  skycache={},skycount=0,columncache={},columncount=0,
  source_blocks=nil},Lighting)
end
-- All lighting entrypoints share one revision gate. In particular,
-- direct_sun must not reuse a cached open column after its roof changes.
function Lighting:refresh()
 local rt=self.runtime
 local map=rt.map
 if self.map~=map or self.revision~=map.geometry_revision or
  self.registry_revision~=rt.light_registry_revision then
  self.map=map
  self.revision=map.geometry_revision
  self.registry_revision=rt.light_registry_revision
  self.cache={};self.count=0
  self.skycache={};self.skycount=0
  self.columncache={};self.columncount=0
  self.source_blocks=nil
 end
end
-- Search 27 mapblocks around the query, not every empty air voxel.
-- This prevents a million no-source BFS visits while meshing daylight.
function Lighting:has_near_source(pos)
 local blocks=self.source_blocks
 if not blocks then
  blocks={}
  for key,node in pairs(self.runtime.map.nodes) do
   local def=self.runtime.registry.nodes[node.name]
   if level(def and def.light_source)>0 then
    local x,y,z=key:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
    x,y,z=tonumber(x),tonumber(y),tonumber(z)
    if x and y and z then
     local block=position_key(floor(x/16),floor(y/16),floor(z/16))
     local list=blocks[block] or {}
     list[#list+1]={x=x,y=y,z=z,light=level(def.light_source)}
     blocks[block]=list
    end
   end
  end
  self.source_blocks=blocks
 end
 local bx,by,bz=floor(pos.x/16),floor(pos.y/16),floor(pos.z/16)
 local radius=0
 for x=bx-1,bx+1 do for y=by-1,by+1 do for z=bz-1,bz+1 do
  local list=blocks[position_key(x,y,z)]
  if list then for _,source in ipairs(list) do
   local dist=abs(source.x-pos.x)+abs(source.y-pos.y)+
    abs(source.z-pos.z)
   if dist<source.light then
    radius=max(radius,source.light)
   end
  end end
 end end end
 return radius
end
-- Get max light arriving at target from real registered emitters, with
-- six-neighbor falloff and blocking geometry. Sources emit from within
-- opaque blocks but light cannot pass through arbitrary opaque blocks.
-- This is a bounded prototype fallback, not native map-light updating.
function Lighting:emitted(pos)
 local rt=self.runtime
 local map=rt.map
 self:refresh()
 local key=position_key(pos.x,pos.y,pos.z)
 local hit=self.cache[key]
 if hit~=nil then return hit end
 self.checks=self.checks+1
 local max_source=self:has_near_source(pos)
 if max_source==0 then
  if self.count>=4096 then self.cache={};self.count=0 end
  self.cache[key]=0
  self.count=self.count+1
  return 0
 end
 local nodes=rt.registry.nodes
 local visited={[key]=true}
 local queue={{x=pos.x,y=pos.y,z=pos.z,d=0}}
 local head=1
 local strongest=0
 while head<=#queue do
  local cell=queue[head]
  head=head+1
  local node=map:get_node(cell)
  local def=nodes[node.name]
  local source=level(def and def.light_source)
  if source>cell.d then
   strongest=max(strongest,source-cell.d)
  end
  -- No source beyond this distance can improve the best known value.
  if strongest>=14-cell.d then break end
  if cell.d<max_source-1 and transparent(node.name,def) then
   for _,off in ipairs(dirs) do
    local x,y,z=cell.x+off[1],cell.y+off[2],cell.z+off[3]
    if abs(x)<=31000 and abs(y)<=31000 and abs(z)<=31000 then
     local k=position_key(x,y,z)
     if not visited[k] then
      visited[k]=true
      queue[#queue+1]={x=x,y=y,z=z,d=cell.d+1}
     end
    end
   end
  end
 end
 if self.count>=4096 then self.cache={};self.count=0 end
 self.cache[key]=strongest
 self.count=self.count+1
 return strongest
end
-- Check an x/z column only in the generation slab.  This is a
-- deterministic on-demand fallback, not baked MapNode param1 sunlight.
function Lighting:direct_sun(x,y,z)
 self:refresh()
 local map=self.runtime.map
 if not generated(map,x,y,z) then return false end
 local column=x..','..z
 local obstruction=self.columncache[column]
 if obstruction==nil then
  obstruction=-17
  local registry=self.runtime.registry.nodes
  for scan=31,-16,-1 do
   local name=map:get_node({x=x,y=scan,z=z}).name
   if not sun_passes(name,registry[name]) then
    obstruction=scan
    break
   end
  end
  if self.columncount>=2048 then self.columncache={};self.columncount=0 end
  self.columncache[column]=obstruction
  self.columncount=self.columncount+1
 end
 return y>obstruction
end
-- Return simulated unblended daylight at a generated map position, or
-- nil when the terrain is not generated.  A straight sky column is level
-- 15.  Sideways daylight spreads through six-neighbor transmissive cells
-- with one light level lost per step; opaque walls block it.
function Lighting:sky(pos)
 self:refresh()
 local map=self.runtime.map
 if not generated(map,pos.x,pos.y,pos.z) then return nil end
 local key=position_key(pos.x,pos.y,pos.z)
 if self.skycache[key]~=nil then return self.skycache[key] end
 local registry=self.runtime.registry.nodes
 local n=map:get_node(pos)
 local brightness=0
 if sun_passes(n.name,registry[n.name]) then
  if self:direct_sun(pos.x,pos.y,pos.z) then
   brightness=15
  else
   local queue={{x=pos.x,y=pos.y,z=pos.z,d=0}}
   local visited={[key]=true}
   local head=1
   while head<=#queue do
    local cell=queue[head]
    head=head+1
    if cell.d<14 then
     for _,offset in ipairs(dirs) do
      local x,y,z=cell.x+offset[1],cell.y+offset[2],
       cell.z+offset[3]
      local k=position_key(x,y,z)
      if not visited[k] and generated(map,x,y,z) then
       visited[k]=true
       local other=map:get_node({x=x,y=y,z=z})
       if sun_passes(other.name,registry[other.name]) then
        local dist=cell.d+1
        if self:direct_sun(x,y,z) then
         brightness=15-dist
         break
        end
        if dist<14 then
         queue[#queue+1]={x=x,y=y,z=z,d=dist}
        end
       end
      end
     end
    end
    if brightness>0 then break end
   end
  end
 end
 if self.skycount>=4096 then self.skycache={};self.skycount=0 end
 self.skycache[key]=brightness
 self.skycount=self.skycount+1
 return brightness
end
-- Keep light banks in their own per-mapblock array. A sparse map does
-- not store air as a normal node; forcing baked param1 into map.nodes would
-- turn empty air into millions of fake registered blocks. These arrays
-- model the two native 4-bit banks without modifying node contents.
local function blockkey(pos)
 return position_key(floor(pos.x/16),floor(pos.y/16),floor(pos.z/16))
end
local function blockindex(pos)
 return 1+(pos.x%16)*256+(pos.y%16)*16+(pos.z%16)
end
local function checked(pos)
 assert(type(pos)=='table' and finite(pos.x) and finite(pos.y)
  and finite(pos.z) and pos.x==floor(pos.x)
  and pos.y==floor(pos.y) and pos.z==floor(pos.z)
  and abs(pos.x)<=31000 and abs(pos.y)<=31000 and abs(pos.z)<=31000,
  'light position requires valid integer coordinates')
 return pos
end
local function packed(day,night)
 return day+16*night
end
-- The original world stores day in the low nibble and night in the high
-- nibble. Compute both *raw* banks; the 175/1000 night ratio is only used
-- when presenting them to the player, never baked into the night bank.
function Lighting:raw_banks(pos)
 local map=self.runtime.map
 local node=map:get_node(pos)
 local def=self.runtime.registry.nodes[node.name]
 local source=level(def and def.light_source)
 if def and def.paramtype=='light' and (node.param1 or 0)~=0 then
  return max(source,node.param1%16),
   max(source,floor(node.param1/16))
 end
 local emitted=self:emitted(pos)
 local night=max(source,emitted)
 local daylight=self:sky(pos)
 local day=max(night,daylight or 0)
 return day,night
end
function Lighting:baked_banks(pos)
 local map=self.runtime.map
 local blocks=map.lightbanks
 if not blocks then return nil end
 local block=blocks[blockkey(pos)]
 if not block or block.map_revision~=map.geometry_revision or
  block.registry_revision~=self.runtime.light_registry_revision then
  return nil
 end
 local marker=map.generatedChunks and map.generatedChunks[
  floor(pos.x/16)..','..floor(pos.z/16)]
 if block.generated_marker~=marker then return nil end
 local value=block.values[blockindex(pos)] or 0
 return value%16,floor(value/16)
end
-- Rebuild exactly one 16^3 block transactionally. No half-updated bank
-- is visible if the computation fails. Packed bank zero still counts as
-- computed; readers never substitute stale lighting for darkness.
function Lighting:relight_block(cx,cy,cz)
 assert(type(cx)=='number' and cx==floor(cx) and
  type(cy)=='number' and cy==floor(cy) and
  type(cz)=='number' and cz==floor(cz),
  'light mapblock coordinates must be integers')
 local map=self.runtime.map
 -- The current Lua generator marks whole x/z columns for y=-16..31.
 local marker=map.generatedChunks and map.generatedChunks[cx..','..cz]
 if not marker or cy<-1 or cy>1 or
  abs(cx*16)>31000 or abs(cx*16+15)>31000 or
  abs(cz*16)>31000 or abs(cz*16+15)>31000 then
  return false
 end
 self:refresh()
 local values={}
 local nonzero=0
 local index=1
 for x=cx*16,cx*16+15 do
  for y=cy*16,cy*16+15 do
   for z=cz*16,cz*16+15 do
    local day,night=self:raw_banks({x=x,y=y,z=z})
    local byte=packed(day,night)
    if byte~=0 then
     values[index]=byte
     nonzero=nonzero+1
    end
    index=index+1
   end
  end
 end
 map.lightbanks=map.lightbanks or {}
 map.lightbanks[position_key(cx,cy,cz)]={
  values=values,map_revision=map.geometry_revision,
  registry_revision=self.runtime.light_registry_revision,
  generated_marker=marker,nonzero=nonzero}
 return true
end
function Lighting:fix_light(p1,p2)
 p1,p2=checked(p1),checked(p2)
 assert(p1.x<=p2.x and p1.y<=p2.y and p1.z<=p2.z,
  'fix_light corners must be ordered')
 local ax,ay,az=floor(p1.x/16),floor(p1.y/16),floor(p1.z/16)
 local bx,by,bz=floor(p2.x/16),floor(p2.y/16),floor(p2.z/16)
 -- The upstream engine can load arbitrary maps. The Lua engine presently
 -- only knows generated demo columns and caps updates to 8 mapblocks.
 if (bx-ax+1)*(by-ay+1)*(bz-az+1)>8 then return false end
 local map=self.runtime.map
 for cx=ax,bx do for cy=ay,by do for cz=az,bz do
  local marker=map.generatedChunks and map.generatedChunks[cx..','..cz]
  if not marker or cy < -1 or cy > 1 then return false end
 end end end
 for cx=ax,bx do for cy=ay,by do for cz=az,bz do
  if not self:relight_block(cx,cy,cz) then return false end
 end end end
 return true
end
function Lighting:get_natural_light(pos,timeofday)
 assert(type(pos)=='table' and finite(pos.x) and
  finite(pos.y) and finite(pos.z) and
  pos.x==floor(pos.x) and pos.y==floor(pos.y) and
  pos.z==floor(pos.z),'natural light requires integer position')
 if timeofday~=nil then
  assert(finite(timeofday),'timeofday must be finite')
 end
 local daylight=self:sky(pos)
 if daylight==nil then return nil end
 local t=timeofday
 if t==nil then t=self.runtime.api.get_timeofday() end
 return min(15,floor(daylight*Lighting.day_ratio(t)/1000))
end
function Lighting:get_node_light(pos,timeofday)
 assert(type(pos)=='table' and finite(pos.x) and
  finite(pos.y) and finite(pos.z) and
  pos.x==floor(pos.x) and pos.y==floor(pos.y) and
  pos.z==floor(pos.z),'node light requires integer position')
 local day,night=self:baked_banks(pos)
 if day==nil then
  day,night=self:raw_banks(pos)
 end
 local t=timeofday
 if t==nil then t=self.runtime.api.get_timeofday() end
 local ratio=Lighting.day_ratio(t)
 return blend(ratio,day,night)
end
return Lighting
