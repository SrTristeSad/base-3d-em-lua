-- Executavel de demonstracao do novo motor Lua usando LÖVR apenas como GPU.
-- NAO carrega VoxeLibre nesta fase: o conjunto da API ainda e parcial.
local Runtime=require('core.runtime')
local Storage=require('core.storage')
local Worldgen=require('core.worldgen')
local Renderer=require('core.renderer')
local Physics=require('core.physics')
local engine=Runtime.new()
engine:installGlobals()
local api=engine.api
api.register_node('lua:grass',{description='Grass',groups={crumbly=1},
  light_source=0,tiles={'mcl_core_grass_block_top.png',
  'default_dirt.png','mcl_core_grass_block_side.png'}})
api.register_node('lua:dirt',{tiles={'default_dirt.png'},description='Dirt',groups={crumbly=3}})
api.register_node('lua:stone',{tiles={'default_stone.png'},description='Stone',groups={cracky=3}})
api.register_node('lua:wood',{tiles={'default_tree.png'},description='Wood',groups={choppy=2}})
api.register_node('lua:leaves',{tiles={'default_leaves.png'},description='Leaves',groups={snappy=3}})
api.register_node('lua:sand',{tiles={'default_sand.png'},description='Sand',groups={crumbly=3}})
api.register_node('lua:water',{drawtype='liquid',liquidtype='source',use_texture_alpha='blend',tiles={'mcl_core_water_source_animation.png'},description='Water',groups={water=1,liquid=1},
 walkable=false})
api.register_node('lua:glass',{description='Glass',drawtype='glasslike',
 use_texture_alpha='blend',walkable=true,tiles={'default_glass.png'}})
api.register_node('lua:lava',{description='Lava',drawtype='liquid',
 use_texture_alpha='blend',walkable=false,
 tiles={'mcl_core_lava_source_animation.png'}})
api.register_node('lua:ladder',{description='Ladder (experimental)',drawtype='plantlike',
 walkable=false,climbable=true,tiles={'default_wood.png'},groups={}})
api.register_node('lua:flower',{description='Flower',drawtype='plantlike',
 tiles={'flowers_dandelion_yellow.png'},walkable=false})
api.register_node('lua:coal_ore',{tiles={'mcl_core_coal_ore.png'},description='Coal Ore',groups={cracky=2}})
local generator=Worldgen.new(engine,{seed=42})
local camera={x=0,y=5,z=11,yaw=0,pitch=0}
local savepath='lua-engine-world.map'
local renderer
local character
-- The LÖVR demo is the session host. This object is NOT a complete Luanti
-- ObjectRef; it only supplies a stable local identity for the physics bridge.
local demo_player={get_player_name=function() return 'singleplayer' end}
-- Terrain is now constructed through the Lua VoxelManip buffer.
-- This is STILL a deliberately simple demo terrain, not Luanti mapgen.
local function createWorld()
 local vm=api.get_voxel_manip(
  {x=-12,y=-2,z=-12},{x=12,y=5,z=12})
 for x=-12,12 do for z=-12,12 do
  local h=math.floor(math.sin(x*.28)*1.2+math.cos(z*.25))
  for y=-2,h do
   vm:set_node_at({x=x,y=y,z=z},{
    name=y==h and 'lua:grass' or
      (y>=h-2 and 'lua:dirt' or 'lua:stone')})
  end
 end end
 for _,p in ipairs({{-5,3},{4,-3},{7,6}}) do
  for y=1,4 do
   vm:set_node_at({x=p[1],y=y,z=p[2]},{name='lua:wood'})
  end
 end
 vm:write_to_map()
 api.set_node({x=3,y=2,z=3},{name='lua:flower'})
 api.set_node({x=4,y=3,z=3},{name='lua:glass'})
 api.set_node({x=5,y=3,z=3},{name='lua:glass'})
 api.set_node({x=-4,y=2,z=5},{name='lua:lava'})
 -- Minimal demo fixtures for swimming and ladders; no new gameplay mods.
 for y=1,3 do
  api.set_node({x=-1,y=y,z=3},{name='lua:water'})
  api.set_node({x=7,y=y,z=3},{name='lua:ladder'})
 end
end
local function look()
 local dx=math.sin(camera.yaw)*math.cos(camera.pitch)
 local dy=math.sin(camera.pitch)
 local dz=-math.cos(camera.yaw)*math.cos(camera.pitch)
 return dx,dy,dz
