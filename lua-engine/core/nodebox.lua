-- Nodebox geometry for the independent Lua mesher.
-- Luanti coordinates: x right, y up, z forwards.  Full facedir (24
-- orientations), 4dir and colorfacedir use the six possible top axes.
-- Connected nodeboxes, leveled height and wallmounted are separate cases.
local N={}
local abs=math.abs
local shapes={
 {n={0,1,0},tile=1,shade=1,
  corners={{1,4,3},{1,4,6},{2,4,6},{2,4,3}}},
 {n={0,-1,0},tile=2,shade=.58,
  corners={{1,5,6},{1,5,3},{2,5,3},{2,5,6}}},
 {n={1,0,0},tile=3,shade=.82,
  corners={{2,5,6},{2,5,3},{2,4,3},{2,4,6}}},
 {n={-1,0,0},tile=4,shade=.76,
  corners={{1,5,3},{1,5,6},{1,4,6},{1,4,3}}},
 {n={0,0,1},tile=5,shade=.9,
  corners={{1,5,6},{2,5,6},{2,4,6},{1,4,6}}},
 {n={0,0,-1},tile=6,shade=.72,
  corners={{2,5,3},{1,5,3},{1,4,3},{2,4,3}}},
}
-- Above vertices use box indices:
-- 1=xmin, 2=xmax, 3=zmin, 4=ymax, 5=ymin, 6=zmax.
-- Their winding is independent of face rotation.
local initial={
 -- Local +x,+y,+z columns; each orientation has determinant +1.
 {{1,0,0},{0,1,0},{0,0,1}},
 {{1,0,0},{0,0,1},{0,-1,0}},
 {{1,0,0},{0,0,-1},{0,1,0}},
 {{0,-1,0},{1,0,0},{0,0,1}},
 {{0,1,0},{-1,0,0},{0,0,1}},
 {{-1,0,0},{0,-1,0},{0,0,1}},
}
local function turn(v,axis,steps)
 -- Luanti facedir uses left-handed quarter turns about the node top.
 for _=1,steps do
  local ax,ay,az=axis[1],axis[2],axis[3]
  local dot=v[1]*ax+v[2]*ay+v[3]*az
  v={az*v[2]-ay*v[3]+ax*dot,
     ax*v[3]-az*v[1]+ay*dot,
     ay*v[1]-ax*v[2]+az*dot}
 end
 return v
end
local function matrix(paramtype,param2)
 param2=param2 or 0
 local rotation
 if paramtype=='4dir' then rotation=param2%4
 elseif paramtype=='color4dir' then rotation=param2%4
 elseif paramtype=='facedir' then rotation=param2%32
 elseif paramtype=='colorfacedir' then rotation=param2%32
 else return initial[1] end
 if rotation>=24 then rotation=0 end
 local top=math.floor(rotation/4)
 local basis=initial[top+1]
 local up=basis[2]
 local steps=rotation%4
 return {turn(basis[1],up,steps),up,turn(basis[3],up,steps)}
end
function N.rotate(v,paramtype,param2)
 local m=matrix(paramtype,param2)
 return {v[1]*m[1][1]+v[2]*m[2][1]+v[3]*m[3][1],
         v[1]*m[1][2]+v[2]*m[2][2]+v[3]*m[3][2],
         v[1]*m[1][3]+v[2]*m[2][3]+v[3]*m[3][3]}
end
local function finite(v)
 return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge
end

