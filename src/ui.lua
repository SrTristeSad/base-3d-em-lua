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
    field('name','NOME',menu and menu.name or '',-2)
    field('seed','SEMENTE',menu and menu.seed or '',-1)
    add('MODO: '..(menu and menu.mode=='creative' and 'CRIATIVO' or 'SOBREVIVENCIA'),0,'newmode')
    add('CRIAR E JOGAR',1,'create_world')
    add('VOLTAR',2,'title')
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

-- A mesma geometria rege clique e desenho: não há zonas cegas.
local function invSlots(state,w,h)
 local cells={}
 local function slot(area,index,x,y)
  cells[#cells+1]={section=area,index=index,x=x,y=y,w=49,h=49}
 end
 for n=1,27 do
  local column=(n-1)%9
  local row=math.floor((n-1)/9)
  slot('inventory',n+9,w/2+(column-4)*55,h/2+8+row*55)
 end
 for n=1,9 do
  slot('inventory',n,w/2+(n-5)*55,h/2+183)
 end
 if state=='furnace' then
  slot('furnace',1,w/2-180,h/2-149)
  slot('furnace',2,w/2-180,h/2-81)
  slot('furnace',3,w/2+98,h/2-116)
  return cells
 end
 local size=state=='workbench' and 3 or 2
 local left=w/2-240
 local top=state=='workbench' and h/2-169 or h/2-155
 for n=1,size*size do
  local col=(n-1)%size
  local row=math.floor((n-1)/size)
  slot(size==3 and 'table' or 'small',n,left+col*55,top+row*55)
 end
 slot('output',1,w/2+88,h/2-118)
 return cells
end
function UI.inventoryHit(state,x,y,w,h)
 if state~='inventory' and state~='workbench'
    and state~='furnace' then return nil end
 for _,cell in ipairs(invSlots(state,w,h)) do
  if inside(cell,x,y) then return cell.section,cell.index end
 end
 return nil
end
local function drawInventory(pass,state,classic,w,h)
 local isTable=state=='workbench'
 rect(pass,w/2,h/2,w,h,.04,.06,.09,.86)
 rect(pass,w/2,h/2,650,530,.17,.19,.21,.99)
 label(pass,isTable and 'BANCADA DE TRABALHO - 3 x 3'
   or 'INVENTARIO - 2 x 2',w/2,h/2-232,26,1,.9,.6)
 label(pass,'Clique E ou ESC para voltar | Esquerdo: pegar/trocar | Direito: dividir',
   w/2,h/2-201,14,.82,.87,.9)
 local output,recipe=classic:preview(isTable and 'table' or 'small')
 for _,cell in ipairs(invSlots(state,w,h)) do
  local stack
  if cell.section=='output' then
   stack=output
  elseif cell.section=='inventory' then
   stack=classic:getSlot(cell.index)
  else
   local area=classic:getArea(cell.section)
   stack=area[cell.index]
  end
  local mx,my=lovr.system.getMousePosition()
  local hover=inside(cell,mx,my)
  rect(pass,cell.x,cell.y,cell.w,cell.h,
    hover and .45 or .28,hover and .48 or .31,hover and .53 or .35,1)
  if stack then
   local name=classic:label(stack.id)
   label(pass,name:sub(1,11),cell.x,cell.y-6,11,1,1,.83)
   label(pass,tostring(stack.count),cell.x+14,cell.y+14,16,.95,.99,1)
   local Rules=require('src.beta181_survival')
   local durability=Rules.maxDurability(stack.id)
   if durability then
    local rest=math.max(0,durability-(stack.damage or 0))
    rect(pass,cell.x,cell.y+21,40,3,.18,.19,.20,1)
    rect(pass,cell.x-20+20*rest/durability,cell.y+21,
      40*rest/durability,3,.32,.82,.34,1)
   end
  end
 end
 label(pass,'CRAFTING',w/2-157,h/2-190,17,.91,.95,1)
 label(pass,'RESULTADO',w/2+88,h/2-160,13,.91,.95,1)
 if output and recipe then
  label(pass,recipe,w/2+105,h/2-73,14,.95,.89,.61)
 end
 label(pass,'MOCHILA - 27 ESPACOS',w/2,h/2-30,16,.9,.93,.99)
 label(pass,'BARRA RAPIDA - 9 ESPACOS',w/2,h/2+139,16,.9,.93,.99)
 label(pass,'SHIFT + clique: transferir pilha | No resultado: fabricar maximo',
   w/2,h/2+236,14,.82,.87,.91)
 if classic.cursor then
  local mx,my=lovr.system.getMousePosition()
  local held=classic.cursor
  rect(pass,mx+52,my-25,126,41,.10,.13,.18,.95)
  label(pass,classic:label(held.id):sub(1,18)..' x'..held.count,mx+52,my-25,13,1,.98,.76)
 end
end

local function drawFurnace(pass,classic,w,h)
 local f=classic and classic.openFurnace
 rect(pass,w/2,h/2,w,h,.035,.05,.07,.89)
 rect(pass,w/2,h/2,650,530,.16,.18,.21,.99)
 label(pass,'FORNALHA — FUNDIÇÃO E COZIMENTO',w/2,h/2-231,27,1,.86,.58)
 label(pass,'E ou ESC: voltar | Shift+clique: transferencia',w/2,h/2-199,
  15,.82,.88,.92)
 local mx,my=lovr.system.getMousePosition()
 for _,cell in ipairs(invSlots('furnace',w,h)) do
  local stack
  if cell.section=='inventory' then
   stack=classic:getSlot(cell.index)
  elseif f then stack=f.slots[cell.index] end
  local hover=inside(cell,mx,my)
  rect(pass,cell.x,cell.y,cell.w,cell.h,
    hover and .45 or .28,hover and .48 or .31,hover and .53 or .36,1)
  if stack then
   label(pass,classic:label(stack.id):sub(1,11),
     cell.x,cell.y-7,11,1,1,.83)
   label(pass,tostring(stack.count),cell.x+14,cell.y+14,16,.94,.96,1)
  end
 end
 label(pass,'MATERIAL',w/2-180,h/2-190,15,.92,.95,1)
 label(pass,'COMBUSTIVEL',w/2-180,h/2-42,15,.92,.95,1)
 label(pass,'SAIDA',w/2+98,h/2-159,15,.92,.95,1)
 local burning=f and f:burnRatio() or 0
 local cooking=f and f:progressRatio() or 0
 rect(pass,w/2-31,h/2-132,112,17,.12,.13,.14,.97)
 if cooking>0 then
  rect(pass,w/2-84+53*cooking,h/2-132,106*cooking,12,
    .95,.67,.30,1)
 end
 label(pass,('COZIMENTO %d%%'):format(math.floor(cooking*100)),
   w/2-26,h/2-101,14,.94,.91,.85)
 rect(pass,w/2-180,h/2-109,48,11,.16,.16,.16)
 if burning>0 then
  rect(pass,w/2-202+22*burning,h/2-109,44*burning,9,
    1,.45,.17)
 end
 label(pass,('FOGO %d%%'):format(math.floor(burning*100)),
   w/2-180,h/2-61,13,.98,.81,.57)
 label(pass,'MOCHILA — 27 ESPACOS',w/2,h/2-30,16,.91,.94,.99)
 label(pass,'BARRA RAPIDA — 9 ESPACOS',w/2,h/2+139,
  16,.91,.94,.99)
 label(pass,'Esquerdo: pegar/trocar | Direito: dividir/uma unidade',
  w/2,h/2+237,14,.81,.87,.92)
 if classic.cursor then
  rect(pass,mx+60,my-22,136,42,.12,.14,.18,.97)
  label(pass,classic:label(classic.cursor.id):sub(1,17)..
    ' x'..classic.cursor.count,mx+60,my-22,13,1,.98,.76)
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
  if state=='inventory' or state=='workbench' then
    drawInventory(pass,state,classic,w,h)
    return
  elseif state=='furnace' then
    drawFurnace(pass,classic,w,h)
    return
  end
  if state=='playing' then
    rect(pass,w/2,h/2,3,20,.98,.99,1)
    rect(pass,w/2,h/2,20,3,.98,.99,1)
    local slotCount=#hotbar
    rect(pass,w/2,h-52,slotCount*69+24,67,.05,.07,.10,.84)
    for i,id in ipairs(hotbar) do
      local x=w/2+(i-(slotCount+1)/2)*69
      local beta=classic and classic.profile=='beta181'
      local item=beta and classic.mode=='survival' and classic:getSlot(i) or nil
      if beta and classic.mode=='survival' then id=item and item.id or 0 end
      local selected=player.selected==i
      rect(pass,x,h-52,62,55,
        selected and .93 or .16,selected and .77 or .22,
        selected and .34 or .27,selected and .95 or .87)
      rect(pass,x,h-52,55,48,.13,.16,.21)
      local display=(beta and classic:label(id) or
        (labels[id] or ('Bloco '..id)))
      if id==0 then display='Vazio' end
      label(pass,i..' '..display:sub(1,11),x,h-58,11)
      if classic and classic.mode=='survival' then
        local count=beta and (item and item.count or 0)
          or (classic:count(id) or 0)
        label(pass,count>0 and tostring(count) or '',x,h-38,14,
          count>0 and .92 or .66,count>0 and .95 or .71,.86)
        if beta and item then
          local wear,total=classic:toolDamage(i)
          if total then
            local fraction=math.max(0,1-wear/total)
            rect(pass,x,h-26,49,4,.14,.14,.15)
            rect(pass,x-24.5+24.5*fraction,h-26,49*fraction,4,
              .36,.85,.39)
          end
        end
      end
    end
    local beta=classic and classic.profile=='beta181'
    label(pass,beta
      and 'E inventario | Dir.: usar balde/comer/construir | Espaco: nadar | Shift correr'
      or 'WASD mover | F3 desempenho | Esq. atacar/minerar | Dir. construir | TAB pagina | E cogumelo',
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
    if beta and classic.mode=='survival' then
      local food=player.hunger or 20
      for i=1,10 do
        local fx=w-28-(10-i)*27
        local amount=math.max(0,math.min(2,food-(i-1)*2))
        rect(pass,fx,146,22,22,.23,.19,.13,.95)
        if amount>0 then
          rect(pass,fx,146,amount==2 and 17 or 9,17,
            .95,.69,.25,.99)
        end
      end
      label(pass,'FOME '..math.floor(food)..'/20',w-150,174,
        14,.96,.85,.66)
      if player.underwater or (player.air or 15)<15 then
        label(pass,('AR %.1f / 15 s'):format(player.air or 15),
          111,161,16,.48,.80,1)
      end
      if player.inLava then
        label(pass,'CUIDADO: LAVA! DANO POR CALOR',
          w/2,188,15,1,.37,.21)
      elseif player.inWater then
        label(pass,'NATACAO: SEGURE ESPACO PARA SUBIR',
          w/2,188,14,.58,.87,1)
      end
    end
    if classic then
      label(pass,(beta and 'BETA 1.8.1 (PROTOTIPO)' or 'CLASSIC 0.30')..
        ' | '..(classic.mode=='creative' and 'CRIATIVO' or 'SOBREVIVENCIA'),
        w/2,86,16,1,.94,.7)
      if classic.mode=='survival' and not beta then
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
    if beta and classic.mode=='survival' then
      label(pass,'E: INVENTARIO 36 ESPACOS | USE BANCADA PARA CRAFT 3x3',
        w/2,h-104,14,.96,.94,.70)
    else
      label(pass,'BARRA '..require('src.textures').currentPage..'/'..
        #require('src.textures').pages..'  |  TAB para trocar',w/2,h-104,14,.96,.94,.70)
    end
    if beta and mesher and mesher.world.lighting then
      local lighting=mesher.world.lighting
      local tick=math.floor(lighting.time)
      local hours=math.floor((tick/1000+6)%24)
      local minutes=math.floor((tick%1000)*60/1000)
      local phase=lighting:phase()
      label(pass,('DIA %d | %02d:%02d | %s | LUZ %d/15'):format(
        lighting.day+1,hours,minutes,phase:upper(),
        lighting:skyLevel()),w/2,157,14,.97,.91,.68)
    end
    if mesher then
      local size=settings.distance*32+32
      label(pass,'Mundo dinamico '..size..'x'..size..
        ' | carregando '..mesher.pending..' chunks',w/2,111,14,.83,.97,.81)
      if showStats then
        label(pass,('CHUNKS %d | QUADS %d | CACHE %d | GERADOS %d'):format(
          mesher.visibleCount,mesher.quads,mesher.world:cacheCount(),
          mesher.world.generatedTotal),w/2,134,14,.90,.93,.99)
        if beta and mesher.world.lighting then
          local stats=mesher.world.lighting:skyCacheStats()
          label(pass,('SKYLIGHT %d VOXELS | %d SECOES | HITS %d | BFS %d'):format(
            stats.entries,stats.sections,stats.hits,stats.bfsNodes),
            w/2,183,13,.80,.90,1)
        end
        if beta and mesher.world.fluids then
          label(pass,('FLUIDOS %d PENDENTES | %d TICKS'):format(
            mesher.world.fluids:pendingCount(),
            mesher.world.fluids.processed),w/2,203,13,.80,.92,1)
        end
      end
    end
    if hit then
      label(pass,'Alvo: '..(labels[hit.id] or 'Bloco')..'  ['..hit.x..','..hit.y..','..hit.z..']',
      w/2,58,16,1,1,.6)
      if beta and classic.mode=='survival' and player.mining then
        local progress=player:miningFraction()
        rect(pass,w/2,h/2+33,112,10,.15,.14,.12,.90)
        if progress>0 then
          rect(pass,w/2-52+52*progress,h/2+33,
            104*progress,7,.95,.77,.40,.95)
        end
        label(pass,('MINERANDO %d%%'):format(math.floor(progress*100)),
          w/2,h/2+53,15,1,.9,.64)
      end
    end
    if beta and player.eating then
      local fraction=math.min(1,(player.eating.elapsed or 0)/1.6)
      label(pass,('COMENDO %d%%'):format(math.floor(fraction*100)),
        w/2,h/2+80,14,.97,.78,.51)
    end
    return
  end
  rect(pass,w/2,h/2,w,h,.022,.033,.050,.88)
  local title=(state=='title' and 'BASE 3D - BETA 1.8.1 (EM DESENVOLVIMENTO)') or
    (state=='create' and 'CRIAR NOVO MUNDO') or
    (state=='worldlist' and 'MEUS MUNDOS') or
    (state=='pause' and 'JOGO PAUSADO') or
    (state=='dead' and 'VOCE MORREU') or 'CONFIGURACOES'
  local titleY=state=='create' and h*.17 or h*.22
  label(pass,title,w/2,titleY,math.min(54,w/20),.94,.82,.51)
  local subtitle=state=='dead' and 'Pressione R ou clique RENASCER'
    or (state=='create' and 'Mundo novo Beta 1.8.1 | seed numerica ou texto')
    or (state=='title' and 'Construa um mundo Beta 1.8.1 com uma seed')
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
  if state=='create' then
    footer='Geracao por imagem desativada | Saves antigos continuam acessiveis'
  elseif state=='worldlist' then
    footer='Cada mundo tem seed, blocos e salvamento independentes'
  end
  label(pass,footer,w/2,h-39,16,.75,.84,.94)
end
return UI
