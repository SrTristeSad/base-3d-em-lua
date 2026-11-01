-- Fixed Luanti nodeboxes: stonecutter blade, slabs and 24 facedir axes.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Engine=require('core.runtime')
local Nodebox=require('core.nodebox')
local Mesher=require('core.mesher')
local rt=Engine.new()
local api=rt.api
local function pos(x,y,z) return {x=x,y=y,z=z} end
local half={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}}
api.register_node('test:slab',{drawtype='nodebox',node_box=half,
 tiles={'default_stone.png'}})
api.register_node('test:saw',{drawtype='nodebox',paramtype2='facedir',
 node_box={type='fixed',fixed={
  {-.5,-.5,-.5,.5,.0625,.5},
  {-.4375,.0625,0,.4375,.5,0},
 }},tiles={'default_stone.png'}})
api.register_node('test:fourdir',{drawtype='nodebox',paramtype2='4dir',
 node_box={type='fixed',fixed={-.375,-.5,-.125,.375,.375,.125}},
 tiles={'default_stone.png'}})
api.register_node('test:painted',{drawtype='nodebox',paramtype2='colorfacedir',
 node_box={type='fixed',fixed={-.5,-.5,-.125,.5,.5,.125}},
 tiles={'default_stone.png'}})
local map=rt.map
local function geometry(name,param2)
 map:set_node(pos(0,0,0),{name=name,param2=param2 or 0})
 local vertices,stat=Mesher.build(map,rt.registry.nodes,0,0,0)
 return vertices,stat
end
local vertices,stat=geometry('test:slab')
assert(stat.faces==6 and stat.nodeboxes==1 and stat.cubes==0)
assert(#vertices==36)
local top_y,bottom_y=-math.huge,math.huge
for _,v in ipairs(vertices) do
 top_y=math.max(top_y,v[2])
 bottom_y=math.min(bottom_y,v[2])
end
assert(top_y==0 and bottom_y==-.5,'slab must not be drawn as a whole cube')
vertices,stat=geometry('test:saw')
assert(stat.faces==8 and #vertices==48,'stonecutter blade must have two sides')
local function centroid(index)
 local mid={0,0,0}
 for k=index,index+5 do
  for axis=1,3 do mid[axis]=mid[axis]+vertices[k][axis]/6 end
 end
 return mid
end
local duplicates=0
for i=1,#vertices,6 do
 local a=vertices[i]
 local ca=centroid(i)
 for j=i+6,#vertices,6 do
  local b=vertices[j]
  local cb=centroid(j)
  if math.abs(ca[1]-cb[1])<1e-8 and
   math.abs(ca[2]-cb[2])<1e-8 and
   math.abs(ca[3]-cb[3])<1e-8 and
   a[4]==-b[4] and a[5]==-b[5] and a[6]==-b[6] then
   duplicates=duplicates+1
  end
 end
end
assert(duplicates>=1,'zero-thickness upright saw must be visible from both sides')
-- Luanti facedir modulo four is left-handed around the top axis.
local yaw=Nodebox.rotate({1,0,0},'facedir',1)
assert(yaw[1]==0 and yaw[2]==0 and yaw[3]==1,
 'facedir 1 must rotate the local right direction towards +Z')
-- Six top-face axes, 4 in-plane rotations each = 24 orientations.
local directions={
 {0,1,0},{0,0,1},{0,0,-1},{1,0,0},{-1,0,0},{0,-1,0}
}
for orientation=0,23 do
 local def=rt.registry.nodes['test:saw']
 local faces=assert(Nodebox.faces(def,{param2=orientation}))
 assert(#faces==8,'all 24 facedir orientations must render blade geometry')
 local top=faces[1]
 local axis=directions[math.floor(orientation/4)+1]
 for i=1,3 do assert(top.n[i]==axis[i],
  'top-face normal mismatch for facedir '..orientation) end
 for _,f in ipairs(faces) do
  for _,v in ipairs(f.corners) do
   for i=1,3 do assert(v[i]>=-.5 and v[i]<=.5,
    'facedir rotated nodebox outside cell') end
  end
 end
 local actual,metrics=geometry('test:saw',orientation)
 assert(metrics.faces==8 and #actual==48)
end
-- Other sides of a rectangular object swap when turned horizontally.
local function bounds(vertices)
 local min={math.huge,math.huge,math.huge}
 local max={-math.huge,-math.huge,-math.huge}
 for _,v in ipairs(vertices) do
  for i=1,3 do
   min[i]=math.min(min[i],v[i])
   max[i]=math.max(max[i],v[i])
  end
 end
 return max[1]-min[1],max[2]-min[2],max[3]-min[3]
end
-- Full param2 must affect mesh cache revisions through the Map API.
map:set_node(pos(9,9,9),{name='test:fourdir',param2=0})
local before=Mesher.fingerprint(map,0,0,0)
map:set_node(pos(9,9,9),{name='test:fourdir',param2=1})
assert(before~=Mesher.fingerprint(map,0,0,0),
 'changing param2 must invalidate the mapblock mesh')
map:remove_node(pos(9,9,9))
local a=geometry('test:fourdir',0)
local b=geometry('test:fourdir',1)
local ax,ay,az=bounds(a)
local bx,by,bz=bounds(b)
assert(ax==bz and az==bx and ay==by,'4dir should rotate horizontal extent')
local e=geometry('test:painted',1)
local f=geometry('test:painted',33)
assert(#e==#f)
for i=1,#e do
 for j=1,12 do
  assert(e[i][j]==f[i][j],'colorfacedir must preserve palette-independent rotation')
 end
end
-- Neighboring full cubes can hide a boundary face, not a recessed slab face.
api.register_node('test:stone',{tiles={'default_stone.png'}})
geometry('test:slab',0)
map:set_node(pos(0,1,0),{name='test:stone'})
vertices,stat=Mesher.build(map,rt.registry.nodes,0,0,0)
assert(stat.faces==12,'recessed slab top must remain visible below neighbor')
map:set_node(pos(1,0,0),{name='test:stone'})
vertices,stat=Mesher.build(map,rt.registry.nodes,0,0,0)
assert(stat.faces==17,'slab boundary face must be occluded by solid neighbor')
assert(not Nodebox.faces({node_box={type='connected'}},{param2=0}),
 'unsupported connected nodeboxes must not be drawn as solid cubes')
print('LUA ENGINE NODEBOX PASS')
