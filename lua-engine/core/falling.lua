-- Luanti builtin/game/falling.lua subset: adjacent-node update, gravity,
-- and dropped items. The host still owns rendering and object pickup.
local Attached=require('core.attached')
local Stack=require('core.itemstack')
local Falling={}
local floor=math.floor
local gravity=9.81
local function copy(p) return {x=p.x,y=p.y,z=p.z} end
local function integer_position(p)
 assert(type(p)=='table' and type(p.x)=='number' and
  type(p.y)=='number' and type(p.z)=='number' and
  p.x==floor(p.x) and p.y==floor(p.y) and p.z==floor(p.z),
  'falling-node check requires integer coordinates')
 return copy(p)
end
local function add(p,d)
 return {x=p.x+d.x,y=p.y+d.y,z=p.z+d.z}
end
local function key(p)
 return p.x..','..p.y..','..p.z
end
-- Luanti builtin falling.lua deliberately checks these 11 neighbors in order.
local neighbors={
 {x=-1,y=-1,z=0},{x=1,y=-1,z=0},
 {x=0,y=-1,z=-1},{x=0,y=-1,z=1},
 {x=0,y=-1,z=0},
 {x=-1,y=0,z=0},{x=1,y=0,z=0},
 {x=0,y=0,z=1},{x=0,y=0,z=-1},
 {x=0,y=0,z=0},{x=0,y=1,z=0}
}
local function accessible(p)
 return p.x>=-31000 and p.x<=31000 and
  p.y>=-31000 and p.y<=31000 and
  p.z>=-31000 and p.z<=31000
end
local function clear_node(rt,pos)
 rt.api.remove_node(pos)
 rt.api.get_meta(pos):from_table({fields={},inventory={}})
 rt.api.get_node_timer(pos):stop()
