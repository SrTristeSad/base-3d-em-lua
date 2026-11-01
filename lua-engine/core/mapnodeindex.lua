-- Phase 49: sparse index of STORED nodes grouped by 16^3 mapblock.
-- This is a conservative candidate query for collision geometry only.
-- No implicit air cells are stored and returned node positions are
-- ordered x, then y, then z to match the original dense voxel sweep.
local Index={}
local floor=math.floor
local SIZE=16
local function block(x,y,z)
 return floor(x/SIZE)..','..floor(y/SIZE)..','..floor(z/SIZE)
end
local function position(k)
 local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
 if not x then error('invalid stored node position: '..tostring(k)) end
 return {x=tonumber(x),y=tonumber(y),z=tonumber(z)}
end
local function create(map)
 local index={nodes=map.nodes,blocks={},entries={},
  count=0,queries=0,candidates_examined=0,blocks_examined=0,
  rebuilds=1}
 for k in pairs(map.nodes) do
  local pos=position(k)
  local bk=block(pos.x,pos.y,pos.z)
  local bucket=index.blocks[bk]
  if not bucket then
   bucket={x=floor(pos.x/SIZE),y=floor(pos.y/SIZE),
    z=floor(pos.z/SIZE),nodes={},count=0}
   index.blocks[bk]=bucket
  end
  bucket.nodes[k]=pos
  bucket.count=bucket.count+1
  index.entries[k]=bk
  index.count=index.count+1
 end
 return index
end
function Index.ensure(map)
 local index=map.collisionNodeIndex
 if index and index.nodes==map.nodes then return index end
 local rebuilt=create(map)
 rebuilt.rebuilds=index and index.rebuilds+1 or 1
 map.collisionNodeIndex=rebuilt
 return rebuilt
end
-- Called AFTER an official Map:set_node update; must never rebuild on
-- every world-generation edit. Lazy reconstruction handles map replacement.
function Index.changed(map,x,y,z,present)
 local index=map.collisionNodeIndex
 if not index then return end
 if index.nodes~=map.nodes then
  map.collisionNodeIndex=nil
  return
 end
 local k=x..','..y..','..z
 local existing=index.entries[k]
 if present then
  if existing then return end
  local bk=block(x,y,z)
  local bucket=index.blocks[bk]
  if not bucket then
   bucket={x=floor(x/SIZE),y=floor(y/SIZE),z=floor(z/SIZE),
    nodes={},count=0}
   index.blocks[bk]=bucket
  end
  bucket.nodes[k]={x=x,y=y,z=z}
  bucket.count=bucket.count+1
  index.entries[k]=bk
  index.count=index.count+1
 elseif existing then
  local bucket=index.blocks[existing]
  bucket.nodes[k]=nil
  bucket.count=bucket.count-1
  if bucket.count==0 then index.blocks[existing]=nil end
  index.entries[k]=nil
  index.count=index.count-1
 end
end
-- Enumerate only stored cells within inclusive voxel bounds.
-- Choose whichever is cheaper: the bounded grid of mapblocks or the
-- currently occupied mapblocks (useful for very long empty sweeps).
function Index.query(map,x1,x2,y1,y2,z1,z2)
 local index=Index.ensure(map)
 index.queries=index.queries+1
 local bx1,bx2=floor(x1/SIZE),floor(x2/SIZE)
 local by1,by2=floor(y1/SIZE),floor(y2/SIZE)
 local bz1,bz2=floor(z1/SIZE),floor(z2/SIZE)
 local volume=(bx2-bx1+1)*(by2-by1+1)*(bz2-bz1+1)
 local buckets={}
 if volume<=index.count then
  for x=bx1,bx2 do for y=by1,by2 do for z=bz1,bz2 do
   index.blocks_examined=index.blocks_examined+1
   local bucket=index.blocks[x..','..y..','..z]
   if bucket then buckets[#buckets+1]=bucket end
  end end end
 else
  for _,bucket in pairs(index.blocks) do
   index.blocks_examined=index.blocks_examined+1
   if bucket.x>=bx1 and bucket.x<=bx2 and
      bucket.y>=by1 and bucket.y<=by2 and
      bucket.z>=bz1 and bucket.z<=bz2 then
    buckets[#buckets+1]=bucket
   end
  end
 end
 local out={}
 for _,bucket in ipairs(buckets) do
  for _,pos in pairs(bucket.nodes) do
   index.candidates_examined=index.candidates_examined+1
   if pos.x>=x1 and pos.x<=x2 and
      pos.y>=y1 and pos.y<=y2 and
      pos.z>=z1 and pos.z<=z2 then
    out[#out+1]=pos
   end
  end
 end
 table.sort(out,function(a,b)
  if a.x~=b.x then return a.x<b.x end
  if a.y~=b.y then return a.y<b.y end
  return a.z<b.z
 end)
 return out
end
return Index
