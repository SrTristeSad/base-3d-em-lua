-- Pure-Lua geometry tests and a fake LÖVR 0.19 GPU surface.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Engine=require('core.runtime')
local Mesher=require('core.mesher')
local Atlas=require('core.atlas')
local Renderer=require('core.renderer')
local rt=Engine.new()
rt.api.register_node('test:stone',{tiles={'default_stone.png'}})
rt.api.register_node('test:grass',{tiles={
 'mcl_core_grass_block_top.png','default_dirt.png',
 {name='default_dirt.png^mcl_dirt_grass_shadow.png'}}})
rt.api.register_node('test:invisible',{drawtype='airlike'})
rt.api.register_node('test:leaves',{drawtype='allfaces',tiles={'default_leaves.png'}})
local map=rt.map
local pos=function(x,y,z)return {x=x,y=y,z=z}end
map:set_node(pos(0,0,0),{name='test:stone'})
local vertices,metrics=Mesher.build(map,rt.registry.nodes,0,0,0)
assert(metrics.cubes==1 and metrics.faces==6 and #vertices==36)
assert(#vertices==metrics.vertices)
-- The mesh carries normals, UVs and color without relying on GPU or C++.
for i=1,#vertices,6 do
 local v=vertices[i]
 assert(#v==12 and v[7]>=0 and v[7]<=1 and v[8]>=0 and v[8]<=1)
 local a,b,c=vertices[i],vertices[i+1],vertices[i+2]
 local u={b[1]-a[1],b[2]-a[2],b[3]-a[3]}
 local w={c[1]-a[1],c[2]-a[2],c[3]-a[3]}
 local cross={
  u[2]*w[3]-u[3]*w[2],
  u[3]*w[1]-u[1]*w[3],
  u[1]*w[2]-u[2]*w[1],
 }
 assert(cross[1]*v[4]+cross[2]*v[5]+cross[3]*v[6]>0,
  'face winding must point outward')
end
map:set_node(pos(1,0,0),{name='test:stone'})
vertices,metrics=Mesher.build(map,rt.registry.nodes,0,0,0)
assert(metrics.faces==10 and #vertices==60,'internal cube faces must be hidden')
map:set_node(pos(0,1,0),{name='test:invisible'})
vertices,metrics=Mesher.build(map,rt.registry.nodes,0,0,0)
assert(metrics.faces==10 and metrics.skipped==1,
 'airlike node must not create mesh or occlude cube')
map:set_node(pos(15,2,0),{name='test:stone'})
local a=Mesher.fingerprint(map,0,0,0)
local b=Mesher.fingerprint(map,1,0,0)
map:set_node(pos(16,2,0),{name='test:stone'})
assert(Mesher.fingerprint(map,0,0,0)~=a,
 'neighbor revisions must invalidate mapblock edge')
assert(Mesher.fingerprint(map,1,0,0)~=b)
local _,edge=Mesher.build(map,rt.registry.nodes,0,0,0)
assert(edge.faces==15,'shared chunk boundary face must be culled')
local _,other=Mesher.build(map,rt.registry.nodes,1,0,0)
assert(other.faces==5,'neighbor chunk must not draw shared face')
assert(Atlas.index('default_stone.png')==4)
assert(Atlas.index({name='default_dirt.png^overlay.png'})==3)
assert(Atlas.index('nonexistent.png')==1)
local grassmap=Engine.new().map
grassmap:set_node(pos(3,3,3),{name='test:grass'})
local grass=Mesher.build(grassmap,rt.registry.nodes,0,0,0)
local topu,topv=Atlas.uv('mcl_core_grass_block_top.png')
assert(math.abs(grass[1][7]-topu)<.001)
assert(math.abs(grass[1][8]-topv)>.001)
local uploads,releases,drawcalls=0,0,0
local graphics={
 newBuffer=function(format,values)
  assert(#format==4 and format[1].name=='VertexPosition')
  assert(#values%6==0)
  uploads=uploads+1
  return {release=function() releases=releases+1 end}
 end,
 newTexture=function(filename)
  assert(filename=='visual/atlas.png')
  return {filename=filename}
 end,
}
local pass={
 mesh=function(_,buffer) assert(buffer);drawcalls=drawcalls+1 end,
 setSampler=function(_,mode) assert(mode=='nearest') end,
 setMaterial=function(_,material) end,
 setColor=function(_,r,g,b,alpha) assert(r==1 and alpha==1) end
}
local render=Renderer.new(graphics)
local camera={x=1,y=1,z=1}
render:draw(pass,map,rt.registry.nodes,camera,1)
assert(uploads>0 and drawcalls>0,'renderer must upload and draw faces')
local baseline=uploads
render:draw(pass,map,rt.registry.nodes,camera,1)
assert(uploads==baseline,'unchanged mapblocks must reuse GPU buffers')
map:remove_node(pos(0,0,0))
render:draw(pass,map,rt.registry.nodes,camera,1)
assert(uploads>baseline and releases>0,'node removal must refresh GPU buffers')
local replacement=Engine.new().map
render:draw(pass,replacement,rt.registry.nodes,camera,1)
assert(render.map==replacement,'newly loaded map must clear cache')
print('LUA ENGINE MESHING PASS')