end
local function target()
 local ox,oy,oz=camera.x,camera.y,camera.z
 local dx,dy,dz=look()
 local last,seen=nil,''
 for t=0,6,.05 do
  local p={x=math.floor(ox+dx*t+.5),
   y=math.floor(oy+dy*t+.5),
   z=math.floor(oz+dz*t+.5)}
  local k=p.x..','..p.y..','..p.z
  if k~=seen then
   seen=k
   if api.get_node(p).name~='air' then return p,last end
   last=p
  end
 end
 return nil
end
function lovr.load()
 local map=Storage.load(savepath,lovr.filesystem)
 if map then engine.map=map;engine.map.registry=engine.registry.items
 else createWorld() end
 renderer=Renderer.new(lovr.graphics)
 -- Feet start below the first-person eye; gravity handles spawn settling.
 character=Physics.new(api,{x=camera.x,y=camera.y-1.62,z=camera.z},
  {profile='luanti'})
 lovr.system.setMouseMode('relative')
end
function lovr.update(dt)
 dt=math.min(math.max(dt,0),.05)
 engine:step(dt)
 local down=lovr.system.isKeyDown
 local dx,dz=0,0
 if down('w','up') then dx=dx+math.sin(camera.yaw);dz=dz-math.cos(camera.yaw) end
 if down('s','down') then dx=dx-math.sin(camera.yaw);dz=dz+math.cos(camera.yaw) end
 if down('a','left') then dx=dx-math.cos(camera.yaw);dz=dz-math.sin(camera.yaw) end
 if down('d','right') then dx=dx+math.cos(camera.yaw);dz=dz+math.sin(camera.yaw) end
 engine:updatePlayerControls('singleplayer',{
  up=down('w','up'),down=down('s','down'),
  left=down('a','left'),right=down('d','right'),
  jump=down('space'),sneak=down('lctrl','rctrl'),
  aux1=down('lshift','rshift')
 })
 character:update(dt,{
  x=dx,z=dz,
  jump=down('space'),
  sprint=down('lshift','rshift'),
  sneak=down('lctrl','rctrl')
 })
 local eye=character:eye()
 camera.x,camera.y,camera.z=eye.x,eye.y,eye.z
end
function lovr.mousemoved(x,y,dx,dy)
 camera.yaw=camera.y+dx*.002
 camera.pitch=math.max(-1.5,math.min(1.5,camera.pitch-dy*.002))
end
function lovr.mousepressed(x,y,button)
 local hit,previous=target()
 if button==1 and hit then api.dig_node(hit)
 elseif button==2 and previous and
   api.get_node(previous).name=='air' then
  api.place_node(previous,{name='lua:stone'})
 end
end
function lovr.keypressed(key)
 if key=='f7' then
  local cx=math.floor(camera.x/16)
  local cz=math.floor(camera.z/16)
  local ok,generated,writes=pcall(generator.generate,generator,cx,cz)
  if not ok then print('chunk generation failed:',generated)
  else print('chunk',cx,cz,generated and 'generated' or 'already generated',writes) end
 elseif key=='f6' then
  local ok,err=Storage.save(engine.map,savepath,lovr.filesystem)
  if not ok then print('save failed',err) end
 elseif key=='escape' then
  lovr.system.setMouseMode('normal')
 end
end
function lovr.quit()
 if engine.api.get_player_by_name('singleplayer') then
  local left,leave_err=pcall(engine.disconnectPlayer,engine,'singleplayer')
  if not left then print('player disconnect callback failed:',leave_err) end
 end
 local ok,err=pcall(engine.shutdown,engine)
 if not ok then print('shutdown callback failed:',err) end
 if lovr.filesystem then Storage.save(engine.map,savepath,lovr.filesystem) end
end
function lovr.draw(pass)
 pass:setClear(.52,.72,.91,1)
 local dx,dy,dz=look()
 pass:setViewPose(1,lovr.math.newMat4():lookAt(
  vec3(camera.x,camera.y,camera.z),
  vec3(camera.x+dx,camera.y+dy,camera.z+dz)),true)
 pass:setProjection('perspective',math.rad(75))
 -- GPU draws batched exposed faces, not one box for every saved node.
 renderer:draw(pass,engine.map,engine.registry.nodes,camera,20)
end
