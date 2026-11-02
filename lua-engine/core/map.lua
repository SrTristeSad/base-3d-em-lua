-- Luanti Lua Engine: sparse voxel map (16^3 mapblocks).
-- A implementation is intentionally independent of the old Beta 1.8 world.
local Inventory=require('core.inventory')
local MapNodeIndex=require('core.mapnodeindex')
local Map={}
Map.__index=Map
Map.BLOCKSIZE=16
-- Luanti 5.18 src/modifiedstate.h and src/mapblock.h.
Map.MOD_STATE_CLEAN=0
Map.MOD_STATE_WRITE_AT_UNLOAD=2
Map.MOD_STATE_WRITE_NEEDED=4
Map.BLOCK_TIMESTAMP_UNDEFINED=4294967295
Map.MOD_REASON_SET_IS_UNDERGROUND=2
Map.MOD_REASON_SET_LIGHTING_COMPLETE=4
Map.MOD_REASON_SET_GENERATED=8
Map.MOD_REASON_SET_NODE=16
Map.MOD_REASON_SET_TIMESTAMP=32
Map.MOD_REASON_REPORT_META_CHANGE=64
Map.MOD_REASON_EXPIRE_IS_AIR=65536
Map.MOD_REASON_VMANIP=131072
Map.MOD_REASON_UNKNOWN=262144
local reason_names={
 [0]='reallocate or initial',
 [1]='setIsUnderground',
 [2]='setLightingComplete',
 [3]='setGenerated',
 [4]='setNode',
 [5]='setTimestamp',
 [6]='reportMetadataChange',
 [7]='clearAllObjects',
 [8]='Timestamp expired (step)',
 [9]='addActiveObjectRaw',
 [10]='removeRemovedObjects: remove',
 [11]='removeRemovedObjects: deactivate',
 [12]='objects cleared due to overflow',
 [13]='deactivateFarObjects: static data moved in',
 [14]='deactivateFarObjects: static data moved out',
 [15]='deactivateFarObjects: static data changed',
 [16]='finishBlockMake: expireIsAir',
 [17]='MMVManip::blitBackAll',
 [18]='unknown'
}
local function reason_or(a,b)
 -- Both Lua 5.4 and LuaJIT support integer-exact arithmetic here;
 -- neither requires bit32, which is not built into all Lua 5.4 hosts.
 local sum=0
 local bit=1
 while a>0 or b>0 do
  local av,bv=a%2,b%2
  if av+bv>0 then sum=sum+bit end
  a=math.floor(a/2); b=math.floor(b/2); bit=bit*2
 end
 return sum
end
local function raise_modified_fast(map,block,state,reason)
 local old=map.modified_states[block] or 0
 if state>old then
  map.modified_states[block]=state
  map.modified_reasons[block]=reason
  -- MapBlock::raiseModified copies m_timestamp to m_disk_timestamp
  -- only when severity increases to at least WRITE_AT_UNLOAD.
  if state>=Map.MOD_STATE_WRITE_AT_UNLOAD then
   map.block_disk_timestamps[block]=map.block_timestamps[block]
  end
 elseif state==old then
  local current=map.modified_reasons[block] or 0
  if current~=reason then
   -- Power-of-two fast path for the per-voxel setNode hot loop.
   if reason>0 and reason%2==0 and
    (reason==16 or reason==131072 or reason==2 or reason==4) and
    math.floor(current/reason)%2==1 then
    -- already set
   else
    map.modified_reasons[block]=reason_or(current,reason)
   end
  end
 end
 if state>0 then map.modified[block]=true end
end
local floor=math.floor
local function coord(p)
 assert(type(p)=='table','position must be a table')
 for _,k in ipairs({'x','y','z'}) do
  assert(type(p[k])=='number' and p[k]==floor(p[k]) and
   p[k]==p[k] and math.abs(p[k])<=31000,
   'invalid integer node position: '..k)
 end
 return p.x,p.y,p.z
end
local function key(x,y,z) return x..','..y..','..z end
local function bk(x,y,z)
 return floor(x/16)..','..floor(y/16)..','..floor(z/16)
