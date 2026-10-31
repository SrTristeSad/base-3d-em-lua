-- Spatial voxel data and content ID subset of Luanti.
-- Mapblock-aligned VoxelManip buffers, x-fastest VoxelArea index ordering.
-- Does NOT implement Luanti lighting, liquid updates or mapgen algorithms.
local V={}
local floor=math.floor
local function point(p)
 assert(type(p)=='table','voxel coordinate table required')
 for _,axis in ipairs({'x','y','z'}) do
  local n=p[axis]
  assert(type(n)=='number' and n==floor(n) and
   math.abs(n)<=31000,'invalid voxel coordinate: '..axis)
 end
 return {x=p.x,y=p.y,z=p.z}
end
local function extents(minp,maxp)
 local a,b=point(minp),point(maxp)
 assert(a.x<=b.x and a.y<=b.y and a.z<=b.z,'invalid voxel extents')
 local volume=(b.x-a.x+1)*(b.y-a.y+1)*(b.z-a.z+1)
 assert(volume<=262144,'VoxelManip region exceeds Lua prototype limit')
 return a,b,volume
end
local Area={}
Area.__index=Area
function Area:new(def)
 assert(type(def)=='table','VoxelArea bounds missing')
 local minp,maxp,volume=extents(def.MinEdge,def.MaxEdge)
 local xstride=maxp.x-minp.x+1
 return setmetatable({MinEdge=minp,MaxEdge=maxp,
  ystride=xstride,zstride=xstride*(maxp.y-minp.y+1),
  volume=volume},Area)
end
function Area:index(x,y,z)
 assert(type(x)=='number' and type(y)=='number' and type(z)=='number'
  and x==floor(x) and y==floor(y) and z==floor(z)
  and x>=self.MinEdge.x and x<=self.MaxEdge.x
  and y>=self.MinEdge.y and y<=self.MaxEdge.y
  and z>=self.MinEdge.z and z<=self.MaxEdge.z,
  'VoxelArea:index outside area')
 return (z-self.MinEdge.z)*self.zstride+
  (y-self.MinEdge.y)*self.ystride+
  (x-self.MinEdge.x)+1
end
function Area:indexp(p) return self:index(p.x,p.y,p.z) end
function Area:contains(x,y,z)
 return type(x)=='number' and type(y)=='number' and type(z)=='number'
  and x>=self.MinEdge.x and x<=self.MaxEdge.x
  and y>=self.MinEdge.y and y<=self.MaxEdge.y
  and z>=self.MinEdge.z and z<=self.MaxEdge.z
end
function Area:containsp(p) return self:contains(p.x,p.y,p.z) end
function Area:iter(minp,maxp)
 local a,b=extents(minp or self.MinEdge,maxp or self.MaxEdge)
 assert(self:containsp(a) and self:containsp(b),'iterator outside area')
 local x,y,z=a.x,a.y,a.z
 return function()
  if z>b.z then return nil end
  local index=self:index(x,y,z)
  local ox,oy,oz=x,y,z
  x=x+1
  if x>b.x then x=a.x;y=y+1 end
  if y>b.y then y=a.y;z=z+1 end
  return index,ox,oy,oz
 end
end
V.VoxelArea=Area
local IDs={}
IDs.__index=IDs
function IDs.new()
 return setmetatable({names={[0]='air',[127]='ignore'},
  ids={air=0,ignore=127},nextId=128},IDs)
end
function IDs:register(name)
 assert(type(name)=='string' and name~='','invalid content name')
 if self.ids[name] then return self.ids[name] end
 local id=self.nextId
 assert(id<=65535,'content IDs exhausted')
 self.nextId=id+1
 self.ids[name]=id
 self.names[id]=name
 return id
end
function IDs:get_id(name)
 return self.ids[name] or 127
end
function IDs:get_name(id)
 assert(type(id)=='number' and id==floor(id) and id>=0 and id<=65535,
  'invalid content ID')
 return self.names[id] or 'ignore'
