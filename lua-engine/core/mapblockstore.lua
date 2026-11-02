-- Host-backed, opt-in 16^3 mapblock streaming. Existing complete-world
-- LUAENGINE 1 saves remain independent of this segmented storage mode.
-- Only drop RAM state after write_atomic confirms a durable block image.
local Map=require('core.map')
local Storage=require('core.storage')
local Store={}
Store.__index=Store
local floor=math.floor

local function decode(k)
 assert(type(k)=='string','mapblock key must be a string')
 local xs,ys,zs=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
 assert(xs and ys and zs,'invalid mapblock key')
 local x,y,z=tonumber(xs),tonumber(ys),tonumber(zs)
 assert(x and y and z and math.abs(x)<=1938 and
  math.abs(y)<=1938 and math.abs(z)<=1938,
  'mapblock coordinate outside world')
 assert(k==x..','..y..','..z,'noncanonical mapblock key')
 return x,y,z
end
local function block_of(k)
 local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
 assert(x and y and z,'invalid node coordinate')
 return floor(tonumber(x)/16)..','..
  floor(tonumber(y)/16)..','..floor(tonumber(z)/16)
end
local function keys(t)
 local out={}
 for k in pairs(t) do out[#out+1]=k end
 table.sort(out)
 return out
end
local function validate_block(image,k)
 local function same(keys_table,from_node)
  for a in pairs(keys_table) do
   if from_node then
    assert(block_of(a)==k,'foreign node in mapblock image')
   else
    assert(a==k,'foreign mapblock marker in image')
   end
  end
 end
 same(image.nodes,true)
 same(image.metadata,true)
 same(image.timers,true)
 same(image.lbm_applied,false)
 same(image.last_active,false)
 assert(next(image.generatedChunks)==nil,
  'per-mapblock data contains global generation markers')
 assert(image.last_active[k]~=nil,
  'per-mapblock image missing last-active timestamp')
end
local function unpack_key(k)
 local x,y,z=decode(k)
 return {x=x*16,y=y*16,z=z*16}
end
local function valid_fs(fs)
 assert(type(fs)=='table' and type(fs.read)=='function' and
  type(fs.write_atomic)=='function',
  'mapblock streaming requires fs.read and fs.write_atomic')
end
local function read(fs,path)
 local data,err=fs.read(path)
 if data==nil then
  if err and err~='not found' then error('mapblock read failed: '..tostring(err),0) end
  return nil
 end
 assert(type(data)=='string','mapblock read returned non-string data')
 return data
end
local function write(fs,path,data)
 local ok,err=fs.write_atomic(path,data)
 assert(ok,'mapblock write failed: '..tostring(err))
end
function Store.new(runtime,fs,prefix)
 assert(runtime and runtime.map and runtime.api,'runtime required')
 valid_fs(fs)
 assert(type(prefix)=='string' and
  prefix:match('^[%w_%.%-/]+$') and
  prefix:sub(1,1)~='/' and not prefix:find('%.%.',1),
  'safe relative storage prefix required')
 assert(not runtime.mapBlockStore,'mapblock store already attached')
 local self=setmetatable({runtime=runtime,fs=fs,prefix=prefix,
  misses={},loads=0,unloads=0},Store)
 local meta=read(fs,prefix..'/world.map')
 if meta then
  local header=Storage.decode(meta)
  assert(next(header.nodes)==nil and next(header.metadata)==nil and
   next(header.timers)==nil and next(header.lbm_applied)==nil and
   next(header.last_active)==nil,'invalid streaming world header')
  assert(runtime.clock<=header.game_time,
   'cannot attach an older segmented world to a newer runtime')
  for key,seed in pairs(header.generatedChunks) do
   local old=runtime.map.generatedChunks[key]
   assert(old==nil or old==seed,'conflicting world generation marker')
   runtime.map.generatedChunks[key]=seed
  end
  runtime.clock=header.game_time
  runtime.map.game_time=header.game_time
 end
 runtime.mapBlockStore=self
 runtime.map.streaming=true
 return self
end
function Store:path(k)
 local x,y,z=decode(k)
 return self.prefix..'/blocks/'..x..'_'..y..'_'..z..'.map'
end
function Store:saveGlobal()
 local rt=self.runtime
 local map=Map.new()
 map.game_time=rt.clock
 map.generatedChunks=rt.map.generatedChunks
 write(self.fs,self.prefix..'/world.map',Storage.encode(map))
 return true
end
function Store:resident(k)
 decode(k)
 local map=self.runtime.map
 if map.revisions[k] or map.lbm_applied[k] or
  map.last_active[k] then return true end
 for key in pairs(map.metadata) do
  if block_of(key)==k then return true end
 end
 for key in pairs(map.timers) do
  if block_of(key)==k then return true end
 end
 return false
end
function Store:snapshot(k)
 decode(k)
 local rt=self.runtime
 local source=rt.map
 local map=Map.new(rt.registry.items)
 map.game_time=rt.clock
 map.last_active[k]=source.last_active[k] or rt.clock
 if source.lbm_applied[k] then
  map.lbm_applied[k]=source.lbm_applied[k]
 end
 for key,value in pairs(source.nodes) do
  if block_of(key)==k then map.nodes[key]=value;map.count=map.count+1 end
 end
 for key,value in pairs(source.metadata) do
  if block_of(key)==k then map.metadata[key]=value end
 end
 for key,value in pairs(source.timers) do
  if block_of(key)==k then map.timers[key]=value end
 end
 return map
end
-- A successful fs.write_atomic must mean the entire file is safely replaced.
-- Failure returns before any in-memory node/metadata/timer is removed.
function Store:unload(k)
 decode(k)
 local rt=self.runtime
 assert(not (rt.activeMapBlocks and rt.activeMapBlocks[k]),
  'cannot unload an active mapblock')
 if not self:resident(k) then return false end
 local map=rt.map
 -- Global world time and chunk markers must be available on next boot
 -- before the block is decoded and its last-active stamp is validated.
 self:saveGlobal()
 write(self.fs,self:path(k),Storage.encode(self:snapshot(k)))
 -- Remove only this block from sparse state; Map:set_node maintains
 -- collision broadphase indexes, geometry revision and map.count.
 for key in pairs(map.nodes) do
  if block_of(key)==k then
   local x,y,z=key:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
   map:remove_node({x=tonumber(x),y=tonumber(y),z=tonumber(z)})
  end
 end
 for key in pairs(map.metadata) do
  if block_of(key)==k then map.metadata[key]=nil end
 end
 for key in pairs(map.timers) do
  if block_of(key)==k then map.timers[key]=nil end
 end
 map.revisions[k]=nil
 map.modified[k]=nil
 map.lightbanks[k]=nil
 map.lbm_applied[k]=nil
 map.last_active[k]=nil
 self.misses[k]=nil
 self.unloads=self.unloads+1
 return true
end
function Store:emerge(k)
 decode(k)
 if self:resident(k) then return false end
 if self.misses[k] then return false end
 local data=read(self.fs,self:path(k))
 if not data then self.misses[k]=true;return false end
 local image=Storage.decode(data)
 validate_block(image,k)
 local rt=self.runtime
 assert(image.game_time<=rt.clock,
  'mapblock timestamp newer than loaded world clock')
 local map=rt.map
 -- The complete image is decoded and validated before modifying live map.
 for key,node in pairs(image.nodes) do
  local x,y,z=key:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  map:set_node({x=tonumber(x),y=tonumber(y),z=tonumber(z)},node)
 end
 for key,entry in pairs(image.metadata) do
  local x,y,z=key:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  local pos={x=tonumber(x),y=tonumber(y),z=tonumber(z)}
  local meta=map:get_meta(pos)
  local from={fields=entry.fields}
  if entry.inventory then from.inventory=entry.inventory:to_table() end
  meta:from_table(from)
 end
 for key,timer in pairs(image.timers) do
  map:get_timer(timer.pos):set(timer.timeout,timer.elapsed)
 end
 map.lbm_applied[k]=image.lbm_applied[k]
 map.last_active[k]=image.last_active[k]
 self.loads=self.loads+1
 self.misses[k]=nil
 return true
end
-- The caller may generate a block after a read miss; remove that cache entry.
function Store:invalidate(k)
 decode(k)
 self.misses[k]=nil
end
-- Persist every resident mapblock and the global clock without eviction.
-- This replaces full-world Storage.save for a segmented streaming session.
function Store:flush()
 self:saveGlobal()
 local found={}
 local map=self.runtime.map
 for key in pairs(map.revisions) do found[key]=true end
 for key in pairs(map.last_active) do found[key]=true end
 for key in pairs(map.lbm_applied) do found[key]=true end
 for key in pairs(map.metadata) do found[block_of(key)]=true end
 for key in pairs(map.timers) do found[block_of(key)]=true end
 for _,key in ipairs(keys(found)) do
  write(self.fs,self:path(key),Storage.encode(self:snapshot(key)))
 end
 return true,#keys(found)
end
return Store
