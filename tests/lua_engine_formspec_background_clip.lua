-- Phase 66: GUIBackgroundImage auto_clip semantics and background parent order.
-- Based on Luanti src/gui/guiFormSpecMenu.cpp parseBackground()
-- and src/gui/guiBackgroundImage.cpp draw().
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
package.preload['core.formspec_original_manifest']=function()
 return {['mcl_inventory_background9.png']={width=32,height=32}}
end
local Background=require('core.formspecbackground')
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local View=require('core.formspecview')
local function eq(a,b)
 assert(a==b,tostring(a)..' != '..tostring(b))
end
local function approx(a,b)
 assert(math.abs(a-b)<1e-8,tostring(a)..' != '..tostring(b))
end
local base={x=100,y=200,w=480,h=320,unit=40}
local rect=assert(Background.auto_rect(base,.5,1,true))
eq(rect.x,120);eq(rect.y,240);eq(rect.w,440);eq(rect.h,240)
local extended=assert(Background.auto_rect(base,-.5,-1,true))
eq(extended.x,80);eq(extended.y,160)
eq(extended.w,520);eq(extended.h,400)
local legacy=assert(Background.auto_rect(base,12,8,false))
eq(legacy.x,88);eq(legacy.y,192)
eq(legacy.w,504);eq(legacy.h,336)
assert(not Background.auto_rect(base,7,0,true))
assert(not Background.auto_rect(base,0/0,0,true))
assert(not Background.auto_rect(base,0,0/0,false))
assert(not Background.auto_rect({x=1,y=0,w=10,h=5,unit=0},0,0,true))
local rt=Runtime.new()
local p={get_player_name=function()return 'BackPlayer' end}
assert(rt:connectPlayer(p,Physics.new(rt.api,{x=0,y=5,z=0})))
local received={}
rt.api.register_on_player_receive_fields(function(_,form,fields)
 received[#received+1]={form=form,fields=fields}
end)
local view=View.new(rt,'BackPlayer')
local w,h=1100,800
local form='formspec_version[4]size[6,4]'..
 'button[1,1;2,1;go;Go]'..
 'background9[.5,.25;0,0;mcl_inventory_background9.png;true;4,4]'..
 'background[-.5,-.25;1,1;default_stone.png;true]'..
 'image[3,2;1,1;default_dirt.png]'
assert(rt.api.show_formspec('BackPlayer','test:back',form))
local l=assert(view:layout(w,h))
eq(#l.controls,4)
local button,rect9,rect2,image
for _,ctl in ipairs(l.controls) do
 if ctl.kind=='button' then button=ctl
 elseif ctl.texture=='mcl_inventory_background9.png' then rect9=ctl
 elseif ctl.texture=='default_stone.png' then rect2=ctl
 elseif ctl.texture=='default_dirt.png' then image=ctl end
end
assert(button and rect9 and rect2 and image)
assert(rect9.background and rect2.background)
assert(not image.background)
eq(rect9.middle,'4,4')
approx(rect9.x,l.x+.5*l.unit)
approx(rect9.y,l.y+.25*l.unit)
approx(rect9.w,l.w-l.unit)
approx(rect9.h,l.h-.5*l.unit)
approx(rect2.x,l.x-.5*l.unit)
approx(rect2.y,l.y-.25*l.unit)
approx(rect2.w,l.w+l.unit)
approx(rect2.h,l.h+.5*l.unit)
-- A background9 with W=H=0 is legal when auto_clip=true: the box
-- derives its dimensions from the containing form's clipping rectangle.
local old=_G.lovr
local texture_paths,geometry={},{}
local graphics={}
function graphics.newTexture(path)
 texture_paths[#texture_paths+1]=path
 return {path=path}
end
function graphics.newBuffer(fmt,vertices)
 geometry[#geometry+1]=vertices
 return {vertices=vertices,release=function()end}
end
local trace={}
local pass={material='none'}
for _,method in ipairs({'push','pop','setViewPose','setProjection',
 'setDepthTest','setColor','plane','text'}) do
 pass[method]=function(_,...)trace[#trace+1]=method end
end
function pass:setMaterial(tex)
 self.material=tex and tex.path or 'none'
end
function pass:mesh(buffer,...)
 trace[#trace+1]='mesh:'..self.material
end
_G.lovr={math={newMat4=function()return {} end},graphics=graphics}
assert(view:draw(pass,w,h))
-- background rendering in original Luanti is on a separate parent:
-- source order must not draw the button under the background.
local graphics_trace={}
for _,event in ipairs(trace) do
 if event:sub(1,5)=='mesh:' then
  graphics_trace[#graphics_trace+1]=event
 end
end
eq(#graphics_trace,3)
eq(graphics_trace[1],'mesh:visual/formspec/mcl_inventory_background9.png')
eq(graphics_trace[2],'mesh:visual/atlas.png')
eq(graphics_trace[3],'mesh:visual/atlas.png')
eq(#geometry[1],54)
assert(view:click(w,h,button.x+button.w/2,button.y+button.h/2,1))
eq(received[#received].fields.go,'true')
-- auto_clip=false uses requested XY/WH rather than full-parent bounds.
assert(rt.api.show_formspec('BackPlayer','test:normal',
 'formspec_version[4]size[6,4]'..
 'background9[.5,1;2,1;mcl_inventory_background9.png;false;4,4]'))
local normal=assert(view:layout(w,h))
local control=normal.controls[1]
approx(control.x,normal.x+.5*normal.unit)
approx(control.y,normal.y+normal.unit)
approx(control.w,2*normal.unit)
approx(control.h,normal.unit)
assert(control.background)
-- Luanti old coordinates interpret auto_clip offsets as pixels
-- and expand the parent rect, not as form units.
assert(rt.api.show_formspec('BackPlayer','test:legacy',
 'size[6,4]background[12,8;1,1;default_stone.png;true]'))
local legacy_layout=assert(view:layout(w,h))
local legacy_ctl=legacy_layout.controls[1]
approx(legacy_ctl.x,legacy_layout.x-12)
approx(legacy_ctl.y,legacy_layout.y-8)
approx(legacy_ctl.w,legacy_layout.w+24)
approx(legacy_ctl.h,legacy_layout.h+16)
-- An explicit real_coordinates[false] changes the interpretation
-- even in a modern form.
assert(rt.api.show_formspec('BackPlayer','test:override',
 'formspec_version[4]size[6,4]real_coordinates[false]'..
 'background[4,3;0,0;default_stone.png;true]'))
local over=assert(view:layout(w,h))
approx(over.controls[1].x,over.x-4)
approx(over.controls[1].w,over.w+8)
-- Invalid auto-clip rectangles are not emitted as corrupt GPU geometry.
assert(rt.api.show_formspec('BackPlayer','test:invalid',
 'formspec_version[4]size[6,4]'..
 'background[5,0;0,0;default_stone.png;true]'..
 'button[1,1;2,1;okay;OK]'))
local invalid=assert(view:layout(w,h))
eq(#invalid.controls,1)
eq(invalid.controls[1].kind,'button')
view:release()
_G.lovr=old
assert(rt:disconnectPlayer('BackPlayer'))
print('LUA ENGINE ORIGINAL FORMSPEC BACKGROUND AUTOCLIP PASS')
