-- Luanti LoadingBlockModifier execution on explicit mapblock activation.
-- See Luanti 5.18 doc/lua_api.md: LBMs are NOT node timers or mapgen hooks.
-- A host must activate resident mapblocks when they become active.
local LBM={}
local floor=math.floor

local function finite(n)
 return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge
end

local function valid_pos(p)
 assert(type(p)=='table' and finite(p.x) and finite(p.y) and
  finite(p.z) and p.x==floor(p.x) and p.y==floor(p.y) and
  p.z==floor(p.z) and math.abs(p.x)<=31000 and
  math.abs(p.y)<=31000 and math.abs(p.z)<=31000,
  'LBM requires an integer node position within map limits')
end

local function blockkey(p)
 return floor(p.x/16)..','..floor(p.y/16)..','..floor(p.z/16)
end

local function matches(api,def,node)
 for _,name in ipairs(def.nodenames) do
  local group=name:match('^group:(.+)$')
  if group then
   if api.get_node_group(node.name,group)>0 then return true end
  else
   local seen={}
   while api.registered_aliases[name] and not seen[name] do
    seen[name]=true
    name=api.registered_aliases[name]
   end
   if name==node.name then return true end
  end
 end
 return false
end

function LBM.register(rt,def)
 assert(type(def)=='table' and type(def.name)=='string' and
  def.name~='', 'LBM requires a persistent name')
 -- Luanti accepts both a single nodename string and a name list.
 -- The upstream VoxeLibre vl_legacy mod uses the string form directly.
 local names=type(def.nodenames)=='string' and
  {def.nodenames} or def.nodenames
 assert(type(names)=='table' and #names>0,
  'LBM requires one or more nodenames')
 local copied={}
 for k,v in pairs(def) do copied[k]=v end
 copied.nodenames={}
 for _,name in ipairs(names) do
  assert(type(name)=='string' and name~='','invalid LBM nodename')
  copied.nodenames[#copied.nodenames+1]=name
 end
 assert((type(def.action)=='function' and def.bulk_action==nil)
  or (type(def.bulk_action)=='function' and def.action==nil),
  'LBM requires exactly one of action or bulk_action')
 for _,existing in ipairs(rt.registry.lbms) do
  assert(existing.name~=def.name,'duplicate LBM name: '..def.name)
 end
 rt.registry.lbms[#rt.registry.lbms+1]=copied
end

-- A newly generated block is newer than all LBMs already registered.
-- Non-repeating LBMs must not be invoked on its freshly generated nodes.
function LBM.mark_generated(rt,minp,maxp)
 valid_pos(minp);valid_pos(maxp)
 local map=rt.map
 map.lbm_applied=map.lbm_applied or {}
 local ax,ay,az=floor(math.min(minp.x,maxp.x)/16),
  floor(math.min(minp.y,maxp.y)/16),
  floor(math.min(minp.z,maxp.z)/16)
 local bx,by,bz=floor(math.max(minp.x,maxp.x)/16),
  floor(math.max(minp.y,maxp.y)/16),
  floor(math.max(minp.z,maxp.z)/16)
 for x=ax,bx do for y=ay,by do for z=az,bz do
  local key=x..','..y..','..z
  local done=map.lbm_applied[key] or {}
  for _,def in ipairs(rt.registry.lbms) do
   if not def.run_at_every_load then done[def.name]=true end
  end
  if next(done) then map.lbm_applied[key]=done end
  map.last_active=map.last_active or {}
  map.last_active[key]=rt.clock
 end end end
end

-- nodepos is any *node* coordinate inside the activated 16^3 block.
-- A call represents a NEW activation, not a repeated tick. In particular,
-- run_at_every_load LBMs run once per activation, not every frame.
-- dtime_s must be supplied by the host from its block last-active clock;
-- zero is used only when that clock is unavailable.
function LBM.activate(rt,nodepos,dtime_s)
 valid_pos(nodepos)
 dtime_s=dtime_s or 0
 assert(finite(dtime_s) and dtime_s>=0,
  'LBM dtime_s must be nonnegative and finite')
 local map=rt.map
 map.lbm_applied=map.lbm_applied or {}
 local key=blockkey(nodepos)
 local done=map.lbm_applied[key] or {}
 local bx,by,bz=floor(nodepos.x/16),floor(nodepos.y/16),
  floor(nodepos.z/16)
 local snapshot={}
 for k in pairs(map.nodes) do
  local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  x,y,z=tonumber(x),tonumber(y),tonumber(z)
  if x and floor(x/16)==bx and floor(y/16)==by and
   floor(z/16)==bz then snapshot[#snapshot+1]={x=x,y=y,z=z} end
 end
 table.sort(snapshot,function(a,b)
  if a.z~=b.z then return a.z<b.z end
  if a.y~=b.y then return a.y<b.y end
  return a.x<b.x
 end)
 local count=0
 for _,def in ipairs(rt.registry.lbms) do
  if def.run_at_every_load or not done[def.name] then
   local positions={}
   for _,pos in ipairs(snapshot) do
    local node=map:get_node(pos)
    if matches(rt.api,def,node) then positions[#positions+1]=pos end
   end
   if def.bulk_action then
    if #positions>0 then
     def.bulk_action(positions,dtime_s)
     count=count+1
    end
   else
    for _,pos in ipairs(positions) do
     local node=map:get_node(pos)
     -- Prior LBMs can replace or remove nodes. Never pass a stale node.
     if matches(rt.api,def,node) then
      def.action(pos,node,dtime_s)
      count=count+1
     end
    end
   end
   if not def.run_at_every_load then done[def.name]=true end
  end
 end
 if next(done) then map.lbm_applied[key]=done end
 return count
end

return LBM