-- A box is either six coordinates or a list of such boxes.
local function box_list(value)
 if type(value)~='table' then return nil end
 if type(value[1])=='number' then value={value} end
 local out={}
 for _,box in ipairs(value) do
  if type(box)~='table' or #box~=6 then return nil end
  for i=1,6 do
   if not finite(box[i]) or abs(box[i])>1.45 then return nil end
  end
  if box[1]>box[4] or box[2]>box[5] or box[3]>box[6] then return nil end
  out[#out+1]={box[1],box[2],box[3],box[4],box[5],box[6]}
 end
 return out
end
local function append(dst,boxes)
 if not boxes then return false end
 for _,box in ipairs(boxes) do dst[#dst+1]=box end
 return true
end

-- Luanti's connected nodebox directions use front=-Z and back=+Z.
local directions={
 {name='top',x=0,y=1,z=0},
 {name='bottom',x=0,y=-1,z=0},
 {name='front',x=0,y=0,z=-1},
 {name='left',x=-1,y=0,z=0},
 {name='back',x=0,y=0,z=1},
 {name='right',x=1,y=0,z=0},
}
local function allowed_sides(def,side)
 local sides=def.connect_sides
 if type(sides)~='table' or next(sides)==nil then return true end
 for _,name in ipairs(sides) do
  if name==side then return true end
 end
 return false
end
local function matches(def,source,other,registry)
 if not other or other.name=='air' or other.name=='ignore' then return false end
 local patterns=def.connects_to
 if type(patterns)=='string' then patterns={patterns} end
 if type(patterns)~='table' then return false end
 for _,pattern in ipairs(patterns) do
  if pattern==other.name then return true end
  if type(pattern)=='string' and pattern:sub(1,6)=='group:' then
   local neighbor_def=registry and registry[other.name]
   if neighbor_def then
    local groups=neighbor_def.groups or {}
    local group=pattern:sub(7)
    if type(groups[group])=='number' and groups[group]>0 then
     return true
    end
   end
  end
 end
 return false
end

-- Wallmounted nodeboxes provide three distinct shapes; top and bottom
-- shapes are already placed and must not be rotated as ordinary facedir.
local function wall_side(box,orient)
 local x1,y1,z1,x2,y2,z2=box[1],box[2],box[3],box[4],box[5],box[6]
 if orient==2 then
  -- side defined for x-, rotate 180 degrees for x+
  return {-x2,y1,-z2,-x1,y2,-z1}
 elseif orient==4 then
  -- x- to z+
  return {z1,y1,-x2,z2,y2,-x1}
 elseif orient==5 then
  -- x- to z-
  return {-z2,y1,x1,-z1,y2,x2}
 end
 return box
end
local function normalized_boxes(def,node,map,pos,registry)
 if type(def)~='table' or type(def.node_box)~='table' then return nil end
 local nodebox=def.node_box
 local kind=nodebox.type
 if kind=='regular' then return {{-.5,-.5,-.5,.5,.5,.5}} end
 if kind=='fixed' then return box_list(nodebox.fixed) end
 if kind=='leveled' then
  local boxes=box_list(nodebox.fixed)
  if not boxes then return nil end
  local param2=node and node.param2 or 0
  local level=def.leveled or 0
  if def.paramtype2=='leveled' and param2~=0 then level=param2 end
  if not finite(level) or level<0 or level>127 then return nil end
  local offset=level/64
  for _,box in ipairs(boxes) do
   -- Leveled nodebox top follows the current level measured from
   -- the minimum Y of the original box.
   box[5]=math.min(1.45,box[2]+offset)
  end
  return boxes
 end
 if kind=='wallmounted' then
  local orient=(node and node.param2 or 0)%8
  if def.paramtype2=='colorwallmounted' then orient=orient%8 end
  local property=orient==0 and 'wall_top' or
   (orient==1 or orient==7) and 'wall_bottom' or
   orient==6 and 'wall_top' or 'wall_side'
  local boxes=box_list(nodebox[property])
  if not boxes then return nil end
  if property=='wall_side' then
   for i,box in ipairs(boxes) do boxes[i]=wall_side(box,orient) end
  elseif orient==6 or orient==7 then
   -- Special vertical wallmounted values rotate the pre-positioned
   -- top/bottom nodebox by 90 degrees around the local Y axis.
   local rotated={}
   for _,box in ipairs(boxes) do
    local x1,y1,z1,x2,y2,z2=box[1],box[2],box[3],box[4],box[5],box[6]
    if orient==6 then
     rotated[#rotated+1]={z1,y1,-x2,z2,y2,-x1}
    else
     rotated[#rotated+1]={-z2,y1,x1,-z1,y2,x2}
    end
   end
   boxes=rotated
  end
  return boxes
 end
 if kind=='connected' then
  if not map or not pos or type(map.get_node)~='function' then return nil end
  local out={}
  if not append(out,box_list(nodebox.fixed or {})) then return nil end
  local connected_any,connected_sides=false,false
  for _,side in ipairs(directions) do
   local neighbor=map:get_node({
    x=pos.x+side.x,y=pos.y+side.y,z=pos.z+side.z})
   local connected=allowed_sides(def,side.name) and
    matches(def,node,neighbor,registry)
   if connected then
    connected_any=true
    if side.y==0 then connected_sides=true end
   end
   local property=(connected and 'connect_' or 'disconnected_')..side.name
   if nodebox[property]~=nil then
    if not append(out,box_list(nodebox[property])) then return nil end
   end
  end
  if not connected_any and nodebox.disconnected~=nil then
   if not append(out,box_list(nodebox.disconnected)) then return nil end
  end
  if not connected_sides and nodebox.disconnected_sides~=nil then
   if not append(out,box_list(nodebox.disconnected_sides)) then return nil end
  end
  return out
 end
 return nil
end

function N.faces(def,node,map,pos,registry)
 local boxes=normalized_boxes(def,node,map,pos,registry)
 if not boxes then return nil end
 local out={}
 -- Luanti: connected nodeboxes never rotate with facedir.
 -- Wallmounted box shapes already encode their mounting orientation.
 local paramtype=def.paramtype2
 if def.node_box.type=='connected' or def.node_box.type=='wallmounted' or
  def.node_box.type=='leveled' then
  paramtype=nil
 end
 local param2=node and node.param2 or 0
 for _,b in ipairs(boxes) do
  local v={b[1],b[4],b[3],b[5],b[2],b[6]}
  for _,shape in ipairs(shapes) do
   local axis=shape.n[1]~=0 and 1 or shape.n[2]~=0 and 2 or 3
   local dx,dy,dz=b[4]-b[1],b[5]-b[2],b[6]-b[3]
   local area=axis==1 and dy*dz or axis==2 and dx*dz or dx*dy
   if area>0 then
    local corners={}
    for _,indices in ipairs(shape.corners) do
     corners[#corners+1]=N.rotate(
      {v[indices[1]],v[indices[2]],v[indices[3]]},paramtype,param2)
    end
    local norm=N.rotate(shape.n,paramtype,param2)
    out[#out+1]={n=norm,tile=shape.tile,shade=shape.shade,
     corners=corners}
   end
  end
 end
 return out
end
return N
