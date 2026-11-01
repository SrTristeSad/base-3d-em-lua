-- Phase 68: Luanti nested scroll_container movers and inherited clipping.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local View=require('core.formspecview')
local rt=Runtime.new()
rt.api.register_craftitem('probe:iron',{
 description='Iron',inventory_image='default_stone.png'})
local player={get_player_name=function()return 'Nester' end}
assert(rt:connectPlayer(player,Physics.new(rt.api,{x=0,y=4,z=0})))
player:get_inventory():set_stack('main',1,'probe:iron 3')
local events={}
rt.api.register_on_player_receive_fields(function(_,name,fields)
 events[#events+1]={name=name,fields=fields}
end)
local view=View.new(rt,'Nester')
local width,height=1100,800
local form='formspec_version[4]size[9,7]'..
 'scroll_container[1,1;4,3;outer;vertical;1;0.5]'..
 'scroll_container[0.5,1.9;3,1.5;inner;horizontal;1;0.25]'..
 'image_button[2.8,0.2;1,1;default_stone.png;inner_edge;Edge]'..
 'button[4.5,0.2;1,1;inner_later;Later]'..
 'list[current_player;main;0.3,0.1;1,1;]'..
 'image[0.1,0.95;1,1;default_stone.png]'..
 'scroll_container_end[]'..
 'button[0.3,2.8;1,1;outer_edge;Outer]'..
 'button[0.3,4.5;1,1;outer_later;Later]'..
 'scroll_container_end[]'..
 'button[7,2;1,1;plain;Outside]'
assert(rt.api.show_formspec('Nester','test:nested',form))
local layout=assert(view:layout(width,height))
local outer=assert(layout.scrolls.outer)
local inner=assert(layout.scrolls.inner)
assert(outer.depth==1 and inner.depth==2)
assert(outer.axis=='vertical' and inner.axis=='horizontal')
local function near(a,b)
 assert(math.abs(a-b)<1e-8,tostring(a)..' differs from '..tostring(b))
end
local function ctl(field)
 local current=assert(view:layout(width,height))
 for _,item in ipairs(current.controls) do
  if item.field==field then return item end
 end
 return nil
end
near(outer.clip.x,layout.x+layout.unit)
near(outer.clip.y,layout.y+layout.unit)
near(outer.clip.w,4*layout.unit)
near(outer.clip.h,3*layout.unit)
near(inner.viewport.x,outer.clip.x+.5*layout.unit)
near(inner.viewport.y,outer.clip.y+1.9*layout.unit)
near(inner.viewport.h,1.5*layout.unit)
near(inner.clip.h,1.1*layout.unit) -- cropped by outer viewport
near(inner.clip.x,inner.viewport.x)
near(inner.clip.w,3*layout.unit)
near(outer.max,3.0) -- outer bottom=5.5 plus padding .5 minus height 3
near(inner.max,2.75) -- right=5.5 plus padding .25 minus width 3
assert(ctl('inner_edge') and not ctl('inner_later'))
assert(ctl('outer_edge') and not ctl('outer_later'))
assert(ctl('plain') and not ctl('plain').clip)

local edge=ctl('inner_edge')
assert(edge.clip==nil or edge.clip.w==inner.clip.w)
local exposed_x=inner.clip.x+inner.clip.w-2
local y=inner.clip.y+0.5*layout.unit
assert(view:click(width,height,exposed_x,y,1))
assert(events[#events].fields.inner_edge=='true')
local count=#events
-- The button extends beyond the inner scroll viewport.
assert(not view:click(width,height,inner.clip.x+inner.clip.w+8,y,1))
assert(#events==count)
-- The inner viewport itself is partially hidden by the outer viewport.
local inner_image
local slot
for _,item in ipairs(layout.controls) do
 if item.kind=='decoration' and item.clip then inner_image=item end
 if item.kind=='slot' then slot=item end
end
assert(inner_image and slot and slot.clip)
assert(inner_image.y+inner_image.h>inner.clip.y+inner.clip.h)
assert(not view:click(width,height,inner_image.x+10,
 inner.clip.y+inner.clip.h+5,1))
assert(view:click(width,height,slot.x+slot.w/2,
 slot.y+slot.h/2,1))
assert(view.selected and view.selected.index==1)
view.selected=nil

local old=_G.lovr
local meshes,scissors={},{}
local graphics={}
function graphics.newTexture(path)return {path=path,release=function()end} end
function graphics.newBuffer(fmt,vertices)
 local b={vertices=vertices}
 function b:release() end
 return b
end
local pass={clip=nil,seen={}}
for _,method in ipairs({'push','pop','setViewPose','setProjection',
 'setDepthTest','setMaterial','setColor','plane','text','mesh'}) do
 pass[method]=function(self,...)
  self.seen[#self.seen+1]={method=method,clip=self.clip}
 end
end
function pass:setScissor(...)
 local a={...}
 if #a==0 then self.clip=nil else self.clip=a end
 scissors[#scissors+1]=self.clip or false
end
_G.lovr={math={newMat4=function()return {} end},graphics=graphics}
assert(view:draw(pass,width,height))
local inner_scissors,outer_scissors=0,0
for _,sc in ipairs(scissors) do
 if sc then
  if sc[1]==math.floor(inner.clip.x) and
   sc[2]==math.floor(inner.clip.y) and
   sc[3]==math.ceil(inner.clip.x+inner.clip.w)-math.floor(inner.clip.x) and
   sc[4]==math.ceil(inner.clip.y+inner.clip.h)-math.floor(inner.clip.y) then
   inner_scissors=inner_scissors+1
  elseif sc[1]==math.floor(outer.clip.x) and
   sc[2]==math.floor(outer.clip.y) then
   outer_scissors=outer_scissors+1
  end
 end
end
assert(inner_scissors>=3,'nested children use intersection scissor')
assert(outer_scissors>=1,'outer controls use their own scissor')
assert(pass.clip==nil,'no scissor state leaks out of the formspec')
local last_scissors=#scissors

-- Wheel events first reach the deepest scroll window.
assert(view:wheel(width,height,exposed_x,y,-2))
near(view.scrolls.inner,2)
near(view.scrolls.outer,0)
local now=assert(view:layout(width,height))
assert(ctl('inner_later'),'horizontal scrolling exposes new child')
-- Explicit content padding is included in the supported scroll extent.
assert(view:wheel(width,height,exposed_x,y,-5))
near(view.scrolls.inner,2.75)
-- At the horizontal limit, the wheel bubbles into the enclosing vertical.
assert(view:wheel(width,height,exposed_x,y,-1))
near(view.scrolls.outer,1)
-- Moving an ancestor shifts a nested viewport in screen coordinates.
local moved=assert(view:layout(width,height))
near(moved.scrolls.inner.viewport.y,inner.viewport.y-layout.unit)
-- Inner scrolling does not alter a control outside both scroll containers.
local plain=assert(ctl('plain'))
near(plain.x,layout.x+7*layout.unit)
near(plain.y,layout.y+2*layout.unit)
assert(view:click(width,height,
 plain.x+plain.w/2,plain.y+plain.h/2,1))
assert(events[#events].fields.plain=='true')
-- The outer viewport scrolls independently when the pointer isn't in inner.
local ox=outer.clip.x+3.8*layout.unit
local oy=outer.clip.y+0.2*layout.unit
assert(view:wheel(width,height,ox,oy,-1))
near(view.scrolls.outer,2)
near(view.scrolls.inner,2.75)
pass.seen={};scissors={}
assert(view:draw(pass,width,height))
assert(pass.clip==nil)
assert(#scissors>0)
assert(last_scissors>0)

-- Reopening a new formspec resets both independent scroll offsets.
assert(rt.api.show_formspec('Nester','test:reset',
 'formspec_version[4]size[4,4]button[0,0;1,1;hello;Hi]'))
assert(view:layout(width,height))
assert(next(view.scrolls)==nil)
view:release()
_G.lovr=old
assert(rt:disconnectPlayer('Nester'))
print('LUA ENGINE NESTED HORIZONTAL/VERTICAL SCROLL CLIPPING PASS')
