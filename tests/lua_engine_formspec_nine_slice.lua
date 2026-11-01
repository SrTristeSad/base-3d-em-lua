-- Phase 65: genuine nine-slice, source-resolution PNG borders and buttons.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
package.preload['core.formspec_original_manifest']=function()
 return {
  ['mcl_inventory_background9.png']={width=32,height=32},
  ['mcl_inventory_button9_pressed.png']={width=32,height=20},
  ['mcl_stonecutter_saw.png']={width=16,height=48},
 }
end
local Nine=require('core.formspecnine')
local Sprites=require('core.formspecsprites')
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local View=require('core.formspecview')
local function eq(a,b,msg)
 assert(a==b,(msg or 'value')..': '..tostring(a)..' != '..tostring(b))
end
local src=assert(Sprites.source('mcl_inventory_background9.png'))
local m=assert(Nine.middle('2',32,32))
eq(m.x0,2);eq(m.y0,2);eq(m.x1,30);eq(m.y1,30)
m=assert(Nine.middle('3,5',32,32))
eq(m.x0,3);eq(m.y0,5);eq(m.x1,29);eq(m.y1,27)
m=assert(Nine.middle('4,6,-4,-6',32,32))
eq(m.x0,4);eq(m.y0,6);eq(m.x1,28);eq(m.y1,26)
m=assert(Nine.middle('2,3,24,21',32,32))
eq(m.x0,2);eq(m.y0,3);eq(m.x1,24);eq(m.y1,21)
for _,bad in ipairs({'','1,2,3','a,2','-1','30','2,-1',
 '4,0,4,5','2,2,-31,-2','2,2,33,29'}) do
 assert(not Nine.middle(bad,32,32),'must reject malformed middle '..bad)
end
local v=assert(Nine.vertices(src,100,100,150,90,'2,2'))
eq(#v,54,'nine patches of two triangles')
eq(v[1][1],25);eq(v[1][2],55)
eq(v[3][1],27);eq(v[3][2],57)
eq(v[1][7],0);eq(v[1][8],0)
eq(v[3][7],2/32);eq(v[3][8],2/32)
eq(v[49][1],173);eq(v[49][2],143)
eq(v[51][1],175);eq(v[51][2],145)
eq(v[51][7],1);eq(v[51][8],1)
-- Tiny GUI dimensions must compress the corners without reversing them.
local compact=assert(Nine.vertices(src,50,50,2,2,'6,6'))
eq(#compact,54)
for _,vertex in ipairs(compact) do
 assert(vertex[1]>=49 and vertex[1]<=51 and
  vertex[2]>=49 and vertex[2]<=51,
  'nine-slice borders must remain within tiny rect')
end
local frame=assert(Sprites.source('mcl_stonecutter_saw.png^[verticalframe:3:1'))
local segmented=assert(Nine.vertices(frame,20,20,80,70,'2,2'))
eq(#segmented,54)
assert(math.abs(segmented[1][8]-1/3)<1e-12)
assert(math.abs(segmented[#segmented][8]-2/3)<1e-12)
assert(not Nine.vertices(src,100,100,150,90,'80,80'))
assert(not Nine.vertices(assert(Sprites.source('default_stone.png')),
 100,100,80,50,'2,2'),
 'atlas texture does not retain original pixel width')
-- New formspec integration: original background9, image v6 middle and
-- styled item_image_button with bgimg_middle rather than flat rectangles.
local rt=Runtime.new()
rt.api.register_node('test:slate',{description='Slate',
 tiles={'default_stone.png'}})
local player={get_player_name=function()return 'NinePlayer' end}
assert(rt:connectPlayer(player,Physics.new(rt.api,{x=0,y=3,z=0})))
local events={}
rt.api.register_on_player_receive_fields(function(_,form,fields)
 events[#events+1]={form=form,fields=fields}
end)
local form='formspec_version[6]size[8,6]'..
 'background9[0,0;8,6;mcl_inventory_background9.png;false;4,4]'..
 'style_type[item_image_button;bgimg=mcl_inventory_background9.png;bgimg_middle=2,2]'..
 'style[chosen;bgimg=mcl_inventory_button9_pressed.png;bgimg_middle=2,2;border=false]'..
 'item_image_button[1,1;1,1;test:slate;chosen;]'..
 'item_image_button[2.5,1;1,1;test:slate;regular;]'..
 'image[4,1;2,2;mcl_inventory_background9.png;3,3]'..
 'button_exit[6,4;1,1;exit;Close]'
assert(rt.api.show_formspec('NinePlayer','test:nine',form))
local view=View.new(rt,'NinePlayer')
local w,h=1000,760
local layout=assert(view:layout(w,h))
local bg=nil
local decorations,buttons={},{}
for _,c in ipairs(layout.controls) do
 if c.kind=='decoration' then decorations[#decorations+1]=c end
 if c.kind=='button' then buttons[c.field]=c end
end
eq(#decorations,2)
eq(decorations[1].middle,'4,4')
eq(decorations[2].middle,'3,3')
assert(buttons.chosen and buttons.regular and buttons.exit)
eq(buttons.chosen.bgimg,'mcl_inventory_button9_pressed.png')
eq(buttons.chosen.bgimg_middle,'2,2')
eq(buttons.chosen.border,'false')
eq(buttons.regular.bgimg,'mcl_inventory_background9.png')
eq(buttons.regular.bgimg_middle,'2,2')
local old=_G.lovr
local allocated={},{}
local paths={}
local buffers={}
local graphics={}
function graphics.newBuffer(fmt,vertices)
 assert(#fmt==4)
 allocated[#allocated+1]=#vertices
 local handle={released=0}
 function handle:release()self.released=self.released+1 end
 buffers[#buffers+1]=handle
 return handle
end
function graphics.newTexture(path)
 paths[#paths+1]=path
 return {release=function()end}
end
local pass={draws=0}
for _,name in ipairs({'push','pop','setViewPose','setProjection',
 'setDepthTest','setMaterial','setColor','plane','text','mesh'}) do
 pass[name]=function(self,...)if name=='mesh' then self.draws=self.draws+1 end end
end
_G.lovr={math={newMat4=function()return {} end},graphics=graphics}
assert(view:draw(pass,w,h))
assert(pass.draws>=6,'backgrounds, button skins and item icons must render')
local nines=0
for _,count in ipairs(allocated) do if count==54 then nines=nines+1 end end
assert(nines>=4,'two image nine-slices and two styled buttons expected')
local before=#allocated
assert(view:draw(pass,w,h))
eq(#allocated,before,'reuse unchanged nine-slice vertex buffers')
local selected=buttons.chosen
assert(view:click(w,h,selected.x+selected.w/2,selected.y+selected.h/2,1))
eq(events[#events].fields.chosen,'true')
local exit=buttons.exit
assert(view:click(w,h,exit.x+exit.w/2,exit.y+exit.h/2,1))
assert(events[#events].fields.quit=='true')
assert(not view:session())
view:release()
_G.lovr=old
assert(rt:disconnectPlayer('NinePlayer'))
print('LUA ENGINE NINE SLICE FORMSPEC ORIGINAL GUI PASS')
