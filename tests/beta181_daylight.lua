package.path='./?.lua;./?/init.lua;'..package.path
local files={}
lovr={filesystem={
 read=function(p) return files[p] end,
 write=function(p,data) files[p]=data; return true end,
 isFile=function(p) return files[p]~=nil end
}}
local Day=require('src.beta181_daylight')
local World=require('src.world')
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
eq(Day.TICKS_PER_DAY,24000)
eq(Day.TICKS_PER_SECOND,20)
eq(Day.clock(0),'06:00')
eq(Day.clock(6000),'12:00')
eq(Day.clock(12000),'18:00')
eq(Day.clock(18000),'00:00')
eq(Day.clock(24000),'06:00')
eq(Day.day(24000),2)
eq(Day.phase(0),'Amanhecer')
eq(Day.phase(18000),'Noite')
assert(Day.sun(6000)>Day.sun(0) and Day.sun(0)>Day.sun(18000))
assert(Day.ambient(6000)>Day.ambient(18000))
local a,b,c=Day.sky(6000)
local x,y,z=Day.sky(18000)
assert(a>x and b>y and c>z)
eq(Day.advance(0,1),20)
eq(Day.advance(23990,1),24010)
eq(Day.normalize(24010),10)
eq(Day.advance(10,-5),10)
eq(Day.advance(10,0/0),10)
local opts={seed='phase5',generatorVersion='beta181',
 savePath='worlds/phase5.sav'}
local w=World.new(opts)
eq(w.time,0)
eq(w:advanceTime(.5),10)
eq(w:advanceTime(1),30)
local player={x=0,y=80,z=0,yaw=0,pitch=0}
assert(w:save(player))
assert(files[opts.savePath]:find('WORLDTIME 30.000',1,true))
local loaded=World.new(opts)
eq(loaded.time,30)
eq(loaded:advanceTime(.25),35)
files['worlds/old.sav']='PLAYER 0.000 80.000 0.000 0.000000 0.000000\n'
local legacy=World.new({seed='old',generatorVersion='beta181',savePath='worlds/old.sav'})
eq(legacy.time,0)
files['worlds/bad.sav']='WORLDTIME 99999999999999\n'
local bad=World.new({seed='bad',generatorVersion='beta181',savePath='worlds/bad.sav'})
eq(bad.time,0)
local classic=World.new({seed='old',generatorVersion='classic030',savePath='worlds/classic.sav'})
eq(classic.time,nil)
eq(classic:advanceTime(10),nil)
assert(classic:save(player))
assert(not files['worlds/classic.sav']:find('WORLDTIME',1,true))
print('beta181_daylight: OK')
