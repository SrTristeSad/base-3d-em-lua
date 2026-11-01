-- Phase 61: original-text formspec view/layout, LÖVR Pass and real input.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local View=require('core.formspecview')
local rt=Runtime.new()
local api=rt.api
api.register_craftitem('test:ore',{description='Raw Ore',stack_max=64})
api.register_craftitem('test:gem',{description='Gem',stack_max=64})
local player={get_player_name=function()return 'Artist' end}
rt:connectPlayer(player,Physics.new(api,{x=0,y=4,z=0}))
local inv=player:get_inventory()
inv:set_size('input',1)
inv:set_stack('main',1,'test:ore 7')
inv:set_stack('main',2,'test:gem 4')
local received={}
api.register_on_player_receive_fields(function(p,name,fields)
 assert(p==player)
 received[#received+1]={name=name,fields=fields}
end)
local events={}
api.register_on_player_inventory_action(function(_,action,_,info)
 events[#events+1]={action=action,info=info}
end)
local form='formspec_version[4]size[8,5]'..
 'label[0.5,0.3;Direct input from original engine]'..
 'list[current_player;main;0.5,1;2,1;]'..
 'list[current_player;input;5,1;1,1;]'..
 'item_image_button[2.5,3;1,1;test:gem;pick;]'..
 'button_exit[5,3;2,0.75;close;Close]'
assert(api.show_formspec('Artist','test:real',form))
local view=View.new(rt,'Artist')
local w,h=1100,780
local layout=view:layout(w,h)
assert(layout.formname=='test:real' and layout.unit>0)
local function find(kind,match)
 local l=assert(view:layout(w,h))
 for _,item in ipairs(l.controls) do
  if item.kind==kind and (not match or match(item)) then
   return item
  end
 end
 error('control not found: '..kind)
end
local function click(ctl,button)
 return view:click(w,h,ctl.x+ctl.w/2,ctl.y+ctl.h/2,button or 1)
end
local source=find('slot',function(c)return c.list=='main' and c.index==1 end)
local input=find('slot',function(c)return c.list=='input' end)
assert(click(source))
assert(click(input))
assert(inv:get_stack('main',1):is_empty())
assert(inv:get_stack('input',1):get_count()==7)
assert(#events==1 and events[1].action=='move')
-- Click source then right-click the destination: exactly one item.
assert(click(input))
assert(click(source,2))
assert(inv:get_stack('main',1):get_count()==1)
assert(inv:get_stack('input',1):get_count()==6)
local button=find('button',function(c)return c.field=='pick' end)
assert(click(button))
assert(#received==1 and received[1].name=='test:real')
assert(received[1].fields.pick=='true')
-- Swapping incompatible items is a supported movement, not a UI-only copy.
local gem=find('slot',function(c)return c.list=='main' and c.index==2 end)
assert(click(gem))
assert(click(input))
assert(inv:get_stack('input',1):get_name()=='test:gem')
assert(inv:get_stack('main',2):get_name()=='test:ore')
-- Original cursor selection is dropped when the server replaces formname.
assert(click(gem))
assert(view.selected~=nil)
assert(api.show_formspec('Artist','test:other','size[3,2]button[0,0;2,1;accept;Go]'))
assert(view:layout(w,h).formname=='test:other' and view.selected==nil)
assert(not view:click(w,h,-500,-500,1))
assert(view:close())
assert(received[#received].fields.quit=='true')
assert(view:layout(w,h)==nil)
-- Renderer draws the active text-only UI on a real LÖVR Pass contract.
assert(api.show_formspec('Artist','test:real',form))
local previous=_G.lovr
_G.lovr={math={newMat4=function()return {identity=true} end}}
local calls={}
local pass={}
for _,name in ipairs({'push','pop','setViewPose','setProjection',
 'setDepthTest','setMaterial','setColor','plane','text'}) do
 pass[name]=function(_,...)calls[#calls+1]={name=name,args={...}} end
end
assert(view:draw(pass,w,h))
_G.lovr=previous
assert(calls[1].name=='push' and calls[#calls].name=='pop')
local rendered_slots=0
for _,command in ipairs(calls) do
 if command.name=='plane' then rendered_slots=rendered_slots+1 end
end
assert(rendered_slots>=6,'must draw actual inventory and buttons')
local close=find('button',function(c)return c.field=='close' end)
assert(click(close))
assert(received[#received].fields.close=='true' and
 received[#received].fields.quit=='true')
assert(view:session()==nil)
-- Scrolled controls are visible and hittable only inside their source region.
local scroll_form='formspec_version[4]size[5,5]'..
 'scroll_container[1,1;1,2;choice;vertical;1]'..
 'button[0,0;1,1;one;One]'..
 'button[0,1;1,1;two;Two]'..
 'button[0,2;1,1;three;Three]'..
 'button[0,3;1,1;four;Four]'..
 'scroll_container_end[]'
assert(api.show_formspec('Artist','test:scroll',scroll_form))
local first=view:layout(w,h)
assert(first.scrolls.choice.max==2)
local function exists(name)
 for _,item in ipairs(view:layout(w,h).controls) do
  if item.kind=='button' and item.field==name then return item end
 end
 return nil
end
assert(exists('one') and exists('two'))
assert(not exists('four'))
local clip=first.scrolls.choice.clip
assert(view:wheel(w,h,clip.x+5,clip.y+5,-2))
assert(view.scrolls.choice==2)
assert(exists('three') and exists('four') and not exists('one'))
assert(click(exists('four')))
assert(received[#received].fields.four=='true')
assert(view:close())
assert(rt:disconnectPlayer('Artist'))
print('LUA ENGINE REAL FORMSPEC LÖVR VIEW PASS')
