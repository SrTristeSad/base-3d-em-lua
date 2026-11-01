-- Exact signed-division legacy PseudoRandom from Luanti's noise.h.
-- Uses 16-bit limbs to avoid precision loss on LuaJIT's doubles.
local M={}
local proto={}
proto.__index=proto
local U=4294967296
local floor=math.floor
local function signed(n)
 n=n%U
 return n>=2147483648 and n-U or n
end
local function integer(n)
 assert(type(n)=='number' and n==floor(n) and n>=-2147483648
  and n<=2147483647,'PseudoRandom state must be a signed 32-bit integer')
 return n
end
local function mul_add(a)
 local u=a%U
 local lo=u%65536
 local hi=floor(u/65536)
 local m=1103515245
 local ml=m%65536
 local mh=floor(m/65536)
 local product=lo*ml+12345
 local low=product%65536
 local upper=(floor(product/65536)+lo*mh+hi*ml)%65536
 return signed(upper*65536+low)
end
function M.new(seed)
 return setmetatable({state=integer(seed or 0)},proto)
end
function proto:next(min,max)
 self.state=mul_add(self.state)
 local q
 if self.state<0 then q=-floor(-self.state/65536)
 else q=floor(self.state/65536) end
 local result=q%32768
 if min==nil and max==nil then return result end
 assert(integer(min) and integer(max) and max>=min,
  'invalid PseudoRandom range')
 local span=max-min
 assert(span<=6553,'PseudoRandom range too large')
 return min+result%(span+1)
end
function proto:get_state() return self.state end
function proto:set_state(value) self.state=integer(value) end
return setmetatable(M,{__call=function(_,seed) return M.new(seed) end})
