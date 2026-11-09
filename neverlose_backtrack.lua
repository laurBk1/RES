-- Neverlose CS:GO legacy. Native ragebot is untouched; manual mode is opt-in.
local group = ui.create('Backtrack | Network-safe')
local enabled = group:switch('Enable', true)
local manual = group:switch('Manual assist (ragebot must be off)', false)
local hvh_rage_bt = group:switch('HvH Rage / SSG 08 extended BT', false)
local ping_spike_sync = group:switch('Auto Ping Spike on SSG 08 / Sniper', false)
local ping_spike_amt = group:slider('Ping Spike target (ms)', 0, 200, 160)
local autowall_bt = group:switch('SSG 08 autowall backtrack (trace_bullet)', true)
local min_bt_dmg = group:slider('Min backtrack damage (SSG 08)', 1, 110, 75)
local prefer_oldest = group:switch('Prefer oldest valid record (max extend)', false)
local draw_trail = group:switch('Draw backtrack trail + HUD', true)
local max_age = group:slider('Record age limit (ms)', 1, 400, 200)
local max_fov = group:slider('Manual FOV (degrees)', 1, 30, 8)
local debug = group:switch('Debug console', false)
local records, identities = {}, {}
local last_time, local_identity, rage_ref, ping_ref, ping_amt_ref, last_error = nil, nil, nil, nil, nil, nil
local last_reason, last_reason_tick = nil, -1
local last_shot_bt = { age_ms = 0, tick = 0, hitbox = 'head', dmg = 0 }
local MAX_RECORDS = 128
-- Hitboxes: 0 = head, 5 = chest, 3 = stomach, 2 = pelvis
local BT_HITBOXES = { 0, 5, 3, 2 }

local function finite(n)
    return type(n) == 'number' and n == n and n > -math.huge and n < math.huge
end

local function clamp(n, lo, hi)
    return math.max(lo, math.min(hi, n))
end

local function point_ok(p)
    return p and finite(p.x) and finite(p.y) and finite(p.z)
end

local function reset()
    records, identities = {}, {}
    last_time, local_identity = nil, nil
    last_reason, last_reason_tick = nil, -1
    if ping_ref then pcall(function() ping_ref:override(nil) end) end
    if ping_amt_ref then pcall(function() ping_amt_ref:override(nil) end) end
end

local function report(reason)
    if not debug:get() then return end
    local tick = globals.tickcount or 0
    if reason ~= last_reason or tick - last_reason_tick >= 128 then
        print('[BT safe] ' .. reason)
        last_reason, last_reason_tick = reason, tick
    end
end

local function read_cvar(name)
    local ok, value = pcall(function() return cvar[name]:float() end)
    return ok and finite(value) and value or nil
end

local function timing()
    local interval, now = globals.tickinterval, globals.curtime
    if not finite(interval) or interval <= 0 or not finite(now) then return nil end
    local unlag = read_cvar('sv_maxunlag')
    local interp, ratio, rate = read_cvar('cl_interp'), read_cvar('cl_interp_ratio'), read_cvar('cl_updaterate')
    if not unlag or unlag <= 0 or not interp or interp < 0 or not ratio or ratio < 0 or not rate or rate <= 0 then return nil end
    local min_rate, max_rate = read_cvar('sv_minupdaterate'), read_cvar('sv_maxupdaterate')
    if min_rate and max_rate and min_rate > 0 and max_rate >= min_rate then
        rate = clamp(rate, min_rate, max_rate)
    end
    if ratio == 0 then ratio = 1 end
    local min_ratio, max_ratio = read_cvar('sv_client_min_interp_ratio'), read_cvar('sv_client_max_interp_ratio')
    if min_ratio and max_ratio and min_ratio >= 0 and max_ratio >= min_ratio then
        ratio = clamp(ratio, min_ratio, max_ratio)
    end
    local lerp = math.max(interp, ratio / rate)
    local channel = utils.net_channel()
    local out_lat = channel and channel.latency and channel.latency[0]
    local in_lat = channel and channel.latency and channel.latency[1]
    local latency = out_lat
    if not finite(latency) or latency < 0 then return nil end
    local rtt = latency + ((finite(in_lat) and in_lat >= 0 and hvh_rage_bt:get()) and in_lat or 0)
    return {now = now, interval = interval, lerp = lerp,
        limit = math.min(max_age:get() / 1000, unlag),
        correction = clamp(rtt + lerp, 0, unlag)}
end

local function valid_record(r, t)
    local age = t.now - r.sim
    -- Conservative client-side filter, not proof of server acceptance.
    return age >= 0 and age <= t.limit and math.abs(t.correction - age) < 0.2
end

local function rage_enabled()
    if not rage_ref then
        for _, name in ipairs({'Enabled', 'Enable'}) do
            local ok, item = pcall(ui.find, 'Aimbot', 'Ragebot', 'Main', name)
            if ok and item then rage_ref = item; break end
        end
    end
    if not rage_ref then return nil end
    local ok, value = pcall(function()
        local override = rage_ref:get_override()
        if override ~= nil then return override end
        return rage_ref:get()
    end)
    if not ok or type(value) ~= 'boolean' then return nil end
    return value
