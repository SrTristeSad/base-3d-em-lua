-- Catalogo de blocos Classic 0.30 preservando IDs do primeiro prototipo.
-- O bloco 9 e agua desde os saves antigos e nao foi renumerado.
local T={}
T.MAX_ID=52
T.names={
 'grass_top','grass_side','dirt','stone','wood_side','wood_top',
 'leaves','sand','planks','bricks','water','cobble','gravel',
 'gold_ore','iron_ore','coal_ore','tnt_side','tnt_top',
 'glass','sponge','gold_block','iron_block','mossy','bookshelf',
 'obsidian','slab','flower_yellow','flower_red','mushroom_brown',
 'mushroom_red','sapling','lava','bedrock','cloth_white',
 'cloth_orange','cloth_magenta','cloth_light_blue','cloth_yellow',
 'cloth_lime','cloth_pink','cloth_gray','cloth_light_gray',
 'cloth_cyan','cloth_purple','cloth_blue','cloth_brown',
 'cloth_green','cloth_red','cloth_black',
 'diamond_ore','redstone_ore','lapis_ore',
 'crafting_side','crafting_top','furnace_side','furnace_top',
 'furnace_front','torch'
}
T.colors={
 grass_top={.34,.65,.23},grass_side={.43,.59,.25},dirt={.44,.31,.20},
 stone={.47,.48,.48},wood_side={.43,.28,.14},wood_top={.61,.45,.25},
 leaves={.24,.49,.20},sand={.82,.75,.49},planks={.65,.48,.28},
 bricks={.68,.32,.27},water={.28,.54,.78},cobble={.49,.49,.46},
 gravel={.51,.50,.48},gold_ore={.65,.55,.28},iron_ore={.54,.49,.42},
 coal_ore={.26,.28,.29},tnt_side={.75,.20,.16},tnt_top={.84,.73,.64},
 glass={.67,.82,.89},sponge={.78,.76,.27},gold_block={.95,.77,.18},
 iron_block={.73,.76,.76},mossy={.35,.46,.33},bookshelf={.46,.29,.16},
 obsidian={.13,.10,.23},slab={.59,.59,.57},flower_yellow={.99,.79,.13},
 flower_red={.84,.17,.21},mushroom_brown={.48,.30,.19},
 mushroom_red={.80,.24,.17},sapling={.29,.65,.25},lava={.94,.31,.07},
 bedrock={.19,.19,.20},cloth_white={.89,.88,.84},
 cloth_orange={.90,.48,.17},cloth_magenta={.72,.27,.66},
 cloth_light_blue={.44,.64,.83},cloth_yellow={.85,.75,.23},
 cloth_lime={.47,.73,.23},cloth_pink={.87,.52,.61},
 cloth_gray={.31,.33,.35},cloth_light_gray={.60,.62,.61},
 cloth_cyan={.20,.57,.62},cloth_purple={.53,.32,.70},
 cloth_blue={.24,.32,.67},cloth_brown={.47,.30,.19},
 cloth_green={.29,.48,.26},cloth_red={.72,.25,.23},cloth_black={.15,.15,.18},
 diamond_ore={.24,.78,.78},redstone_ore={.68,.18,.16},
 lapis_ore={.20,.29,.72},
 crafting_side={.55,.36,.18},crafting_top={.66,.49,.25},
 furnace_side={.43,.43,.42},furnace_top={.49,.49,.47},
 furnace_front={.33,.33,.32},torch={.96,.74,.22}
}
local function sides(key) return {key,key,key,key,key,key} end
T.faces={
 [1]={'grass_side','grass_side','grass_top','dirt','grass_side','grass_side'},
 [2]=sides('dirt'),[3]=sides('stone'),
 [4]={'wood_side','wood_side','wood_top','wood_top','wood_side','wood_side'},
 [5]=sides('leaves'),[6]=sides('sand'),[7]=sides('planks'),
 [8]=sides('bricks'),[9]=sides('water'),[10]=sides('cobble'),
 [11]=sides('gravel'),[12]=sides('gold_ore'),[13]=sides('iron_ore'),
 [14]=sides('coal_ore'),
 [15]={'tnt_side','tnt_side','tnt_top','tnt_top','tnt_side','tnt_side'},
 [16]=sides('glass'),[17]=sides('sponge'),[18]=sides('gold_block'),
 [19]=sides('iron_block'),[20]=sides('mossy'),[21]=sides('bookshelf'),
 [22]=sides('obsidian'),[23]=sides('slab'),[24]=sides('flower_yellow'),
 [25]=sides('flower_red'),[26]=sides('mushroom_brown'),
 [27]=sides('mushroom_red'),[28]=sides('sapling'),[29]=sides('lava'),
 [30]=sides('bedrock')
}
T.labels={
 'Grama','Terra','Rocha','Tronco','Folhas','Areia','Tabuas','Tijolo',
 'Agua','Pedregulho','Cascalho','Minerio ouro','Minerio ferro',
 'Carvao','TNT','Vidro','Esponja','Bloco ouro','Bloco ferro',
 'Pedra musgo','Estante','Obsidiana','Laje','Flor amarela',
 'Flor vermelha','Cogumelo marrom','Cogumelo vermelho','Muda',
 'Lava','Rocha-mae'
}
local dyeNames={'white','orange','magenta','light_blue','yellow','lime',
 'pink','gray','light_gray','cyan','purple','blue','brown','green','red','black'}
