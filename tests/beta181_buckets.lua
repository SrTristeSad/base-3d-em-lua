-- Fase 11: receita, coleta e despejo de baldes com saves antigos.
package.path='./?.lua;./?/init.lua;'..package.path
local files={}
lovr={filesystem={
 read=function(p) return files[p] end,
 write=function(p,s) files[p]=s;return true end,
 isFile=function(p) return files[p]~=nil end,
 createDirectory=function() return true end
}}
local World=require('src.world')
local Beta=require('src.beta181_items')
local Recipes=require('src.beta181_crafting')
local Buckets=require('src.beta181_buckets')
local function eq(a,b,why)
 assert(a==b,(why or 'valor')..' esperado '..tostring(b)..
   ' obtido '..tostring(a))
end
local inv=Beta.new('survival')
for i=1,3 do assert(inv:grant(325,1)) end
eq(inv:count(325),3)
for i=1,3 do eq(inv.slots[i].count,1,'baldes nao empilham') end
assert(not inv:replaceBucket(1,326,325),'tipo incorreto nao troca')
assert(not inv:replaceBucket(1,325,3),'outro item nao e balde')
assert(inv:replaceBucket(1,325,326))
eq(inv:getSlot(1).id,326)
eq(inv:getSlot(2).id,325)
assert(inv:replaceBucket(1,326,325))
local craft=Beta.new('survival')
-- Ferro em V na grade 3x3, normalizado em 3x2.
craft.craft3[1]={id=265,count=1}
craft.craft3[3]={id=265,count=1}
craft.craft3[5]={id=265,count=1}
eq(craft:preview('table').id,325,'receita balde')
eq(craft:preview('small'),nil,'nao cabe no 2x2')
assert(craft:takeOutput('table',false))
eq(craft.cursor.id,325)
eq(craft.cursor.count,1)
eq(craft.craft3[1],nil)
eq(craft.craft3[3],nil)
eq(craft.craft3[5],nil)
local opts={generatorVersion='beta181',seed='phase11-bucket',
 savePath='worlds/phase11.sav'}
local w=World.new(opts)
local p={selected=1,x=0,y=124,z=0,
 eye=function() return 0,124,0 end,
 direction=function() return 0,0,1 end}
local stock=Beta.new('survival')
stock.slots[1]={id=325,count=1}
-- Inicialmente, um balde vazio nao tem liquido para coletar.
local handled,success=Buckets.use(w,p,stock)
eq(handled,true)
eq(success,false)
eq(stock:getSlot(1).id,325)
-- Colocar fonte de agua no mundo e usar o balde vazio.
assert(w:set(0,124,3,9))
handled,success=Buckets.use(w,p,stock)
assert(handled and success,'coletar fonte de agua')
eq(stock:getSlot(1).id,326,'balde de agua apos coleta')
eq(w:get(0,124,3),0,'fonte removida do mundo')
-- Contra bloco solido, despeja no ar imediatamente anterior.
assert(w:set(0,124,4,3))
handled,success=Buckets.use(w,p,stock)
assert(handled and success,'despejar agua no espaco livre')
eq(w:get(0,124,3),9)
eq(stock:getSlot(1).id,325,'balde vazio apos despejo')
eq(w.fluids:get(0,124,3),nil,'balde cria fonte')
assert(w.fluids:pendingCount()>0,'agua reativa simulação')
-- Nao recolher fluxo em vez de fonte.
assert(w:set(0,124,3,0))
assert(w:set(0,124,3,9,{level=2,falling=false}))
handled,success=Buckets.use(w,p,stock)
assert(handled and not success,'corrente nao e fonte')
eq(stock:getSlot(1).id,325)
eq(w:get(0,124,3),9,'corrente preservada')
-- Nao deve atravessar paredes para coletar fonte atras.
assert(w:set(0,124,3,3))
assert(w:set(0,124,5,9))
handled,success=Buckets.use(w,p,stock)
assert(handled and not success,'bloqueado por parede')
eq(w:get(0,124,5),9)
-- Teste de fonte de lava: coleta e despejo.
assert(w:set(0,124,3,29))
handled,success=Buckets.use(w,p,stock)
assert(handled and success,'coleta de lava')
eq(stock:getSlot(1).id,327)
eq(w:get(0,124,3),0)
handled,success=Buckets.use(w,p,stock)
assert(handled and success,'despeja lava')
eq(w:get(0,124,3),29)
eq(stock:getSlot(1).id,325)
-- Balde cheio nao sobrescreve fluido existente nem pedra.
stock.slots[1]={id=326,count=1}
handled,success=Buckets.use(w,p,stock)
assert(handled and not success,'sem sobrescrever lava')
eq(stock:getSlot(1).id,326)
eq(w:get(0,124,3),29)
-- Obstaculo com espaco anterior dentro do jogador nao permite despejo.
assert(w:set(0,124,3,0))
p.z=3
handled,success=Buckets.use(w,p,stock)
assert(handled and not success,'nao colocar fonte no proprio corpo')
eq(stock:getSlot(1).id,326)
p.z=0
-- Contagem unstackable, cursor e inventario cheio.
local full=Beta.new('survival')
for i=1,36 do full.slots[i]={id=325,count=1} end
eq(full:capacity(325),0)
assert(not full:grant(325,1),'sem espaco')
eq(full:count(325),36)
local over=Beta.new('creative')
-- Em criativo, balde de agua/lava e reutilizavel e nao altera slots.
assert(w:set(0,124,3,0))
handled,success=Buckets.use(w,p,over,{326})
assert(handled and success)
eq(w:get(0,124,3),9)
eq(over:getSlot(1),nil)
local previous=w:get(0,124,3)
handled,success=Buckets.use(w,p,over,{326})
assert(handled and not success)
eq(w:get(0,124,3),previous)
-- Save e load com baldes cheios, receita e blocos fluidos.
stock.slots[1]={id=327,count=1}
assert(w:save({x=0,y=85,z=0,yaw=0,pitch=0},stock))
local loaded=World.new(opts)
eq(loaded.savedSlots[1].id,327,'item salvo')
eq(loaded:get(0,124,3),9,'bloco salvo')
local recovered=Beta.new('survival',{slots=loaded.savedSlots})
eq(recovered:getSlot(1).id,327)
-- Classic: baldes nao interceptam uso; comportamento anterior segue.
local old=World.new({generatorVersion='classic030',seed='classic11'})
handled,success=Buckets.use(old,p,stock)
eq(handled,false)
eq(success,false)
print('beta181_buckets: OK')
