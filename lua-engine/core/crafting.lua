-- Subset of Luanti's craft registry and get_craft_result.
-- Shaped, shapeless, cooking, fuel and toolrepair; groups and replacements.
-- Unsupported recipes fail explicitly. Item stacks always have value semantics.
local Stack=require('core.itemstack')
local Craft={}
Craft.__index=Craft
local function copy(t)
 local out={}
 for k,v in pairs(t or {}) do out[k]=v end
 return out
end
local function row_value(row,x)
 return type(row)=='table' and row[x] or nil
end
local function make_stack(value,registry)
 return Stack.new(value,registry)
end
local function nonempty(stack)
 return not stack:is_empty()
end
local function predicate(ingredient,stack,items,aliases)
 if type(ingredient)~='string' or ingredient=='' then
  return not nonempty(stack),false
 end
 if not nonempty(stack) then return false,false end
 if ingredient:sub(1,6)=='group:' then
  local def=items[stack:get_name()]
  if not def or type(def.groups)~='table' then return false,true end
  for group in ingredient:sub(7):gmatch('[^,]+') do
   if (def.groups[group] or 0)<=0 then return false,true end
  end
  return true,true
 end
 local seen={}
 while aliases[ingredient] and not seen[ingredient] do
  seen[ingredient]=true
  ingredient=aliases[ingredient]
 end
 return ingredient==stack:get_name(),false
