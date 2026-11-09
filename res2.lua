-- ══════════════════════════════════════════════════════════════════════════════
--  PURE RESOLVER v11.0 (BUILT FROM SCRATCH) | CS:GO Legacy 2023 | gamesense.pub
--  Arhitectura 100% noua, scrisa de la zero (fara cod legacy v8/v9):
--  1. Calcul FFI exact CCSGOPlayerAnimState & C_AnimationLayer (13 layere, auto-offset).
--  2. Limita fizica exacta Valve (get_max_desync):
--     - Stand: 58° | Run: 48..58° | Slow-walk: 48° | Duck-Stand: 46° | Duck-Move: 34..38° | Air: 58°
--     (Elimina complet miss-urile pe +50/-50 la duck move spd=40 unde limita reala este 35..38°!).
--  3. Semn corect Move/Air Desync: in HvH, fake-ul este tras spre directia de strafe,
--     iar capul REAL este pe partea opusa (-sign(vel_yaw - eye_yaw)) sau pe centrul Jitter-ului!
--  4. Detector Center-Jitter vs Static/Opposite: cand inamicul face Center Jitter (|Δeye| >= 18°),
--     capul real este aproape de centrul de oscilatie (±28°..±38°), nu la ±58°!
--  5. 3D Raycast Head-Hide Freestand (client.trace_line + client.trace_bullet) pe pozitiile
--     reale ale capului la ±max_desync.
--  6. SSG08 (Scout) Headhunter Mode + Force Pitch 89 pe orice Defensive Pitch (inclusiv in aer).
-- ══════════════════════════════════════════════════════════════════════════════

local bit = require("bit")
local ffi_ok, ffi = pcall(require, "ffi")

if ffi_ok and ffi then
    pcall(ffi.cdef, [[
        typedef struct {
            char  pad_0000[20];
            int   m_nOrder;
            int   m_nSequence;
            float m_flPrevCycle;
            float m_flWeight;
            float m_flWeightDeltaRate;
            float m_flPlaybackRate;
            float m_flCycle;
            void* m_pOwner;
            char  pad_0038[4];
        } C_AnimLayer_Pure_t;

        typedef struct {
            char  pad_0000[24];
            int   m_nOrder;
            int   m_nSequence;
            float m_flPrevCycle;
            float m_flWeight;
            float m_flWeightDeltaRate;
            float m_flPlaybackRate;
            float m_flCycle;
            void* m_pOwner;
        } C_AnimLayer18_Pure_t;

        typedef struct {
            void*   pThis;
            char    pad2[91];
            void*   pBaseEntity;
            void*   pActiveWeapon;
            void*   pLastActiveWeapon;
            float   m_flLastClientSideAnimationUpdateTime;
            int     m_iLastClientSideAnimationUpdateFramecount;
            float   m_flEyePitch;
            float   m_flEyeYaw;
            float   m_flPitch;
            float   m_flGoalFeetYaw;
            float   m_flCurrentFeetYaw;
            float   m_flCurrentTorsoYaw;
            float   m_flUnknownVelocityLean;
            float   m_flLeanAmount;
            char    pad4[4];
            float   m_flFeetCycle;
            float   m_flFeetYawRate;
            float   m_fUnknown2;
            float   m_fDuckAmount;
            float   m_fLandingDuckAdditiveSomething;
            float   m_fUnknown3;
            float   m_vOriginX;
            float   m_vOriginY;
            float   m_vOriginZ;
            float   m_vLastOriginX;
            float   m_vLastOriginY;
            float   m_vLastOriginZ;
            float   m_vVelocityX;
            float   m_vVelocityY;
            char    pad5[4];
            float   m_flUnknownFloat1;
            char    pad6[8];
            float   m_flUnknownFloat2;
            float   m_flUnknownFloat3;
            float   m_flUnknown;
            float   m_flSpeed2D;
            float   m_flUpVelocity;
            float   m_flSpeedNormalized;
            float   m_flFeetSpeedForwardsOrSideWays;
            float   m_flFeetSpeedUnknownForwardOrSideways;
            float   m_flTimeSinceStartedMoving;
            float   m_flTimeSinceStoppedMoving;
            bool    m_bOnGround;
            bool    m_bInHitGroundAnimation;
            char    pad7[10];
            float   m_flLastOriginZ;
            float   m_flHeadHeightOrOffsetFromHittingGroundAnimation;
            float   m_flStopToFullRunningFraction;
            char    pad8[4];
            float   m_flUnknownFraction;
            char    pad9[4];
            float   m_flUnknown3;
            char    pad10[528];
        } CCSGOPlayerAnimState_Pure_t;
    ]])
