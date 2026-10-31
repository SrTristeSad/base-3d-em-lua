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

function UI.buttons(state, settings, w, h, classic, menu)
  local cx=w/2
  local b={}
  local function add(text,row,action)
    b[#b+1]={text=text,x=cx,y=h*.49+row*58,w=360,h=47,action=action}
  end
  if state=='title' then
    if menu and menu.selected then
      add('CONTINUAR: '..menu.selected.name:sub(1,26),-2,'play')
    end
    add('CRIAR NOVO MUNDO',-1,'create')
    add('ESCOLHER MUNDO',0,'worldlist')
    add('CONFIGURACOES',1,'settings')
    add('SAIR',2,'quit')
  elseif state=='create' then
    local function field(name,label,value,row)
      local focused=menu and menu.focus==name
      local prompt=(value=='' and '(opcional)' or value:sub(1,42))
      add(label..': '..prompt..(focused and ' |' or ''),row,'field:'..name)
    end
    field('name','NOME',menu and menu.name or '',-3)
    field('seed','SEMENTE',menu and menu.seed or '',-2)
    field('image','IMAGEM PNG/JPG',menu and menu.image or '',-1)
    add('ESCOLHER IMAGEM NA PASTA MAPS',0,'images')
    add('TESTAR IMAGEM EXEMPLO',1,'demoimage')
    add('MODO: '..(menu and menu.mode=='creative' and 'CRIATIVO' or 'SOBREVIVENCIA'),2,'newmode')
    add('CRIAR E JOGAR',3,'create_world')
    add('VOLTAR',4,'title')
  elseif state=='imagelist' then
    local images=menu and menu.images or {}
    local page=menu and menu.imagePage or 1
    for i=1,4 do
      local name=images[(page-1)*4+i]
      if name then add('USAR: '..name:sub(1,39),i-2.5,'pickimage:'..name) end
    end
    if page>1 then add('ANTERIOR',2.5,'imageprev') end
    if #images>page*4 then add('PROXIMA',2.5,'imagenext') end
    add('VOLTAR',3.5,'backcreate')
  elseif state=='worldlist' then
    local entries=menu and menu.entries or {}
    local page=(menu and menu.page or 1)
    for i=1,4 do
      local item=entries[(page-1)*4+i]
      if item then
        add('JOGAR: '..item.name:sub(1,33),i-2.5,'load:'..item.id)
      end
    end
    if page>1 then add('PAGINA ANTERIOR',2.5,'previous') end
    if #entries>page*4 then add('PROXIMA PAGINA',2.5,'next') end
    add('VOLTAR',3.5,'title')
  elseif state=='dead' then
    add('RENASCER',0,'respawn')
    add('MENU INICIAL',1,'title')
  elseif state=='pause' then
    add('CONTINUAR',-1,'resume')
    add('SALVAR MUNDO',0,'save')
    add('CONFIGURACOES',1,'settings')
    add('MENU INICIAL',2,'title')
  elseif state=='settings' then
    add('CAMPO DE VISAO: '..settings.fov..' graus',-3,'fov')
    add('SENSIBILIDADE: '..settings.sensitivityLabel,-2,'sensitivity')
    add('INVERTER EIXO X: '..(settings.invertX and 'SIM' or 'NAO'),-1,'invertx')
    add('INVERTER EIXO Y: '..(settings.invertY and 'SIM' or 'NAO'),0,'inverty')
    add('ALCANCE: '..(settings.distance*32+32)..'x'..
      (settings.distance*32+32)..' blocos',1,'distance')
    add('TELA CHEIA: '..(settings.fullscreen and 'SIM' or 'NAO'),2,'fullscreen')
    add('VOLTAR',3,'back')
  end
  return b
end

function UI.click(state,settings,x,y,w,h,classic,menu)
  for _,b in ipairs(UI.buttons(state,settings,w,h,classic,menu)) do
    if inside(b,x,y) then return b.action end
  end
end

function UI.draw(pass,state,settings,player,hit,hotbar,labels,creepers,classic,creatures,
  mesher,showStats,menu)
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
    label(pass,'WASD mover | F3 desempenho | Esq. atacar/minerar | Dir. construir | TAB pagina | E cogumelo',
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
    if mesher then
      local size=settings.distance*32+32
      label(pass,'Mundo dinamico '..size..'x'..size..
        ' | carregando '..mesher.pending..' chunks',w/2,111,14,.83,.97,.81)
      if showStats then
        label(pass,('CHUNKS %d | QUADS %d | CACHE %d | GERADOS %d'):format(
          mesher.visibleCount,mesher.quads,mesher.world:cacheCount(),
          mesher.world.generatedTotal),w/2,134,14,.90,.93,.99)
      end
    end
    if hit then
      label(pass,'Alvo: '..(labels[hit.id] or 'Bloco')..'  ['..hit.x..','..hit.y..','..hit.z..']',
      w/2,58,16,1,1,.6)
    end
    return
  end
  rect(pass,w/2,h/2,w,h,.022,.033,.050,.88)
  local title=(state=='title' and 'BASE 3D - CLASSIC 0.30') or
    (state=='imagelist' and 'ESCOLHER IMAGEM') or
    (state=='create' and 'CRIAR NOVO MUNDO') or
    (state=='worldlist' and 'MEUS MUNDOS') or
    (state=='pause' and 'JOGO PAUSADO') or
    (state=='dead' and 'VOCE MORREU') or 'CONFIGURACOES'
  local titleY=(state=='create' or state=='imagelist') and h*.13 or h*.22
  label(pass,title,w/2,titleY,math.min(54,w/20),.94,.82,.51)
  local subtitle=state=='dead' and 'Pressione R ou clique RENASCER'
    or (state=='create' and 'Digite seed ou escolha uma imagem para influenciar terreno')
    or (state=='imagelist' and 'Copie PNG ou JPG para a pasta maps do save')
    or (state=='title' and 'Crie um mundo com seed ou com uma imagem')
    or (state=='worldlist' and 'Selecione um mundo para continuar')
    or 'Sandbox voxel independente - LÖVR 0.19'
  label(pass,subtitle,w/2,titleY+44,17,.72,.82,.90)
  if menu and menu.notice and menu.notice~='' then
    label(pass,menu.notice:sub(1,95),w/2,titleY+68,15,1,.64,.57)
  end
  local mx,my=lovr.system.getMousePosition()
  for _,b in ipairs(UI.buttons(state,settings,w,h,classic,menu)) do
    local hover=inside(b,mx,my)
    rect(pass,b.x,b.y,b.w,b.h,
      hover and .25 or .11,hover and .44 or .20,
      hover and .55 or .26,1)
    label(pass,b.text,b.x,b.y,21,1,1,1)
  end
  local footer='Skins: assets/skins/player.png | Blocos: assets/textures/'
  if state=='create' or state=='imagelist' then
    footer='Imagem: maps/foto.png | Deixe vazio para usar apenas a seed'
  elseif state=='worldlist' then
    footer='Cada mundo tem seed, blocos e salvamento independentes'
  end
  label(pass,footer,w/2,h-39,16,.75,.84,.94)
end
return UI
