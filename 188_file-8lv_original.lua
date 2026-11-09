--[[
    AWP AX EXPLOIT — body force + instant shot + prediction gate
                     + auto peek / unpeek / DT / fake lag / AA assist
    API: https://docs-csgo.neverlose.cc/
    Config necesar: Double tap sau Hide shots activat pe AWP, Exploit pornit.
]]

local ST = { IDLE = 1, HOLD = 2, FIRE = 3, RETREAT = 4 }

local menu = ui.create("Scripts", "AWP AX Exploit")

local enable        = menu:switch("Enable", true)
local weapon_sel    = menu:selectable("Weapons", "AWP", "SSG 08")
local body_only     = menu:switch("Force body hitboxes", true)
local hitbox_sel    = menu:selectable("Hitboxes", "Chest", "Stomach", "Pelvis", "Arms", "Legs", "Feet")

local exploit_ctl   = menu:switch("Exploit control", true)
local hide_shots    = menu:switch("Hide shots", true)
local double_tap    = menu:switch("Double tap on shot", true)
local teleport      = menu:switch("Teleport on shot", false)
local min_charge    = menu:slider("Min charge", 0, 1, 1, 100)
local recharge_ms   = menu:slider("Recharge block (ms)", 0, 800, 260, 1)

local instant       = menu:switch("Instant shot", true)
local delay_shot    = menu:switch("Delay shot until hittable", true)
local auto_scope    = menu:switch("Auto scope", true)
local only_ground   = menu:switch("Only on ground", true)

local pred_mode     = menu:combo("Prediction mode", "Smart lateral gate", "Direction change", "Off")
local lateral_tol   = menu:slider("Lateral tolerance (u)", 4, 40, 14, 1)
local max_lead      = menu:slider("Max lead (ms)", 0, 400, 200, 1)
local bullet_speed  = menu:slider("Bullet speed (u/s)", 1000, 5000, 3000, 1)
local min_damage    = menu:slider("Min damage", 1, 100, 45, 1)

local peek_key      = menu:hotkey("Auto peek key", 0x58)
local peek_dist     = menu:slider("Peek distance (u)", 10, 80, 40, 1)
local retreat_ms    = menu:slider("Retreat after shot (ms)", 0, 600, 180, 1)

local fake_lag      = menu:switch("Fake lag (idle)", true)
local fake_lag_ticks= menu:slider("Fake lag ticks", 1, 16, 6, 1)

local aa_assist     = menu:switch("AA assist (inverter on shot)", true)
local draw_hud      = menu:switch("Draw HUD", true)
local debug         = menu:switch("Debug prints", false)

weapon_sel:set({ "AWP" })
hitbox_sel:set({ "Chest", "Stomach", "Pelvis" })

-- ───────────────────────── state ─────────────────────────
local state, prev_state = ST.IDLE, ST.IDLE
local peek_sign = 1
local retreat_until, recharge_until = 0, 0
local last_vel = {}
local overridden_item
local hud = { dmg = 0, lat = 0, charge = 0, note = "-" }

-- ───────────────────────── helpers ─────────────────────────
local function hotkey_on(item)
    local v = item:get()
    if type(v) == "boolean" then return v end
    return v ~= nil and v ~= 0
end

local function is_valid_weapon(me)
    local wep = me:get_player_weapon()
    if not wep then return false, nil end
    local allowed = weapon_sel:get()
    if type(allowed) ~= "table" then return false, nil end
    local cn = wep:get_classname()
    if cn == "CWeaponAWP" and allowed[1] then return true, "AWP" end
    if cn == "CWeaponSSG08" and allowed[2] then return true, "SSG 08" end
    return false, nil
end

local function find_hitbox_item(weapon_name)
    local cats, tabs = { "Aimbot", "Ragebot" }, { "Weapons", "Weapon settings", "Per weapon" }
    local names = { "Hitboxes", "Hitbox", "Target hitboxes", "Prefer hitboxes" }
    for _, c in ipairs(cats) do
        for _, t in ipairs(tabs) do
            for _, n in ipairs(names) do
                local ok, item = pcall(ui.find, c, t, weapon_name, n)
                if ok and item then return item end
            end
        end
    end
    return nil
end

local function apply_hitboxes(weapon_name)
    if not body_only:get() then
        if overridden_item then overridden_item:override(nil) end
        overridden_item = nil
        return
    end
    local sel = hitbox_sel:get()
    if type(sel) ~= "table" or #sel == 0 then return end
    local item = find_hitbox_item(weapon_name)
    if not item then return end
    overridden_item = item
    item:override(sel)