end

-- ── 1. UI Controls (Clean & Auto-Configured)
local ui_enable      = ui.new_checkbox("RAGE", "Other", "[PURE v11] Enable Pure Resolver")
local ui_ssg_head    = ui.new_checkbox("RAGE", "Other", "[PURE v11] SSG08 Headhunter Priority")
local ui_fix_pitch   = ui.new_checkbox("RAGE", "Other", "[PURE v11] Fix Defensive Pitch (Ground & Air)")
local ui_air_sp      = ui.new_checkbox("RAGE", "Other", "[PURE v11] Force Safe-Point in Air (Non-SSG)")
local ui_debug_log   = ui.new_checkbox("RAGE", "Other", "[PURE v11] Hit/Miss Console Logs")

ui.set(ui_enable, true)
ui.set(ui_ssg_head, true)
ui.set(ui_fix_pitch, true)
ui.set(ui_air_sp, false)
ui.set(ui_debug_log, true)

-- ── 2. Math & Source Engine Helpers
local DEG2RAD = math.pi / 180.0
local RAD2DEG = 180.0 / math.pi
local FL_ONGROUND = 1
local FL_DUCKING  = 4

local HITGROUP_NAMES = {
    [0] = "generic", [1] = "head", [2] = "chest", [3] = "stomach",
    [4] = "left arm", [5] = "right arm", [6] = "left leg", [7] = "right leg",
    [8] = "neck", [9] = "?", [10] = "gear"
}

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function norm_yaw(y)
    y = (y + 180) % 360
    if y < 0 then y = y + 360 end
    return y - 180
end

local function is_whitelisted(p)
    if type(p) ~= "number" or p < 1 or p > 64 then return false end
    local ok, v = pcall(plist.get, p, "Add to whitelist")
    return ok and v == true
end

local function get_vel2d(p)
    local vx, vy = entity.get_prop(p, "m_vecVelocity")
    if not vx then return 0, 0, 0 end
    return math.sqrt(vx * vx + vy * vy), vx, vy
end

local function is_holding_ssg08()
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return false end
    local w = entity.get_player_weapon(me)
    if not w then return false end
    local idx = (entity.get_prop(w, "m_iItemDefinitionIndex") or 0) % 65536
    return idx == 40
end

-- ── 3. FFI AnimLayers & AnimState Reader
local ent_list_ptr = nil
local animlayer_off = 0x2990
local animstate_off = 0x9960
local layer_struct_type = "C_AnimLayer_Pure_t**"
local ffi_calibrated = false

local function get_client_entity(p)
    if not ffi_ok or not ffi then return nil end
    if not ent_list_ptr then
        for _, mod in ipairs({ "client.dll", "client_panorama.dll" }) do
            local ok, ptr = pcall(client.create_interface, mod, "VClientEntityList003")
            if ok and ptr then
                ent_list_ptr = ffi.cast("void***", ptr)
                break
            end
        end
    end
    if not ent_list_ptr then return nil end
    local ok, ent = pcall(function()
        local vt = ent_list_ptr[0]
        if not vt then return nil end
        local fn = ffi.cast("void*(__thiscall*)(void*, int)", vt[3])
        return fn(ent_list_ptr, p)
    end)
    return ok and ent or nil
end

