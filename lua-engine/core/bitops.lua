-- Luanti/LuaJIT-compatible 32-bit bitops when native 'bit' is unavailable.
-- Arithmetic implementation deliberately avoids Lua 5.3-only operators.
local B={}
local U=4294967296
local SIGN=2147483648
local floor=math.floor
local function u32(n)
 assert(type(n)=='number' and n==n and n~=math.huge and n~=-math.huge,
  'bit operation expects finite number')
 return floor(n)%U
end
local function signed(n)
 n=n%U
 return n>=SIGN and n-U or n
end
local function pair(a,b,mode)
 a,b=u32(a),u32(b)
 local out,weight=0,1
 for _=1,32 do
  local x,y=a%2,b%2
  if (mode=='and' and x==1 and y==1)
   or (mode=='or' and (x==1 or y==1))
   or (mode=='xor' and x~=y) then out=out+weight end
  a=floor(a/2);b=floor(b/2);weight=weight*2
 end
 return out
end
local function fold(mode,initial,...)
 local acc=initial
 for i=1,select('#',...) do
  local value=select(i,...)
  acc=pair(acc,value,mode)
 end
 return signed(acc)
end
function B.tobit(n) return signed(u32(n)) end
function B.band(...) return fold('and',U-1,...) end
function B.bor(...) return fold('or',0,...) end
function B.bxor(...) return fold('xor',0,...) end
function B.bnot(n) return signed(U-1-u32(n)) end
function B.lshift(n,b) return signed((u32(n)*2^(u32(b)%32))%U) end
function B.rshift(n,b) return floor(u32(n)/2^(u32(b)%32)) end
function B.arshift(n,b) return signed(floor(signed(u32(n))/2^(u32(b)%32))) end
function B.rol(n,b)
 b=u32(b)%32
 local x=u32(n)
 return signed((x%2^(32-b))*2^b+floor(x/2^(32-b)))
end
function B.ror(n,b)
 b=u32(b)%32
 local x=u32(n)
 return signed((floor(x/2^b)+(x%2^b)*2^(32-b))%U)
end
function B.bswap(n)
 local x=u32(n)
 local a,b,c,d=x%256,floor(x/256)%256,floor(x/65536)%256,floor(x/16777216)%256
 return signed(a*16777216+b*65536+c*256+d)
end
function B.tohex(n,digits)
 digits=digits or 8
 assert(type(digits)=='number' and digits==floor(digits)
  and math.abs(digits)<=8,'invalid hex digit count')
 local alphabet=digits<0 and '0123456789ABCDEF' or '0123456789abcdef'
 digits=math.abs(digits)
 local x=u32(n)
 local out={}
 for i=1,8 do
  local v=x%16
  out[9-i]=alphabet:sub(v+1,v+1)
  x=floor(x/16)
 end
 return table.concat(out):sub(9-digits)
end
return B
