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
  overlay={},flags={},writes=0,discarded_border=0,
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
function Buffer:get_node(pos)
 assert(self:contains(pos),'generation voxel outside MMVManip area')
 local v=self.overlay[indexkey(pos)]
 if v then return copy(v) end
 if self:_resident(pos) then return self.source:get_node(pos) end
 return {name='ignore',param1=0,param2=0}
end
function Buffer:get_flags(pos)
 assert(self:contains(pos),'generation voxel outside MMVManip area')
 local key=indexkey(pos)
 local flags=self.flags[key] or 0
 if self.overlay[key] or self:_resident(pos) then return flags end
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
 -- Never change nodes in already-emerged mapblocks (including known air).
 if not self.overlay[k] and self:_resident(pos) then return false end
 self.overlay[k]=copy(node) -- even air is *known* here
 self.flags[k]=nil
 self.writes=self.writes+1
 return true
end
function Buffer:remove_node(pos)
 return self:set_node(pos,{name='air'})
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
 local nodes,discarded=0,0
 for k,node in pairs(self.overlay) do
  local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  local pos={x=tonumber(x),y=tonumber(y),z=tonumber(z)}
  if self:core_contains(pos) then
   if node.name~='air' then map:set_node(pos,node) end
   nodes=nodes+1
  else
   discarded=discarded+1
  end
 end
 self.core_nodes,self.discarded_border=nodes,discarded
 return nodes,discarded
end
return Buffer
