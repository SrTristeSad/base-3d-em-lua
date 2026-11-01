-- Luanti legacy PseudoRandom exact regression vectors.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local PseudoRandom=require('core.pseudorandom')
local vectors={
 [0]={0,21469,9989,22118,3498,16928,16045,19742},
 [1]={16838,5759,10113,17516,31052,5628,23011,7420},
 [42]={19082,17034,15270,25462,13857,1094,13678,26501},
 [-1]={15930,4409,9862,26719,8713,28227,9081,32064},
 [12345]={21469,9989,22118,3498,16928,16045,19742,12123},
}
for seed,expected in pairs(vectors) do
 local rng=PseudoRandom(seed)
 for i,v in ipairs(expected) do
  local got=rng:next()
  assert(got==v,('seed %s step %d expected %d got %d')
   :format(seed,i,v,got))
 end
end
local r=PseudoRandom(42)
local snapshot=r:get_state()
local a=r:next()
r:set_state(snapshot)
assert(r:next()==a,'get/set_state must replay exact sequence')
local bounded=PseudoRandom(42)
for _=1,100 do
 local v=bounded:next(-100,100)
 assert(v>=-100 and v<=100)
end
assert(not pcall(function()r:next(20,10)end))
assert(not pcall(function()r:next(0,6554)end))
assert(not pcall(function()PseudoRandom(2147483648)end))
assert(not pcall(function()r:set_state(1.5)end))
print('lua_engine_pseudorandom: OK')
