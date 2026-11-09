-- Executes the anti-aim sections of the shipped single-file script with API mocks.
local file = assert(io.open('mytools.lua', 'r'))
local source = file:read('*a')
file:close()
local function between(first, last)
    local a = assert(source:find(first, 1, true), first)
    local b = assert(source:find(last, a, true), last)
    return source:sub(a, b - 1)
end
local callbacks, refs = {}, {}
local tick, now, trace_calls = 100, 10, 0
local trace_side, trace_skip, trace_height = 0
local local_player, enemies, bomb = 1, {}, false
local props = {
    [1] = {m_nTickBase = 1000, m_fFlags = 1, m_flDuckAmount = 0, m_flPoseParameter = .5, m_iTeamNum = 3},
    [2] = {['m_vecViewOffset[2]'] = 46}, [3] = {['m_vecViewOffset[2]'] = 64},
}
local velocity = {0, 0, 0}
local origin = {[1] = {0, 0, 0}, [2] = {100, 0, 0}, [3] = {100, 0, 0}, [9] = {0, 0, 0}}
local function noop() end
local function control(value, min, max)
    return {value = value, min = min, max = max}
end
ui = {
    new_checkbox = function() return control(false) end,
    new_hotkey = function() local r = control(false); r.hotkey = true; return r end,
    new_slider = function(_, _, _, min, max, default) return control(default or min, min, max) end,
    new_combobox = function(_, _, _, first, ...) return control(type(first) == 'table' and first[1] or first) end,
    new_multiselect = function() return control({}) end,
    new_label = function() return control('') end,
    new_button = function(_, _, _, fn) return {callback = fn} end,
    set_visible = noop, set_callback = noop,
    get = function(r) assert(type(r) == 'table'); return r.value end,
    set = function(r, v)
        assert(type(r) == 'table')
        if r.hotkey and type(v) == 'string' then return end
        if r.min then assert(type(v) == 'number' and v >= r.min and v <= r.max, 'slider range: '..tostring(v)) end
        r.value = v
    end,
    reference = function(_, _, name)
        if not refs[name] then
            local second = control(0, -180, 180)
            if name == 'Double tap' or name == 'On shot anti-aim' or name == 'Slow motion' or name == 'Freestanding' then
                second = control(false); second.hotkey = true
            end
            refs[name] = {control(false), second}
        end
        return unpack(refs[name])
    end,
}
entity = {
    get_local_player = function() return local_player end,
    is_alive = function(i) return i ~= nil and i ~= 0 end,
    is_enemy = function(i) return i == 2 or i == 3 end,
    is_dormant = function() return false end,
    get_players = function() return enemies end,
    get_player_weapon = function(i) assert(i); return 5 end,
    get_classname = function() return 'CWeaponSSG08' end,
    get_all = function() return bomb and {9} or {} end,
    get_origin = function(i) return unpack(origin[i]) end,
    hitbox_position = function(i) local p = origin[i]; return p[1], p[2], p[3] + 64 end,
    get_prop = function(i, name)
        if name == 'm_vecVelocity' then return unpack(velocity) end
        if name == 'm_vecOrigin' then return unpack(origin[i]) end
        return props[i] and props[i][name]
    end,
}
globals = {
    tickcount = function() return tick end, realtime = function() return now end,
    tickinterval = function() return 1/64 end, frametime = function() return 1/60 end,
}
client = {
    set_event_callback = function(name, fn) callbacks[name] = callbacks[name] or {}; table.insert(callbacks[name], fn) end,
    unset_event_callback = noop, color_log = noop,
    eye_position = function() return 0, 0, 64 end,
    camera_angles = function() return 0, 0 end,
    userid_to_entindex = function(i) return i end,
    trace_line = function(skip, x, y, z, tx, ty, tz)
        trace_calls = trace_calls + 1
        if x == 100 then
            trace_skip, trace_height = skip, z
            if trace_side ~= 0 then return (ty * trace_side > 0) and .1 or 1, -1 end
        end
        return 1, -1
    end,
    trace_bullet = function() return nil, 0 end,
}
renderer = {world_to_screen = function() return 0, 0 end}
bit = require('bit')
local vec = {}; vec.__index = vec
function vec:length2d() return math.sqrt(self.x*self.x + self.y*self.y) end
function vec:length() return math.sqrt(self.x*self.x + self.y*self.y + self.z*self.z) end
function vec:dist(other) return math.sqrt((self.x-other.x)^2+(self.y-other.y)^2+(self.z-other.z)^2) end
local function vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0}, vec) end
package.preload.vector = function() return vector end
for _, name in ipairs({'entity','http','base64','clipboard','steamworks'}) do
    package.preload['gamesense/'..name] = function() return {} end
