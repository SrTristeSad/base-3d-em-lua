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
  queries=0,candidates_examined=0,fallback_queries=0}
 rt.spatialEntities=index
 for _,obj in ipairs(rt.luaEntities or {}) do insert(index,obj) end
 return index
end
function Index.update(rt,obj)
 local index=Index.ensure(rt)
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
 if index and index.objects==rt.luaEntities then remove(index,obj) end
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
return Index