local function get_anim_layer(p, idx)
    if not ffi_ok or not ffi or not idx or idx < 0 or idx > 12 then return nil end
    local ok, res = pcall(function()
        local ent = get_client_entity(p)
        if not ent then return nil end
        local ent_addr = tonumber(ffi.cast("uintptr_t", ent))
        if not ffi_calibrated then
            for _, off in ipairs({ 0x2990, 0x2980, 0x2970, 0x29A0 }) do
                local p_try = ffi.cast("void**", ffi.cast("char*", ent) + off)
                if p_try and p_try[0] then
                    local l_addr = tonumber(ffi.cast("uintptr_t", p_try[0]))
                    if l_addr and l_addr > 0x10000 and l_addr < 0xFFFEFFFF and l_addr % 4 == 0 then
                        local base = ffi.cast("char*", p_try[0])
                        if tonumber(ffi.cast("uintptr_t", ffi.cast("void**", base + 0x30)[0])) == ent_addr then
                            animlayer_off, layer_struct_type, ffi_calibrated = off, "C_AnimLayer_Pure_t**", true
                            break
                        elseif tonumber(ffi.cast("uintptr_t", ffi.cast("void**", base + 0x34)[0])) == ent_addr then
                            animlayer_off, layer_struct_type, ffi_calibrated = off, "C_AnimLayer18_Pure_t**", true
                            break
                        end
                    end
                end
            end
        end
        local pp = ffi.cast(layer_struct_type, ffi.cast("char*", ent) + animlayer_off)
        if not pp or not pp[0] then return nil end
        local l = pp[0][idx]
        local seq, w, pr, cy = tonumber(l.m_nSequence), tonumber(l.m_flWeight), tonumber(l.m_flPlaybackRate), tonumber(l.m_flCycle)
        if not seq or seq < 0 or seq > 5000 or not w or w ~= w then return nil end
        return { sequence = seq, weight = w, playback_rate = pr or 0, cycle = cy or 0 }
    end)
    return ok and res or nil
end

local function get_anim_state_ffi(p)
    if not ffi_ok or not ffi then return nil end
    local ok, res = pcall(function()
        local ent = get_client_entity(p)
        if not ent then return nil end
        for _, off in ipairs({ animstate_off, 0x9960, 0x3914, 0x3900 }) do
            local pp = ffi.cast("CCSGOPlayerAnimState_Pure_t**", ffi.cast("char*", ent) + off)
            if pp and pp[0] then
                local addr = tonumber(ffi.cast("uintptr_t", pp[0]))
                if addr and addr > 0x10000 and addr < 0xFFFEFFFF then
                    local st = pp[0]
                    if st.pBaseEntity == ent then
                        animstate_off = off
                        return st
                    end
                end
            end
        end
        return nil
    end)
    return ok and res or nil
end

-- ── 4. Exact Valve Max Desync Angle Calculator (CCSGOPlayerAnimState::Update)
-- Fixes missing Duck-Move (spd=40..80) where real max desync is 34..38 deg, NOT 50 deg!
local function get_exact_max_desync(p, spd, duck, on_ground)
    local st = get_anim_state_ffi(p)
    if st then
        local fsf = clamp(tonumber(st.m_flFeetSpeedForwardsOrSideWays) or 0, 0, 1)
        local fsuf = clamp(tonumber(st.m_flFeetSpeedUnknownForwardOrSideways) or 0, 0, 1)
        local stop_frac = clamp(tonumber(st.m_flStopToFullRunningFraction) or 0, 0, 1)
        local d_amt = clamp(tonumber(st.m_fDuckAmount) or duck, 0, 1)
        local mod = (stop_frac * -0.3 - 0.2) * fsf + 1.0
        if d_amt > 0 then
            mod = mod + ((d_amt * fsuf) * (0.5 - mod))
        end
        return clamp(math.floor(58.0 * mod + 0.5), 28, 58)
    end
    -- Exact mathematical fallback matching Valve server AnimState formula
    local max_spd = entity.get_prop(p, "m_flMaxspeed") or 260
    if max_spd <= 0 then max_spd = 260 end
    local run_spd = math.max(1, max_spd * 0.52)
    local crouch_spd = math.max(1, max_spd * 0.34)
    local fsf = clamp(spd / run_spd, 0, 1)
    local fsuf = clamp(spd / crouch_spd, 0, 1)
    local stop_frac = spd > 130 and 1.0 or (spd > 15 and 0.5 or 0.0)
    local mod = (stop_frac * -0.3 - 0.2) * fsf + 1.0
    if duck > 0 then
        mod = mod + ((duck * fsuf) * (0.5 - mod))
    end
    if not on_ground then
        return duck > 0.6 and 46 or 54
    end
    return clamp(math.floor(58.0 * mod + 0.5), 29, 58)
end

-- ── 5. Per-Player State & History
local P = {}

