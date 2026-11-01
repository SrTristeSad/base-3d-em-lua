-- Luanti directiontables.cpp inverse orientation vectors.
-- Indexed with native param2 + 1; preserve 6d facedir order exactly.
local Direction={}
local facedir={
 {0,0,1},{1,0,0},{0,0,-1},{-1,0,0},
 {0,-1,0},{1,0,0},{0,1,0},{-1,0,0},
 {0,1,0},{1,0,0},{0,-1,0},{-1,0,0},
 {0,0,1},{0,-1,0},{0,0,-1},{0,1,0},
 {0,0,1},{0,1,0},{0,0,-1},{0,-1,0},
 {0,0,1},{-1,0,0},{0,0,-1},{1,0,0}
}
local fourdir={{0,0,1},{1,0,0},{0,0,-1},{-1,0,0}}
local wallmounted={
 {0,1,0},{0,-1,0},{1,0,0},{-1,0,0},
 {0,0,1},{0,0,-1},{0,1,0},{0,-1,0}
}
local function value(tbl,index)
 if type(index)~='number' or index~=math.floor(index) then return nil end
 local v=tbl[index+1]
 if not v then return nil end
 return {x=v[1],y=v[2],z=v[3]}
end
function Direction.facedir_to_dir(param2)
 return value(facedir,param2)
end
function Direction.fourdir_to_dir(param2)
 return value(fourdir,param2)
end
function Direction.wallmounted_to_dir(param2)
 return value(wallmounted,param2)
end
-- Copy of builtin_shared.check_attached_node direction and support rules.
-- Attached-to-air/non-walkable fails. This is only the placement check:
-- falling-node update and dropped item entities are not implemented here.
function Direction.check_attached(api,registry,pos,node,group_rating)
 assert(type(node)=='table' and type(node.name)=='string' and
  type(pos)=='table' and type(group_rating)=='number',
  'attached-node check requires a node, position and group')
 local def=registry[node.name]
 if not def then return false end
 if group_rating==0 then return true end
 local delta={x=0,y=0,z=0}
 local kind=def.paramtype2
 local p2=node.param2 or 0
 if group_rating==3 then
  delta.y=-1
 elseif group_rating==4 then
  delta.y=1
 elseif group_rating==2 then
  if kind=='facedir' or kind=='colorfacedir' then
   delta=Direction.facedir_to_dir(p2%32) or {x=0,y=0,z=1}
  elseif kind=='4dir' or kind=='color4dir' then
   delta=Direction.fourdir_to_dir(p2%4) or {x=0,y=0,z=1}
  end
 elseif kind=='wallmounted' or kind=='colorwallmounted' then
  delta=Direction.wallmounted_to_dir(p2%8) or {x=0,y=1,z=0}
 else
  delta.y=-1
 end
 local adjacent=api.get_node({x=pos.x+delta.x,y=pos.y+delta.y,
  z=pos.z+delta.z})
 local support=registry[adjacent.name]
 -- Lua builtin: unknown node defs do not automatically reject.
 return support==nil or support.walkable~=false
end
return Direction