end
-- Records drops as host-visible objects. Never serialize metadata to a
-- lossy itemstring; ItemStack.to_string rejects metadata-bearing stacks.
function Falling.add_item(rt,pos,item)
 assert(type(pos)=='table' and type(pos.x)=='number' and
  type(pos.y)=='number' and type(pos.z)=='number',
  'dropped item requires position')
 local stack=Stack.new(item,rt.registry.items)
 if stack:is_empty() then return nil end
 rt.droppedItems=rt.droppedItems or {}
 local obj={pos=copy(pos),stack=stack,removed=false}
 function obj:get_pos() return copy(self.pos) end
 function obj:get_item() return self.stack:copy() end
 function obj:remove()
  if self.removed then return end
  self.removed=true
  for i,v in ipairs(rt.droppedItems) do
   if v==self then table.remove(rt.droppedItems,i);break end
  end
 end
 rt.droppedItems[#rt.droppedItems+1]=obj
 return obj
end
function Falling.get_dropped_items(rt)
 local out={}
 for _,obj in ipairs(rt.droppedItems or {}) do
  out[#out+1]={pos=obj:get_pos(),stack=obj:get_item()}
 end
 return out
end
function Falling.get_falling_nodes(rt)
 local out={}
 for _,obj in ipairs(rt.fallingNodes or {}) do
  out[#out+1]={pos=copy(obj.pos),node={
   name=obj.node.name,param1=obj.node.param1,param2=obj.node.param2},
   velocity=obj.velocity}
 end
 return out
end
local function passable(rt,falling,under)
 local bdef=rt.registry.nodes[under.name]
 if not bdef then return false end
 if falling.name==under.name then return false end
 if bdef.walkable~=false and not bdef.buildable_to then return false end
 local fdef=rt.registry.nodes[falling.name]
 local floating=fdef and (fdef.groups or {}).float or 0
 if floating==0 or bdef.liquidtype==nil or
   bdef.liquidtype=='none' then return true end
 return fdef.liquidtype=='source' and bdef.liquidtype~='source'
end
local function capture_timer(api,pos)
 local timer=api.get_node_timer(pos)
 if not timer:is_started() then return nil end
 return {timeout=timer:get_timeout(),elapsed=timer:get_elapsed()}
end
-- Transform voxel into a pending falling object. No initial free fall is
-- required here: core.spawn_falling_node explicitly forces conversion.
function Falling.spawn(rt,where)
 local pos=integer_position(where)
 local api=rt.api
 local node=api.get_node(pos)
 if node.name=='air' or node.name=='ignore' or
  not rt.registry.nodes[node.name] then return false end
 rt.fallingNodes=rt.fallingNodes or {}
 local obj={pos=copy(pos),node=node,
  meta=api.get_meta(pos):to_table(),
  timer=capture_timer(api,pos),velocity=0}
 clear_node(rt,pos)
 rt.fallingNodes[#rt.fallingNodes+1]=obj
 return true,obj
end
local function drop_attached(rt,pos,node,def)
 local api=rt.api
 local drops=api.get_node_drops(node.name,'')
 if def.preserve_metadata then
  local meta=api.get_meta(pos):to_table()
  local fields={}
  for k,v in pairs(meta.fields or {}) do fields[k]=v end
  for i,v in ipairs(drops) do drops[i]=Stack.new(v,rt.registry.items) end
  def.preserve_metadata(copy(pos),{
   name=node.name,param1=node.param1,param2=node.param2},fields,drops)
 end
 clear_node(rt,pos)
 for _,item in ipairs(drops) do Falling.add_item(rt,pos,item) end
end
-- Returns true if it transformed the node. Mirrors check order from Luanti.
function Falling.check_single(rt,where)
 local pos=integer_position(where)
 if not accessible(pos) then return false end
 local node=rt.api.get_node(pos)
 local def=rt.registry.nodes[node.name]
 if not def or node.name=='air' or node.name=='ignore' then return false end
 if ((def.groups or {}).falling_node or 0)~=0 then
  local below={x=pos.x,y=pos.y-1,z=pos.z}
  if accessible(below) then
   local bottom=rt.api.get_node(below)
   if passable(rt,node,bottom) then
    return Falling.spawn(rt,pos)
   end
  end
 end
 local attached=(def.groups or {}).attached_node or 0
 if attached~=0 and not Attached.check_attached(
   rt.api,rt.registry.nodes,pos,node,attached) then
  drop_attached(rt,pos,node,def)
  return true
 end
 return false
end
-- Finite worklist for chained support failures. Every changed node queues
-- neighbors, as in native check_for_falling. Mutations are deliberate:
-- raw set_node/remove_node do not implicitly trigger this lifecycle.
function Falling.check(rt,where)
 local center=integer_position(where)
 local work,pending,head={},{},1
 local function enqueue(pos)
  if not accessible(pos) then return end
  local k=key(pos)
  if pending[k] then return end
  pending[k]=true
  work[#work+1]=pos
 end
 for _,d in ipairs(neighbors) do enqueue(add(center,d)) end
 local changed=0
 while head<=#work do
  if head>32768 then
   error('falling propagation exceeded 32768 checks',2)
  end
  local pos=work[head]
  head=head+1
  pending[key(pos)]=nil
  if Falling.check_single(rt,pos) then
   changed=changed+1
   for _,d in ipairs(neighbors) do enqueue(add(pos,d)) end
  end
 end
 return changed
end
local function settle(rt,obj,where)
 local api=rt.api
 local existing=api.get_node(where)
 local def=rt.registry.nodes[existing.name]
 if existing.name~='air' and not (def and def.buildable_to) then
  return false
 end
 api.get_node_timer(where):stop()
 api.get_meta(where):from_table({fields={},inventory={}})
 api.set_node(where,obj.node)
 local newdef=rt.registry.nodes[obj.node.name]
 if newdef and newdef.on_construct then newdef.on_construct(copy(where)) end
 api.get_meta(where):from_table(obj.meta)
 if obj.timer then
  api.get_node_timer(where):set(obj.timer.timeout,obj.timer.elapsed)
 end
 return true
end
-- Host-independent falling object motion with swept vertical voxel tests.
-- No object/player collisions, leveled merging or floating-on-water yet.
function Falling.step(rt,dt)
 assert(type(dt)=='number' and dt>=0 and dt==dt and dt~=math.huge,
  'invalid falling timestep')
 local pending=rt.fallingNodes or {}
 for i=#pending,1,-1 do
  local obj=pending[i]
  local y=obj.pos.y
  local speed=obj.velocity-gravity*dt
  local target=math.max(-30999,y+obj.velocity*dt-.5*gravity*dt*dt)
  local from=floor(y+.5)
  local to=floor(target+.5)
  local landing=nil
  for cell=from-1,to,-1 do
   if cell < -31000 then break end
   local at={x=obj.pos.x,y=cell,z=obj.pos.z}
   local under=rt.api.get_node(at)
   if not passable(rt,obj.node,under) then
    landing={x=at.x,y=cell+1,z=at.z}
    break
   end
  end
  if landing then
   if settle(rt,obj,landing) then
    table.remove(pending,i)
    Falling.check(rt,landing)
   else
    -- Placement blocked by a concurrent world edit. Retain object rather
    -- than silently deleting its node and inventory metadata.
    obj.velocity=0
    obj.pos.y=math.max(y,landing.y)
   end
  else
   obj.pos.y=target
   obj.velocity=speed
  end
 end
end
return Falling
