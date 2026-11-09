--[[
    bt_extend_v2.lua  |  FIX linia 113 + head-only manual mode
    CS:GO legacy  |  Neverlose  |  path: <csgo>/nl/scripts/
    - Ragebot ON  -> mod nativ, script NU atinge aim/fire/tickcount, doar choke lag
    - Ragebot OFF -> mod manual, aim exclusiv head + in_attack + send_packet
--]]

local MAX_REC = 64
local recs, last_sim = {}, {}
local hud = { shift = 0, choke = 0, mode = '-', state = 'idle', target = '-', hg = '-' }
local font, flush_tick, last_label, err_count = nil, -1, nil, 0
local rage_ref, cfg_done = nil, false

local sidebar = ui.sidebar('BT Extend v2', 'clock-rotate-left')
local PRESET_LIST = { 'Auto (by weapon)', 'SSG-08', 'AWP', 'Pistol', 'Rifle' }

local main = ui.create('Main', 'Auto')
local enable    = main:switch('Enable', true)
local preset    = main:combo('Preset', unpack(PRESET_LIST))
local auto_mode = main:switch('Auto-detect (skip if ragebot on)', true)
local manual_on = main:switch('Force manual mode', false)
local debug_log = main:switch('Debug console', false)

local tune = ui.create('Tuning', 'Sliders')
local max_shift   = tune:slider('Max shift', 1, 64, 40, 1, ' ticks')
local aim_fov     = tune:slider('Aim FOV', 1, 60, 8, 1, ' deg')
local fire_delay  = tune:slider('Fire delay', 0, 8, 1, 1, ' ticks')
local head_off    = tune:slider('Head offset Z', -4, 8, 1, 1, ' units')
local min_dmg     = tune:slider('Min damage override', 0, 200, 101, 1, '')
local vis_check   = tune:switch('Require head visible', true)
local force_send  = tune:switch('Force send on shot', true)

local lag = ui.create('Choke lag', 'Network')
local lag_on      = lag:switch('Choke lag ON', true)
local choke_cap   = lag:slider('Choke cap', 4, 16, 10, 1, ' cmds')

local vis = ui.create('Visuals', 'Eye')
local draw_hud = vis:switch('HUD', true)

local function tick_interval()
    local ti = globals.tickinterval
    if ti and ti > 0 then return ti end
    return 1 / 64
end

local function find_any(list)
    for _, p in ipairs(list) do
        local ok, it = pcall(ui.find, unpack(p))
        if ok and it then return it end
    end
end

local function try_override(item, value)
    if item then pcall(function() item:override(value) end) end
end

local function combo_str(item, list)
    local v = item:get()
    if type(v) == 'number' then return list[v] end
    return v
end

local function log(msg)
    if debug_log:get() then print('[bt2] ' .. msg) end
end

local function configure_once()
    if cfg_done then return end
    cfg_done = true
    pcall(function() cvar.cl_interp_ratio:int(2) end)
    rage_ref = find_any({
        { 'Aimbot', 'Ragebot', 'Main', 'Enable' },
        { 'Aimbot', 'Ragebot', 'Main', 'Enabled' },
    })
end

local function ragebot_on()
    if not rage_ref then return false end
    local v = false
    pcall(function() v = rage_ref:get() end)
    return v == true
end

local function apply_preset()
    local lp = entity.get_local_player()
    if not lp then return end
    local wpn = lp:get_player_weapon()
    local info = wpn and wpn:get_weapon_info() or nil

    local manual = combo_str(preset, PRESET_LIST)
    local label = manual
    if manual == 'Auto (by weapon)' then
        if not info then return end
        local wt = info.weapon_type
        if wt == 0 or wt == 7 or wt == 8 then hud.mode = 'none'; return end
        if wt == 5 then
            local n = (info.weapon_name or ''):lower()
            label = n:find('awp') and 'AWP' or 'SSG-08'
        elseif wt == 1 then label = 'Pistol'
        else label = 'Rifle' end
    end
    if label == last_label then return end
    last_label = label
    hud.mode = label
end

