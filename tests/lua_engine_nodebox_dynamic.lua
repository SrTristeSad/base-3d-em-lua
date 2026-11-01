-- Original Luanti nodebox connectivity, param2 height, wall orientation.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Nodebox=require('core.nodebox')
local Mesher=require('core.mesher')
local rt=Runtime.new()
local api=rt.api
local map=rt.map
local function at(x,y,z)return {x=x,y=y,z=z} end
local function bbox(def,node,pos)
 return assert(Nodebox.faces(def,node,map,pos or at(2,2,2),rt.registry.nodes))
end
local function extent(faces)
 local mn={math.huge,math.huge,math.huge}
 local mx={-math.huge,-math.huge,-math.huge}
 for _,f in ipairs(faces) do
  for _,p in ipairs(f.corners) do
   for i=1,3 do
    mn[i]=math.min(mn[i],p[i])
    mx[i]=math.max(mx[i],p[i])
   end
  end
 end
 return mn,mx
end
api.register_node('test:fence',{
 drawtype='nodebox',paramtype2='facedir',
 groups={fence=1},
 connects_to={'group:fence','test:stone'},
 node_box={type='connected',
  fixed={-.125,-.5,-.125,.125,.5,.125},
  connect_right={.125,-.125,-.125,.5,.125,.125},
  connect_left={-.5,-.125,-.125,-.125,.125,.125},
  connect_front={-.125,-.125,-.5,.125,.125,-.125},
  connect_back={-.125,-.125,.125,.125,.125,.5},
  disconnected={-.25,-.5,-.25,.25,-.375,.25},
  disconnected_sides={-.375,.375,-.375,.375,.5,.375},
 }})
