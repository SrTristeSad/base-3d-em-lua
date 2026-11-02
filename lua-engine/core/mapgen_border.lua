-- Luanti 5.18 MMVManip vertical overlap transfer, scoped Lua implementation.
-- Upstream: src/mapgen/mapgen_v7.cpp::generateTerrain (one-up/down),
-- src/servermap.cpp::finishBlockMake and src/voxel.cpp::copyTo.
-- SPDX-License-Identifier: LGPL-2.1-or-later
--
-- This is NOT a full MMVManip blitBackAll. Unlike a complete mapblock,
-- a carried-over voxel must NOT make emerge_area think a block is loaded.
local Border={}
Border.__index=Border
local floor=math.floor
local function parsekey(s)
 local x,y,z=s:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
 assert(x and y and z,'invalid border mapblock key')
 x,y,z=tonumber(x),tonumber(y),tonumber(z)
 assert(math.abs(x)<=1938 and math.abs(y)<=1938 and
  math.abs(z)<=1938 and s==x..','..y..','..z,
  'invalid border mapblock coordinates')
 return x,y,z
end
local function nodekey(p) return p.x..','..p.y..','..p.z end
local function decodekey(s)
 local x,y,z=s:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
 assert(x and y and z,'invalid border voxel key')
 return {x=tonumber(x),y=tonumber(y),z=tonumber(z)}
end
local function belongs(p,bx,by,bz)
 return floor(p.x/16)==bx and floor(p.y/16)==by and floor(p.z/16)==bz
end
local function escape_name(s)
 return (s:gsub('([^%w_%-.~])',function(c)
  return ('%%%02X'):format(c:byte())
 end))
end
local function unescape_name(s)
 assert(not s:find('[^%w_%-.~%%]'),'invalid encoded border nodename')
 assert(not s:find('%%[^%x]') and not s:find('%%$') and
  not s:find('%%[%x][^%x]'),
  'invalid percent encoding')
 return (s:gsub('%%(%x%x)',function(h) return string.char(tonumber(h,16)) end))
end
local function validnode(node)
 assert(type(node)=='table' and type(node.name)=='string' and
  #node.name>=1 and #node.name<=256 and node.name~='ignore' and
  not node.name:find('[%c]'),
  'invalid partial border node')
 return {name=node.name,param1=node.param1 or 0,
  param2=node.param2 or 0}
end
function Border.new(runtime)
 assert(runtime and runtime.map,'world runtime required')
 return setmetatable({runtime=runtime,pending={},loaded={},dirty={},
  seeded=0,published=0},Border)
end
function Border:path(block)
 parsekey(block)
 local store=self.runtime.mapBlockStore
 assert(store,'disk border path requires MapBlockStore')
 local x,y,z=parsekey(block)
 return store.prefix..'/vertical-borders/'..
  x..'_'..y..'_'..z..'.border'
