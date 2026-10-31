-- Relogio por mundo da Beta 1.8.1, independente dos perfis anteriores.
local Daylight={}
Daylight.TICKS_PER_DAY=24000
Daylight.TICKS_PER_SECOND=20
local floor,cos,pi,min,max=math.floor,math.cos,math.pi,math.min,math.max
local function finite(n)
 return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge
end
function Daylight.valid(t)
 return finite(t) and t>=0 and t<=1000000000000
end
function Daylight.normalize(t)
 return Daylight.valid(t) and t%24000 or 0
end
function Daylight.advance(t,dt)
 local now=Daylight.valid(t) and t or 0
 if not finite(dt) or dt<=0 then return now end
 return min(1000000000000,now+min(dt,60)*20)
end
function Daylight.sun(t)
 local a=(Daylight.normalize(t)-6000)*2*pi/24000
 local level=max(0,min(1,(cos(a)+.15)/.75))
 return level*level*(3-2*level)
end
function Daylight.ambient(t)
 return .20+.80*Daylight.sun(t)
end
function Daylight.sky(t)
 local l=Daylight.sun(t)
 local twilight=4*l*(1-l)
 return .025+.465*l+.045*twilight,
   .04+.68*l+.010*twilight,.11+.80*l
end
function Daylight.phase(t)
 local n=Daylight.normalize(t)
 if n<1000 then return 'Amanhecer' end
 if n<11000 then return 'Dia' end
 if n<13000 then return 'Anoitecer' end
 return 'Noite'
end
function Daylight.day(t)
 return floor((Daylight.valid(t) and t or 0)/24000)+1
end
function Daylight.clock(t)
 local h=(Daylight.normalize(t)+6000)/1000
 return ('%02d:%02d'):format(floor(h)%24,floor((h-floor(h))*60))
end
return Daylight
