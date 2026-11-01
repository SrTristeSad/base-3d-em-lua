-- Phase 67: scroll_container partial clipping via native LÖVR Pass:setScissor.
-- Luanti clips all child graphics to the scroll region; it must NOT
-- discard a child just because one corner is outside the viewport.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local View=require('core.formspecview')
local rt=Runtime.new()
rt.api.register_craftitem('probe:ore',{description='Ore',
 inventory_image='default_stone.png'})
local player={get_player_name=function() return 'Scroller' end}
assert(rt:connectPlayer(player,Physics.new(rt.api,{x=0,y=4,z=0})))
local inv=player:get_inventory()
inv:set_stack('main',1,'probe:ore 7')
local reports={}
rt.api.register_on_player_receive_fields(function(_,name,fields)
 reports[#reports+1]={name=name,fields=fields}
end)
local form='formspec_version[4]size[7,5]'..
 'scroll_container[1,1;2.5,1.4;choice;vertical;1]'..
 'image_button[0,1.1;1,1;default_stone.png;partial;Partial]'..
 'list[current_player;main;1.3,1.1;1,1;]'..
 'image[0,0;1,1;default_stone.png]'..
 'button[0,2.5;1,1;later;Later]'..
 'scroll_container_end[]'..
 'button[5,3;1,1;outside;Outside]'
assert(rt.api.show_formspec('Scroller','test:scroll_partial',form))
local view=View.new(rt,'Scroller')
local width,height=1067,781
local layout=assert(view:layout(width,height))
local clip=assert(layout.scrolls.choice.clip)
local controls={}
for _,ctl in ipairs(layout.controls) do
 if ctl.field then controls[ctl.field]=ctl end
 if ctl.kind=='slot' then controls.slot=ctl end
 if ctl.kind=='decoration' then controls.image=ctl end
end
local partial=assert(controls.partial)
local slot=assert(controls.slot)
local outside=assert(controls.outside)
assert(not controls.later,'fully offscreen button must be culled')
assert(partial.clip and slot.clip and controls.image.clip)
assert(not outside.clip,'unscrolled controls should not inherit clip')
assert(partial.y<clip.y+clip.h and
 partial.y+partial.h>clip.y+clip.h,
 'button must be kept even when lower half is clipped')
assert(slot.y<clip.y+clip.h and
 slot.y+slot.h>clip.y+clip.h,
 'inventory cells must support partial clipping')

local passed={}
local function check(ctl,x,y)
 return view:click(width,height,x,y,1)
end
local click_x=partial.x+partial.w/2
local exposed_y=clip.y+clip.h-3
assert(check(partial,click_x,exposed_y))
assert(reports[#reports].fields.partial=='true')
local before=#reports
-- Hit test must reject areas of the same element outside the clip.
local clicked,reason=check(partial,click_x,clip.y+clip.h+3)
assert(not clicked and reason=='outside_control')
assert(#reports==before)
-- Inventory click inside its visible sliver still operates on the real InvRef.
assert(check(slot,slot.x+slot.w/2,exposed_y))
assert(view.selected and view.selected.list=='main' and view.selected.index==1)
view.selected=nil
local hidden_click=check(slot,slot.x+slot.w/2,clip.y+clip.h+5)
assert(not hidden_click and view.selected==nil)

local old=_G.lovr
local images,bufs={},{}
local graphics={}
function graphics.newTexture(path)
 images[#images+1]=path
 return {path=path,release=function() end}
end
function graphics.newBuffer(_,vertices)
 bufs[#bufs+1]=vertices
 return {vertices=vertices,release=function()end}
end
local pass={calls={},clip=nil}
for _,method in ipairs({'push','pop','setViewPose','setProjection',
 'setDepthTest','setColor','setMaterial','text','plane','mesh'}) do
 pass[method]=function(self,...)
  local target={...}
  self.calls[#self.calls+1]={method=method,clip=self.clip,args=target}
 end
end
function pass:setScissor(...)
 local args={...}
 if #args==0 then
  self.clip=nil
  self.calls[#self.calls+1]={method='scissor_reset'}
 else
  assert(#args==4,'LÖVR Pass:setScissor expects x,y,w,h')
  assert(args[3]>0 and args[4]>0)
  self.clip=args
  self.calls[#self.calls+1]={method='scissor_set',clip=args}
 end
end
_G.lovr={math={newMat4=function()return {} end},graphics=graphics}
assert(view:draw(pass,width,height))
local sleft,stop=math.max(0,math.floor(clip.x)),
 math.max(0,math.floor(clip.y))
local sright=math.min(width,math.ceil(clip.x+clip.w))
local sbottom=math.min(height,math.ceil(clip.y+clip.h))
local set_count,reset_count,clipped_meshes,unclipped_planes=0,0,0,0
for _,cmd in ipairs(pass.calls) do
 if cmd.method=='scissor_set' then
  set_count=set_count+1
  local c=cmd.clip
  assert(c[1]==sleft and c[2]==stop and
   c[3]==sright-sleft and c[4]==sbottom-stop)
 elseif cmd.method=='scissor_reset' then
  reset_count=reset_count+1
 elseif cmd.method=='mesh' then
  if cmd.clip then clipped_meshes=clipped_meshes+1 end
 elseif cmd.method=='plane' and not cmd.clip then
  unclipped_planes=unclipped_planes+1
 end
end
assert(set_count==reset_count and set_count>=3,
 'one native scissor rectangle per visible scroll child')
assert(clipped_meshes>=3,
 'partial image, image button and inventory icon must render clipped')
assert(unclipped_planes>=2,'frame and external button remain unscissored')
assert(pass.clip==nil,'scissor must be reset after all scroll children')
assert(view.sprites and #bufs>=3)
-- Full geometry / UVs remain untouched; scissor clips fragments rather
-- than resampling source textures into cropped substitutes.
for _,verts in ipairs(bufs) do
 assert(#verts==6)
end
local previous_buffers=#bufs
pass.calls={}
assert(view:draw(pass,width,height))
assert(#bufs==previous_buffers,'same partial sprites reuse GPU buffers')
assert(pass.clip==nil)

-- Scrolling exposes the button that was previously fully outside the clip.
assert(view:wheel(width,height,clip.x+10,clip.y+10,-3))
assert(view.scrolls.choice>0)
layout=assert(view:layout(width,height))
controls={}
for _,ctl in ipairs(layout.controls) do
 if ctl.field then controls[ctl.field]=ctl end
end
assert(controls.later and controls.later.clip)
assert(not controls.partial,'original button becomes completely offscreen')
local later=controls.later
local cy=math.max(later.y,clip.y)+1
assert(cy<math.min(later.y+later.h,clip.y+clip.h))
assert(view:click(width,height,later.x+later.w/2,cy,1))
assert(reports[#reports].fields.later=='true')
pass.calls={}
assert(view:draw(pass,width,height))
assert(pass.clip==nil)
-- Source formspec callbacks and independent outside controls are unchanged.
assert(view:click(width,height,
 outside.x+outside.w/2,outside.y+outside.h/2,1))
assert(reports[#reports].fields.outside=='true')
view:release()
_G.lovr=old
assert(rt:disconnectPlayer('Scroller'))
print('LUA ENGINE PARTIAL SCROLL CONTAINER SCISSOR PASS')
