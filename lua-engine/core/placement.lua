-- Node placement orientation from Luanti builtin/game/item.lua.
-- Pure Lua and LuaJIT compatible.  Does not attempt client prediction.
local Placement={}
local abs,floor=math.abs,math.floor
local function check_dir(d)
 assert(type(d)=='table' and type(d.x)=='number' and
  type(d.y)=='number' and type(d.z)=='number','direction vector required')
end
-- Matches core.dir_to_wallmounted: direction is under - above.
function Placement.dir_to_wallmounted(dir)
 check_dir(dir)
 local x,y,z=abs(dir.x),abs(dir.y),abs(dir.z)
 if y>=x and y>=z then return dir.y>=0 and 0 or 1 end
 if x>=z then return dir.x>=0 and 2 or 3 end
 return dir.z>=0 and 4 or 5
end
-- Horizontal facedir, as used by the builtin item's default placement.
-- The 6d version is deliberately not claimed until separately ported.
function Placement.dir_to_facedir(dir)
 check_dir(dir)
 if abs(dir.x)>abs(dir.z) then
  return dir.x<0 and 3 or 1
 end
 return dir.z<0 and 2 or 0
end
function Placement.dir_to_fourdir(dir)
 return Placement.dir_to_facedir(dir)
end
local divisor={
 color=1,colorwallmounted=8,colorfacedir=32,
 color4dir=4,colordegrotate=32
}
local function valid_param2(v)
 assert(type(v)=='number' and v==floor(v) and v>=0 and
  v<=255, 'param2 must be an integer in [0,255]')
 return v
end
-- Pointed thing's above (not replaceable destination) is used for facedir.
function Placement.param2(def,stack,player,pointed,explicit)
 assert(type(def)=='table' and type(pointed)=='table' and
  type(pointed.under)=='table' and type(pointed.above)=='table',
  'invalid node placement')
 local param=explicit or 0
 if def.place_param2~=nil then
  param=def.place_param2
 elseif explicit==nil then
  local kind=def.paramtype2
  if kind=='wallmounted' or kind=='colorwallmounted' then
   local d={x=pointed.under.x-pointed.above.x,
    y=pointed.under.y-pointed.above.y,
    z=pointed.under.z-pointed.above.z}
   param=Placement.dir_to_wallmounted(d)
   -- 6/7 rotated ceiling/floor modes depend on placer position.
   if def.wallmounted_rotate_vertical and (param==0 or param==1) and
     player and type(player.get_pos)=='function' then
    local pos=player:get_pos()
    if pos then
     local px,pz=pointed.above.x-pos.x,pointed.above.z-pos.z
     local rotate=false
     if def.drawtype=='torchlike' then
      rotate=not ((px<0 and pz>0) or (px>0 and pz<0))
      if d.y>0 then rotate=not rotate end
     elseif def.drawtype=='signlike' then
      rotate=abs(px)<abs(pz)
     else
      rotate=abs(px)>abs(pz)
     end
     if rotate then param=param+6 end
    end
   end
  elseif kind=='facedir' or kind=='colorfacedir' or
         kind=='4dir' or kind=='color4dir' then
   if player and type(player.get_pos)=='function' then
    local pos=player:get_pos()
    if pos then
     param=Placement.dir_to_facedir({
      x=pointed.above.x-pos.x,
      y=pointed.above.y-pos.y,
      z=pointed.above.z-pos.z
     })
    end
   end
  end
 end
 valid_param2(param)
 local div=divisor[def.paramtype2]
 if div and def.place_param2==nil then
  local palette=stack:get_meta():get_string('palette_index')
  if palette~='' then
   local index=tonumber(palette)
   if index and index==floor(index) and index>=0 then
    param=(floor(index/div)*div+param%div)%256
   end
  end
 end
 return valid_param2(param)
end
return Placement
