-- Luanti 5.18 EmergeManager::getContainingChunk + MapgenV7 chunk bounds.
-- Sources: src/emerge.cpp, src/servermap.cpp, src/mapgen/mapgen_v7.cpp.
-- SPDX-License-Identifier: LGPL-2.1-or-later
local C={}
local floor=math.floor
local function integer(x)
 return type(x)=='number' and x==floor(x) and x==x and
  x~=math.huge and x~=-math.huge
end
local axes={'x','y','z'}
function C.size(size)
 if type(size)=='number' then size={x=size,y=size,z=size} end
 assert(type(size)=='table','mapgen chunk dimensions required')
 local s={}
 local volume=1
 for _,k in ipairs(axes) do
  local v=size[k]
  assert(integer(v) and v>=1 and v<=12,
   'invalid mapgen chunk size')
  s[k]=v
  volume=volume*v
 end
 assert(volume<=2000,'Luanti chunk volume exceeds 2000 mapblocks')
 return s
end
-- C++ integer division truncates towards zero; getContainerPos floors.
-- Example: size=5, offset=-2 => chunk containing block 0 is [-2,2].
-- For size=2, offset=-1 => chunk containing block 0 is [-1,0].
function C.containing(blockpos,size)
 local s=C.size(size)
 assert(type(blockpos)=='table','mapblock position required')
 local result={}
 for _,k in ipairs(axes) do
  local n=blockpos[k]
  assert(integer(n) and math.abs(n)<=1938,'invalid mapblock coordinate')
  local offset=-floor(s[k]/2)
  result[k]=floor((n-offset)/s[k])*s[k]+offset
 end
 return result
end
function C.geometry(blockpos,size)
 local s=C.size(size)
 local mn=C.containing(blockpos,s)
 local mx,npmin,npmax,fullmin,fullmax={},{},{},{},{}
 for _,k in ipairs(axes) do
  mx[k]=mn[k]+s[k]-1
  npmin[k]=mn[k]*16
  npmax[k]=(mx[k]+1)*16-1
  fullmin[k]=(mn[k]-1)*16
  fullmax[k]=(mx[k]+2)*16-1
  -- ServerMap::initBlockMake rejects chunks when even the extra border
  -- exceeds mapgen limits. No silent clipping at +/-31000.
  assert(math.abs(fullmin[k])<=31000 and
   math.abs(fullmax[k])<=31000,'mapgen chunk border outside world')
 end
 return {size=s,block_min=mn,block_max=mx,node_min=npmin,
  node_max=npmax,full_node_min=fullmin,full_node_max=fullmax}
end
function C.each_block(geom)
 local a,b=geom.block_min,geom.block_max
 local result={}
 for x=a.x,b.x do for y=a.y,b.y do for z=a.z,b.z do
  result[#result+1]={x=x,y=y,z=z,key=x..','..y..','..z}
 end end end
 return result
end
return C
