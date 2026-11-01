-- Luanti Lua Engine: sparse voxel map (16^3 mapblocks).
-- A implementation is intentionally independent of the old Beta 1.8 world.
local Inventory=require('core.inventory')
local Map={}
Map.__index=Map
Map.BLOCKSIZE=16
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
  revisions={},modified={},generatedChunks={},count=0,
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
function Map:get_node(p)
 local n=self.nodes[Map.key(p)]
 if not n then return {name='air',param1=0,param2=0} end
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
 local oldname=old and old.name or 'air'
 if name=='air' then
  if old then self.count=self.count-1 end
  self.nodes[k]=nil
 else
  if not old then self.count=self.count+1 end
  self.nodes[k]={name=name,param1=p1,param2=p2}
 end
 if oldname~=name or (old and (old.param1~=p1 or old.param2~=p2)) then
  -- Collision nodeboxes (including connected neighbors) may depend on
  -- any changed cell. A single monotonic stamp invalidates cached shapes.
  self.geometry_revision=self.geometry_revision+1
  local block=bk(x,y,z)
  self.revisions[block]=(self.revisions[block] or 0)+1
  self.modified[block]=true
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