api.register_node('test:stone',{groups={cracky=1}})
api.register_node('test:wood',{drawtype='airlike',groups={fence=1}})
local fence=rt.registry.nodes['test:fence']
local place=at(2,2,2)
map:set_node(place,{name='test:fence'})
local standalone=bbox(fence,map:get_node(place),place)
assert(#standalone==18,'isolated fence must show core and disconnected decorations')
local _,initial=Mesher.build(map,rt.registry.nodes,0,0,0)
assert(initial.nodeboxes==1 and initial.faces==18)
local old=Mesher.fingerprint(map,0,0,0)
map:set_node(at(3,2,2),{name='test:wood'})
assert(old~=Mesher.fingerprint(map,0,0,0),'neighbor must invalidate mesh')
local connected=bbox(fence,map:get_node(place),place)
assert(#connected==12,'right-connected fence must use right arm and no disconnected')
local mn,mx=extent(connected)
assert(mx[1]==.5,'right arm must reach adjacent node boundary')
local _,stats=Mesher.build(map,rt.registry.nodes,0,0,0)
assert(stats.nodeboxes==1 and stats.faces==12)
map:remove_node(at(3,2,2))
map:set_node(at(2,2,1),{name='test:stone'})
local front=bbox(fence,map:get_node(place),place)
assert(#front==12,'front is negative Z and connects to stone by name')
local fm,fx=extent(front)
assert(fm[3]==-.5,'front arm must extend towards -Z')
map:remove_node(at(2,2,1))
map:set_node(at(3,2,2),{name='test:wood'})
map:set_node(at(1,2,2),{name='test:wood'})
map:set_node(at(2,2,3),{name='test:wood'})
local sides=bbox(fence,map:get_node(place),place)
assert(#sides==24,'multiple connecting directions use three arms and central post')
-- Facedir MUST NOT rotate connected nodeboxes (Luanti special case).
local v0=bbox(fence,{name='test:fence',param2=0},place)
local v1=bbox(fence,{name='test:fence',param2=10},place)
assert(#v0==#v1)
for i=1,#v0 do
 for j=1,4 do
  for axis=1,3 do
   assert(v0[i].corners[j][axis]==v1[i].corners[j][axis])
  end
 end
end
api.register_node('test:restricted',{drawtype='nodebox',
 connects_to={'group:fence'},connect_sides={'left'},
 node_box={type='connected',fixed={-.125,-.5,-.125,.125,.5,.125},
 connect_right={.125,-.1,-.1,.5,.1,.1},
 connect_left={-.5,-.1,-.1,-.125,.1,.1}}})
local restricted=rt.registry.nodes['test:restricted']
local only_left=bbox(restricted,{name='test:restricted'},place)
assert(#only_left==12,'connect_sides list must suppress disallowed right arm')
map:remove_node(at(1,2,2))
local no_left=bbox(restricted,{name='test:restricted'},place)
assert(#no_left==6,'connect_sides left must ignore existing right neighbor')
api.register_node('test:level',{drawtype='nodebox',paramtype2='leveled',
 leveled=16,node_box={type='leveled',fixed={-.5,-.5,-.5,.5,.5,.5}}})
local level=rt.registry.nodes['test:level']
local function top(n)
 local faces=bbox(level,{name='test:level',param2=n},place)
 return faces[1].corners[1][2]
end
assert(top(0)==-.25 and top(32)==0 and top(64)==.5)
assert(top(127)==1.45,'high leveled block must respect supported soft limit')
api.register_node('test:wall',{drawtype='nodebox',paramtype2='wallmounted',
 node_box={type='wallmounted',
  wall_top={-.3,.375,-.1,.3,.5,.1},
  wall_bottom={-.3,-.5,-.1,.3,-.375,.1},
  wall_side={-.5,-.3,-.1,-.375,.3,.1}}})
local wall=rt.registry.nodes['test:wall']
local function limits(n)
 return extent(bbox(wall,{name='test:wall',param2=n},place))
end
local m0,M0=limits(0)
assert(m0[2]==.375 and M0[2]==.5,'wallmounted top selection')
local m1,M1=limits(1)
assert(m1[2]==-.5 and M1[2]==-.375,'wallmounted bottom selection')
local m2,M2=limits(2)
assert(m2[1]==.375 and M2[1]==.5,'wallmounted positive X')
local m3,M3=limits(3)
assert(m3[1]==-.5 and M3[1]==-.375,'wallmounted negative X')
local m4,M4=limits(4)
assert(m4[3]==.375 and M4[3]==.5,'wallmounted positive Z')
local m5,M5=limits(5)
assert(m5[3]==-.5 and M5[3]==-.375,'wallmounted negative Z')
local m6,M6=limits(6)
assert(m6[1]==-.1 and M6[1]==.1,'rotated top swaps horizontal footprint')
local m7,M7=limits(7)
assert(m7[1]==-.1 and M7[1]==.1,'rotated bottom swaps horizontal footprint')
local unsupported=Nodebox.faces({node_box={type='unknown'}},{param2=0})
assert(unsupported==nil,'unknown shapes must not silently render full cubes')
-- Luanti nodebox query shares the dynamic geometry with meshing.
map:set_node(place,{name='test:fence',param2=0})
local resolved=api.get_node_boxes('node_box',place)
assert(#resolved==3,'two neighbors should produce a post plus two rails')
map:remove_node(at(3,2,2))
resolved=api.get_node_boxes('node_box',place)
assert(#resolved==2,'removing a connection must update queried node boxes')
map:set_node(at(5,2,2),{name='test:level',param2=32})
local query=api.get_node_boxes('node_box',at(5,2,2))
assert(#query==1 and query[1][5]==0,
 'leveled geometry must be visible through the public API')
map:set_node(at(6,2,2),{name='test:wall',param2=4})
query=api.get_node_boxes('node_box',at(6,2,2))
assert(query[1][3]==.375 and query[1][6]==.5,
 'wallmounted geometry must resolve through the public API')
api.register_node('test:select',{drawtype='nodebox',paramtype2='4dir',
 node_box={type='fixed',fixed={-.5,-.5,-.125,.5,.5,.125}},
 selection_box={type='fixed',fixed={-.25,-.25,-.375,.25,.25,.375}}})
map:set_node(at(7,2,2),{name='test:select',param2=1})
local selection=api.get_node_boxes('selection_box',at(7,2,2))
local collision=api.get_node_boxes('collision_box',at(7,2,2))
local visual=api.get_node_boxes('node_box',at(7,2,2))
assert(#selection==1 and #collision==1 and #visual==1)
assert(selection[1][1]==-.375 and selection[1][4]==.375,
 'selection box must rotate independently from visible box')
assert(collision[1][1]==-.125 and collision[1][4]==.125,
 'default collision box should use rotated node box for nodebox drawtype')
assert(not pcall(api.get_node_boxes,'unknown',at(7,2,2)),
 'unknown box query kinds must be rejected')
print('LUA ENGINE CONNECTED LEVELED WALLMOUNTED PASS')
