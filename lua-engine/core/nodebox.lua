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
local function normalized_boxes(def,param2)
 if type(def)~='table' or type(def.node_box)~='table' then return nil end
 local nodebox=def.node_box
 if nodebox.type~='fixed' then return nil end
 local boxes=nodebox.fixed
 if type(boxes)~='table' then return nil end
 if type(boxes[1])=='number' then boxes={boxes} end
 local out={}
 for _,box in ipairs(boxes) do
  if type(box)~='table' or #box~=6 then return nil end
  for i=1,6 do
   if not finite(box[i]) or abs(box[i])>1 then return nil end
  end
  if box[1]>box[4] or box[2]>box[5] or box[3]>box[6] then return nil end
  out[#out+1]=box
 end
 return out
end
function N.faces(def,node)
 local boxes=normalized_boxes(def,node and node.param2)
 if not boxes then return nil end
 local out={}
 local param2=node and node.param2 or 0
 for _,b in ipairs(boxes) do
  local v={b[1],b[4],b[3],b[5],b[2],b[6]}
  for _,shape in ipairs(shapes) do
   local axis=shape.n[1]~=0 and 1 or shape.n[2]~=0 and 2 or 3
   -- Only emit nonzero-area quads. For a zero-thickness box, this
   -- preserves both sides of its actual plane without bogus side faces.
   local dx,dy,dz=b[4]-b[1],b[5]-b[2],b[6]-b[3]
   local area=axis==1 and dy*dz or axis==2 and dx*dz or dx*dy
   if area>0 then
    local corners={}
    for _,indices in ipairs(shape.corners) do
     corners[#corners+1]=N.rotate({v[indices[1]],v[indices[2]],
                                   v[indices[3]]},def.paramtype2,param2)
    end
    local norm=N.rotate(shape.n,def.paramtype2,param2)
    out[#out+1]={n=norm,tile=shape.tile,shade=shape.shade,
      corners=corners}
   end
  end
 end
 return out
end
return N
