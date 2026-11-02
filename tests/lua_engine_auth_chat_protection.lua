-- Phase 71: Luanti privilege sets, protection callbacks and chat transport.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local rt=Runtime.new({default_privs='interact,shout'})
local api=rt.api
local function eq(a,b,what)
 assert(a==b,(what or 'value')..': '..tostring(a)..' != '..tostring(b))
end
local alice={get_player_name=function()return 'Alice' end}
local bob={get_player_name=function()return 'Bob' end}
assert(rt:connectPlayer(alice,Physics.new(api,{x=0,y=3,z=0})))
assert(rt:connectPlayer(bob,Physics.new(api,{x=0,y=3,z=0})))
-- A registration is metadata and does not grant a privilege to anybody.
api.register_privilege('fly',{description='Flight'})
local priv=api.get_player_privs('Alice')
eq(priv.interact,true);eq(priv.shout,true);eq(priv.fly,nil)
priv.interact=nil -- no leaked mutable references from storage
eq(api.get_player_privs('Alice').interact,true)
local ok,missing=api.check_player_privs('Alice','interact','fly')
eq(ok,false);eq(#missing,1);eq(missing[1],'fly')
ok,missing=api.check_player_privs(alice,{fly=true,shout=true,ban=false})
eq(ok,false);eq(#missing,1);eq(missing[1],'fly')
ok,missing=api.check_player_privs('Alice','interact','shout')
eq(ok,true);eq(missing,'')
-- Set privileges *replaces* the entire set, unlike change_player_privs.
assert(api.set_player_privs('Alice',{fly=true,interact=true}))
eq(api.get_player_privs('Alice').shout,nil)
eq(api.get_player_privs('Bob').shout,true)
assert(api.change_player_privs('Alice',{fly=false,shout=true}))
eq(api.get_player_privs('Alice').fly,nil)
eq(api.get_player_privs('Alice').shout,true)
assert(not pcall(api.set_player_privs,'Alice',{interact='yes'}))
assert(not pcall(api.check_player_privs,'Alice',42))
local notified={}
assert(type(api.registered_on_protection_violation)=='table')
api.register_on_protection_violation(function(pos,name)
 notified[#notified+1]={pos=pos,name=name}
 pos.x=123456 -- no mutable argument should leak to second callback
end)
api.register_on_protection_violation(function(pos,name)
 eq(pos.x,2)
 eq(name,'Bob')
 notified[#notified+1]={pos=pos,name=name}
end)
local source={x=2,y=1,z=4}
api.record_protection_violation(source,'Bob')
eq(#notified,2);eq(source.x,2)
eq(notified[2].pos.x,2)
eq(api.is_protected(source,'Bob'),false)
-- Mods may override core.is_protected, as upstream misc.lua permits.
api.is_protected=function(pos,name)
 return name=='Bob' and pos.x==4 and pos.y==3 and pos.z==2
end
eq(api.is_protected({x=4,y=3,z=2},'Bob'),true)
local blocked=api.is_area_protected(
 {x=6,y=3,z=2},{x=0,y=3,z=2},'Bob',2)
assert(blocked and blocked.x==4 and blocked.y==3 and blocked.z==2)
eq(api.is_area_protected({x=0,y=0,z=0},
 {x=6,y=3,z=2},'Alice',2),false)
assert(not pcall(api.is_area_protected,
 {x=0,y=0,z=0},{x=5,y=5,z=5},'Bob',0))
-- The server-to-host queue delivers only to connected named recipients.
api.chat_send_player('Alice','Welcome, 100% ready')
api.chat_send_player('Offline','Not delivered')
api.chat_send_all('Global event')
local inbox=rt:pollChat('Alice')
eq(#inbox,2);eq(inbox[1],'Welcome, 100% ready')
eq(inbox[2],'Global event')
eq(#rt:pollChat('Alice'),0)
local binbox=rt:pollChat('Bob')
eq(#binbox,1);eq(binbox[1],'Global event')
eq(#rt:pollChat('Offline'),0)
eq(api.format_chat_message('Alice','100% @name done'),
 '<Alice> 100% @name done')
assert(not pcall(api.chat_send_player,'Alice',{}))
assert(not pcall(api.format_chat_message,'Alice',5))
-- Disconnection never leaks undelivered messages to a new session.
api.chat_send_player('Alice','Message before disconnect')
assert(rt:disconnectPlayer('Alice'))
eq(#rt:pollChat('Alice'),0)
assert(rt:connectPlayer(alice,Physics.new(api,{x=0,y=3,z=0})))
eq(#rt:pollChat('Alice'),0)
-- Connected host hooks receive actual messages immediately, no hidden
-- claim of a native networking subsystem.
local sent={}
local persistent={}
local other=Runtime.new({
 read_player_privs=function(name)
  return persistent[name] or {}
 end,
 write_player_privs=function(name,privs)
  persistent[name]=privs
  return true
 end,
 chat_sink=function(name,message)
  sent[#sent+1]=name..':'..message
 end,
 is_protected=function(pos,name)
  return name=='Bob' and pos.x==5
 end,
 settings={chat_message_format='(@name) @message'}
})
local a2=other.api
assert(a2.set_player_privs('Bob',{interact=true}))
local borrowed=a2.get_player_privs('Bob')
eq(borrowed.interact,true)
assert(a2.change_player_privs('Bob',{fly=true}))
eq(persistent.Bob.fly,true)
eq(a2.is_protected({x=5,y=0,z=0},'Bob'),true)
local bob2={get_player_name=function()return 'Bob' end}
assert(other:connectPlayer(bob2,Physics.new(a2,{x=0,y=3,z=0})))
a2.chat_send_player('Bob','Sent through transport')
eq(sent[1],'Bob:Sent through transport')
eq(#other:pollChat('Bob'),0)
eq(a2.format_chat_message('Bob','A 100%'),'(Bob) A 100%')
assert(rt:disconnectPlayer('Bob'))
assert(rt:disconnectPlayer('Alice'))
assert(other:disconnectPlayer('Bob'))
print('LUA ENGINE CHAT, PRIVILEGES AND PROTECTION BRIDGE PASS')
