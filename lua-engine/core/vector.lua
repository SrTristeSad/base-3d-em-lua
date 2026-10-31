-- Minimal vector implementation of Luanti-facing Lua vector API.
local V={}
local mt={}
mt.__index=V
local sqrt=math.sqrt
local function v(x,y,z)
 if type(x)=='table' then
  y,z=x.y,x.z
  x=x.x
 end
 assert(type(x)=='number' and type(y)=='number' and
  type(z)=='number','vector requires numeric x,y,z')
 return setmetatable({x=x,y=y,z=z},mt)
end
V.new=v
V.copy=v
function V.add(a,b)
 if type(b)=='number' then return v(a.x+b,a.y+b,a.z+b) end
 return v(a.x+b.x,a.y+b.y,a.z+b.z)
end
function V.subtract(a,b)
 if type(b)=='number' then return v(a.x-b,a.y-b,a.z-b) end
 return v(a.x-b.x,a.y-b.y,a.z-b.z)
end
function V.multiply(a,b)
 if type(a)=='number' then return v(b.x*a,b.y*a,b.z*a) end
 if type(b)=='number' then return v(a.x*b,a.y*b,a.z*b) end
 return v(a.x*b.x,a.y*b.y,a.z*b.z)
end
function V.divide(a,b)
 if type(b)=='number' then return v(a.x/b,a.y/b,a.z/b) end
 return v(a.x/b.x,a.y/b.y,a.z/b.z)
end
function V.length(a) return sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
function V.distance(a,b) return V.length(V.subtract(a,b)) end
function V.direction(a,b)
 local d=V.subtract(b,a)
 return V.normalize(d)
end
function V.normalize(a)
 local n=V.length(a)
 if n==0 then return v(0,0,0) end
 return V.divide(a,n)
end
function V.dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
function V.cross(a,b)
 return v(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)
end
function V.round(a)
 local function rnd(x) return math.floor(x+.5) end
 return v(rnd(a.x),rnd(a.y),rnd(a.z))
end
function V.floor(a)
 return v(math.floor(a.x),math.floor(a.y),math.floor(a.z))
end
function V.offset(a,dx,dy,dz)
 return v(a.x+dx,a.y+dy,a.z+dz)
end
function V.equals(a,b) return a.x==b.x and a.y==b.y and a.z==b.z end
function V.sort(a,b)
 return v(math.min(a.x,b.x),math.min(a.y,b.y),math.min(a.z,b.z)),
  v(math.max(a.x,b.x),math.max(a.y,b.y),math.max(a.z,b.z))
end
function V.to_string(a)
 return ('(%g, %g, %g)'):format(a.x,a.y,a.z)
end
mt.__add=V.add
mt.__sub=V.subtract
mt.__mul=V.multiply
mt.__div=V.divide
mt.__unm=function(a) return v(-a.x,-a.y,-a.z) end
mt.__tostring=V.to_string
return V