end
function Border:loadBlock(block)
 if self.loaded[block] then return end
 local bx,by,bz=parsekey(block)
 local store=self.runtime.mapBlockStore
 local content
 if store then
  local err
  content,err=store.fs.read(self:path(block))
  assert(content==nil or type(content)=='string',
   'invalid border read type')
  if content==nil then
   assert(err==nil or err=='not found',
    'partial border read failed: '..tostring(err))
  end
 end
 local parsed={}
 if content~=nil then
  assert(#content<=300000,'partial border file exceeds size limit')
  local lines={}
  for line in (content..'\n'):gmatch('(.-)\n') do
   if line~='' then lines[#lines+1]=line end
  end
  assert(lines[1]=='LUAENGINE BORDER 1' and
   lines[#lines]=='END','invalid border file header/trailer')
  assert(#lines<=4098,'too many border voxels in one mapblock')
  for i=2,#lines-1 do
   local x,y,z,name,p1,p2=lines[i]:match(
    '^V (%-?%d+) (%-?%d+) (%-?%d+) (%S+) (%d+) (%d+)$')
   assert(x and name,'invalid border voxel line')
   local p={x=tonumber(x),y=tonumber(y),z=tonumber(z)}
   assert(math.abs(p.x)<=31000 and math.abs(p.y)<=31000 and
    math.abs(p.z)<=31000 and belongs(p,bx,by,bz),
    'border voxel outside mapblock')
   local nk=nodekey(p)
   assert(not parsed[nk],'duplicate border voxel')
   local n=validnode({name=unescape_name(name),param1=tonumber(p1),
    param2=tonumber(p2)})
   assert(n.param1<=255 and n.param2<=255,
    'invalid border node parameters')
   parsed[nk]=n
  end
 end
 self.pending[block]=parsed
 self.loaded[block]=true
end
function Border:loadCore(geom)
 local a,b=geom.block_min,geom.block_max
 for x=a.x,b.x do for y=a.y,b.y do for z=a.z,b.z do
  self:loadBlock(x..','..y..','..z)
 end end end
end
-- The native buffer's CONTENT_IGNORE check preserves a prior
-- overgenerated voxel. Seed staged core before terrain generation.
function Border:seed(buffer,geom)
 self:loadCore(geom)
 local seeded=0
 local a,b=geom.block_min,geom.block_max
 for x=a.x,b.x do for y=a.y,b.y do for z=a.z,b.z do
  local block=x..','..y..','..z
  for nk,node in pairs(self.pending[block]) do
   local p=decodekey(nk)
   if buffer:core_contains(p) and buffer:terrain_writable(p) then
    assert(buffer:set_node(p,node),'border seed rejected')
    seeded=seeded+1
   end
  end
 end end end
 self.seeded=self.seeded+seeded
 return seeded
end
-- InitialEmerge loads the COMPLETE MMVManip volume. Import only
-- already-known sidecar nodes outside the generated core, including X/Z
-- margins; CONTENT_IGNORE remains unknown and cannot be carved.
function Border:seedExpanded(buffer,geom)
 local from,to=geom.full_node_min,geom.full_node_max
 local count=0
 for x=floor(from.x/16),floor(to.x/16) do
  for y=floor(from.y/16),floor(to.y/16) do
   for z=floor(from.z/16),floor(to.z/16) do
    local block=x..','..y..','..z
    self:loadBlock(block)
    for nk,node in pairs(self.pending[block]) do
     local p=decodekey(nk)
     if buffer:contains(p) and not buffer:core_contains(p) and
       buffer:terrain_writable(p) then
      assert(buffer:set_node(p,node),'MMVManip halo seed rejected')
      count=count+1
     end
    end
   end
  end
 end
 self.seeded=self.seeded+count
 return count
end
-- Only changes to an already-known provisional halo voxel are copied
-- back. Do not synthesize stone in CONTENT_IGNORE or modify a completed
-- neighbor; both would diverge from MMVManip::copyTo/initialEmerge.
function Border:publishModifiedHalo(buffer)
 local count=0
 for nk in pairs(buffer.modified) do
  local p=decodekey(nk)
  if not buffer:core_contains(p) then
   local block=self.runtime.map:blockkey(p)
   self:loadBlock(block)
   local old=self.pending[block][nk]
   local changed=buffer.overlay[nk]
   local map=self.runtime.map
   if old and changed and not (map.revisions[block] or
    map.last_active[block] or map.lbm_applied[block]) and
    (old.name~=changed.name or old.param1~=changed.param1 or
     old.param2~=changed.param2) then
    self.pending[block][nk]=validnode(changed)
    self.dirty[block]=true
    count=count+1
   end
  end
 end
 return count
end
-- Scoped MMVManip::blitBackAll equivalent for the HALO only.
-- Native src/map.cpp selects mapblocks with any known node (including
-- air) and skips blocks marked generated unless overwrite_generated=true.
-- We preserve generated/user-edited blocks and transfer known halo voxels
-- into partial sidecars instead of pretending the destination is emerged.
-- In contrast to the previous publishModifiedHalo, this also transfers
-- NEW known voxels, not just changes to previously imported sidecars.
function Border:blitBackHalo(buffer)
 assert(buffer and buffer.is_gen_buffer and
  type(buffer.getCoveredBlocks)=='function',
  'blitBackHalo requires a generated MMVManip workspace')
 local covered=buffer:getCoveredBlocks()
 local changed,modified_blocks=0,{}
 local map=self.runtime.map
 local function copyback(p)
  if not buffer:contains(p) or buffer:core_contains(p) then
   return
  end
  local block=map:blockkey(p)
  if not covered[block] then return end
  -- The native default !overwrite_generated condition. In the sparse
  -- Lua map, revisions and generated activation markers also conservatively
  -- protect player edits that are not explicitly marked generated.
  if map.revisions[block] or map.last_active[block] or
   map.lbm_applied[block] then return end
  local node=buffer:get_node(p)
  if node.name=='ignore' then return end
  self:loadBlock(block)
  local nk=nodekey(p)
  local prev=self.pending[block][nk]
  local n=validnode(node)
  if prev and prev.name==n.name and prev.param1==n.param1 and
   prev.param2==n.param2 then return end
  self.pending[block][nk]=n
  self.dirty[block]=true
  modified_blocks[block]=true
  changed=changed+1
 end
 -- Known-air columns have compressed representation. Only the one-down
 -- and one-up generated halo planes need individual entries in sidecars.
 for key,col in pairs(buffer.air_columns) do
  local x,z=key:match('^(%-?%d+),(%-?%d+)$')
  x,z=tonumber(x),tonumber(z)
  local a,b=buffer.geometry.node_min,buffer.geometry.node_max
  local function visit(lo,hi)
   for y=lo,hi do copyback({x=x,y=y,z=z}) end
  end
  if x<a.x or x>b.x or z<a.z or z>b.z then
   -- Future stages may have known-air columns in an X/Z border.
   visit(col.ymin,col.ymax)
  else
   -- Current V7 has 80+2 known air cells per column. Only the
   -- overgenerated Y planes can belong to outside-core blocks,
   -- avoiding an O(chunk volume) second scan during blit.
   visit(col.ymin,math.min(col.ymax,a.y-1))
   visit(math.max(col.ymin,b.y+1),col.ymax)
  end
 end
 -- Other mapgen algorithms (e.g. CavesRandomWalk) can create or modify
 -- voxels on any X/Y/Z face of the full MMVManip area.
 for key in pairs(buffer.overlay) do
  local p=decodekey(key)
  if not buffer:core_contains(p) then copyback(p) end
 end
 local nblocks=0
 for _ in pairs(modified_blocks) do nblocks=nblocks+1 end
 return changed,nblocks
end
local function add(self,p,node)
 local block=self.runtime.map:blockkey(p)
 self:loadBlock(block)
 if self.pending[block][nodekey(p)] then return false end
 -- Never hold provisional values for a complete/resident mapblock.
 local map=self.runtime.map
 if map.revisions[block] or map.last_active[block] or
  map.lbm_applied[block] then return false end
 self.pending[block][nodekey(p)]=validnode(node)
 self.dirty[block]=true
 self.published=self.published+1
 return true
end
-- Called AFTER commit of the interior. Only the one-above and one-below
-- planes are valid input for the current partial V7 terrain stage.
function Border:publish(buffer,geom)
 local count=0
 for z=geom.node_min.z,geom.node_max.z do
  for x=geom.node_min.x,geom.node_max.x do
   for _,y in ipairs({geom.node_min.y-1,geom.node_max.y+1}) do
    local p={x=x,y=y,z=z}
    local node=buffer:get_node(p)
    if node.name~='ignore' and add(self,p,node) then
     count=count+1
    end
   end
  end
 end
 return count
end
-- Once a formerly-partial block has been generated completely, remove
-- its provisional entries but retain other edges for future chunks.
function Border:retire(geom)
 self:loadCore(geom)
 local count=0
 for x=geom.block_min.x,geom.block_max.x do
  for y=geom.block_min.y,geom.block_max.y do
   for z=geom.block_min.z,geom.block_max.z do
    local k=x..','..y..','..z
    local t=self.pending[k]
    if next(t) then
     for _ in pairs(t) do count=count+1 end
     self.pending[k]={}
     self.dirty[k]=true
    end
   end
  end
 end
 return count
end
function Border:flush()
 local store=self.runtime.mapBlockStore
 if not store then return true,0 end
 local keys={}
 for key in pairs(self.dirty) do keys[#keys+1]=key end
 table.sort(keys)
 for _,block in ipairs(keys) do
  local entries={}
  for k in pairs(self.pending[block]) do entries[#entries+1]=k end
  table.sort(entries)
  local out={'LUAENGINE BORDER 1'}
  for _,nk in ipairs(entries) do
   local p=decodekey(nk)
   local n=validnode(self.pending[block][nk])
   out[#out+1]=('V %d %d %d %s %d %d'):format(
    p.x,p.y,p.z,escape_name(n.name),n.param1,n.param2)
  end
  out[#out+1]='END'
  local ok,err=store.fs.write_atomic(self:path(block),
   table.concat(out,'\n')..'\n')
  assert(ok,'partial border write failed: '..tostring(err))
  self.dirty[block]=nil
 end
 return true,#keys
end
function Border:countPending()
 local sum=0
 for _,table_nodes in pairs(self.pending) do
  for _ in pairs(table_nodes) do sum=sum+1 end
 end
 return sum
end
return Border
