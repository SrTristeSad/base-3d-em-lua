-- Luanti 5.18 VoxelManipulator / MMVManip generation-area subset.
-- References: src/voxel.h (NO_DATA, CHECKED1, CONTENT_IGNORE),
-- src/voxel.cpp (copyTo skips ignore) and MapgenV7::generateTerrain.
-- SPDX-License-Identifier: LGPL-2.1-or-later
--
-- A sparse, map-shaped staging adapter. It distinguishes not-yet-emerged
-- CONTENT_IGNORE from known air, retains transient voxel flags, and exposes
-- original 1-mapblock border extents. Only the chunk CORE is committed:
-- writing incomplete border nodes to the live map would falsely mark them
-- generated and break emerge_area/MapBlockStore.
local Buffer={}
Buffer.__index=Buffer
Buffer.FLAG_NO_DATA=1
Buffer.FLAG_CHECKED1=2  -- VMANIP_FLAG_CAVE
Buffer.FLAG_CHECKED2=4
Buffer.FLAG_CHECKED3=8
Buffer.FLAG_CHECKED4=16
local floor=math.floor
local function inbounds(p,a,b)
 return p.x>=a.x and p.x<=b.x and
  p.y>=a.y and p.y<=b.y and
  p.z>=a.z and p.z<=b.z
end
local function indexkey(p)
 return p.x..','..p.y..','..p.z
end
local function validpos(p)
 assert(type(p)=='table','voxel buffer position required')
 for _,axis in ipairs({'x','y','z'}) do
  local v=p[axis]
  assert(type(v)=='number' and v==floor(v) and
   math.abs(v)<=31000,'invalid generation voxel position')
 end
end
local function copy(n)
 return {name=n.name,param1=n.param1 or 0,param2=n.param2 or 0}
end
function Buffer.new(map,geom)
 assert(map and map.nodes and map.revisions and
  type(map.get_node)=='function' and
  type(map.set_node)=='function',
  'generation buffer requires a source map')
 assert(type(geom)=='table' and
  type(geom.node_min)=='table' and
  type(geom.node_max)=='table' and
  type(geom.full_node_min)=='table' and
  type(geom.full_node_max)=='table',
  'generation buffer requires full Luanti chunk geometry')
 for _,p in ipairs({geom.node_min,geom.node_max,
  geom.full_node_min,geom.full_node_max}) do validpos(p) end
 for _,axis in ipairs({'x','y','z'}) do
  assert(geom.full_node_min[axis]<=geom.node_min[axis] and
   geom.node_min[axis]<=geom.node_max[axis] and
   geom.node_max[axis]<=geom.full_node_max[axis],
   'invalid generation buffer boundaries')
 end
 local xmin,ymin,zmin=geom.full_node_min.x,
  geom.full_node_min.y,geom.full_node_min.z
 local sx=geom.full_node_max.x-xmin+1
 local sy=geom.full_node_max.y-ymin+1
 local sz=geom.full_node_max.z-zmin+1
 return setmetatable({
  source=map,geometry=geom,is_gen_buffer=true,extended_y=true,
  overlay={},modified={},flags={},air_columns={},air_columns_count=0,
  resident_original={},resident_modified={},resident_halo_ground=nil,
  writes=0,discarded_border=0,
  core_nodes=0,voxel_count=sx*sy*sz,
  sx=sx,sy=sy,sz=sz,origin={x=xmin,y=ymin,z=zmin}
 },Buffer)
end
function Buffer:contains(pos)
 return inbounds(pos,self.geometry.full_node_min,
  self.geometry.full_node_max)
end
function Buffer:core_contains(pos)
 return inbounds(pos,self.geometry.node_min,self.geometry.node_max)
end
-- Original VoxelArea layout: X changes fastest, followed by Y, then Z.
-- Lua uses 1-based indices; C++ area.index uses 0-based indices.
function Buffer:index(pos)
 assert(self:contains(pos),'generation voxel outside MMVManip area')
 return (pos.z-self.origin.z)*self.sx*self.sy+
  (pos.y-self.origin.y)*self.sx+(pos.x-self.origin.x)+1
end
function Buffer:_resident(pos)
 local key=self.source:blockkey(pos)
 return self.source.revisions[key] or self.source.last_active[key] or
  self.source.lbm_applied[key]
end
-- The C++ ManualMapVoxelManipulator initialEmerge also reads already
-- loaded neighbor mapblocks. Only cave carving can request edits to their
-- known ground nodes; terrain generation still protects their contents.
function Buffer:enable_resident_halo_caves(ground_name)
 assert(type(ground_name)=='string' and ground_name~='',
  'resident halo cave ground name required')
 self.resident_halo_ground=ground_name
