-- Phase 74: actual LÖVR-compatible surface vertex colors respond to
-- generated sunlight, artificial lamps and neighbor mapblock edits.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Mesher=require('core.mesher')
local Renderer=require('core.renderer')
local Lighting=require('core.lighting')
local rt=Runtime.new()
local api=rt.api
local function p(x,y,z) return {x=x,y=y,z=z} end
local function near(a,b)
 return math.abs(a-b)<1e-6
end
api.register_node('lightmesh:stone',{tiles={'default_stone.png'}})
api.register_node('lightmesh:torch',{light_source=14,drawtype='torchlike',
 paramtype='light',walkable=false})
local map=rt.map
map.generatedChunks['0,0']=42
-- A surface in a generated column must be bright under direct midday sun.
map:set_node(p(15,1,15),{name='lightmesh:stone'})
local day=Mesher.build(map,rt.registry.nodes,0,0,0,rt.lighting,.5)
local night=Mesher.build(map,rt.registry.nodes,0,0,0,rt.lighting,0)
assert(#day==36 and #night==36)
assert(near(day[1][9],1),'upward sunlit vertex should be full brightness')
assert(night[1][9]<day[1][9] and night[1][9]>.16,
 'night sunlight must dim the top face without becoming fully black')
assert(near(day[1][9],day[1][10]) and
 near(day[1][10],day[1][11]),'vertex color channels must match')
assert(near(day[1][12],1),'opaque mesh must preserve alpha')
-- Unlit opt-out callers retain the Phase 69 geometry/color contract.
local old=Mesher.build(map,rt.registry.nodes,0,0,0)
assert(near(old[1][9],1) and near(old[7][9],.58))
-- With no registered emitter, even thousands of ambient samples should
-- not trigger any BFS traversal or grow a cache without a limit.
assert(rt.lighting.source_blocks~=nil)
assert(next(rt.lighting.source_blocks)==nil)
assert(rt.lighting.count<=4096)
local uploads,releases=0,0
local gfx={
 newBuffer=function(_,vertices)
  uploads=uploads+1
  return {vertices=vertices,release=function() releases=releases+1 end}
 end,
 newTexture=function(name)
  assert(name=='visual/atlas.png')
  return {name=name}
 end
}
local pass={
 setSampler=function(_,mode) assert(mode=='nearest') end,
 setMaterial=function()end,
 setColor=function(_,r,g,b,a)
  assert(r==1 and g==1 and b==1 and a==1)
 end,
 mesh=function(_,buffer) assert(buffer and buffer.vertices) end
}
local renderer=Renderer.new(gfx)
local camera=p(15,2,15)
renderer:draw(pass,map,rt.registry.nodes,camera,1,rt.lighting,0)
local first=renderer.cache['0,0,0']
assert(first and first.buffer and near(first.buffer.vertices[1][9],
 night[1][9]))
local a=uploads
renderer:draw(pass,map,rt.registry.nodes,camera,1,rt.lighting,0)
assert(uploads==a,'unchanged lighting must reuse GPU buffers')
renderer:draw(pass,map,rt.registry.nodes,camera,1,rt.lighting,.5)
assert(uploads>a,'daylight change must refresh mesh color')
a=uploads
renderer:draw(pass,map,rt.registry.nodes,camera,1,rt.lighting,.5)
assert(uploads==a,'steady daytime lighting must stay cached')
-- Torches near a mapblock corner must illuminate its faces even when
-- source and affected mesh are in DIAGONALLY adjacent mapblocks.
local diag=p(16,2,16)
local before=Mesher.fingerprint(map,0,0,0)
local before_lit=Mesher.fingerprint(map,0,0,0,true)
map:set_node(diag,{name='lightmesh:torch'})
assert(Mesher.fingerprint(map,0,0,0)==before,
 'legacy geometry fingerprint must remain unchanged')
assert(Mesher.fingerprint(map,0,0,0,true)~=before_lit,
 'lit fingerprint must include all 26 neighboring mapblocks')
local lit=Mesher.build(map,rt.registry.nodes,0,0,0,rt.lighting,0)
assert(lit[1][9]>night[1][9],
 'diagonal torch must increase the exposed face light at night')
renderer:draw(pass,map,rt.registry.nodes,camera,1,rt.lighting,0)
local after=renderer.cache['0,0,0']
assert(after.buffer~=first.buffer,
 'GPU upload must invalidate for light changes across diagonal boundary')
assert(near(after.buffer.vertices[1][9],lit[1][9]))
-- Changing a definition's light_source must update the same visible face
-- without moving a node or modifying any of its geometry revisions.
local unchanged=Mesher.fingerprint(map,0,0,0,true)
api.override_item('lightmesh:torch',{light_source=3})
assert(Mesher.fingerprint(map,0,0,0,true)==unchanged)
renderer:draw(pass,map,rt.registry.nodes,camera,1,rt.lighting,0)
assert(renderer.cache['0,0,0'].light_registry_revision==
 rt.light_registry_revision)
assert(renderer.cache['0,0,0'].buffer.vertices[1][9]<
 after.buffer.vertices[1][9], 'definition overrides must re-upload vertex lighting')
-- Keep the explicit unlit rendering path intact in both renderer and mesher.
local before_unlit=uploads
renderer:draw(pass,map,rt.registry.nodes,camera,1)
assert(uploads>before_unlit,'switching lit to unlit must refresh buffers once')
local no_lights=uploads
renderer:draw(pass,map,rt.registry.nodes,camera,1)
assert(uploads==no_lights,'unlit rendering must preserve original GPU cache')
assert(releases>0,'obsolete GPU buffers must be released')
print('LUA ENGINE LIGHT-AWARE GPU MESHER AND DIAGONAL CACHE PASS')
