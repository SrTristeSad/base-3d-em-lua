-- Phase 69: upstream scrollbaroptions, scrollbar[] values and linked mover.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Bar=require('core.formspecscrollbar')
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local View=require('core.formspecview')
local function eq(a,b)
 assert(a==b,tostring(a)..' ~= '..tostring(b))
end
local function near(a,b)
 assert(math.abs(a-b)<1e-8,tostring(a)..' ~= '..tostring(b))
end
local defaults=Bar.defaults()
eq(defaults.min,0);eq(defaults.max,1000)
eq(defaults.smallstep,10);eq(defaults.largestep,100)
eq(defaults.thumbsize,1);eq(defaults.arrows,'default')
local opts=Bar.options(defaults,{'min=4','max=80','smallstep=5',
 'largestep=12','thumbsize=8','arrows=hide'})
eq(opts.min,4);eq(opts.max,80);eq(opts.smallstep,5)
eq(opts.largestep,12);eq(opts.thumbsize,8);eq(opts.arrows,'hide')
local invalid=Bar.options(opts,{'smallstep=-1','largestep=-2',
 'thumbsize=0','min=xyz','arrows=bananas'})
eq(invalid.smallstep,10);eq(invalid.largestep,100)
eq(invalid.thumbsize,1);eq(invalid.min,4)
eq(invalid.arrows,'hide')
eq(Bar.range(opts,4,1.5,.5,.1),0)
local amin,amax=Bar.range(opts,4,1.5,.5,.1)
eq(amin,0);eq(amax,30)
eq(select(2,Bar.range(opts,4,1.5,nil,.1)),80)
eq(Bar.clamp(150,4,80),80)
eq(Bar.clamp(-20,4,80),4)
eq(Bar.track({x=0,y=0,w=100,h=200},'horizontal',50,4,80),42)
eq(Bar.event(42,true),'CHG:42')
eq(Bar.event(42,false),'VAL:42')
local rt=Runtime.new()
local player={get_player_name=function()return 'Scrollbars' end}
assert(rt:connectPlayer(player,Physics.new(rt.api,{x=0,y=5,z=0})))
local received={}
rt.api.register_on_player_receive_fields(function(_,form,fields)
 received[#received+1]={form=form,fields=fields}
end)
local form='formspec_version[4]size[9,7]'..
 'scroll_container[.5,.5;2,1.5;v;vertical;.1;.5]'..
 'button[0,1;1,1;top;Top]'..
 'button[0,3;1,1;below;Below]'..
 'scroll_container_end[]'..
 'scrollbaroptions[min=4;max=80;smallstep=5;largestep=12;thumbsize=8;arrows=hide]'..
 'scrollbar[3,.5;.4,1.5;vertical;v;10]'..
 'scroll_container[4,1;2,1.5;h;horizontal;.1]'..
 'button[0,0;1,1;left;Left]'..
 'button[2.5,0;1,1;right;Right]'..
 'scroll_container_end[]'..
 'scrollbaroptions[min=2;max=40;smallstep=3;arrows=show]'..
 'scrollbar[4,3;2,.4;horizontal;h;6]'..
 'button[6,4;1,1;apply;Apply]'
assert(rt.api.show_formspec('Scrollbars','test:bars',form))
local view=View.new(rt,'Scrollbars')
local W,H=1100,810
local function find(kind,field)
 local layout=assert(view:layout(W,H))
 for _,ctl in ipairs(layout.controls) do
  if ctl.kind==kind and ctl.field==field then return ctl end
 end
 return nil
end
local l=assert(view:layout(W,H))
eq(view.scrollbar_values.v,10)
eq(view.scrollbar_values.h,6)
eq(l.scrolls.v.bar.max,30)
eq(l.scrolls.v.bar.min,0)
eq(l.scrolls.h.bar.min,2)
eq(l.scrolls.h.bar.max,40)
local v=assert(find('scrollbar','v'))
local h=assert(find('scrollbar','h'))
eq(v.value,10);eq(v.min,0);eq(v.max,30)
eq(h.value,6);eq(h.min,2);eq(h.max,40)
eq(v.options.thumbsize,8);eq(h.options.arrows,'show')
local top=assert(find('button','top'))
near(top.y,l.scrolls.v.viewport.y+(1-10*.1)*l.unit)
local left=assert(find('button','left'))
near(left.x,l.scrolls.h.viewport.x-6*.1*l.unit)
local values=view:form_values()
eq(values.v,'VAL:10');eq(values.h,'VAL:6')
-- Native wheel over content follows the scrollbar's smallstep in raw
-- integer units; the linked scroll_container then applies its factor.
local vp=l.scrolls.v.clip
assert(view:wheel(W,H,vp.x+5,vp.y+5,-1))
eq(view.scrollbar_values.v,15)
eq(received[#received].fields.v,'CHG:15')
eq(received[#received].fields.h,'VAL:6')
l=view:layout(W,H)
top=assert(find('button','top'))
near(top.y,l.scrolls.v.viewport.y+(1-15*.1)*l.unit)
local hvp=l.scrolls.h.clip
assert(view:wheel(W,H,hvp.x+5,hvp.y+5,-1))
eq(view.scrollbar_values.h,9)
eq(received[#received].fields.h,'CHG:9')
eq(received[#received].fields.v,'VAL:15')
l=view:layout(W,H)
left=assert(find('button','left'))
near(left.x,l.scrolls.h.viewport.x-9*.1*l.unit)
-- Clicking the track changes its position, preserving field semantics.
h=assert(find('scrollbar','h'))
assert(view:click(W,H,h.x+h.w*.75,h.y+h.h/2,1))
eq(view.scrollbar_values.h,31)
eq(received[#received].fields.h,'CHG:31')
eq(received[#received].fields.v,'VAL:15')
v=assert(find('scrollbar','v'))
assert(view:click(W,H,v.x+v.w/2,v.y+v.h,1))
eq(view.scrollbar_values.v,30)
eq(received[#received].fields.v,'CHG:30')
assert(not view:wheel(W,H,vp.x+5,vp.y+5,-1),
 'wheel at dynamic max does not send extra changed events')
assert(not view:scrollbarChange('v',30))
assert(not view:scrollbarChange('unknown',12))
assert(not view:scrollbarChange('h',0/0))
-- A regular button sends the current positions as VAL, never CHG.
local apply=assert(find('button','apply'))
assert(view:click(W,H,apply.x+apply.w/2,apply.y+apply.h/2,1))
eq(received[#received].fields.apply,'true')
eq(received[#received].fields.v,'VAL:30')
eq(received[#received].fields.h,'VAL:31')

local previous=_G.lovr
local pass={clip=nil,thumbs=0,scissors=0}
local graphics={}
function graphics.newTexture(path)return {path=path,release=function()end}end
function graphics.newBuffer(_,vertices)
 return {vertices=vertices,release=function()end}
end
for _,k in ipairs({'push','pop','setViewPose','setProjection','setDepthTest',
 'setMaterial','setColor','text','mesh'}) do
 pass[k]=function()end
end
function pass:plane(...)self.thumbs=self.thumbs+1 end
function pass:setScissor(...)
 local a={...}
 self.clip=#a>0 and a or nil
 if #a>0 then self.scissors=self.scissors+1 end
end
_G.lovr={math={newMat4=function()return {} end},graphics=graphics}
assert(view:draw(pass,W,H))
assert(pass.thumbs>=5,'two track + thumb pairs and background')
assert(pass.clip==nil)
assert(pass.scissors>=1,'scroll container still clips contents')
view:release()
_G.lovr=previous
-- Form replacement resets independent scrollbar value caches.
assert(rt.api.show_formspec('Scrollbars','test:new',
 'formspec_version[4]size[4,3]button[0,0;1,1;okay;OK]'))
assert(view:layout(W,H))
assert(next(view.scrollbar_values)==nil)
assert(rt:disconnectPlayer('Scrollbars'))
print('LUA ENGINE ORIGINAL SCROLLBAR CHG VAL AND OPTIONS PASS')