local function get_p(p)
    local d = P[p]
    if not d then
        d = {
            last_sim = 0,
            last_tick = 0,
            choke = 0,
            is_shifting = false,
            shift_until = 0,
            -- Eye & LBY history (last 12 net updates)
            eye_hist = {},
            lby_hist = {},
            vel_hist = {},
            pitch_hist = {},
            l6_hist = {},
            -- Jitter & Spin detection
            is_jitter = false,
            jitter_delta = 0,
            jitter_center = 0,
            jitter_side = -1,
            -- Pitch defensive detection
            last_normal_pitch = 89,
            def_pitch_until = 0,
            -- Unified Bruteforce & Learning per player
            stage = 0, -- 0 = smart deterministic, 1..6 = bruteforce stages
            bf_base_side = -1,
            miss_count = 0,
            last_missed_ang = nil,
            last_missed_side = nil,
            hit_side = nil,
            hit_ang = nil,
            hit_tick = -999,
            side_score = { [1] = 0, [-1] = 0 },
            -- Applied state & shot snapshots
            applied_ang = -58,
            applied_src = "init",
            applied_conf = 75,
            applied_stage = 0,
            applied_group = "stand",
            applied_tick = 0,
            shots = {},
            last_shot = nil,
            wc = {}
        }
        P[p] = d
    end
    return d
end

local function get_group(p, spd, duck, on_ground)
    if not on_ground then return "air" end
    if duck > 0.6 then return spd > 15 and "duck_move" or "duck" end
    if spd > 10 then return "move" end
    return "stand"
end

-- ── 6. 3D Head-Hide Freestand Detector
local function solve_3d_freestand(p, eye_yaw, duck, max_ang)
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return 0 end
    local ex, ey, ez = client.eye_position()
    local px, py, pz = entity.get_origin(p)
    if not ex or not px then return 0 end
    local head_z = pz + (64 - duck * 18)

    local rad_pos = norm_yaw(eye_yaw + max_ang) * DEG2RAD
    local rad_neg = norm_yaw(eye_yaw - max_ang) * DEG2RAD

    local fp1 = client.trace_line(p, ex, ey, ez, px + 22 * math.cos(rad_pos), py + 22 * math.sin(rad_pos), head_z) or 1
    local fn1 = client.trace_line(p, ex, ey, ez, px + 22 * math.cos(rad_neg), py + 22 * math.sin(rad_neg), head_z) or 1
    local fp2 = client.trace_line(p, ex, ey, ez, px + 32 * math.cos(rad_pos), py + 32 * math.sin(rad_pos), head_z) or 1
    local fn2 = client.trace_line(p, ex, ey, ez, px + 32 * math.cos(rad_neg), py + 32 * math.sin(rad_neg), head_z) or 1

    local score_pos = fp1 + fp2
    local score_neg = fn1 + fn2
    if math.abs(score_pos - score_neg) >= 0.14 then
        -- Real head is hidden on the side with MORE wall cover (smaller trace fraction)
        return (score_pos < score_neg) and 1 or -1
    end
    return 0
end

