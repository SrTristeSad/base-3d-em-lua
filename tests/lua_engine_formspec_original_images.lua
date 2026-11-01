-- Phase 64: untouched full-resolution formspec sprites + Lua UV modifier.
-- Source-only run supplies the same generated manifest shape as the .lovr ZIP.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
package.preload['core.formspec_original_manifest']=function()
 return {
  ['mcl_inventory_stonecutter.png']={width=176,height=160},
  ['mcl_stonecutter_saw.png']={width=16,height=48},
 }
end
local Atlas=require('core.atlas')
local Sprites=require('core.formspecsprites')
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local View=require('core.formspecview')
local function eq(a,b)
 assert(a==b,tostring(a)..' ~= '..tostring(b))
end
local bg=assert(Sprites.source('mcl_inventory_stonecutter.png'))
eq(bg.path,'visual/formspec/mcl_inventory_stonecutter.png')
assert(bg.original and bg.width==176 and bg.height==160)
eq(bg.uv[2],0);eq(bg.uv[4],1)
local saw=assert(Sprites.source('mcl_stonecutter_saw.png^[verticalframe:3:1'))
eq(saw.path,'visual/formspec/mcl_stonecutter_saw.png')
assert(math.abs(saw.uv[2]-1/3)<1e-12)
assert(math.abs(saw.uv[4]-2/3)<1e-12)
local closed=assert(Sprites.source('mcl_stonecutter_saw.png^[verticalframe:3:1]'))
eq(closed.uv[2],saw.uv[2])
local vertices=assert(Sprites.quad('mcl_stonecutter_saw.png^[verticalframe:3:1',
 100,110,28,42))
eq(vertices[1][2],89);eq(vertices[3][2],131)
eq(vertices[1][8],saw.uv[2]);eq(vertices[3][8],saw.uv[4])
assert(not Sprites.source('mcl_stonecutter_saw.png^[verticalframe:3:3'))
assert(not Sprites.source('mcl_stonecutter_saw.png^[verticalframe:0:0'))
assert(not Sprites.source('mcl_stonecutter_saw.png^[verticalframe:5:0'))
assert(not Sprites.source('mcl_stonecutter_saw.png^[colorize:red'))
assert(not Sprites.source('../mcl_stonecutter_saw.png'))
assert(not Sprites.source('mcl_stonecutter_saw.png;other.png'))
local atlas=assert(Sprites.source('default_stone.png'))
eq(atlas.path,'visual/atlas.png')
eq(atlas.uv[1],select(1,Atlas.uv('default_stone.png')))
local count,paths=0,{}
local buffers={}
local graphics={}
function graphics.newBuffer(format,vertices)
 eq(#vertices,6)
 local buffer={freed=0}
 function buffer:release()self.freed=self.freed+1 end
 buffers[#buffers+1]=buffer
 return buffer
end
function graphics.newTexture(path)
 count=count+1;paths[#paths+1]=path
 local t={freed=0}
 function t:release()self.freed=self.freed+1 end
 return t
end
local pass={}
for _,name in ipairs({'push','pop','setViewPose','setProjection',
 'setDepthTest','setMaterial','setColor','plane','text','mesh'}) do
 pass[name]=function(self,...) end
end
local sprites=Sprites.new(graphics)
sprites:beginFrame()
assert(sprites:draw(pass,'mcl_inventory_stonecutter.png',100,100,40,40))
assert(sprites:draw(pass,'mcl_stonecutter_saw.png^[verticalframe:3:1',
 180,100,40,40))
assert(sprites:draw(pass,'default_stone.png',200,200,40,40))
sprites:endFrame()
eq(count,3)
eq(paths[1],'visual/formspec/mcl_inventory_stonecutter.png')
eq(paths[2],'visual/formspec/mcl_stonecutter_saw.png')
eq(paths[3],'visual/atlas.png')
sprites:beginFrame()
assert(sprites:draw(pass,'mcl_stonecutter_saw.png^[verticalframe:3:1',
 180,100,40,40))
sprites:endFrame()
eq(count,3)
sprites:release()
for _,buffer in ipairs(buffers) do eq(buffer.freed,1) end
for _,t in pairs(sprites.textures) do error('unreleased texture '..tostring(t)) end

local rt=Runtime.new()
local player={get_player_name=function()return 'GuiPlayer' end}
assert(rt:connectPlayer(player,Physics.new(rt.api,{x=0,y=4,z=0})))
local form='formspec_version[4]size[8,6]'..
 'image[1,1;2,2;mcl_inventory_stonecutter.png]'..
 'image_button[4,1;1,1;mcl_stonecutter_saw.png^[verticalframe:3:1;toggle;]'..
 'image[4,3;1,1;unknown.png]'
assert(rt.api.show_formspec('GuiPlayer','probe:original',form))
local view=View.new(rt,'GuiPlayer')
local originals={}
rt.api.register_on_player_receive_fields(function(_,name,fields)
 originals[#originals+1]={name=name,fields=fields}
end)
local old=_G.lovr
_G.lovr={math={newMat4=function()return {} end},graphics=graphics}
local w,h=900,720
assert(view:draw(pass,w,h))
eq(count,5)
local target
for _,control in ipairs(view:layout(w,h).controls) do
 if control.kind=='button' and control.field=='toggle' then
  target=control
 end
end
assert(target and target.texture=='mcl_stonecutter_saw.png^[verticalframe:3:1')
assert(view:click(w,h,target.x+target.w/2,target.y+target.h/2,1))
eq(originals[#originals].fields.toggle,'true')
view:release()
_G.lovr=old
assert(rt:disconnectPlayer('GuiPlayer'))
print('LUA ENGINE ORIGINAL FORMSPEC PNG AND VERTICALFRAME PASS')