-- FIX LINIA 113: get_simulation_time sigur, fara colon fara paranteze
local function note_record(ply)
    local idx = ply:get_index()

    local ok, sim = pcall(function() return ply:get_simulation_time() end)
    if not ok or not sim then return end
    if type(sim) == 'table' then sim = sim.current end
    if not sim then return end
    if last_sim[idx] == sim then return end
    last_sim[idx] = sim

    local ok_hb, hb = pcall(function() return ply:get_hitbox_position(0) end)
    if not ok_hb or not hb then return end

    local list = recs[idx]
    if not list then list = {}; recs[idx] = list end
    list[#list + 1] = { tick = globals.tickcount, head = hb }
    if #list > MAX_REC then table.remove(list, 1) end
end

local function real_budget(cmd)
    local chan = utils.net_channel()
    local lat = 0
    if chan then lat = chan.avg_latency[0] or 0 end
    local window = math.floor(math.min(max_shift:get(), lat / tick_interval()) + 0.5)
    local unacked = math.max(0, (globals.last_outgoing_command or 0) - (globals.commandack or 0))
    local used = math.max(cmd.choked_commands or 0, unacked)
    hud.choke = used
    return window - used
end

local function head_visible(lp, ply, point)
    local vis_ok = false
    pcall(function() vis_ok = ply:is_visible() end)
    if not vis_ok then return false end

    local eye = lp:get_eye_position()
    if not eye then return false end

    local ok, tr = pcall(utils.trace_line, eye, point, lp)
    if not ok or not tr then return true end
    if tr.fraction and tr.fraction < 0.97 then return false end
    return true
end

local function select_head_record(lp, window)
    local now = globals.tickcount
    local best, best_ply, best_age = nil, nil, -1

    for _, ply in ipairs(entity.get_players(true)) do
        if ply:is_alive() and not ply:is_dormant() then
            local list = recs[ply:get_index()]
            if list then
                for i = #list, 1, -1 do
                    local r = list[i]
                    local age = now - r.tick
                    if age >= 1 and age <= window then
                        local aim = r.head + vector(0, 0, head_off:get())
                        if not vis_check:get() or head_visible(lp, ply, aim) then
                            if age > best_age then
                                best_age, best, best_ply = age, r, ply
                            end
                        end
                    elseif age > window then break end
                end
            end
        end
    end
    return best, best_ply
end

local function angle_to(eye, point, view)
    local fwd = vector():angles(view.x, view.y)
    local dir = eye:to(point)
    local len = dir:length()
    if len == 0 then return 999 end
    local dot = fwd:dot(dir:scaled(1 / len))
    if dot > 1 then dot = 1 elseif dot < -1 then dot = -1 end
    return math.deg(math.acos(dot))
end

local function drive_lag(cmd)
    if not lag_on:get() then return end
    local current = cmd.choked_commands or 0
    if globals.tickcount <= flush_tick or current >= choke_cap:get() then
        cmd.send_packet = true
        return
    end
    cmd.send_packet = false
end

local function on_createmove(cmd)
    if not globals.is_in_game then return end
    configure_once()
    apply_preset()

    local lp = entity.get_local_player()
    if not lp or not lp:is_alive() then hud.state = 'dead'; return end
    if not enable:get() then hud.state = 'off'; return end

    drive_lag(cmd)
    for _, ply in ipairs(entity.get_players(true)) do note_record(ply) end

    -- Decizie mod
    local use_manual = manual_on:get()
    if auto_mode:get() then
        use_manual = not ragebot_on()
    end

    -- NATIV: ragebot-ul tau preia. Nu atingem nimic in afara de choke lag.
    -- Fortam min damage sus ca sa nu mai dea body.
    if not use_manual then
        if ragebot_on() and min_dmg:get() > 0 then
            local dmg = ui.find('Aimbot', 'Ragebot', 'Selection', 'Min. Damage')
            if dmg then try_override(dmg, min_dmg:get()) end
        end
        hud.state = 'native (ragebot)'
        return
    end

    -- MANUAL: control complet, head-only, fara fallback
    local eye = lp:get_eye_position()
    if not eye then return end

    local budget = real_budget(cmd)
    if budget < 1 then hud.state = 'no budget'; return end
    budget = math.min(budget, max_shift:get())

    local rec, target_ply = select_head_record(lp, budget)
    if not rec then
        hud.shift, hud.state, hud.target = budget, 'no head rec', '-'
        return
    end

    cmd.tickcount = rec.tick
    hud.shift = globals.tickcount - rec.tick
    hud.target = target_ply:get_name() or '?'
    hud.hg = 'head'

    local aim = rec.head + vector(0, 0, head_off:get())
    local ang = eye:to(aim):angles()
    cmd.view_angles = vector(ang.x, ang.y, 0)

    local fov = angle_to(eye, aim, cmd.view_angles)
    if fov > aim_fov:get() and not cmd.in_attack then
        hud.state = 'out of fov'
        return
    end

    if globals.tickcount - flush_tick >= fire_delay:get() then
        cmd.in_attack = true
        if force_send:get() then cmd.send_packet = true end
        flush_tick = globals.tickcount
        hud.state = 'FIRE HEAD'
        log(('FIRE %s shift=%d'):format(hud.target, hud.shift))
    else
        hud.state = 'armed'
    end
end

events.createmove:set(function(cmd)
    local ok, err = pcall(on_createmove, cmd)
    if not ok then
        err_count = err_count + 1
        if err_count <= 3 then print('[bt2] ' .. tostring(err)) end
    end
end)

events.render:set(function()
    if not draw_hud:get() then return end
    if not font then
        font = render.load_font('Verdana', 14, 'ad')
        if not font then return end
    end
    local lines = {
        { color(60, 200, 255), 'BT2 [' .. hud.mode .. ']' },
        { color(200, 200, 200), 'state: ' .. hud.state },
        { color(200, 200, 200), ('shift %d | choke %d | hg %s'):format(hud.shift, hud.choke, hud.hg) },
        { color(200, 200, 200), ('target: %s'):format(hud.target) },
    }
    for i, l in ipairs(lines) do
        render.text(font, vector(16, 16 + (i - 1) * 15), l[1], 's', l[2])
    end
end)

common.add_event('bt2 loaded', 'bolt')