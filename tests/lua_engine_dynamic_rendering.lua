-- Phase 32: static + moving voxel rendering in a fake LÖVR Pass.
-- No GPU or platform-specific libraries needed under Lua 5.4 and LuaJIT.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Mesher=require('core.mesher')
local Atlas=require('core.atlas')
local Renderer=require('core.renderer')
local rt=Runtime.new({item_physics=false})
local api=rt.api
local function p(x,y,z)return {x=x,y=y,z=z}end
api.register_node('test:stone',{tiles={'default_stone.png'}})
api.register_node('test:sand',{tiles={'default_sand.png'},
 groups={falling_node=1}})
api.register_node('test:slab',{drawtype='nodebox',paramtype2='facedir',
 node_box={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}},
 tiles={'default_wood.png'}})
api.register_craftitem('test:gem',{inventory_image='default_wood.png'})
local sandnode={name='test:sand',param2=0}
local isolated,metrics=Mesher.single_node(sandnode,rt.registry.nodes)
assert(#isolated==36 and metrics.faces==6 and metrics.cubes==1,
 'a moving cube needs all 6 faces even if its original location is occupied')
local u,v=Atlas.uv('default_sand.png')
assert(math.abs(isolated[1][7]-u)<1e-6 and
 math.abs(isolated[1][8]-v)>1e-6,'moving nodes use the original atlas')
local half=Mesher.single_node({name='test:sand'},rt.registry.nodes,.5)
assert(#half==36 and math.abs(half[1][2])==.25)
local slab=Mesher.single_node({name='test:slab',param2=1},
 rt.registry.nodes)
assert(#slab==36 and slab[1][2]~=isolated[1][2],
 'isolated nodeboxes retain actual geometry and facedir orientation')
local icon=Mesher.item_cube('default_wood.png',.32)
assert(#icon==36)
for _,vertex in ipairs(icon) do
 assert(math.abs(vertex[1])<=.160001 and
  math.abs(vertex[2])<=.160001 and
  math.abs(vertex[3])<=.160001)
end
assert(not pcall(Mesher.single_node,{name='test:sand'},
 rt.registry.nodes,0),'nonpositive model scale must be rejected')

local uploads,releases=0,0
local graphics={
 newBuffer=function(format,vertices)
  assert(#format==4 and #vertices>0 and #vertices%6==0)
  uploads=uploads+1
  local buffer={vertices=vertices,serial=uploads}
  function buffer:release()
   assert(not self.released,'GPU buffer released twice')
   self.released=true
   releases=releases+1
  end
  return buffer
 end,
 newTexture=function(file)
  assert(file=='visual/atlas.png')
  return {name=file}
 end,
}
local calls={}
local pass={
 mesh=function(_,buffer,x,y,z)
  assert(buffer and not buffer.released)
  calls[#calls+1]={buffer=buffer,x=x,y=y,z=z}
 end,
 setSampler=function(_,mode) assert(mode=='nearest') end,
 setMaterial=function(_,texture)
  assert(not texture or texture.name=='visual/atlas.png')
 end,
 setColor=function(_,r,g,b,a) assert(r==1 and g==1 and b==1 and a==1) end,
}
local renderer=Renderer.new(graphics)
local camera=p(0,3,0)
api.set_node(p(0,0,0),{name='test:stone'})
api.set_node(p(0,8,0),{name='test:sand'})
local ok=api.spawn_falling_node(p(0,8,0))
assert(ok and api.get_node(p(0,8,0)).name=='air')
local item=api.add_item(p(2,2,0),'test:gem')
assert(item)
renderer:draw(pass,rt.map,rt.registry.nodes,camera,1)
local static_uploads=uploads
calls={}
renderer:draw_dynamic(pass,rt,camera,20)
assert(#calls==2 and renderer.dynamic_drawcalls==2)
assert(uploads==static_uploads+2 and renderer.dynamic_rebuilt==2)
local fallcall,dropcall=calls[1],calls[2]
assert(fallcall.x==0 and fallcall.y==8 and fallcall.z==0)
assert(dropcall.x==2 and math.abs(dropcall.y-2.15)<.0001)
assert(#fallcall.buffer.vertices==36 and #dropcall.buffer.vertices==36)
local original_sand_buffer=fallcall.buffer
local item_buffer=dropcall.buffer

calls={}
renderer:draw(pass,rt.map,rt.registry.nodes,camera,1)
-- Static map draw calls are separate from the two dynamic objects.
calls={}
renderer:draw_dynamic(pass,rt,camera,20)
assert(#calls==2 and uploads==static_uploads+2,
 'moving objects must reuse GPU vertex buffers across frames')
assert(calls[1].buffer==original_sand_buffer and
 calls[2].buffer==item_buffer)

rt:step(.2)
calls={}
renderer:draw_dynamic(pass,rt,camera,20)
assert(#calls==2 and calls[1].y<8 and
 calls[1].buffer==original_sand_buffer,
 'moving object translation must update without regenerating geometry')

calls={}
renderer:draw_dynamic(pass,rt,p(100,0,100),3)
assert(#calls==0 and renderer.dynamic_drawcalls==0,
 'objects outside radius must not be drawn')

-- Falling object lands as a static voxel, without a duplicate moving mesh.
rt:step(2)
assert(#api.get_falling_nodes()==0)
assert(api.get_node(p(0,1,0)).name=='test:sand')
calls={}
renderer:draw(pass,rt.map,rt.registry.nodes,camera,1)
renderer:draw_dynamic(pass,rt,camera,20)
assert(renderer.dynamic_drawcalls==1)
assert(#calls>=2 and calls[#calls].buffer==item_buffer)

item:remove()
calls={}
renderer:draw_dynamic(pass,rt,camera,20)
assert(#calls==0)
local dynamic_releases_before=releases
renderer:reset()
assert(releases>=dynamic_releases_before+2 and
 next(renderer.dynamic_cache)==nil and next(renderer.cache)==nil,
 'reset must release static and dynamic GPU buffers')

-- Registry switches invalidate cached models to avoid mismatched UVs.
api.set_node(p(4,8,0),{name='test:slab',param2=1})
assert(api.spawn_falling_node(p(4,8,0)))
renderer:draw_dynamic(pass,rt,camera,20)
assert(renderer.dynamic_drawcalls==1)
assert(#calls==1 and #calls[1].buffer.vertices==36)
print('LUA ENGINE PHASE 32 DYNAMIC RENDERING PASS')
