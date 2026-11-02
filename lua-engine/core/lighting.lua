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
function Lighting.new(runtime)
 return setmetatable({runtime=runtime,map=nil,revision=nil,
  registry_revision=nil,cache={},count=0,checks=0},Lighting)
end
-- Get max light arriving at target from real registered emitters, with
-- six-neighbor falloff and blocking geometry. Sources emit from within
-- opaque blocks but light cannot pass through arbitrary opaque blocks.
-- This is a bounded prototype fallback, not native map-light updating.
function Lighting:emitted(pos)
 local rt=self.runtime
 local map=rt.map
 if self.map~=map or self.revision~=map.geometry_revision or
  self.registry_revision~=rt.light_registry_revision then
  self.map=map
  self.revision=map.geometry_revision
  self.registry_revision=rt.light_registry_revision
  self.cache={}
  self.count=0
 end
 local key=position_key(pos.x,pos.y,pos.z)
 local hit=self.cache[key]
 if hit~=nil then return hit end
 self.checks=self.checks+1
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
  if cell.d<13 and transparent(node.name,def) then
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
function Lighting:get_node_light(pos,timeofday)
 assert(type(pos)=='table' and finite(pos.x) and
  finite(pos.y) and finite(pos.z) and
  pos.x==floor(pos.x) and pos.y==floor(pos.y) and
  pos.z==floor(pos.z),'node light requires integer position')
 local map=self.runtime.map
 local node=map:get_node(pos)
 local def=self.runtime.registry.nodes[node.name]
 local source=level(def and def.light_source)
 local day,night=source,source
 if node.param1 and def and def.paramtype=='light' then
  day=max(day,node.param1%16)
  night=max(night,floor(node.param1/16))
 end
 -- Sparse Lua worlds don't run the original Luanti light updater yet.
 -- If both banks were explicitly supplied, respect them as authoritative.
 if day==source and night==source then
  local emitted=self:emitted(pos)
  day=max(day,emitted)
  night=max(night,emitted)
 end
 local t=timeofday
 if t==nil then t=self.runtime.api.get_timeofday() end
 local ratio=Lighting.day_ratio(t)
 return blend(ratio,day,night)
end
return Lighting
