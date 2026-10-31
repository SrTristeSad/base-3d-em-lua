-- Receitas reconstruídas para a Beta 1.8.1. Não usa arquivos Mojang.
-- A grade é normalizada para permitir mover padrões dentro de 2x2/3x3.
local C={}
local recipes={}
local function recipe(name,w,h,ingredients,output,count)
 assert(#ingredients==w*h)
 recipes[#recipes+1]={name=name,width=w,height=h,
   ingredients=ingredients,output=output,count=count or 1}
end
recipe('Tábuas',1,1,{4},7,4)
recipe('Gravetos',1,2,{7,7},280,4)
recipe('Bancada de trabalho',2,2,{7,7,7,7},50)
recipe('Tochas',1,2,{263,280},52,4)
recipe('Picareta de madeira',3,3,{7,7,7,0,280,0,0,280,0},270)
recipe('Picareta de pedra',3,3,{10,10,10,0,280,0,0,280,0},274)
recipe('Espada de madeira',1,3,{7,7,280},268)
recipe('Espada de pedra',1,3,{10,10,280},272)
recipe('Machado de madeira',2,3,{7,7,7,280,0,280},271)
recipe('Machado de pedra',2,3,{10,10,10,280,0,280},275)
recipe('Pá de madeira',1,3,{7,280,280},269)
recipe('Pá de pedra',1,3,{10,280,280},273)
recipe('Pá de ferro',1,3,{265,280,280},256)
recipe('Picareta de ferro',3,3,{265,265,265,0,280,0,0,280,0},257)
recipe('Picareta de diamante',3,3,{264,264,264,0,280,0,0,280,0},278)
recipe('Machado de ferro',2,3,{265,265,265,280,0,280},258)
recipe('Espada de ferro',1,3,{265,265,280},267)
recipe('Fornalha',3,3,{10,10,10,10,0,10,10,10,10},51)
recipe('Balde',3,2,{265,0,265,0,265,0},325)
recipe('Pão',3,1,{296,296,296},297)
C.recipes=recipes
function C.match(grid,width)
 if width~=2 and width~=3 then return nil end
 local minX,minY,maxX,maxY=width,width,-1,-1
 for i=1,width*width do
  local slot=grid[i]
  if slot and slot.id and slot.count and slot.count>0 then
   local x=(i-1)%width
   local y=math.floor((i-1)/width)
   minX,minY=math.min(minX,x),math.min(minY,y)
   maxX,maxY=math.max(maxX,x),math.max(maxY,y)
  end
 end
 if maxX<0 then return nil end
 local w,h=maxX-minX+1,maxY-minY+1
 for _,r in ipairs(recipes) do
  if r.width==w and r.height==h then
   local matches=true
   for dy=0,h-1 do for dx=0,w-1 do
    local slot=grid[(minY+dy)*width+minX+dx+1]
    if (slot and slot.id or 0)~=r.ingredients[dy*w+dx+1] then
     matches=false
     break
    end
   end if not matches then break end end
   if matches then return r end
  end
 end
 return nil
end
function C.consume(grid,width)
 local matched=C.match(grid,width)
 if not matched then return nil end
 for i=1,width*width do
  local slot=grid[i]
  if slot and slot.id and slot.count and slot.count>0 then
   slot.count=slot.count-1
   if slot.count<=0 then grid[i]=nil end
  end
 end
 return {id=matched.output,count=matched.count},matched
end
return C
