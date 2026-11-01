-- Sparse spatial hash for live LuaEntity collision boxes.
-- Only broadphase candidates are indexed; narrowphase retains the
-- precise AABB overlap and original per-axis swept collision solver.
-- Cell size four nodes, integer coordinates; registration-order results.
local Index={}
local floor=math.floor
local CELL=4
local MAX_QUERY_CELLS=4096
local function key(x,y,z)
 return x..','..y..','..z
end
local function boxes(obj)
 local p,b=obj.pos,obj.properties.collisionbox
 return {p.x+b[1],p.y+b[2],p.z+b[3],
  p.x+b[4],p.y+b[5],p.z+b[6]}
end
local function eligible(obj)
 return not obj.removed and obj.properties.physical==true and
  obj.properties.collide_with_objects~=false
end
local function ranges(b)
 return floor(b[1]/CELL),floor(b[4]/CELL),
  floor(b[2]/CELL),floor(b[5]/CELL),
  floor(b[3]/CELL),floor(b[6]/CELL)
end
local function cells(b)
 local x1,x2,y1,y2,z1,z2=ranges(b)
 local out={}
 for x=x1,x2 do for y=y1,y2 do for z=z1,z2 do
  out[#out+1]=key(x,y,z)
 end end end
 return out
end
-- A second hash tracks the CENTER of every active registered entity,
-- including nonphysical entities, so core.get_objects_inside_radius
-- keeps its original center-distance semantics.
local function centerkey(obj)
 local p=obj.pos
 return key(floor(p.x/CELL),floor(p.y/CELL),floor(p.z/CELL))
end
local function insertcenter(index,obj)
 if obj.removed then return end
 local k=centerkey(obj)
 index.centerMembers[obj]=k
 local bucket=index.centers[k]
 if not bucket then bucket={};index.centers[k]=bucket end
 bucket[#bucket+1]=obj
end
local function removecenter(index,obj)
 local k=index.centerMembers[obj]
 if not k then return end
 index.centerMembers[obj]=nil
 local bucket=index.centers[k]
 if bucket then
  for i=#bucket,1,-1 do
   if bucket[i]==obj then table.remove(bucket,i);break end
  end
  if #bucket==0 then index.centers[k]=nil end
 end
end
local function insert(index,obj)
 if not eligible(obj) then return end
 local occupied=cells(boxes(obj))
 index.members[obj]=occupied
 for _,k in ipairs(occupied) do
  local bucket=index.buckets[k]
  if not bucket then bucket={};index.buckets[k]=bucket end
  bucket[#bucket+1]=obj
 end
end
local function remove(index,obj)
 local occupied=index.members[obj]
 if not occupied then return end
 index.members[obj]=nil
 for _,k in ipairs(occupied) do
  local bucket=index.buckets[k]
  if bucket then
   for i=#bucket,1,-1 do
    if bucket[i]==obj then table.remove(bucket,i);break end
   end
   if #bucket==0 then index.buckets[k]=nil end
  end
 end
end
function Index.ensure(rt)
 local index=rt.spatialEntities
 if index and index.objects==rt.luaEntities then return index end
 index={objects=rt.luaEntities,buckets={},members={},
  centers={},centerMembers={},
  queries=0,candidates_examined=0,fallback_queries=0,
  proximity_queries=0,proximity_candidates_examined=0,
  proximity_fallback_queries=0}
 rt.spatialEntities=index
 for _,obj in ipairs(rt.luaEntities or {}) do
  insert(index,obj)
  insertcenter(index,obj)
 end
 return index
end
function Index.update(rt,obj)
 local index=Index.ensure(rt)
 local previous_center=index.centerMembers[obj]
 if obj.removed then
  if previous_center then removecenter(index,obj) end
 else
  local current_center=centerkey(obj)
  if previous_center~=current_center then
   if previous_center then removecenter(index,obj) end
   insertcenter(index,obj)
  end
 end
 local old=index.members[obj]
 if not eligible(obj) then
  if old then remove(index,obj) end
  return
 end
 local current=cells(boxes(obj))
 if old and #old==#current then
  local same=true
  for i=1,#current do
   if old[i]~=current[i] then same=false;break end
  end
  if same then return end -- common case: no cell boundary crossed
 end
 remove(index,obj)
 insert(index,obj)
end
function Index.remove(rt,obj)
 local index=rt.spatialEntities
 if index and index.objects==rt.luaEntities then
  remove(index,obj)
  removecenter(index,obj)
 end
end
-- Entries are sorted by monotonic ObjectRef ID to preserve old linear
-- collision traversal order. No approximation or reach-radius pruning.
function Index.query(rt,b,exclude)
 local index=Index.ensure(rt)
 index.queries=index.queries+1
 local x1,x2,y1,y2,z1,z2=ranges(b)
 local volume=(x2-x1+1)*(y2-y1+1)*(z2-z1+1)
 local out,seen={},{}
 if volume>MAX_QUERY_CELLS then
  -- Long-distance sweeps still work without allocating huge cell lists.
  index.fallback_queries=index.fallback_queries+1
  for _,obj in ipairs(rt.luaEntities or {}) do
   if obj~=exclude and eligible(obj) then
    out[#out+1]=obj
   end
  end
  index.candidates_examined=index.candidates_examined+#out
  return out
 end
 for x=x1,x2 do for y=y1,y2 do for z=z1,z2 do
  local bucket=index.buckets[key(x,y,z)]
  if bucket then
   for _,obj in ipairs(bucket) do
    if obj~=exclude and not seen[obj] and eligible(obj) then
     seen[obj]=true
     out[#out+1]=obj
    end
   end
  end
 end end end
 table.sort(out,function(a,b)return a.id<b.id end)
 index.candidates_examined=index.candidates_examined+#out
 return out
end
-- Exact center-distance lookup. A radius query does not ask for a physical
-- shape: nonphysical LuaEntities are indexed too. The fallback covers
-- unbounded radii without constructing a huge array of hash cells.
function Index.nearby(rt,pos,radius)
 local index=Index.ensure(rt)
 index.proximity_queries=index.proximity_queries+1
 local x1,x2,y1,y2,z1,z2=ranges({
  pos.x-radius,pos.y-radius,pos.z-radius,
  pos.x+radius,pos.y+radius,pos.z+radius})
 local volume=(x2-x1+1)*(y2-y1+1)*(z2-z1+1)
 local out={}
 local limit=radius*radius
 local function accept(obj)
  if obj.removed then return end
  local p=obj.pos
  local dx,dy,dz=p.x-pos.x,p.y-pos.y,p.z-pos.z
  if dx*dx+dy*dy+dz*dz<=limit then out[#out+1]=obj end
 end
 if volume>MAX_QUERY_CELLS then
  index.proximity_fallback_queries=index.proximity_fallback_queries+1
  for _,obj in ipairs(rt.luaEntities or {}) do
   index.proximity_candidates_examined=
    index.proximity_candidates_examined+1
   accept(obj)
  end
 else
  for x=x1,x2 do for y=y1,y2 do for z=z1,z2 do
   local bucket=index.centers[key(x,y,z)]
   if bucket then
    for _,obj in ipairs(bucket) do
     index.proximity_candidates_examined=
      index.proximity_candidates_examined+1
     accept(obj)
    end
   end
  end end end
 end
 table.sort(out,function(a,b)return a.id<b.id end)
 return out
end
return Index