end
function Map.new(registry)
 return setmetatable({nodes={},metadata={},timers={},registry=registry,
  revisions={},modified={},modified_states={},modified_reasons={},
  generatedChunks={},lightbanks={},lbm_applied={},
  blank_blocks={},
  -- MapBlock::isAir is a lazy per-block CONTENT_AIR cache. Unknown
  -- MapBlocks have no cache entry, and transient IGNORE is not AIR.
  block_air_cache={},block_air_scans=0,
  -- Luanti 5.18 MapBlock::m_lighting_complete is u16, default 0xFFFF.
  -- Only deviations from the default need a sparse entry.
  lighting_complete={},
  -- Native u32 MapBlock timestamps, independent of fractional LBM
  -- last_active clock. Absent entries mean 0xffffffff (undefined).
  block_timestamps={},block_disk_timestamps={},
  -- Luanti 5.18 MapBlock::is_underground, false by default.
  underground={},
  game_time=0,last_active={},count=0,
  geometry_revision=0},Map)
end
function Map.key(p)
 local x,y,z=coord(p)
 return key(x,y,z)
end
function Map:blockkey(p)
 local x,y,z=coord(p)
 return bk(x,y,z)
end
local function blockcoords(block)
 assert(type(block)=='string','mapblock cache key must be a string')
 local xs,ys,zs=block:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
 assert(xs and ys and zs,'invalid mapblock cache key')
 local x,y,z=tonumber(xs),tonumber(ys),tonumber(zs)
 assert(x and y and z and math.abs(x)<=1938 and
  math.abs(y)<=1938 and math.abs(z)<=1938 and
  block==x..','..y..','..z,'invalid mapblock cache coordinates')
 return x,y,z
end
local function timestamp_value(t)
 assert(type(t)=='number' and t==floor(t) and
  t>=0 and t<=Map.BLOCK_TIMESTAMP_UNDEFINED,
  'MapBlock timestamp must be a u32')
 return t
end
-- A native timestamp setter operates on an existing MapBlock object,
-- not on unloaded terrain. Do not create a block just to change time.
local function block_resident(map,block,bx,by,bz)
 if map.blank_blocks[block] or map.revisions[block] or
  map.last_active[block] or map.lbm_applied[block] or
  map.lighting_complete[block] or map.underground[block] or
  map.block_timestamps[block] then return true end
 for _,entries in ipairs({map.nodes,map.metadata,map.timers}) do
  for k in pairs(entries) do
   local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
   if x and floor(tonumber(x)/16)==bx and
    floor(tonumber(y)/16)==by and floor(tonumber(z)/16)==bz then
    return true
   end
  end
 end
 return false
end
function Map:get_mapblock_timestamp(block)
 blockcoords(block)
 return self.block_timestamps[block] or Map.BLOCK_TIMESTAMP_UNDEFINED
end
-- Native getDiskTimestamp() is explicitly deprecated and should not
-- be interpreted as the last durable write time. It is captured on
-- a rise of the modification severity and restored on disk import.
function Map:get_mapblock_disk_timestamp(block)
 blockcoords(block)
 return self.block_disk_timestamps[block] or Map.BLOCK_TIMESTAMP_UNDEFINED
end
function Map:set_mapblock_timestamp_no_changed_flag(block,t)
 local bx,by,bz=blockcoords(block)
 t=timestamp_value(t)
 assert(block_resident(self,block,bx,by,bz),
  'timestamp requires a resident MapBlock')
 if t==Map.BLOCK_TIMESTAMP_UNDEFINED then
  self.block_timestamps[block]=nil
 else
  self.block_timestamps[block]=t
 end
 return true
end
function Map:set_mapblock_timestamp(block,t)
 self:set_mapblock_timestamp_no_changed_flag(block,t)
 -- Native MapBlock::setTimestamp raises WRITE_AT_UNLOAD even when
 -- assigned the same value. No-change import setter does not raise.
 self:raise_mapblock_modified(block,Map.MOD_STATE_WRITE_AT_UNLOAD,
  Map.MOD_REASON_SET_TIMESTAMP)
 return true