end
function Buffer:disable_resident_halo_caves()
 self.resident_halo_ground=nil
end
function Buffer:can_carve_resident(pos)
 if not self:contains(pos) or self:core_contains(pos) or
    self.resident_halo_ground==nil or not self:_resident(pos) then
  return false
 end
 local key=indexkey(pos)
 -- A cave must not remove nodes bearing metadata or running timers.
 if self.source.metadata[key] or self.source.timers[key] then return false end
 local n=self.source:get_node(pos)
 return n.name==self.resident_halo_ground
end
-- During V7 terrain generation, a complete vertical column is known to
-- contain air EXCEPT at its explicit non-air entries. Store the known-air
-- default once per column instead of allocating a Lua node/key per sky voxel.
-- This only represents staged generation; it does not mark live mapblocks.
function Buffer:begin_terrain_column(x,z,ymin,ymax)
 local a,b=self.geometry.full_node_min,self.geometry.full_node_max
 local p={x=x,y=ymin,z=z}
 assert(self:contains(p) and self:contains({x=x,y=ymax,z=z}) and
  ymin<=ymax,'terrain column outside MMVManip area')
 local key=x..','..z
 assert(not self.air_columns[key],
  'cannot begin a terrain column more than once')
 self.air_columns[key]={ymin=ymin,ymax=ymax}
 self.air_columns_count=self.air_columns_count+1
end
function Buffer:_known_air(pos)
 local col=self.air_columns[pos.x..','..pos.z]
 return col and pos.y>=col.ymin and pos.y<=col.ymax
end
function Buffer:terrain_writable(pos)
 assert(self:contains(pos),'generation voxel outside MMVManip area')
 return not self.overlay[indexkey(pos)] and not self:_resident(pos)
end
function Buffer:get_node(pos)
 assert(self:contains(pos),'generation voxel outside MMVManip area')
 local v=self.overlay[indexkey(pos)]
 if v then return copy(v) end
 if self:_resident(pos) then return self.source:get_node(pos) end
 if self:_known_air(pos) then return {name='air',param1=0,param2=0} end
 return {name='ignore',param1=0,param2=0}
end
function Buffer:get_flags(pos)
 assert(self:contains(pos),'generation voxel outside MMVManip area')
 local key=indexkey(pos)
 local flags=self.flags[key] or 0
 if self.overlay[key] or self:_resident(pos) or self:_known_air(pos) then
  return flags
 end
 return flags+Buffer.FLAG_NO_DATA
end
function Buffer:mark_cave(pos)
 assert(self:contains(pos),'generation voxel outside MMVManip area')
 local key=indexkey(pos)
 if self:get_node(pos).name=='ignore' then return false end
 local flags=self.flags[key] or 0
 if floor(flags/Buffer.FLAG_CHECKED1)%2==0 then
  self.flags[key]=flags+Buffer.FLAG_CHECKED1
 end
 return true
end
function Buffer:set_node(pos,node)
 assert(self:contains(pos),'generation voxel outside MMVManip area')
 assert(type(node)=='table' and type(node.name)=='string' and
  node.name~='' and node.name~='ignore',
  'cannot write CONTENT_IGNORE as generated data')
 local k=indexkey(pos)
 -- Existing mapblocks are immutable to terrain generation. A cave may
 -- change a known ground node in the halo only when explicitly enabled.
 if self:_resident(pos) then
  if self.resident_halo_ground==nil then return false end
  if not self.resident_original[k] then
   if not self:can_carve_resident(pos) then return false end
   self.resident_original[k]=copy(self.source:get_node(pos))
  end
  self.resident_modified[k]=true
 end
 -- An air node under the column's known-air default needs no allocation
 -- unless it replaces explicit ground (e.g. after cave excavation).
 if node.name=='air' and not self.overlay[k] and self:_known_air(pos) then
  return true
 end
 self.overlay[k]=copy(node) -- explicit air still replaces excavated stone
 self.modified[k]=true
 self.flags[k]=nil
 self.writes=self.writes+1
 return true
end
function Buffer:remove_node(pos)
 return self:set_node(pos,{name='air'})
