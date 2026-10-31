local World = require('src.world')
local Mesher = require('src.mesher')
local Textures = require('src.textures')
local Player = require('src.player')
local Avatar = require('src.avatar')
local UI = require('src.ui')
local Creepers = require('src.creepers')
local Classic = require('src.classic')
local Creatures = require('src.creatures')
local TNT = require('src.tnt')

local world,mesher,player,avatar,tiles,creepers,classic,creatures,tnt
local autosave=0
local state = 'title'
local previous = 'title'
local settings = {
  fov=75,sensitivity=.003,sensitivityLabel='MEDIA',
  distance=2,fullscreen=false
}
local fovs={60,75,90}
local sens={{.0015,'BAIXA'},{.003,'MEDIA'},{.005,'ALTA'}}
local function cycle(value,options)
  for i,v in ipairs(options) do
    if value==v then return options[i%#options+1] end
  end
  return options[1]
end
local function saveSettings()
  lovr.filesystem.write('settings.ini',
    ('fov=%d\nsensitivity=%.4f\ndistance=%d\nfullscreen=%d\n'):format(
    settings.fov,settings.sensitivity,settings.distance,settings.fullscreen and 1 or 0))
end
local function loadSettings()
  local str=lovr.filesystem.read('settings.ini')
  if not str then return end
  local props={}
  for key,value in str:gmatch('([%a]+)=([%d%.]+)') do props[key]=tonumber(value) end
  for _,n in ipairs(fovs) do if n==props.fov then settings.fov=n end end
  for _,s in ipairs(sens) do
    if math.abs(s[1]-(props.sensitivity or 0))<.0001 then
      settings.sensitivity,settings.sensitivityLabel=s[1],s[2]
    end
  end
  if props.distance and props.distance>=1 and props.distance<=3
    and props.distance%1==0 then settings.distance=props.distance end
  settings.fullscreen=props.fullscreen==1
end

local function setState(next)
  state=next
  lovr.system.setMouseMode(next=='playing' and 'relative' or 'normal')
end
local function saveWorld()
  if world and player then
    local ok,err=world:save(player,classic)
    if not ok then print('Nao foi possivel salvar o mundo:',err) end
  end
end
local function action(a)
  if a=='play' or a=='resume' then
    setState('playing')
  elseif a=='pause' then
    setState('pause')
  elseif a=='mode' then
    local next=classic.mode=='survival' and 'creative' or 'survival'
    classic=Classic.new(next,classic.items,classic.score)
    -- Criativo tem vida plena, alem de blocos ilimitados e sem inimigos.
    player.health=player.maxHealth
    player.invulnerable=1
  elseif a=='respawn' then
    player:respawn(world)
    setState('playing')
  elseif a=='quit' then
    saveWorld()
    lovr.event.quit()
  elseif a=='settings' then
    previous=state
    setState('settings')
  elseif a=='back' then
    setState(previous)
  elseif a=='title' then
    saveWorld()
    setState('title')
  elseif a=='save' then
    saveWorld()
  elseif a=='fov' then
    settings.fov=cycle(settings.fov,fovs)
    saveSettings()
  elseif a=='sensitivity' then
    local index=1
    for i,v in ipairs(sens) do if v[1]==settings.sensitivity then index=i end end
    local value=sens[index%#sens+1]
    settings.sensitivity,settings.sensitivityLabel=value[1],value[2]
    saveSettings()
  elseif a=='distance' then
    settings.distance=settings.distance%3+1
    saveSettings()
  elseif a=='fullscreen' then
    settings.fullscreen=not settings.fullscreen
    lovr.system.setWindowFullscreen(settings.fullscreen)
    saveSettings()
  end
end

function lovr.load()
  loadSettings()
  if settings.fullscreen then lovr.system.setWindowFullscreen(true) end
  lovr.graphics.setBackgroundColor(.49,.72,.91)
  tiles=Textures.load()
  world=World.new()
  mesher=Mesher.new(world,tiles,Textures.faces)
  mesher:sync()
  player=Player.new(world)
  classic=Classic.new(world.savedMode,world.savedItems,world.savedScore)
  creepers=Creepers.new(world)
  creatures=Creatures.new(world)
  tnt=TNT.new(world)
  avatar=Avatar.new()
  setState('title')
end

function lovr.update(dt)
  if state=='playing' then
    player:update(dt,world)
    creepers:update(dt,player,classic)
    creatures:update(dt,player,classic)
    tnt:update(dt,player,classic)
    mesher:sync()
    if player.health<=0 then setState('dead') end
    autosave=autosave+dt
    if autosave>=45 then
      autosave=0
      saveWorld()
    end
  end
end

function lovr.draw(pass)
  local cx,cy,cz,tx,ty,tz
  if state=='title' then
    cx,cy,cz,tx,ty,tz=13,13,17,0,3,0
  else
    cx,cy,cz,tx,ty,tz=player:camera()
  end
  pass:setViewPose(1,lovr.math.newMat4():lookAt(
    vec3(cx,cy,cz),vec3(tx,ty,tz)),true)
  pass:setProjection('perspective',math.rad(settings.fov))
  pass:setSampler('nearest')
  pass:setColor(1,1,1)
  pass:setViewCull(true)
  mesher:draw(pass,cx,cz,settings.distance)
  if classic.mode=='survival' then
    creepers:draw(pass,cx,cz,settings.distance*16+20)
    creatures:draw(pass,cx,cz,settings.distance*16+20)
    tnt:draw(pass,cx,cz,settings.distance*16+20)
  end
  if player.third and state~='title' then avatar:draw(pass,player) end
  local hit
  if state=='playing' then
    hit=player:raycast(world,6)
    if hit then
      pass:setMaterial()
      pass:setColor(1,.9,.45)
      pass:box(hit.x,hit.y,hit.z,1.015,1.015,1.015,0,0,1,0,'line')
    end
  end
  pass:setViewCull(false)
  UI.draw(pass,state,settings,player,hit,Textures.hotbar,Textures.labels,creepers,classic,creatures)
end

function lovr.mousemoved(x,y,dx,dy)
  if state~='playing' then return end
  player.yaw=player.y+dx*settings.sensitivity
  player.pitch=math.max(-1.50,math.min(1.50,player.pitch-dy*settings.sensitivity))
end

function lovr.mousepressed(x,y,button)
  if state=='playing' then
    if button==1 then
      local attacked=false
      if classic.mode=='survival' then
        attacked=creepers:hit(player,1,classic)
          or creatures:hit(player,classic)
      end
      if not attacked then
        player:edit(world,button,Textures.hotbar,classic,tnt)
      end
    elseif button==2 then
      if not tnt:defuse(player,classic) then
        player:edit(world,button,Textures.hotbar,classic,tnt)
      end
    end
  else
    local w,h=lovr.system.getWindowDimensions()
    local a=UI.click(state,settings,x,y,w,h,classic)
    if a then action(a) end
  end
end

function lovr.wheelmoved(dx,dy)
  if state=='playing' and dy~=0 then
    player.selected=(player.selected-1-(dy>0 and 1 or -1))%#Textures.hotbar+1
  end
end

function lovr.keypressed(key)
  if key=='escape' then
    if state=='playing' then action('pause')
    elseif state=='pause' then action('resume')
    elseif state=='settings' then action('back')
    end
    return
  end
  if state~='playing' then
    if key=='return' and state=='title' then action('play')
    elseif key=='r' and state=='dead' then action('respawn') end
    return
  end
  if key=='tab' then
    Textures.nextPage(1)
    player.selected=1
  elseif key=='e' then
    classic:eat(player)
  elseif key=='f5' then
    player.third=not player.third
  elseif key=='f6' then
    saveWorld()
  else
    local slot=tonumber(key)
    if slot and slot>=1 and slot<=#Textures.hotbar then player.selected=slot end
  end
end

function lovr.focus(focused)
  if not focused and state=='playing' then setState('pause') end
end

function lovr.quit()
  saveWorld()
  saveSettings()
end
