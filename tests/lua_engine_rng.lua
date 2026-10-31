-- Luanti bit/PCG regression vectors and LuaJIT-compatible arithmetic.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local bit=require('core.bitops')
local PCG=require('core.pcgrandom')
local function eq(a,b,desc)
 assert(a==b,(desc or 'value')..': expected '..tostring(b)..
  ', got '..tostring(a))
end
eq(bit.band(0xffffffff,0x12345678),0x12345678,'band')
eq(bit.band(-1,0x77,0x15),0x15,'multi-band')
eq(bit.bor(1,2,4),7,'multi-bor')
eq(bit.bxor(0x55,0xaa,0xff),0,'multi-bxor')
eq(bit.tobit(0xffffffff),-1,'signed bit')
eq(bit.bnot(0),-1,'bnot')
eq(bit.lshift(1,31),-2147483648,'shift')
eq(bit.rshift(-1,1),2147483647,'logical shift')
eq(bit.arshift(-2,1),-1,'arithmetic shift')
eq(bit.rol(0x12345678,8),0x34567812,'rotate left')
eq(bit.ror(0x12345678,8),0x78123456,'rotate right')
eq(bit.bswap(0x12345678),0x78563412,'bswap')
eq(bit.tohex(-1),'ffffffff','hex lowercase')
eq(bit.tohex(-1,-8),'FFFFFFFF','hex uppercase')
eq(bit.tohex(0x12345678,4),'5678','hex digits')
local vectors={
 {seed=0,values={174444157,-1751025858,-1069608390,
  -245019355,-2053080942,1518253903}},
 {seed=42,values={1898997482,1014631766,-198958742,
  633901381,1139273534,-1865419252}},
 {seed=12345,values={-2043628230,380381740,-1159844481,
  -755651080,-1202852131,-1741247842}},
 {seed=-1,values={971470767,385103218,535892592,
  -1117461634,388799378,15047732}},
}
for _,item in ipairs(vectors) do
 local rng=PCG(item.seed)
 for i,v in ipairs(item.values) do
  eq(rng:next(),v,'PCG32('..item.seed..') index '..i)
 end
end
local a=PCG(42)
local state=a:get_state()
eq(#state,32,'state 128-bit hex string')
local first=a:next()
local b=PCG(0)
b:set_state(state)
eq(b:next(),first,'state restored')
local bounded=PCG(42)
for i=1,500 do
 local n=bounded:next(-10,10)
 assert(n>=-10 and n<=10,'out-of-range at '..i)
end
local sum=PCG(42):rand_normal_dist(-10,10)
assert(sum>=-10 and sum<=10,'normal range')
assert(not pcall(PCG,math.huge),'inf seed rejected')
assert(not pcall(PCG,9007199254740992),'imprecise seed rejected')
assert(not pcall(b.set_state,b,'garbage'),'bad state rejected')
print('lua_engine_rng: OK')
