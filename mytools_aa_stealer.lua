-- mytools_aa_stealer.lua
-- Standalone Gamesense Anti-Aim Profiler & Stealer for mytools.lua
-- Profiles any selected enemy player's observable AA per movement state (Standing, Moving, Slowwalk, Crouch, Air)
-- and exports a 100% compatible Base64 config string to clipboard for mytools "Import settings".

local base64 = require 'gamesense/base64'
local clipboard = require 'gamesense/clipboard'

local enable_stealer = ui.new_checkbox('AA', 'Anti-aimbot angles', '\a95b806ff★ Enable mytools AA Stealer')
local target_mode    = ui.new_combobox('AA', 'Anti-aimbot angles', 'Stealer Target Mode', 'Spectated Player (Auto)', 'Selected Player Slot', 'Crosshair / Best Threat')
local manual_slot    = ui.new_slider('AA', 'Anti-aimbot angles', 'Player Slot (1-16)', 1, 16, 1, true)
local draw_steal_hud = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Show Live AA Analyzer HUD')
local auto_export    = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Auto-copy to clipboard on Export click')
ui.set(draw_steal_hud, true)
ui.set(auto_export, true)

local STATE_NAMES = {
    [1] = 'Global',
    [2] = 'Standing',
    [3] = 'Moving',
    [4] = 'Slow motion',
    [5] = 'Crouching',
    [6] = 'Crouching & moving',
    [7] = 'In air',
    [8] = 'In air & crouching',
    [9] = 'No exploits',
    [10] = 'On use'
}

local function normalize_yaw(v)
    return (v + 180) % 360 - 180
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function new_state_bucket()
    return {
        samples = 0,
        pitch_sum = 0,
        zero_pitch_hits = 0,
        up_pitch_hits = 0,
        rel_yaws = {},
        jitter_deltas = {},
        sign_flips = 0,
        pose_vals = {},
        pose_flips = 0,
        defensive_hits = 0,
        def_yaws = {},
        last_rel_yaw = nil,
        last_delta = nil,
        last_pose = nil
    }
end

local profiles = {}
local last_target = nil
local last_status_line = 'Waiting for target (Spectate or select slot)...'
local candidate_slots = {}

local function get_profile(ent)
    if not profiles[ent] then
        local p = {
            last_sim = nil,
            states = {}
        }
        for i = 1, 10 do
            p.states[i] = new_state_bucket()
        end
        profiles[ent] = p
    end
    return profiles[ent]
end

local function reset_profiles()
    profiles = {}
    last_target = nil
end

local function detect_enemy_state(ent)
    local vx = entity.get_prop(ent, 'm_vecVelocity[0]') or 0
    local vy = entity.get_prop(ent, 'm_vecVelocity[1]') or 0
    local spd2d = math.sqrt(vx * vx + vy * vy)
    local flags = entity.get_prop(ent, 'm_fFlags') or 1
    local airborne = bit.band(flags, 1) == 0
    local duck = (entity.get_prop(ent, 'm_flDuckAmount') or 0) >= 0.8
    if airborne then
        return duck and 8 or 7
    elseif duck then
        return (spd2d > 2) and 6 or 5
    elseif spd2d > 2 then
        return (spd2d < 85) and 4 or 3
    end
    return 2
end

