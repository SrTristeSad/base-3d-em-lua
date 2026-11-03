-- Luanti-compatible world object queries across live LuaEntities,
-- dropped item ObjectRefs and connected host PlayerRefs.
-- The caller receives references, not copies of entity/player state.
local Entities=require('core.luaentities')
local Objects={}
local huge=math.huge
local function finite(n)
 return type(n)=='number' and n==n and n~=huge and n~=-huge
end
local function pos(v,label)
 assert(type(v)=='table' and finite(v.x) and finite(v.y) and
  finite(v.z),'invalid '..label..' position')
 return {x=v.x,y=v.y,z=v.z}
end
local function object_pos(obj)
 if type(obj)~='table' or type(obj.get_pos)~='function' then
  return nil
 end
 local p=obj:get_pos()
 if type(p)=='table' and finite(p.x) and finite(p.y) and
  finite(p.z) then return p end
 return nil
end
local function players(rt)
 local names={}
 for name in pairs(rt.players or {}) do names[#names+1]=name end
 table.sort(names)
 local out={}
 for _,name in ipairs(names) do
  local player=rt.players[name]
  if player then out[#out+1]=player end
 end
 return out
end
local function add_other_refs(rt,output,accept)
 -- Stable order after LuaEntities: dropped items (world order),
 -- then connected players (name order). Native Luanti does not promise
 -- a particular result order; deterministic Lua order aids repeatability.
 for _,obj in ipairs(rt.droppedItems or {}) do
  if not obj.removed then
   local p=object_pos(obj)
   if p and accept(p) then output[#output+1]=obj end
  end
 end
 for _,player in ipairs(players(rt)) do
  local p=object_pos(player)
  if p and accept(p) then output[#output+1]=player end
 end
 return output
end
function Objects.inside_radius(rt,position,radius)
 local p=pos(position,'radius center')
 assert(finite(radius) and radius>=0,
  'object radius must be finite and nonnegative')
 local out=Entities.radius(rt,p,radius)
 local squared=radius*radius
 return add_other_refs(rt,out,function(v)
  local x,y,z=v.x-p.x,v.y-p.y,v.z-p.z
  return x*x+y*y+z*z<=squared
 end)
end
function Objects.in_area(rt,corner1,corner2)
 local minp,maxp=pos(corner1,'min'),pos(corner2,'max')
 assert(minp.x<=maxp.x and minp.y<=maxp.y and
  minp.z<=maxp.z,'invalid object query cuboid')
 local function includes(p)
  return p.x>=minp.x and p.x<=maxp.x and
   p.y>=minp.y and p.y<=maxp.y and
   p.z>=minp.z and p.z<=maxp.z
 end
 local out={}
 -- get_objects_in_area is a CENTER query, not a collisionbox overlap.
 -- Inactive/removed LuaEntities do not appear in Entities.get.
 for _,obj in ipairs(Entities.get(rt)) do
  if includes(obj.pos) then out[#out+1]=obj end
 end
 return add_other_refs(rt,out,includes)
end
return Objects