end

local function session()
    if not enabled:get() or not globals.is_in_game then reset(); return nil end
    local lp = entity.get_local_player()
    if not lp or not lp:is_alive() then reset(); return nil end
    local info = lp:get_player_info()
    local id = info and info.userid
    local now = globals.curtime
    if not id or not finite(now) then reset(); return nil end
    if (last_time and now < last_time) or (local_identity and local_identity ~= id) then reset() end
    last_time, local_identity = now, id
    return lp
end

local function collect()
    if not session() then return end
    local allow_rage = hvh_rage_bt:get()
    if not allow_rage and (not manual:get() or rage_enabled() ~= false) then
        records, identities = {}, {}
        return
    end
    local t = timing()
    if not t then records, identities = {}, {}; report('history unavailable: timing data missing'); return end
    local seen = {}
    for _, ply in ipairs(entity.get_players(true)) do
        local idx = ply:get_index()
        if ply:is_alive() and not ply:is_dormant() then
            local info, times = ply:get_player_info(), ply:get_simulation_time()
            local sim = type(times) == 'table' and times.current or nil
            local origin, head = ply:get_origin(), ply:get_hitbox_position(0)
            if info and info.userid and finite(sim) and sim > 0 and sim <= t.now
                and point_ok(origin) and point_ok(head) then
                seen[idx] = true
                local boxes = { [0] = vector(head.x, head.y, head.z) }
                for _, hb in ipairs(BT_HITBOXES) do
                    if hb ~= 0 then
                        local ok_hb, pos = pcall(function() return ply:get_hitbox_position(hb) end)
                        if ok_hb and point_ok(pos) then
                            boxes[hb] = vector(pos.x, pos.y, pos.z)
                        end
                    end
                end
                local list = identities[idx] == info.userid and records[idx] or {}
                local previous = list[#list]
                if previous then
                    local dx, dy, dz = origin.x-previous.origin.x, origin.y-previous.origin.y, origin.z-previous.origin.z
                    if sim < previous.sim or dx*dx + dy*dy + dz*dz > 64*64 then list = {} end
                end
                local kept = {}
                for _, rec in ipairs(list) do
                    if t.now - rec.sim <= t.limit then kept[#kept + 1] = rec end
                end
                list = kept
                if not list[#list] or sim ~= list[#list].sim then
                    list[#list + 1] = {sim = sim, head = vector(head.x, head.y, head.z),
                        origin = vector(origin.x, origin.y, origin.z), boxes = boxes}
                end
                while #list > MAX_RECORDS do table.remove(list, 1) end
                records[idx], identities[idx] = list, info.userid
            end
        end
    end
    for idx in pairs(records) do
        if not seen[idx] then records[idx], identities[idx] = nil, nil end
    end
end

local function fov_to(eye, point, view)
    local dx, dy, dz = point.x-eye.x, point.y-eye.y, point.z-eye.z
    local length = math.sqrt(dx*dx + dy*dy + dz*dz)
    if length <= 0 then return nil end
    local pitch, yaw = math.rad(view.x), math.rad(view.y)
    local cp = math.cos(pitch)
    local dot = (cp*math.cos(yaw)*dx + cp*math.sin(yaw)*dy - math.sin(pitch)*dz) / length
    return math.deg(math.acos(clamp(dot, -1, 1)))
end

local function visible(lp, target, eye, point)
    local ok, trace = pcall(utils.trace_line, eye, point, lp)
    if not ok or not trace or trace.start_solid or trace.all_solid then return false end
    if not finite(trace.fraction) then return false end
    if trace.fraction >= 0.999 then return true end
    return trace.entity ~= nil and trace.entity:get_index() == target:get_index()
end

local function evaluate_record_point(lp, ply, eye, rec, use_autowall, min_dmg)
    if use_autowall and utils and utils.trace_bullet then
        local best_pt, best_dmg = nil, 0
        local boxes = rec.boxes or { [0] = rec.head }
        for _, hb in ipairs(BT_HITBOXES) do
            local pt = boxes[hb]
            if point_ok(pt) then
                local ok, dmg = pcall(utils.trace_bullet, lp, eye, pt)
                if ok and finite(dmg) and dmg >= min_dmg and dmg > best_dmg then
                    best_dmg = dmg
                    best_pt = pt
                end
            end
        end
        if best_pt then return best_pt, best_dmg end
    end
    if visible(lp, ply, eye, rec.head) then
        return rec.head, 100
    end
    return nil, 0
end

local function sync_ping_spike(active_sniper)
    if not ping_spike_sync:get() or not hvh_rage_bt:get() then return end
    if not ping_ref then
        for _, p in ipairs({
            {'Miscellaneous', 'Main', 'Other', 'Fake Latency'},
            {'Aimbot', 'Ragebot', 'Main', 'Ping Spike'},
        }) do
            local ok, item = pcall(ui.find, p[1], p[2], p[3], p[4])
            if ok and item then ping_ref = item; break end
        end
    end
    if ping_ref then
        pcall(function() ping_ref:override(active_sniper and true or nil) end)
    end
    if ping_amt_ref then
        pcall(function() ping_amt_ref:override(active_sniper and ping_spike_amt:get() or nil) end)
    end
end

local function on_move(cmd)
    local lp = session()
    if not lp then return end
    local rage_mode = hvh_rage_bt:get()
    if not manual:get() and not rage_mode then report('native: no command or network overrides'); return end
    local rage = rage_enabled()
    if not rage_mode and rage ~= false then
        report(rage and 'native: ragebot active' or 'manual blocked: ragebot state unknown')
        return
    end
    if cmd.in_use == true or cmd.in_use == 1 then return end
    local weapon = lp:get_player_weapon()
    local info = weapon and weapon:get_weapon_info()
    -- Firearms only: pistol, SMG, rifle, shotgun, sniper, machinegun.
    if not info or not finite(info.weapon_type) or info.weapon_type < 1 or info.weapon_type > 6 then return end
    sync_ping_spike(info.weapon_type == 5)
    if cmd.in_attack ~= true and cmd.in_attack ~= 1 then return end
    local t = timing()
    local eye, view = lp:get_eye_position(), cmd.view_angles
    if not t or not point_ok(eye) or not point_ok(view) then report('manual blocked: timing/view unavailable'); return end
    local use_aw = rage_mode and autowall_bt:get()
    local eff_fov = rage_mode and 180 or max_fov:get()
    local want_oldest = rage_mode and prefer_oldest:get()
    local best, best_pt, best_dmg, best_fov, target_index = nil, nil, 0, eff_fov, nil
    for _, ply in ipairs(entity.get_players(true)) do
        local idx = ply:get_index()
        local player_info = ply:get_player_info()
        if ply:is_alive() and not ply:is_dormant() and player_info and identities[idx] == player_info.userid then
            local list = records[idx] or {}
            local hp = (type(ply.m_iHealth) == 'number' and ply.m_iHealth > 0) and ply.m_iHealth or 100
            local req_dmg = math.min(min_bt_dmg:get(), hp)
            for i = #list, 1, -1 do
                local rec = list[i]
                if valid_record(rec, t) then
                    local fov = fov_to(eye, rec.head, view)
                    local better_choice = false
                    if want_oldest then
                        better_choice = fov and fov <= eff_fov and (not best or rec.sim < best.sim)
                    else
                        better_choice = fov and (fov < best_fov or (fov == best_fov and (not best or rec.sim > best.sim)))
                    end
                    if better_choice then
                        local pt, dmg = evaluate_record_point(lp, ply, eye, rec, use_aw, req_dmg)
                        if pt then
                            best, best_pt, best_dmg, best_fov, target_index = rec, pt, dmg, fov, idx
                        end
                    end
                end
            end
        end
    end
    if not best then report('manual: no eligible record inside FOV'); return end
    local aim_point = best_pt or best.head
    local delta = eye:to(aim_point)
    local angles = delta:angles()
    if not point_ok(angles) then return end
    local shot_tick = math.floor((best.sim + t.lerp) / t.interval + 0.5)
    -- Commit only after validation; packet, attack and movement fields stay untouched.
    cmd.view_angles = vector(angles.x, angles.y, 0)
    cmd.tickcount = shot_tick
    last_shot_bt.age_ms = (t.now - best.sim) * 1000
    last_shot_bt.tick = shot_tick
    last_shot_bt.dmg = best_dmg
    report(('manual candidate P%d age=%.0fms fov=%.2f tick=%d choke=%d'):format(
        target_index, (t.now-best.sim)*1000, best_fov, shot_tick, cmd.choked_commands or 0))
end

local function on_render()
    if not enabled:get() or not draw_trail:get() or not render or not render.world_to_screen then return end
    local t = timing()
    if not t then return end
    for _, list in pairs(records) do
        local prev_screen = nil
        for i = 1, #list do
            local rec = list[i]
            if valid_record(rec, t) then
                local ok_s, s = pcall(render.world_to_screen, rec.head)
                if ok_s and s and finite(s.x) and finite(s.y) then
                    local age_ratio = clamp((t.now - rec.sim) / math.max(0.001, t.limit), 0, 1)
                    if color and render.circle_outline then
                        local c = color(math.floor(255 * age_ratio), math.floor(255 * (1 - age_ratio)), 120, 220)
                        pcall(render.circle_outline, s, c, 3, 0, 1, 1)
                        if prev_screen and render.line then
                            pcall(render.line, prev_screen, s, c)
                        end
                    end
                    prev_screen = s
                end
            end
        end
    end
end

local function guarded(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            reset()
            if last_error ~= tostring(err) then
                print('[BT safe] callback aborted: ' .. tostring(err))
                last_error = tostring(err)
            end
        end
    end
end

enabled:set_callback(reset)
manual:set_callback(reset)
hvh_rage_bt:set_callback(reset)
events.net_update_end:set(guarded(collect))
events.createmove:set(guarded(on_move))
events.render:set(guarded(on_render))
events.level_init:set(reset)
events.round_start:set(reset)
events.player_spawn:set(reset)
events.player_disconnect:set(reset)
events.shutdown:set(reset)