end
-- Luanti MapBlock::raiseModified severity/reason ordering. These
-- transient diagnostic tables do not change the LUAENGINE 1 save format.
function Map:get_mapblock_modified_state(block)
 blockcoords(block)
 return self.modified_states[block] or Map.MOD_STATE_CLEAN
end
function Map:get_mapblock_modified_reason(block)
 blockcoords(block)
 return self.modified_reasons[block] or 0
end
function Map:get_mapblock_modified_reason_string(block)
 local reason=self:get_mapblock_modified_reason(block)
 local names={}
 for i=0,18 do
  if math.floor(reason/2^i)%2==1 then
   names[#names+1]=reason_names[i]
  end
 end
 return table.concat(names,', ')
end
function Map:raise_mapblock_modified(block,state,reason)
 blockcoords(block)
 assert(state==Map.MOD_STATE_CLEAN or
  state==Map.MOD_STATE_WRITE_AT_UNLOAD or
  state==Map.MOD_STATE_WRITE_NEEDED,
  'invalid MapBlock modified state')
 assert(type(reason)=='number' and reason==floor(reason) and
  reason>=0 and reason<2^19,
  'invalid MapBlock modified reason')
 raise_modified_fast(self,block,state,reason)
 return self:get_mapblock_modified_state(block)
end
function Map:reset_mapblock_modified(block)
 blockcoords(block)
 self.modified_states[block]=nil
 self.modified_reasons[block]=nil
 self.modified[block]=nil
end
-- Luanti 5.18 MapBlock::getIsUnderground / setIsUnderground.
-- This is a persisted MapBlock flag, not a calculation of sunlight.
function Map:get_mapblock_is_underground(block)
 blockcoords(block)
 return self.underground[block]==true
end
-- Native setIsUnderground always raises WRITE_NEEDED, even if its
-- boolean value remains identical. Validate residency first so no
-- implicit MapBlock is created by changing a flag.
function Map:set_mapblock_is_underground(block,is_underground)
 local bx,by,bz=blockcoords(block)
 assert(type(is_underground)=='boolean',
  'is_underground requires a boolean')
 local resident=self.blank_blocks[block] or
  self.revisions[block] or self.last_active[block] or
  self.lbm_applied[block] or self.lighting_complete[block] or
  self.underground[block]
 if not resident then
  local function inblock(k)
   local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
   return x and floor(tonumber(x)/16)==bx and
    floor(tonumber(y)/16)==by and floor(tonumber(z)/16)==bz
  end
  for _,entries in ipairs({self.nodes,self.metadata,self.timers}) do
   for k in pairs(entries) do
    if inblock(k) then resident=true;break end
   end
   if resident then break end
  end
 end
 assert(resident,'is_underground requires a resident MapBlock')
 local changed=self:get_mapblock_is_underground(block)~=is_underground
 if is_underground then
  self.underground[block]=true
 else
  self.underground[block]=nil
 end
 self:raise_mapblock_modified(block,Map.MOD_STATE_WRITE_NEEDED,
  Map.MOD_REASON_SET_IS_UNDERGROUND)
 return changed
end
-- Native MapBlock::m_lighting_complete is a 16-bit flag word. Bits 0..5
-- represent LIGHTBANK_DAY neighbors (directions 0..5); bits 6..11
-- represent LIGHTBANK_NIGHT. Preserve the four reserved upper bits.
local function lightword(flags)
 assert(type(flags)=='number' and flags==floor(flags) and
  flags>=0 and flags<=65535,'lighting complete must be a u16')
 return flags
end
local function direction_bit(bank,direction)
 assert(bank=='day' or bank=='night' or bank==0 or bank==1,
  'light bank must be day/night or 0/1')
 assert(type(direction)=='number' and direction==floor(direction) and
  direction>=0 and direction<=5,'light direction must be 0..5')
 return 2^(direction+((bank=='night' or bank==1) and 6 or 0))
end
function Map:get_mapblock_lighting_complete(block)
 blockcoords(block)
 return self.lighting_complete[block] or 65535
end
function Map:is_mapblock_lighting_complete(block,bank,direction)
 local bit=direction_bit(bank,direction)
 return floor(self:get_mapblock_lighting_complete(block)/bit)%2==1
end
-- Setter mirrors setLightingComplete(u16): changing any bit raises
-- write-at-unload dirty state, without implying that light was computed.
-- The target must already be resident, as in MapBlock::setLightingComplete.
function Map:set_mapblock_lighting_complete(block,flags)
 local bx,by,bz=blockcoords(block)
 flags=lightword(flags)
 local resident=self.blank_blocks[block] or
  self.revisions[block] or self.last_active[block] or
  self.lbm_applied[block]
 if not resident then
  local function inblock(k)
   local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
   return x and floor(tonumber(x)/16)==bx and
    floor(tonumber(y)/16)==by and floor(tonumber(z)/16)==bz
  end
  for _,entries in ipairs({self.nodes,self.metadata,self.timers}) do
   for k in pairs(entries) do
    if inblock(k) then resident=true;break end
   end
   if resident then break end
  end
 end
 assert(resident,'lighting complete requires a resident MapBlock')
 local old=self:get_mapblock_lighting_complete(block)
 if old==flags then return false end
 if flags==65535 then
  self.lighting_complete[block]=nil
 else
  self.lighting_complete[block]=flags
 end
 self:raise_mapblock_modified(block,Map.MOD_STATE_WRITE_AT_UNLOAD,
  Map.MOD_REASON_SET_LIGHTING_COMPLETE)
 return true
end
function Map:set_mapblock_lighting_complete_direction(block,bank,direction,complete)
 assert(type(complete)=='boolean','lighting complete requires boolean')
 local bit=direction_bit(bank,direction)
 local current=self:get_mapblock_lighting_complete(block)
 local already=floor(current/bit)%2==1
 if complete==already then
  -- Even a no-op setter must not accept an absent MapBlock.
  blockcoords(block)
  -- Check residency by requiring an existing MapBlock via the
  -- full-word setter, which is idempotent for identical flags.
  return self:set_mapblock_lighting_complete(block,current)
 end
 return self:set_mapblock_lighting_complete(block,
  complete and current+bit or current-bit)
end
-- Luanti 5.18 MapBlock::expireIsAirCache. Called on node mutations,
-- on transitions from IGNORE to generated AIR, and after MMVManip blit.
-- No serialized copy of this derived state is needed.
function Map:expire_mapblock_air_cache(block)
 blockcoords(block)
 self.block_air_cache[block]=nil
end
-- Nil means no resident MapBlock. For an existing one, this is exactly
-- MapBlock::isAir: every one of its 4096 MapNodes must have CONTENT_AIR,
-- independent of param1/param2, metadata, timers and light.
function Map:is_mapblock_air(block)
 local bx,by,bz=blockcoords(block)
 local nodes=0
 local has_non_air=false
 local resident=not not (self.blank_blocks[block] or
  self.revisions[block] or self.last_active[block] or
  self.lbm_applied[block])
 local value=self.block_air_cache[block]
 if value~=nil then return value end
 for key,node in pairs(self.nodes) do
  local x,y,z=key:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  if x and floor(tonumber(x)/16)==bx and
   floor(tonumber(y)/16)==by and floor(tonumber(z)/16)==bz then
   resident=true
   nodes=nodes+1
   if node.name~='air' then has_non_air=true end
  end
 end
 if not resident then
  for _,collection in ipairs({self.metadata,self.timers}) do
   for key in pairs(collection) do
    local x,y,z=key:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
    if x and floor(tonumber(x)/16)==bx and
     floor(tonumber(y)/16)==by and floor(tonumber(z)/16)==bz then
     resident=true
     break
    end
   end
   if resident then break end
  end
 end
 if not resident then return nil end
 self.block_air_scans=self.block_air_scans+1
 -- Unwritten cells in generated/ordinary blocks are sparse AIR.
 -- Unwritten cells in blank MapBlocks are CONTENT_IGNORE.
 local air=not has_non_air and
  (not self.blank_blocks[block] or nodes==4096)
 self.block_air_cache[block]=air
 return air
end
-- MapBlocks created by ServerMap::createBlock start full of
-- CONTENT_IGNORE and are not generated (Luanti 5.18 mapblock.cpp:101).
-- Keep them distinct from generated empty blocks, which are known air.
function Map:create_blank_block(block)
 assert(type(block)=='string' and
  block:match('^%-?%d+,%-?%d+,%-?%d+$'),
  'invalid blank mapblock key')
 local x,y,z=block:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
 x,y,z=tonumber(x),tonumber(y),tonumber(z)
 assert(math.abs(x)<=1938 and math.abs(y)<=1938 and
  math.abs(z)<=1938 and block==x..','..y..','..z,
  'blank mapblock outside valid coordinates')
 if self.blank_blocks[block] then return false end
 if self.revisions[block] or self.last_active[block] or
  self.lbm_applied[block] then return false end
 local function has(key)
  local px,py,pz=key:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  return px and floor(tonumber(px)/16)==x and
   floor(tonumber(py)/16)==y and floor(tonumber(pz)/16)==z
 end
 for k in pairs(self.nodes) do if has(k) then return false end end
 for k in pairs(self.metadata) do if has(k) then return false end end
 for k in pairs(self.timers) do if has(k) then return false end end
 self.blank_blocks[block]=true
 self:expire_mapblock_air_cache(block)
 return true
end
function Map:finish_blank_block(block)
 if not self.blank_blocks[block] then return false end
 self.blank_blocks[block]=nil
 self:expire_mapblock_air_cache(block)
 -- During construction, an explicit AIR node can represent a single
 -- known cell inside an otherwise CONTENT_IGNORE blank block.
 -- After generation, AIR becomes the normal sparse default.
 for key,node in pairs(self.nodes) do
  -- Only AIR(0,0) is equivalent to an absent sparse cell.
  if node.name=='air' and (node.param1 or 0)==0 and
     (node.param2 or 0)==0 then
   local x,y,z=key:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
   if x and floor(tonumber(x)/16)..','..
      floor(tonumber(y)/16)..','..floor(tonumber(z)/16)==block then
    self.nodes[key]=nil
    self.count=self.count-1
   end
  end
 end
 return true
end
function Map:get_node(p)
 local k=Map.key(p)
 local n=self.nodes[k]
 if not n then
  return {name=self.blank_blocks[self:blockkey(p)] and
   'ignore' or 'air',param1=0,param2=0}
 end
 return {name=n.name,param1=n.param1,param2=n.param2}
end
function Map:set_node(p,node)
 local x,y,z=coord(p)
 assert(type(node)=='table' and type(node.name)=='string'
  and node.name~='','node.name is required')
 local k=key(x,y,z)
 local old=self.nodes[k]
 local name=node.name
 local p1=node.param1 or 0
 local p2=node.param2 or 0
 assert(type(p1)=='number' and p1==floor(p1)
  and p1>=0 and p1<=255,'param1 outside 0..255')
 assert(type(p2)=='number' and p2==floor(p2)
  and p2>=0 and p2<=255,'param2 outside 0..255')
 local block=bk(x,y,z)
 local blank=self.blank_blocks[block]==true
 local oldname=old and old.name or (blank and 'ignore' or 'air')
 if name=='air' and not blank and p1==0 and p2==0 then
  if old then self.count=self.count-1 end
  self.nodes[k]=nil
 else
  -- A blank mapblock stores explicitly written AIR until it is generated.
  if not old then self.count=self.count+1 end
  self.nodes[k]={name=name,param1=p1,param2=p2}
 end
 -- Map:set_node is a hot worldgen loop; 'block' is already a
 -- canonical key, so invalidate directly rather than re-parse it.
 -- Even a byte-identical MapNode write expires the derived isAir cache.
 self.block_air_cache[block]=nil
 -- Sparse collision broadphase is maintained incrementally once built.
 -- Replacing map.nodes directly is handled by lazy index reconstruction.
 MapNodeIndex.changed(self,x,y,z,name~='air')
 if oldname~=name or (old and (old.param1~=p1 or old.param2~=p2)) or
    (not old and (p1~=0 or p2~=0)) then
  -- Collision nodeboxes (including connected neighbors) may depend on
  -- any changed cell. A single monotonic stamp invalidates cached shapes.
  self.geometry_revision=self.geometry_revision+1
  local block=bk(x,y,z)
  self.revisions[block]=(self.revisions[block] or 0)+1
  raise_modified_fast(self,block,Map.MOD_STATE_WRITE_NEEDED,
   Map.MOD_REASON_SET_NODE)
  -- Optional runtime observer keeps collision geometry live without
  -- forcing a complete shape cache reset after each mining/build edit.
  if self.on_geometry_changed then
   self.on_geometry_changed(self,x,y,z)
  end
 end
 return true
end
function Map:remove_node(p)
 return self:set_node(p,{name='air'})
end
function Map:iter_nodes(minp,maxp)
 local minx,miny,minz=coord(minp)
 local maxx,maxy,maxz=coord(maxp)
 assert(minx<=maxx and miny<=maxy and minz<=maxz,'invalid node range')
 local volume=(maxx-minx+1)*(maxy-miny+1)*(maxz-minz+1)
 assert(volume<=1048576,'area too large')
 local nodes={}
 for x=minx,maxx do for y=miny,maxy do for z=minz,maxz do
  local n=self:get_node({x=x,y=y,z=z})
  nodes[#nodes+1]={pos={x=x,y=y,z=z},node=n}
 end end end
 return nodes
end
local function metaref(entry,registry)
 local ref={}
 function ref:get_string(name) return tostring(entry.fields[name] or '') end
 function ref:set_string(name,v)
  assert(type(name)=='string' and
   (type(v)=='string' or type(v)=='number'),'invalid metadata')
  entry.fields[name]=tostring(v)
 end
 function ref:get_int(name) return tonumber(entry.fields[name]) and
  floor(tonumber(entry.fields[name])) or 0 end
 function ref:set_int(name,v)
  assert(type(v)=='number' and v==floor(v),'integer expected')
  entry.fields[name]=tostring(v)
 end
 function ref:get_float(name) return tonumber(entry.fields[name]) or 0 end
 function ref:set_float(name,v)
  assert(type(v)=='number','number expected')
  entry.fields[name]=tostring(v)
 end
 function ref:contains(name) return entry.fields[name]~=nil end
 function ref:get_inventory()
  if not entry.inventory then entry.inventory=Inventory.new(registry) end
  return entry.inventory
 end
 function ref:to_table()
  local fields={}
  for k,v in pairs(entry.fields) do fields[k]=v end
  return {fields=fields,inventory=entry.inventory and
   entry.inventory:to_table() or {}}
 end
 function ref:from_table(t)
  entry.fields={}
  if t and t.fields then
   for k,v in pairs(t.fields) do entry.fields[k]=tostring(v) end
  end
  if t and t.inventory then
   ref:get_inventory():from_table(t.inventory)
  else
   entry.inventory=nil
  end
  return true
 end
 return ref
end
function Map:get_meta(p)
 local k=Map.key(p)
 if not self.metadata[k] then self.metadata[k]={fields={}} end
 return metaref(self.metadata[k],self.registry)
end
function Map:get_timer(p)
 local k=Map.key(p)
 local all=self.timers
 local ref={}
 function ref:start(timeout)
  assert(type(timeout)=='number' and timeout>0,'timeout must be positive')
  all[k]={timeout=timeout,elapsed=0,pos={x=p.x,y=p.y,z=p.z}}
 end
 function ref:stop() all[k]=nil end
 function ref:is_started() return all[k]~=nil end
 function ref:get_timeout() return all[k] and all[k].timeout or 0 end
 function ref:get_elapsed() return all[k] and all[k].elapsed or 0 end
 function ref:set(timeout,elapsed)
  assert(type(timeout)=='number' and timeout>0,'bad timeout')
  all[k]={timeout=timeout,elapsed=elapsed or 0,
   pos={x=p.x,y=p.y,z=p.z}}
 end
 return ref
end
return Map