end

local function clear_hitboxes()
    if overridden_item then overridden_item:override(nil) end
    overridden_item = nil
end

local function reset()
    clear_hitboxes()
    state = ST.IDLE
    hud.dmg, hud.lat, hud.note = 0, 0, "-"
end

local function angle_delta(a, b)
    local d = math.abs(a - b) % 360
    return d > 180 and (360 - d) or d
end

local function best_target(me, view)
    local eye = me:get_eye_position()
    local best, score_best
    for _, p in ipairs(entity.get_players(true)) do
        if p:is_alive() and not p:is_dormant() then
            local ang = (eye:to(p:get_origin())):angles()
            local score = angle_delta(ang.y, view.y) + angle_delta(ang.x, view.x) * 0.5
            if score < (score_best or 70) then best, score_best = p, score end
        end
    end
    return best
end

-- timp pana la impact: jumatate din RTT out + jumatate din RTT in + zbor
local function lead_time(eye, point)
    local net = utils.net_channel()
    if not net then return 0 end
    local latency = ((net.avg_latency[0] or 0) + (net.avg_latency[1] or 0)) * 0.5
    local travel = eye:dist(point) / bullet_speed:get()
    return math.min(latency + travel, max_lead:get() / 1000)
end

-- extrapolare cu simularea de movement a jocului, fallback liniar
local function predict(target, eye, point, t)
    local ticks = math.clamp(math.floor(t / globals.tickinterval + 0.5), 1, 32)
    local ok, sim = pcall(function() return target:simulate_movement() end)
    if ok and sim then
        sim:think(ticks)
        return sim.origin + vector(0, 0, 46)
    end
    local anim = target:get_anim_state()
    local vel = anim and anim.velocity or vector(0, 0, 0)
    return point + vel * t
end

-- latura pe care iese din cover (damage cumulat pe 3 distante)
local function choose_side(me, target, view)
    local eye = me:get_eye_position()
    local aim = target:get_origin() + vector(0, 0, 46)
    local yaw = math.rad(view.y)
    local right = vector(math.sin(yaw), -math.cos(yaw), 0)
    local best_sign, best_score = 0, -1

    for _, sign in ipairs({ 1, -1 }) do
        local score = 0
        for _, d in ipairs({ peek_dist:get() * 0.5, peek_dist:get(), peek_dist:get() * 1.6 }) do
            local damage, trace = utils.trace_bullet(me, eye + right * (sign * d), aim)
            if trace and trace.entity == target then score = score + damage end
        end
        if score > best_score then best_sign, best_score = sign, score end
    end
    return best_score > 0 and best_sign or 0
end

