-- Phase 62: real host-side formspec text input, checkboxes and dropdowns.
-- Verify original Luanti field names and values in callbacks on Lua 5.4/JIT.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local View=require('core.formspecview')
local rt=Runtime.new()
local api=rt.api
local player={get_player_name=function()return 'Editor' end}
assert(rt:connectPlayer(player,Physics.new(api,{x=0,y=4,z=0})))
local view=View.new(rt,'Editor')
local w,h=1120,790
local reports={}
api.register_on_player_receive_fields(function(p,form,fields)
 assert(p==player)
 reports[#reports+1]={form=form,fields=fields}
end)
local function control(kind,name)
 local layout=assert(view:layout(w,h))
 for _,c in ipairs(layout.controls) do
  if c.kind==kind and c.field==name then return c end
 end
 error('control not found '..kind..' '..name)
end
local function click(ctl)
 return view:click(w,h,ctl.x+ctl.w/2,ctl.y+ctl.h/2,1)
end
local form='formspec_version[4]size[9,7]'..
 'field[.5,.7;4,.7;title;Title;default]'..
 'field_close_on_enter[title;false]'..
 'textarea[.5,2;4,1.3;notes;Notes;line one]'..
 'checkbox[.5,4;safe;Safe;false]'..
 'dropdown[4.8,.7;3,.75;mode;First,Second\\,Plus,Third;1;false]'..
 'dropdown[4.8,2;3,.75;level;Small,Medium,Large;2;true]'..
 'button[4.8,4;2,.75;apply;Apply]'..
 'button_exit[4.8,5;2,.75;close;Close]'
assert(api.show_formspec('Editor','test:input',form))
local layout=assert(view:layout(w,h))
assert(layout.unit>0 and #layout.controls==8)
assert(view.values.title=='default' and view.values.notes=='line one')
assert(view.values.safe=='false' and view.values.mode==1)
assert(view.values.level==2)
assert(view:textinput('x')==false,'unfocused text must not be inserted')
assert(click(control('field','title')))
assert(view.focus=='title')
-- UTF-8 backspace removes one codepoint, never a byte fragment.
assert(view:textinput(' ç'))
assert(view.values.title=='default ç')
assert(view:keypressed('backspace'))
assert(view.values.title=='default ')
assert(view:textinput('OK'))
assert(view.values.title=='default OK')
assert(view:keypressed('return'))
assert(reports[#reports].form=='test:input')
assert(reports[#reports].fields.key_enter_field=='title')
assert(reports[#reports].fields.title=='default OK')
assert(not reports[#reports].fields.quit,
 'field_close_on_enter=false must keep original formspec active')
assert(view:session())
assert(click(control('field','notes')))
assert(view:textinput('\nline two'))
assert(view:keypressed('return'),'Enter inserts newline in textarea')
assert(view.values.notes=='line one\nline two\n')
assert(click(control('checkbox','safe')))
assert(reports[#reports].fields.safe=='true')
assert(click(control('dropdown','mode')))
assert(view.values.mode==2)
assert(reports[#reports].fields.mode=='Second,Plus',
 'dropdown value should unescape escaped commas')
assert(click(control('dropdown','level')))
assert(view.values.level==3)
assert(reports[#reports].fields.level=='3',
 'dropdown with index_event sends selected index, not label')
assert(click(control('button','apply')))
local event=reports[#reports].fields
assert(event.apply=='true' and event.title=='default OK')
assert(event.notes=='line one\nline two\n')
assert(event.safe=='true' and event.mode=='Second,Plus')
assert(event.level=='3')
assert(view:session() and view.values.title=='default OK',
 'non-exit button must not reset client edits')
-- Changing the actual server-authored formspec discards unsent values.
assert(api.show_formspec('Editor','test:input',
 'formspec_version[4]size[4,2]field[0,0;2,.7;title;Title;fresh]'..
 'field[0,1;2,.7;password;Password;secret]'))
assert(view:layout(w,h))
assert(view.values.title=='fresh' and view.values.password=='secret')
assert(click(control('field','title')))
assert(view:keypressed('return'))
assert(reports[#reports].fields.key_enter_field=='title')
assert(reports[#reports].fields.quit=='true')
assert(view:session()==nil)
-- Password field should be masked when displayed, while submit retains value.
assert(api.show_formspec('Editor','test:pwd',
 'formspec_version[4]size[5,3]pwdfield[0.5,0.8;3,1;secret;Password]'..
 'button_exit[.5,2;2,.7;close;Done]'))
assert(view:layout(w,h))
assert(click(control('field','secret')))
assert(view:textinput('not-a-plain-label'))
local prior=_G.lovr
_G.lovr={math={newMat4=function()return {} end}}
local displayed={}
local pass={}
for _,name in ipairs({'push','pop','setViewPose','setProjection',
 'setDepthTest','setMaterial','setColor','plane','text'}) do
 pass[name]=function(_,...)if name=='text' then
  displayed[#displayed+1]=tostring((...)) end
 end
end
assert(view:draw(pass,w,h))
_G.lovr=prior
assert(not table.concat(displayed,';'):find('not-a-plain-label',1,true),
 'password text should not be visible in LÖVR draw pass')
assert(click(control('button','close')))
assert(reports[#reports].fields.secret=='not-a-plain-label')
assert(reports[#reports].fields.quit=='true')
assert(view:session()==nil)
assert(rt:disconnectPlayer('Editor'))
print('LUA ENGINE FORMSPEC TEXT AND CHOICE CONTROLS PASS')
