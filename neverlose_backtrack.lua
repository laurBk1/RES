-- Neverlose CS:GO legacy. Native ragebot is untouched; manual mode is opt-in.
local group = ui.create('Backtrack | Network-safe')
local enabled = group:switch('Enable', true)
local manual = group:switch('Manual assist (ragebot must be off)', false)
local max_age = group:slider('Record age limit (ms)', 1, 200, 150)
local max_fov = group:slider('Manual FOV (degrees)', 1, 30, 8)
local debug = group:switch('Debug console', false)
local records, identities = {}, {}
local last_time, local_identity, rage_ref, last_error = nil, nil, nil, nil
local last_reason, last_reason_tick = nil, -1
local MAX_RECORDS = 128

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
    local latency = channel and channel.latency and channel.latency[0]
    if not finite(latency) or latency < 0 then return nil end
    return {now = now, interval = interval, lerp = lerp,
        limit = math.min(max_age:get() / 1000, unlag),
        correction = clamp(latency + lerp, 0, unlag)}
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
    -- Only the opt-in manual path consumes this history.
    if not manual:get() or rage_enabled() ~= false then records, identities = {}, {}; return end
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
                        origin = vector(origin.x, origin.y, origin.z)}
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

local function on_move(cmd)
    local lp = session()
    if not lp then return end
    if not manual:get() then report('native: no command or network overrides'); return end
    local rage = rage_enabled()
    if rage ~= false then
        report(rage and 'native: ragebot active' or 'manual blocked: ragebot state unknown')
        return
    end
    if cmd.in_attack ~= true and cmd.in_attack ~= 1 then return end
    if cmd.in_use == true or cmd.in_use == 1 then return end
    local weapon = lp:get_player_weapon()
    local info = weapon and weapon:get_weapon_info()
    -- Firearms only: pistol, SMG, rifle, shotgun, sniper, machinegun.
    if not info or not finite(info.weapon_type) or info.weapon_type < 1 or info.weapon_type > 6 then return end
    local t = timing()
    local eye, view = lp:get_eye_position(), cmd.view_angles
    if not t or not point_ok(eye) or not point_ok(view) then report('manual blocked: timing/view unavailable'); return end
    local best, best_fov, target_index = nil, max_fov:get(), nil
    for _, ply in ipairs(entity.get_players(true)) do
        local idx = ply:get_index()
        local player_info = ply:get_player_info()
        if ply:is_alive() and not ply:is_dormant() and player_info and identities[idx] == player_info.userid then
            local list = records[idx] or {}
            for i = #list, 1, -1 do
                local rec = list[i]
                if valid_record(rec, t) then
                    local fov = fov_to(eye, rec.head, view)
                    if fov and (fov < best_fov or (fov == best_fov and (not best or rec.sim > best.sim)))
                        and visible(lp, ply, eye, rec.head) then
                        best, best_fov, target_index = rec, fov, idx
                    end
                end
            end
        end
    end
    if not best then report('manual: no eligible record inside FOV'); return end
    local delta = eye:to(best.head)
    local angles = delta:angles()
    if not point_ok(angles) then return end
    local shot_tick = math.floor((best.sim + t.lerp) / t.interval + 0.5)
    -- Commit only after validation; packet, attack and movement fields stay untouched.
    cmd.view_angles = vector(angles.x, angles.y, 0)
    cmd.tickcount = shot_tick
    report(('manual candidate P%d age=%.0fms fov=%.2f tick=%d choke=%d'):format(
        target_index, (t.now-best.sim)*1000, best_fov, shot_tick, cmd.choked_commands or 0))
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
events.net_update_end:set(guarded(collect))
events.createmove:set(guarded(on_move))
events.level_init:set(reset)
events.round_start:set(reset)
events.player_spawn:set(reset)
events.player_disconnect:set(reset)
events.shutdown:set(reset)
