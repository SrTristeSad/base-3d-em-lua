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
local Worlds = require('src.worlds')
local Camera = require('src.camera')
local MobSkins = require('src.mob_skins')

local world,mesher,player,avatar,tiles,creepers,classic,creatures,tnt,mobSkins
local ignoreMouseMove=false
local autosave=0
local showStats=false
local selectedWorld=nil
local menu={name='',seed='',image='',mode='survival',
  focus=nil,notice='',selected=nil,entries={},page=1,images={},imagePage=1}
local state = 'title'
local previous = 'title'
local settings = {
  fov=75,sensitivity=.002,sensitivityLabel='MEDIA',
  distance=1,fullscreen=false,invertX=false,invertY=false
}
local fovs={60,75,90}
local sens={{.0012,'BAIXA'},{.002,'MEDIA'},{.0032,'ALTA'},{.0045,'MUITO ALTA'}}
local function cycle(value,options)
  for i,v in ipairs(options) do
    if value==v then return options[i%#options+1] end
  end
  return options[1]
end
local function saveSettings()
  lovr.filesystem.write('settings.ini',
    ('fov=%d\nsensitivity=%.4f\ndistance=%d\nfullscreen=%d\ninvertX=%d\ninvertY=%d\n'):format(
    settings.fov,settings.sensitivity,settings.distance,
    settings.fullscreen and 1 or 0,
    settings.invertX and 1 or 0,settings.invertY and 1 or 0))
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
  settings.invertX=props.invertX==1
  settings.invertY=props.invertY==1
end

local function setState(next)
  ignoreMouseMove=next=='playing'
  state=next
  lovr.system.setMouseMode(next=='playing' and 'relative' or 'normal')
end
local function saveWorld()
  if selectedWorld and world and player then
    local ok,err=world:save(player,classic)
    if not ok then print('Nao foi possivel salvar o mundo:',err) end
  end
end
local function releaseSession()
 if mesher then
  for _,chunk in pairs(mesher.chunks) do
   for _,mesh in ipairs(chunk.meshes) do mesh:release() end
  end
 end
end
local function useWorld(options,entry)
 releaseSession()
 selectedWorld=entry
 world=World.new(options)
 player=Player.new(world)
 classic=Classic.new(world.savedMode or (entry and entry.mode) or 'creative',
   lovr.filesystem.isFile(world.SAVE) and world.savedItems or nil,
   world.savedScore)
 mesher=Mesher.new(world,tiles,Textures.faces)
 mesher:sync(player.x,player.y,player.z,settings.distance,6)
 creepers=Creepers.new(world)
 creatures=Creatures.new(world)
 tnt=TNT.new(world)
 menu.selected=entry
 autosave=0
end
local function refreshWorlds()
 menu.entries=Worlds.list()
end
local function openWorldById(id)
 refreshWorlds()
 for _,entry in ipairs(menu.entries) do
  if entry.id==id then
   local opts,err=Worlds.open(entry)
   if not opts then menu.notice=err or 'Nao foi possivel abrir mundo';return false end
   saveWorld()
   useWorld(opts,entry)
   menu.notice=''
   return true
  end
 end
 menu.notice='Mundo nao encontrado'
 return false
end

local function action(a)
  if a=='play' or a=='resume' then
    if selectedWorld then setState('playing') else setState('create') end
  elseif a=='create' then
    menu.name='';menu.seed='';menu.image='';menu.focus=nil
    menu.notice=''
    setState('create')
  elseif a=='create_world' then
    menu.focus=nil
    local options,entry=Worlds.create(menu.name,menu.seed,menu.image,menu.mode)
    if not options then
      menu.notice=entry or 'Erro ao criar mundo'
    else
      saveWorld()
      useWorld(options,entry)
      refreshWorlds()
      menu.notice=''
      setState('playing')
    end
  elseif a=='images' then
    lovr.filesystem.createDirectory('maps')
    local files=lovr.filesystem.getDirectoryItems('maps') or {}
    menu.images={}
    for _,filename in ipairs(files) do
      if filename:lower():match('%.png$') or filename:lower():match('%.jpe?g$') then
        if lovr.filesystem.isFile('maps/'..filename) then
          menu.images[#menu.images+1]=filename
        end
      end
    end
    table.sort(menu.images)
    menu.imagePage=1
    menu.notice=#menu.images==0 and
      'Nenhum PNG/JPG na pasta maps. Pode testar a imagem exemplo.' or ''
    setState('imagelist')
  elseif a=='imageprev' then
    menu.imagePage=math.max(1,menu.imagePage-1)
  elseif a=='imagenext' then
    menu.imagePage=menu.imagePage+1
  elseif a=='backcreate' then
    menu.notice=''
    setState('create')
  elseif a:sub(1,10)=='pickimage:' then
    local filename=a:sub(11)
    for _,available in ipairs(menu.images) do
      if available==filename then
        menu.image='maps/'..available
        menu.notice='Imagem selecionada: '..available
        setState('create')
        break
      end
    end
  elseif a=='demoimage' then
    menu.image='assets/worlds/demo.png'
    menu.notice='Imagem exemplo carregada. A seed tambem afeta o terreno.'
  elseif a=='newmode' then
    menu.mode=menu.mode=='survival' and 'creative' or 'survival'
  elseif a=='worldlist' then
    refreshWorlds()
    menu.notice=''
    menu.page=1
    setState('worldlist')
  elseif a=='next' then
    menu.page=menu.page+1
  elseif a=='previous' then
    menu.page=math.max(1,menu.page-1)
  elseif a:sub(1,6)=='field:' then
    local field=a:sub(7)
    if field=='name' or field=='seed' or field=='image' then
      menu.focus=field
      menu.notice=''
    end
  elseif a:sub(1,5)=='load:' then
    if openWorldById(tonumber(a:sub(6))) then setState('playing') end
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
    menu.focus=nil
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
  elseif a=='invertx' then
    settings.invertX=not settings.invertX
    saveSettings()
  elseif a=='inverty' then
    settings.invertY=not settings.invertY
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
  avatar=Avatar.new()
  mobSkins=MobSkins.new()
  refreshWorlds()
  if #menu.entries>0 then
    local item=menu.entries[#menu.entries]
    local options,err=Worlds.open(item)
    if options then
      useWorld(options,item)
    else
      menu.notice=err or 'O mundo selecionado nao abriu'
    end
  end
  if not world then
    useWorld({seed='preview',savePath='worlds/__preview__.sav'},nil)
    classic.mode='creative'
  end
  setState('title')
end

function lovr.update(dt)
  if state=='playing' then
    player:update(dt,world)
    creepers:update(dt,player,classic)
    creatures:update(dt,player,classic)
    tnt:update(dt,player,classic)
    mesher:sync(player.x,player.y,player.z,settings.distance,3)
    if player.health<=0 then setState('dead') end
    autosave=autosave+dt
    if autosave>=45 then
      autosave=0
      saveWorld()
    end
  elseif state=='title' or state=='create' or state=='worldlist'
      or state=='imagelist' or state=='settings' then
    -- Preenche o panorama atras do menu, sem simular inimigos.
    mesher:sync(player.x,player.y,player.z,settings.distance,2)
  end
end

function lovr.draw(pass)
  local cx,cy,cz,tx,ty,tz
  if state=='title' or state=='create' or state=='worldlist'
      or state=='imagelist' or state=='settings' then
    cx,cy,cz,tx,ty,tz=player.x+13,player.y+10,player.z+17,
      player.x,player.y,player.z
  else
    cx,cy,cz,tx,ty,tz=player:camera(world)
  end
  pass:setViewPose(1,lovr.math.newMat4():lookAt(
    vec3(cx,cy,cz),vec3(tx,ty,tz)),true)
  pass:setProjection('perspective',math.rad(settings.fov))
  pass:setSampler('nearest')
  pass:setColor(1,1,1)
  pass:setViewCull(true)
  mesher:draw(pass)
  if classic.mode=='survival' then
    creepers:draw(pass,cx,cz,settings.distance*16+20,mobSkins)
    creatures:draw(pass,cx,cz,settings.distance*16+20,mobSkins)
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
  UI.draw(pass,state,settings,player,hit,Textures.hotbar,Textures.labels,creepers,classic,creatures,
    mesher,showStats,menu)
end

function lovr.mousemoved(x,y,dx,dy)
  if state~='playing' then return end
  if ignoreMouseMove then
    ignoreMouseMove=false
    return
  end
  player.yaw,player.pitch=Camera.look(player.yaw,player.pitch,
    settings.invertX and -dx or dx,dy,settings.sensitivity,settings.invertY)
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
    local a=UI.click(state,settings,x,y,w,h,classic,menu)
    if a then action(a) end
  end
end

function lovr.wheelmoved(dx,dy)
  if state=='playing' and dy~=0 then
    player.selected=(player.selected-1-(dy>0 and 1 or -1))%#Textures.hotbar+1
  end
end

function lovr.textinput(text)
 if state~='create' or not menu.focus then return end
 local maxLen=menu.focus=='image' and 110 or 56
 if type(text)=='string' and #text<12 then
  local value=menu[menu.focus]..text:gsub('[\r\n|]','')
  menu[menu.focus]=value:sub(1,maxLen)
 end
end

function lovr.keypressed(key)
 if state=='create' and menu.focus then
  if key=='return' or key=='kpenter' then menu.focus=nil;return end
  if key=='backspace' then
   local value=menu[menu.focus]
   if utf8 and utf8.offset then
    local index=utf8.offset(value,-1)
    menu[menu.focus]=index and value:sub(1,index-1) or ''
   else menu[menu.focus]=value:sub(1,-2) end
   return
  elseif key=='tab' then
   local order={name='seed',seed='image',image='name'}
   menu.focus=order[menu.focus]
   return
  end
 end
 if key=='escape' then
    if state=='playing' then action('pause')
    elseif state=='pause' then action('resume')
    elseif state=='settings' then action('back')
    elseif state=='imagelist' then action('backcreate')
    elseif state=='create' or state=='worldlist' then action('title')
    end
    return
  end
  if state~='playing' then
    if key=='return' and state=='title' then action('play')
    elseif key=='r' and state=='dead' then action('respawn') end
    return
  end
  if key=='f3' then
    showStats=not showStats
  elseif key=='tab' then
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
  if focused then ignoreMouseMove=true end
end

function lovr.quit()
  saveWorld()
  saveSettings()
end