end
local chunk = source:sub(1, assert(source:find('local function on_paint()', 1, true)) - 1)
    .. between('local function apply_adaptive_preset()', "client.set_event_callback('paint_ui', function()")
    .. between("client.set_event_callback('net_update_end', function()", '--fastladder')
    .. '\nreturn {settings=settings, states=anti_aim_settings, refs=reference, runtime=ab_state, reset=reset_aa_runtime, tactical=update_tactical_awareness, normalize=normalize_yaw, steal=apply_and_export_stolen_aa}'
local aa = assert(loadstring(chunk, '@mytools-aa-sections'))()
assert(not aa.settings.anti_brute_head.value and not aa.states[1].override_state.value, 'load must preserve config')
local function emit(name, e)
    for _, fn in ipairs(callbacks[name] or {}) do fn(e or {}) end
end
local number = 0
local function command(choke, use, jump)
    number = number + 1
    local cmd = {command_number=number, chokedcommands=choke or 0, in_use=use or 0, in_jump=jump or 0, buttons=0}
    emit('setup_command', cmd)
    return cmd
end
local passed = 0
local function test(name, fn)
    aa.reset(); enemies = {}; velocity = {0,0,0}; bomb = false; local_player = 1
    props[1].m_fFlags, props[1].m_flDuckAmount = 1, 0
    for _, cfg in ipairs(aa.states) do
        for key, r in pairs(cfg) do
            if type(r.value) == 'boolean' then r.value = false end
        end
        ui.set(cfg.yaw1, '180'); ui.set(cfg.yaw_jitter1, 'Off'); ui.set(cfg.body_yaw1, 'Off')
        ui.set(cfg.yaw2_left, 0); ui.set(cfg.yaw2_right, 0); ui.set(cfg.yaw2_randomize, 0)
        ui.set(cfg.yaw_jitter2_randomize, 0)
    end
    for _, r in pairs(aa.settings) do if type(r.value) == 'boolean' then r.value = false end end
    aa.settings.tweaks.value = {}
    aa.refs.double_tap[1].value, aa.refs.double_tap[2].value = false, false
    aa.refs.on_shot_anti_aim[1].value, aa.refs.on_shot_anti_aim[2].value = false, false
    aa.refs.slow_motion[1].value, aa.refs.slow_motion[2].value = false, false
    aa.refs.duck_peek_assist.value = false
    fn(); passed = passed + 1; print('PASS '..name)
end

