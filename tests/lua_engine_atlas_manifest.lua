-- Stress-test the atlas loader without loading thousands of PNGs in Lua tests.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local source=require('core.atlas')
assert(#source.tiles==20 and source.columns==4 and source.rows==5)
local base=source.tiles
package.loaded['core.atlas']=nil
package.preload['core.atlas_manifest']=function()
 local names={}
 for i,name in ipairs(base) do names[i]=name end
 for i=21,2900 do names[i]='fixture_'..i..'.png' end
 return {columns=64,tiles=names}
end
local atlas=require('core.atlas')
assert(#atlas.tiles==2900 and atlas.columns==64 and atlas.rows==46)
assert(atlas.index('default_stone.png')==4,'old tile indices changed')
assert(atlas.index('fixture_21.png')==21)
assert(atlas.index('fixture_2900.png')==2900)
assert(atlas.index('not-a-real-texture.png')==1)
local u0,v0,u1,v1=atlas.uv('fixture_2900.png')
assert(u0>=0 and u0<u1 and u1<=1)
assert(v0>=0 and v0<v1 and v1<=1)
local index=atlas.index('fixture_2900.png')-1
local col,row=index%64,math.floor(index/64)
assert(u0>col/64 and u1<(col+1)/64)
assert(v0>row/46 and v1<(row+1)/46)
assert(atlas.index('default_dirt.png^mcl_dirt_grass_shadow.png')==9)
-- A malformed packaged index must fail loudly; never show unrelated textures.
package.loaded['core.atlas']=nil
package.loaded['core.atlas_manifest']=nil
package.preload['core.atlas_manifest']=function()
 return {columns=64,tiles={'wrong.png'}}
end
assert(not pcall(require,'core.atlas'),'mismatched atlas index must be rejected')
print('LUA ENGINE FULL ATLAS INDEX PASS')
