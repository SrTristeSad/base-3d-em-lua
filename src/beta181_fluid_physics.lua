-- Fase 10: amostragem de liquidos, correnteza e imersao do jogador.
-- Coordenadas inteiras sao centros de blocos; limites vao de -.5 a +.5.
-- Compativel com o perfil antigo: nao requer novos blocos nem assets.
local M={}
local floor,sqrt,min,max=math.floor,math.sqrt,math.min,math.max
local function cell(x) return floor(x+.5) end
local CARDINAL={{1,0},{-1,0},{0,1},{0,-1}}
local function isLiquid(id) return id==9 or id==29 end
function M.sample(world,x,y,z)
 if not world or not world.get then return nil end
 local bx,by,bz=cell(x),cell(y),cell(z)
 local id=world:get(bx,by,bz)
 if not isLiquid(id) then return nil end
 local meta=world.fluids and world.fluids:get(bx,by,bz)
 local depth=0
 if meta and not meta.falling then depth=meta.level/8 end
 local surface=by+.5-depth
 if y<by-.5 or y>surface then return nil end
 return {id=id,x=bx,y=by,z=bz,meta=meta,surface=surface}
end
-- Direcao media do fluxo: niveis maiores representam camada menos
-- profunda; correnteza empurra da fonte em direcao aos canais rasos.
-- Agua/lava natural estacionaria (sem estado de fluxo) nao empurra.
function M.current(world,position)
 if not position or not position.meta then return 0,0,0 end
 if position.meta.falling then return 0,-1,0 end
 local id,x,y,z=position.id,position.x,position.y,position.z
 local level=position.meta.level
 local vx,vz=0,0
 for i=1,4 do
  local d=CARDINAL[i]
  local nx,nz=x+d[1],z+d[2]
  if not world.within or world:within(nx,y,nz) then
   if world:get(nx,y,nz)==id then
    local other=world.fluids and world.fluids:get(nx,y,nz)
    local candidate=other and (other.falling and 0 or other.level) or 0
    local gradient=candidate-level
    if gradient>0 then
     vx=vx+d[1]*gradient
     vz=vz+d[2]*gradient
    end
   end
  end
 end
 local length=sqrt(vx*vx+vz*vz)
 if length<.01 then return 0,0,0 end
 return vx/length,0,vz/length
end
function M.environment(world,player)
 if not world or world.generatorVersion~='beta181' then
  return {id=nil,water=false,lava=false,underwater=false,
    currentX=0,currentY=0,currentZ=0}
 end
 local x,y,z=player.x,player.y,player.z
 local feet=M.sample(world,x,y+.16,z)
 local torso=M.sample(world,x,y+.85,z)
 local eye=M.sample(world,x,y+1.61,z)
 local immersed=(torso or feet)
 local lava=(feet and feet.id==29) or (torso and torso.id==29)
 local water=not lava and immersed and immersed.id==9 or false
 local stream=torso or feet
 local vx,vy,vz=M.current(world,stream)
 return {id=lava and 29 or (water and 9 or nil),
   water=not not water,lava=not not lava,
   underwater=not not (eye and eye.id==9),
   currentX=vx,currentY=vy,currentZ=vz}
end
return M