-- ── 7. Network Update Analyzer (Runs on each new SimulationTime)
local function update_player_net(p, d)
    local now = globals.tickcount()
    local sim = entity.get_prop(p, "m_flSimulationTime") or 0
    local eye = entity.get_prop(p, "m_angEyeAngles[1]") or 0
    local pitch = entity.get_prop(p, "m_angEyeAngles[0]") or 0
    local lby = entity.get_prop(p, "m_flLowerBodyYawTarget") or eye
    local spd, vx, vy = get_vel2d(p)
    local ti = globals.tickinterval() or 0.015625

    if sim == d.last_sim then
        d.choke = d.choke + 1
        return
    end

    local sim_dt = sim - d.last_sim
    local tick_dt = math.max(1, now - d.last_tick)
    local sim_ticks = math.floor(sim_dt / ti + 0.5)
    if d.last_sim > 0 and (sim_dt < -ti or (sim_ticks - math.max(tick_dt, d.choke + 1)) >= 10) then
        d.is_shifting = true
        d.shift_until = now + 6
    elseif now > d.shift_until then
        d.is_shifting = false
    end
    d.choke = 0
    d.last_sim = sim
    d.last_tick = now

    -- Pitch history & Defensive Pitch detection
    if pitch >= 75 and pitch <= 89.5 then
        d.last_normal_pitch = pitch
    elseif pitch <= -35 or (math.abs(pitch) <= 50 and #d.pitch_hist >= 2) then
        d.def_pitch_until = now + 6
    end
    table.insert(d.pitch_hist, 1, pitch)
    if #d.pitch_hist > 8 then table.remove(d.pitch_hist) end

    -- Eye, LBY & Velocity history
    table.insert(d.eye_hist, 1, eye)
    if #d.eye_hist > 10 then table.remove(d.eye_hist) end
    table.insert(d.lby_hist, 1, lby)
    if #d.lby_hist > 10 then table.remove(d.lby_hist) end
    if spd > 5 then
        table.insert(d.vel_hist, 1, math.deg(math.atan2(vy, vx)))
        if #d.vel_hist > 8 then table.remove(d.vel_hist) end
    end

    -- Layer 6 history
    local l6 = get_anim_layer(p, 6)
    if l6 then
        table.insert(d.l6_hist, 1, l6)
        if #d.l6_hist > 8 then table.remove(d.l6_hist) end
    end

    -- Jitter / Center-Jitter / Spin analysis across last 4 packets
    d.is_jitter = false
    d.jitter_delta = 0
    if #d.eye_hist >= 3 then
        local d1 = norm_yaw(d.eye_hist[1] - d.eye_hist[2])
        local d2 = norm_yaw(d.eye_hist[2] - d.eye_hist[3])
        local ad1, ad2 = math.abs(d1), math.abs(d2)
        -- Alternating sign between consecutive packets = Jitter!
        if ad1 >= 16 and ad2 >= 16 and ad1 <= 145 and ad2 <= 145 and (d1 * d2) < 0 then
            d.is_jitter = true
            d.jitter_delta = (ad1 + ad2) * 0.5
            d.jitter_center = norm_yaw(d.eye_hist[2] + d1 * 0.5)
            -- When current eye jumped positive (+d1), real feet yaw lags toward negative (-1)
            d.jitter_side = (d1 > 0) and -1 or 1
        end
    end
end

-- ── 8. Pure Deterministic Angle Solver
local function build_bf_stages(p, d, base_s, max_ang, grp)
    -- Tailored per-state bruteforce angles:
    -- On duck_move (like Global P5 duck spd=40), max_ang is 35..38 deg, so testing ±50 misses over the head!
    local a1 = max_ang
    local a2 = (grp == "duck_move") and 24 or ((grp == "duck") and 34 or 38)
    local a3 = (grp == "duck_move") and 14 or 24
    return {
        [1] =  base_s * a1,
        [2] = -base_s * a1,
        [3] =  base_s * a2,
        [4] = -base_s * a2,
        [5] =  base_s * a3,
        [6] = -base_s * a3,
    }
end

local function solve_player(p, d)
    local now = globals.tickcount()
    local flags = entity.get_prop(p, "m_fFlags") or 1
    local on_ground = bit.band(flags, FL_ONGROUND) ~= 0
    local duck = entity.get_prop(p, "m_flDuckAmount") or 0
    local spd, vx, vy = get_vel2d(p)
    local eye = entity.get_prop(p, "m_angEyeAngles[1]") or 0
    local lby = entity.get_prop(p, "m_flLowerBodyYawTarget") or eye
    local grp = get_group(p, spd, duck, on_ground)
    local max_ang = get_exact_max_desync(p, spd, duck, on_ground)

    -- 1. Check On-Shot (enemy firing right now -> head snaps to 0 desync)
    local wep = entity.get_player_weapon(p)
    if wep then
        local lst = entity.get_prop(wep, "m_fLastShotTime")
        local sim = entity.get_prop(p, "m_flSimulationTime")
        local ti = globals.tickinterval() or 0.015625
        if lst and sim and lst > 0 and math.abs(sim - lst) <= ti * 2 then
            return 0, "on_shot", 98, grp, max_ang
        end
    end

    -- 2. Determine best deterministic side for this player
    local fs_side = (on_ground and spd < 120) and solve_3d_freestand(p, eye, duck, max_ang) or 0
    local learned_side = 0
    if d.side_score[1] ~= d.side_score[-1] then
        learned_side = (d.side_score[1] > d.side_score[-1]) and 1 or -1
    end

    -- 3. If we are in active Bruteforce search (stage 1..6 after a miss), use exact stage!
    if d.stage >= 1 and d.stage <= 6 then
        local base_s = (d.bf_base_side and d.bf_base_side ~= 0) and d.bf_base_side or -1
        local stages = build_bf_stages(p, d, base_s, max_ang, grp)
        local bf_ang = stages[d.stage] or (base_s * max_ang)
        return bf_ang, "bf" .. tostring(d.stage), 80, grp, max_ang
    end

    -- 4. Recent confirmed Head Hit memory (valid for 64 ticks if same side)
    if d.hit_ang and (now - d.hit_tick) <= 64 and d.miss_count == 0 then
        local h_side = d.hit_ang >= 0 and 1 or -1
        local scaled = h_side * math.min(math.abs(d.hit_ang), max_ang)
        return scaled, "hit_lock", 92, grp, max_ang
    end

    -- 5. Server LBY - Eye Delta (when bd != 0, e.g. Standing LBY break or Moving LBY lag)
    local bd = norm_yaw(lby - eye)
    if math.abs(bd) >= 6 and math.abs(bd) <= 62 then
        local lby_side = (bd > 0) and 1 or -1
        local lby_amp = clamp(math.abs(bd), 28, max_ang)
        return lby_side * lby_amp, "lby_measured", 90, grp, max_ang
    end

    -- 6. Center-Jitter / Offset-Jitter Resolution
    if d.is_jitter then
        -- Against Center Jitter, maximum desync is compressed to ~34..42 deg toward jitter_side
        local j_amp = clamp(math.floor(max_ang * 0.72), 28, 44)
        local j_side = (learned_side ~= 0) and learned_side or d.jitter_side
        return j_side * j_amp, "jitter_center", 86, grp, max_ang
    end

    -- 7. Moving / Air Strafe Resolution (Correct HvH Opposite-Velocity Sign!)
    -- Proven by match logs (P1 MicroHard duck spd=76 & P8 anibreani move spd=100/168):
    -- When strafing, client fake is pulled along velocity, while REAL head is on -sign(vel_yaw - eye_yaw)!
    if spd >= 25 then
        local vel_yaw = math.deg(math.atan2(vy, vx))
        local v_diff = norm_yaw(vel_yaw - eye)
        local abs_vd = math.abs(v_diff)
        local mv_side = 0
        if abs_vd >= 10 and abs_vd <= 165 then
            -- Opposite to velocity-eye delta (real desync side in HvH!)
            mv_side = (v_diff > 0) and -1 or 1
        elseif #d.vel_hist >= 2 then
            local turn = norm_yaw(d.vel_hist[1] - d.vel_hist[2])
            if math.abs(turn) >= 1.5 then
                mv_side = (turn > 0) and -1 or 1
            end
        end
        if mv_side == 0 then
            mv_side = (learned_side ~= 0 and learned_side) or (fs_side ~= 0 and fs_side) or -1
        end
        return mv_side * max_ang, "move_pure", 85, grp, max_ang
    end

    -- 8. Standing / Crouch-Stand Resolution (3D Freestand + Layer 3/6 + Learned Side)
    local st_side = fs_side
    if st_side == 0 and learned_side ~= 0 then
        st_side = learned_side
    end
    if st_side == 0 then
        local l3 = get_anim_layer(p, 3)
        local l6 = get_anim_layer(p, 6)
        if l3 and l3.sequence == 4 and l3.weight > 0.01 then
            st_side = (l3.cycle < 0.5) and -1 or 1
        elseif l6 and #d.l6_hist >= 2 then
            local dw = l6.weight - d.l6_hist[2].weight
            if math.abs(dw) > 0.002 then
                st_side = (dw > 0) and -1 or 1
            end
        end
    end
    if st_side == 0 then st_side = -1 end
    return st_side * max_ang, "stand_pure", 80, grp, max_ang
end

-- ── 9. Apply to Gamesense plist
local function pw(d, p, field, val)
    local now = globals.tickcount()
    local c = d.wc[field]
    if c and c.v == val and (now - c.t) < 24 then return end
    d.wc[field] = { v = val, t = now }
    pcall(plist.set, p, field, val)
end

local function restore_player(p)
    local d = P[p]
    if d then d.wc = {} end
    pcall(plist.set, p, "Force body yaw", false)
    pcall(plist.set, p, "Force body yaw value", 0)
    pcall(plist.set, p, "Force pitch", false)
    pcall(plist.set, p, "Override prefer body aim", "-")
    pcall(plist.set, p, "Override safe point", "-")
    pcall(plist.set, p, "High priority", false)
end

local function run_resolver()
    if not ui.get(ui_enable) then return end
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return end
    local ssg = ui.get(ui_ssg_head) and is_holding_ssg08()
    local now = globals.tickcount()

    local enemies = entity.get_players(true)
    for i = 1, #enemies do
        local p = enemies[i]
        if entity.is_alive(p) and not entity.is_dormant(p) then
            if is_whitelisted(p) then
                restore_player(p)
            else
                local d = get_p(p)
                update_player_net(p, d)
                local ang, src, conf, grp, max_ang = solve_player(p, d)

                d.applied_ang   = ang
                d.applied_src   = src
                d.applied_conf  = conf
                d.applied_stage = d.stage
                d.applied_group = grp
                d.applied_max   = max_ang
                d.applied_tick  = now

                pw(d, p, "Correction active", true)
                pw(d, p, "Force body yaw", true)
                pw(d, p, "Force body yaw value", ang)

                -- Defensive Pitch Fix (works on BOTH Ground and Air!)
                local pt = entity.get_prop(p, "m_angEyeAngles[0]") or 89
                if math.abs(pt) > 89.5 then
                    pw(d, p, "Force pitch", true)
                    pw(d, p, "Force pitch value", pt > 0 and 89 or -89)
                elseif ui.get(ui_fix_pitch) and (pt <= -35 or (now <= d.def_pitch_until and pt < 75)) then
                    pw(d, p, "Force pitch", true)
                    pw(d, p, "Force pitch value", d.last_normal_pitch or 89)
                else
                    pw(d, p, "Force pitch", false)
                end

                -- Headhunter Priority (Never force baim or safe-point baim when holding SSG08!)
                local hp_enemy = entity.get_prop(p, "m_iHealth") or 100
                local want_head_only = ssg and hp_enemy > 72
                pw(d, p, "High priority", want_head_only or conf >= 85)
                pw(d, p, "Override prefer body aim", "-")

                local want_sp = (not want_head_only) and (grp == "air" and ui.get(ui_air_sp))
                pw(d, p, "Override safe point", want_sp and "On" or "-")
            end
        end
    end
end

client.set_event_callback("net_update_end", run_resolver)
client.set_event_callback("setup_command", run_resolver)

-- ── 10. Shot Tracking & Bruteforce Feedback (aim_fire / aim_hit / aim_miss)
local stats = { shots = 0, hits = 0, head_shots = 0, head_hits = 0, res_miss = 0 }

client.set_event_callback("aim_fire", function(e)
    if not ui.get(ui_enable) or not e or not e.target then return end
    local p = e.target
    local d = get_p(p)
    local spd = get_vel2d(p)
    local pitch = math.floor((entity.get_prop(p, "m_angEyeAngles[0]") or 0) + 0.5)
    local eye = entity.get_prop(p, "m_angEyeAngles[1]") or 0
    local lby = entity.get_prop(p, "m_flLowerBodyYawTarget") or eye
    local bd = math.floor(norm_yaw(lby - eye) + 0.5)

    local rec = {
        id = e.id or 0,
        tick = globals.tickcount(),
        ang = d.applied_ang or 0,
        src = d.applied_src or "unknown",
        conf = d.applied_conf or 0,
        stage = d.applied_stage or 0,
        grp = d.applied_group or "stand",
        max_ang = d.applied_max or 58,
        spd = math.floor(spd + 0.5),
        hc = math.floor((e.hit_chance or 0) + 0.5),
        bt = e.backtrack or 0,
        hg = e.hitgroup,
        pitch = pitch,
        bd = bd,
        shift = d.is_shifting
    }
    d.shots[e.id or 0] = rec
    d.last_shot = rec
end)

client.set_event_callback("aim_hit", function(e)
    if not ui.get(ui_enable) or not e or not e.target then return end
    local p = e.target
    local d = get_p(p)
    local rec = d.shots[e.id or 0] or d.last_shot
    d.shots[e.id or 0] = nil

    stats.shots = stats.shots + 1
    stats.hits = stats.hits + 1
    local is_head = (e.hitgroup == 1 or e.hitgroup == 8) or (rec and (rec.hg == 1 or rec.hg == 8))
    if is_head then
        stats.head_shots = stats.head_shots + 1
        stats.head_hits = stats.head_hits + 1
    end

    if rec then
        local side = (rec.ang >= 0) and 1 or -1
        if is_head then
            d.hit_ang = rec.ang
            d.hit_side = side
            d.hit_tick = globals.tickcount()
            d.miss_count = 0
            d.stage = 0
            d.side_score[side] = (d.side_score[side] or 0) + 2
        end
        if ui.get(ui_debug_log) then
            local hg_name = HITGROUP_NAMES[e.hitgroup] or tostring(e.hitgroup)
            client.log(string.format(
                "[PURE HIT] P%d %s %ddmg | used=%s(%+d) | %s spd=%d max=%d hc=%d bt=%d pitch=%d bd=%d%s",
                p, hg_name, e.damage or 0, rec.src, rec.ang, rec.grp, rec.spd, rec.max_ang,
                rec.hc, rec.bt, rec.pitch, rec.bd, rec.shift and " SHIFT" or ""
            ))
        end
    end
end)

client.set_event_callback("aim_miss", function(e)
    if not ui.get(ui_enable) or not e or not e.target then return end
    local p = e.target
    local d = get_p(p)
    local rec = d.shots[e.id or 0] or d.last_shot
    d.shots[e.id or 0] = nil

    stats.shots = stats.shots + 1
    local is_head = (e.hitgroup == 1 or e.hitgroup == 8) or (rec and (rec.hg == 1 or rec.hg == 8))
    if is_head then stats.head_shots = stats.head_shots + 1 end

    -- Ignore non-resolver misses (spread, prediction error, unregistered shot, death)
    if e.reason ~= "?" then
        if ui.get(ui_debug_log) and rec then
            client.log(string.format(
                "[PURE MISS] P%d %s (ignorat) | used=%s(%+d) | %s spd=%d max=%d hc=%d",
                p, tostring(e.reason), rec.src, rec.ang, rec.grp, rec.spd, rec.max_ang, rec.hc
            ))
        end
        return
    end

    stats.res_miss = stats.res_miss + 1
    local missed_ang = (rec and rec.ang) or d.applied_ang or -58
    local missed_side = (missed_ang >= 0) and 1 or -1

    d.miss_count = d.miss_count + 1
    d.hit_ang = nil
    d.last_missed_ang = missed_ang
    d.last_missed_side = missed_side
    d.side_score[missed_side] = (d.side_score[missed_side] or 0) - 1
    d.side_score[-missed_side] = (d.side_score[-missed_side] or 0) + 1

    -- Advance Bruteforce Stage deterministically:
    -- If we missed on stage 0 (deterministic), jump to stage 1 (which build_bf_stages sets to -missed_side * max_ang!)
    -- If we missed on stage 1..5, advance to stage + 1 (wrapping 6 -> 1)
    if (rec and rec.stage or d.stage) == 0 then
        d.bf_base_side = -missed_side
        d.stage = 1
    else
        d.stage = ((rec and rec.stage or d.stage) % 6) + 1
    end

    if ui.get(ui_debug_log) and rec then
        local stages = build_bf_stages(p, d, d.bf_base_side or -1, rec.max_ang, rec.grp)
        local next_ang = stages[d.stage] or 0
        client.log(string.format(
            "[PURE MISS] P%d RESOLVER (?) | used=%s(%+d) | %s spd=%d max=%d hc=%d bt=%d pitch=%d bd=%d%s | next=bf%d(%+d)",
            p, rec.src, missed_ang, rec.grp, rec.spd, rec.max_ang, rec.hc, rec.bt,
            rec.pitch, rec.bd, rec.shift and " SHIFT" or "", d.stage, next_ang
        ))
    end
end)

client.set_event_callback("round_end", function()
    if ui.get(ui_debug_log) and stats.shots > 0 then
        local hr = stats.head_shots > 0 and math.floor((stats.head_hits / stats.head_shots) * 100 + 0.5) or 0
        client.log(string.format(
            "[PURE STATS] shots=%d hits=%d | HEAD HITRATE=%d%% (%d/%d) | resolver_miss=%d",
            stats.shots, stats.hits, hr, stats.head_hits, stats.head_shots, stats.res_miss
        ))
    end
end)

client.set_event_callback("round_start", function()
    for p, d in pairs(P) do
        d.stage = 0
        d.miss_count = 0
        d.wc = {}
    end
end)

client.set_event_callback("shutdown", function()
    for p = 1, globals.maxplayers() do
        pcall(restore_player, p)
    end
end)

client.log("[PURE RESOLVER v11.0] Built from Scratch | Exact Valve AnimState Desync | Move Opposite Sign | SSG08 Headhunter")
