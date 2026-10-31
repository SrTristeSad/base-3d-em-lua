local UI={}
local function rect(pass,x,y,w,h,r,g,b,a)
  pass:setColor(r,g,b,a or 1)
  pass:box(x,y,0,w,h,.001)
end
local function label(pass,text,x,y,scale,r,g,b)
  pass:setColor(r or 1,g or 1,b or 1)
  pass:text(text,x,y,-.005,scale or 19)
end
local function inside(b,x,y)
  return x>=b.x-b.w/2 and x<=b.x+b.w/2 and
    y>=b.y-b.h/2 and y<=b.y+b.h/2
end

function UI.buttons(state, settings, w, h, classic)
  local cx=w/2
  local b={}
  local function add(text,row,action)
    b[#b+1]={text=text,x=cx,y=h*.49+row*58,w=360,h=47,action=action}
  end
  if state=='title' then
    add('JOGAR',-1,'play')
    add('MODO: '..(classic and classic.mode=='creative' and 'CRIATIVO' or 'SOBREVIVENCIA'),0,'mode')
    add('CONFIGURACOES',1,'settings')
    add('SAIR',2,'quit')
  elseif state=='dead' then
    add('RENASCER',0,'respawn')
    add('MENU INICIAL',1,'title')
  elseif state=='pause' then
    add('CONTINUAR',-1,'resume')
    add('SALVAR MUNDO',0,'save')
    add('CONFIGURACOES',1,'settings')
    add('MENU INICIAL',2,'title')
  elseif state=='settings' then
    add('CAMPO DE VISAO: '..settings.fov..' graus',-2,'fov')
    add('MOUSE: '..settings.sensitivityLabel,-1,'sensitivity')
    add('DISTANCIA: '..settings.distance..' chunks',0,'distance')
    add('TELA CHEIA: '..(settings.fullscreen and 'SIM' or 'NAO'),1,'fullscreen')
    add('VOLTAR',2,'back')
  end
  return b
end

function UI.click(state,settings,x,y,w,h,classic)
  for _,b in ipairs(UI.buttons(state,settings,w,h,classic)) do
    if inside(b,x,y) then return b.action end
  end
end

function UI.draw(pass,state,settings,player,hit,hotbar,labels,creepers,classic,creatures)
  local w,h=pass:getDimensions()
  pass:setViewPose(1,lovr.math.newMat4())
  pass:setProjection('orthographic')
  pass:setDepthTest()
  pass:setDepthWrite(false)
  pass:setMaterial()
  if state=='playing' then
    rect(pass,w/2,h/2,3,20,.98,.99,1)
    rect(pass,w/2,h/2,20,3,.98,.99,1)
    rect(pass,w/2,h-52,8*69+24,67,.05,.07,.10,.84)
    for i,id in ipairs(hotbar) do
      local x=w/2+(i-4.5)*69
      local selected=player.selected==i
      rect(pass,x,h-52,62,55,
        selected and .93 or .16,selected and .77 or .22,
        selected and .34 or .27,selected and .95 or .87)
      rect(pass,x,h-52,55,48,.13,.16,.21)
      label(pass,i..'  '..(labels[id] or ('Bloco '..id)),x,h-58,11)
      if classic and classic.mode=='survival' then
        local count=classic:count(id) or 0
        label(pass,tostring(count),x,h-38,14,
          count>0 and .92 or .66,count>0 and .95 or .71,.86)
      end
    end
    label(pass,'WASD mover | Esq. atacar/minerar | Dir. construir/desarmar TNT | TAB pagina | E cogumelo',
      w/2,28,15,.9,.96,1)
    -- Vida inicial: dez coracoes. Dano e morte sao calculados no jogador.
    local health=player.health or 20
    for i=1,10 do
      local cx=30+(i-1)*27
      local fill=math.max(0,math.min(2,health-(i-1)*2))
      rect(pass,cx,92,22,22,.25,.12,.13,.96)
      if fill>0 then
        local r=fill==2 and .96 or .65
        rect(pass,cx,92,fill==2 and 17 or 9,17,r,.17,.19,.99)
      end
    end
    label(pass,'VIDA '..health..'/20',112,119,15,1,.86,.82)
    if classic then
      label(pass,'CLASSIC 0.30 | '..(classic.mode=='creative' and 'CRIATIVO' or 'SOBREVIVENCIA'),
        w/2,86,16,1,.94,.7)
      if classic.mode=='survival' then
        label(pass,'PONTOS '..tostring(classic.score),w-124,119,15,.92,.91,.7)
      end
    end
    local nearby=0
    if creepers then
      for _,mob in ipairs(creepers.list) do
        if mob.active then nearby=nearby+1 end
      end
    end
    if creatures then nearby=nearby+creatures:count() end
    if classic and classic.mode=='creative' then nearby=0 end
    label(pass,'Criaturas: '..nearby..'  |  F6 salvar',w-119,92,15,.86,.98,.83)
    label(pass,'BARRA '..require('src.textures').currentPage..'/'..
      #require('src.textures').pages..'  |  TAB para trocar',w/2,h-104,14,.96,.94,.70)
    if hit then
      label(pass,'Alvo: '..(labels[hit.id] or 'Bloco')..'  ['..hit.x..','..hit.y..','..hit.z..']',
      w/2,58,16,1,1,.6)
    end
    return
  end
  rect(pass,w/2,h/2,w,h,.022,.033,.050,.88)
  local title=(state=='title' and 'BASE 3D - CLASSIC 0.30') or
    (state=='pause' and 'JOGO PAUSADO') or
    (state=='dead' and 'VOCE MORREU') or 'CONFIGURACOES'
  label(pass,title,w/2,h*.22,math.min(54,w/20),.94,.82,.51)
  label(pass,state=='dead' and 'Pressione R ou clique RENASCER'
    or 'Sandbox voxel independente  -  LÖVR 0.19',
    w/2,h*.22+52,17,.72,.82,.90)
  local mx,my=lovr.system.getMousePosition()
  for _,b in ipairs(UI.buttons(state,settings,w,h,classic)) do
    local hover=inside(b,mx,my)
    rect(pass,b.x,b.y,b.w,b.h,
      hover and .25 or .11,hover and .44 or .20,
      hover and .55 or .26,1)
    label(pass,b.text,b.x,b.y,21,1,1,1)
  end
  label(pass,'Skins: assets/skins/player.png  |  Texturas: assets/textures/*.png',
    w/2,h-39,16,.75,.84,.94)
end
return UI
