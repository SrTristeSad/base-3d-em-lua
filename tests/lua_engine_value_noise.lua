-- Luanti 5.18 original noise.cpp regression, Lua 5.4 + LuaJIT.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Noise=require('core.valuenoise')
local Runtime=require('core.runtime')
local ModEnvironment=require('core.modenvironment')
local function near(x,y,epsilon)
 assert(type(x)=='number' and type(y)=='number' and
  math.abs(x-y)<=(epsilon or 1e-6),
  ('noise mismatch %.17g versus %.17g'):format(x,y))
end
-- Golden reference is upstream noise.cpp integer-lattice formula:
-- 1619*x+31337*y+52591*z+1013*seed; signed overflow masked
-- at 0x7fffffff, xorshift13, cubic polynomial with 60493/19990303.
local vectors={
 {0,0,0,0,-0.2817909838631749},
 {1,0,0,0,0.1717331623658538},
 {-1,-1,-1,1,-0.35694673750549555},
 {13,-23,19,42,0.836062484420836},
 {315,-58,217,-987,0.8341284869238734}
}
for _,v in ipairs(vectors) do
 near(Noise._lattice(v[1],v[2],v[3],v[4],true),v[5],1e-9)
end
local params={offset=0,scale=1,spread={x=1,y=1,z=1},
 seed=0,octaves=1,persist=.5,lacunarity=2,flags='defaults'}
local rt=Runtime.new({mapgen={seed=0}})
local api=rt.api
local p=api.get_value_noise(params)
near(p:get_3d({x=13,y=-23,z=19}),
 Noise._lattice(13,-23,19,0,true))
near(p:get_2d({x=1,y=0}),Noise._lattice(1,0,0,0,false))
assert(p.get2d==p.get_2d and p.get3d==p.get_3d)
local eased=p:get_2d({x=.25,y=.5})
local linearp=api.get_value_noise({offset=0,scale=1,
 spread={x=1,y=1,z=1},seed=0,octaves=1,persist=.5,
 flags='noeased'})
local linear=linearp:get_2d({x=.25,y=.5})
local expected=Noise._lattice(0,0,0,0,false)*.75*.5+
 Noise._lattice(1,0,0,0,false)*.25*.5+
 Noise._lattice(0,1,0,0,false)*.75*.5+
 Noise._lattice(1,1,0,0,false)*.25*.5
near(linear,expected)
assert(math.abs(eased-linear)>1e-4,'default 2D smoothing must use quintic ease')
local eased3d=api.get_value_noise({offset=0,scale=1,
 spread={x=1,y=1,z=1},seed=0,octaves=1,persist=.5,
 flags='eased'})
assert(math.abs(eased3d:get_3d({x=.25,y=.5,z=.7})-
 p:get_3d({x=.25,y=.5,z=.7}))>1e-4,
 'default 3D is linear, eased flag forces quintic interpolation')
local absparams={offset=3,scale=2,spread={x=8,y=8,z=8},
 seed=2,octaves=3,persist=.5,lacunarity=2,flags='absvalue'}
local v=api.get_value_noise(absparams):get_3d({x=2,y=5,z=-3})
assert(v>=3,'absvalue flag must apply before octave weighting')
assert(api.get_perlin==api.get_value_noise)
assert(api.get_perlin_map==api.get_value_noise_map)
local rt2=Runtime.new({mapgen={seed=984}})
local fromworld=rt2.api.get_value_noise(params)
local native=api.get_value_noise({offset=0,scale=1,
 spread={x=1,y=1,z=1},seed=984,octaves=1,persist=.5})
near(fromworld:get_3d({x=3,y=1,z=4}),native:get_3d({x=3,y=1,z=4}))
local legacy=rt2.api.get_perlin(0,1,.6,4)
assert(type(legacy:get_2d({x=2,y=3}))=='number')
near(legacy:get_2d({x=2,y=3}),
 rt2.api.get_value_noise({offset=0,scale=1,
 spread={x=4,y=4,z=4},seed=0,octaves=1,persist=.6}):get_2d({x=2,y=3}))
-- Map output must use x-fastest indexing, 2D y rows, 3D z/y/x.
local m=api.get_value_noise_map(params,{x=3,y=2,z=2})
local flat2=m:get_2d_map_flat({x=-1,y=1})
assert(#flat2==6)
local nested2=m:get_2d_map({x=-1,y=1})
for y=0,1 do for x=0,2 do
 local n=m:get_2d_map_flat({x=-1,y=1})
 near(flat2[y*3+x+1],nested2[y+1][x+1])
 near(flat2[y*3+x+1],p:get_2d({x=x-1,y=y+1}))
end end
local provided={}
assert(m:get_2d_map_flat({x=-1,y=1},provided)==provided)
assert(#provided==6)
local flat3=m:get_3d_map_flat({x=-1,y=1,z=-2})
assert(#flat3==12)
local nested3=m:get_3d_map({x=-1,y=1,z=-2})
for z=0,1 do for y=0,1 do for x=0,2 do
 local i=z*6+y*3+x+1
 near(flat3[i],nested3[z+1][y+1][x+1])
 near(flat3[i],p:get_3d({x=x-1,y=y+1,z=z-2}))
end end end
m:calc_3d_map({x=-1,y=1,z=-2})
local slice=m:get_map_slice({x=1,y=1,z=0},{x=2,y=1,z=2})
assert(#slice==4)
near(slice[1],flat3[5]);near(slice[2],flat3[6])
near(slice[3],flat3[11]);near(slice[4],flat3[12])
local into={}
assert(m:get_map_slice({x=0,y=0,z=0},{x=1,y=1,z=1},into)==into)
near(into[1],flat3[1])
assert(not pcall(m.get_map_slice,m,{x=3,y=0,z=0},{x=1,y=1,z=1}))
assert(not pcall(m.get_map_slice,m,{x=0,y=0,z=0},{x=1,y=0,z=1}))
local two=api.get_value_noise_map(params,{x=2,y=3})
assert(two:get_3d_map({x=0,y=0,z=0})==nil)
assert(two:get_3d_map_flat({x=0,y=0,z=0})==nil)
assert(two:calc_3d_map({x=0,y=0,z=0})==nil)
assert(two:get_2d_map({x=0,y=0})[3][2])
assert(not pcall(api.get_value_noise_map,params,{x=1000,y=1000,z=2}))
assert(not pcall(api.get_value_noise,{offset=0,scale=1,
 spread={x=1,y=1,z=1},seed=1,octaves=5}))
assert(not pcall(api.get_value_noise,{offset=0,scale=1,
 spread={x=-1,y=1,z=1},seed=1,octaves=1}))
assert(not pcall(api.get_value_noise,{offset=0,scale=1,
 spread={x=100,y=100,z=100},seed=1,octaves=1,flags='not-a-flag'}))
local globals={}
rt:installGlobals(globals)
assert(type(globals.ValueNoise)=='function' and type(globals.ValueNoiseMap)=='function')
assert(globals.PerlinNoise==globals.ValueNoise and
 globals.PerlinNoiseMap==globals.ValueNoiseMap)
near(globals.ValueNoise(params):get_2d({x=2,y=1}),p:get_2d({x=2,y=1}))
local modenv=ModEnvironment.new(rt)
assert(type(modenv.globals.ValueNoise)=='function' and
 type(modenv.globals.ValueNoiseMap)=='function')
near(modenv.globals.ValueNoise(params):get_2d({x=2,y=1}),p:get_2d({x=2,y=1}))
print('LUA ENGINE LUANTI 5.18 VALUE NOISE PASS')
