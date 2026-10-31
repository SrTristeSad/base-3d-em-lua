-- PCG32 in portable Lua: exact uint64 math using two uint32 limbs.
-- Algorithm mirrors Luanti 5.18 noise.cpp PcgRandom. Not crypto-secure.
local Bit=require('core.bitops')
local floor=math.floor
local U=4294967296
local MHI,MLO=0x5851f42d,0x4c957f2d
local SEQ_HI,SEQ_LO=0xda3e39cb,0x94b95bdb
local PCG={}
local mt={__index=PCG}
local function u(n) return n%U end
local function signed32(n)
 n=u(n)
 return n>=2147483648 and n-U or n
end
local function split(n)
 assert(type(n)=='number' and n==floor(n) and
  n>=-9007199254740991 and n<=9007199254740991,
  'PcgRandom seed/sequence outside exact numeric range')
 if n>=0 then return floor(n/U),n%U end
 local a=-n
 local h,l=floor(a/U),a%U
 return u(-h-(l>0 and 1 or 0)),u(-l)
end
local function mul32(a,b)
 local al,ah=a%65536,floor(a/65536)
 local bl,bh=b%65536,floor(b/65536)
 local base=al*bl
 local mid=ah*bl+al*bh+floor(base/65536)
 local low=(base%65536)+(mid%65536)*65536
 local high=u(ah*bh+floor(mid/65536))
 return high,low
end
local function mul64(ah,al,bh,bl)
 local high,low=mul32(al,bl)
 local _,cross1=mul32(ah,bl)
 local _,cross2=mul32(al,bh)
 return u(high+cross1+cross2),low
end
local function add64(ah,al,bh,bl)
 local total=al+bl
 return u(ah+bh+(total>=U and 1 or 0)),u(total)
end
local function shr64(hi,lo,n)
 if n==0 then return hi,lo end
 if n>=64 then return 0,0 end
 if n>=32 then return 0,floor(hi/2^(n-32)) end
 return floor(hi/2^n),
  floor(lo/2^n)+(hi%2^n)*2^(32-n)
end
local function advance(self)
 local hi,lo=self.hi,self.lo
 local mh,ml=mul64(hi,lo,MHI,MLO)
 self.hi,self.lo=add64(mh,ml,self.inc_hi,self.inc_lo)
 local h,l=shr64(hi,lo,18)
 h,l=Bit.bxor(h,hi),Bit.bxor(l,lo)
 local _,x=shr64(u(h),u(l),27)
 local rot=floor(hi/134217728)
 return u(Bit.bor(Bit.rshift(x,rot),Bit.lshift(x,(32-rot)%32)))
end
local function hex32(n)
 return Bit.tohex(n,8)
end
function PCG.new(seed,seq)
 local sh,sl=split(seed)
 local qh,ql
 if seq==nil then qh,ql=SEQ_HI,SEQ_LO else qh,ql=split(seq) end
 local self=setmetatable({hi=0,lo=0,
  inc_hi=u(2*qh+floor(ql/2147483648)),
  inc_lo=u(2*ql+1)},mt)
 advance(self)
 self.hi,self.lo=add64(self.hi,self.lo,sh,sl)
 advance(self)
 return self
end
function PCG:next(minimum,maximum)
 if minimum==nil and maximum==nil then
  return signed32(advance(self))
 end
 assert(type(minimum)=='number' and type(maximum)=='number'
  and minimum==floor(minimum) and maximum==floor(maximum)
  and minimum>=-2147483648 and maximum<=2147483647
  and maximum>=minimum,'invalid PcgRandom bounds')
 local bound=maximum-minimum+1
 local threshold=(U-bound)%bound
 local r=advance(self)
 while r<threshold do r=advance(self) end
 local result=minimum+r%bound
 return result
end
function PCG:rand_normal_dist(minimum,maximum,trials)
 trials=trials or 6
 assert(type(trials)=='number' and trials==floor(trials) and
  trials>=1 and trials<=1000,'invalid trial count')
 local sum=0
 for _=1,trials do sum=sum+self:next(minimum,maximum) end
 return floor(sum/trials+0.5)
end
function PCG:get_state()
 return hex32(self.hi)..hex32(self.lo)..
  hex32(self.inc_hi)..hex32(self.inc_lo)
end
function PCG:set_state(value)
 assert(type(value)=='string' and #value==32 and
  value:match('^%x+$'),
  'PcgRandom:set_state expects 32 hex characters')
 self.hi=tonumber(value:sub(1,8),16)
 self.lo=tonumber(value:sub(9,16),16)
 self.inc_hi=tonumber(value:sub(17,24),16)
 self.inc_lo=tonumber(value:sub(25,32),16)
end
return setmetatable(PCG,{__call=function(_,seed,seq)
 return PCG.new(seed,seq)
end})
