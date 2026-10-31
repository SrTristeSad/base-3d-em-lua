-- Executavel de demonstracao do novo motor Lua usando LÖVR apenas como GPU.
-- NAO carrega VoxeLibre nesta fase: o conjunto da API ainda e parcial.
local Runtime=require('core.runtime')
local Storage=require('core.storage')
local engine=Runtime.new()
engine:installGlobals()
local api=engine.api
api.register_node('lua:grass',{description='Grass',groups={crumbly=1},
  light_source=0})
api.register_node('lua:dirt',{description='Dirt',groups={crumbly=3}})
api.register_node('lua:stone',{description='Stone',groups={cracky=3}})
api.register_node('lua:wood',{description='Wood',groups={choppy=2}})
local palette={
 ['lua:grass']={.35,.66,.27},
 ['lua:dirt']={.47,.31,.19},
 ['lua:stone']={.48,.49,.51},
 ['lua:wood']={.65,.46,.24}
}
local camera={x=0,y=5,z=11,yaw=0,pitch=0}
local savepath='lua-engine-world.map'
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
 if map then engine.map=map else createWorld() end
 lovr.system.setMouseMode('relative')
end
function lovr.update(dt)
 dt=math.min(math.max(dt,0),.05)
 engine:step(dt)
 local down=lovr.system.isKeyDown
 local dx,dz=0,0
 local speed=down('lshift','rshift') and 12 or 6
 if down('w','up') then dx=dx+math.sin(camera.yaw);dz=dz-math.cos(camera.yaw) end
 if down('s','down') then dx=dx-math.sin(camera.yaw);dz=dz+math.cos(camera.yaw) end
 if down('a','left') then dx=dx-math.cos(camera.yaw);dz=dz-math.sin(camera.yaw) end
 if down('d','right') then dx=dx+math.cos(camera.yaw);dz=dz+math.sin(camera.yaw) end
 local len=math.sqrt(dx*dx+dz*dz)
 if len>0 then
  camera.x=camera.x+dx/len*speed*dt
  camera.z=camera.z+dz/len*speed*dt
 end
 if down('space') then camera.y=camera.y+speed*dt end
 if down('lctrl','rctrl') then camera.y=camera.y-speed*dt end
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
 if key=='f6' then
  local ok,err=Storage.save(engine.map,savepath,lovr.filesystem)
  if not ok then print('save failed',err) end
 elseif key=='escape' then
  lovr.system.setMouseMode('normal')
 end
end
function lovr.quit()
 if lovr.filesystem then Storage.save(engine.map,savepath,lovr.filesystem) end
end
function lovr.draw(pass)
 pass:setClear(.52,.72,.91,1)
 local dx,dy,dz=look()
 pass:setViewPose(1,lovr.math.newMat4():lookAt(
  vec3(camera.x,camera.y,camera.z),
  vec3(camera.x+dx,camera.y+dy,camera.z+dz)),true)
 pass:setProjection('perspective',math.rad(75))
 pass:setColor(1,1,1)
 for k,node in pairs(engine.map.nodes) do
  local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  x,y,z=tonumber(x),tonumber(y),tonumber(z)
  if math.abs(x-camera.x)<20 and math.abs(y-camera.y)<12 and
    math.abs(z-camera.z)<20 then
   local c=palette[node.name] or {1,.1,1}
   pass:setColor(c[1],c[2],c[3])
   pass:box(x,y,z,1,1,1)
  end
 end
end
