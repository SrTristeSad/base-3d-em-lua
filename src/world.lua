local World = {}
World.__index = World
World.SIZE = 48
World.MIN = -24
World.MAX = 23
World.YMIN = -4
World.YMAX = 19
World.CHUNK = 16
World.SAVE = 'world.sav'

local function key(x, y, z) return x .. ',' .. y .. ',' .. z end
local function height(x, z)
  local h = 3 + math.sin(x * .14) * 2 + math.cos(z * .13) * 2
    + math.sin((x + z) * .09) * 1.5
  return math.max(-2, math.min(8, math.floor(h)))
end
local function rng(x, z)
  local a = math.sin(x * 127.1 + z * 311.7 + 37.1) * 43758.5453
  return a - math.floor(a)
end

function World.new()
  local w = setmetatable({ blocks = {}, edits = {}, dirty = {}, savedPlayer = nil }, World)
  for x = w.MIN, w.MAX do
    for z = w.MIN, w.MAX do
      local h = height(x, z)
      for y = w.YMIN, h do
        local id = (y == h and 1) or (y >= h - 2 and 2) or 3
        w.blocks[key(x, y, z)] = id
      end
      for y = h + 1, 1 do
        w.blocks[key(x, y, z)] = 9
      end
    end
  end
  for x = w.MIN + 3, w.MAX - 3 do
    for z = w.MIN + 3, w.MAX - 3 do
      local h = height(x, z)
      if h > 1 and rng(x,z) > .987 and (math.abs(x) > 4 or math.abs(z) > 4) then
        for y = h + 1, h + 4 do w.blocks[key(x, y, z)] = 4 end
        for yy = h + 3, h + 5 do
          for xx = x - 2, x + 2 do
            for zz = z - 2, z + 2 do
              local distance = math.abs(xx - x) + math.abs(zz - z)
              if distance < ((yy == h + 5) and 3 or 4)
                and not w.blocks[key(xx, yy, zz)] then
                w.blocks[key(xx, yy, zz)] = 5
              end
            end
          end
        end
      end
    end
  end
  w:load()
  for cx = math.floor(w.MIN / w.CHUNK), math.floor(w.MAX / w.CHUNK) do
    for cz = math.floor(w.MIN / w.CHUNK), math.floor(w.MAX / w.CHUNK) do
      w.dirty[cx .. ':' .. cz] = true
    end
  end
  return w
end

function World:within(x, y, z)
  return x >= self.MIN and x <= self.MAX
    and z >= self.MIN and z <= self.MAX
    and y >= self.YMIN and y <= self.YMAX
end

function World:get(x, y, z)
  if not self:within(x,y,z) then return 0 end
  return self.blocks[key(x,y,z)] or 0
end

function World:set(x, y, z, id)
  if not self:within(x,y,z) or y == self.YMIN then return false end
  if id < 0 or id > 9 or id % 1 ~= 0 then return false end
  if self:get(x,y,z) == id then return false end
  local k = key(x,y,z)
  self.blocks[k] = id == 0 and nil or id
  self.edits[k] = id
  for _, d in ipairs({{0,0},{1,0},{-1,0},{0,1},{0,-1}}) do
    local cx = math.floor((x+d[1])/self.CHUNK)
    local cz = math.floor((z+d[2])/self.CHUNK)
    self.dirty[cx .. ':' .. cz] = true
  end
  return true
end

-- Uma detonacao remove apenas blocos editaveis. A camada de fundo,
-- a agua e a area de nascimento ficam protegidas contra destruicao.
function World:explode(px,py,pz,radius)
  radius=math.max(.5,math.min(4,radius or 2))
  local removed=0
  local r=math.ceil(radius)
  for x=math.floor(px)-r,math.floor(px)+r do
    for y=math.floor(py)-r,math.floor(py)+r do
      for z=math.floor(pz)-r,math.floor(pz)+r do
        local dx,dy,dz=x-px,y-py,z-pz
        local id=self:get(x,y,z)
        local safeSpawn=math.abs(x)<3 and math.abs(z)<3
        if id~=0 and id~=9 and y>self.YMIN and not safeSpawn
          and dx*dx+dy*dy+dz*dz<=radius*radius then
          if self:set(x,y,z,0) then removed=removed+1 end
        end
      end
    end
  end
  return removed
end

function World:isSolid(x,y,z)
  local id = self:get(x,y,z)
  return id ~= 0 and id ~= 9 and id ~= 5
end

function World:spawnHeight(x,z)
  for y = self.YMAX, self.YMIN, -1 do
    if self:isSolid(x,y,z) and self:get(x,y+1,z) == 0 then
      return y + .51
    end
  end
  return 10
end

function World:load()
  local source = lovr.filesystem.read(self.SAVE)
  if not source then return end
  for line in source:gmatch('[^\r\n]+') do
    local px,py,pz,yaw,pitch = line:match('^PLAYER ([%d%.%-]+) ([%d%.%-]+) ([%d%.%-]+) ([%d%.%-]+) ([%d%.%-]+)$')
    if px and tonumber(px) and tonumber(py) and tonumber(pz) then
      self.savedPlayer = { x=tonumber(px), y=tonumber(py), z=tonumber(pz),
        yaw=tonumber(yaw) or 0, pitch=tonumber(pitch) or 0 }
    else
      local x,y,z,id = line:match('^BLOCK (%-?%d+) (%-?%d+) (%-?%d+) (%d+)$')
      x,y,z,id = tonumber(x),tonumber(y),tonumber(z),tonumber(id)
      if x and y and z and id and self:within(x,y,z) and id <= 9 then
        local k = key(x,y,z)
        self.blocks[k] = id == 0 and nil or id
        self.edits[k] = id
      end
    end
  end
end

function World:save(player)
  local lines = { string.format('PLAYER %.3f %.3f %.3f %.6f %.6f',
    player.x,player.y,player.z,player.yaw,player.pitch) }
  local keys = {}
  for k in pairs(self.edits) do keys[#keys+1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local x,y,z = k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
    lines[#lines+1] = ('BLOCK %s %s %s %d'):format(x,y,z,self.edits[k])
  end
  return lovr.filesystem.write(self.SAVE, table.concat(lines,'\n') .. '\n')
end
return World
