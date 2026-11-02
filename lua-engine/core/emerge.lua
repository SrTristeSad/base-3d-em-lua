-- Luanti 5.18 mapblock emergence API over the optional segmented store.
-- load_area is synchronous and never generates; emerge_area queues work.
local E={}
local floor=math.floor
local function finite(v)
 return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge
end
local function pos(p)
 assert(type(p)=='table' and finite(p.x) and finite(p.y) and finite(p.z)
  and p.x==floor(p.x) and p.y==floor(p.y) and p.z==floor(p.z)
  and math.abs(p.x)<=31000 and math.abs(p.y)<=31000
  and math.abs(p.z)<=31000,'invalid map emergence node coordinates')
 return p
end
local function key(bx,by,bz) return bx..','..by..','..bz end
local function decode(k)
 local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
 return tonumber(x),tonumber(y),tonumber(z)
end
local function blockpos(k)
 local x,y,z=decode(k)
 return {x=x,y=y,z=z}
end
local function nodepos(k)
 local x,y,z=decode(k)
 return {x=x*16,y=y*16,z=z*16}
end
local function bounds(a,b)
 a=pos(a);b=pos(b or a)
 local minx,maxx=floor(math.min(a.x,b.x)/16),floor(math.max(a.x,b.x)/16)
 local miny,maxy=floor(math.min(a.y,b.y)/16),floor(math.max(a.y,b.y)/16)
 local minz,maxz=floor(math.min(a.z,b.z)/16),floor(math.max(a.z,b.z)/16)
 local total=(maxx-minx+1)*(maxy-miny+1)*(maxz-minz+1)
 assert(total<=4096,'map emergence range exceeds Lua engine block budget')
 local out={}
 for x=minx,maxx do for y=miny,maxy do for z=minz,maxz do
  out[#out+1]=key(x,y,z)
 end end end
 return out
end
local function resident_keys(rt)
 local found={}
 local map=rt.map
 for k in pairs(map.revisions) do found[k]=true end
 for k in pairs(map.lbm_applied) do found[k]=true end
 for k in pairs(map.last_active) do found[k]=true end
 for k in pairs(map.metadata) do
  local x,y,z=decode(k)
  found[key(floor(x/16),floor(y/16),floor(z/16))]=true
 end
 for k in pairs(map.timers) do
  local x,y,z=decode(k)
  found[key(floor(x/16),floor(y/16),floor(z/16))]=true
 end
 return found
end
local function isloaded(rt,k)
 if rt.mapBlockStore then return rt.mapBlockStore:resident(k) end
 return resident_keys(rt)[k]==true
end
function E.loaded(rt)
 local keys={}
 for k in pairs(resident_keys(rt)) do keys[#keys+1]=k end
 table.sort(keys)
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=blockpos(k) end
 return out
end
-- The host may provide the original mapgen when it is actually available.
-- Returning true means exactly one mapblock was successfully generated.
function E.set_generator(rt,fn)
 assert(fn==nil or type(fn)=='function','mapblock generator must be a function')
 rt.mapBlockGenerator=fn
end
local function load(rt,k)
 if isloaded(rt,k) then return true,false end
 local store=rt.mapBlockStore
 if not store then return false,false end
 if store:emerge(k) then return true,true end
 return false,false
end
function E.load_area(rt,p1,p2)
 local blocks=bounds(p1,p2)
 local count=0
 for _,k in ipairs(blocks) do
  local ok,disk=load(rt,k)
  if ok then count=count+1 end
 end
 return count
end
function E.queue(rt,p1,p2,callback,param)
 assert(callback==nil or type(callback)=='function',
  'emerge_area callback must be a function')
 local blocks=bounds(p1,p2)
 rt.emergeQueue=rt.emergeQueue or {}
 rt.emergeQueue[#rt.emergeQueue+1]={
  blocks=blocks,next=1,callback=callback,param=param}
end
-- A snapshot budget prevents callback-enqueued emergence from spinning.
-- Every callback reports remaining calls in its *own* request.
function E.step(rt)
 local queue=rt.emergeQueue
 if not queue or #queue==0 then return 0 end
 local budget=rt.opts.emerge_blocks_per_step or 8
 assert(finite(budget) and budget==floor(budget)
  and budget>=1 and budget<=4096,'invalid emerge_blocks_per_step')
 local done=0
 while done<budget and #queue>0 do
  local req=queue[1]
  local k=req.blocks[req.next]
  local action=rt.api.EMERGE_CANCELLED
  if isloaded(rt,k) then
   action=rt.api.EMERGE_FROM_MEMORY
  else
   local ok,loaded=pcall(load,rt,k)
   if not ok then
    action=rt.api.EMERGE_ERRORED
   elseif loaded then
    action=rt.api.EMERGE_FROM_DISK
   elseif rt.mapBlockGenerator then
    local p=nodepos(k)
    local maxp={x=p.x+15,y=p.y+15,z=p.z+15}
    -- World-edge mapblocks may extend beyond the valid 31000-node limit.
    if math.abs(p.x)>31000 or math.abs(p.y)>31000 or
       math.abs(p.z)>31000 or maxp.x>31000 or
       maxp.y>31000 or maxp.z>31000 then
     action=rt.api.EMERGE_CANCELLED
    else
     local generated,result=pcall(rt.mapBlockGenerator,rt,p,maxp)
     if not generated then
      action=rt.api.EMERGE_ERRORED
     elseif result==true then
      -- Only an actual host generator can claim a generated mapblock.
      local finalized=pcall(function()
       rt:markGeneratedMapBlocks(p,maxp)
       rt:generate(p,maxp,rt.opts.seed or 0)
      end)
      if finalized then
       if rt.mapBlockStore then rt.mapBlockStore:invalidate(k) end
       action=rt.api.EMERGE_GENERATED
      else action=rt.api.EMERGE_ERRORED end
     end
    end
   end
  end
  req.next=req.next+1
  local remaining=#req.blocks-req.next+1
  if remaining==0 then table.remove(queue,1) end
  done=done+1
  if req.callback then
   req.callback(blockpos(k),action,remaining,req.param)
  end
 end
 return done
end
function E.install(rt,api)
 api.EMERGE_CANCELLED=0
 api.EMERGE_ERRORED=1
 api.EMERGE_FROM_MEMORY=2
 api.EMERGE_FROM_DISK=3
 api.EMERGE_GENERATED=4
 api.MAP_BLOCKSIZE=16
 function api.load_area(p1,p2) return E.load_area(rt,p1,p2) end
 function api.emerge_area(p1,p2,cb,param)
  return E.queue(rt,p1,p2,cb,param)
 end
 function api.get_loaded_blocks() return E.loaded(rt) end
 function api.get_active_blocks()
  local out={}
  for k in pairs(rt.activeMapBlocks or {}) do out[#out+1]=k end
  table.sort(out)
  for i,k in ipairs(out) do out[i]=blockpos(k) end
  return out
 end
 function api.compare_block_status(p,condition)
  if condition~='unknown' and condition~='emerging' and
   condition~='loaded' and condition~='active' then return nil end
  local p=pos(p)
  local k=key(floor(p.x/16),floor(p.y/16),floor(p.z/16))
  local active=rt.activeMapBlocks and rt.activeMapBlocks[k] or false
  local loaded=isloaded(rt,k)
  local emerging=false
  for _,req in ipairs(rt.emergeQueue or {}) do
   for n=req.next,#req.blocks do
    if req.blocks[n]==k then emerging=true;break end
   end
   if emerging then break end
  end
  if condition=='active' then return active==true end
  if condition=='loaded' then return loaded and not active end
  if condition=='emerging' then return emerging end
  return not loaded and not emerging
 end
end
return E
