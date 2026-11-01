-- Luanti formspec lifecycle: actual host player, real field payloads.
-- Verify on both Lua 5.4 and LuaJIT. No GUI is simulated by these tests.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local Formspec=require('core.formspec')
local changes={}
local rt=Runtime.new({on_formspec_change=function(name,session)
 changes[#changes+1]={name=name,session=session}
end})
local api=rt.api
assert(api.show_formspec('Offline','test:form','size[3,2]')==false)
local host={name='Alice'}
function host:get_player_name() return self.name end
local controller=Physics.new(api,{x=0,y=4,z=0})
assert(rt:connectPlayer(host,controller)==host)
assert(host:get_meta():get_string('select')=='')
host:get_meta():set_string('select','mcl_core:stone')
assert(host:get_meta():get_string('select')=='mcl_core:stone')
host:get_meta():set_int('count',64)
assert(host:get_meta():get_int('count')==64)
local copy=host:get_meta():to_table()
copy.fields.count='999'
assert(host:get_meta():get_int('count')==64)
local stored=host:get_meta()
local source='formspec_version[4]size[5,3]'..
 'image_button[1,1;1,1;sheet.png^[verticalframe:3:1;pick;Pick]'..
 'field[0.5,1;3,1;entry;Label;This\\] is valid]'
local parsed,err=Formspec.parse(source)
assert(parsed and not err and #parsed==4)
assert(parsed[3].name=='image_button' and
 parsed[3].params:find('sheet.png^[verticalframe:3:1',1,true),
 'texture modifiers must not terminate the outer formspec element')
assert(parsed[4].params:find('This\\] is valid',1,true))
assert(not Formspec.parse('size[1,2'))
assert(api.show_formspec('Alice','test:form',source)==true)
local opened=rt:getPlayerFormspec('Alice')
assert(opened.formname=='test:form' and opened.formspec==source)
opened.elements[1].name='modified'
assert(rt:getPlayerFormspec('Alice').elements[1].name=='formspec_version',
 'session getter must not expose mutable internal objects')
assert(changes[#changes].session.formspec==source)
local hits={}
api.register_on_player_receive_fields(function(p,name,fields)
 hits[#hits+1]='older'
 assert(p==host and name=='test:form')
 assert(fields.entry=='value' and fields.pick=='Pick')
end)
api.register_on_player_receive_fields(function(p,name,fields)
 hits[#hits+1]='newer'
 assert(p==host and name=='test:form')
 assert(fields.entry=='value' and fields.pick=='Pick')
 return false
end)
local event={pick='Pick',entry='value'}
assert(rt:receiveFormFields('Alice','test:other',event)==false)
assert(#hits==0)
assert(rt:receiveFormFields('Alice','test:form',event))
assert(table.concat(hits,',')=='newer,older')
local stopped=0
api.register_on_player_receive_fields(function()
 stopped=stopped+1
 return true
end)
hits={}
assert(rt:receiveFormFields('Alice','test:form',event))
assert(stopped==1 and #hits==0,
 'latest callback returning true must suppress earlier callbacks')
-- Registered source fields always arrive as strings.
assert(not pcall(rt.receiveFormFields,rt,'Alice','test:form',{pick=true}))
assert(stopped==1)
assert(api.close_formspec('Alice','other:form')==false)
assert(rt:getPlayerFormspec('Alice').formname=='test:form')
-- Repeated show replaces the active session instead of stacking windows.
assert(api.show_formspec('Alice','test:updated','size[2,2]'))
assert(not rt:receiveFormFields('Alice','test:form',{quit='true'}))
assert(rt:getPlayerFormspec('Alice').formname=='test:updated')
local closes=0
api.register_on_player_receive_fields(function(p,formname,fields)
 if fields.quit then
  closes=closes+1
  assert(rt:getPlayerFormspec(p:get_player_name())==nil,
   'client quit must clear the active window before callback')
 end
 return true
end)
assert(rt:receiveFormFields('Alice','test:updated',{quit='true'}))
assert(closes==1 and rt:getPlayerFormspec('Alice')==nil)
assert(not rt:receiveFormFields('Alice','test:updated',{pick='Pick'}))
assert(api.show_formspec('Alice','','size[8,9]'))
assert(api.close_formspec('Alice','wrong')==false)
assert(api.close_formspec('Alice','')==true,
 'empty close_formspec formname must force-close active window')
assert(not api.close_formspec('Alice',''))

-- Server close must not fabricate a quit field event.
assert(closes==1)
assert(api.show_formspec('Alice','test:leave','size[1,1]'))
assert(rt:disconnectPlayer('Alice'))
assert(rt:getPlayerFormspec('Alice')==nil)
assert(changes[#changes].session==nil)
assert(host.get_meta==nil,'bridge must remove its injected player metadata method')
-- Runtime owns metadata by identity, which survives reconnect in this world.
rt:connectPlayer(host,Physics.new(api,{x=0,y=4,z=0}))
assert(host:get_meta()==stored and host:get_meta():get_int('count')==64)
assert(rt:disconnectPlayer('Alice'))
assert(api.show_formspec('Alice','test:late','size[1,1]')==false)
print('LUA ENGINE FORMSPEC SESSION AND PLAYER METADATA PASS')