end
local function normalized_shape(rows)
 assert(type(rows)=='table' and #rows>0,'shaped recipe requires rows')
 local width=0
 for _,row in ipairs(rows) do
  assert(type(row)=='table','shaped recipe rows must be tables')
  width=math.max(width,#row)
 end
 assert(width>0,'empty shaped recipe')
 local minx,miny,maxx,maxy=width,#rows,0,0
 for y,row in ipairs(rows) do for x=1,width do
  local a=row_value(row,x)
  if a and a~='' then
   assert(type(a)=='string','recipe ingredient must be a string')
   minx,miny=math.min(minx,x),math.min(miny,y)
   maxx,maxy=math.max(maxx,x),math.max(maxy,y)
  end
 end end
 assert(maxx>0,'empty shaped recipe')
 local cells={}
 for y=miny,maxy do for x=minx,maxx do
  cells[#cells+1]=row_value(rows[y],x) or ''
 end end
 return {width=maxx-minx+1,height=maxy-miny+1,cells=cells}
end
local function normalized_input(input,registry)
 assert(type(input)=='table','craft input required')
 local method=input.method or 'normal'
 assert(method=='normal' or method=='cooking' or method=='fuel',
  'invalid craft method')
 local width=input.width or 0
 assert(type(width)=='number' and width%1==0 and width>=0
  and width<=16,'invalid craft width')
 local slots={}
 local source=input.items or {}
 assert(type(source)=='table' and #source<=256,'invalid craft items')
 local count=0
 for i=1,#source do
  slots[i]=make_stack(source[i],registry)
  if nonempty(slots[i]) then count=count+1 end
 end
 return method,width,slots,count
end
local function dimensions(items,width)
 if width<=0 then return nil end
 local minx,miny,maxx,maxy=width,math.huge,0,0
 for i,stack in ipairs(items) do
  if nonempty(stack) then
   local x=(i-1)%width+1
   local y=math.floor((i-1)/width)+1
   minx,miny=math.min(minx,x),math.min(miny,y)
   maxx,maxy=math.max(maxx,x),math.max(maxy,y)
  end
 end
 if maxx==0 then return nil end
 local cells={}
 for y=miny,maxy do for x=minx,maxx do
  local i=(y-1)*width+x
  cells[#cells+1]=items[i] or make_stack()
 end end
 return {width=maxx-minx+1,height=maxy-miny+1,cells=cells,
  left=minx,top=miny}
end
local function match_shaped(recipe,grid,items,aliases)
 if not grid or recipe.shape.width~=grid.width or
  recipe.shape.height~=grid.height then return nil end
 local positions={}
 for i,expected in ipairs(recipe.shape.cells) do
  local actual=grid.cells[i]
  local ok=predicate(expected,actual,items,aliases)
  if not ok then return nil end
  if expected~='' then
   local x=(i-1)%grid.width+grid.left
   local y=math.floor((i-1)/grid.width)+grid.top
   positions[#positions+1]=(y-1)*grid.input_width+x
  end
 end
 return positions
end
local function match_shapeless(recipe,slots,items,aliases,count)
 if #recipe.ingredients~=count then return nil end
 local indexes={}
 for i,stack in ipairs(slots) do
  if nonempty(stack) then indexes[#indexes+1]=i end
 end
 local used={}
 local result={}
 local function solve(n)
  if n>#recipe.ingredients then return true end
  for _,i in ipairs(indexes) do
   if not used[i] and predicate(recipe.ingredients[n],slots[i],items,aliases) then
    used[i]=true
    result[n]=i
    if solve(n+1) then return true end
    used[i]=nil
   end
  end
  return false
 end
 if solve(1) then return result end
end
local function match_single(recipe,slots,count,items,aliases)
 if count~=1 then return nil end
 for i,stack in ipairs(slots) do
  if nonempty(stack) and predicate(recipe.ingredient,stack,items,aliases) then
   return {i}
  end
 end
end
local function matches(recipe,method,width,slots,count,items,aliases)
 if recipe.kind=='toolrepair' or recipe.method~=method then return nil end
 if method~='normal' then
  return match_single(recipe,slots,count,items,aliases)
 end
 if recipe.kind=='shapeless' then
  return match_shapeless(recipe,slots,items,aliases,count)
 end
 local grid=dimensions(slots,width)
 if not grid then return nil end
 grid.input_width=width
 return match_shaped(recipe,grid,items,aliases)
end
local function priority(recipe)
 return (recipe.kind=='shaped' and 2 or 1)*10000-
  recipe.group_count*100
end
function Craft.new(items,aliases)
 return setmetatable({items=items or {},aliases=aliases or {},
  recipes={},serial=0},Craft)
end
function Craft:register(def)
 assert(type(def)=='table','craft definition required')
 local kind=def.type or 'shaped'
 assert(kind=='shaped' or kind=='shapeless' or
  kind=='cooking' or kind=='fuel' or kind=='toolrepair','unsupported craft type: '..tostring(kind))
 if kind=='toolrepair' then
  local additional=def.additional_wear or 0
  assert(type(additional)=='number' and additional==additional
   and additional~=math.huge and additional~=-math.huge,
   'toolrepair additional_wear must be finite')
  self.serial=self.serial+1
  local recipe={kind='toolrepair',method='normal',output='',
   additional_wear=additional,order=self.serial}
  self.toolrepair=recipe
  self.recipes[#self.recipes+1]=recipe
  return recipe
 end
 local method=(kind=='cooking' or kind=='fuel') and kind or 'normal'
 local shape,ingredients,ingredient
 if kind=='shaped' then shape=normalized_shape(def.recipe)
 elseif kind=='shapeless' then
  assert(type(def.recipe)=='table' and #def.recipe>0,
   'shapeless recipe needs ingredients')
  ingredients={}
  for _,name in ipairs(def.recipe) do
   assert(type(name)=='string' and name~='','empty shapeless ingredient')
   ingredients[#ingredients+1]=name
  end
 else
  assert(type(def.recipe)=='string' and def.recipe~='',
   'fuel/cooking recipe needs an item')
  ingredient=def.recipe
 end
 local groups=0
 local function count_groups(name)
  if type(name)=='string' and name:sub(1,6)=='group:' then
   groups=groups+1
  end
 end
 if shape then for _,a in ipairs(shape.cells) do count_groups(a) end
 elseif ingredients then for _,a in ipairs(ingredients) do count_groups(a) end
 else count_groups(ingredient) end
 local output=def.output or ''
 if kind~='fuel' then
  assert(type(output)=='string' and output~='',
   'craft output required')
  assert(nonempty(make_stack(output,self.items)),'empty craft output')
 end
 local replacements={}
 for _,pair in ipairs(def.replacements or {}) do
  assert(type(pair)=='table' and type(pair[1])=='string'
   and type(pair[2])=='string','invalid replacements')
  replacements[#replacements+1]={pair[1],pair[2]}
 end
 self.serial=self.serial+1
 local recipe={kind=kind,method=method,shape=shape,
  ingredients=ingredients,ingredient=ingredient,output=output,
  cooktime=def.cooktime or 3,burntime=def.burntime or 1,
  group_count=groups,order=self.serial,
  replacements=replacements}
 assert(recipe.cooktime>0 and recipe.burntime>0,'invalid craft timing')
 self.recipes[#self.recipes+1]=recipe
 return recipe
end
local function output_recipe(recipe)
 if recipe.kind=='shaped' then
  return {method='normal',width=recipe.shape.width,
   items=copy(recipe.shape.cells),output=recipe.output}
 elseif recipe.kind=='shapeless' then
  return {method='normal',width=0,items=copy(recipe.ingredients),
   output=recipe.output}
 end
 return {method=recipe.method,width=0,items={recipe.ingredient},
  output=recipe.output}
end
function Craft:all_for(output)
 local list={}
 for _,r in ipairs(self.recipes) do
  if r.output~='' and make_stack(r.output,self.items):get_name()==output then
   list[#list+1]=output_recipe(r)
  end
 end
 return #list>0 and list or nil
end
function Craft:one_for(output)
 local list=self:all_for(output)
 return list and list[#list] or {items=nil,width=0}
end
function Craft:result(input)
 local method,width,slots,count=normalized_input(input,self.items)
 local original={}
 for i,s in ipairs(slots) do original[i]=s:copy() end
 local output={item=make_stack(nil,self.items),time=0,replacements={}}
 local change={method=method,width=width,items=original}
 if count==0 then return output,change end
 local winner,where,score
 for _,recipe in ipairs(self.recipes) do
  local indexes=matches(recipe,method,width,slots,count,self.items,self.aliases)
  if indexes then
   local rank=priority(recipe)
   if not winner or rank>score then
    winner,where,score=recipe,indexes,rank
   end
  end
 end
 if not winner then
  if method=='normal' and self.toolrepair and count==2 then
   local indexes={}
   for i,stack in ipairs(slots) do
    if nonempty(stack) then indexes[#indexes+1]=i end
   end
   local a,b=slots[indexes[1]],slots[indexes[2]]
   local def=a and self.items[a:get_name()]
   if a and b and a:get_name()==b:get_name() and
    def and def.type=='tool' and
    (not def.groups or def.groups.disable_repair~=1) and
    a:get_count()==1 and b:get_count()==1 then
    -- Luanti wear units range from 0 to 65535.  Repair bonus is a
    -- fraction of 65536; negative additional_wear improves durability.
    local wear=math.floor(a:get_wear()+b:get_wear()-65536+
     self.toolrepair.additional_wear*65536+0.5)
    if wear<65536 then
     output.item=make_stack({name=a:get_name(),count=1,
      wear=math.max(0,wear)},self.items)
     change.items[indexes[1]]:take_item(1)
     change.items[indexes[2]]:take_item(1)
    end
   end
  end
  return output,change
 end
 if winner.method~='fuel' then
  output.item=make_stack(winner.output,self.items)
 end
 if method=='cooking' then output.time=winner.cooktime end
 if method=='fuel' then output.time=winner.burntime end
 for _,i in ipairs(where) do
  local consumed=change.items[i]:take_item(1)
  for _,pair in ipairs(winner.replacements) do
   if consumed:get_name()==pair[1] then
    local replacement=make_stack(pair[2],self.items)
    if change.items[i]:is_empty() then
     change.items[i]=replacement
    else
     output.replacements[#output.replacements+1]=replacement
    end
    break
   end
  end
 end
 return output,change
end
-- Non-Luanti convenience: atomic single-craft transfer between InvRef lists.
-- Refuses to consume inputs unless both result and overflow replacements fit.
function Craft:take(inventory,gridlist,outlist,method)
 local width=inventory:get_width(gridlist)
 local before=inventory:get_list(gridlist)
 local destination=inventory:get_list(outlist)
 if not before or not destination then return false,'missing list' end
 local result,changed=self:result({
  method=method or 'normal',width=width,items=before})
 if result.item:is_empty() then return false,'no recipe' end
 local simulate=require('core.inventory').new(self.items)
 simulate:set_list(outlist,destination)
 if not simulate:add_item(outlist,result.item):is_empty() then
  return false,'output full'
 end
 for _,replacement in ipairs(result.replacements) do
  if not simulate:add_item(outlist,replacement):is_empty() then
   return false,'replacements full'
  end
 end
 inventory:set_list(gridlist,changed.items)
 inventory:set_list(outlist,simulate:get_list(outlist))
 return true,result.item
end
return Craft
