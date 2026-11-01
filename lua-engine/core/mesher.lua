-- CPU-side visible-face mesher for 16^3 mapblocks. Pure Lua; no LÖVR.
-- Cube, simple liquid/glass and crossed plantlike meshes. Source node definitions
-- (including mcl_core) provide tiles and drawtype; no name-based geometry.
local Atlas=require('core.atlas')
local Nodebox=require('core.nodebox')
local M={}
local floor=math.floor
M.size=16
-- Top, bottom, right, left, front (+Z), back (-Z).
local faces={
 {n={0,1,0},tile=1,shade=1,
  corners={{-.5,.5,-.5},{-.5,.5,.5},{.5,.5,.5},{.5,.5,-.5}}},
 {n={0,-1,0},tile=2,shade=.58,
  corners={{-.5,-.5,.5},{-.5,-.5,-.5},{.5,-.5,-.5},{.5,-.5,.5}}},
 {n={1,0,0},tile=3,shade=.82,
  corners={{.5,-.5,.5},{.5,-.5,-.5},{.5,.5,-.5},{.5,.5,.5}}},
 {n={-1,0,0},tile=4,shade=.76,
  corners={{-.5,-.5,-.5},{-.5,-.5,.5},{-.5,.5,.5},{-.5,.5,-.5}}},
 {n={0,0,1},tile=5,shade=.9,
  corners={{-.5,-.5,.5},{.5,-.5,.5},{.5,.5,.5},{-.5,.5,.5}}},
 {n={0,0,-1},tile=6,shade=.72,
  corners={{.5,-.5,-.5},{-.5,-.5,-.5},{-.5,.5,-.5},{.5,.5,-.5}}},
}
M.faces=faces
local function definition(registry,name)
 return registry and registry[name]
end
function M.is_cube(def)
 if type(def)~='table' then return false end
 local drawtype=def.drawtype or 'normal'
 return drawtype=='normal' or drawtype=='allfaces' or
  drawtype=='glasslike' or drawtype=='glasslike_framed' or
  drawtype=='glasslike_framed_optional' or drawtype=='liquid' or drawtype=='flowingliquid'
end
local function occludes(def)
 return M.is_cube(def) and (def.drawtype or 'normal')~='glasslike'
  and def.drawtype~='glasslike_framed'
  and def.drawtype~='glasslike_framed_optional'
  and def.drawtype~='liquid' and def.drawtype~='flowingliquid'
  and def.use_texture_alpha~='blend'
  and def.use_texture_alpha~='clip' and def.sunlight_propagates~=true
end
local cross_faces={
 {n={-.70710678,0,.70710678},tile=1,shade=1,
  corners={{-.5,-.5,-.5},{.5,-.5,.5},{.5,.5,.5},{-.5,.5,-.5}}},
 {n={.70710678,0,-.70710678},tile=1,shade=1,
  corners={{-.5,.5,-.5},{.5,.5,.5},{.5,-.5,.5},{-.5,-.5,-.5}}},
 {n={.70710678,0,.70710678},tile=1,shade=1,
  corners={{-.5,-.5,.5},{.5,-.5,-.5},{.5,.5,-.5},{-.5,.5,.5}}},
 {n={-.70710678,0,-.70710678},tile=1,shade=1,
  corners={{-.5,.5,.5},{.5,.5,-.5},{.5,-.5,-.5},{-.5,-.5,.5}}},
}
local function tile_for(def,index)
 local tiles=def.tiles
 if type(tiles)~='table' then return 'missing.png' end
 -- Luanti uses tile 1 for the top and 2 for the bottom, with 3-6 sides.
 return tiles[index] or tiles[3] or tiles[1] or 'missing.png'
