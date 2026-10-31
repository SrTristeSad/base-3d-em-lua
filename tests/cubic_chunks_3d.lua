-- Cubic Chunks: 16x16x16, descarregamento vertical, vizinhos e persistencia.
package.path='./?.lua;./?/init.lua;'..package.path
local saved
lovr={filesystem={read=function() return saved end,
  write=function(_,text) saved=text; return true end}}
local World=require('src.world')
local w=World.new()
assert(w.CHUNK==16 and w.YMIN==-32 and w.YMAX==63)
assert(w:cacheCount()==0)
local a=w:get(0,0,0)
local b=w:get(0,-1,0)
local c=w:get(0,17,0)
assert(type(a)=='number' and type(b)=='number' and c==0)
assert(w.cache['0:0:0'] and w.cache['0:-1:0'] and w.cache['0:1:0'],
 'Camadas verticais devem ter cache independente')
assert(not w.cache['0:2:0'])
local before=w:cacheCount()
assert(w:get(0,45,0)==0)
assert(w.cache['0:2:0'] and w:cacheCount()==before+1,
 'Blocos altos precisam carregar seções novas')
assert(w:set(0,45,0,7))
assert(w.dirty['0:2:0'])
assert(w:get(0,45,0)==7)
assert(w:set(0,15,0,7))
assert(w.dirty['0:0:0'] and w.dirty['0:1:0'],
 'Alterar uma borda vertical precisa remalhar ambas as seções')
assert(w:set(0,-16,0,7))
assert(w.dirty['0:-1:0'] and w.dirty['0:-2:0'])
assert(w:get(0,-16,0)==7)
local ground=w:spawnHeight(0,0)
local actor={x=0,y=ground,z=0,yaw=0,pitch=0}
assert(w:save(actor))
w:prune(0,0,0,1,0)
assert(not w.cache['0:2:0'] and not w.cache['0:-2:0'],
 'Secoes verticais fora de alcance nao foram descarregadas')
assert(w:get(0,45,0)==7 and w:get(0,-16,0)==7,
 'Regeneracao precisa restaurar edicoes de outras camadas')
local fresh=World.new()
assert(fresh.savedPlayer and fresh:get(0,45,0)==7 and fresh:get(0,-16,0)==7,
 'Save precisa manter a coordenada Y sem projetar em coluna')
assert(fresh:get(0,15,0)==7)
assert(not fresh:set(0,64,0,7) and not fresh:set(0,-33,0,7),
 'Protecao de limites verticais falhou')
print('cubic_chunks_3d: OK')
