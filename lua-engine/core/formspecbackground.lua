-- Luanti GUIBackgroundImage auto_clip rectangle in source-space formspec pixels.
-- The original C++ implementation draws inside Parent->getAbsoluteClippingRect()
-- adjusted by autoclip_offset, without an additional GPU scissor.
-- Modern coordinates (formspec_version >= 2) INSET both sides for positive
-- X/Y; legacy coordinates extend both sides for positive pixel offsets.
local Background={}
local function finite(n)
 return type(n)=='number' and n==n and
  n~=math.huge and n~=-math.huge
end
function Background.auto_rect(layout,ox,oy,real_coordinates)
 if type(layout)~='table' or
  not finite(layout.x) or not finite(layout.y) or
  not finite(layout.w) or not finite(layout.h) or
  not finite(layout.unit) or layout.unit<=0 or
  layout.w<=0 or layout.h<=0 or
  not finite(ox) or not finite(oy) then
  return nil,'invalid_autoclip'
 end
 -- Original C++ real-coordinate path:
 --   pos = -getRealCoordinateBasePos(v_pos)
 --   rect.UpperLeftCorner -= pos; LowerRightCorner += pos
 -- Pixel-perfect conversion is approximated at this host's formspec unit.
 local px,py
 if real_coordinates then
  px,py=ox*layout.unit,oy*layout.unit
 else
  -- Legacy parser passes the numeric X/Y offsets directly in pixels.
  px,py=-ox,-oy
 end
 local w,h=layout.w-2*px,layout.h-2*py
 if not finite(w) or not finite(h) or w<=0 or h<=0 then
  return nil,'empty_autoclip'
 end
 return {x=layout.x+px,y=layout.y+py,w=w,h=h}
end
return Background