local function refresh_candidate_players(me)
    candidate_slots = {}
    local max_clients = globals.maxplayers and globals.maxplayers() or 64
    for ent = 1, max_clients do
        if ent ~= me and entity.get_classname and entity.get_classname(ent) == 'CCSPlayer' then
            if entity.is_alive(ent) and not entity.is_dormant(ent) then
                candidate_slots[#candidate_slots + 1] = ent
            end
        end
    end
    if #candidate_slots == 0 then
        local enemies = entity.get_players(false) or entity.get_players(true) or {}
        for i = 1, #enemies do
            local en = enemies[i]
            if en ~= me and entity.is_alive(en) and not entity.is_dormant(en) then
                candidate_slots[#candidate_slots + 1] = en
            end
        end
    end
    return candidate_slots
end

local function pick_target(me)
    local mode = ui.get(target_mode)
    if mode == 'Spectated Player (Auto)' and me then
        local obs = entity.get_prop(me, 'm_hObserverTarget')
        if obs and obs ~= me and entity.is_alive(obs) and not entity.is_dormant(obs) then
            return obs
        end
    end
    local list = refresh_candidate_players(me)
    if #list == 0 then return nil end
    if mode == 'Selected Player Slot' or (mode == 'Spectated Player (Auto)' and not entity.is_alive(me)) then
        local slot = clamp(ui.get(manual_slot), 1, #list)
        return list[slot]
    end
    local enemies = entity.get_players(true) or list
    if #enemies == 0 then return list[1] end
    local mx, my, mz = entity.get_origin(me)
    if not mx then return enemies[1] end
    local _, cam_yaw = client.camera_angles()
    cam_yaw = cam_yaw or 0
    local best, best_fov = enemies[1], 999
    for i = 1, #enemies do
        local en = enemies[i]
        if entity.is_alive(en) and not entity.is_dormant(en) then
            local ex, ey = entity.get_origin(en)
            if ex then
                local ang = math.deg(math.atan2(ey - my, ex - mx))
                local d = math.abs(normalize_yaw(ang - cam_yaw))
                if d < best_fov then
                    best_fov = d
                    best = en
                end
            end
        end
    end
    return best
end

local function record_enemy_sample(me, ent)
    if not ent or not entity.is_alive(ent) or entity.is_dormant(ent) then return end
    local sim = entity.get_prop(ent, 'm_flSimulationTime')
    if not sim then return end
    local prof = get_profile(ent)
    if prof.last_sim and sim == prof.last_sim then return end

    local dt_shift = prof.last_sim and (sim < prof.last_sim) or false
    prof.last_sim = sim

    local ex, ey = entity.get_origin(ent)
    if not ex then return end

    local rx, ry = nil, nil
    if me and me ~= ent and entity.is_alive(me) then
        rx, ry = entity.get_origin(me)
    end
    if not rx then
        local all = entity.get_players(false) or entity.get_players(true) or {}
        local best_d2 = math.huge
        for i = 1, #all do
            local other = all[i]
            if other ~= ent and entity.is_alive(other) and not entity.is_dormant(other) and entity.is_enemy(other) ~= entity.is_enemy(ent) then
                local ox, oy = entity.get_origin(other)
                if ox then
                    local d2 = (ox - ex) * (ox - ex) + (oy - ey) * (oy - ey)
                    if d2 < best_d2 then best_d2, rx, ry = d2, ox, oy end
                end
            end
        end
    end

    local pitch = entity.get_prop(ent, 'm_angEyeAngles[0]') or 89
    local eye_yaw = entity.get_prop(ent, 'm_angEyeAngles[1]') or 0
    local pose11 = entity.get_prop(ent, 'm_flPoseParameter', 11)
    local body_deg = pose11 and ((pose11 * 120) - 60) or 0

    local vx = entity.get_prop(ent, 'm_vecVelocity[0]') or 0
    local vy = entity.get_prop(ent, 'm_vecVelocity[1]') or 0
    local at_target_back = rx and (math.deg(math.atan2(ry - ey, rx - ex)) + 180)
        or ((math.abs(vx) + math.abs(vy) > 2) and (math.deg(math.atan2(vy, vx)) + 180) or 180)
    local rel_yaw = normalize_yaw(eye_yaw - at_target_back)

    local st_id = detect_enemy_state(ent)
    local pname = (entity.get_player_name and entity.get_player_name(ent)) or ('Ent#' .. tostring(ent))
    for _, bucket_id in ipairs({ 1, st_id }) do
        local b = prof.states[bucket_id]
        b.samples = b.samples + 1
        b.pitch_sum = b.pitch_sum + pitch
        if math.abs(pitch) < 15 then b.zero_pitch_hits = b.zero_pitch_hits + 1 end
        if pitch < -45 then b.up_pitch_hits = b.up_pitch_hits + 1 end

        if dt_shift or math.abs(pitch) < 15 then
            b.defensive_hits = b.defensive_hits + 1
            b.def_yaws[#b.def_yaws + 1] = rel_yaw
            if #b.def_yaws > 32 then table.remove(b.def_yaws, 1) end
        end

        b.rel_yaws[#b.rel_yaws + 1] = rel_yaw
        if #b.rel_yaws > 48 then table.remove(b.rel_yaws, 1) end

        if b.last_rel_yaw ~= nil then
            local delta = normalize_yaw(rel_yaw - b.last_rel_yaw)
            if math.abs(delta) >= 6 then
                b.jitter_deltas[#b.jitter_deltas + 1] = delta
                if #b.jitter_deltas > 48 then table.remove(b.jitter_deltas, 1) end
                if b.last_delta and (delta * b.last_delta < 0) then
                    b.sign_flips = b.sign_flips + 1
                end
                b.last_delta = delta
            end
        end
        b.last_rel_yaw = rel_yaw

        b.pose_vals[#b.pose_vals + 1] = body_deg
        if #b.pose_vals > 48 then table.remove(b.pose_vals, 1) end
        if b.last_pose and (body_deg * b.last_pose < -15) then
            b.pose_flips = b.pose_flips + 1
        end
        b.last_pose = body_deg
    end
    local sb = prof.states[st_id]
    last_status_line = string.format('%s | %s (%d samples) | P:%.0f | RelYaw:%.0f | Body:%.0f',
        pname, STATE_NAMES[st_id] or 'State', sb.samples, pitch, rel_yaw, body_deg)
end

local function solve_bucket_state(b, fallback)
    if not b or b.samples < 3 then
        return fallback
    end
    local avg_pitch = b.pitch_sum / b.samples
    local pitch_mode, pitch_val = 'Down', 89
    if b.up_pitch_hits > b.samples * 0.4 then
        pitch_mode, pitch_val = 'Up', -89
    elseif avg_pitch < 70 and avg_pitch > -45 then
        pitch_mode, pitch_val = 'Custom', clamp(math.floor(avg_pitch + 0.5), -89, 89)
    end

    local left_sum, left_cnt = 0, 0
    local right_sum, right_cnt = 0, 0
    for i = 1, #b.rel_yaws do
        local y = b.rel_yaws[i]
        if y < 0 then
            left_sum, left_cnt = left_sum + y, left_cnt + 1
        else
            right_sum, right_cnt = right_sum + y, right_cnt + 1
        end
    end
    local y_left = left_cnt > 0 and clamp(math.floor(left_sum / left_cnt + 0.5), -180, 180) or -8
    local y_right = right_cnt > 0 and clamp(math.floor(right_sum / right_cnt + 0.5), -180, 180) or 11

    local j_abs_sum = 0
    for i = 1, #b.jitter_deltas do
        j_abs_sum = j_abs_sum + math.abs(b.jitter_deltas[i])
    end
    local avg_j_delta = (#b.jitter_deltas > 0) and (j_abs_sum / #b.jitter_deltas) or 0
    local j_amp = clamp(math.floor(avg_j_delta * 0.5 + 0.5), 0, 90)

    local j_mode = 'Off'
    local j_l, j_r = 0, 0
    if j_amp >= 8 then
        local flip_rate = b.sign_flips / math.max(1, #b.jitter_deltas)
        if flip_rate >= 0.55 then
            j_mode = 'Per-Tick Adaptive'
            j_l = -j_amp
            j_r = j_amp
        elseif flip_rate >= 0.3 then
            j_mode = '3-Way'
            j_l = -j_amp
            j_r = j_amp
        else
            j_mode = 'Center'
            j_l = -j_amp
            j_r = j_amp
        end
        -- When Center jitter is active, keep base left/right near the center mean
        local center_mean = clamp(math.floor((y_left + y_right) * 0.5 + 0.5), -35, 35)
        y_left = clamp(center_mean - 6, -180, 180)
        y_right = clamp(center_mean + 6, -180, 180)
    end

    local by_mode = 'Center Desync Exploit'
    local by_val = -116
    if #b.pose_vals > 0 then
        local pose_flip_rate = b.pose_flips / math.max(1, #b.pose_vals)
        if pose_flip_rate >= 0.35 then
            by_mode = 'Center Desync Exploit'
            by_val = -122
        elseif pose_flip_rate >= 0.12 then
            by_mode = 'Opposite Jitter'
            by_val = -116
        else
            by_mode = 'Static'
            local last_p = b.pose_vals[#b.pose_vals] or -60
            by_val = (last_p < 0) and -110 or 110
        end
    end

    local has_def = b.defensive_hits > 0
    local def_y1 = has_def and 'Desync-Exploit Flick' or 'Hidden-Head Flick'
    local def_y2 = (#b.def_yaws > 0) and clamp(math.floor(b.def_yaws[#b.def_yaws] + 0.5), -180, 180) or -124

    return {
        override = true,
        pitch1 = pitch_mode, pitch2 = pitch_val,
        yaw_base = 'At targets', yaw1 = '180',
        y_l = y_left, y_r = y_right, y_rand = 0,
        j_mode = j_mode, j_l = j_l, j_r = j_r, j_rand = 0, j_delay = 2,
        by_mode = by_mode, by_val = by_val, fs_by = true, roll = 0,
        f_def = false,
        def_aa = true,
        def_p = true,
        def_p1 = 'Custom',
        def_p2 = (b.zero_pitch_hits > 0) and 0 or -89,
        def_p3 = 89,
        def_y = true,
        def_y1 = def_y1,
        def_y2 = def_y2
    }
end

local function build_mytools_export_payload(ent)
    local prof = ent and profiles[ent] or nil
    local global_solved = solve_bucket_state(prof and prof.states[1] or nil, {
        override = true, pitch1 = 'Down', pitch2 = 89, yaw_base = 'At targets', yaw1 = '180',
        y_l = -8, y_r = 11, y_rand = 0,
        j_mode = 'Per-Tick Adaptive', j_l = -47, j_r = 53, j_rand = 0, j_delay = 2,
        by_mode = 'Center Desync Exploit', by_val = -122, fs_by = true, roll = 0,
        f_def = false, def_aa = true, def_p = true, def_p1 = 'Custom', def_p2 = 0, def_p3 = 89,
        def_y = true, def_y1 = 'Desync-Exploit Flick', def_y2 = -124
    })

    local st = {}
    st[1] = global_solved
    for i = 2, 8 do
        st[i] = solve_bucket_state(prof and prof.states[i] or nil, global_solved)
        if i >= 6 then st[i].f_def = true end
    end
    st[9] = solve_bucket_state(prof and prof.states[2] or nil, global_solved)
    st[9].f_def, st[9].def_aa, st[9].def_p, st[9].def_y = false, false, false, false
    st[10] = {
        override = true, pitch1 = 'Off', pitch2 = 0, yaw_base = 'Local view', yaw1 = 'Off',
        y_l = 0, y_r = 0, y_rand = 0,
        j_mode = 'Micro-Sway', j_l = -6, j_r = 6, j_rand = 0, j_delay = 2,
        by_mode = 'Opposite', by_val = 0, fs_by = true, roll = 0,
        f_def = false, def_aa = false, def_p = false, def_p1 = 'Off', def_p2 = 0, def_p3 = 0,
        def_y = false, def_y1 = '180', def_y2 = 0
    }

    -- Pack in exact data.integers order expected by mytools.lua import()
    local arr = { 'Global' }
    local fields = {
        'override', 'f_def', 'pitch1', 'pitch2', 'yaw_base', 'yaw1',
        'y_l', 'y_r', 'y_rand', 'j_mode', 'j_l', 'j_r', 'j_rand', 'j_delay',
        'by_mode', 'by_val', 'fs_by', 'roll',
        'def_aa', 'def_p', 'def_p1', 'def_p2', 'def_p3', 'def_y', 'def_y1', 'def_y2'
    }
    for _, key in ipairs(fields) do
        for i = 1, 10 do
            table.insert(arr, st[i][key])
        end
    end
    -- Trailing 14 settings in mytools data.integers
    table.insert(arr, true) -- avoid_backstab
    table.insert(arr, true) -- safe_head_in_air
    table.insert(arr, { 'Standing', 'Moving', 'Slow motion', 'Crouching' })
    table.insert(arr, { 'Off jitter on manual' })
    table.insert(arr, true)  -- master_switch
    table.insert(arr, false) -- console_filter
    table.insert(arr, true)  -- anim_breakerx
    table.insert(arr, 0)     -- scope_fov
    table.insert(arr, false) -- trashtalk
    table.insert(arr, 0)     -- aspectratio
    table.insert(arr, true)  -- hitmarker
    table.insert(arr, true)  -- fastladder
    table.insert(arr, false) -- clantagchanger
    table.insert(arr, false) -- warmup_disabler

    local encoded = base64.encode(json.stringify({ arr }))
    return encoded, st
end

local function export_stolen_aa()
    local me = entity.get_local_player()
    local target = last_target or (me and pick_target(me))
    local encoded, solved = build_mytools_export_payload(target)
    if ui.get(auto_export) and clipboard and clipboard.set then
        clipboard.set(encoded)
    end
    local tname = (target and entity.get_player_name and entity.get_player_name(target)) or tostring(target or 'default')
    client.color_log(124, 252, 0, "mytools AA Stealer ~\0")
    client.color_log(255, 255, 255, string.format(" Stolen AA from [%s] copied to clipboard! Click 'Import settings' in mytools.", tname))
    return encoded, solved
end

ui.new_button('AA', 'Anti-aimbot angles', '★ Steal & Export Target AA (mytools)', export_stolen_aa)
ui.new_button('AA', 'Anti-aimbot angles', 'Reset AA Stealer Samples', reset_profiles)

client.set_event_callback('net_update_end', function()
    if not ui.get(enable_stealer) then return end
    local me = entity.get_local_player()
    if not me then return end
    local target = pick_target(me)
    if target then
        last_target = target
        record_enemy_sample(me, target)
    end
end)

client.set_event_callback('paint', function()
    if not ui.get(enable_stealer) or not ui.get(draw_steal_hud) or not renderer or not renderer.text then return end
    renderer.text(20, 420, 149, 184, 6, 255, 'b', 0, '★ mytools AA Stealer Live Analyzer')
    renderer.text(20, 436, 255, 255, 255, 230, '', 0, last_status_line)
    if last_target and profiles[last_target] then
        local p = profiles[last_target]
        local y = 454
        for st_id = 2, 8 do
            local b = p.states[st_id]
            if b and b.samples > 0 then
                local solved = solve_bucket_state(b, nil)
                if solved then
                    renderer.text(20, y, 200, 230, 255, 220, '', 0, string.format(
                        '[%s] n=%d -> Pitch:%s | L/R:%d/%d | Jitter:%s(%d/%d) | Body:%s',
                        STATE_NAMES[st_id], b.samples, solved.pitch1, solved.y_l, solved.y_r,
                        solved.j_mode, solved.j_l, solved.j_r, solved.by_mode
                    ))
                    y = y + 15
                end
            end
        end
    end
end)

client.set_event_callback('round_prestart', reset_profiles)

return {
    record = record_enemy_sample,
    export = export_stolen_aa,
    build = build_mytools_export_payload,
    reset = reset_profiles,
    profiles = function() return profiles end,
    STATE_NAMES = STATE_NAMES
}