end
-- Luanti 5.18 MMVManip::getCoveredBlocks (src/map.cpp): a mapblock
-- is covered if ANY position in it has data (!VOXELFLAG_NO_DATA).
-- The Lua representation can count a known-air column in O(number of
-- Y mapblocks), instead of allocating all individual air voxels.
-- Returned keys are block positions, values are the same booleans as
-- the original covered-block map (only true entries need copying).
function Buffer:getCoveredBlocks()
 local result={}
 local function visit(p)
  if self:contains(p) then
   result[self.source:blockkey(p)]=true
  end
 end
 for key in pairs(self.overlay) do
  local x,y,z=key:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  visit({x=tonumber(x),y=tonumber(y),z=tonumber(z)})
 end
 for key,rng in pairs(self.air_columns) do
  local x,z=key:match('^(%-?%d+),(%-?%d+)$')
  x,z=tonumber(x),tonumber(z)
  for by=floor(rng.ymin/16),floor(rng.ymax/16) do
   visit({x=x,y=by*16,z=z})
  end
 end
 -- initialEmerge also copies loaded mapblocks, including their
 -- implicit-air cells. A loaded but all-air block is covered.
 local function resident(block)
  local bx,by,bz=block:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  if bx then
   local p={x=tonumber(bx)*16,y=tonumber(by)*16,
    z=tonumber(bz)*16}
   local max={x=p.x+15,y=p.y+15,z=p.z+15}
   local a,b=self.geometry.full_node_min,self.geometry.full_node_max
   if max.x>=a.x and max.y>=a.y and max.z>=a.z and
    p.x<=b.x and p.y<=b.y and p.z<=b.z then
    result[block]=true
   end
  end
 end
 for key in pairs(self.source.revisions) do resident(key) end
 for key in pairs(self.source.last_active) do resident(key) end
 for key in pairs(self.source.lbm_applied) do resident(key) end
 return result
end
-- Imported MMVManip voxels are the initial state, not modifications.
-- Cave writes after this point can be copied back to partial neighbors.
function Buffer:mark_imports_clean()
 self.modified={}
end
local function same(a,b)
 return a.name==b.name and (a.param1 or 0)==(b.param1 or 0)
  and (a.param2 or 0)==(b.param2 or 0)
end
-- A preflight prevents overwriting edits performed after initialEmerge.
-- It runs before any live-map writes, including the generated core.
function Buffer:validate_resident_halo()
 local map=self.source
 for k in pairs(self.resident_modified) do
  local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  local p={x=tonumber(x),y=tonumber(y),z=tonumber(z)}
  assert(self:contains(p) and not self:core_contains(p) and
   self:_resident(p) and self.resident_original[k] and
   not map.metadata[k] and not map.timers[k] and
   same(map:get_node(p),self.resident_original[k]),
   'MMVManip resident halo changed during mapgen')
 end
end
-- Equivalent to MMVManip::copyTo/ServerMap::finishBlockMake for the
-- generated core only. Ignore is not copied; explicit air clears nodes.
-- Validation comes before the first live-map mutation.
function Buffer:commit_core()
 local map=self.source
 local geom=self.geometry
 for _,axis in ipairs({'x','y','z'}) do
  assert(geom.node_min[axis]<=geom.node_max[axis],
   'invalid generated core')
 end
 for x=floor(geom.node_min.x/16),floor(geom.node_max.x/16) do
  for y=floor(geom.node_min.y/16),floor(geom.node_max.y/16) do
   for z=floor(geom.node_min.z/16),floor(geom.node_max.z/16) do
    local k=x..','..y..','..z
    assert(not (map.revisions[k] or map.last_active[k] or
     map.lbm_applied[k]),'cannot overwrite existing mapblock in commit')
   end
  end
 end
 -- No part of the core is committed if a neighboring voxel was
 -- changed concurrently or has node metadata/timers.
 self:validate_resident_halo()
 local nodes,discarded,resident=0,0,0
 for k,node in pairs(self.overlay) do
  local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  local pos={x=tonumber(x),y=tonumber(y),z=tonumber(z)}
  if self:core_contains(pos) then
   if node.name~='air' then map:set_node(pos,node) end
   nodes=nodes+1
  elseif self.resident_modified[k] then
   -- Native blitBackAll writes non-IGNORE nodes to emerged neighbors.
   -- These are staged cave changes, never raw terrain or unknown voxels.
   if not same(node,self.resident_original[k]) then
    map:set_node(pos,node)
    resident=resident+1
   end
  else
   discarded=discarded+1
  end
 end
 self.core_nodes,self.discarded_border=nodes,discarded
 self.committed_resident=resident
 return nodes,discarded,resident
end
return Buffer
