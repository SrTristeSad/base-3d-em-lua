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

function UI.buttons(state, settings, w, h)
  local cx=w/2
  local b={}
  local function add(text,row,action)
    b[#b+1]={text=text,x=cx,y=h*.49+row*58,w=360,h=47,action=action}
  end
  if state=='title' then
    add('JOGAR',0,'play')
    add('CONFIGURACOES',1,'settings')
    add('SAIR',2,'quit')
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

function UI.click(state,settings,x,y,w,h)
  for _,b in ipairs(UI.buttons(state,settings,w,h)) do
    if inside(b,x,y) then return b.action end
  end
end

function UI.draw(pass,state,settings,player,hit,hotbar,labels)
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
      label(pass,i..'  '..labels[i],x,h-53,14)
    end
    label(pass,'WASD mover | Mouse olhar | Esq. quebrar | Dir. colocar | F5 camera | ESC menu',
      w/2,28,17,.9,.96,1)
    if hit then
      label(pass,'Alvo: '..(labels[hit.id] or 'Agua')..'  ['..hit.x..','..hit.y..','..hit.z..']',
      w/2,58,16,1,1,.6)
    end
    return
  end
  rect(pass,w/2,h/2,w,h,.022,.033,.050,.88)
  local title=(state=='title' and 'BASE 3D EM LUA') or
    (state=='pause' and 'JOGO PAUSADO') or 'CONFIGURACOES'
  label(pass,title,w/2,h*.22,math.min(54,w/20),.94,.82,.51)
  label(pass,'Sandbox voxel independente  -  LÖVR 0.19',
    w/2,h*.22+52,17,.72,.82,.90)
  local mx,my=lovr.system.getMousePosition()
  for _,b in ipairs(UI.buttons(state,settings,w,h)) do
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