end
function M.build(map,registry,cx,cy,cz)
 assert(type(cx)=='number' and cx==floor(cx) and
  type(cy)=='number' and cy==floor(cy) and
  type(cz)=='number' and cz==floor(cz),'invalid mapblock coordinates')
 assert(map and type(map.get_node)=='function','map required')
 local vertices={}
 local metrics={faces=0,cubes=0,nodeboxes=0,plants=0,liquids=0,skipped=0}
 local sx,sy,sz=cx*16,cy*16,cz*16
 local function emit(x,y,z,face,def)
  local u0,v0,u1,v1=Atlas.uv(tile_for(def,face.tile))
  -- One unindexed pair of triangles; the default LÖVR mesh mode is triangles.
  local uvs={{u0,v1},{u1,v1},{u1,v0},{u0,v0}}
  local order={1,2,3,1,3,4}
  for _,i in ipairs(order) do
   local p=face.corners[i]
   vertices[#vertices+1]={
    x+p[1],y+p[2],z+p[3],
    face.n[1],face.n[2],face.n[3],
    uvs[i][1],uvs[i][2],
    face.shade,face.shade,face.shade,1
   }
  end
  metrics.faces=metrics.faces+1
 end
 for x=sx,sx+15 do for y=sy,sy+15 do for z=sz,sz+15 do
  local node=map:get_node({x=x,y=y,z=z})
  if node.name~='air' and node.name~='ignore' then
   local def=definition(registry,node.name)
   if M.is_cube(def) then
    metrics.cubes=metrics.cubes+1
    local drawtype=def.drawtype or 'normal'
    local transparent=drawtype=='glasslike' or
     drawtype=='glasslike_framed' or
     drawtype=='glasslike_framed_optional' or
     drawtype=='liquid' or drawtype=='flowingliquid'
    if drawtype=='liquid' or drawtype=='flowingliquid' then
     metrics.liquids=metrics.liquids+1
    end
    for _,face in ipairs(faces) do
     local adjacent=map:get_node({
      x=x+face.n[1],y=y+face.n[2],z=z+face.n[3]})
     -- Avoid coplanar liquid/glass faces between two identical cells.
     if not occludes(definition(registry,adjacent.name)) and
      not (transparent and adjacent.name==node.name) then
      emit(x,y,z,face,def)
     end
    end
   elseif def and def.drawtype=='nodebox' then
    local parts=Nodebox.faces(def,node)
    if parts then
     metrics.nodeboxes=metrics.nodeboxes+1
     for _,face in ipairs(parts) do
      local axis=face.n[1]~=0 and 1 or face.n[2]~=0 and 2 or 3
      -- A solid neighboring cube only hides an exposed face when
      -- that face lies directly on the shared map-cell boundary.
      local boundary=true
      for _,p in ipairs(face.corners) do
       if math.abs(p[axis]-face.n[axis]*.5)>1e-8 then
        boundary=false
        break
       end
      end
      local hidden=false
      if boundary then
       local adjacent=map:get_node({
        x=x+face.n[1],y=y+face.n[2],z=z+face.n[3]})
       hidden=occludes(definition(registry,adjacent.name))
      end
      if not hidden then emit(x,y,z,face,def) end
     end
    else
     metrics.skipped=metrics.skipped+1
    end
   elseif def and def.drawtype=='plantlike' then
    -- Two diagonal crossed quads; both sides are wound outwards.
    metrics.plants=metrics.plants+1
    for _,face in ipairs(cross_faces) do emit(x,y,z,face,def) end
   else
    metrics.skipped=metrics.skipped+1
   end
  end
 end end end
 metrics.vertices=#vertices
 return vertices,metrics
end
-- Block boundary changes invalidate visible faces in both mapblocks.
function M.fingerprint(map,cx,cy,cz)
 local revisions=map.revisions or {}
 local function revision(x,y,z)
  return revisions[x..','..y..','..z] or 0
 end
 return table.concat({
  revision(cx,cy,cz),revision(cx-1,cy,cz),revision(cx+1,cy,cz),
  revision(cx,cy-1,cz),revision(cx,cy+1,cz),
  revision(cx,cy,cz-1),revision(cx,cy,cz+1)
 },':')
end
return M
