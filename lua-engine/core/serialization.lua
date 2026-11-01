-- Data-only Luanti-style Lua table serialization.
-- Never evaluates input as code. Supports scalars, nested tables and basic
-- escaped strings. Unsupported Lua source is rejected rather than executed.
local M={}
local MAX_LENGTH=1024*1024
local MAX_DEPTH=64
local MAX_ENTRIES=100000
local function number_ok(n)
 return n==n and n~=math.huge and n~=-math.huge
end
local function encode(value,depth,seen)
 assert(depth<=MAX_DEPTH,'serialization table nesting limit')
 local kind=type(value)
 if kind=='nil' then return 'nil' end
 if kind=='string' then return string.format('%q',value) end
 if kind=='number' then
  assert(number_ok(value),'nonfinite number cannot be serialized')
  return tostring(value)
 end
 if kind=='boolean' then return tostring(value) end
 assert(kind=='table','unsupported serialization type: '..kind)
 assert(not seen[value],'cyclic Lua table cannot be serialized')
 seen[value]=true
 local keys={}
 for k in pairs(value) do
  local kt=type(k)
  assert(kt=='string' or kt=='number' or kt=='boolean',
   'unsupported table key: '..kt)
  if kt=='number' then assert(number_ok(k),'nonfinite table key') end
  keys[#keys+1]=k
  assert(#keys<=MAX_ENTRIES,'too many table entries')
 end
 table.sort(keys,function(a,b)
  local x,y=type(a),type(b)
  if x~=y then return x<y end
  if x=='number' then return a<b end
  return tostring(a)<tostring(b)
 end)
 local parts={}
 for _,key in ipairs(keys) do
  parts[#parts+1]='['..encode(key,depth+1,seen)..']='..
   encode(value[key],depth+1,seen)
 end
 seen[value]=nil
 return '{'..table.concat(parts,',')..'}'
end
function M.serialize(value)
 local result='return '..encode(value,0,{})
 assert(#result<=MAX_LENGTH,'serialized value too large')
 return result
end

local function parse(source)
 assert(type(source)=='string' and #source<=MAX_LENGTH,'invalid input size')
 local pos,used=1,0
 local function peek() return source:sub(pos,pos) end
 local function spaces()
  while peek()~='' and peek():match('%s') do pos=pos+1 end
 end
 local function fail(msg) error('invalid serialized data: '..msg,0) end
 local function quoted()
  local quote=peek()
  pos=pos+1
  local out={}
  while true do
   local c=peek()
   if c=='' then fail('unterminated string') end
   if c==quote then pos=pos+1;return table.concat(out) end
   if c=='\n' or c=='\r' then fail('unescaped newline') end
   if c~='\\' then
    out[#out+1]=c
    pos=pos+1
   else
    pos=pos+1
    local escaped=peek()
    if escaped=='' then fail('trailing escape') end
    local map={a='\a',b='\b',f='\f',n='\n',r='\r',t='\t',v='\v',
     ['\\']='\\',['"']='"',["'"]="'",['\n']='\n'}
    if map[escaped] then
     out[#out+1]=map[escaped]
     pos=pos+1
    elseif escaped=='z' then
     pos=pos+1
     spaces()
    elseif escaped=='x' then
     local hex=source:sub(pos+1,pos+2)
     if not hex:match('^[%da-fA-F][%da-fA-F]$') then fail('invalid hex escape') end
     out[#out+1]=string.char(tonumber(hex,16))
     pos=pos+3
    elseif escaped:match('%d') then
     local digits=source:sub(pos):match('^%d%d?%d?')
     local n=tonumber(digits)
     if n>255 then fail('byte escape out of range') end
     out[#out+1]=string.char(n)
     pos=pos+#digits
    else
     fail('unsupported string escape')
    end
   end
  end
 end
 local parse_value
 local function table_value(depth)
  if depth>MAX_DEPTH then fail('nesting limit') end
  pos=pos+1
  local result={}
  local next_array=1
  spaces()
  while peek()~='}' do
   if peek()=='' then fail('missing table closing brace') end
   used=used+1
   if used>MAX_ENTRIES then fail('too many table entries') end
   local key,value
   if peek()=='[' then
    pos=pos+1
    key=parse_value(depth+1)
    spaces()
    if peek()~=']' then fail('missing table key bracket') end
    pos=pos+1
    spaces()
    if peek()~='=' then fail('missing table key assignment') end
    pos=pos+1
    value=parse_value(depth+1)
   else
    local ident=source:sub(pos):match('^([%a_][%w_]*)%s*=')
    if ident then
     key=ident
     pos=pos+#ident
     spaces()
     pos=pos+1
     value=parse_value(depth+1)
    else
     key=next_array
     next_array=next_array+1
     value=parse_value(depth+1)
    end
   end
   if type(key)=='table' or key==nil then fail('invalid table key') end
   result[key]=value
   spaces()
   if peek()==',' or peek()==';' then pos=pos+1;spaces()
   elseif peek()~='}' then fail('expected separator') end
  end
  pos=pos+1
  return result
 end
 function parse_value(depth)
  spaces()
  local c=peek()
  if c=='{' then return table_value(depth) end
  if c=='"' or c=="'" then return quoted() end
  if c=='' then fail('unexpected end') end
  local rest=source:sub(pos)
  local num=rest:match('^[+-]?0[xX][%da-fA-F]+')
   or rest:match('^[+-]?%d+%.?%d*[eE][+-]?%d+')
   or rest:match('^[+-]?%.%d+[eE][+-]?%d+')
   or rest:match('^[+-]?%d+%.?%d*')
   or rest:match('^[+-]?%.%d+')
  if num then
   local n=tonumber(num)
   if not n or not number_ok(n) then fail('invalid number') end
   pos=pos+#num
   return n
  end
  local word=rest:match('^[%a_][%w_]*')
  if word then
   pos=pos+#word
   if word=='nil' then return nil end
   if word=='true' then return true end
   if word=='false' then return false end
  end
  fail('unsupported expression')
 end
 spaces()
 local word=source:sub(pos):match('^[%a_][%w_]*')
 if word=='return' then pos=pos+6 end
 local result=parse_value(0)
 spaces()
 if peek()==';' then pos=pos+1;spaces() end
 if pos<=#source then fail('trailing input') end
 return result
end
function M.deserialize(data)
 if type(data)~='string' or data:match('^%s*$') then return nil end
 local ok,value=pcall(parse,data)
 if not ok then return nil end
 return value
end
return M