test('no preset side effects on load', function()
    assert(not aa.settings.anti_brute_head.value)
    assert(not source:find('pcall(apply_adaptive_preset)', 1, true))
end)
test('nil local player returns before weapon access', function() local_player = nil; command() end)
test('state boundaries and horizontal speed', function()
    for i=2,8 do aa.states[i].override_state.value = true end
    velocity = {2,0,100}; command(); assert(state_id == 2)
    props[1].m_flDuckAmount = .8; command(); assert(state_id == 5)
    velocity = {3,0,0}; command(); assert(state_id == 6)
    command(0,0,1); assert(state_id == 8)
    props[1].m_flDuckAmount = 0; command(0,0,1); assert(state_id == 7)
    command(); assert(state_id == 3)
    aa.refs.slow_motion[1].value, aa.refs.slow_motion[2].value = true, true
    command(); assert(state_id == 4)
    aa.states[4].override_state.value = false; command(); assert(state_id == 1)
    aa.states[9].override_state.value = true; command(); assert(state_id == 9)
end)
test('manual edge toggle and custom jitter priority', function()
    aa.settings.tweaks.value = {'Off jitter on manual'}
    aa.states[1].yaw_jitter1.value = '5-Way'
    aa.states[1].yaw_jitter2_left.value, aa.states[1].yaw_jitter2_right.value = -70, 70
    aa.settings.manual_left.value = true
    command(); assert(aa.refs.yaw[2].value == -90 and aa.refs.yaw_base.value == 'Local view')
    for _=1,20 do now = now + .3; command(); assert(aa.refs.yaw[2].value == -90) end
    aa.settings.manual_left.value = false; command()
    aa.settings.manual_left.value = true; command(); assert(aa.runtime.manual_direction == nil)
end)
test('configured 90 degree yaw is not manual input', function()
    aa.states[1].yaw2_right.value = 90; aa.states[1].yaw_base.value = 'At targets'
    command(); assert(aa.refs.yaw[2].value == 90 and aa.refs.yaw_base.value == 'At targets')
end)
test('defuse status cannot leak to next command', function()
    aa.states[10].override_state.value = true; bomb = true
    assert(command(0,1).in_use == 1)
    bomb = false; assert(command(0,1).in_use == 0 and state_id == 10)
end)
test('packet counter and delay hold across choke and duplicate callback', function()
    aa.refs.double_tap[1].value, aa.refs.double_tap[2].value = true, true
    aa.states[1].freestanding_body_yaw.value = true
    aa.states[1].yaw_jitter1.value = 'Delay'; aa.states[1].yaw_jitter2_delay.value = 2
    local c = command(); local count = aa.runtime.pkt_count
    local body = aa.refs.body_yaw[2].value
    emit('setup_command', c); command(1); command(2)
    assert(aa.runtime.pkt_count == count and aa.refs.body_yaw[2].value == body)
    command(); assert(aa.refs.body_yaw[2].value ~= body)
    assert(aa.refs.freestanding_body_yaw.value == false)
end)
test('defensive request is not a detected shift', function()
    aa.refs.double_tap[1].value, aa.refs.double_tap[2].value = true, true
    local cfg = aa.states[1]
    cfg.force_defensive.value, cfg.defensive_anti_aimbot.value, cfg.defensive_pitch.value = true,true,true
    cfg.pitch1.value, cfg.defensive_pitch1.value, cfg.defensive_pitch2.value = 'Down','Custom',-89
    props[1].m_nTickBase = 1000; emit('net_update_end')
    assert(command().force_defensive and aa.refs.pitch[1].value == 'Down')
    props[1].m_nTickBase = 1005; emit('net_update_end'); command(); assert(aa.refs.pitch[1].value == 'Down')
    props[1].m_nTickBase = 1001; emit('net_update_end'); command(); assert(aa.refs.pitch[2].value == -89)
    tick = tick + 4; command(); assert(aa.refs.pitch[1].value == 'Down')
end)
local function start_defensive()
    aa.refs.double_tap[1].value, aa.refs.double_tap[2].value = true, true
    local cfg = aa.states[1]
    cfg.pitch1.value, cfg.defensive_pitch1.value, cfg.defensive_pitch2.value = 'Down', 'Custom', -89
    cfg.defensive_anti_aimbot.value, cfg.defensive_pitch.value, cfg.defensive_yaw.value = true, true, true
    cfg.defensive_yaw1.value, cfg.defensive_yaw2.value = '180', 110
    props[1].m_nTickBase = 1000; emit('net_update_end')
    props[1].m_nTickBase = 994; emit('net_update_end')