-- ───────────────────────── createmove ─────────────────────────
events.createmove:set(function(cmd)
    local me = entity.get_local_player()
    if not me or not me:is_alive() or not enable:get() then reset() return end

    local ok, weapon_name = is_valid_weapon(me)
    if not ok then reset() return end
    apply_hitboxes(weapon_name)

    local wep = me:get_player_weapon()
    local ammo = wep and wep.m_iClip1 or 0
    local reloading = wep and (wep:get_weapon_reload() or -1) >= 0
    local scoped = me.m_bIsScoped == true or me.m_bIsScoped == 1
    local on_ground = bit.band(me.m_fFlags, 1) ~= 0
    local curtime = globals.curtime
    local charge = rage.exploit:get() or 0
    local target = best_target(me, cmd.view_angles)

    hud.charge, hud.dmg, hud.lat = charge, 0, 0

    if auto_scope:get() and not scoped then cmd.in_attack2 = true end

    local want_fire = false

    if target then
        local eye = me:get_eye_position()
        local point = target:get_origin() + vector(0, 0, 46)
        local predicted = predict(target, eye, point, lead_time(eye, point))

        local damage, trace = utils.trace_bullet(me, eye, point)
        local hittable = trace and trace.entity == target and damage >= min_damage:get()
        hud.dmg = damage or 0

        local dir = (point - eye):normalized()
        local delta = predicted - point
        local lateral = (delta - dir * delta:dot(dir)):length()
        hud.lat = lateral

        local anim = target:get_anim_state()
        local vel = anim and anim.velocity
        local idx = target:get_index()
        local reversing = false
        if vel then
            local lv = last_vel[idx]
            reversing = lv ~= nil and vel:dot(lv) < 0
            last_vel[idx] = vel
        end

        local mode = pred_mode:get()
        local lead_ok
        if mode == 3 then lead_ok = true
        elseif mode == 2 then lead_ok = reversing and lateral <= lateral_tol:get() * 2
        else lead_ok = lateral <= lateral_tol:get() end

        want_fire = hittable and lead_ok
            and ((not exploit_ctl:get()) or charge >= min_charge:get())
            and curtime >= recharge_until
            and ((not only_ground:get()) or on_ground)
            and ammo > 0 and not reloading and scoped

        if want_fire then state = ST.FIRE
        elseif curtime < retreat_until then state = ST.RETREAT
        else state = ST.HOLD end

        if hotkey_on(peek_key) and state ~= ST.FIRE then
            if not hittable and state == ST.HOLD then
                local side = choose_side(me, target, cmd.view_angles)
                if side ~= 0 then peek_sign = side end
            end
            if state == ST.RETREAT then
                cmd.sidemove = -peek_sign * 450
            elseif state == ST.HOLD then
                cmd.sidemove = peek_sign * 450
            end
        end

        hud.note = want_fire and "FIRE" or (hittable and "LEAD" or "OCCLUDED")
    else
        state = ST.IDLE
        hud.note = "NO TARGET"
    end

    -- exploatare
    if exploit_ctl:get() then
        if state == ST.FIRE then
            rage.exploit:allow_charge(true)
            rage.exploit:allow_defensive(true)
            rage.exploit:force_charge()
            if double_tap:get() then cmd.force_defensive = true end
            if teleport:get() then rage.exploit:force_teleport() end
        else
            rage.exploit:allow_charge(true)
            if hide_shots:get() then rage.exploit:allow_defensive(false) end
        end
    end

    -- shot / hold
    if state == ST.FIRE then
        cmd.send_packet = true
        cmd.no_choke = true
        cmd.block_movement = 2
        if instant:get() then cmd.in_attack = true end
    elseif delay_shot:get() then
        cmd.in_attack = false
    end

    -- fake lag (nu concureaza cu discharge-ul)
    if fake_lag:get() and state ~= ST.FIRE and curtime >= recharge_until then
        local cap = math.min(fake_lag_ticks:get(), cvar.sv_maxusrcmdprocessticks:int() or 16)
        if globals.choked_commands < cap then cmd.send_packet = false end
    end

    -- efecte la tranzitia in FIRE
    if state == ST.FIRE and prev_state ~= ST.FIRE then
        recharge_until = curtime + recharge_ms:get() / 1000
        retreat_until = curtime + retreat_ms:get() / 1000
        if aa_assist:get() then rage.antiaim:inverter(not rage.antiaim:inverter()) end
    end
    prev_state = state
end)

-- ───────────────────────── HUD ─────────────────────────
events.render:set(function()
    if not draw_hud:get() or not enable:get() then return end
    local me = entity.get_local_player()
    if not me or not me:is_alive() then return end

    local size = render.screen_size()
    local base = vector(size.x * 0.5 - 90, size.y * 0.75)

    render.rect(base, base + vector(180, 54), color(10, 10, 12, 190), 4)
    render.rect_outline(base, base + vector(180, 54), color(0, 200, 255, 120), 1, 4)

    local c = hud.note == "FIRE" and color(80, 240, 130) or color(240, 240, 240)
    render.text(4, base + vector(8, 6), c, nil, "STATE: ", hud.note)
    render.text(2, base + vector(8, 22), color(200, 200, 200, 220), nil,
        ("dmg %d | lat %.1f | ch %.0f%%"):format(hud.dmg, hud.lat, hud.charge * 100))

    render.rect(base + vector(8, 40), base + vector(172, 45), color(25, 25, 25, 220), 2)
    render.rect(base + vector(8, 40), base + vector(8 + 164 * hud.charge, 45),
        hud.charge >= min_charge:get() and color(60, 220, 120, 230) or color(220, 170, 60, 230), 2)
end)

-- ───────────────────────── events ─────────────────────────
events.aim_fire:set(function(e)
    retreat_until = globals.curtime + retreat_ms:get() / 1000
    if not debug:get() then return end
    local g = { [0] = "generic", "head", "chest", "stomach", "larm", "rarm", "lleg", "rleg", "neck", "gear" }
    print(("[ax] fire %s | hg %s | dmg %d"):format(e.target:get_name(), g[e.hitgroup] or "?", e.damage))
end)

events.aim_ack:set(function(e)
    if not debug:get() or not e.state then return end
    print(("[ax] miss: %s"):format(e.state))
end)

events.shutdown:set(clear_hitboxes)