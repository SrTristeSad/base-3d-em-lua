-- Phase 70: exercise real Luanti 5.18 node API contracts, not only symbol names.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local rt=Runtime.new()
local api=rt.api
local sequence={}
local function record(tag,pos)
 sequence[#sequence+1]=tag..'@'..pos.x
end
api.register_node('audit:a',{
 description='A',groups={soil=1,ore=2},
 on_construct=function(p)
  record('construct_a',p)
  assert(api.get_meta(p):get_string('token')=='')
 end,
 on_destruct=function(p)
  record('destruct_a',p)
  assert(api.get_node(p).name=='audit:a')
 end,
 after_destruct=function(p,n)
  record('after_a',p)
  assert(n.name=='audit:a')
 end})
api.register_node('audit:b',{
 groups={soil=1,ore=1},
 on_construct=function(p) record('construct_b',p) end,
 on_destruct=function(p) record('destruct_b',p) end,
 after_destruct=function(p,n)
  record('after_b',p)
  assert(n.name=='audit:b')
 end})
api.register_alias('audit:alias','audit:a')
local p={x=-16,y=7,z=3}
assert(api.add_node(p,{name='audit:alias',param2=5}))
assert(api.get_node(p).name=='audit:a')
assert(sequence[1]=='construct_a@-16')
local ref=api.get_meta(p)
ref:set_string('token','secret')
api.get_node_timer(p):start(30)
-- swap_node changes the node and param2 only, not metadata or timers;
-- native swap_node does not trigger any destructor / constructor.
assert(api.swap_node(p,{name='audit:b',param2=7}))
assert(#sequence==1)
assert(api.get_meta(p):get_string('token')=='secret')
assert(api.get_node_timer(p):is_started())
assert(api.get_node(p).param2==7)
local q={x=-14,y=7,z=3}
local r={x=-13,y=7,z=3}
assert(api.bulk_swap_node({q,r},{name='audit:b',param2=2}))
assert(#sequence==1)
assert(api.get_node(q).name=='audit:b' and api.get_node(r).name=='audit:b')
-- Native setNode triggers the exact 3-stage callback sequence and
-- resets old metadata and timers without touching unrelated positions.
assert(api.set_node(p,{name='audit:a'}))
assert(#sequence==4)
assert(sequence[2]=='destruct_b@-16')
assert(sequence[3]=='after_b@-16')
assert(sequence[4]=='construct_a@-16')
assert(api.get_meta(p):get_string('token')=='')
assert(not api.get_node_timer(p):is_started())
assert(api.get_node(q).param2==2)
local old=#sequence
assert(api.bulk_set_node({q,r},{name='audit:a',param2=9}))
assert(#sequence==old+6)
assert(api.get_node(q).param2==9 and api.get_node(r).param2==9)
local old2=#sequence
-- Luanti's empty bulk operation still succeeds.
assert(api.bulk_set_node({}, {name='audit:b'}))
assert(api.bulk_swap_node({}, {name='audit:b'}))
assert(#sequence==old2)
-- A set_node call even when the name is identical invokes old/new hooks.
assert(api.set_node(p,{name='audit:a'}))
assert(#sequence==old2+3)
old2=#sequence
assert(api.remove_node(p))
assert(api.get_node(p).name=='air')
assert(sequence[old2+1]=='destruct_a@-16')
assert(sequence[old2+2]=='after_a@-16')
assert(#sequence==old2+2)
-- Direct place_node/dig_node must not run constructors twice after
-- moving their native hooks to the shared low-level API.
local placed,dug=0,0
api.register_on_placenode(function() placed=placed+1 end)
api.register_on_dignode(function() dug=dug+1 end)
old2=#sequence
assert(api.place_node(p,{name='audit:a'}))
assert(#sequence==old2+1 and placed==1)
assert(api.dig_node(p))
assert(dug==1 and #sequence==old2+3)
-- Filter lookup is based on registered groups, resolving aliases,
-- and returns both results and per-node counts, as native Luanti does.
local minp={x=-17,y=7,z=2}
local maxp={x=-11,y=7,z=4}
local found,counts=api.find_nodes_in_area(minp,maxp,'group:soil')
assert(type(counts)=='table')
assert(#found==2 and counts['audit:a']==2)
local byname=api.find_nodes_in_area(minp,maxp,'group:soil',true)
assert(type(byname['audit:a'])=='table' and #byname['audit:a']==2)
assert(byname['audit:b']==nil)
local alias,acount=api.find_nodes_in_area(minp,maxp,'audit:alias')
assert(#alias==2 and acount['audit:a']==2)
local inclusive,cnt=api.find_nodes_in_area(
 {x=-13,y=7,z=3},{x=-17,y=7,z=3},'group:ore')
assert(#inclusive==2 and cnt['audit:a']==2,
 'reversed area bounds must be accepted')
-- Only a node with real air directly above belongs to under_air.
api.set_node({x=-14,y=8,z=3},{name='audit:b'})
local under=api.find_nodes_in_area_under_air(minp,maxp,'group:soil')
assert(#under==1 and under[1].x==-13)
api.remove_node({x=-14,y=8,z=3})
under=api.find_nodes_in_area_under_air(minp,maxp,'group:soil')
assert(#under==2)
-- Near uses Chebyshev shells; excludes the origin by default.
local center={x=-14,y=7,z=3}
assert(api.find_node_near(center,0,'audit:a')==nil)
local at=api.find_node_near(center,0,'audit:a',true)
assert(at and at.x==-14)
local around=api.find_node_near(center,1,'group:soil')
assert(around and around.x==-13)
assert(api.find_node_near({x=20,y=20,z=20},1,'audit:a')==nil)
assert(not pcall(api.find_node_near,center,-1,'audit:a'))
assert(not pcall(api.find_node_near,center,65,'audit:a'))
assert(not pcall(api.bulk_set_node,'bad',{name='audit:a'}))
-- Mapblock collision index and geometry revisions remain consistent
-- after both ordinary and bulk node operations.
assert(rt.map.count==2)
assert(rt.map.revisions[rt.map:blockkey(q)]>0)
print('LUA ENGINE NATIVE NODE SEARCH, BULK SET AND LIFECYCLE PASS')
