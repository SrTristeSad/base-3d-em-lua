-- Phase 63: formspec renders exact pixels from the existing Luanti atlas
-- through an orthographic LÖVR mesh; no substituted generated assets.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Atlas=require('core.atlas')
local Sprites=require('core.formspecsprites')
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local View=require('core.formspecview')
local function eq(a,b,msg)
 assert(a==b,(msg or 'unexpected')..' '..tostring(a)..' != '..tostring(b))
end
local a,b,c,d=Atlas.uv('default_stone.png')
local verts=assert(Sprites.quad('default_stone.png',120,160,40,60))
eq(#verts,6)
eq(verts[1][1],100)
eq(verts[1][2],130)
eq(verts[1][7],a)
eq(verts[1][8],b)
eq(verts[3][1],140)
eq(verts[3][2],190)
eq(verts[3][7],c)
eq(verts[3][8],d)
assert(not Sprites.quad('missing_unregistered_icon.png',1,2,3,4))
assert(not Sprites.quad('default_stone.png',1,2,0,4))
assert(not Sprites.quad('default_stone.png',1,2,0/0,4))

local rt=Runtime.new()
rt.api.register_node('test:stone',{
 description='Slate',tiles={'default_stone.png'}})
rt.api.register_craftitem('test:sand',{
 description='Sand sample',inventory_image='default_sand.png'})
rt.api.register_craftitem('test:unknown',{description='Not illustrated'})
local player={get_player_name=function()return 'Pixel' end}
assert(rt:connectPlayer(player,Physics.new(rt.api,{x=0,y=3,z=0})))
local inv=player:get_inventory()
inv:set_stack('main',1,'test:stone 18')
inv:set_stack('main',2,'test:sand 5')
inv:set_stack('main',3,'test:unknown 2')
local form='formspec_version[4]size[9,6]'..
 'label[0.2,0.3;Atlas from original registered definitions]'..
 'list[current_player;main;0.5,1;3,1;]'..
 'image[0.5,3;1,1;default_stone.png]'..
 'item_image[2,3;1,1;test:stone]'..
 'image_button[3.5,3;1,1;default_sand.png;image;]'..
 'item_image_button[5,3;1,1;test:sand;item;]'..
 'image[6.5,3;1,1;not_a_real_asset.png]'
local received={}
rt.api.register_on_player_receive_fields(function(_,name,fields)
 received[#received+1]={name=name,fields=fields}
end)
assert(rt.api.show_formspec('Pixel','test:atlas',form))
local view=View.new(rt,'Pixel')
local w,h=1200,900
local layout=assert(view:layout(w,h))
local count_buffers, count_textures=0,0
local all_buffers={}
local graphics={}
function graphics.newBuffer(format,vertices)
 count_buffers=count_buffers+1
 assert(#format==4 and #vertices==6)
 local buffer={vertices=vertices,releases=0}
 function buffer:release()self.releases=self.releases+1 end
 all_buffers[#all_buffers+1]=buffer
 return buffer
end
function graphics.newTexture(path)
 eq(path,'visual/atlas.png')
 count_textures=count_textures+1
 return {path=path}
end
local old=_G.lovr
_G.lovr={math={newMat4=function()return {} end},graphics=graphics}
local pass={calls={},meshes={},materials={}}
for _,name in ipairs({'push','pop','setViewPose','setProjection',
 'setDepthTest','setMaterial','setColor','plane','text','mesh'}) do
 pass[name]=function(self,...)
  self.calls[#self.calls+1]=name
  if name=='mesh' then self.meshes[#self.meshes+1]={...} end
  if name=='setMaterial' then self.materials[#self.materials+1]=... end
 end
end
local function draw()
 assert(view:draw(pass,w,h))
 eq(pass.calls[1],'push')
 eq(pass.calls[#pass.calls],'pop')
end
draw()
eq(count_textures,1,'load shared atlas only once')
-- Three inventory entries (stone/sand), image, item_image and two
-- image buttons. Unknown item/texture remains legible as placeholder.
eq(count_buffers,6,'known sprites should each allocate an atlas quad')
eq(#pass.meshes,6)
for _,call in ipairs(pass.meshes) do
 eq(call[2],0);eq(call[3],0);eq(call[4],0)
end
-- A second draw of the exact same form reuses GPU mesh buffers.
pass.calls={};pass.meshes={}
draw()
eq(count_textures,1)
eq(count_buffers,6)
eq(#pass.meshes,6)
local wanted={}
for _,c0 in ipairs(layout.controls) do
 if c0.kind=='button' then wanted[c0.field]=c0 end
end
assert(wanted.image and wanted.item)
local function click(ctl)
 return view:click(w,h,ctl.x+ctl.w/2,ctl.y+ctl.h/2,1)
end
assert(click(wanted.image))
eq(received[#received].fields.image,'true')
assert(click(wanted.item))
eq(received[#received].fields.item,'true')

-- Move inventory: the same graphical source slot is also a real InvRef.
local slots={}
for _,ctl in ipairs(layout.controls) do
 if ctl.kind=='slot' then slots[ctl.index]=ctl end
end
assert(click(slots[1]))
local ok,n=click(slots[3])
assert(ok and n==18)
eq(inv:get_stack('main',1):get_name(),'test:unknown')
eq(inv:get_stack('main',3):get_name(),'test:stone')
-- Cache should evict old GUI quads after the form changes, not leak GPU
-- resources across repeated server-sent formspec replacements.
assert(rt.api.show_formspec('Pixel','test:different',
 'size[2,2]image[0,0;1,1;default_dirt.png]'))
for i=1,4 do
 pass.calls={};pass.meshes={}
 draw()
end
assert(all_buffers[1].releases>=1,'stale sprite buffer must be released')
view.sprites:release()
assert(rt:disconnectPlayer('Pixel'))
_G.lovr=old
print('LUA ENGINE FORMSPEC ATLAS SPRITES, GPU UV AND CLICK PASS')
