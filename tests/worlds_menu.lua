-- Criação Beta 1.8.1 sem opção de PNG/JPG; menus legados preservados.
package.path='./?.lua;./?/init.lua;'..package.path
local UI=require('src.ui')
local menu={name='',seed='',mode='survival',focus='seed',
  notice='',selected=nil,entries={},page=1}
local settings={fov=75,sensitivityLabel='MEDIA',distance=1,fullscreen=false}
local function buttons(state)
 local result={}
 for _,b in ipairs(UI.buttons(state,settings,1280,720,nil,menu)) do
  result[b.action]=b
 end
 return result
end
local title=buttons('title')
assert(title.create and title.worldlist and title.settings)
assert(not title.play)
menu.selected={name='Construido'}
assert(buttons('title').play)
local create=buttons('create')
for _,name in ipairs({'field:name','field:seed','newmode','create_world','title'}) do
 assert(create[name],'Campo de criação faltando: '..name)
end
assert(not create['field:image'] and not create.images and not create.demoimage)
assert(UI.click('create',settings,create['field:seed'].x,create['field:seed'].y,
  1280,720,nil,menu)=='field:seed')
menu.entries={{id=1,name='Meu mundo'},{id=2,name='Outro mundo'}}
assert(buttons('worldlist')['load:1'] and buttons('worldlist')['load:2'])
print('worlds_menu: OK')