end
V.ContentIDs=IDs
local Manip={}
Manip.__index=Manip
function Manip.new(map,ids)
 return setmetatable({map=map,ids=ids,area=nil,
  data=nil,param2=nil,dirty=false},Manip)
end
local function arraycopy(list,n)
 local out={}
 for i=1,n do out[i]=list[i] end
 return out
end
local function checkarray(array,n,validate)
 assert(type(array)=='table' and #array==n,'incorrect VoxelManip data length')
 for i=1,n do
  local x=array[i]
  assert(type(x)=='number' and x==floor(x) and validate(x),
   'invalid voxel array at index '..i)
 end
 return arraycopy(array,n)
end
function Manip:read_from_map(minp,maxp)
 local lo,hi=extents(minp,maxp)
 local function aligned(v) return floor(v/16)*16 end
 local a={x=aligned(lo.x),y=aligned(lo.y),z=aligned(lo.z)}
 local b={x=aligned(hi.x)+15,y=aligned(hi.y)+15,z=aligned(hi.z)+15}
 local area=Area:new({MinEdge=a,MaxEdge=b})
 self.area=area
 self.data,self.param2={},{}
 for i,x,y,z in area:iter() do
  local node=self.map:get_node({x=x,y=y,z=z})
  self.data[i]=self.ids:get_id(node.name)
  self.param2[i]=node.param2
 end
 self.dirty=false
 return a,b
end
function Manip:get_emerged_area()
 assert(self.area,'read_from_map must be called first')
 return point(self.area.MinEdge),point(self.area.MaxEdge)
end
function Manip:get_data(buffer)
 assert(self.data,'VoxelManip not loaded')
 local out=buffer or {}
 for i=1,#self.data do out[i]=self.data[i] end
 return out
end
function Manip:set_data(array)
 assert(self.area,'VoxelManip not loaded')
 self.data=checkarray(array,self.area.volume,function(x)
  return x>=0 and x<=65535
 end)
 self.dirty=true
end
function Manip:get_param2_data(buffer)
 assert(self.param2,'VoxelManip not loaded')
 local out=buffer or {}
 for i=1,#self.param2 do out[i]=self.param2[i] end
 return out
end
function Manip:set_param2_data(array)
 assert(self.area,'VoxelManip not loaded')
 self.param2=checkarray(array,self.area.volume,function(x)
  return x>=0 and x<=255
 end)
 self.dirty=true
end
function Manip:get_node_at(pos)
 assert(self.area and self.area:containsp(pos),'voxel position outside buffer')
 local i=self.area:indexp(pos)
 return {name=self.ids:get_name(self.data[i]),
  param1=0,param2=self.param2[i]}
end
function Manip:set_node_at(pos,node)
 assert(self.area and self.area:containsp(pos),'voxel position outside buffer')
 assert(type(node)=='table' and type(node.name)=='string',
  'invalid node')
 local id=self.ids:get_id(node.name)
 assert(id~=127 or node.name=='ignore','unregistered voxel node')
 local p2=node.param2 or 0
 assert(type(p2)=='number' and p2==floor(p2) and p2>=0 and p2<=255,
  'invalid node param2')
 local i=self.area:indexp(pos)
 self.data[i],self.param2[i]=id,p2
 self.dirty=true
end
function Manip:write_to_map()
 assert(self.area,'VoxelManip not loaded')
 local writes=0
 if self.dirty then
  for i,x,y,z in self.area:iter() do
   local name=self.ids:get_name(self.data[i])
   if name~='ignore' then
    local p={x=x,y=y,z=z}
    local old=self.map:get_node(p)
    if old.name~=name or old.param2~=self.param2[i] then
     self.map:set_node(p,{name=name,param2=self.param2[i]})
     writes=writes+1
    end
   end
  end
 end
 self.dirty=false
 return writes
end
V.VoxelManip=Manip
return V
