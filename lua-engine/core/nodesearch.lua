-- Luanti 5.18 node search helpers for the Lua map.
-- Respects aliases, concrete node names, and group selectors. The present
-- map is sparse and treats non-stored positions as air; Luanti's distinction
-- between unloaded ("ignore") and generated air is still outstanding.
local Search={}
local floor=math.floor
local function match(name,filter,definitions,aliases)
 local resolved=name
 local seen={}
 while aliases[resolved] and not seen[resolved] do
  seen[resolved]=true
  resolved=aliases[resolved]
 end
 local def=definitions[name] or definitions[resolved]
 for _,selector in ipairs(filter) do
  local canonical=selector
  local visited={}
  while aliases[canonical] and not visited[canonical] do
   visited[canonical]=true
   canonical=aliases[canonical]
  end
  if canonical==name or canonical==resolved then return true end
  local group=selector:match('^group:(.+)$')
  if group and def and type(def.groups)=='table' and
   (def.groups[group] or 0)>0 then
   return true
  end
 end
 return false
end
local function normalize(selectors)
 if type(selectors)=='string' then return {selectors} end
 assert(type(selectors)=='table',
  'node selector must be a string or list')
 local list={}
 for i=1,#selectors do
  assert(type(selectors[i])=='string','invalid node selector')
  list[#list+1]=selectors[i]
 end
 return list
end
local function validate_bounds(map,a,b)
 -- Existing Lua map validates integer coordinates and the world limit.
 local x1,y1,z1=map.key(a) and a.x,a.y,a.z
 local x2,y2,z2=map.key(b) and b.x,b.y,b.z
 return {x=math.min(x1,x2),y=math.min(y1,y2),z=math.min(z1,z2)},
  {x=math.max(x1,x2),y=math.max(y1,y2),z=math.max(z1,z2)}
end
function Search.area(map,definitions,aliases,p1,p2,selectors,grouped)
 local a,b=validate_bounds(map,p1,p2)
 local filter=normalize(selectors)
 local results,counts={},{}
 for _,entry in ipairs(map:iter_nodes(a,b)) do
  local name=entry.node.name
  if match(name,filter,definitions,aliases) then
   if grouped then
    local list=results[name] or {}
    list[#list+1]=entry.pos
    results[name]=list
   else
    results[#results+1]=entry.pos
   end
   counts[name]=(counts[name] or 0)+1
  end
 end
 if grouped==true then return results end
 return results,counts
end
function Search.under_air(map,definitions,aliases,p1,p2,selectors)
 local a,b=validate_bounds(map,p1,p2)
 local filter=normalize(selectors)
 local results={}
 for _,entry in ipairs(map:iter_nodes(a,b)) do
  local pos,name=entry.pos,entry.node.name
  if name~='air' and
   match(name,filter,definitions,aliases) and
   pos.y<31000 and map:get_node({x=pos.x,y=pos.y+1,z=pos.z}).name=='air' then
   results[#results+1]=pos
  end
 end
 return results
end
function Search.near(map,definitions,aliases,pos,radius,selectors,center)
 map.key(pos)
 assert(type(radius)=='number' and radius==floor(radius) and
  radius>=0 and radius<=64,'unsupported node search radius (0..64)')
 local filter=normalize(selectors)
 local start=center==true and 0 or 1
 for d=start,radius do
  for dx=-d,d do for dy=-d,d do for dz=-d,d do
   if math.max(math.abs(dx),math.abs(dy),math.abs(dz))==d then
    local p={x=pos.x+dx,y=pos.y+dy,z=pos.z+dz}
    if math.abs(p.x)<=31000 and math.abs(p.y)<=31000 and
     math.abs(p.z)<=31000 and
     match(map:get_node(p).name,filter,definitions,aliases) then
     return p
    end
   end
  end end end
 end
 return nil
end
return Search
