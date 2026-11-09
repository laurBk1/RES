local controls, callbacks, logs = {}, {}, {}
local vec = {}; vec.__index = vec
function vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, vec) end
function vec:to(p) return vector(p.x-self.x, p.y-self.y, p.z-self.z) end
function vec:angles()
    return vector(-math.deg(math.atan2(self.z, math.sqrt(self.x*self.x+self.y*self.y))), math.deg(math.atan2(self.y,self.x)), 0)
end
local actual_print = print
print = function(s) logs[#logs+1] = s end
local function item(name,value)
    local r = {value=value}
    function r:get() return self.value end
    function r:get_override() return self.overridden end
    function r:set_callback(fn) self.callback=fn end
    controls[name]=r
    return r
end
local rage = item('rage',false)
local find_available = true
ui = {
    create=function()
        return {switch=function(_,n,v) return item(n,v) end,
            slider=function(_,n,lo,hi,v) return item(n,v) end}
    end,
    find=function() if find_available then return rage end end,
}
events=setmetatable({}, {__index=function(t,k)
    local event={set=function(_,fn) callbacks[k]=fn end}; rawset(t,k,event); return event
end})
local cvars = {sv_maxunlag=.2,cl_interp=0,cl_interp_ratio=1,cl_updaterate=64,
    sv_minupdaterate=64,sv_maxupdaterate=64,sv_client_min_interp_ratio=1,sv_client_max_interp_ratio=2}
cvar=setmetatable({}, {__index=function(_,name) return {float=function(_, ...)
    assert(select('#',...)==0, 'cvar mutation forbidden'); return cvars[name]
end} end})
globals={is_in_game=true,tickinterval=1/64,tickcount=640,curtime=10}
local latency=.04
local trace_mode, trace_calls='clear',0
utils={net_channel=function() return {latency={[0]=latency,[1]=latency}} end,
    trace_line=function()
        trace_calls=trace_calls+1
        if trace_mode=='error' then error('trace unavailable') end
        if trace_mode=='nil' then return nil end
        return {fraction=trace_mode=='clear' and 1 or .1,start_solid=trace_mode=='solid',all_solid=false}
    end}
local weapon_type=5
local weapon={get_weapon_info=function() return {weapon_type=weapon_type} end}
local function player(idx)
    local p={idx=idx,userid=idx+100,sim=9.95,alive=true,dormant=false,head=vector(100,0,64),origin=vector(100,0,0)}
    function p:get_index() return self.idx end
    function p:get_player_info() return {userid=self.userid} end
    function p:get_simulation_time() return {current=self.sim,old=self.sim-.01} end
    function p:is_alive() return self.alive end
    function p:is_dormant() return self.dormant end
    function p:get_origin() return self.origin end
    function p:get_hitbox_position() return self.head end
    function p:get_player_weapon() return weapon end
    function p:get_eye_position() return vector(0,0,64) end
    return p
end
local lp, enemies=player(1),{player(2)}
entity={get_local_player=function() return lp end,get_players=function() return enemies end}
assert(loadfile('neverlose_backtrack.lua'))()
local function set(name,value)
    controls[name].value=value
    if controls[name].callback then controls[name].callback() end
end
local function move(attack)
    local cmd={tickcount=640,view_angles=vector(0,0,0),in_attack=attack or false,in_attack2=false,
        in_use=false,send_packet=false,choked_commands=7,forwardmove=100,sidemove=20}
    return cmd
end
local function run(cmd)
    local packet,attack,choke,forward,side=cmd.send_packet,cmd.in_attack,cmd.choked_commands,cmd.forwardmove,cmd.sidemove
    callbacks.createmove(cmd)
    assert(cmd.send_packet==packet and cmd.in_attack==attack and cmd.choked_commands==choke)
    assert(cmd.forwardmove==forward and cmd.sidemove==side)
end
local function unchanged(cmd)
    local tick,view=cmd.tickcount,cmd.view_angles
    run(cmd); assert(cmd.tickcount==tick and cmd.view_angles==view,'command changed unexpectedly')
end
local tests=0
local function test(name,fn)
    lp=player(1);enemies={player(2)};rage.value=false;rage.overridden=nil
    globals.is_in_game=true;globals.curtime=10;globals.tickcount=640
    globals.tickinterval=1/64;latency=.04;weapon_type=5;trace_mode='clear';trace_calls=0
    cvars.sv_maxunlag=.2;cvars.cl_interp_ratio=1;cvars.cl_updaterate=64
    cvars.sv_minupdaterate=64;cvars.sv_maxupdaterate=64
    set('Enable',true);set('Manual assist (ragebot must be off)',true)
    set('HvH Rage / SSG 08 extended BT',false)
    controls['Prefer oldest valid record (max extend)'].value=false
    controls['Record age limit (ms)'].value=150
    logs={};fn()
    for _,line in ipairs(logs) do assert(not line:find('callback aborted',1,true),line) end
    tests=tests+1;actual_print('PASS '..name)
end
test('native and disabled paths preserve every command field',function()
    set('Manual assist (ragebot must be off)',false);callbacks.net_update_end();unchanged(move(true))
    set('Enable',false);unchanged(move(true))
end)
test('ragebot enabled or overridden never competes with native aim',function()
    rage.value=true;callbacks.net_update_end();unchanged(move(true))
    rage.value=false;rage.overridden=true;callbacks.net_update_end();unchanged(move(true))
end)
test('unknown rage state fails closed',function()
    rage.value='unknown';callbacks.net_update_end();unchanged(move(true))
end)
test('valid manual shot uses simulation plus interpolation, not capture tick',function()
    callbacks.net_update_end();local cmd=move(true);run(cmd)
    assert(cmd.tickcount==math.floor((9.95+1/64)*64+.5) and cmd.tickcount~=640)
    assert(cmd.view_angles.x==0 and cmd.view_angles.y==0)
end)
test('no autofire or aiming without user attack',function()
    callbacks.net_update_end();unchanged(move(false))
end)
test('FOV rejects before changing angle or tick',function()
    enemies[1].head=vector(0,100,64);callbacks.net_update_end();unchanged(move(true))
    assert(trace_calls==0)
end)
test('smallest FOV wins instead of oldest record across players',function()
    enemies[1].head=vector(100,10,64);enemies[1].sim=9.87
    enemies[2]=player(3);enemies[2].head=vector(100,1,64);enemies[2].sim=9.96
    callbacks.net_update_end();local cmd=move(true);run(cmd)
    assert(cmd.view_angles.y < 1 and cmd.tickcount==math.floor((9.96+1/64)*64+.5))
end)
test('trace errors, missing trace, walls and start-solid fail closed',function()
    callbacks.net_update_end()
    for _,v in ipairs({'error','nil','wall','solid'}) do trace_mode=v;unchanged(move(true)) end
end)
test('age and server max-unlag limits reject stale history',function()
    enemies[1].sim=9.8;callbacks.net_update_end();unchanged(move(true))
    enemies[1].sim=9.95;cvars.sv_maxunlag=.03;callbacks.net_update_end();unchanged(move(true))
end)
test('missing timing and large correction mismatch fail closed',function()
    callbacks.net_update_end();cvars.sv_maxunlag=nil;unchanged(move(true))
    cvars.sv_maxunlag=1;latency=.5;unchanged(move(true))
end)
test('server interpolation and updaterate bounds are applied',function()
    cvars.cl_updaterate=128;cvars.cl_interp_ratio=10
    callbacks.net_update_end();local cmd=move(true);run(cmd)
    assert(cmd.tickcount==math.floor((9.95+2/64)*64+.5))
end)
test('teleport and simulation rollback remove older viable head',function()
    callbacks.net_update_end()
    enemies[1].sim=9.97;enemies[1].origin=vector(300,300,0);enemies[1].head=vector(0,300,64)
    callbacks.net_update_end();unchanged(move(true))
    callbacks.round_start();enemies[1]=player(2);callbacks.net_update_end()
    enemies[1].sim=9.94;enemies[1].head=vector(0,100,64)
    callbacks.net_update_end();unchanged(move(true))
end)
test('slot reuse, dormancy, death, spawn and round clear old records',function()
    callbacks.net_update_end();enemies[1].userid=999;unchanged(move(true))
    enemies[1]=player(2);callbacks.net_update_end();enemies[1].dormant=true
    callbacks.net_update_end();enemies[1].dormant=false;unchanged(move(true))
    callbacks.net_update_end();lp.alive=false;callbacks.net_update_end();lp.alive=true;unchanged(move(true))
    for _,event in ipairs({'round_start','player_spawn','player_disconnect','level_init','shutdown'}) do
        callbacks.net_update_end();callbacks[event]();unchanged(move(true))
    end
end)
test('copy head vectors instead of retaining mutable API objects',function()
    callbacks.net_update_end();enemies[1].head.y=100
    local cmd=move(true);run(cmd);assert(cmd.view_angles.y==0)
end)
test('knife, grenade and use input do not get manual aiming',function()
    callbacks.net_update_end()
    for _,v in ipairs({0,7,8,9}) do weapon_type=v;unchanged(move(true)) end
    weapon_type=5;local cmd=move(true);cmd.in_use=true;unchanged(cmd)
end)
test('choke and send-packet decisions remain owned by Neverlose',function()
    callbacks.net_update_end()
    for _,packet in ipairs({false,true}) do
        for _,choke in ipairs({0,7,16}) do
            local cmd=move(true);cmd.send_packet=packet;cmd.choked_commands=choke;run(cmd)
        end
    end
end)
test('HvH Rage / SSG 08 extended BT works with ragebot enabled, autowall trace_bullet and extended 350ms ping-spike window',function()
    rage.value=true
    set('HvH Rage / SSG 08 extended BT',true)
    controls['Prefer oldest valid record (max extend)'].value=true
    controls['Record age limit (ms)'].value=400
    cvars.sv_maxunlag=0.4
    latency=0.16 -- 160ms outgoing + 160ms incoming = 320ms RTT with ping spike
    trace_mode='wall' -- line-of-sight blocked by thin wall, must use trace_bullet autowall
    utils.trace_bullet=function(_, _, pt)
        if pt and pt.x == 100 then return 88 end
        return 0
    end
    -- Record 1: 320ms old (sim = 9.68), Record 2: 50ms old (sim = 9.95)
    enemies[1].sim=9.68; enemies[1].head=vector(100,20,64); callbacks.net_update_end()
    enemies[1].sim=9.95; enemies[1].head=vector(100,5,64); callbacks.net_update_end()
    local cmd=move(true); run(cmd)
    local expected_oldest_tick = math.floor((9.68 + 1/64) * 64 + 0.5)
    assert(cmd.tickcount == expected_oldest_tick, 'must select 320ms extended backtrack record via autowall')
    utils.trace_bullet=nil
end)
print=actual_print
print(('%d Neverlose regression groups passed; mock API, not in-game proof'):format(tests))
