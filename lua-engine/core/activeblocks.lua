-- Resident active mapblock tracking based on Luanti 5.18 ServerEnvironment.
-- This deliberately does not synthesize unloaded mapblocks or terrain.
local ActiveBlocks={}
local floor=math.floor
local function finite(v)
 return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge
end
local function key(x,y,z)
 return x..','..y..','..z
end
local function position_key(p)
 return key(floor(p.x/16),floor(p.y/16),floor(p.z/16))
end
local function decode_key(k)
 local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
 if not x then return nil end
 return tonumber(x),tonumber(y),tonumber(z)
end
local function get_position(rt,name,player)
 local controller=rt.playerPhysicsControllers[name]
 local owner=controller or player
 if type(owner.get_pos)~='function' then return nil end
 local p=owner:get_pos()
 if type(p)~='table' or not finite(p.x) or
  not finite(p.y) or not finite(p.z) then return nil end
 if math.abs(p.x)>31000 or math.abs(p.y)>31000 or
  math.abs(p.z)>31000 then return nil end
 return p
end
local function settings(rt)
 local radius=rt.opts.active_block_range
 if radius==nil then radius=3 end -- upstream default
 assert(finite(radius) and radius==floor(radius) and radius>=0 and radius<=8,
  'active_block_range must be an integer in 0..8 for this Lua host')
 return radius
end
local function resident(rt)
 local out={}
 -- Map revisions are updated by all node writes, VoxelManip and save decode.
 -- Include blocks with no nodes but metadata, timers or LBM markers.
 for k in pairs(rt.map.revisions or {}) do out[k]=true end
 for k in pairs(rt.map.lbm_applied or {}) do out[k]=true end
 for k in pairs(rt.map.last_active or {}) do out[k]=true end
 for k in pairs(rt.map.metadata or {}) do
  local x,y,z=decode_key(k)
  if x then out[key(floor(x/16),floor(y/16),floor(z/16))]=true end
 end
 for k in pairs(rt.map.timers or {}) do
  local x,y,z=decode_key(k)
  if x then out[key(floor(x/16),floor(y/16),floor(z/16))]=true end
 end
 return out
end
local function desired(rt,radius)
 local wanted={}
 local any=false
 for name,player in pairs(rt.players) do
  local p=get_position(rt,name,player)
  if p then
   any=true
   -- Luanti converts world coordinates to integer nodes and then blocks.
   local bx=floor(floor(p.x+.5)/16)
   local by=floor(floor(p.y+.5)/16)
   local bz=floor(floor(p.z+.5)/16)
   for dx=-radius,radius do for dy=-radius,radius do
    for dz=-radius,radius do
     if dx*dx+dy*dy+dz*dz<=radius*radius then
      wanted[key(bx+dx,by+dy,bz+dz)]=true
     end
    end
   end end
  end
 end
 return wanted,any
end
function ActiveBlocks.clear(rt)
 if rt.activeMapBlocks then
  rt.map.last_active=rt.map.last_active or {}
  for k in pairs(rt.activeMapBlocks) do
   rt.map.last_active[k]=rt.clock
  end
 end
 rt.activeMapBlocks={}
end
-- Called before each engine step, and immediately after disconnect.
-- Updates only loaded/resident blocks. Unlike Luanti's ServerMap this
-- prototype does not yet emerge missing blocks or simulate AO ranges.
function ActiveBlocks.sync(rt)
 if rt.opts.auto_activate_blocks==false then return false end
 local radius=settings(rt)
 local wanted,any=desired(rt,radius)
 if not any and not rt.activeBlockTracking then return false end
 if any then rt.activeBlockTracking=true end
 -- Emerge saved blocks BEFORE calculating resident activation candidates.
 -- Read misses remain unloaded; no fabricated terrain is generated.
 if rt.mapBlockStore then
  local list={}
  for k in pairs(wanted) do list[#list+1]=k end
  table.sort(list)
  for _,k in ipairs(list) do
   if not rt.mapBlockStore:resident(k) then
    rt.mapBlockStore:emerge(k)
   end
  end
 end
 local loaded=resident(rt)
 local next_active={}
 for k in pairs(wanted) do
  if loaded[k] then next_active[k]=true end
 end
 rt.activeMapBlocks=rt.activeMapBlocks or {}
 rt.map.last_active=rt.map.last_active or {}
 -- Deactivate before activating, as upstream ServerEnvironment does.
 for k in pairs(rt.activeMapBlocks) do
  if not next_active[k] then
   rt.map.last_active[k]=rt.clock
   if rt.mapBlockStore then
    -- No RAM eviction until the block's atomic write is successful.
    -- It must no longer be marked active to satisfy unload's invariant.
    rt.activeMapBlocks[k]=nil
    rt.mapBlockStore:unload(k)
   end
  end
 end
 local added={}
 for k in pairs(next_active) do
  if not rt.activeMapBlocks[k] then added[#added+1]=k end
 end
 table.sort(added)
 for _,k in ipairs(added) do
  local x,y,z=decode_key(k)
  local last=rt.map.last_active[k]
  local elapsed=last and math.max(0,rt.clock-last) or 0
  -- Mark active before dispatch: callbacks can inspect active status.
  rt.activeMapBlocks[k]=true
  rt:activateMapBlock({x=x*16,y=y*16,z=z*16},elapsed)
  -- Native activation first executes LBMs and then catches up node timers.
  if elapsed>0 and rt._tickNodeTimers then
   rt:_tickNodeTimers(elapsed,k)
  end
  rt.map.last_active[k]=rt.clock
 end
 rt.activeMapBlocks=next_active
 return true
end
function ActiveBlocks.is_active(rt,nodepos)
 assert(type(nodepos)=='table' and finite(nodepos.x) and
  finite(nodepos.y) and finite(nodepos.z),'invalid node position')
 return rt.activeMapBlocks and rt.activeMapBlocks[position_key(nodepos)]==true or false
end
return ActiveBlocks
