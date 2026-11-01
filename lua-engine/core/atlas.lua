-- Fixed 4x4 atlas layout shared with scripts/build_lua_engine_atlas.py.
-- These are texture identifiers, not copies of upstream images.
local A={}
A.tiles={
 'missing.png',
 'mcl_core_grass_block_top.png',
 'default_dirt.png',
 'default_stone.png',
 'default_sand.png',
 'default_cobble.png',
 'mcl_core_coal_ore.png',
 'mcl_core_iron_ore.png',
 'mcl_core_grass_block_side.png',
 'default_tree.png',
 'default_leaves.png',
 'default_water.png',
 'default_wood.png',
 'mcl_core_gold_ore.png',
 'default_gravel.png',
 'default_snow.png',
}
A.columns=4
local lookup={}
for i,name in ipairs(A.tiles) do lookup[name]=i end
function A.name(tile)
 if type(tile)=='table' then tile=tile.name end
 if type(tile)~='string' then return A.tiles[1] end
 -- Complex texture modifiers will require their own compositing stage.
 local simple=tile:match('^([^%^%[%:]+)')
 if not simple then return A.tiles[1] end
 return simple
end
function A.index(tile)
 return lookup[A.name(tile)] or 1
end
function A.uv(tile)
 local id=A.index(tile)-1
 local column,row=id%A.columns,math.floor(id/A.columns)
 -- half-pixel inset into the 16px tile to avoid atlas bleeding.
 local inset=.5/64
 local u0=column/4+inset
 local v0=row/4+inset
 local u1=(column+1)/4-inset
 local v1=(row+1)/4-inset
 return u0,v0,u1,v1
end
return A
