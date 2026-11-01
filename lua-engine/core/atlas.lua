-- Expandable 4-column atlas layout shared with scripts/build_lua_engine_atlas.py.
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
 'mcl_core_water_source_animation.png',
 'default_wood.png',
 'mcl_core_gold_ore.png',
 'default_gravel.png',
 'flowers_dandelion_yellow.png',
 'default_glass.png',
 'default_ice.png',
 'mcl_core_lava_source_animation.png',
 'default_brick.png',
}
-- In the packaged LÖVR build this file is generated alongside the PNG.
-- Source-only API tests keep the small fixed atlas and its stable indices.
local loaded,manifest=pcall(require,'core.atlas_manifest')
if loaded then
 assert(type(manifest)=='table' and type(manifest.tiles)=='table' and
  type(manifest.columns)=='number' and
  manifest.columns>=1 and manifest.columns<=64 and
  #manifest.tiles>=#A.tiles,'invalid generated atlas manifest')
 for i,name in ipairs(A.tiles) do
  assert(manifest.tiles[i]==name,'generated atlas changed reserved tile order')
 end
 A.tiles=manifest.tiles
 A.columns=manifest.columns
elseif not tostring(manifest):find("module 'core.atlas_manifest' not found",1,true) then
 error(manifest)
else
 A.columns=4
end
A.rows=math.ceil(#A.tiles/A.columns)
local lookup={}
for i,name in ipairs(A.tiles) do lookup[name]=i end
function A.name(tile)
 if type(tile)=='table' then tile=tile.name end
 if type(tile)~='string' then return A.tiles[1] end
 -- Complex texture modifiers will require their own compositing stage.
 -- VoxeLibre's grass side is composed of the dirt base and a shadow
 -- overlay.  This atlas uses a representative combined placeholder.
 if tile:find('default_dirt.png^mcl_dirt_grass_shadow.png',1,true)==1 then
  return 'mcl_core_grass_block_side.png'
 end
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
 local insetU=.5/(A.columns*16)
 local insetV=.5/(A.rows*16)
 local u0=column/A.columns+insetU
 local v0=row/A.rows+insetV
 local u1=(column+1)/A.columns-insetU
 local v1=(row+1)/A.rows-insetV
 return u0,v0,u1,v1
end
return A