for i,name in ipairs(dyeNames) do
 T.faces[30+i]=sides('cloth_'..name)
 T.labels[30+i]='La '..i
end
T.faces[47]=sides('diamond_ore')
T.faces[48]=sides('redstone_ore')
T.faces[49]=sides('lapis_ore')
T.labels[47]='Minerio diamante'
T.labels[48]='Minerio redstone'
T.labels[49]='Minerio lapis'
T.faces[50]={'crafting_side','crafting_side','crafting_top','planks',
 'crafting_side','crafting_side'}
T.faces[51]={'furnace_front','furnace_side','furnace_top','stone',
 'furnace_side','furnace_side'}
T.faces[52]=sides('torch')
T.labels[50]='Bancada de trabalho'
T.labels[51]='Fornalha'
T.labels[52]='Tocha'
T.pages={
 {1,2,3,4,5,6,7,8},
 {10,11,12,13,14,15,16,17},
 {18,19,20,21,22,23,24,25},
 {26,27,28,9,29,30,31,32},
 {33,34,35,36,37,38,39,40},
 {41,42,43,44,45,46,7,8}
}
T.legacyPages=T.pages
T.betaPages={
 {1,2,3,4,5,6,7,8,10},
 {11,12,13,14,47,48,49,15,16},
 {17,18,19,20,21,22,23,24,25},
 {26,27,28,29,30,31,32,33,34},
 {35,36,37,38,39,40,41,42,43},
 {44,45,46,7,8,9,10,16,22},
 {50,51,52,7,10,4,14,47,48}
}
T.currentPage=1
T.hotbar={}
function T.setPage(index)
 if not T.pages[index] then return false end
 T.currentPage=index
 local page=T.pages[index]
 for i=1,#page do T.hotbar[i]=page[i] end
 for i=#page+1,#T.hotbar do T.hotbar[i]=nil end
 return true
end
function T.setProfile(profile)
 T.pages=profile=='beta181' and T.betaPages or T.legacyPages
 T.setPage(1)
end
function T.nextPage(delta)
 return T.setPage((T.currentPage-1+(delta or 1))%#T.pages+1)
end
T.setPage(1)
function T.load()
 local list={}
 for _,name in ipairs(T.names) do
  local path='assets/textures/'..name..'.png'
  if lovr.filesystem.isFile(path) then
   local ok,tex=pcall(lovr.graphics.newTexture,path)
   if ok then list[name]=tex else print('Erro textura:',path,tex) end
  end
  if not list[name] then
   local image=lovr.data.newImage(16,16)
   local base=T.colors[name]
   for y=0,15 do
    for x=0,15 do
     local n=((x*37+y*17+x*y*7)%17)/16
     local light=.86+n*.24
     if name=='grass_side' and y<4 then light=1.24 end
     if name=='wood_side' and x%4==0 then light=.71 end
     if name=='planks' and y%5==0 then light=.7 end
     if name=='bricks' and (y%5==0 or x%8==0) then light=.66 end
     if name=='wood_top' and (x==3 or x==12 or y==3 or y==12) then light=.7 end
     if name=='tnt_side' and y>5 and y<10 then light=1.40 end
     if name=='lava' then light=.83+(x*7+y*3)%6*.09 end
     if name:sub(1,6)=='cloth_' then light=.95+n*.08 end
     image:setPixel(x,y,
      math.min(1,base[1]*light),math.min(1,base[2]*light),
      math.min(1,base[3]*light),1)
    end
   end
   list[name]=lovr.graphics.newTexture(image)
  end
 end
 return list
end
return T