end
test('defensive ends immediately when tickbase recovers', function()
    start_defensive(); command(); assert(aa.refs.pitch[2].value == -89)
    props[1].m_nTickBase = 1000; emit('net_update_end'); command()
    assert(aa.refs.pitch[1].value == 'Down', 'recovered tickbase must restore base pitch')
end)
test('successive rollback does not extend existing defensive window', function()
    start_defensive(); local deadline = aa.runtime.def_until
    tick = tick + 1; props[1].m_nTickBase = 988; emit('net_update_end')
    assert(aa.runtime.def_until <= deadline, 'rollback must not extend expiry')
end)
test('defensive yaw owns freestanding and edge until expiry', function()
    start_defensive()
    aa.settings.freestanding.value, aa.settings.edge_yaw.value = true, true
    aa.settings.freestanding_conditions.value = {'Standing'}
    aa.settings.tweaks.value = {'Off jitter while freestanding'}
    command()
    assert(aa.refs.yaw[2].value == 110, 'freestanding overwrote defensive yaw')
    assert(not aa.refs.freestanding[1].value and not aa.refs.edge_yaw.value)
    assert(not aa.refs.freestanding_body_yaw.value)
    tick = aa.runtime.def_until + 1; command()
    assert(aa.refs.pitch[1].value == 'Down' and aa.refs.yaw[2].value == 0)
    assert(aa.refs.freestanding[1].value and aa.refs.edge_yaw.value)
end)
test('disabling exploits invalidates old defensive window', function()
    start_defensive(); command()
    aa.refs.double_tap[1].value = false; command()
    aa.refs.double_tap[1].value = true; command()
    assert(aa.refs.pitch[1].value == 'Down', 're-enable must require a fresh observation')
end)
test('manual and use suppress defensive angles and requests', function()
    start_defensive(); aa.states[1].force_defensive.value = true
    aa.settings.manual_left.value = true; aa.settings.edge_yaw.value = true
    aa.settings.tweaks.value = {'Off jitter on manual'}
    local cmd = command()
    assert(not cmd.force_defensive and aa.refs.pitch[1].value == 'Down')
    assert(aa.refs.yaw[2].value == -90 and not aa.refs.edge_yaw.value)
    aa.states[10].override_state.value, aa.states[10].force_defensive.value = true,true
    aa.states[10].pitch1.value = 'Down'
    cmd = command(0,1); assert(not cmd.force_defensive and aa.refs.pitch[1].value == 'Down')
end)
test('near-impact feedback per shooter and tick; no fake defensive', function()
    aa.settings.anti_brute_head.value = true
    local impact = {userid=2,x=-100,y=0,z=64}
    emit('bullet_impact', impact); emit('bullet_impact', impact)
    assert(aa.runtime.enemy_phase[2] == 2 and aa.runtime.impact_count == 1)
    impact.userid=3; emit('bullet_impact', impact)
    assert(aa.runtime.enemy_phase[3] == 2 and aa.runtime.impact_count == 2)
    tick = tick + 1; emit('bullet_impact', impact); assert(aa.runtime.enemy_phase[3] == 3)
    assert(aa.runtime.def_until == -1)
    impact.userid=1; emit('bullet_impact', impact); assert(aa.runtime.impact_count == 3)
    impact.userid=2; impact.x,impact.y=100,200; emit('bullet_impact',impact); assert(aa.runtime.impact_count == 3)
end)
test('trace origin skip, crouched eye height, cadence, stable cover and clear', function()
    enemies = {2}; trace_side=1
    local function scan() aa.tactical(1,0,0,64,0,vector(0,0,0),0) end
    scan(); assert(trace_skip == 2 and trace_height == 46 and aa.runtime.fs_side == 0)
    local calls=trace_calls; tick=tick+1; scan(); assert(trace_calls==calls)
    tick=tick+3; scan(); assert(aa.runtime.fs_side ~= 0)
    enemies={}; scan(); assert(aa.runtime.fs_side==0 and aa.runtime.fs_best_yaw==0 and aa.runtime.peek_until==-1)
    trace_side=0
end)
test('round, spawn and disconnect clear feedback', function()
    aa.runtime.enemy_phase[2]=4; aa.runtime.impact_tick[2]=tick
    emit('player_disconnect',{userid=2}); assert(aa.runtime.enemy_phase[2]==nil)
    aa.runtime.manual_direction=90; aa.runtime.def_until=tick+8
    emit('player_spawn',{userid=1}); assert(aa.runtime.manual_direction==nil and aa.runtime.def_until==-1)
    aa.runtime.enemy_phase[3]=6; emit('round_prestart'); assert(next(aa.runtime.enemy_phase)==nil)
end)
test('new target does not inherit another shooter phase', function()
    aa.runtime.phase = 5; aa.runtime.enemy_phase[3] = 4
    enemies = {2}; aa.states[1].yaw_jitter1.value = 'Anti-Brute'
    command(); assert(aa.refs.yaw_jitter[2].value == 43)
end)
test('native jitter randomness holds across choked commands', function()
    local cfg=aa.states[1]
    cfg.yaw_jitter1.value='Center'; cfg.yaw_jitter2_randomize.value=80
    command(); local value=aa.refs.yaw_jitter[2].value
    command(1); command(2); assert(aa.refs.yaw_jitter[2].value==value)
end)
test('backstab check skips non-knife hitbox scans', function()
    enemies={2}; aa.settings.avoid_backstab.value=true
    command(); local calls=trace_calls
    command(1); assert(trace_calls==calls+1) -- Only the use-direction trace.
end)
test('custom modes and extreme offsets stay within native sliders', function()
    for _, j in ipairs({'Off','Offset','Center','Random','Skitter','Delay','3-Way','5-Way','Anti-Brute','Tank-AA','Adaptive','Micro-Sway','Per-Tick Adaptive'}) do
        for _, b in ipairs({'Off','Opposite','Jitter','Static','Opposite Jitter','Anti-Brute','Sway','Adaptive Desync','Center Desync Exploit'}) do
            local cfg=aa.states[1]
            cfg.yaw_jitter1.value, cfg.body_yaw1.value=j,b
            cfg.yaw2_left.value,cfg.yaw2_right.value,cfg.yaw2_randomize.value=180,-180,180
            cfg.yaw_jitter2_left.value,cfg.yaw_jitter2_right.value,cfg.yaw_jitter2_randomize.value=180,-180,180
            command()
        end
    end
    assert(aa.normalize(725)==5 and aa.normalize(-725)==-5)
end)
test('Per-Tick Adaptive, Center Desync Exploit and Dynamic Defensive on Peek only trigger defensive on threat', function()
    aa.refs.double_tap[1].value, aa.refs.double_tap[2].value = true, true
    aa.settings.defensive_peek.value = true
    aa.settings.per_tick_aa.value = true
    local cfg = aa.states[1]
    cfg.yaw1.value = '180'
    cfg.pitch1.value = 'Down'
    cfg.yaw_jitter1.value = 'Per-Tick Adaptive'
    cfg.body_yaw1.value = 'Center Desync Exploit'
    cfg.defensive_anti_aimbot.value = true
    cfg.defensive_yaw.value = true
    cfg.defensive_yaw1.value = 'Desync-Exploit Flick'
    -- Standing idle without peek threat: must NOT force defensive every tick
    enemies = { 2 }
    velocity = { 0, 0, 0 }
    local cmd_idle = command(0)
    assert(not cmd_idle.force_defensive, 'must not force defensive when idle with no peek threat')
    assert(aa.refs.pitch[1].value == 'Down' and aa.refs.yaw_jitter[1].value == 'Center')
    -- Simulate real movement peek (>35 u/s) against enemy 2: must trigger defensive on peek
    velocity = { 180, 0, 0 }
    tick = tick + 5
    local cmd_peek = command(0)
    assert(cmd_peek.force_defensive == true, 'must force defensive when peeking an enemy threat')
end)
test('Live Enemy AA Stealer works while dead/spectating via m_hObserverTarget and applies per-state settings', function()
    enemies = { 2 }
    props[1].m_iHealth = 0 -- Local player is dead and spectating player 2
    props[1].m_hObserverTarget = 2
    aa.settings.aa_stealer.value = true
    aa.settings.steal_mode.value = 'Spectated Player (Auto)'
    props[2] = props[2] or {}
    props[2].m_fFlags = 1
    props[2].m_flDuckAmount = 0
    -- Simulate 4 net updates from enemy 2 with Center jitter (-42 / +44) and Down pitch (89)
    local sim_yaws = { -42, 44, -40, 46 }
    for i = 1, #sim_yaws do
        props[2].m_flSimulationTime = 10 + i * 0.03
        props[2]['m_angEyeAngles[0]'] = 89
        props[2]['m_angEyeAngles[1]'] = sim_yaws[i]
        emit('net_update_end')
    end
    aa.steal()
    props[1].m_iHealth = 100
    props[1].m_hObserverTarget = nil
    assert(aa.states[2].override_state.value == true)
    assert(aa.states[2].pitch1.value == 'Down')
    assert(aa.states[2].yaw_jitter1.value == 'Per-Tick Adaptive')
    assert(aa.states[2].yaw_jitter2_left.value <= -40 and aa.states[2].yaw_jitter2_right.value >= 40)
    assert((aa.runtime.steal_progress or 0) > 0, 'scanner progress bar must advance as samples are collected')
end)
print(string.format('%d anti-aim regression groups passed (mock API; not in-game proof)', passed))
