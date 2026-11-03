-- Sparse, bounded Lua flowing-liquid subset. Not the full native Luanti solver.
local Liquid={}
Liquid.__index=Liquid
local floor=math.floor
local dirs={{0,0,0},{0,-1,0},{0,1,0},{1,0,0},{-1,0,0},{0,0,1},{0,0,-1}}
local sides={{1,0,0},{-1,0,0},{0,0,1},{0,0,-1}}
local function valid(n)
 return type(n)=='number' and n==floor(n) and n>=-31000 and n<=31000
end
local function key(p) return p.x..','..p.y..','..p.z end
local function decode(k)
 local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
 return {x=tonumber(x),y=tonumber(y),z=tonumber(z)}
end
local function offset(p,d)
 local x,y,z=p.x+d[1],p.y+d[2],p.z+d[3]
 if valid(x) and valid(y) and valid(z) then
  return {x=x,y=y,z=z}
 end
end
function Liquid.new(rt,opts)
 assert(rt and rt.map and rt.registry,'liquid simulation requires runtime')
 opts=opts or {}
 local interval,budget=opts.interval or .5,opts.budget or 128
 assert(type(interval)=='number' and interval>=.01 and interval<=60,
  'invalid liquid interval')
 assert(type(budget)=='number' and budget==floor(budget) and
  budget>=1 and budget<=4096,'invalid liquid budget')
 local self=setmetatable({runtime=rt,interval=interval,budget=budget,
  clock=0,queue={},queued={},head=1,tail=0,byname={},
  tick_count=0,changed_count=0},Liquid)
 self:refresh()
 self:rescan()
 return self
end
function Liquid:refresh()
 local registry=self.runtime.registry.nodes
 local byname={}
 for name,def in pairs(registry) do
  if def.liquidtype=='source' then
   local flow=def.liquid_alternative_flowing
   local alt=registry[flow or '']
   if alt and alt.liquidtype=='flowing' and
      (not alt.liquid_alternative_source or
       alt.liquid_alternative_source==name) then
    local range=type(def.liquid_range)=='number'
      and def.liquid_range or 7
    local family={source=name,flowing=flow,
      range=math.max(1,math.min(7,floor(range))),
      renewable=def.liquid_renewable==true}
    byname[name]=family
    byname[flow]=family
   end
  end
 end
 self.byname=byname
end
function Liquid:enqueue(pos)
 if not pos or not(valid(pos.x) and valid(pos.y) and valid(pos.z)) then
  return false
 end
 local k=key(pos)
 if self.queued[k] then return false end
 self.tail=self.tail+1
 self.queue[self.tail]={x=pos.x,y=pos.y,z=pos.z}
 self.queued[k]=true
 return true
end
function Liquid:wake(pos)
 for _,d in ipairs(dirs) do self:enqueue(offset(pos,d)) end
end
function Liquid:node_changed(x,y,z)
 local pos={x=x,y=y,z=z}
 for _,d in ipairs(dirs) do
  local p=offset(pos,d)
  local n=p and self.runtime.map.nodes[key(p)]
  if n and self.byname[n.name] then
   self:wake(pos)
   return
  end
 end
end
function Liquid:rescan()
 self.queue={};self.queued={};self.head=1;self.tail=0
 local keys={}
 for k,node in pairs(self.runtime.map.nodes) do
  if self.byname[node.name] then keys[#keys+1]=k end
 end
 table.sort(keys)
 for _,k in ipairs(keys) do self:wake(decode(k)) end
end
function Liquid:_plan(pos)
 local map=self.runtime.map
 local old=map:get_node(pos)
 if old.name=='ignore' then return end
 local family=self.byname[old.name]
 if family and old.name==family.source then return end
 if old.name~='air' and
  (not family or old.name~=family.flowing) then return end
 local above=offset(pos,{0,1,0})
 local upper=above and map:get_node(above) or {name='ignore'}
 local around={}
 local contested=false
 local function consider(n)
  local f=self.byname[n.name]
  if f and family and family~=f then contested=true end
  if f and not family then family=f end
 end
 consider(upper)
 for i,d in ipairs(sides) do
  local p=offset(pos,d)
  around[i]=p and map:get_node(p) or {name='ignore'}
  consider(around[i])
 end
 if not family or contested then return end
 local from_above=upper.name==family.source or
  upper.name==family.flowing
 local level=from_above and 0 or nil
 local sources=0
 for _,n in ipairs(around) do
  if n.name==family.source then
   sources=sources+1
   if not level or level>1 then level=1 end
  elseif n.name==family.flowing then
   local prev=n.param2%8
   if n.param2>=8 then prev=0 end
   local candidate=prev+1
   if candidate<=family.range and
      (not level or candidate<level) then level=candidate end
  end
 end
 local below=offset(pos,{0,-1,0})
 local below_name=below and map:get_node(below).name or 'ignore'
 local supported=below_name~='air' and below_name~='ignore' and
  below_name~=family.flowing
 if family.renewable and sources>=2 and supported then
  return {name=family.source,param1=0,param2=0}
 end
 if not level then
  if old.name==family.flowing then
   return {name='air',param1=0,param2=0}
  end
  return
 end
 local param2=level+(from_above and not supported and 8 or 0)
 if old.name==family.flowing and old.param1==0 and
  old.param2==param2 then return end
 return {name=family.flowing,param1=0,param2=param2}
end
function Liquid:tick()
 local planned={}
 local map=self.runtime.map
 for _=1,self.budget do
  if self.head>self.tail then break end
  local pos=self.queue[self.head]
  self.queue[self.head]=nil
  self.head=self.head+1
  self.queued[key(pos)]=nil
  local target=self:_plan(pos)
  if target then planned[#planned+1]={pos=pos,node=target} end
 end
 if self.head>self.tail then
  self.queue={};self.head=1;self.tail=0
 end
 local changed,blocks={},{}
 for _,e in ipairs(planned) do
  map:set_node(e.pos,e.node)
  changed[#changed+1]=e.pos
  blocks[map:blockkey(e.pos)]=true
 end
 if #changed>0 then
  map:dispatch_modified_blocks_event(blocks,true,false)
  self.runtime:liquidTransformed(changed)
  self.changed_count=self.changed_count+#changed
 end
 self.tick_count=self.tick_count+1
 return #changed
end
function Liquid:step(dt)
 assert(type(dt)=='number' and dt>=0 and dt==dt and
  dt~=math.huge,'invalid liquid dt')
 self.clock=self.clock+dt
 local ticks=0
 while self.clock>=self.interval and ticks<4 do
  self.clock=self.clock-self.interval
  self:tick()
  ticks=ticks+1
 end
 if ticks==4 and self.clock>self.interval then
  self.clock=self.interval
 end
 return ticks
end
function Liquid:pending_count() return self.tail-self.head+1 end
return Liquid
