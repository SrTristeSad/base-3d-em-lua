local Textures = {}
Textures.names = { 'grass_top', 'grass_side', 'dirt', 'stone', 'wood_side',
  'wood_top', 'leaves', 'sand', 'planks', 'bricks', 'water' }
Textures.colors = {
  grass_top = {.34,.65,.23}, grass_side = {.43,.59,.25},
  dirt = {.44,.31,.20}, stone = {.47,.48,.48},
  wood_side = {.43,.28,.14}, wood_top = {.61,.45,.25},
  leaves = {.24,.49,.20}, sand = {.82,.75,.49},
  planks = {.65,.48,.28}, bricks = {.68,.32,.27}, water = {.28,.54,.78}
}
Textures.faces = {
  [1] = {'grass_side','grass_side','grass_top','dirt','grass_side','grass_side'},
  [2] = {'dirt','dirt','dirt','dirt','dirt','dirt'},
  [3] = {'stone','stone','stone','stone','stone','stone'},
  [4] = {'wood_side','wood_side','wood_top','wood_top','wood_side','wood_side'},
  [5] = {'leaves','leaves','leaves','leaves','leaves','leaves'},
  [6] = {'sand','sand','sand','sand','sand','sand'},
  [7] = {'planks','planks','planks','planks','planks','planks'},
  [8] = {'bricks','bricks','bricks','bricks','bricks','bricks'},
  [9] = {'water','water','water','water','water','water'}
}
Textures.hotbar = {1,2,3,4,5,6,7,8}
Textures.labels = {'Grama','Terra','Pedra','Tronco','Folhas','Areia','Madeira','Tijolo'}

function Textures.load()
  local list = {}
  for _, name in ipairs(Textures.names) do
    local path = 'assets/textures/' .. name .. '.png'
    if lovr.filesystem.isFile(path) then
      local ok, tex = pcall(lovr.graphics.newTexture, path)
      if ok then list[name] = tex else print('Erro textura:',path,tex) end
    end
    if not list[name] then
      local image = lovr.data.newImage(16,16)
      local base = Textures.colors[name]
      for y=0,15 do
        for x=0,15 do
          local n = ((x*37 + y*17 + x*y*7) % 17)/16
          local light = .86 + n*.24
          if name=='grass_side' and y < 4 then light = 1.27 end
          if name=='wood_side' and x%4 == 0 then light = .72 end
          if name=='planks' and y%5 == 0 then light = .70 end
          if name=='bricks' and (y%5 == 0 or x%8 == 0) then light = .66 end
          if name=='wood_top' and (x==3 or x==12 or y==3 or y==12) then light = .70 end
          image:setPixel(x,y,
            math.min(1,base[1]*light),math.min(1,base[2]*light),math.min(1,base[3]*light),1)
        end
      end
      list[name] = lovr.graphics.newTexture(image)
    end
  end
  return list
end
return Textures
