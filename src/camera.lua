-- Camera FPS (Classic 0.30) sem dependencias graficas.
-- Rotacao consistente com Player:direction e mouse em modo relativo.
local Camera={}
local sin,cos,abs,floor=math.sin,math.cos,math.abs,math.floor
Camera.MAX_PITCH=math.rad(89)
Camera.TAU=math.pi*2

function Camera.look(yaw,pitch,dx,dy,sensitivity,invertY)
  yaw=tonumber(yaw) or 0
  pitch=tonumber(pitch) or 0
  dx=tonumber(dx) or 0
  dy=tonumber(dy) or 0
  sensitivity=math.max(.0002,math.min(.01,tonumber(sensitivity) or .002))
  -- Evita salto extremo ao reobter foco/capturar o cursor.
  if dx~=dx or dy~=dy or abs(dx)>500 or abs(dy)>500 then
    return yaw,pitch
  end
  -- +yaw aponta +X quando o jogador vira o mouse para direita.
  yaw=(yaw+dx*sensitivity+math.pi)%Camera.TAU-math.pi
  local direction=invertY and 1 or -1
  pitch=math.max(-Camera.MAX_PITCH,math.min(Camera.MAX_PITCH,
    pitch+direction*dy*sensitivity))
  return yaw,pitch
end

function Camera.forward(yaw,pitch)
  local c=cos(pitch)
  return sin(yaw)*c,sin(pitch),-cos(yaw)*c
end

local function solid(world,x,y,z)
  if not world or not world.isSolid then return false end
  return world:isSolid(floor(x+.5),floor(y+.5),floor(z+.5))
end

-- Evita ver o interior das paredes com a camera em terceira pessoa.
-- Baseia o recuo no olho e procura a primeira superficie ao longo do raio.
function Camera.thirdPerson(world,x,y,z,dx,dy,dz,distance)
  distance=math.max(.5,math.min(8,distance or 3.5))
  local vx,vy,vz=-dx*distance,1.0-dy*distance,-dz*distance
  local length=math.sqrt(vx*vx+vy*vy+vz*vz)
  local ux,uy,uz=vx/length,vy/length,vz/length
  local safe=length
  for t=.15,length,.10 do
    if solid(world,x+ux*t,y+uy*t,z+uz*t) then
      safe=math.max(0,t-.22)
      break
    end
  end
  return x+ux*safe,y+uy*safe,z+uz*safe
end
return Camera
