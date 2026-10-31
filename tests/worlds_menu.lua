-- Verifica os botoes do menu de criar/carregar sem abrir janela GPU.
package.path='./?.lua;./?/init.lua;'..package.path
local UI=require('src.ui')
local menu={name='',seed='',image='',mode='survival',focus='seed',
  notice='',selected=nil,entries={},page=1,images={},imagePage=1}
local settings={fov=75,sensitivityLabel='MEDIA',distance=1,fullscreen=false}
local function indexButtons(state)
 local result={}
 for _,b in ipairs(UI.buttons(state,settings,1280,720,nil,menu)) do
  result[b.action]=b
 end
 return result
end
local title=indexButtons('title')
assert(title.create and title.worldlist and title.settings,'Pagina inicial incompleta')
assert(not title.play,'Nao pode continuar se nao existe mundo')
menu.selected={name='Construido'}
assert(indexButtons('title').play)
local b=indexButtons('create')
for _,name in ipairs({'field:name','field:seed','field:image','images',
 'demoimage','newmode','create_world','title'}) do
 assert(b[name],'Campo do criador ausente: '..name)
end
assert(UI.click('create',settings,b['field:seed'].x,b['field:seed'].y,
  1280,720,nil,menu)=='field:seed')
menu.images={'foto de familia.png','minha imagem.jpg'}
local images=indexButtons('imagelist')
assert(images['pickimage:foto de familia.png'])
assert(images.backcreate)
menu.entries={{id=1,name='Meu mundo'},{id=2,name='Outro mundo'}}
assert(indexButtons('worldlist')['load:1'])
assert(indexButtons('worldlist')['load:2'])
print('worlds_menu: OK')
