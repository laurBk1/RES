-- ══════════════════════════════════════════════════════════════════════════════
--  ADAPTIVE RESOLVER v10.0 | CS:GO Legacy 2023 | gamesense.pub | PURE DETERMINISTIC EDITION
--  v10.0 (Arhitectura Pura & Determinista din logurile cu anydesk P7 stand & anibreani P8 air):
--  1. REPARAT geometric player_freestand: testeaza direct pozitiile 3D ale capului la eye_yaw + 58°
--     si eye_yaw - 58° din perspectiva ta (trace_line & trace_bullet) si alege partea unde
--     inamicul isi ascunde capul real dupa perete/obstacol (inainte era inversat!).
--  2. ADAUGAT Air-Strafe Velocity Turn Resolver pentru bhop/air cu Backward AA (|vel_yaw - eye| > 155°):
--     cand inamicul sare direct spre tine (ca P8 air spd=286), calculeaza directia de strafe din
--     derivata unghiului de viteza (vel_yaw_now - vel_yaw_prev) si rezolva partea reala in aer!
--  3. REPARAT Stand Layer 3 (seq 4 balance adjust) + Layer 6 + Anti-Bias: eliminat bias-ul orb
--     pe +58° (side = 1) cand inamicul sta pe loc cu bd=0!
--  4. SSG08 Headhunter Mode + Bruteforce Unificat 58°/38°/29° fara poluare.
-- ══════════════════════════════════════════════════════════════════════════════
local bit = require("bit")
local ffi = require("ffi")

-- 1 ── error wrapper
do
    local orig = __RES_ORIG_SEC or client.set_event_callback
    local seen, count = {}, 0
    __RES_ORIG_SEC = orig
    pcall(function()
        client.set_event_callback = function(ev, fn)
            if type(fn) ~= "function" then return orig(ev, fn) end
            return orig(ev, function(...)
                local args = { n = select("#", ...), ... }
                local ok, r = xpcall(function()
                    return fn(unpack(args, 1, args.n))
                end, function(e)
                    return (debug and debug.traceback) and debug.traceback(tostring(e), 2) or tostring(e)
                end)
                if not ok then
                    local key = tostring(ev) .. "|" .. string.sub(tostring(r), 1, 120)
                    if not seen[key] and count < 8 then
                        seen[key] = true; count = count + 1
                        client.log("[ERR-TRACE] " .. tostring(ev) .. " :: " .. string.sub(tostring(r), 1, 900))
                    end
                    return
                end
                return r
            end)
        end
    end)
end

-- 2 ── structuri FFI
ffi.cdef[[
    typedef struct {
        char pad_0000[0x14]; uint32_t m_nOrder; uint32_t m_nSequence;
        float m_flPrevCycle; float m_flWeight; float m_flWeightDeltaRate;
        float m_flPlaybackRate; float m_flCycle; void* m_pOwner; char pad_0034[4];
    } C_AnimLayer_t;
    typedef struct {
        int32_t m_nOrder; int32_t m_nSequence; float m_flPrevCycle; float m_flWeight;
        float m_flWeightDeltaRate; float m_flPlaybackRate; char _pad18[4];
        void* m_pOwner; float m_flCycle; char _pad20[0x14];
    } C_AnimLayer1C_t;
    typedef struct {
        int32_t m_nOrder; int32_t m_nSequence; float m_flPrevCycle; float m_flWeight;
        float m_flWeightDeltaRate; float m_flPlaybackRate; void* m_pOwner; float m_flCycle;
        char _pad18[0x14];
    } C_AnimLayer18_t;
]]

-- 3 ── plist adapter
local BRUTE = {}
BRUTE.real_fields = { ["Correction active"]=true, ["Force body yaw"]=true, ["Force body yaw value"]=true,
    ["Override safe point"]=true, ["Override prefer body aim"]=true, ["Force pitch"]=true,
    ["Force pitch value"]=true, ["High priority"]=true, ["Add to whitelist"]=true }
BRUTE.warned = {}
local plist = (function(gs)
    return {
        set = function(player, field, value)
            if type(player) ~= "number" or player < 1 or player > 64 then return false end
            if not BRUTE.real_fields[field] then
                if not BRUTE.warned[field] then BRUTE.warned[field] = true
                    client.log("[PLIST] camp necunoscut: " .. tostring(field)) end
                return false
            end
            local ok, err = pcall(gs.set, player, field, value)
            if not ok and not BRUTE.warned["!" .. field] then
                BRUTE.warned["!" .. field] = true
                client.log("[PLIST-ERR] " .. tostring(field) .. " -> " .. tostring(err))
            end
            return ok
        end,
        get = function(player, field)
            if type(player) ~= "number" or player < 1 or player > 64 then return nil end
            local ok, v = pcall(gs.get, player, field)
            return ok and v or nil
        end,
    }
end)(plist)

local function is_whitelisted(p)
    if type(p) ~= "number" or p < 1 or p > 64 then return false end
    return plist.get(p, "Add to whitelist") == true
end

-- 4 ── FFI anim layers
local ANIMLAYER_OFFSET = 0x2990
local ANIMLAYER_CANDIDATES = { 0x2990, 0x2980, 0x2970, 0x29A0 }
local LAYER_STRUCT = "C_AnimLayer_t"
local _ffi_calibrated = false
local function cur_struct()
    if _ffi_calibrated and BRUTE._auto_struct then return BRUTE._auto_struct end
    if not BRUTE.ffistruct_ui then return LAYER_STRUCT end
    local v = ui.get(BRUTE.ffistruct_ui)
    if v == "C_AnimLayer1C_t (owner@0x1C)" then return "C_AnimLayer1C_t" end
    if v == "C_AnimLayer18_t (owner@0x18)" then return "C_AnimLayer18_t" end
    return LAYER_STRUCT
end
local entity_list_ptr, entity_list_tick = nil, 0
local function get_entity_list_safe()
    if entity_list_ptr then return entity_list_ptr end
    local now = globals.tickcount()
    if now - entity_list_tick < 64 then return nil end
    entity_list_tick = now
    local ptr
    for _, mod in ipairs({"client.dll", "client_panorama.dll"}) do
        local ok, pp = pcall(client.create_interface, mod, "VClientEntityList003")
        if ok and pp then ptr = pp break end
    end
    if ptr then entity_list_ptr = ffi.cast("void*", ptr) end
    return entity_list_ptr
end
local function get_client_entity_safe(player)
    local el = get_entity_list_safe()
    if not el then return nil end
    local ok, res = pcall(function()
        local vt = ffi.cast("void***", el)
        if not vt then return nil end
        local vtable = vt[0]
        if not vtable then return nil end
        local fn = ffi.cast("void*(__thiscall*)(void*, int)", vtable[3])
        if not fn then return nil end
        local ent = fn(el, player)
        if ent == nil then return nil end
        return ent
    end)
    return ok and res or nil
end
local function get_anim_layers_ptr_safe(player)
    local ok, res = pcall(function()
        local ent = get_client_entity_safe(player)
        if ent == nil then return nil end
        if not _ffi_calibrated then
            local enta = tonumber(ffi.cast("uintptr_t", ent))
            for _, off in ipairs(ANIMLAYER_CANDIDATES) do
                local pp_try = ffi.cast("void**", ffi.cast("char*", ent) + off)
                if pp_try ~= nil and pp_try[0] ~= nil then
                    local lptr = pp_try[0]
                    local addr = tonumber(ffi.cast("uintptr_t", lptr))
                    if addr and addr >= 0x10000 and addr <= 0xFFFEFFFF and addr % 4 == 0 then
                        local base = ffi.cast("char*", lptr)
                        if tonumber(ffi.cast("uintptr_t", ffi.cast("void**", base + 0x30)[0])) == enta then
                            ANIMLAYER_OFFSET, BRUTE._auto_struct, _ffi_calibrated = off, "C_AnimLayer_t", true; break
                        elseif tonumber(ffi.cast("uintptr_t", ffi.cast("void**", base + 0x1C)[0])) == enta then
                            ANIMLAYER_OFFSET, BRUTE._auto_struct, _ffi_calibrated = off, "C_AnimLayer1C_t", true; break
                        elseif tonumber(ffi.cast("uintptr_t", ffi.cast("void**", base + 0x18)[0])) == enta then
                            ANIMLAYER_OFFSET, BRUTE._auto_struct, _ffi_calibrated = off, "C_AnimLayer18_t", true; break
                        end
                    end
                end
            end
        end
        local pp = ffi.cast(cur_struct() .. "**", ffi.cast("char*", ent) + ANIMLAYER_OFFSET)
        if pp == nil then return nil end
        local layers = pp[0]
        if layers == nil then return nil end
        local addr = tonumber(ffi.cast("uintptr_t", layers))
        if not addr or addr < 0x10000 or addr > 0xFFFEFFFF or addr % 4 ~= 0 then return nil end
        return layers
    end)
    return ok and res or nil
end
local _ovl_stat = { ok = 0, bad = 0, logged = false }
local function get_anim_overlay_ffi(player, index)
    if not index or index < 0 or index > 12 then return {sequence=0, cycle=0, playback_rate=1, weight=0, valid=false} end
    local ok, res = pcall(function()
        local layers = get_anim_layers_ptr_safe(player)
        if layers == nil then return nil end
        local l = layers[index]
        local seq, pr, w, cy = tonumber(l.m_nSequence), l.m_flPlaybackRate, l.m_flWeight, l.m_flCycle
        if not seq or seq < 0 or seq > 5000 then return nil end
        if pr ~= pr or math.abs(pr) > 100 then return nil end
        if w ~= w or w < -0.01 or w > 1.01 then return nil end
        if cy ~= cy or cy < -0.01 or cy > 1.5 then return nil end
        return { sequence=seq, cycle=cy, playback_rate=pr, weight=w, valid=true }
    end)
    if ok and res then _ovl_stat.ok = _ovl_stat.ok + 1 else _ovl_stat.bad = _ovl_stat.bad + 1 end
    if not _ovl_stat.logged and (_ovl_stat.ok + _ovl_stat.bad) >= 300 then
        _ovl_stat.logged = true
        client.log(string.format("[FFI] anim layers: %d ok / %d invalide (%s) struct=%s",
            _ovl_stat.ok, _ovl_stat.bad, _ovl_stat.ok > _ovl_stat.bad and "OK" or "NU MERGE", cur_struct()))
    end
    if ok and res then return res end
    return {sequence=0, cycle=0, playback_rate=1, weight=0, valid=false}
end
local function dump_anim_layers()
    local players = entity.get_players(true)
    if #players == 0 then return end
    local p = players[1]
    local ent = get_client_entity_safe(p)
    local layers = get_anim_layers_ptr_safe(p)
    if not ent or not layers then
        client.log("[FFI-DUMP] FAIL ent=" .. tostring(ent ~= nil) .. " layers=" .. tostring(layers ~= nil)); return end
    local enta = tonumber(ffi.cast("uintptr_t", ent))
    local base = ffi.cast("char*", layers)
    local found = {}
    for off = 0, 0x50, 4 do
        local v = tonumber(ffi.cast("uintptr_t", ffi.cast("void**", base + off)[0]))
        if v == enta then found[#found + 1] = string.format("0x%X", off) end
    end
    client.log(string.format("[FFI-DUMP] struct=%s ent=%s | m_pOwner: %s | %s", cur_struct(),
        tostring(enta), (#found > 0 and table.concat(found, ",") or "NIMIC"),
        (#found > 0 and "OK" or "schimba 'FFI struct'")))
end
local function test_ffi()
    if #entity.get_players(true) == 0 then return end
    pcall(dump_anim_layers)
end
local frame_counter, session_id = 0, 0
local cached_pr, cached_pr_tick = nil, 0

-- 5 ── UI
local enable_resolver = ui.new_checkbox("RAGE", "Other", "[ADAPTIVE RESOLVER] Enable")
local crouch_fix      = ui.new_checkbox("RAGE", "Other", "[FIX] Crouch + SafeHead -> auto body")
local head_priority   = ui.new_checkbox("RAGE", "Other", "[AIM] Max head damage")
local threat_priority = ui.new_checkbox("RAGE", "Other", "[CPU] Dynamic threat priority")
local smart_cache     = ui.new_checkbox("RAGE", "Other", "[CPU] Smart caching")
local zeus_resolver   = ui.new_checkbox("RAGE", "Other", "[MISC] Skip melee (zeus/knife)")
local debug_log       = ui.new_checkbox("RAGE", "Other", "[LOG] Hit/Miss console")
ui.set(enable_resolver, true); ui.set(crouch_fix, true); ui.set(head_priority, true)
ui.set(threat_priority, true); ui.set(smart_cache, true); ui.set(zeus_resolver, true); ui.set(debug_log, true)

-- 5b ── referinte native Ragebot (Double Tap / Hide Shots / Safe Point / Baim)
local REF = {}
do
    local function find_ref(tab, container, name)
        local ok, r1, r2, r3 = pcall(ui.reference, tab, container, name)
        if ok and r1 ~= nil then return { r1, r2, r3 } end
        return nil
    end
    REF.dt = find_ref("RAGE", "Aimbot", "Double tap") or find_ref("RAGE", "Other", "Double tap")
    REF.hs = find_ref("AA", "Other", "On shot anti-aim") or find_ref("RAGE", "Other", "On shot anti-aim")
    REF.fsp = find_ref("RAGE", "Aimbot", "Force safe point")
    REF.fbaim = find_ref("RAGE", "Other", "Force body aim") or find_ref("RAGE", "Aimbot", "Force body aim")
end
local function is_ref_active(ref_tbl)
    if not ref_tbl or not ref_tbl[1] then return false end
    local ok1, v1 = pcall(ui.get, ref_tbl[1])
    if not ok1 or not v1 then return false end
    if ref_tbl[2] then
        local ok2, v2 = pcall(ui.get, ref_tbl[2])
        if ok2 and type(v2) == "boolean" then return v2 end
    end
    return v1 == true
end
local function is_local_dt_active() return is_ref_active(REF.dt) end
local function is_local_hs_active() return is_ref_active(REF.hs) end

-- 6 ── constante
local C = {
    DEG2RAD = math.pi/180, RAD2DEG = 180/math.pi, EPSILON = 0.001, DECAY_RATE = 0.92,
    CONF_LOW = 25, CONF_MED = 55, TICK_INTERVAL = 0.015625,
    SAFE_HEAD_CONF_THRESHOLD = 38, SAFE_HEAD_SCAN_DIST = 28,
    SAFE_HEAD_SCAN_ANGLES = {0,45,90,135,-180,-135,-90,-45},
    SAFE_HEAD_VISIBLE_THRESHOLD = 0.9, BODY_VISIBLE_THRESHOLD = 0.97, HEAD_VISIBLE_THRESHOLD = 0.97,
    HEAD_TRACE_OFFSETS = {{0,0,0},{0,0,6},{4,0,0}},
    RESOLVER_LOCK_TICKS = 2, ROUND_RESET_DECAY_HIT = 0.7, ROUND_RESET_DECAY_MISS = 0.7,
    ROUND_RESET_SYS_DECAY = 0.6, ROUND_RESET_SYS_RATE_BLEND = 0.2,
    ROUND_RESET_BF_LOG_DECAY = 0.4, ROUND_RESET_BF_CONF_RESET = 35,
    HEAD_OFFSET_STAND = 70, HEAD_OFFSET_CROUCH = 46, HEAD_OFFSET_DUCK_LERP = 24,
    CACHE_MAX_AGE = 3, THREAT_CACHE_AGE = 6, MOVING_CACHE_MAX_AGE = 32,
    MISS_STREAK_FLIP = 4, SIMTIME_HISTORY_MAX = 24, ANIM_RECORD_MAX = 32, LAYER_HISTORY_MAX = 8,
    YAW_ACCEL_MAX = 6, FLIP_INTERVAL_MAX = 8, ANGLE_BUCKETS = {18,28,38,48,58},
    HITBOX_HEAD = 0, HITBOX_PELVIS = 2, HITBOX_STOMACH = 3, HITBOX_CHEST = 4,
    BODY_HITBOXS = {2,3,4,5},
    DT_SHIFT_MIN = 12, DT_SHIFT_MAX = 22, DT_CONFIDENCE_HIT = 45, DT_CONFIDENCE_MISS = 20, DT_CONFIDENCE_THRESHOLD = 50,
    HS_SHIFT_MIN = 7, HS_SHIFT_MAX = 11, HS_CONFIDENCE_HIT = 30, HS_CONFIDENCE_MISS = 15, HS_CONFIDENCE_THRESHOLD = 60,
    CHOKE_MIN = 2, DT_CHOKE_MIN = 6, LAGCOMP_BOOST_CAP = 20,
    LAGCOMP_CONF_PENALTY_PER_TICK = 3, LAGCOMP_BOOST_PER_TICK = 1.1,
    LAGCOMP_CHOKE_THRESH = 5, LAGCOMP_CHOKE_PENALTY_PER_TICK = 1.2, LAGCOMP_CHOKE_BOOST_PER_TICK = 0.4,
    SIM_FROZEN_THRESHOLD = 3, SIM_FROZEN_PENALTY = 20,
    FREESTAND_TRACE_DIST = 110, FREESTAND_THRESHOLD = 0.18, WALL_FS_DIST = 300, WALL_FS_OFF_ANGLES = {45,90,135},
    THREAT_LETHAL = 10, THREAT_AIR_SNIPER = 8, THREAT_AGGRESSIVE_PUSH = 7, THREAT_SNIPER_RANGE = 6,
    THREAT_RIFLE_CLOSE = 5, THREAT_NORMAL = 3, THREAT_SCAN_INTERVAL_HIGH = 3, THREAT_SCAN_INTERVAL_LOW = 6,
    EYE_LBY_ALIGN_THRESHOLD = 5, DESYNC_ALIGN_MAX = 10,
    PP11_ALIGN_DEG = 3.0, PP11_SIDE_MIN_DEG = 8.0, PP11_AMP_MIN_DEG = 6.0, PP11_SCALE = 116.0,
    PP11_SIDE_DEADBAND = 4.0, PP11_STRONG_DEG = 12,
    MEAS_MIN_DEG = 4, MEAS_MAX_SPD = 350, MEAS_BLEND = 0.15, SEED_AMP_CAP = 58,
    ALIGN_SETTLE_TICKS = 3, ALIGN_EYE_SETTLE = 2, ALIGN_BREAK_COOLDOWN = 8,
    ALIGN_MISS_BLOCK = 2, ALIGN_BLOCK_TICKS = 25,
    PITCH_TILT_DEG = 45,
    MOVE_MIN_SPD = 25, MOVE_FULL_SPD = 50, MOVE_AIR_MIN_SPD = 150, MOVE_AIR_MAX_TURN = 70,
    MOVE_MIN_DEG = 3.0, PITCH_DEF_DEG = 84,
    PITCH_DOWN_MIN = 76, PITCH_DEF_UP_MAX = -35, PITCH_DEF_FLAT_MAX = 48, PITCH_UNTRUSTED = 89.5,
    LEGIT_AA_MAX_ANGLE = 60, LEGIT_AA_MIN_ANGLE = 30, LEGIT_AA_JITTER_MAX = 60, BREAK_LC_TICKS = 4,
    VOTE_STICKY = 1.12,
    WEAPON_GROUPS = {
        pistol={1,2,3,4,30,32,36,61,63,64}, rifle={7,8,9,10,13,14,16,39,60}, sniper={9,11,38,40},
        auto={11,38}, shotgun={25,26,27,29,35}, smg={17,19,23,24,26,33,34}, heavy={28,31},
        knife={42,59,500,503,505,506,507,508,509,510,511,512,514,515,516,517,518,519,520,521},
    },
}
local FL_ONGROUND, FL_DUCKING = 1, 4
local HITGROUP_NAMES = {[0]="generic",[1]="head",[2]="chest",[3]="stomach",[4]="left arm",[5]="right arm",
    [6]="left leg",[7]="right leg",[8]="neck",[9]="?",[10]="gear"}
local AA_STATE_MAX_DELTA = { ["stand"]=58, ["run"]=58, ["jump"]=58, ["duck"]=50,
    ["duck move"]=50, ["duck jump"]=58, ["slow walk"]=58 }

-- 7 ── state
local ST = { player_memory={}, player_animation_data={}, simtime_history={}, layer_history={},
    shot_context={}, last_applied={}, resolver_seed={}, angle_hit_data={}, last_valid_pos={},
    last_valid_vel={}, last_valid_tick={}, resolver_lock={}, lby_update_cache={}, side_flip_history={},
    side_score={}, fs_bait={}, animation_records={}, bone_matrix_cache={}, pose_parameter_cache={},
    tickbase_data={}, desync_data={}, jitter_data_v={}, confidence_data={}, bruteforce_data={},
    safe_head_data={}, last_resolve_tick={}, cache_session={}, network_angle_history={},
    lby_broke={}, lby_broke_side={}, lby_broke_ang={}, last_moving_cache={}, yaw_accel_history={}, entity_cache={},
    cache_timestamp={}, cache_data={}, crouch_cache={}, flip_history={}, aa_state={},
    break_lc={}, instant_block={}, baim_req={}, unsafe={}, hard_tick={}, vote_side={},
    pp_hist={}, sgn={}, thrash={}, break_lc_until={}, last_result={}, last_result_sim={},
    lby_change_tick={}, eye_change_tick={}, aligned_miss_n={},
    pitch_hist={}, clean_pp11={}, anim_interp={}, sgn_player={}, dt_burst={}, on_shot={} }
ST.purge_cache = function(player)
    local prefix = tostring(player) .. "|"
    for _, tbl in ipairs({ST.cache_data, ST.cache_timestamp, ST.cache_session}) do
        for k in pairs(tbl) do
            if type(k) == "string" and k:sub(1, #prefix) == prefix then tbl[k] = nil end
        end
    end
end
local wall_data, _pfs_cache, last_plist_reset = {}, {}, {}
local is_tickbase_shifting, max_angle

-- 8 ── math
local function vec(x,y,z) return {x=x or 0, y=y or 0, z=z or 0} end
local function vec_len(v) return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) end
local function normalize_yaw(yaw)
    yaw = math.fmod(yaw + 180, 360)
    if yaw < 0 then yaw = yaw + 360 end
    return yaw - 180
end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function CalcAngle(xs,ys,zs,xd,yd,zd)
    local dx, dy, dz = xd-xs, yd-ys, zd-zs
    local hyp = math.sqrt(dx*dx + dy*dy)
    if hyp < 0.001 then return 0, 0 end
    return -math.atan2(dz, hyp) * C.RAD2DEG, normalize_yaw(math.atan2(dy, dx) * C.RAD2DEG)
end
local function vec_dist(a, b)
    if not a or not b then return 9999 end
    return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2)
end
local function trace_hit_valid(he, target) return he == -1 or he == target end

-- 9 ── detectori pp11
local BF_STAGES = { {1,38}, {-1,38}, {1,58}, {-1,58}, {1,20}, {-1,20} }
local function pp11_raw(player)
    local v = entity.get_prop(player, "m_flPoseParameter", 11)
    if type(v) ~= "number" or v < 0 or v > 1 then return nil end
    return v
end
local function pp11_is_echo(player, raw_deg)
    if not raw_deg then return true end
    local cur = BRUTE.cur_applied and BRUTE.cur_applied(player)
    if cur == nil then return false end
    if math.abs(raw_deg - cur) < 2.2 or (cur ~= 0 and math.abs(raw_deg + cur) < 2.2) then
        local cp = ST.clean_pp11[player]
        if not cp or (globals.tickcount() - (cp.tick or 0)) > 8 then return true end
    end
    return false
end
local function pp11_raw_dev(player)
    local v = pp11_raw(player)
    if not v then return nil end
    local deg = (v - 0.5) * C.PP11_SCALE
    if pp11_is_echo(player, deg) then
        local cp = ST.clean_pp11[player]
        if cp and (globals.tickcount() - (cp.tick or 0)) <= 16 then return cp.deg end
        return nil
    end
    ST.clean_pp11[player] = { deg = deg, v = v, tick = globals.tickcount() }
    return deg
end
local function pp11_dev_signed(player)
    local d = pp11_raw_dev(player)
    if not d then return nil end
    return d * (BRUTE.M and BRUTE.M.sign or 1)
end
local function pp11_raw_side(player)
    local d = pp11_raw_dev(player)
    if not d or math.abs(d) < C.PP11_SIDE_DEADBAND then return 0 end
    return d > 0 and 1 or -1
end
local function pp11_body_delta(player)
    local eye = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    return normalize_yaw(lby - eye)
end
local function pp11_stable(player)
    local h = ST.pp_hist[player]
    if not h or #h < 3 then return true end
    local lo, hi = 1, 0
    for i = #h - 2, #h do
        local v = h[i].v
        if v < lo then lo = v end
        if v > hi then hi = v end
    end
    return (hi - lo) < 0.02
end
local function pp11_jump(player)
    local h = ST.pp_hist[player]
    if not h or #h < 2 then return 0 end
    return math.abs(h[#h].v - h[#h-1].v) * C.PP11_SCALE
end
local function get_fake_limit(player)
    local st_name = ST.aa_state[player] or "stand"
    local state_lim = AA_STATE_MAX_DELTA[st_name] or 58
    local anim_lim = max_angle and max_angle(player) or state_lim
    local dd = ST.desync_data[player]
    if dd and dd.desync_delta and dd.desync_delta >= 12 and dd.confidence > 60 then
        return clamp(math.max(math.abs(dd.desync_delta) + 6, anim_lim * 0.85), 18, state_lim)
    end
    local eye = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    local delta = math.abs(normalize_yaw(eye - lby))
    if delta >= 12 then
        return clamp(math.max(delta + 6, anim_lim), 18, state_lim)
    end
    return clamp(anim_lim, 18, state_lim)
end
local function update_pitch_history(player)
    local pt = entity.get_prop(player, "m_angEyeAngles[0]")
    if type(pt) ~= "number" then return end
    local sim = entity.get_prop(player, "m_flSimulationTime") or 0
    local h = ST.pitch_hist[player]
    if not h then h = { last_sim = -1, down_ticks = 0, last_normal = 89, flick_until = 0, last_pt = pt }; ST.pitch_hist[player] = h end
    if sim == h.last_sim then return end
    h.last_sim = sim
    if pt >= C.PITCH_DOWN_MIN and pt <= C.PITCH_UNTRUSTED then
        h.down_ticks = math.min(32, (h.down_ticks or 0) + 1)
        h.last_normal = pt
    elseif pt <= C.PITCH_DEF_UP_MAX or (math.abs(pt) <= C.PITCH_DEF_FLAT_MAX and (h.down_ticks or 0) >= 2) then
        h.flick_until = globals.tickcount() + 6
    elseif math.abs(pt - (h.last_pt or pt)) >= 45 then
        h.flick_until = globals.tickcount() + 5
    else
        h.down_ticks = math.max(0, (h.down_ticks or 0) - 1)
    end
    h.last_pt = pt
end
local function is_defensive_pitch(player)
    local pt = entity.get_prop(player, "m_angEyeAngles[0]") or 0
    if math.abs(pt) > C.PITCH_UNTRUSTED then return true, "untrusted" end
    local h = ST.pitch_hist[player]
    local tick = globals.tickcount()
    if pt <= C.PITCH_DEF_UP_MAX then return true, "up" end
    if h and (h.flick_until or 0) >= tick and pt < C.PITCH_DOWN_MIN then return true, "flick" end
    if ST.hard_recent and ST.hard_recent(player, 4) and pt < C.PITCH_DOWN_MIN then return true, "shift_pitch" end
    return false, nil
end
local function detect_on_shot(player)
    local w = entity.get_player_weapon(player)
    if not w then return false end
    local lst = entity.get_prop(w, "m_fLastShotTime")
    local sim = entity.get_prop(player, "m_flSimulationTime")
    if type(lst) ~= "number" or type(sim) ~= "number" or lst <= 0 then return false end
    local ti = globals.tickinterval() or C.TICK_INTERVAL
    if math.abs(sim - lst) <= ti * 2.0 then
        ST.on_shot[player] = globals.tickcount()
        return true
    end
    return ST.on_shot[player] ~= nil and (globals.tickcount() - ST.on_shot[player]) <= 1
end
local function aligned_shortcut_ok(player)
    local vx, vy = entity.get_prop(player, "m_vecVelocity")
    local fl = entity.get_prop(player, "m_fFlags") or 1
    if math.sqrt((vx or 0)^2 + (vy or 0)^2) > 5 or bit.band(fl, FL_ONGROUND) == 0 then return false end
    local pm = ST.player_memory[player]
    if pm and (pm.misses or 0) > 0 then return false end
    local l6 = get_anim_overlay_ffi(player, 6)
    if l6 and l6.valid and ((l6.weight or 0) > 0.001 or (l6.playback_rate or 0) > 0.0005) then
        return false
    end
    local bf = ST.bruteforce_data[player]
    if bf and #bf.hit_hist > 0 and math.abs(bf.hit_hist[1].angle or 0) >= 15 then return false end
    return true
end
local function truly_aligned(player)
    local d = pp11_raw_dev(player)
    if not d then return false end
    return math.abs(d) < C.PP11_ALIGN_DEG
end
local function aligned_stable(player)
    local tick = globals.tickcount()
    local lt = ST.lby_change_tick[player]
    if lt and (tick - lt) < C.ALIGN_SETTLE_TICKS then return false end
    local et = ST.eye_change_tick[player]
    if et and (tick - et) < C.ALIGN_EYE_SETTLE then return false end
    if ST.lby_broke[player] and (tick - ST.lby_broke[player]) < C.ALIGN_BREAK_COOLDOWN then return false end
    local h = ST.pp_hist[player]
    if h and #h >= 3 then
        for i = #h - 2, #h do
            if math.abs((h[i].v - 0.5) * C.PP11_SCALE) >= C.PP11_ALIGN_DEG then return false end
        end
    end
    return true
end
local function aligned_blocked(player)
    local b = ST.instant_block[player]
    return b ~= nil and b > globals.tickcount()
end
local function aligned_full_ok(player)
    return aligned_shortcut_ok(player) and truly_aligned(player) and aligned_stable(player)
        and not aligned_blocked(player) and not is_defensive_pitch(player)
end
local function check_eye_lby_aligned(player)
    local eye = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    local delta = math.abs(normalize_yaw(eye - lby))
    local dd = ST.desync_data[player]
    local measured = dd and math.abs(dd.desync_delta or 0) or 0
    return (delta < C.EYE_LBY_ALIGN_THRESHOLD and measured < C.DESYNC_ALIGN_MAX and aligned_full_ok(player)),
        eye, lby, delta
end
local function get_desync_resolution(player)
    local d = ST.desync_data[player]
    if not d or d.confidence < 30 then return nil, 0 end
    return d.desync_side, clamp(d.max_desync_delta or 0, 0, 58)
end

-- 10 ── cache
local CACHE_MAX_ENTRIES = 200
local function ckey(player, t) return string.format("%d|%s", player, tostring(t)) end
local function is_cache_valid(player, t, max_age)
    if not ui.get(smart_cache) then return false end
    local k = ckey(player, t)
    if not ST.cache_timestamp[k] or ST.cache_session[k] ~= session_id then return false end
    return (globals.tickcount() - ST.cache_timestamp[k]) < (max_age or C.CACHE_MAX_AGE)
end
local function set_cache(player, t, data)
    local k = ckey(player, t)
    local count = 0
    for _ in pairs(ST.cache_timestamp) do count = count + 1 end
    if count > CACHE_MAX_ENTRIES then
        local arr = {}
        for kk, v in pairs(ST.cache_timestamp) do arr[#arr+1] = {key=kk, time=v} end
        table.sort(arr, function(a,b) return a.time < b.time end)
        for i = 1, math.floor(CACHE_MAX_ENTRIES*0.25) do
            local kk = arr[i] and arr[i].key
            if kk then ST.cache_data[kk], ST.cache_timestamp[kk], ST.cache_session[kk] = nil, nil, nil end
        end
    end
    ST.cache_data[k], ST.cache_timestamp[k], ST.cache_session[k] = data, globals.tickcount(), session_id
end
local function get_cache(player, t) return ST.cache_data[ckey(player, t)] end

-- 11 ── entity / weapon
local function get_weapon_info(player)
    if not player then return {idx=0, is_lethal=false, is_sniper=false, is_rifle=false} end
    local weapon = entity.get_player_weapon(player)
    if not weapon then return {idx=0, is_lethal=false, is_sniper=false, is_rifle=false} end
    local def = entity.get_prop(weapon, "m_iItemDefinitionIndex") or 0
    local function in_group(g)
        local t = C.WEAPON_GROUPS[g]
        if not t then return false end
        for _, id in ipairs(t) do if id == def then return true end end
        return false
    end
    return { idx=def, is_lethal=(def==31 or def==42 or def==59), is_sniper=in_group("sniper"), is_rifle=in_group("rifle") }
end
local function get_velocity(player)
    local x, y, z = entity.get_prop(player, "m_vecVelocity")
    if x == nil then return 0 end
    return math.sqrt(x*x + y*y + z*z)
end
local function get_velocity_vector(player)
    local x, y, z = entity.get_prop(player, "m_vecVelocity")
    if not x then return vec(0,0,0) end
    return vec(x,y,z)
end
local function get_distance_to_local(player)
    local lp = entity.get_local_player()
    if not lp then return 9999 end
    local lx, ly, lz = entity.get_origin(lp)
    local tx, ty, tz = entity.get_origin(player)
    if not lx or not tx then return 9999 end
    return math.sqrt((tx-lx)^2 + (ty-ly)^2 + (tz-lz)^2)
end
local function get_player_resource()
    if globals.tickcount() - cached_pr_tick < 10 and cached_pr then return cached_pr end
    cached_pr = entity.get_player_resource()
    cached_pr_tick = globals.tickcount()
    return cached_pr
end
local function get_entities() return entity.get_players(true) end
local function is_crouching(player)
    local f = entity.get_prop(player, "m_fFlags")
    return f ~= nil and bit.band(f, FL_DUCKING) == FL_DUCKING
end
local function is_on_ground(player)
    local f = entity.get_prop(player, "m_fFlags") or 0
    return bit.band(f, FL_ONGROUND) ~= 0
end
local function in_air(player) return not is_on_ground(player) end
-- [v8.4.0] pp11 = doar indiciu de amplitudine; partea vine din lby-eye (imun la corectie)
local function pp11_ampl_hint(player, side_measured, ampl_measured)
    local d = pp11_dev_signed(player)
    if not d or math.abs(d) < C.PP11_AMP_MIN_DEG then return ampl_measured, nil end
    if (d > 0 and 1 or -1) == side_measured then
        local blended = ampl_measured*(1 - C.MEAS_BLEND) + math.min(math.abs(d), 58)*C.MEAS_BLEND
        return blended, true
    end
    return ampl_measured, false
end
-- [v8.4.0] masurare desync din netprop de server
local function measured_desync(player)
    if not is_on_ground(player) then return nil end
    if get_velocity(player) > C.MEAS_MAX_SPD then return nil end
    local eye = entity.get_prop(player, "m_angEyeAngles[1]")
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget")
    if not eye or not lby then return nil end
    local bd = normalize_yaw(lby - eye)
    local ab = math.abs(bd)
    if ab < C.MEAS_MIN_DEG or ab > 60 then return nil end
    return bd > 0 and 1 or -1, ab, bd
end
local function state(player)
    if player == nil then return 2 end
    local vel = get_velocity(player)
    if vel < 5 and not in_air(player) and not is_crouching(player) then return 1
    elseif in_air(player) and is_crouching(player) then return 5
    elseif in_air(player) then return 4
    elseif is_crouching(player) then return 6
    elseif vel <= 78 then return 3
    else return 2 end
end
local function get_ent(player)
    if not player or type(player) ~= "number" then return nil end
    if ST.entity_cache[player] == nil and entity.is_alive(player) then ST.entity_cache[player] = player end
    if not ST.entity_cache[player] then return nil end
    return {
        get_anim_state = function()
            local eye = entity.get_prop(player, "m_angEyeAngles[1]")
            local lby = entity.get_prop(player, "m_flLowerBodyYawTarget")
            local duck = entity.get_prop(player, "m_flDuckAmount") or 0
            if not eye then return nil end
            local vx, vy = entity.get_prop(player, "m_vecVelocity")
            local spd2d = math.sqrt((vx or 0)^2 + (vy or 0)^2)
            local max_spd = entity.get_prop(player, "m_flMaxspeed") or 260
            if max_spd <= 0 then max_spd = 260 end
            local flRunningSpeed = clamp(spd2d / (max_spd * 0.520), 0, 1)
            local flDuckingSpeed = clamp(spd2d / (max_spd * 0.340), 0, 1)
            local ai = ST.anim_interp[player]
            local sim = entity.get_prop(player, "m_flSimulationTime") or 0
            if not ai then
                ai = { stop_to_full = 0, last_sim = sim, last_walk = false }
                ST.anim_interp[player] = ai
            elseif sim > ai.last_sim then
                local dt = clamp(sim - ai.last_sim, 0, 0.5)
                ai.last_sim = sim
                if spd2d > (max_spd * 0.520) then
                    ai.stop_to_full = clamp(ai.stop_to_full + dt * 2.0, 0, 1)
                elseif spd2d < (max_spd * 0.520) then
                    ai.stop_to_full = clamp(ai.stop_to_full - dt * 2.0, 0, 1)
                end
            end
            return { goal_feet_yaw=lby or eye, current_feet_yaw=lby or eye, max_yaw=58, duck_amount=duck,
                feet_speed_forwards_or_sideways=flRunningSpeed,
                feet_speed_unknown_forwards_or_sideways=flDuckingSpeed,
                stop_to_full_running_fraction=ai.stop_to_full, speed2d=spd2d, max_speed=max_spd }
        end,
        get_anim_overlay = function(_, index) return get_anim_overlay_ffi(player, index) end,
    }
end
local function get_ent_safe(player)
    if not player or type(player) ~= "number" then return nil end
    if not entity.is_alive(player) then ST.entity_cache[player] = nil; return nil end
    return get_ent(player)
end

-- 12 ── simtime + istoric pp11
local function simtime_push(player, sim, tick, vx, vy)
    if not ST.simtime_history[player] then
        ST.simtime_history[player] = {buf={}, head=1, size=0, max=C.SIMTIME_HISTORY_MAX} end
    local h = ST.simtime_history[player]
    h.buf[h.head] = {sim=sim, tick=tick, vx=vx or 0, vy=vy or 0}
    h.head = (h.head % h.max) + 1
    if h.size < h.max then h.size = h.size + 1 end
end
local function simtime_get(player, idx)
    local h = ST.simtime_history[player]
    if not h or h.size == 0 or idx > h.size then return nil end
    return h.buf[(h.head - 1 - idx + h.max*2) % h.max + 1]
end
local function pp_hist_push(player)
    local v, sim = pp11_raw(player), entity.get_prop(player, "m_flSimulationTime")
    if v == nil or sim == nil then return end
    local h = ST.pp_hist[player]
    if not h then h = {}; ST.pp_hist[player] = h end
    local last = h[#h]
    if last and math.abs(last.sim - sim) < 0.0001 then last.tick = globals.tickcount(); return end
    h[#h+1] = { sim=sim, v=v, tick=globals.tickcount() }
    while #h > 32 do table.remove(h, 1) end
end
local function init_animation_records(player)
    if not ST.animation_records[player] then
        ST.animation_records[player] = {records={}, index=0, size=0, max_size=C.ANIM_RECORD_MAX} end
end
local function store_animation_record(player)
    init_animation_records(player)
    local ent = get_ent_safe(player)
    if not ent then return nil end
    local anim = ent:get_anim_state()
    if not anim then return nil end
    local ox, oy, oz = entity.get_origin(player)
    if not ox then return nil end
    local record = { tick=globals.tickcount(), simtime=entity.get_prop(player,"m_flSimulationTime") or 0,
        origin=vec(ox,oy,oz), velocity=get_velocity_vector(player),
        eye_yaw=entity.get_prop(player,"m_angEyeAngles[1]") or 0, goal_feet_yaw=anim.goal_feet_yaw or 0,
        current_feet_yaw=anim.current_feet_yaw or 0,
        lower_body_yaw=entity.get_prop(player,"m_flLowerBodyYawTarget") or 0,
        duck_amount=entity.get_prop(player,"m_flDuckAmount") or 0, animation_layers={} }
    for _, i in ipairs({1,3,6,12}) do
        local l = ent:get_anim_overlay(i)
        if l and l.valid ~= false then
            record.animation_layers[i] = { sequence=l.sequence or 0, playback_rate=l.playback_rate or 0,
                cycle=l.cycle or 0, weight=l.weight or 0 }
        end
    end
    local recs = ST.animation_records[player]
    recs.index = (recs.index % recs.max_size) + 1
    recs.records[recs.index] = record
    if recs.size < recs.max_size then recs.size = recs.size + 1 end
    if not ST.bone_matrix_cache[player] then ST.bone_matrix_cache[player] = {} end
    local bm = ST.bone_matrix_cache[player]
    for _, hb in ipairs({C.HITBOX_HEAD, C.HITBOX_PELVIS, C.HITBOX_CHEST}) do
        local hx, hy, hz = entity.hitbox_position(player, hb)
        if hx then bm[hb] = {x=hx, y=hy, z=hz, tick=record.tick} end
    end
    if not ST.pose_parameter_cache[player] then ST.pose_parameter_cache[player] = {} end
    local pp = ST.pose_parameter_cache[player]
    for _, idx in ipairs({11,12,13}) do
        local v = entity.get_prop(player, "m_flPoseParameter", idx)
        if type(v) == "number" then pp[idx] = {value=v, tick=record.tick} end
    end
    return record
end
local function get_animation_record(player, offset)
    init_animation_records(player)
    local recs = ST.animation_records[player]
    if recs.size < offset then return nil end
    return recs.records[(recs.index - offset + recs.max_size*2) % recs.max_size + 1]
end
local function get_latest_record(player) return get_animation_record(player, 1) end

-- 13 ── desync
local function init_desync_data(player)
    if not ST.desync_data[player] then
        ST.desync_data[player] = {delta_hist={}, last_update=0, desync_side=1, desync_delta=0,
            confidence=0, max_desync_delta=58, eye=0, lby=0, gfy=0}
    end
end
local function update_desync_data(player)
    init_desync_data(player)
    local d = ST.desync_data[player]
    local rec = get_latest_record(player)
    if not rec then return end
    local tick = globals.tickcount()
    if tick == d.last_update or (rec.simtime and d.last_sim == rec.simtime) then return end
    d.last_sim = rec.simtime
    local ey, lby = rec.eye_yaw, rec.lower_body_yaw
    local mvx, mvy = entity.get_prop(player, "m_vecVelocity")
    local mfl = entity.get_prop(player, "m_fFlags") or 1
    d.eye, d.lby, d.gfy, d.last_update = ey, lby, rec.goal_feet_yaw, tick
    local spd2d = math.sqrt((mvx or 0)^2 + (mvy or 0)^2)
    if spd2d > 130 or bit.band(mfl, FL_ONGROUND) == 0 then
        d.desync_delta, d.confidence = 0, 15; return end
    local st_max = AA_STATE_MAX_DELTA[ST.aa_state[player] or "stand"] or 58
    local anim_lim = max_angle and max_angle(player) or st_max
    local body_delta = normalize_yaw(lby - ey)
    local delta = clamp(body_delta, -58, 58)
    local l6 = rec.animation_layers and rec.animation_layers[6]
    local l3 = rec.animation_layers and rec.animation_layers[3]
    local micro_active = (spd2d < 4) and l6 and ((l6.weight or 0) > 0.0005 or (l6.playback_rate or 0) > 0.0002)
    local lby_breaker = (spd2d < 4) and l3 and l3.sequence == 4 and ((l3.weight or 0) > 0.01 or (l3.cycle or 0) < 0.95)
    if math.abs(body_delta) < 3 then
        if micro_active or lby_breaker then
            delta = (d.desync_side or 1) * math.min(anim_lim, lby_breaker and 58 or 52)
        else
            delta = 0
        end
    end
    local side = delta > 0 and 1 or (delta < 0 and -1 or (d.desync_side or 1))
    d.max_desync_delta = clamp(math.max(math.abs(delta) + 5, anim_lim), 18, st_max)
    d.desync_delta, d.desync_side = math.abs(delta), side
    table.insert(d.delta_hist, 1, {delta=delta, side=side, tick=tick})
    if #d.delta_hist > 16 then table.remove(d.delta_hist) end
    local conf = 50
    if math.abs(delta) > 35 then conf = conf + 25 end
    if math.abs(delta) > 45 then conf = conf + 15 end
    if micro_active or lby_breaker then conf = math.max(conf, 68) end
    if math.abs(delta) < 3 then conf = 20 end
    if #d.delta_hist >= 4 then
        local same = 0
        for i = 1, 4 do if d.delta_hist[i].side == side then same = same + 1 end end
        if same >= 3 then conf = conf + 20 end
    end
    d.confidence = math.min(100, conf)
end

-- 14 ── instant head guided
local function get_instant_head_guided(player)
    if aligned_blocked(player) then return nil end
    local eye_now = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    local lby_now = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    local pitch_now = math.abs(entity.get_prop(player, "m_angEyeAngles[0]") or 0)
    local def_pitch = is_defensive_pitch(player)
    if detect_on_shot(player) and not def_pitch then
        return { side=0, angle=0, yaw=eye_now, confidence=97, source="on_shot_head",
            force_shoot=true, is_instant_head=true, meas=true }
    end
    if math.abs(normalize_yaw(eye_now - lby_now)) < 3 and aligned_full_ok(player)
       and not def_pitch then
        local c = pitch_now >= C.PITCH_TILT_DEG and 80 or 95
        return { side=0, angle=0, yaw=eye_now, confidence=c, source="instant_head_aligned",
            force_shoot=(c >= 90), is_instant_head=true } end
    return nil
end

-- 15 ── break LC
local function detect_break_lc(player)
    local weapon = entity.get_player_weapon(player)
    if not weapon then ST.break_lc[player] = {detected=false}; return false end
    local idx = entity.get_prop(weapon, "m_iItemDefinitionIndex")
    local reload = entity.get_prop(weapon, "m_bInReload")
    local d = ST.break_lc[player]
    if not d or d.last_idx == nil then
        ST.break_lc[player] = {detected=false, last_idx=idx, last_reload=reload}; return false end
    local fired = false
    if idx ~= nil and d.last_idx ~= nil and idx ~= d.last_idx then
        ST.break_lc_until[player] = globals.tickcount() + C.BREAK_LC_TICKS; fired = true end
    if d.last_reload == false and reload == true then
        ST.break_lc_until[player] = globals.tickcount() + C.BREAK_LC_TICKS; fired = true end
    d.last_idx, d.last_reload, d.detected = idx, reload, fired
    return fired
end

-- 16 ── vizibilitate / crouch
local function is_head_visible(player)
    local lp = entity.get_local_player()
    if not lp then return false end
    local hx, hy, hz = entity.hitbox_position(player, C.HITBOX_HEAD)
    local ex, ey, ez = client.eye_position()
    if not hx or not ex then return false end
    local visible = 0
    for _, off in ipairs(C.HEAD_TRACE_OFFSETS) do
        local frac, he = client.trace_line(lp, ex, ey, ez, hx+off[1], hy+off[2], hz+off[3])
        if frac >= C.HEAD_VISIBLE_THRESHOLD and trace_hit_valid(he, player) then visible = visible + 1 end
    end
    return visible >= 1
end
local function is_body_visible(player)
    local lp = entity.get_local_player()
    if not lp then return false, C.HITBOX_STOMACH end
    local ex, ey, ez = client.eye_position()
    if not ex then return false, C.HITBOX_STOMACH end
    for _, hb in ipairs(C.BODY_HITBOXS) do
        local x, y, z = entity.hitbox_position(player, hb)
        if x then
            local frac, he = client.trace_line(lp, ex, ey, ez, x, y, z)
            if frac >= C.BODY_VISIBLE_THRESHOLD and trace_hit_valid(he, player) then return true, hb end
        end
    end
    return false, C.HITBOX_STOMACH
end
local function is_holding_ssg08()
    local lp = entity.get_local_player()
    if not lp then return false end
    local w = entity.get_player_weapon(lp)
    if not w then return false end
    local d = (entity.get_prop(w, "m_iItemDefinitionIndex") or 0) % 65536
    return d == 40
end
local function ssg_wants_head_only(player)
    if not ui.get(head_priority) then return false end
    if is_holding_ssg08() then
        local hp = entity.get_prop(player, "m_iHealth") or 100
        return hp > 75
    end
    return false
end
local function handle_crouch_safe_head(player)
    if not ui.get(crouch_fix) then return nil end
    if ssg_wants_head_only(player) then return nil end
    local flags = entity.get_prop(player, "m_fFlags") or 0
    if bit.band(flags, FL_DUCKING) == 0 then ST.crouch_cache[player] = nil; return nil end
    local c = ST.crouch_cache[player]
    if c and globals.tickcount() - c.tick < 6 then return c.result end
    local head_visible = is_head_visible(player)
    local body_visible, body_hb = is_body_visible(player)
    if not head_visible and body_visible then
        local r = { force_body=true, hitbox=body_hb, min_damage=25, reason="crouch_safe_head", force_shoot=true }
        ST.crouch_cache[player] = {result=r, tick=globals.tickcount()}; return r
    end
    if head_visible and body_visible and not get_weapon_info(entity.get_local_player()).is_sniper
       and not ui.get(head_priority) then
        return { force_body=true, hitbox=body_hb, min_damage=20, reason="crouch_body_preferred", force_shoot=false }
    end
    return nil
end

-- 17 ── threat / aa state / head hidden
local function get_threat_level(player)
    if not ui.get(threat_priority) then return C.THREAT_NORMAL, "normal", {} end
    if is_cache_valid(player, "threat", C.THREAT_CACHE_AGE) then
        local c = get_cache(player, "threat")
        if c then return c.level, c.type, c.info end
    end
    local weapon = get_weapon_info(player)
    local vel = get_velocity(player)
    local air = not is_on_ground(player)
    local dist = get_distance_to_local(player)
    local level, ttype = C.THREAT_NORMAL, "normal"
    if weapon.is_lethal then level, ttype = C.THREAT_LETHAL, "lethal_cqc"
    elseif air and weapon.is_sniper then level, ttype = C.THREAT_AIR_SNIPER, "air_sniper"
    elseif vel > 200 and dist < 500 then level, ttype = C.THREAT_AGGRESSIVE_PUSH, "aggressive_push"
    elseif weapon.is_sniper and dist > 1000 then level, ttype = C.THREAT_SNIPER_RANGE, "sniper_range"
    elseif weapon.is_rifle and dist < 800 then level, ttype = C.THREAT_RIFLE_CLOSE, "rifle_close" end
    local info = { weapon=weapon, velocity=vel, in_air=air, distance=dist }
    set_cache(player, "threat", { level=level, type=ttype, info=info })
    return level, ttype, info
end
local function detect_aa_state(player)
    local vel = get_velocity(player)
    local duck = entity.get_prop(player, "m_flDuckAmount") or 0
    local air = not is_on_ground(player)
    if air and duck > 0.8 then return "duck jump"
    elseif air then return "jump"
    elseif vel > 3 and duck > 0.8 then return "duck move"
    elseif vel > 3 and vel < 100 then return "slow walk"
    elseif vel > 3 then return "run"
    elseif duck > 0.8 then return "duck"
    else return "stand" end
end
local function update_aa_state(player) ST.aa_state[player] = detect_aa_state(player) end
local function detect_head_hidden(player)
    if is_head_visible(player) then return false end
    return is_body_visible(player) == true
end

-- 18 ── flip / jitter
local function track_side_flip(player)
    if not ST.flip_history[player] then
        ST.flip_history[player] = {last_side=0, intervals={}, last_flip_tick=0, last_eye=nil} end
    local d = ST.flip_history[player]
    local sim = entity.get_prop(player, "m_flSimulationTime")
    if sim and d.last_sim == sim then return end
    d.last_sim = sim
    local eye = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    local bd = normalize_yaw(lby - eye)
    local side = 0
    if math.abs(bd) >= 4 then
        side = bd > 0 and 1 or -1
    elseif d.last_eye ~= nil then
        local ed = normalize_yaw(eye - d.last_eye)
        if math.abs(ed) >= 8 then side = ed > 0 and -1 or 1 else side = d.last_side end
    end
    d.last_eye = eye
    if d.last_side ~= 0 and side ~= 0 and side ~= d.last_side then
        local interval = globals.tickcount() - d.last_flip_tick
        if interval >= 1 and interval < 64 then
            table.insert(d.intervals, interval)
            if #d.intervals > 12 then table.remove(d.intervals, 1) end
        end
        d.last_flip_tick = globals.tickcount()
    end
    if side ~= 0 then d.last_side = side end
end
local function predict_next_flip(player)
    local d = ST.flip_history[player]
    if not d or #d.intervals < 4 then return nil end
    local sorted = {}
    for _, v in ipairs(d.intervals) do sorted[#sorted+1] = v end
    table.sort(sorted)
    local median = sorted[math.floor(#sorted/2) + 1]
    if math.abs((globals.tickcount() - d.last_flip_tick) - median) <= 2 then return -d.last_side end
    return d.last_side
end
local function init_jitter_data_v(player)
    if not ST.jitter_data_v[player] then
        ST.jitter_data_v[player] = {yaw_hist={}, delta_hist={}, pattern="none", predicted_side=1, predicted_angle=58, confidence=0} end
end
local function update_jitter_data_v(player)
    init_jitter_data_v(player)
    local d = ST.jitter_data_v[player]
    local rec = get_latest_record(player)
    if not rec or (rec.simtime and d.last_sim == rec.simtime) then return end
    d.last_sim = rec.simtime
    table.insert(d.yaw_hist, 1, rec.eye_yaw)
    if #d.yaw_hist > 16 then table.remove(d.yaw_hist) end
    if #d.yaw_hist < 2 then return end
    local cur_delta = normalize_yaw(rec.eye_yaw - d.yaw_hist[2])
    table.insert(d.delta_hist, 1, cur_delta)
    if #d.delta_hist > 15 then table.remove(d.delta_hist) end
    if #d.delta_hist < 3 then return end
    local n_check = math.min(8, #d.delta_hist)
    local sign_changes, big_flips, same_dir, total_abs = 0, 0, 0, math.abs(d.delta_hist[1])
    for i = 2, n_check do
        local d1, d2 = d.delta_hist[i-1], d.delta_hist[i]
        total_abs = total_abs + math.abs(d2)
        if math.abs(d1) >= 8 and math.abs(d2) >= 8 then
            if (d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0) then
                sign_changes = sign_changes + 1
                if math.abs(math.abs(d1) - math.abs(d2)) <= 22 then big_flips = big_flips + 1 end
            elseif (d1 > 0 and d2 > 0) or (d1 < 0 and d2 < 0) then
                same_dir = same_dir + 1
            end
        end
    end
    local avg_mag = total_abs / n_check
    local anim_lim = max_angle and max_angle(player) or 58
    if avg_mag < 6 then
        d.pattern, d.confidence = "none", 0
        return
    end
    if sign_changes >= math.max(2, n_check - 2) then
        if big_flips >= math.max(2, sign_changes - 1) then
            d.pattern = "alternating"
            d.predicted_side = d.delta_hist[1] > 0 and -1 or 1
            d.predicted_angle = clamp(math.max(32, avg_mag * 0.72), 28, anim_lim)
            d.confidence = math.min(92, 62 + sign_changes * 5 + math.min(avg_mag, 40) * 0.25)
        else
            d.pattern = "offset"
            local sum_yaw = 0
            for i = 1, math.min(4, #d.yaw_hist) do sum_yaw = sum_yaw + normalize_yaw(d.yaw_hist[i] - rec.eye_yaw) end
            d.predicted_side = sum_yaw >= 0 and 1 or -1
            d.predicted_angle = clamp(math.max(29, avg_mag * 0.65), 25, anim_lim)
            d.confidence = math.min(84, 54 + sign_changes * 4)
        end
    elseif same_dir >= math.max(2, n_check - 2) and avg_mag >= 14 then
        d.pattern = "spin"
        d.predicted_side = d.delta_hist[1] > 0 and -1 or 1
        d.predicted_angle = clamp(anim_lim, 35, 58)
        d.confidence = math.min(80, 50 + same_dir * 5)
    elseif sign_changes >= 2 and avg_mag >= 10 then
        d.pattern = "3way"
        local pos = 0
        for i = 1, n_check do if d.delta_hist[i] > 0 then pos = pos + 1 end end
        d.predicted_side = (d.delta_hist[1] > 8 and -1) or (d.delta_hist[1] < -8 and 1) or (pos > n_check/2 and 1 or -1)
        d.predicted_angle = clamp(math.max(35, avg_mag * 0.6), 28, anim_lim)
        d.confidence = math.min(75, 45 + sign_changes * 5)
    else d.pattern, d.confidence = "none", 0 end
end
local function get_jitter_resolution(player)
    init_jitter_data_v(player)
    local d = ST.jitter_data_v[player]
    if d.confidence < 25 then return 0, 0, 0 end
    return d.predicted_side, d.confidence, d.predicted_angle or 58
end

-- 19 ── bruteforce
local function init_bruteforce_data(player)
    if not ST.bruteforce_data[player] then
        ST.bruteforce_data[player] = { hit_hist={}, miss_hist={}, log_p_left=-0.693, log_p_right=-0.693,
            angle_scores={}, last_side=1, last_angle=0, confidence=50, adaptive_mode="balanced",
            miss_streak={side=1, count=0}, immediate_flip=false, next_side=1,
            last_miss_side=0, consecutive_miss_count=0,
            system_hitrate={ desync={hits=0,misses=0,rate=0.5}, jitter={hits=0,misses=0,rate=0.5},
                safe_head={hits=0,misses=0,rate=0.5}, layer={hits=0,misses=0,rate=0.5},
                lby={hits=0,misses=0,rate=0.5}, bruteforce={hits=0,misses=0,rate=0.5},
                pp11_live={hits=0,misses=0,rate=0.5}, pp11_fallback={hits=0,misses=0,rate=0.5},
                pp11_aligned={hits=0,misses=0,rate=0.5}, desync_measured={hits=0,misses=0,rate=0.5},
                eye_lby_aligned_direct={hits=0,misses=0,rate=0.5}, instant_head_aligned={hits=0,misses=0,rate=0.5},
                move_yaw={hits=0,misses=0,rate=0.5}, bullet_pick={hits=0,misses=0,rate=0.5} } }
    end
end
local function update_system_hitrate(player, source, is_hit)
    init_bruteforce_data(player)
    local sys = ST.bruteforce_data[player].system_hitrate[source]
    if not sys then sys = {hits=0,misses=0,rate=0.5}; ST.bruteforce_data[player].system_hitrate[source] = sys end
    if is_hit then sys.hits = sys.hits + 1 else sys.misses = sys.misses + 1 end
    local tot = sys.hits + sys.misses
    if tot > 0 then sys.rate = sys.rate*0.7 + (sys.hits/tot)*0.3 end
end
local function record_hit_bf(player, side, angle, src)
    init_bruteforce_data(player)
    local d = ST.bruteforce_data[player]
    local tick = globals.tickcount()
    table.insert(d.hit_hist, 1, {side=side, angle=angle, tick=tick})
    if #d.hit_hist > 32 then table.remove(d.hit_hist) end
    if side == 1 then d.log_p_left = d.log_p_left + 0.847; d.log_p_right = d.log_p_right - 0.847
    else d.log_p_right = d.log_p_right + 0.847; d.log_p_left = d.log_p_left - 0.847 end
    local m = math.max(d.log_p_left, d.log_p_right)
    d.log_p_left, d.log_p_right = d.log_p_left - m, d.log_p_right - m
    local ab = math.floor(angle/10)*10
    if not d.angle_scores[ab] then d.angle_scores[ab] = {hits=0, misses=0, last_tick=tick} end
    d.angle_scores[ab].hits = d.angle_scores[ab].hits + 1
    d.angle_scores[ab].last_tick = tick
    local total = #d.hit_hist + #d.miss_hist
    d.confidence = total > 0 and ((#d.hit_hist+2)/(total+4))*100 or 50
    d.last_side, d.last_angle = side, angle
    d.consecutive_miss_count, d.last_miss_side = 0, 0
    if src then update_system_hitrate(player, src, true) end
end
local function record_miss_bf(player, side, angle, src)
    init_bruteforce_data(player)
    local d = ST.bruteforce_data[player]
    if d.last_miss_side == side then d.consecutive_miss_count = d.consecutive_miss_count + 1
    else d.consecutive_miss_count = 1 end
    d.last_miss_side = side
    if d.consecutive_miss_count >= 2 then
        d.log_p_left, d.log_p_right = d.log_p_left*0.75, d.log_p_right*0.75
        d.immediate_flip, d.next_side = true, -side
        d.consecutive_miss_count = 0
    end
    if d.miss_streak.side == side then
        d.miss_streak.count = d.miss_streak.count + 1
        if d.miss_streak.count >= C.MISS_STREAK_FLIP then
            d.immediate_flip, d.next_side, d.miss_streak.count = true, -side, 0 end
    else d.miss_streak = {side=side, count=1} end
    local tick = globals.tickcount()
    table.insert(d.miss_hist, 1, {side=side, angle=angle, tick=tick})
    if #d.miss_hist > 32 then table.remove(d.miss_hist) end
    if side == 1 then d.log_p_left = d.log_p_left - 1.099; d.log_p_right = d.log_p_right + 0.405
    else d.log_p_right = d.log_p_right - 1.099; d.log_p_left = d.log_p_left + 0.405 end
    local m = math.max(d.log_p_left, d.log_p_right)
    d.log_p_left, d.log_p_right = d.log_p_left - m, d.log_p_right - m
    local ab = math.floor(angle/10)*10
    if not d.angle_scores[ab] then d.angle_scores[ab] = {hits=0, misses=0, last_tick=tick} end
    d.angle_scores[ab].misses = d.angle_scores[ab].misses + 1
    d.angle_scores[ab].last_tick = tick
    local total = #d.hit_hist + #d.miss_hist
    d.confidence = total > 0 and ((#d.hit_hist+2)/(total+4))*100 or 50
    if src then update_system_hitrate(player, src, false) end
end
local function get_adaptive_bruteforce(player, default_side, default_angle)
    init_bruteforce_data(player)
    local d = ST.bruteforce_data[player]
    local tick = globals.tickcount()
    local p_left, p_right = math.exp(d.log_p_left), math.exp(d.log_p_right)
    local p_tot = p_left + p_right
    local prob_left = p_tot > 0 and (p_left/p_tot) or 0.5
    local prob_right = p_tot > 0 and (p_right/p_tot) or 0.5
    local best_side
    if prob_left > prob_right + 0.1 then best_side = 1
    elseif prob_right > prob_left + 0.1 then best_side = -1
    else best_side = default_side end
    local best_angle, best_score = default_angle, -999
    for ab, sc in pairs(d.angle_scores) do
        local tot = sc.hits + sc.misses
        if tot > 0 then
            local age = math.max(0.25, 1 - ((tick - (sc.last_tick or tick))/256))
            local s = ((sc.hits+1)/(tot+2))*100*age
            if s > best_score then best_score, best_angle = s, ab end
        end
    end
    if d.confidence < 30 then d.adaptive_mode = "aggressive"
    elseif d.confidence > 70 then d.adaptive_mode = "conservative"
    else d.adaptive_mode = "balanced" end
    if d.adaptive_mode == "aggressive" then
        if #d.miss_hist > 0 and d.miss_hist[1].side == d.last_side then best_side = -d.last_side end
        if not best_angle or best_angle < 28 then best_angle = 58 end
    elseif d.adaptive_mode == "conservative" then
        best_side = prob_left > prob_right and 1 or -1
        best_angle = (best_angle and best_angle >= 18) and best_angle or (default_angle and default_angle >= 18 and default_angle or 58)
    else best_angle = (best_angle and best_angle >= 18) and best_angle or 38 end
    local recent = 0
    for i = 1, math.min(3, #d.miss_hist) do
        if d.miss_hist[i].side == best_side and d.miss_hist[i].angle == best_angle then recent = recent + 1 end
    end
    if recent >= 2 then
        best_side, best_angle = -best_side, 38
        local stamp = d.miss_hist[1] and d.miss_hist[1].tick or 0
        if d._pen_stamp ~= stamp then d._pen_stamp = stamp; d.confidence = math.max(0, d.confidence - 30) end
    end
    local flip = predict_next_flip(player)
    if flip and flip ~= 0 and d.confidence > 40 then best_side = flip end
    if d.immediate_flip then
        d.immediate_flip = false
        return (d.next_side ~= 0 and d.next_side or -d.last_side), 38, 70
    end
    d.last_side = best_side
    return best_side, best_angle or 38, d.confidence
end

-- 20 ── confidence engine
local function init_confidence_data_v(player)
    if not ST.confidence_data[player] then
        ST.confidence_data[player] = { layer_stability=50, resolver_history=50, hit_ratio=50,
            velocity_state=50, tickbase_exploit=50, desync_validation=50, overall_confidence=50 } end
end
local function update_confidence_engine(player)
    init_confidence_data_v(player)
    local d = ST.confidence_data[player]
    local rec = get_latest_record(player)
    if not rec then return end
    local l6, l3 = rec.animation_layers[6], rec.animation_layers[3]
    if l6 then
        local prev_rec = get_animation_record(player, 2)
        local prev_l6 = prev_rec and prev_rec.animation_layers and prev_rec.animation_layers[6]
        local pr_diff = prev_l6 and math.abs((l6.playback_rate or 0) - (prev_l6.playback_rate or 0)) or 0
        d.layer_stability = clamp(90 - pr_diff * 400 - ((l3 and (l3.weight or 0) > 0.5) and 15 or 0), 20, 95)
    end
    local vel = vec_len(rec.velocity)
    if vel < 5 then d.velocity_state = 80 elseif vel < 100 then d.velocity_state = 60
    elseif is_on_ground(player) then d.velocity_state = 40 else d.velocity_state = 20 end
    d.tickbase_exploit = (is_tickbase_shifting and is_tickbase_shifting(player)) and 70 or 50
    d.desync_validation = get_desync_resolution(player) and 70 or 30
    local bf = ST.bruteforce_data[player]
    if bf then d.hit_ratio = bf.confidence end
    local system_weight, system_score = 0, 0
    if bf and bf.system_hitrate then
        local weights = {desync=0.25, jitter=0.20, safe_head=0.15, layer=0.20, lby=0.10, bruteforce=0.10,
            pp11_live=0.20, pp11_fallback=0.20, pp11_aligned=0.15, desync_measured=0.35,
            eye_lby_aligned_direct=0.25, instant_head_aligned=0.20, move_yaw=0.15,
            jitter_lby_fake=0.20, desync_lby_fake=0.20, wall_freestand=0.15, moving_cache=0.15}
        for name, w in pairs(weights) do
            local s = bf.system_hitrate[name]
            if s then
                local tot = s.hits + s.misses
                if tot >= 3 then system_score = system_score + s.rate*100*w; system_weight = system_weight + w end
            end
        end
        if system_weight > 0 then d.resolver_history = system_score/system_weight end
    end
    local w_layer, w_history = 0.20, (system_weight > 0 and 0.30 or 0.15)
    local w_hit, w_vel, w_tick, w_desync = 0.25, 0.10, 0.08, 0.07
    local w_total = w_layer + w_history + w_hit + w_vel + w_tick + w_desync
    d.overall_confidence = math.min(100, (d.layer_stability*w_layer + d.resolver_history*w_history +
        d.hit_ratio*w_hit + d.velocity_state*w_vel + d.tickbase_exploit*w_tick + d.desync_validation*w_desync)/w_total)
end
local function get_confidence_engine(player)
    init_confidence_data_v(player)
    return ST.confidence_data[player].overall_confidence or 50
end

-- 21 ── tickbase
local function init_tickbase_data(player)
    if not ST.tickbase_data[player] then
        ST.tickbase_data[player] = { history={}, last_simtime=nil, last_realtime=nil, last_tick=nil, shifted_ticks=0,
            is_shifting=false, is_doubletap=false, is_hideshots=false, recharge_time=0,
            dt_confidence=0, hs_confidence=0, initialized=false, choke=0, choke_prev=0, shift_until=0 } end
end
local function update_tickbase_data(player)
    init_tickbase_data(player)
    local d = ST.tickbase_data[player]
    local simtime = entity.get_prop(player, "m_flSimulationTime") or 0
    local ti = globals.tickinterval()
    local rt = globals.realtime()
    local now_tick = globals.tickcount()
    if not ti or ti <= 0 then ti = C.TICK_INTERVAL end
    if not d.initialized then
        d.last_simtime, d.last_realtime, d.last_tick, d.initialized = simtime, rt, now_tick, true
        return
    end
    if simtime == d.last_simtime then
        if d.last_choke_tick ~= now_tick then
            d.last_choke_tick = now_tick
            d.choke = (d.choke or 0) + 1
        end
        if (d.choke or 0) >= C.CHOKE_MIN then d.is_choking = true end
        if d.is_shifting and d.recharge_time > 0 and now_tick > d.recharge_time then
            d.is_shifting, d.shifted_ticks = false, 0 end
        return
    end
    local real_dt = rt - (d.last_realtime or rt)
    local sim_dt = simtime - d.last_simtime
    if real_dt <= 0 or real_dt > 1 then
        d.last_simtime, d.last_realtime, d.last_tick, d.choke = simtime, rt, now_tick, 0
        d.is_shifting, d.shifted_ticks = false, 0
        return
    end
    local tick_elapsed = math.max(1, now_tick - (d.last_tick or now_tick))
    local sim_t = sim_dt / ti
    local expected_t = math.max(tick_elapsed, (d.choke or 0) + 1)
    local burst = math.floor((sim_t - expected_t) + 0.5)
    local mag = math.abs(burst)
    d.choke_prev, d.choke, d.is_choking = d.choke, 0, false
    if sim_dt < -ti then
        local back_ticks = math.min(22, math.abs(math.floor(sim_dt / ti + 0.5)))
        d.shifted_ticks = math.max(2, back_ticks)
        d.is_shifting = true
        d.shift_until = now_tick + math.min(d.shifted_ticks + 2, 8)
        d.recharge_time = now_tick + back_ticks + 2
        ST.hard_tick[player] = now_tick; ST.unsafe[player] = now_tick
    elseif burst >= 14 and (d.choke_prev or 0) <= 2 then
        d.shifted_ticks, d.is_shifting = burst, true
        d.shift_until = now_tick + 6
        d.recharge_time = now_tick + math.min(burst, 16) + 2
        ST.hard_tick[player] = now_tick; ST.unsafe[player] = now_tick
    elseif d.recharge_time > 0 and now_tick > d.recharge_time then
        d.is_shifting, d.shifted_ticks = false, 0
    end
    if (d.shift_until or 0) < now_tick then d.is_shifting = false end
    if (sim_dt < -ti * 6) or (burst >= C.DT_SHIFT_MIN and burst <= C.DT_SHIFT_MAX) then
        d.dt_confidence = math.min(100, d.dt_confidence + C.DT_CONFIDENCE_HIT)
    elseif mag <= 2 and not d.is_choking then
        d.dt_confidence = math.max(0, d.dt_confidence - C.DT_CONFIDENCE_MISS) end
    if (sim_dt < -ti * 3 and sim_dt >= -ti * 10) or (burst >= C.HS_SHIFT_MIN and burst <= C.HS_SHIFT_MAX) then
        d.hs_confidence = math.min(100, d.hs_confidence + C.HS_CONFIDENCE_HIT)
    elseif mag <= 1 then d.hs_confidence = math.max(0, d.hs_confidence - C.HS_CONFIDENCE_MISS) end
    d.is_doubletap = d.dt_confidence >= C.DT_CONFIDENCE_THRESHOLD
    d.is_hideshots = d.hs_confidence >= C.HS_CONFIDENCE_THRESHOLD
    table.insert(d.history, 1, {simtime=simtime, tick=now_tick, shifted=d.shifted_ticks})
    if #d.history > 16 then table.remove(d.history) end
    d.last_simtime, d.last_realtime, d.last_tick = simtime, rt, now_tick
end
is_tickbase_shifting = function(player) init_tickbase_data(player); return ST.tickbase_data[player].is_shifting end
local function is_using_doubletap(player) init_tickbase_data(player); return ST.tickbase_data[player].is_doubletap end
ST.hard_recent = function(player, n)
    local t = ST.hard_tick[player]
    return t ~= nil and (globals.tickcount() - t) <= (n or 2)
end
ST.is_hard_shift = function(player) return ST.hard_recent(player, 2) end

-- 22 ── safe head
local function init_safe_head_data(player)
    if not ST.safe_head_data[player] then
        ST.safe_head_data[player] = { best_angle=0, confidence=0, cache_origin={x=0,y=0,z=0},
            cache_result=false, cache_timestamp=0, cache_points={} } end
end
local function optimized_safe_head_scan(player)
    init_safe_head_data(player)
    local data = ST.safe_head_data[player]
    if not is_on_ground(player) or get_velocity(player) > 35 then
        data.best_angle, data.confidence, data.cache_result = 0, 0, false
        return false, {}, 0, 0
    end
    local ox, oy, oz = entity.get_origin(player)
    if not ox then return data.cache_result, data.cache_points, data.best_angle, data.confidence end
    local origin = vec(ox, oy, oz)
    if ui.get(smart_cache) and vec_dist(origin, data.cache_origin) < 8
       and (globals.realtime() - data.cache_timestamp) < 0.1 then
        return data.cache_result, data.cache_points, data.best_angle, data.confidence end
    local threat = ui.get(threat_priority) and get_threat_level(player) or C.THREAT_NORMAL
    local scan_interval = threat >= 8 and C.THREAT_SCAN_INTERVAL_HIGH or C.THREAT_SCAN_INTERVAL_LOW
    if globals.tickcount() % scan_interval ~= 0 then
        return data.cache_result, data.cache_points, data.best_angle, data.confidence end
    local record = get_latest_record(player)
    local lp = entity.get_local_player()
    if not record or not lp then return false, {}, 0, 0 end
    local ex, ey, ez = client.eye_position()
    if not ex then return false, {}, 0, 0 end
    local duck = entity.get_prop(player, "m_flDuckAmount") or 0
    local head_z = record.origin.z + (C.HEAD_OFFSET_STAND - duck*C.HEAD_OFFSET_DUCK_LERP)
    local fake_limit = get_fake_limit(player)
    local candidate_deltas = { -58, -38, 38, 58 }
    local best_angle, best_cover, min_frac, max_frac = 0, -1, 1.0, 0.0
    local safe_angles = {}
    for _, d_ang in ipairs(candidate_deltas) do
        local clamped = clamp(d_ang, -fake_limit, fake_limit)
        local world_yaw = normalize_yaw(record.eye_yaw + clamped)
        local rad = world_yaw * C.DEG2RAD
        local hx = record.origin.x + math.cos(rad) * 18
        local hy = record.origin.y + math.sin(rad) * 18
        local frac_eye = client.trace_line(player, ex, ey, ez, hx, hy, head_z) or 1
        local frac_wall = client.trace_line(player, record.origin.x, record.origin.y, head_z,
            record.origin.x + math.cos(rad) * C.SAFE_HEAD_SCAN_DIST,
            record.origin.y + math.sin(rad) * C.SAFE_HEAD_SCAN_DIST, head_z) or 1
        if frac_eye < min_frac then min_frac = frac_eye end
        if frac_eye > max_frac then max_frac = frac_eye end
        local cover_score = (1.0 - frac_eye) * 70 + (1.0 - frac_wall) * 30
        safe_angles[#safe_angles+1] = clamped
        if cover_score > best_cover then
            best_cover, best_angle = cover_score, clamped
        end
    end
    local asym = max_frac - min_frac
    local conf = 0
    if min_frac < 0.55 and max_frac > 0.90 and asym >= 0.35 then
        conf = clamp(math.floor(45 + asym * 50), 0, 88)
    end
    if conf < C.SAFE_HEAD_CONF_THRESHOLD then best_angle = 0 end
    data.best_angle, data.confidence = best_angle, conf
    data.cache_result, data.cache_points = conf >= C.SAFE_HEAD_CONF_THRESHOLD, safe_angles
    data.cache_origin, data.cache_timestamp = origin, globals.realtime()
    return data.cache_result, safe_angles, best_angle, data.confidence
end
local function get_safe_head_resolution(player)
    local _, _, angle, conf = optimized_safe_head_scan(player)
    if conf < C.SAFE_HEAD_CONF_THRESHOLD then return nil, 0 end
    return angle, conf
end

-- 23 ── melee
local function is_melee_weapon(weapon)
    if not weapon then return false end
    local def = entity.get_prop(weapon, "m_iItemDefinitionIndex")
    return def == 31 or def == 42 or def == 59
end

-- 24 ── lagcomp
local function lagcomp_analyze(player)
    local empty = {boost=0, is_choking=false, is_frozen=false, is_teleport=false, confidence_penalty=0}
    local h = ST.simtime_history[player]
    if not h or h.size < 3 then return empty end
    local ti = globals.tickinterval()
    if not ti or ti <= 0 then ti = C.TICK_INTERVAL end
    local n, p2, p5 = simtime_get(player,1), simtime_get(player,2), simtime_get(player, math.min(h.size,5))
    if not n or not p2 or not p5 then return empty end
    local boost, penalty = 0, 0
    local is_choking, is_frozen, is_teleport = false, false, false
    local sim_adv, tick_adv = (n.sim or 0) - (p5.sim or 0), ((n.tick or 0) - (p5.tick or 0))*ti
    if sim_adv > 0 and tick_adv > 0 then
        local lag = tick_adv - sim_adv
        if lag >= ti*3 then
            local lag_ticks = math.floor(lag/ti + 0.5)
            boost = clamp(lag_ticks*C.LAGCOMP_BOOST_PER_TICK, 0, C.LAGCOMP_BOOST_CAP)
            penalty = penalty + clamp(lag_ticks*C.LAGCOMP_CONF_PENALTY_PER_TICK, 0, 25)
        end
    end
    local choke = ((n.sim or 0) - (p2.sim or 0))/ti
    if choke > C.LAGCOMP_CHOKE_THRESH then
        is_choking = true
        penalty = penalty + math.min(choke*C.LAGCOMP_CHOKE_PENALTY_PER_TICK, 30)
        boost = boost + math.min(math.floor(choke*C.LAGCOMP_CHOKE_BOOST_PER_TICK), 6)
    end
    local frozen = 0
    for i = 1, math.min(h.size-1, 6) do
        local a, b = simtime_get(player,i), simtime_get(player,i+1)
        if a and b and math.abs((a.sim or 0) - (b.sim or 0)) < C.EPSILON then frozen = frozen + 1 end
    end
    if frozen >= C.SIM_FROZEN_THRESHOLD then
        is_frozen = true; penalty = penalty + C.SIM_FROZEN_PENALTY; boost = 0 end
    if n.vx ~= nil and math.sqrt(n.vx*n.vx + n.vy*n.vy) > 700 then is_teleport = true; penalty = penalty + 20 end
    return { boost=clamp(boost,0,C.LAGCOMP_BOOST_CAP), is_choking=is_choking, is_frozen=is_frozen,
        is_teleport=is_teleport, confidence_penalty=clamp(penalty,0,50) }
end

-- 25 ── moving cache / yaw accel / LBY / flip
local function update_moving_cache(player, side, angle, yaw)
    if get_velocity(player) > 5 then
        local hx, hy, hz = entity.hitbox_position(player, C.HITBOX_HEAD)
        ST.last_moving_cache[player] = { side=side, angle=angle, yaw=yaw, tick=globals.tickcount(),
            head=(hx and vec(hx,hy,hz)) or nil }
    end
end
local function get_moving_resolver(player)
    local c = ST.last_moving_cache[player]
    if not c then return nil end
    local cached_eye = normalize_yaw((c.yaw or 0) - (c.side or 0)*(c.angle or 0))
    if math.abs(normalize_yaw(cached_eye - (entity.get_prop(player, "m_angEyeAngles[1]") or 0))) > 15 then
        ST.last_moving_cache[player] = nil; return nil end
    local lc = lagcomp_analyze(player)
    local max_age = C.MOVING_CACHE_MAX_AGE + math.floor((lc.boost or 0)*0.5)
    if (globals.tickcount() - c.tick) > max_age then return nil end
    return c
end
local function update_yaw_accel(player, yaw)
    if not ST.yaw_accel_history[player] then
        ST.yaw_accel_history[player] = {buf={}, head=1, size=0, max=C.YAW_ACCEL_MAX} end
    local h = ST.yaw_accel_history[player]
    local sim = entity.get_prop(player, "m_flSimulationTime")
    if sim and h.last_sim == sim then return end
    h.last_sim = sim
    h.buf[h.head] = yaw
    h.head = (h.head % h.max) + 1
    if h.size < h.max then h.size = h.size + 1 end
end
local function get_yaw_accel(player)
    local h = ST.yaw_accel_history[player]
    if not h or h.size < 3 then return 0, false end
    local function g(i) return h.buf[(h.head - 1 - i + h.max*2) % h.max + 1] or 0 end
    local d1, d2 = normalize_yaw(g(1)-g(2)), normalize_yaw(g(2)-g(3))
    local accel = math.abs(d1 - d2)
    return accel, (accel > 45 or (math.abs(d1) > 50 and (d1*d2) < 0))
end
local function update_lby_timing(player)
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget")
    if not lby then return end
    if not ST.lby_update_cache[player] then
        ST.lby_update_cache[player] = {last_lby=lby, last_update=globals.tickcount(), interval=0,
            update_count=0, predicted_tick=0} end
    local c = ST.lby_update_cache[player]
    if math.abs(normalize_yaw(lby - c.last_lby)) > 2 then
        local interval = globals.tickcount() - c.last_update
        if c.update_count > 0 and interval > 5 and interval < 100 then c.interval = c.interval*0.7 + interval*0.3
        elseif interval > 5 then c.interval = interval end
        c.last_lby, c.last_update = lby, globals.tickcount()
        c.update_count = c.update_count + 1
        if c.interval > 5 then c.predicted_tick = globals.tickcount() + math.floor(c.interval) end
        ST.lby_change_tick[player] = globals.tickcount()
    end
end
local function lby_detect(player)
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget")
    local eye = entity.get_prop(player, "m_angEyeAngles[1]")
    if lby == nil or eye == nil then return nil, nil end
    local diff = normalize_yaw(lby - eye)
    if math.abs(diff) > 35 then return clamp(math.abs(diff), 0, 58), (diff > 0 and 1 or -1) end
    return nil, nil
end
local function get_lby_prediction(player)
    local c = ST.lby_update_cache[player]
    if not c or c.interval == 0 then return false, 0, nil end
    local ticks = (c.predicted_tick or 0) - globals.tickcount()
    local _, side = lby_detect(player)
    return (ticks >= -2 and ticks <= 4), ticks, side
end
local function update_flip_history(player, side)
    if not ST.side_flip_history[player] then
        ST.side_flip_history[player] = {last_side=side, last_flip_tick=globals.tickcount(), intervals={}, avg_interval=0}
        return end
    local h = ST.side_flip_history[player]
    if side ~= h.last_side then
        local interval = globals.tickcount() - h.last_flip_tick
        if interval > 3 and interval < 200 then
            table.insert(h.intervals, interval)
            if #h.intervals > C.FLIP_INTERVAL_MAX then table.remove(h.intervals, 1) end
            local sum = 0
            for _, v in ipairs(h.intervals) do sum = sum + v end
            h.avg_interval = sum/#h.intervals
        end
        h.last_side, h.last_flip_tick = side, globals.tickcount()
    end
end

-- 26 ── side score / angle data
local function ss_init(player, st, side)
    ST.side_score[player] = ST.side_score[player] or {}
    ST.side_score[player][st] = ST.side_score[player][st] or {}
    ST.side_score[player][st][side] = ST.side_score[player][st][side] or {h=0, m=0}
    return ST.side_score[player][st][side]
end
local function ss_record_hit(player, st, side)
    local s = ss_init(player, st, side); s.h, s.m = (s.h or 0)*C.DECAY_RATE + 1, (s.m or 0)*C.DECAY_RATE end
local function ss_record_miss(player, st, side)
    local s = ss_init(player, st, side); s.h, s.m = (s.h or 0)*C.DECAY_RATE, (s.m or 0)*C.DECAY_RATE + 1 end
local function ss_best_side(player, st)
    if not ST.side_score[player] or not ST.side_score[player][st] then return nil end
    local pos = ST.side_score[player][st][1] or {h=0, m=0}
    local neg = ST.side_score[player][st][-1] or {h=0, m=0}
    local sp, sn = pos.h - pos.m*1.5, neg.h - neg.m*1.5
    if sp > sn + 1 then return 1 elseif sn > sp + 1 then return -1 end
    return nil
end
local function record_angle_hit(player, st, angle, hit)
    ST.angle_hit_data[player] = ST.angle_hit_data[player] or {}
    ST.angle_hit_data[player][st] = ST.angle_hit_data[player][st] or {}
    local bi, bd = 1, 999
    for i, bucket in ipairs(C.ANGLE_BUCKETS) do
        local d = math.abs(math.abs(angle) - bucket)
        if d < bd then bd, bi = d, i end
    end
    local t = ST.angle_hit_data[player][st]
    t[bi] = t[bi] or {h=0, m=0}
    if hit then t[bi].h = t[bi].h + 1 else t[bi].m = t[bi].m + 1 end
end
local function get_best_angle_bucket(player, st)
    if not ST.angle_hit_data[player] or not ST.angle_hit_data[player][st] then return nil end
    local bi, bs = nil, -999
    for i, d in pairs(ST.angle_hit_data[player][st]) do
        local score = (d.h or 0) - (d.m or 0)*1.5
        if score > bs then bs, bi = score, i end
    end
    if bi and bs > 0 then return C.ANGLE_BUCKETS[bi] end
    return nil
end

-- 27 ── anti-freestand bait
local function afb_check(player, fs_side, pm_side)
    if not fs_side or fs_side == 0 then return pm_side or 1 end
    if not ST.fs_bait[player] then ST.fs_bait[player] = {side=fs_side, miss=0, inv=false, cd=0} end
    local a = ST.fs_bait[player]
    if a.cd > 0 then a.cd = a.cd - 1; if a.cd == 0 then a.inv, a.miss = false, 0 end end
    if a.side ~= fs_side then a.side, a.miss, a.inv = fs_side, 0, false end
    if a.inv then return -fs_side end
    return fs_side
end
local function afb_miss(player, applied_side, fs_side)
    if not applied_side or not fs_side or fs_side == 0 then return end
    local a = ST.fs_bait[player]
    if not a or applied_side ~= fs_side then return end
    a.miss = (a.miss or 0) + 1
    if a.miss >= 3 then a.inv, a.cd = true, 20 end
end

-- 28 ── freestand
local function wall_freestand(player)
    player = player or 0
    wall_data[player] = wall_data[player] or {side=1, last_side=0, last_hit=0, hit_side=0, cache_tick=-1, cache_side=1}
    local wd = wall_data[player]
    local me = entity.get_local_player()
    if not me or entity.get_prop(me, "m_lifeState") ~= 0 then return 1 end
    local tick = globals.tickcount()
    if tick - wd.cache_tick < 4 then return wd.cache_side end
    wd.cache_tick = tick
    local now = globals.curtime()
    if wd.hit_side ~= 0 and now - wd.last_hit > 5 then wd.last_side, wd.last_hit, wd.hit_side = 0, 0, 0 end
    local ex, ey, ez = entity.get_origin(player)
    local mx, my = entity.get_origin(me)
    if not ex or not mx then return 1 end
    ez = ez + (entity.get_prop(player, "m_vecViewOffset[2]") or 64)
    local yaw = math.deg(math.atan2(my - ey, mx - ex))
    local left, right = 0, 0
    for _, off in ipairs(C.WALL_FS_OFF_ANGLES) do
        local rl = (yaw - off)*C.DEG2RAD
        left = left + client.trace_line(player, ex, ey, ez, ex + C.WALL_FS_DIST*math.cos(rl), ey + C.WALL_FS_DIST*math.sin(rl), ez)
        local rr = (yaw + off)*C.DEG2RAD
        right = right + client.trace_line(player, ex, ey, ez, ex + C.WALL_FS_DIST*math.cos(rr), ey + C.WALL_FS_DIST*math.sin(rr), ez)
    end
    local side
    if math.abs(left - right) < 0.15 then side = (wd.last_side ~= 0) and wd.last_side or 1
    else side = left < right and 1 or -1 end
    if wd.hit_side ~= 0 then side = wd.hit_side end
    wd.side, wd.last_side, wd.cache_side = side, side, side
    return side
end
local function player_freestand(player)
    local tick = globals.tickcount()
    local c = _pfs_cache[player]
    if c and tick - c.tick < 4 then return c.side end
    local lp = entity.get_local_player()
    if not lp then return 0 end
    local ex, ey, ez = client.eye_position()
    local px, py, pz = entity.get_origin(player)
    if not ex or not px then return 0 end
    local eye_yaw = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    local duck_p = entity.get_prop(player, "m_flDuckAmount") or 0
    local phead_z = pz + (C.HEAD_OFFSET_STAND - duck_p*(C.HEAD_OFFSET_STAND - C.HEAD_OFFSET_CROUCH))
    local frac_pos, frac_neg = 0, 0
    for _, radius in ipairs({ 18, 28 }) do
        local rad_pos = normalize_yaw(eye_yaw + 58) * C.DEG2RAD
        local rad_neg = normalize_yaw(eye_yaw - 58) * C.DEG2RAD
        local fp = client.trace_line(player, ex, ey, ez, px + radius * math.cos(rad_pos), py + radius * math.sin(rad_pos), phead_z) or 1
        local fn = client.trace_line(player, ex, ey, ez, px + radius * math.cos(rad_neg), py + radius * math.sin(rad_neg), phead_z) or 1
        frac_pos = frac_pos + fp
        frac_neg = frac_neg + fn
    end
    local side = 0
    if math.abs(frac_pos - frac_neg) >= 0.12 then
        side = (frac_pos < frac_neg) and 1 or -1
    end
    _pfs_cache[player] = {tick=tick, side=side}
    return side
end

-- 29 ── feedback
ST.learn = function(player, is_hit, applied_ang, src)
    if not applied_ang then return end
    if applied_ang == 0 then
        if src then update_system_hitrate(player, src, is_hit) end
        return
    end
    local st_i = state(player)
    local side = applied_ang > 0 and 1 or -1
    local ang = math.abs(applied_ang)
    if is_hit then
        record_hit_bf(player, side, ang, src); ss_record_hit(player, st_i, side)
        record_angle_hit(player, st_i, ang, true)
    else
        record_miss_bf(player, side, ang, src); ss_record_miss(player, st_i, side)
        record_angle_hit(player, st_i, ang, false)
        afb_miss(player, side, player_freestand(player))
    end
end

-- 30 ── anim layer
max_angle = function(player)
    local ent = get_ent(player)
    if not ent then return 58 end
    local a = ent:get_anim_state()
    if not a then return 58 end
    local fsf = clamp(a.feet_speed_forwards_or_sideways, 0, 1)
    local fsuf = clamp(a.feet_speed_unknown_forwards_or_sideways, 0, 1)
    local duck = clamp(a.duck_amount or 0, 0, 1)
    local value = (a.stop_to_full_running_fraction * -0.3 - 0.2)*fsf + 1
    if duck > 0 then value = value + duck*fsuf*(0.5 - value) end
    local raw = type(a.max_yaw) == "number" and a.max_yaw or 58
    return clamp(math.min(math.abs(raw), math.abs(raw)*value), 18, 58)
end
local function ring_get(buf, head, max, size, offset)
    if not buf or size <= offset then return nil end
    return buf[(head - 1 - offset + max*3) % max + 1]
end
local function anim_layer_resolve(player)
    local def = {side=1, angle=0, is_fake=false, confidence_bonus=0, frozen=false,
        side_flipped=false, is_transition=false, fake_move=false, rel_stable=true}
    if not player or not entity.is_alive(player) then return def end
    local ent = get_ent(player)
    if not ent then return def end
    local anim = ent:get_anim_state()
    if not anim then return def end
    local l1, l3 = ent:get_anim_overlay(1), ent:get_anim_overlay(3)
    local l6, l12 = ent:get_anim_overlay(6), ent:get_anim_overlay(12)
    if not l1 or l1.valid == false then return def end
    local pr1 = (l1 and type(l1.playback_rate) == "number" and l1.playback_rate) or 0
    local pr3 = (l3 and type(l3.playback_rate) == "number" and l3.playback_rate) or 0
    local pr6 = (l6 and type(l6.playback_rate) == "number" and l6.playback_rate) or 0
    local seq3 = (l3 and type(l3.sequence) == "number" and l3.sequence) or 0
    local w3 = (l3 and type(l3.weight) == "number" and l3.weight) or 0
    local w6 = (l6 and type(l6.weight) == "number" and l6.weight) or 0
    local w12 = (l12 and type(l12.weight) == "number" and l12.weight) or 0
    local cy3 = (l3 and type(l3.cycle) == "number" and l3.cycle) or 0
    local cy6 = (l6 and type(l6.cycle) == "number" and l6.cycle) or 0
    local spd2d = anim.speed2d or get_velocity(player)
    local exp_w6 = clamp(anim.feet_speed_forwards_or_sideways or 0, 0, 1)
    local diff13, diff36, diff16 = math.abs(pr1-pr3), math.abs(pr3-pr6), math.abs(pr1-pr6)
    local micro_desync = (spd2d < 4.0) and (w6 > 0.0005 or pr6 > 0.0002)
    local lby_breaker = (spd2d < 4.0) and (seq3 == 4) and (w3 > 0.005 or cy3 < 0.96)
    local move_desync = (spd2d >= 4.0) and (math.abs(w6 - exp_w6) > 0.08 or w12 > 0.08 or pr6 > 0.001)
    local is_fake = micro_desync or lby_breaker or move_desync or (diff13 > 0.18 and diff36 < 0.08) or (diff16 > 0.22 and w6 > 0.05)
    if not is_fake then return def end
    local is_transition = (w3 > 0.3 and w3 < 0.85) or (seq3 == 4 and w3 > 0.05)
    local pad = ST.player_animation_data[player]
    local frozen = false
    if pad then
        local cy6_floor = math.floor(cy6*1000)
        if cy6_floor == (pad.last_cy6 or -1) and get_velocity(player) > 30 then
            pad.freeze_ticks = (pad.freeze_ticks or 0) + 1
            frozen = (pad.freeze_ticks or 0) >= 3
        else pad.freeze_ticks = 0 end
        pad.last_cy6 = cy6_floor
    end
    if not ST.layer_history[player] then
        ST.layer_history[player] = {buf={}, head=1, size=0, max=C.LAYER_HISTORY_MAX} end
    local lh = ST.layer_history[player]
    lh.buf[lh.head] = {pr1=pr1, pr3=pr3, pr6=pr6, w6=w6, cy6=cy6, diff13=diff13}
    lh.head = (lh.head % lh.max) + 1
    if lh.size < lh.max then lh.size = lh.size + 1 end
    local pr1_delta, rel_stable = 0, true
    local prev = ring_get(lh.buf, lh.head, lh.max, lh.size, 1)
    if prev then
        pr1_delta = math.abs(pr1 - prev.pr1)
        rel_stable = math.abs(diff13 - (prev.diff13 or 0)) < 0.08
    end
    local side_flipped = pr1_delta > 0.38
    if pad then
        if w12 > 0.5 and w6 < 0.1 and get_velocity(player) > 30 then pad.fake_move_ticks = (pad.fake_move_ticks or 0) + 1
        else pad.fake_move_ticks = 0 end
    end
    local fake_move = pad and (pad.fake_move_ticks or 0) >= 3
    local la, pmm = ST.last_applied[player], ST.player_memory[player]
    local side = 0
    do
        local md_side = measured_desync(player)
        if md_side then side = md_side end
    end
    if side == 0 then side = ss_best_side(player, state(player)) or 0 end
    if side == 0 then
        local vx_l, vy_l = entity.get_prop(player, "m_vecVelocity")
        local eye_l = entity.get_prop(player, "m_angEyeAngles[1]") or 0
        if vx_l and spd2d >= 15 then
            local v_diff = normalize_yaw(math.deg(math.atan2(vy_l, vx_l)) - eye_l)
            if math.abs(v_diff) >= 8 and math.abs(v_diff) <= 165 then
                side = v_diff > 0 and 1 or -1
            end
        end
        if side == 0 then
            local fs_l = player_freestand(player)
            if fs_l and fs_l ~= 0 then side = fs_l end
        end
        if side == 0 and spd2d < 15 and seq3 == 4 and (w3 > 0.01 or cy3 < 0.95) then
            side = (cy3 < 0.5) and -1 or 1
        end
        if side == 0 and math.abs(w6 - exp_w6) > 0.015 then
            side = (w6 > exp_w6) and -1 or 1
        end
    end
    if side == 0 then
        local eye = entity.get_prop(player, "m_angEyeAngles[1]") or 0
        local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or eye
        local delta = normalize_yaw(lby - eye)
        if math.abs(delta) >= 3 then side = delta > 0 and 1 or -1 end
    end
    if side == 0 and la and la.side and la.side ~= 0 then side = la.side > 0 and 1 or -1 end
    if side == 0 and pmm and pmm.last_side and pmm.last_side ~= 0 then side = pmm.last_side > 0 and 1 or -1 end
    if side == 0 then side = -1 end
    local bonus = 12
    if rel_stable then bonus = bonus + 10 end
    if not side_flipped then bonus = bonus + 8 end
    if not frozen then bonus = bonus + 8 end
    if not fake_move then bonus = bonus + 5 end
    if not is_transition then bonus = bonus + 2 end
    return { side=side, angle=clamp(max_angle(player), 0, 58), is_fake=true,
        confidence_bonus=clamp(bonus, 0, 20), frozen=frozen, side_flipped=side_flipped,
        is_transition=is_transition, fake_move=fake_move, rel_stable=rel_stable }
end

-- 31 ── defensive_result
local function defensive_result(player, eye_live, src)
    local head_only = ssg_wants_head_only(player)
    local mside, mamp = measured_desync(player)
    if mside and mamp >= C.MEAS_MIN_DEG then
        local amp, agrees = pp11_ampl_hint(player, mside, mamp)
        amp = clamp(amp, 28, 58)
        local bv = (not head_only) and is_body_visible(player) or false
        return { side=mside, angle=amp, yaw=normalize_yaw(eye_live + mside*amp),
                 confidence=(agrees == false) and 78 or 88, source=src, force_shoot=false, meas=true,
                 force_body=bv, hitbox=(bv and C.HITBOX_STOMACH or "Head") }
    end
    local pm = ST.player_memory[player]
    local dd = ST.desync_data[player]
    local vx_d, vy_d = entity.get_prop(player, "m_vecVelocity")
    local spd_d = math.sqrt((vx_d or 0)^2 + (vy_d or 0)^2)
    local move_s = 0
    if vx_d and spd_d >= 25 then
        local vd = normalize_yaw(math.deg(math.atan2(vy_d, vx_d)) - eye_live)
        if math.abs(vd) >= 10 and math.abs(vd) <= 165 then move_s = vd > 0 and 1 or -1 end
    end
    local last_side = (move_s ~= 0 and move_s) or ss_best_side(player, state(player)) or player_freestand(player) or (pm and pm.last_side) or (dd and dd.desync_side) or 1
    if last_side == 0 then last_side = 1 end
    local st_lim = AA_STATE_MAX_DELTA[ST.aa_state[player] or "stand"] or 58
    local probe = clamp(st_lim, 38, 58)
    local bf = ST.bruteforce_data[player]
    if bf and #bf.hit_hist >= 1 and bf.confidence > 55 then probe = clamp(bf.hit_hist[1].angle, 29, 58) end
    local bv3 = (not head_only) and is_body_visible(player) or false
    return { side=last_side, angle=probe, yaw=normalize_yaw(eye_live + last_side*probe), confidence=70,
             source=src, force_shoot=false, force_body=bv3,
             hitbox=(bv3 and C.HITBOX_STOMACH or "Head") }
end

-- 32 ── resolve_player (inner)
local function resolve_player_inner(player, pm)
    if not get_ent(player) then return nil end
    local lc_pre = lagcomp_analyze(player)
    local sim_now = entity.get_prop(player, "m_flSimulationTime") or 0
    local th = ST.thrash[player]
    if th and th.sim == sim_now and lc_pre.is_frozen and th.res then return th.res end
    local _air_fast = (not is_on_ground(player)) and get_velocity(player) > 150
    local eye_live = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    local lby_live = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    local pitch_live = math.abs(entity.get_prop(player, "m_angEyeAngles[0]") or 0)
    local def_pitch = is_defensive_pitch(player)
    if detect_on_shot(player) and not def_pitch then
        return { yaw=eye_live, side=0, angle=0, confidence=97,
            source="on_shot_head", force_shoot=true,
            hitbox="Head", is_instant_head=true, meas=true }
    end
    if not def_pitch
       and math.abs(normalize_yaw(eye_live - lby_live)) < 3 and aligned_full_ok(player) then
        local dd = ST.desync_data[player]
        if (dd and math.abs(dd.desync_delta or 0) or 0) < 10 then
            local tilted = pitch_live >= C.PITCH_TILT_DEG
            return { yaw=eye_live, side=0, angle=0, confidence=tilted and 80 or 96,
                source="eye_lby_aligned_direct", force_shoot=(not tilted),
                hitbox="Head", is_instant_head=true } end
    end
    local head_hidden = detect_head_hidden(player)
    detect_break_lc(player)
    local blu = ST.break_lc_until[player]
    if blu and globals.tickcount() <= blu and get_velocity(player) <= 10 then
        return { yaw=eye_live, side=0, angle=0, confidence=88, source="break_lc_reset",
                 force_shoot=true, hitbox="Head" } end

    if def_pitch then
        local dss, dsd = get_desync_resolution(player)
        local mside_pre, mamp_pre = measured_desync(player)
        local pp11_strong_pre = (not mside_pre) and pp11_dev_signed(player)
            and math.abs(pp11_dev_signed(player)) >= C.PP11_STRONG_DEG
        if (not dss or (dsd or 0) < 8) and not pp11_strong_pre and not (mside_pre and mamp_pre >= C.MEAS_MIN_DEG) then
            return defensive_result(player, eye_live, "defensive_aa") end
    end

    do
        local fl0 = entity.get_prop(player, "m_fFlags") or 0
        local vx, vy = entity.get_prop(player, "m_vecVelocity")
        local spd = math.sqrt((vx or 0)^2 + (vy or 0)^2)
        local eye0 = entity.get_prop(player, "m_angEyeAngles[1]") or 0
        local tb = ST.tickbase_data[player]
        local on_gnd = bit.band(fl0, FL_ONGROUND) ~= 0

        -- [v8.4.0] SURSA PRIMARA: lby - eye (netprop de server, imun la corectie)
        local mside, mamp = measured_desync(player)
        if mside and mamp >= C.MEAS_MIN_DEG then
            local amp, agrees = pp11_ampl_hint(player, mside, mamp)
            local cap_m = math.min(58, math.max(max_angle(player), 10))
            amp = clamp(amp, C.MEAS_MIN_DEG, cap_m)
            local fl_m = get_fake_limit(player)
            if fl_m > 0 then amp = math.min(amp, math.max(fl_m, C.MEAS_MIN_DEG)) end
            local c = 92
            if lc_pre.is_frozen then c = c - 5 end
            if (lc_pre.confidence_penalty or 0) > 0 then c = c - lc_pre.confidence_penalty*0.2 end
            if tb and tb.is_doubletap then c = c - 6 end
            if agrees == false then c = c - 8 end
            if spd > C.MOVE_MIN_SPD then c = c - 6 end
            if mamp < 8 then c = c - 12 end
            local conf = math.max(45, math.floor(c))
            local r = { yaw=normalize_yaw(eye0 + mside*amp), side=mside, angle=amp,
                        confidence=conf, source="desync_measured", force_shoot=false, hitbox="Head", meas=true }
            if not ssg_wants_head_only(player) and def_pitch then
                r.force_body, r.hitbox = true, C.HITBOX_STOMACH
                if not is_body_visible(player) then r.force_body, r.hitbox = false, "Head" end
            elseif not ssg_wants_head_only(player) and head_hidden then
                r.force_body, r.hitbox = true, C.HITBOX_STOMACH
            end
            return r
        end

        local mv_min = on_gnd and C.MOVE_FULL_SPD or C.MOVE_AIR_MIN_SPD
        local heading_ok = true
        if not on_gnd and vx ~= nil and vy ~= nil then
            local p2 = simtime_get(player, 2)
            if p2 and (p2.vx ~= 0 or p2.vy ~= 0) then
                local d0 = math.deg(math.atan2(p2.vy, p2.vx))
                local d1 = math.deg(math.atan2(vy, vx))
                if math.abs(normalize_yaw(d1 - d0)) > C.MOVE_AIR_MAX_TURN then heading_ok = false end
            end
        end
        if vx ~= nil and spd > mv_min and heading_ok then
            local vel_yaw = math.deg(math.atan2(vy, vx))
            local raw_diff = normalize_yaw(vel_yaw - eye0)
            local abs_diff = math.abs(raw_diff)
            local sd = 0
            if abs_diff >= 10 and abs_diff <= 162 then
                sd = raw_diff > 0 and 1 or -1
            elseif abs_diff > 162 then
                local p2 = simtime_get(player, 2)
                if p2 and (p2.vx ~= 0 or p2.vy ~= 0) then
                    local d0 = math.deg(math.atan2(p2.vy, p2.vx))
                    local turn = normalize_yaw(vel_yaw - d0)
                    if math.abs(turn) >= 1.5 then sd = turn > 0 and 1 or -1 end
                end
                if sd == 0 then sd = player_freestand(player) end
                if sd == 0 then sd = ss_best_side(player, state(player)) or -1 end
            end
            if sd ~= 0 then
                local st_lim = AA_STATE_MAX_DELTA[ST.aa_state[player] or "run"] or 58
                local move_amp = clamp(math.max(max_angle(player), st_lim), 38, st_lim)
                local mv_conf = on_gnd and 88 or math.floor(80 * clamp(1 - (spd - 150)/300, 0.45, 1))
                local force_shoot_mv = on_gnd and (spd < 250) or false
                return { yaw=normalize_yaw(eye0 + sd * move_amp), side=sd, angle=move_amp,
                         confidence=mv_conf,
                         source="move_yaw", force_shoot=force_shoot_mv, meas=true,
                         force_body=head_hidden or nil,
                         hitbox=(head_hidden and C.HITBOX_STOMACH or "Head") }
            end
        end
    end

    local instant = get_instant_head_guided(player)
    if instant then if _air_fast then instant.force_shoot = false end return instant end

    local lock = ST.resolver_lock[player]
    if lock then
        local st_now = ST.aa_state[player] or "stand"
        if st_now == "jump" or st_now == "duck jump" then ST.resolver_lock[player] = nil
        else
            local age = globals.tickcount() - (lock.tick or 0)
            local cur_eye = entity.get_prop(player, "m_angEyeAngles[1]") or 0
            local eye_delta = math.abs(normalize_yaw(cur_eye - (lock.eye_at_lock or cur_eye)))
            local yaw_err = math.abs(normalize_yaw((lock.yaw or 0) - cur_eye))
            local ds = get_desync_resolution(player)
            local side_ok = (ds == nil) or (ds == lock.side)
            if age < C.RESOLVER_LOCK_TICKS and (lock.confidence or 0) >= 80 and (lock.angle or 0) >= 25
               and eye_delta < 40 and yaw_err < 20 and lock.state == st_now and side_ok then
                return {yaw=lock.yaw, side=lock.side, angle=lock.angle, confidence=lock.confidence, source="ST.resolver_lock"} end
            ST.resolver_lock[player] = nil
        end
    end

    local lc = lc_pre
    local state_idx = state(player)
    local layer = anim_layer_resolve(player)
    local anim_max = max_angle(player)
    local confidence = get_confidence_engine(player)
    local desync_side, desync_delta = get_desync_resolution(player)
    local jitter_side, jitter_conf, jitter_ang = get_jitter_resolution(player)
    local bf_side, bf_angle, bf_conf = get_adaptive_bruteforce(player, layer.side, layer.angle)
    local fs_side = player_freestand(player)
    local lby_near, lby_ticks, lby_side = get_lby_prediction(player)
    local _, jitter_flip = get_yaw_accel(player)
    local wall_fs = wall_freestand(player)
    local sh_angle, sh_conf = get_safe_head_resolution(player)
    local base_yaw = entity.get_prop(player, "m_angEyeAngles[1]") or pm.last_yaw or 0
    local fake_limit = get_fake_limit(player)
    local eye_aligned, real_eye_now, real_lby_now, eye_lby_delta = check_eye_lby_aligned(player)
    if (ST.hard_recent(player, 4) or def_pitch)
       and (not desync_side or (desync_delta or 0) < 8) then
        local mside_h, mamp_h = measured_desync(player)
        if not (mside_h and mamp_h >= C.MEAS_MIN_DEG) then
            return defensive_result(player, real_eye_now, "defensive_aa_hard") end
    end

    local best_by_source = {}
    if not head_hidden and sh_angle ~= nil and math.abs(sh_angle) >= C.PP11_AMP_MIN_DEG
       and sh_conf >= C.SAFE_HEAD_CONF_THRESHOLD then
        local clamped = clamp(sh_angle, -fake_limit, fake_limit)
        local side = clamped > 0 and 1 or -1
        local angle = math.min(math.abs(clamped), anim_max)
        best_by_source["safe_head"] = { side=side, angle=angle,
            yaw=normalize_yaw(base_yaw + side*angle), confidence=math.min(100, 50 + sh_conf*0.5),
            source="safe_head", weight=1.2*(sh_conf/100) }
    end
    if lby_near and lby_side and lby_side ~= 0 then
        local la = anim_max
        best_by_source["lby"] = { side=lby_side, angle=la, yaw=normalize_yaw(base_yaw + lby_side*la),
            confidence=math.floor(60 + math.min(40, math.abs(lby_ticks or 0)*5)), source="lby", weight=2.0 }
    end
    if jitter_side and jitter_side ~= 0 and jitter_conf > 35 then
        local ja = clamp(jitter_ang and jitter_ang > 0 and jitter_ang or anim_max, 25, anim_max)
        local js = jitter_side
        best_by_source["jitter"] = { side=js, angle=ja, yaw=normalize_yaw(base_yaw + js*ja),
            confidence=jitter_conf, source="jitter", weight=1.8*(jitter_conf/100) }
    end
    if desync_side and confidence >= C.CONF_LOW then
        local da = clamp(desync_delta or layer.angle, 0, fake_limit)
        best_by_source["desync"] = { side=desync_side, angle=da, yaw=normalize_yaw(base_yaw + desync_side*da),
            confidence=confidence, source="desync", weight=1.5*(confidence/100) }
    end
    local mc = get_moving_resolver(player)
    if mc and (lc.is_frozen or layer.frozen) then
        local c2 = (lc.confidence_penalty and lc.confidence_penalty > 0) and math.max(55, 85 - lc.confidence_penalty) or 85
        best_by_source["moving_cache"] = { side=mc.side, angle=mc.angle, yaw=mc.yaw, confidence=c2,
            source="moving_cache", weight=1.3 }
    end
    local aa_now = ST.aa_state[player] or "stand"
    if wall_fs ~= 0 and not (aa_now == "run" or aa_now == "slow walk" or aa_now == "duck move") then
        local wa = layer.angle or 35
        best_by_source["wall_freestand"] = { side=wall_fs, angle=wa, yaw=normalize_yaw(base_yaw + wall_fs*wa),
            confidence=55, source="wall_freestand", weight=0.6 }
    end
    local ls = ss_best_side(player, state_idx) or layer.side
    local lfs = (fs_side ~= 0) and afb_check(player, fs_side, ls) or ls
    if layer.is_fake and (layer.angle or 0) > 0 then
        best_by_source["layer"] = { side=lfs, angle=layer.angle, yaw=normalize_yaw(base_yaw + lfs*layer.angle),
            confidence=math.max(confidence, 76), source="layer", weight=2.1*(math.max(confidence, 76)/100) }
    end
    do
        local ba = (bf_angle and bf_angle >= 28) and bf_angle or (get_best_angle_bucket(player, state_idx) or anim_max)
        if not ba or ba <= 0 then ba = anim_max end
        best_by_source["bruteforce"] = { side=bf_side, angle=ba, yaw=normalize_yaw(base_yaw + bf_side*ba),
            confidence=math.max(bf_conf or 62, 62), source="bruteforce", weight=1.5*(math.max(bf_conf or 62, 62)/100) }
    end
    if ST.lby_broke[player] and globals.tickcount() - ST.lby_broke[player] < 10 then
        local bs = ST.lby_broke_side[player] or 1
        local ba = math.min(ST.lby_broke_ang[player] or 58, fake_limit > 0 and fake_limit or 58)
        ba = clamp(ba, 5, anim_max)
        best_by_source["lby_break"] = { side=bs, angle=ba, yaw=normalize_yaw(base_yaw + bs*ba),
            confidence=90, source="lby_break", weight=2.2 }
    end

    if ST.jitter_data_v[player] and ST.jitter_data_v[player].pattern == "alternating" then
        local ddj = ST.desync_data[player]
        local amp = ddj and math.abs(ddj.desync_delta or 0) or 0
        if amp >= C.LEGIT_AA_MIN_ANGLE and amp < C.LEGIT_AA_JITTER_MAX then
            local la2 = clamp(amp, C.LEGIT_AA_MIN_ANGLE, C.LEGIT_AA_MAX_ANGLE)
            for _, k in ipairs({"jitter", "desync"}) do
                local b2 = best_by_source[k]
                if b2 then b2.angle = math.min(b2.angle, la2); b2.yaw = normalize_yaw(base_yaw + b2.side*b2.angle) end
            end
        end
    end
    if ui.get(head_priority) then
        for _, k in ipairs({"safe_head", "lby"}) do
            if best_by_source[k] then best_by_source[k].weight = best_by_source[k].weight*1.3 end
        end
    end

    local vl, vr = 0, 0
    for _, cand in pairs(best_by_source) do
        local vote = (cand.weight or 0)*(0.5 + ((cand.confidence or 50)/100)*0.5)
        if cand.side == 1 then vl = vl + vote elseif cand.side == -1 then vr = vr + vote end
    end
    local pv = ST.vote_side[player]
    if pv == 1 then vl = vl*C.VOTE_STICKY elseif pv == -1 then vr = vr*C.VOTE_STICKY end
    local final_side = vl > vr and 1 or (vr > vl and -1 or (layer.side ~= 0 and layer.side or (pm.last_side or 1)))
    ST.vote_side[player] = final_side
    local vote_total = vl + vr
    local margin = vote_total > 0 and math.abs(vl-vr)/vote_total or 0
    local final_conf = clamp(math.floor(35 + 60*margin), 5, 95)

    local winner, best_score = nil, -math.huge
    for _, cand in pairs(best_by_source) do
        if cand.side == final_side then
            local s = (cand.weight or 0)*0.65 + ((cand.confidence or 0)/100)*0.35
            if s > best_score then winner, best_score = cand, s end
        end
    end
    if not winner then
        winner = { yaw=normalize_yaw(base_yaw + final_side*38), side=final_side, angle=38,
                   confidence=55, source="emergency_fallback" } end

    if BRUTE.bullet_ui and ui.get(BRUTE.bullet_ui) and not lc.is_frozen then
        local cands = {}
        local function add(side, angle)
            if not side or side == 0 or not angle or angle < 3 then return end
            for _, c in ipairs(cands) do
                if c.side == side and math.abs(c.angle - angle) < 4 then return end
            end
            cands[#cands+1] = { side=side, angle=angle }
        end
        add(winner.side, winner.angle)
        local rdev = pp11_raw_dev(player)
        add(pp11_raw_side(player), rdev and math.min(math.abs(rdev), 58) or 0)
        add(-final_side, 58); add(final_side, 58); add(final_side, 38)
        local picked = BRUTE.pick_by_bullet(player, cands)
        if picked then winner = picked; final_conf = math.max(final_conf, 88) end
    end

    if head_hidden and not ssg_wants_head_only(player) then
        winner.force_body, winner.hitbox = true, C.HITBOX_STOMACH
    end

    local dd_meas = ST.desync_data[player]
    local measured = dd_meas and math.abs(dd_meas.desync_delta or 0) or 0
    local real_max = (measured < 5 and eye_lby_delta < 3 and aligned_full_ok(player))
        and 0 or math.max(5, math.min(58, math.max(fake_limit, measured + 5, anim_max)))
    if winner.source and winner.source:find("move_yaw") then
        real_max = math.max(real_max, 58)
    end
    if winner.side and winner.side ~= 0 and real_max > 0 then
        if (winner.angle or 0) > real_max then
            winner.angle = real_max; winner.yaw = normalize_yaw(base_yaw + winner.side*winner.angle) end
        if (winner.angle or 0) <= 0 then
            winner.angle = math.min(38, real_max); winner.yaw = normalize_yaw(base_yaw + winner.side*winner.angle) end
    end
    if eye_aligned and not def_pitch then
        winner.side, winner.angle, winner.yaw = 0, 0, real_eye_now
        winner.source = (winner.source or "?") .. "_aligned"
        winner.confidence = math.max(winner.confidence or 50, 85)
    end
    winner.confidence = clamp((winner.confidence or 50)*0.7 + final_conf*0.3, 5, 97)
    if winner.force_shoot and final_conf < 60 then winner.force_shoot = false end

    if winner.source == "move_yaw" or winner.source == "desync_measured" then
        update_moving_cache(player, winner.side, winner.angle, winner.yaw)
    end
    update_flip_history(player, winner.side or 1)

    local st_lock = ST.aa_state[player] or "stand"
    if st_lock ~= "jump" and st_lock ~= "duck jump" and winner.source ~= "ST.resolver_lock" then
        ST.resolver_lock[player] = { side=winner.side, angle=winner.angle, yaw=winner.yaw,
            confidence=winner.confidence, tick=globals.tickcount(), eye_at_lock=base_yaw, state=st_lock }
    elseif st_lock == "jump" or st_lock == "duck jump" then ST.resolver_lock[player] = nil end

    local real_eye = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    local yaw_error = math.abs(normalize_yaw((winner.yaw or 0) - real_eye))
    local src = winner.source or "unknown"
    local tol = 120
    if src:find("instant_head") or src:find("move_yaw")
       or src:find("bullet_pick") or src == "emergency_fallback" then tol = 160 end
    if yaw_error > tol then
        winner.angle = clamp(winner.angle or 58, 28, 58)
        winner.yaw = normalize_yaw(real_eye + (winner.side or 1) * winner.angle)
    end
    if _air_fast then winner.force_shoot = false end
    return { yaw=winner.yaw, side=winner.side, angle=winner.angle, confidence=winner.confidence or 50,
        source=src, force_shoot=winner.force_shoot,
        is_instant_shot=(src:find("instant_head") ~= nil), is_safe_head=(src == "safe_head"),
        is_jitter=(src == "jitter"), force_body=winner.force_body,
        hitbox=winner.hitbox }
end

-- 32b ── anti-drift: un rezultat per net update
local function resolve_player(player, pm)
    local sim = entity.get_prop(player, "m_flSimulationTime") or 0
    local c = ST.last_result[player]
    if c and sim ~= 0 and ST.last_result_sim[player] == sim
       and (globals.tickcount() - (c.tick or 0)) <= 12 then
        local copy = {}
        for k, v in pairs(c) do copy[k] = v end
        copy.tick = globals.tickcount()
        return copy
    end
    local r = resolve_player_inner(player, pm)
    if type(r) == "table" then
        r.tick = globals.tickcount()
        ST.last_result[player] = r
        ST.last_result_sim[player] = sim
    end
    return r
end

-- 33 ── plist helpers
local function reset_all_plist()
    for player = 1, globals.maxplayers() do
        if entity.is_alive(player) and BRUTE.restore then BRUTE.restore(player) end end
end
local function reset_plist(player)
    if last_plist_reset[player] == globals.tickcount() then return end
    last_plist_reset[player] = globals.tickcount()
end

-- 34 ── process tick
local function process_player_tick(player, weapon)
    if not entity.is_alive(player) then ST.purge_cache(player); return end
    if not ST.player_memory[player] then
        ST.player_memory[player] = {misses=0, last_yaw=entity.get_prop(player, "m_angEyeAngles[1]") or 0, last_side=1} end
    if not ST.player_animation_data[player] then
        ST.player_animation_data[player] = {last_cy6=0, freeze_ticks=0, fake_move_ticks=0} end
    local pm = ST.player_memory[player]
    local sim = entity.get_prop(player, "m_flSimulationTime")
    local tick = globals.tickcount()
    local vx, vy = entity.get_prop(player, "m_vecVelocity")
    simtime_push(player, sim, tick, vx, vy)
    pp_hist_push(player)
    update_pitch_history(player)
    update_aa_state(player)
    local sc_old = ST.shot_context[player]
    if sc_old and (tick - (sc_old.tick or 0)) > 8 then ST.shot_context[player] = nil end
    local na_eye = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    local na_lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    if not ST.network_angle_history[player] then
        ST.network_angle_history[player] = {head=1, size=0, max=32, buf={}} end
    local h = ST.network_angle_history[player]
    local na_sim = entity.get_prop(player, "m_flSimulationTime")
    if h.last_sim ~= na_sim then
        local prev = h.buf[(h.head - 2 + h.max) % h.max + 1]
        if prev then
            local lby_d = math.abs(normalize_yaw(na_lby - prev.lby))
            local eye_d = math.abs(normalize_yaw(na_eye - prev.yaw))
            local diff_now = math.abs(normalize_yaw(na_lby - na_eye))
            if lby_d > 35 and eye_d < 10 and diff_now > 20 then
                ST.lby_broke[player] = tick
                ST.lby_broke_side[player] = normalize_yaw(na_lby - na_eye) > 0 and 1 or -1
                ST.lby_broke_ang[player] = clamp(diff_now, 5, 58)
            end
            if eye_d > 2 then ST.eye_change_tick[player] = tick end
        end
        h.buf[h.head] = {yaw=na_eye, lby=na_lby, time=globals.curtime()}
        h.head = (h.head % h.max) + 1
        if h.size < h.max then h.size = h.size + 1 end
        h.last_sim = na_sim
    end
    local lvx, lvy, lvz = entity.get_origin(player)
    if lvx then ST.last_valid_pos[player] = vec(lvx, lvy, lvz) end
    ST.last_valid_vel[player] = get_velocity_vector(player)
    ST.last_valid_tick[player] = tick
    init_desync_data(player); init_jitter_data_v(player); init_confidence_data_v(player)
    init_bruteforce_data(player); init_safe_head_data(player); init_tickbase_data(player)
    if ST.last_resolve_tick[player] ~= tick then
        ST.last_resolve_tick[player] = tick
        store_animation_record(player)
        update_tickbase_data(player)
        pcall(update_desync_data, player)
        update_jitter_data_v(player)
        update_confidence_engine(player)
        track_side_flip(player)
        update_lby_timing(player)
        update_yaw_accel(player, na_eye)
        do
            local bd0, pd0 = pp11_body_delta(player), pp11_raw_dev(player)
            if bd0 and pd0 and math.abs(bd0) >= 10 and math.abs(pd0) >= 10 then
                ST.pp11_sign_n = (ST.pp11_sign_n or 0) + 1
                if (bd0 > 0) == (pd0 > 0) then
                    ST.pp11_sign_agree = (ST.pp11_sign_agree or 0) + 1 end
                if ST.pp11_sign_n >= 60 then
                    local ratio = (ST.pp11_sign_agree or 0) / ST.pp11_sign_n
                    local want = BRUTE.M.sign or 1
                    if ratio <= 0.20 then want = -1 elseif ratio >= 0.80 then want = 1 end
                    if want ~= (BRUTE.M.sign or 1) then
                        BRUTE.SS.cal, BRUTE.SS.p, BRUTE.SS.n = want, 0, 0
                        BRUTE.m_update()
                        client.log(string.format("[PP11-SGN] semn pp11 -> %s (acord %.0f%%, %d probe)",
                            want == -1 and "INVERSAT" or "NORMAL", ratio*100, ST.pp11_sign_n))
                        for pl in pairs(ST.last_result) do ST.last_result[pl] = nil end
                    end
                    ST.pp11_sign_agree = math.floor((ST.pp11_sign_agree or 0)/2)
                    ST.pp11_sign_n = math.floor(ST.pp11_sign_n/2)
                end
            end
        end
    end
    local crouch_data = handle_crouch_safe_head(player)
    if not (ui.get(zeus_resolver) and is_melee_weapon(weapon)) then
        local ok, result = pcall(resolve_player, player, pm)
        if not ok then
            ST._rerr_n = (ST._rerr_n or 0) + 1
            if ST._rerr_n <= 5 then client.log("[RES-ERR] P" .. tostring(player) .. ": " .. tostring(result)) end
            result = nil
        end
        if type(result) ~= "table" then result = nil end
        if not result then
            local eye = entity.get_prop(player, "m_angEyeAngles[1]") or 0
            local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
            local aligned = math.abs(normalize_yaw(eye - lby)) < 3 and aligned_full_ok(player)
            local fb_side = ss_best_side(player, state(player)) or player_freestand(player) or pm.last_side or 1
            if fb_side == 0 then fb_side = 1 end
            local fb_ang = aligned and 0 or (AA_STATE_MAX_DELTA[ST.aa_state[player] or "stand"] or 58)
            result = { yaw=normalize_yaw(eye + fb_side * fb_ang), side=aligned and 0 or fb_side, angle=fb_ang,
                confidence=aligned and 95 or 60,
                source=aligned and "emergency_aligned" or "bruteforce_fallback", force_shoot=false, hitbox="Head" }
        end
        ST.resolver_seed[player] = { side=result.side or 0, angle=math.abs(result.angle or 0),
            confidence=result.confidence or 0, source=result.source or "resolved", tick=tick,
            force_body=result.force_body and true or false, meas=result.meas and true or false }
        if type(sim) == "number" then ST.thrash[player] = { sim = sim, res = result } end
        if crouch_data and crouch_data.force_body then
            result.force_body = true
            result.hitbox = crouch_data.hitbox or result.hitbox
            if crouch_data.force_shoot then result.force_shoot, result.crouch_fix = true, true end
        end
        if is_using_doubletap(player) or ST.is_hard_shift(player) then ST.unsafe[player] = tick end
        if (crouch_data and crouch_data.force_body) or result.force_body then ST.baim_req[player] = tick end
        pm.last_yaw, pm.last_side = result.yaw, result.side
        ST.last_applied[player] = { side=result.side or 1, angle=result.angle or 35, tick=tick, yaw=result.yaw or 0 }
        ST.shot_context[player] = { yaw=result.yaw, side=result.side, angle=result.angle,
            confidence=result.confidence or 50, tick=tick, is_safe_head=result.is_safe_head,
            crouch_fix=result.crouch_fix, source=result.source or "resolved",
            is_instant_head=result.is_instant_head, force_body=result.force_body }
    end
end

-- 35 ── events
client.set_event_callback("setup_command", function()
    frame_counter = frame_counter + 1
    if not ui.get(enable_resolver) then
        if frame_counter % 10 == 0 then reset_all_plist() end
        return
    end
    local players = get_entities()
    if not entity.get_local_player() then return end
    local weapon = entity.get_player_weapon(entity.get_local_player())
    if ui.get(threat_priority) and frame_counter % 5 == 0 then
        table.sort(players, function(a, b) return get_threat_level(a) > get_threat_level(b) end) end
    for _, player in ipairs(players) do
        reset_plist(player)
        local ok, err = pcall(process_player_tick, player, weapon)
        if not ok then
            ST.entity_cache[player] = nil
            ST._perr_n = (ST._perr_n or 0) + 1
            if ST._perr_n <= 5 then client.log("[TICK-ERR] P" .. tostring(player) .. ": " .. tostring(err)) end
        end
    end
end)
local function clear_player(player)
    if not player or player == 0 then return end
    for _, k in ipairs({"resolver_lock","last_resolve_tick","player_memory","player_animation_data",
        "simtime_history","layer_history","shot_context","last_moving_cache","yaw_accel_history",
        "lby_update_cache","side_flip_history","angle_hit_data","side_score","fs_bait",
        "last_valid_pos","last_valid_vel","last_valid_tick","animation_records","bone_matrix_cache",
        "pose_parameter_cache","tickbase_data","desync_data","jitter_data_v","confidence_data",
        "bruteforce_data","safe_head_data","entity_cache","crouch_cache","network_angle_history",
        "lby_broke","lby_broke_side","lby_broke_ang","flip_history","aa_state","break_lc","baim_req","unsafe",
        "hard_tick","pp_hist","thrash","break_lc_until","vote_side","last_result","last_result_sim",
        "lby_change_tick","eye_change_tick","aligned_miss_n",
        "pitch_hist","clean_pp11","anim_interp","sgn_player","dt_burst","on_shot"}) do
        ST[k][player] = nil
    end
    _pfs_cache[player] = nil
    ST.purge_cache(player)
end
client.set_event_callback("player_disconnect", function(e) clear_player(client.userid_to_entindex(e.userid)) end)
client.set_event_callback("round_end", function()
    for player in pairs(ST.player_memory) do if not entity.is_alive(player) then ST.player_memory[player] = nil end end
    ST.last_resolve_tick = {}
end)
local function full_reset()
    reset_all_plist()
    for _, k in ipairs({"player_memory","player_animation_data","simtime_history","layer_history",
        "shot_context","last_applied","resolver_seed","angle_hit_data","last_valid_pos","last_valid_vel",
        "last_valid_tick","resolver_lock","lby_update_cache","side_flip_history","side_score","fs_bait",
        "animation_records","bone_matrix_cache","pose_parameter_cache","tickbase_data","desync_data",
        "jitter_data_v","confidence_data","bruteforce_data","safe_head_data","last_resolve_tick",
        "cache_session","network_angle_history","lby_broke","lby_broke_side","lby_broke_ang","flip_history","aa_state",
        "break_lc","instant_block","last_moving_cache","yaw_accel_history","entity_cache",
        "cache_timestamp","cache_data","crouch_cache","baim_req","unsafe","hard_tick","vote_side",
        "pp_hist","thrash","break_lc_until","last_result","last_result_sim",
        "lby_change_tick","eye_change_tick","aligned_miss_n",
        "pitch_hist","clean_pp11","anim_interp","sgn_player","dt_burst","on_shot"}) do ST[k] = {} end
    wall_data, last_plist_reset = {}, {}
    cached_pr, cached_pr_tick = nil, 0
    ST.pp11_sign_agree, ST.pp11_sign_n = 0, 0
end
client.set_event_callback("net_disconnect", full_reset)
client.set_event_callback("level_init", function()
    session_id = session_id + 1
    full_reset()
    client.delay_call(3, test_ffi)
end)
client.set_event_callback("round_start", function()
    for _, states in pairs(ST.side_score) do
        for _, sides in pairs(states) do
            for _, s in pairs(sides) do s.h, s.m = (s.h or 0)*C.ROUND_RESET_DECAY_HIT, (s.m or 0)*C.ROUND_RESET_DECAY_MISS end
        end
    end
    for _, data in pairs(ST.angle_hit_data) do
        for _, buckets in pairs(data) do
            for _, b in pairs(buckets) do b.h, b.m = (b.h or 0)*C.ROUND_RESET_DECAY_HIT, (b.m or 0)*C.ROUND_RESET_DECAY_MISS end
        end
    end
    for player = 1, globals.maxplayers() do
        if entity.is_alive(player) or entity.is_dormant(player) then
            for _, k in ipairs({"simtime_history","tickbase_data","safe_head_data","animation_records",
                "bone_matrix_cache","pose_parameter_cache","desync_data","jitter_data_v","confidence_data",
                "entity_cache","flip_history","break_lc","pp_hist","thrash","last_result","last_result_sim",
                "instant_block","aligned_miss_n","pitch_hist","clean_pp11","anim_interp","dt_burst","on_shot"}) do
                ST[k][player] = nil end
            _pfs_cache[player] = nil
            if ST.player_memory[player] then ST.player_memory[player].misses = 0 end
            local bf = ST.bruteforce_data[player]
            if bf then
                bf.log_p_left = bf.log_p_left*C.ROUND_RESET_BF_LOG_DECAY
                bf.log_p_right = bf.log_p_right*C.ROUND_RESET_BF_LOG_DECAY
                while #bf.hit_hist > 16 do table.remove(bf.hit_hist) end
                while #bf.miss_hist > 16 do table.remove(bf.miss_hist) end
                for _, sc in pairs(bf.angle_scores) do
                    sc.hits, sc.misses = math.floor(sc.hits*C.ROUND_RESET_DECAY_HIT), math.floor(sc.misses*C.ROUND_RESET_DECAY_MISS) end
                if bf.system_hitrate then
                    for _, sys in pairs(bf.system_hitrate) do
                        sys.hits, sys.misses = math.floor(sys.hits*C.ROUND_RESET_SYS_DECAY), math.floor(sys.misses*C.ROUND_RESET_SYS_DECAY)
                        sys.rate = sys.rate*(1 - C.ROUND_RESET_SYS_RATE_BLEND) + 0.5*C.ROUND_RESET_SYS_RATE_BLEND
                    end
                end
                local tot = #bf.hit_hist + #bf.miss_hist
                bf.confidence = tot > 0 and ((#bf.hit_hist+2)/(tot+4))*100 or C.ROUND_RESET_BF_CONF_RESET
            end
        end
    end
    for _, k in ipairs({"resolver_lock","last_applied","resolver_seed","last_resolve_tick",
        "simtime_history","layer_history","yaw_accel_history","side_flip_history","fs_bait",
        "last_moving_cache","crouch_cache","lby_broke","lby_broke_side","lby_broke_ang","bone_matrix_cache","pose_parameter_cache"}) do
        ST[k] = {} end
    wall_data, _pfs_cache, last_plist_reset = {}, {}, {}
end)
client.log("[RES] v10.0 incarcat | Pure Deterministic Resolver | 3D Freestand + Air-Strafe Turn + SSG08 Head")

-- 36 ── BRUTE
do
    local ANGLES = { 58, 38, 29 }
    local NSTAGE = 6
    BRUTE.clean = true
    BRUTE.STALL_MAX, BRUTE.STALL_LAG, BRUTE.SEED_TRUST_MIN = 3, 2, 0.55
    BRUTE.T, BRUTE.T0 = { h=0, n=0, skip=0, said=false }, { h=0, n=0 }
    BRUTE.SS = { p=0, n=0, cal=1 }
    BRUTE.ss_mode_ui = ui.new_combobox("RAGE", "Other", "Min resolver: semn seed detector", {"Auto","Normal","Inversat"})
    BRUTE.seed_sign = function()
        local m = ui.get(BRUTE.ss_mode_ui)
        if m == "Normal" then return 1 elseif m == "Inversat" then return -1 end
        return 1
    end
    BRUTE.sgn_for = function(src, p)
        if p and ST.sgn_player[p] and src and ST.sgn_player[p][src] then
            local psg = ST.sgn_player[p][src]
            if ((psg.agree or 0) + (psg.dis or 0)) >= 3 then return psg.sign or 1 end
        end
        local sg = src and ST.sgn[src]
        if not sg then return 1 end
        if ((sg.agree or 0) + (sg.dis or 0)) < 10 then return 1 end
        return sg.sign or 1
    end
    BRUTE.ss_vote = function(vote)
        local S = BRUTE.SS
        if vote > 0 then S.p = S.p + 1 else S.n = S.n + 1 end
        local tot = S.p + S.n
        if tot >= 60 then S.p, S.n = math.floor(S.p/2), math.floor(S.n/2); tot = S.p + S.n end
        if tot >= 12 then
            local want = S.cal
            if S.cal == 1 and S.n >= 0.75*tot then want = -1
            elseif S.cal == -1 and S.p >= 0.75*tot then want = 1 end
            if want ~= S.cal then
                client.log(string.format("[SIDE] semn seed -> %s automat (normal=%d inversat=%d).",
                    want == -1 and "INVERSAT" or "NORMAL", S.p, S.n))
                S.cal, S.p, S.n = want, 0, 0
                BRUTE.m_update()
            end
        end
    end
    BRUTE.base_result = function(hit)
        local B0 = BRUTE.T0
        B0.n = B0.n + 1
        if hit then B0.h = B0.h + 1 end
        if B0.n >= 40 then B0.h, B0.n = math.floor(B0.h/2), math.floor(B0.n/2) end
    end
    BRUTE.AMP = { max={h=0,n=0}, det={h=0,n=0} }
    BRUTE._amp, BRUTE._ap, BRUTE._sf = {}, {}, {}
    BRUTE.amp_pick = function(p, seed)
        local now = globals.tickcount()
        local c = BRUTE._ap[p]
        if c and (now - c.tick) <= 128 then return c.mode, c.ab end
        local det = math.min(math.abs(seed.angle or 0), ANGLES[1])
        local mode, ab = "det", false
        if det < ANGLES[1] - 2 then
            ab = true
            local A = BRUTE.AMP
            if A.max.n < 6 or A.det.n < 6 then mode = (A.det.n <= A.max.n) and "det" or "max"
            elseif math.random() < 0.15 then mode = math.random() < 0.5 and "det" or "max"
            else mode = (A.det.h/A.det.n > A.max.h/A.max.n) and "det" or "max" end
        end
        BRUTE._ap[p] = { tick=now, mode=mode, ab=ab }
        return mode, ab
    end
    BRUTE.amp_result = function(mode, hit)
        local X = BRUTE.AMP[mode]
        if not X then return end
        X.n = X.n + 1
        if hit then X.h = X.h + 1 end
        if X.n >= 60 then X.h, X.n = math.floor(X.h/2), math.floor(X.n/2) end
    end
    BRUTE.SRC, BRUTE._sk = {}, {}
    BRUTE.WEAK = { wall_freestand=true, jitter=true, network_angle=true, bruteforce=true }
    BRUTE.src_ok = function(p, src)
        if src and (src:find("aligned") or src:find("move_yaw") or src:find("desync_measured")) then return true end
        if src and src:find("pp11") then
            local r0 = BRUTE.SRC[src]
            if not r0 or r0.n < 12 then return true end
            if (r0.h/r0.n) < 0.40 then
                r0.skip = (r0.skip or 0) + 1
                return (r0.skip % 3 == 0)
            end
            return true
        end
        local now = globals.tickcount()
        local c = BRUTE._sk[p]
        if c and c.src == src and (now - c.tick) <= 128 then return c.ok end
        local r = BRUTE.SRC[src]
        if not r then r = {h=0, n=0, skip=0}; BRUTE.SRC[src] = r end
        local weak = BRUTE.WEAK[src] == true
        local ok
        if r.n < 8 then ok = true
        else ok = (r.h/r.n) >= (weak and 0.55 or 0.40) end
        if not ok then r.skip = r.skip + 1; if r.skip % 3 == 0 then ok = true end end
        BRUTE._sk[p] = { src=src, tick=now, ok=ok }
        return ok
    end
    BRUTE.src_result = function(src, hit)
        if not src then return end
        local r = BRUTE.SRC[src]
        if not r then r = {h=0, n=0, skip=0}; BRUTE.SRC[src] = r end
        r.n = r.n + 1
        if hit then r.h = r.h + 1 end
        if r.n >= 40 then r.h, r.n = math.floor(r.h/2), math.floor(r.n/2) end
    end
    BRUTE.seed_trusted = function()
        local T = BRUTE.T
        if T.n < 6 then return true end
        return (T.h/T.n >= BRUTE.SEED_TRUST_MIN) or T.probe == true
    end
    BRUTE.seed_result = function(hit, soft)
        local T = BRUTE.T
        T.n = T.n + 1
        if hit then T.h = T.h + (soft and 0.5 or 1) end
        if T.n >= 40 then T.h, T.n = math.floor(T.h/2), math.floor(T.n/2) end
        if T.n == 6 and not T.said then
            T.said = true
            client.log(string.format("[SEED] detector: %d shot-uri, %.1f hit => %s",
                T.n, T.h, (T.h/T.n >= BRUTE.SEED_TRUST_MIN) and "INCREDERE" or "FARA INCREDERE"))
        end
    end
    BRUTE.dup29 = function(b, k)
        return (k >= 5) and b.snap ~= nil and (b.snap.spd or 0) >= 100 and b.snap.grp ~= "stand"
    end
    BRUTE.M = { agree=0, dis=0, sign=1, enabled=false, dev_min=0.10, gen=0 }
    function BRUTE.m_update()
        local M = BRUTE.M
        local ns = (BRUTE.SS.cal == -1) and -1 or 1
        if ns ~= M.sign then M.gen = (M.gen or 0) + 1 end
        M.sign = ns
        M.enabled = (M.agree + M.dis) >= 4
    end
    BRUTE.pp11_dev = function(p)
        local v = entity.get_prop(p, "m_flPoseParameter", 11)
        if type(v) ~= "number" or v < 0 or v > 1 then return nil end
        return (v - 0.5)*C.PP11_SCALE*BRUTE.M.sign
    end
    BRUTE.pp11_side = function(p)
        local d = BRUTE.pp11_dev(p)
        if not d or math.abs(d) < C.PP11_SIDE_MIN_DEG then return 0 end
        return d > 0 and 1 or -1
    end
    BRUTE.pp11amp_ui = ui.new_checkbox("RAGE", "Other", "Min resolver: amplitudine din pose param 11")
    ui.set(BRUTE.pp11amp_ui, true)
    BRUTE.pp11_angle = function(p)
        local v = entity.get_prop(p, "m_flPoseParameter", 11)
        if not v then return 0 end
        local a = math.abs(v - 0.5)*C.PP11_SCALE
        if a < C.PP11_AMP_MIN_DEG then return 0 end
        if a > 58 then a = 58 end
        return math.floor(a + 0.5)
    end
    BRUTE.bullet_ui = ui.new_checkbox("RAGE", "Other", "Min resolver: trace_bullet experimental (poate citi modelul vechi)")
    ui.set(BRUTE.bullet_ui, false)
    local function head_at_delta(p, delta)
        local ox, oy, oz = entity.get_origin(p)
        local hx, hy, hz = entity.hitbox_position(p, C.HITBOX_HEAD)
        if not ox or not hx then return nil end
        local dx, dy = hx - ox, hy - oy
        local r = delta*C.DEG2RAD
        local c, s = math.cos(r), math.sin(r)
        return ox + dx*c - dy*s, oy + dx*s + dy*c, hz
    end
    BRUTE.pick_by_bullet = function(p, cands)
        local me = entity.get_local_player()
        local ex, ey, ez = client.eye_position()
        if not me or not ex or #cands == 0 then return nil end
        local best, best_dmg, best_ang = nil, 0, nil
        for _, c in ipairs(cands) do
            local ang = (c.side == 0) and 0 or c.side*math.abs(c.angle)
            local cur = (BRUTE.cur_applied and BRUTE.cur_applied(p)) or 0
            local hx, hy, hz = head_at_delta(p, ang - cur)
            if hx then
                local ent, dmg = client.trace_bullet(me, ex, ey, ez, hx, hy, hz, false)
                if ent == p and (dmg or 0) > best_dmg then best, best_dmg, best_ang = c, dmg, ang end
            end
        end
        if best then
            local base = entity.get_prop(p, "m_angEyeAngles[1]") or 0
            return { side=best.side, angle=math.abs(best_ang), yaw=normalize_yaw(base + best_ang),
                     confidence=92, source="bullet_pick", force_shoot=true, hitbox="Head" }
        end
        return nil
    end
    local B = {}
    BRUTE.B = B
    BRUTE.cur_applied = function(p) return B[p] and B[p].applied or 0 end
    local function group_of(p)
        local f = entity.get_prop(p, "m_fFlags") or 1
        local vx, vy = entity.get_prop(p, "m_vecVelocity")
        local spd = math.sqrt((vx or 0)^2 + (vy or 0)^2)
        if bit.band(f, FL_ONGROUND) == 0 then return "air" end
        if (entity.get_prop(p, "m_flDuckAmount") or 0) > 0.6 then return "duck" end
        if spd > 5 then return "move" end
        return "stand"
    end
    local function get(p)
        if not B[p] then B[p] = { g={}, order=nil, nhit=0, nfail=0, last_hit_stage=nil, filt=0, filt_lag=0 } end
        return B[p]
    end
    -- [v8.5.0] partea de baza per-tinta: invatat (ss_best_side) > ultimul hit confirmat > ultima parte
    local function base_side(p)
        local s = ss_best_side(p, state(p))
        if not s or s == 0 then
            local bf = ST.bruteforce_data[p]
            local h1 = bf and bf.hit_hist and bf.hit_hist[1]
            if h1 and (h1.side == 1 or h1.side == -1) then s = h1.side end
        end
        if not s or s == 0 then
            local fs = player_freestand(p)
            if fs and fs ~= 0 then s = fs end
        end
        if not s or s == 0 then
            local pmm = ST.player_memory[p]
            s = pmm and pmm.last_side
        end
        if not s or s == 0 then s = -1 end
        return s
    end
    local function build_order(p)
        local s = base_side(p)
        local sd = ST.resolver_seed[p]
        if sd and sd.tick and (globals.tickcount() - sd.tick) <= 8 and (sd.confidence or 0) >= 40
           and (sd.angle or 0) > 0 and (sd.side or 0) ~= 0 then
            if sd.meas then s = (sd.side > 0) and 1 or -1 end
        end
        local bb = B[p]
        if bb and bb.last_missed_ang and bb.last_missed_ang ~= 0 then
            s = (bb.last_missed_ang > 0) and -1 or 1
        elseif bb and bb.flip_first and not (sd and sd.meas and (sd.angle or 0) > 0) then
            s = -s
        end
        get(p).order_side = s
        local a1, a2, a3 = 58, 38, 29
        return { s*a1, -s*a1, s*a2, -s*a2, s*a3, -s*a3 }
    end
    local function skip_native(b, p)
        local sd = p and ST.resolver_seed[p]
        if sd and sd.tick and (globals.tickcount() - sd.tick) <= 2 and (sd.confidence or 0) >= 85 and sd.meas then
            return false
        end
        return (b.s0_consec_fail or 0) >= 2
    end
    local function gstate(p, grp)
        local b = get(p)
        if not b.g[grp] then
            local start = 0
            if b.last_hit_stage and b.last_hit_stage > 0 then start = b.last_hit_stage
            elseif b.search and b.search > 0 then start = b.search
            elseif skip_native(b, p) then start = 1
            elseif b.nhit == 0 and b.nfail == 0 then start = BRUTE.class_start(b, p) end
            b.g[grp] = { stage=start, hit=nil, misses=0, filt=0 }
            if start > 0 and not b.order then b.order = build_order(p) end
        end
        return b.g[grp]
    end
    local function state_cap(p)
        return AA_STATE_MAX_DELTA[ST.aa_state[p] or "stand"] or 58
    end
    local WEAK_SRC = { wall=true, network=true }
    local function angle_of(p, stage)
        local cap = state_cap(p)
        local flp = entity.get_prop(p, "m_fFlags") or 0
        if stage == 0 and bit.band(flp, FL_ONGROUND) ~= 0 and get_velocity(p) <= 30 then
            local dv = BRUTE.pp11_dev(p)
            local sd_pre = ST.resolver_seed[p]
            local is_def_pre = sd_pre and tostring(sd_pre.source or ""):find("defensive")
            if dv and math.abs(dv) < C.PP11_ALIGN_DEG and not is_def_pre and aligned_full_ok(p) then return 0 end
        end
        if stage == 0 then
            if not BRUTE.always_on() then return nil end
            local seed = ST.resolver_seed[p]
            local ssrc = seed and tostring(seed.source) or ""
            local direct_seed = ssrc:find("aligned") ~= nil
                or ssrc:find("move_yaw") ~= nil or ssrc:find("desync_measured") ~= nil
                or ssrc:find("on_shot") ~= nil or ssrc:find("lby_break") ~= nil
                or ssrc:find("jitter") ~= nil or ssrc:find("layer") ~= nil
            local seed_ok = seed and seed.tick and (globals.tickcount() - seed.tick) <= 4
                and (seed.confidence or 0) >= 65 and ssrc:sub(1, 9) ~= "emergency"
                and direct_seed and BRUTE.src_ok(p, ssrc)
            if seed_ok and ((seed.angle or 0) > 0 or ssrc:find("defensive")
               or ssrc:find("aligned") or ssrc:find("instant_head") or ssrc:find("on_shot")) then
                BRUTE._sf[p] = globals.tickcount()
                if (seed.angle or 0) > 0 then
                    local strong = ssrc:find("move_yaw") or ssrc:find("bullet_pick")
                        or ssrc:find("defensive") or ssrc:find("desync_measured") or ssrc:find("lby_break")
                        or ssrc:find("jitter") or ssrc:find("layer")
                    if strong then
                        BRUTE._amp[p] = nil
                        local a0 = math.abs(seed.angle)
                        if a0 >= 34 then a0 = cap elseif a0 >= 22 then a0 = math.min(38, cap) else a0 = math.min(29, cap) end
                        if a0 > cap then a0 = cap end
                        local sgn0 = (seed.side < 0) and -1 or 1
                        sgn0 = sgn0 * BRUTE.sgn_for(ssrc, p)
                        return sgn0*a0
                    end
                    local mode, ab = BRUTE.amp_pick(p, seed)
                    BRUTE._amp[p] = ab and mode or nil
                    local amp = ANGLES[1]
                    if mode == "det" then amp = math.min(math.abs(seed.angle), ANGLES[1]) end
                    if amp > cap then amp = cap end
                    local side = (seed.side < 0) and -1 or 1
                    side = side*BRUTE.sgn_for(ssrc, p)
                    return side*amp
                end
                return 0
            end
            if ui.get(BRUTE.native_ui) then return nil end
            local b = get(p)
            local stt = gstate(p, group_of(p))
            if not b.order then b.order = build_order(p) end
            local use_stg = (stt.stage and stt.stage > 0) and stt.stage or 1
            local a = b.order[use_stg]
            if a and math.abs(a) > cap then a = a > 0 and cap or -cap end
            return a
        end
        local b = get(p)
        if not b.order then b.order = build_order(p) end
        local a = b.order[stage]
        if a and math.abs(a) > cap then a = a > 0 and cap or -cap end
        return a
    end
    function BRUTE.reset() B = {}; BRUTE.B = B end
    BRUTE.C = { hvh={}, normal={} }
    BRUTE.cls_of = function(pitch, pp12)
        if math.abs(pitch or 0) >= 80 or math.abs((pp12 or 0.5) - 0.5) >= 0.45 then return "hvh" end
        return "normal"
    end
    BRUTE.cstat = function(cls, stage)
        BRUTE.C[cls][stage] = BRUTE.C[cls][stage] or { h=0, m=0 }
        return BRUTE.C[cls][stage]
    end
    BRUTE.class_start = function(b, p)
        local cls = b.cls or BRUTE.cls_of(entity.get_prop(p, "m_angEyeAngles[0]"), entity.get_prop(p, "m_flPoseParameter", 12))
        if cls ~= "hvh" then return 0 end
        local n = 0
        for k = 0, NSTAGE do local c = BRUTE.C.hvh[k]; if c then n = n + c.h + c.m end end
        if n < 4 then return 0 end
        local best, bests = 0, -1
        for k = 0, NSTAGE do
            local c = BRUTE.cstat("hvh", k)
            local sc = (c.h+1)/(c.h+c.m+2) + (k == 0 and 0.03 or 0)
            if sc > bests then best, bests = k, sc end
        end
        if best > 0 and bests >= 0.62 then
            if not b.order then b.order = build_order(p) end
            return best
        end
        return 0
    end
    BRUTE.next_stage = function(b, p, used)
        b.tried = b.tried or {}
        b.tried[used] = true
        b.tried[0] = true
        local sd0 = ST.resolver_seed[p]
        b.s0_streak = 0
        if used == 0 then
            local s0src = sd0 and tostring(sd0.source) or ""
            local s0ang = math.abs(sd0 and sd0.angle or 0)
            local trigger = s0src:find("pp11") or s0src:find("bruteforce")
                or s0src:find("defensive") or s0src:find("safe_head")
                or s0src:find("jitter") or s0src:find("layer") or s0src:find("lby")
                or s0src:find("instant_head") or s0src:find("desync")
                or (s0src:find("move_yaw") and s0ang >= 20)
            b.flip_first = trigger and true or false
            b.order, b.order_side = nil, nil
            BRUTE.ord_reset = (BRUTE.ord_reset or 0) + 1
        end
        if not b.order then b.order = build_order(p) end
        if used == 0 then
            return 1
        end
        local cand = {}
        for k = 1, NSTAGE do
            if not b.tried[k] and not (k == 0 and skip_native(b, p)) and not BRUTE.dup29(b, k) then cand[#cand+1] = k end
        end
        local used_ang = (b.last_missed_ang and b.last_missed_ang ~= 0 and b.last_missed_ang)
            or (used and used > 0 and b.order and b.order[used]) or 0
        if used_ang ~= 0 and #cand > 1 then
            local f = {}
            for _, k in ipairs(cand) do
                local a2 = (k > 0 and b.order and b.order[k]) or 0
                if a2 == 0 or math.abs(a2 - used_ang) > 6 then f[#f+1] = k end
            end
            if #f > 0 then cand = f end
        end
        if #cand == 0 then
            b.tried = {}
            b.s0_consec_fail = 0
            for k = 1, NSTAGE do
                if k ~= used and not (k == 0 and skip_native(b, p)) and not BRUTE.dup29(b, k) then cand[#cand+1] = k end
            end
            if #cand == 0 then return (used == 1) and 2 or 1 end
        end
        if used and used > 0 then
            local mirror = (used % 2 == 1) and (used + 1) or (used - 1)
            for _, k in ipairs(cand) do if k == mirror then return mirror end end
        end
        local n = 0
        if b.cls == "hvh" then for k = 0, NSTAGE do local c = BRUTE.C.hvh[k]; if c then n = n + c.h + c.m end end end
        if n >= 4 then
            local best, bs = cand[1], -1
            for _, k in ipairs(cand) do
                local c = BRUTE.cstat("hvh", k)
                local sc = (c.h+1)/(c.h+c.m+2) + (k == 0 and 0.03 or 0)
                if sc > bs then best, bs = k, sc end
            end
            return best
        end
        for _, k in ipairs(cand) do if k > used then return k end end
        local pick = cand[1]
        if pick == used then for _, k in ipairs(cand) do if k ~= used then pick = k break end end end
        return pick
    end
    BRUTE.fmt_stage = function(p, stage, ang)
        if not stage or stage == 0 then
            if not BRUTE.always_on() then return "native" end
            if ang == nil then return "s0(seed|native)" end
            return ang ~= 0 and string.format("seed(%+d)", ang) or "seed(0)"
        end
        if ang ~= nil then return string.format("bf%d(%+d)", stage, math.floor(ang + 0.5)) end
        local ok, a = pcall(angle_of, p, stage)
        return string.format("bf%d(%+d)", stage, (ok and a) or 0)
    end
    BRUTE.say_ui = ui.new_checkbox("RAGE", "Other", "Min resolver: chat say (hit/miss)")
    ui.set(BRUTE.say_ui, false)
    BRUTE.say_mode_ui = ui.new_combobox("RAGE", "Other", "Min resolver: chat say mod", {"Hit + Miss","Doar miss","Doar hit"})
    BRUTE.say_last = 0
    BRUTE.say = function(kind, p, info, sn)
        local m = ui.get(BRUTE.say_mode_ui)
        if (m == "Doar miss" and kind ~= "MISS") or (m == "Doar hit" and kind ~= "HIT") then return end
        local now = globals.realtime()
        if now - BRUTE.say_last < 1.5 then return end
        BRUTE.say_last = now
        local name = tostring(entity.get_player_name(p) or ("P" .. p))
        local what = tostring(info.what or "")
        what = what:gsub("%[.-%]", ""):gsub("%(.-%)", ""):gsub("%s+", " ")
        what = what:gsub("^RESOLVER%s*$", "resolver a ratat"):gsub("^%s+", ""):gsub("%s+$", "")
        local msg = string.format("[RESOLVER] %s %s | %s | %s", kind, name, what, tostring(info.used))
        msg = msg:gsub("[;\"%%]", ""):gsub("[^%g ]", "?")
        if #msg > 120 then msg = msg:sub(1, 120) end
        client.exec("say " .. msg)
    end
    BRUTE.clean_log = function(kind, p, info)
        local say_on = ui.get(BRUTE.say_ui) and (kind == "HIT" or kind == "MISS")
        if not ui.get(debug_log) and not say_on then return end
        local b = B[p]
        local sn = info.snap or (b and b.snap)
        if say_on then pcall(BRUTE.say, kind, p, info, sn) end
        if not ui.get(debug_log) then return end
        local grp = sn and sn.grp or group_of(p)
        local st = b and b.g[grp]
        local nxt = BRUTE.fmt_stage(p, st and st.stage or 0) .. ((st and st.hit ~= nil) and "*" or "")
        local ctx = sn and string.format("%s spd=%d hc=%d bt=%d pitch=%d pp11=%.2f bd=%d cls=%s%s",
            sn.grp, sn.spd, sn.hc or 0, sn.bt or 0, sn.pitch or 0, sn.pp11 or 0.5, sn.bd or 0,
            b.cls or "?", sn.hard and " SHIFT" or "") or "no_snapshot"
        client.log(string.format("[%s] P%d %s | used=%s | %s | seed=%s | next=%s", kind, p, info.what, info.used, ctx,
            ((sn and sn.sseed) or "?") .. ((sn and sn.via_seed) and ("[USED" .. (sn.amp and (":" .. sn.amp) or "") .. "]") or ""), nxt))
    end
    BRUTE.always_ui = ui.new_checkbox("RAGE", "Other", "Min resolver: aplica mereu body yaw propriu (fara resolverul nativ)")
    ui.set(BRUTE.always_ui, true)
    BRUTE.always_on = function() return ui.get(BRUTE.always_ui) end
    BRUTE.seedmin_ui = ui.new_slider("RAGE", "Other", "Min resolver: seed min confidence", 20, 95, 40)
    BRUTE.native_ui = ui.new_checkbox("RAGE", "Other", "Min resolver: fara seed => resolver nativ")
    BRUTE.assist_ui = ui.new_checkbox("RAGE", "Other", "Min resolver: body aim + safe point cat sondeaza")
    ui.set(BRUTE.assist_ui, false)
    BRUTE.head_ui = ui.new_checkbox("RAGE", "Other", "Min resolver: prefera head (Override prefer body aim = Off)")
    ui.set(BRUTE.head_ui, true)
    BRUTE.air_sp_ui = ui.new_checkbox("RAGE", "Other", "Min resolver: safe point cand inamicul e in aer")
    ui.set(BRUTE.air_sp_ui, true)
    BRUTE.timing_ui = ui.new_combobox("RAGE", "Other", "Min resolver: cand aplic plist-ul", {"setup_command","net_update_end"})
    ui.set(BRUTE.timing_ui, "net_update_end")
    BRUTE.exp_sp_ui = ui.new_checkbox("RAGE", "Other", "Min resolver: safe point cand inamicul face DT/defensive/fakelag")
    ui.set(BRUTE.exp_sp_ui, true)
    BRUTE.snip_ui = ui.new_slider("RAGE", "Other", "Min resolver: sniper baim dupa N miss-uri (0=off)", 0, 5, 2)
    BRUTE.lowhp_ui = ui.new_slider("RAGE", "Other", "Min resolver: baim cand HP inamic <= (0=off)", 0, 100, 0)
    BRUTE.bt_ui = ui.new_slider("RAGE", "Other", "Min resolver: ignora miss daca backtrack > (ticks, 0=off)", 0, 32, 16)
    BRUTE.skipbody_ui = ui.new_checkbox("RAGE", "Other", "Min resolver: miss tintit in corp nu avanseaza unghiul")
    ui.set(BRUTE.skipbody_ui, true)
    BRUTE.aim_ui = ui.new_combobox("RAGE", "Other", "Min resolver: tintire", {"Head","Head + baim la exploit","Echilibrat"})
    ui.set(BRUTE.aim_ui, "Head + baim la exploit")
    BRUTE.head_mode = function() return ui.get(BRUTE.aim_ui) == "Head" end
    BRUTE.pitch_ui = ui.new_checkbox("RAGE", "Other", "Min resolver: Force pitch la pitch AA (A/B test)")
    ui.set(BRUTE.pitch_ui, true)
    BRUTE.ffistruct_ui = ui.new_combobox("RAGE", "Other", "Min resolver: FFI struct",
        {"C_AnimLayer_t (pad 0x14, implicit)", "C_AnimLayer1C_t (owner@0x1C)", "C_AnimLayer18_t (owner@0x18)"})
    ui.set(BRUTE.ffistruct_ui, "C_AnimLayer_t (pad 0x14, implicit)")
    BRUTE.UNSAFE_WINDOW = 6
    BRUTE.recent_unsafe = function(p)
        local t = ST.unsafe[p]
        return t ~= nil and (globals.tickcount() - t) <= BRUTE.UNSAFE_WINDOW
    end
    BRUTE.exploit_unsafe = function(p)
        if ui.get(BRUTE.aim_ui) == "Echilibrat" then
            return (ui.get(BRUTE.exp_sp_ui) and BRUTE.recent_unsafe(p)) or false end
        return false
    end
    BRUTE.big_sniper = function()
        local me = entity.get_local_player()
        if not me then return false end
        local w = entity.get_player_weapon(me)
        if not w then return false end
        local d = (entity.get_prop(w, "m_iItemDefinitionIndex") or 0) % 65536
        return d == 9 or d == 38 or d == 11
    end
    BRUTE.is_head_clean = function(p)
        if is_defensive_pitch(p) then return false end
        local hx, hy, hz = entity.hitbox_position(p, C.HITBOX_HEAD)
        if not hx then return false end
        return client.visible(hx, hy, hz) == true
    end
    BRUTE.want_baim = function(p, b, st)
        if ssg_wants_head_only(p) and (st.misses or 0) < 2 then
            return false
        end
        if ui.get(BRUTE.head_ui) and ui.get(head_priority) and (st.misses or 0) < 2 then
            local hp_now = entity.get_prop(p, "m_iHealth") or 100
            if hp_now > 55 and not is_defensive_pitch(p) then return false end
        end
        local pitch_wb = math.abs(entity.get_prop(p, "m_angEyeAngles[0]") or 0)
        if is_defensive_pitch(p) then
            local sdw = ST.resolver_seed[p]
            local s0ok = sdw and (globals.tickcount() - (sdw.tick or 0)) <= 4 and (sdw.confidence or 0) >= 88
                         and (tostring(sdw.source or ""):find("desync_measured")
                              or tostring(sdw.source or ""):find("on_shot"))
            if not s0ok then
                local bv_wb = is_body_visible(p)
                if bv_wb then return true end
            end
        elseif pitch_wb >= C.PITCH_TILT_DEG and pitch_wb < C.PITCH_DOWN_MIN and not BRUTE.is_head_clean(p) then
            if is_body_visible(p) then return true end
        end
        local hp_th = ui.get(BRUTE.lowhp_ui)
        if hp_th > 0 and (entity.get_prop(p, "m_iHealth") or 100) <= hp_th then return true end
        local n = ui.get(BRUTE.snip_ui)
        if n > 0 and (st.misses or 0) >= n and BRUTE.big_sniper() then return true end
        if ui.get(BRUTE.aim_ui) ~= "Echilibrat" and ui.get(BRUTE.exp_sp_ui) and BRUTE.recent_unsafe(p) then
            local tb = ST.tickbase_data[p]
            if (ST.hard_recent(p, 4) or (tb and tb.is_doubletap)) and not BRUTE.is_head_clean(p) then
                return true end
        end
        local sdd = ST.resolver_seed[p]
        if sdd and sdd.tick and (globals.tickcount() - sdd.tick) <= 4
           and tostring(sdd.source):find("defensive") then
            local bvd = is_body_visible(p)
            if bvd then return true end
        end
        local rq = ST.baim_req[p]
        if rq ~= nil and (globals.tickcount() - rq) <= 4 then
            if BRUTE.is_head_clean(p) then return false end
            return true
        end
        return false
    end
    BRUTE.is_head = function(hg)
        if hg == nil then return false end
        if type(hg) == "string" then
            local s = hg:lower()
            return s == "head" or s == "neck" or s == "?"
        end
        return hg == 1 or hg == 8
    end
    local function apply(p)
        local b = get(p)
        if is_whitelisted(p) then
            if b.once then pcall(BRUTE.restore, p); b.once = nil end
            return
        end
        b.once = true
        local grp = group_of(p)
        local st = gstate(p, grp)
        local now = globals.tickcount()
        if b.order and st.stage == 0 and st.hit == nil and (st.misses or 0) == 0 and b.order_gen ~= BRUTE.M.gen then
            b.order, b.tried, b.order_side = nil, nil, nil
            b.order_gen = BRUTE.M.gen
        end
        if b.nhit == 0 and b.nfail == 0 and not b.last_hit_stage and not b.search
           and st.hit == nil and st.misses == 0 then st.stage = BRUTE.class_start(b, p) end
        if BRUTE._sf then BRUTE._sf[p] = nil end
        local use_mem = (st.hit_angle ~= nil and (st.misses or 0) == 0 and (now - (st.hit_tick or 0)) <= 32)
        if use_mem then
            local sd = ST.resolver_seed[p]
            if sd and (sd.angle or 0) > 0 and math.abs((sd.angle or 0) - math.abs(st.hit_angle)) > 8 then
                use_mem = false
            end
        end
        if use_mem then
            local sd = ST.resolver_seed[p]
            local mem_side = st.hit_angle > 0 and 1 or (st.hit_angle < 0 and -1 or 0)
            local sd_src = sd and tostring(sd.source or "") or ""
            local strong = sd and sd.tick and (now - sd.tick) <= 1 and (sd.confidence or 0) >= 80
                           and (sd.angle or 0) > 0 and (sd.side or 0) ~= 0 and (sd.side > 0 and 1 or -1) ~= mem_side
                           and (pp11_stable(p) or sd_src:find("defensive") or sd_src:find("desync_measured"))
            if strong then use_mem = false end
        end
        local a
        if use_mem then a = st.hit_angle end
        if a == nil then
            local ok_ao, ao = pcall(angle_of, p, st.stage)
            a = ok_ao and ao or nil
        end
        b.applied_via_seed = (st.stage == 0 and BRUTE._sf and BRUTE._sf[p] == now) or false
        b.applied_amp = b.applied_via_seed and BRUTE._amp[p] or nil
        b.applied, b.applied_stage = a, st.stage
        do
            local sdap = ST.resolver_seed[p]
            b.applied_src = sdap and sdap.source or nil
            b.applied_conf = sdap and (sdap.confidence or 0) or 0
            b.applied_seedang = sdap and ((sdap.side or 0)*(sdap.angle or 0)) or 0
            b.applied_how = (a == nil and "native") or (use_mem and "mem") or (st.stage > 0 and "bf") or "seed"
        end
        b.applied_tick, b.applied_group = globals.tickcount(), grp
        b.applied_sim = entity.get_prop(p, "m_flSimulationTime")
        local function pw(field, value)
            local c = b.wc
            if not c then c = {}; b.wc = c end
            local e = c[field]
            if e and e.v == value and (now - e.t) < 32 then return end
            c[field] = { v=value, t=now }
            plist.set(p, field, value)
        end
        pw("Correction active", true)
        local pt = entity.get_prop(p, "m_angEyeAngles[0]") or 0
        local sd_seed = ST.resolver_seed[p]
        local def_pt, def_kind = is_defensive_pitch(p)
        if math.abs(pt) > C.PITCH_UNTRUSTED then
            pw("Force pitch", true); pw("Force pitch value", pt > 0 and 89 or -89)
        elseif ui.get(BRUTE.pitch_ui) and def_pt and (def_kind == "flick" or def_kind == "up" or def_kind == "shift_pitch") then
            local ph = ST.pitch_hist[p]
            pw("Force pitch", true); pw("Force pitch value", (ph and ph.last_normal) or 89)
        else pw("Force pitch", false) end
        local hp = ((sd_seed and sd_seed.tick and (now - sd_seed.tick) <= 1 and (sd_seed.confidence or 0) >= 85
                    and ((sd_seed.source or ""):find("instant") or (sd_seed.source or ""):find("aligned")
                         or (sd_seed.source or ""):find("on_shot") or (sd_seed.source or ""):find("lby_break")
                         or (sd_seed.source or ""):find("move_yaw") or (sd_seed.source or ""):find("desync_measured")))
                    or ssg_wants_head_only(p)) and true or false
        if b.hp_on ~= hp then pw("High priority", hp); b.hp_on = hp end
        local probing = (st.stage > 0 and st.hit == nil)
        local assist = (ui.get(BRUTE.assist_ui) and probing) and true or false
        local sp_want = (not ssg_wants_head_only(p)) and (((grp == "air" and ui.get(BRUTE.air_sp_ui) and not BRUTE.head_mode()) or BRUTE.exploit_unsafe(p)) or assist) and true or false
        if b.sp_on ~= sp_want then pcall(plist.set, p, "Override safe point", sp_want and "On" or "-"); b.sp_on = sp_want end
        local baim_want = (not ssg_wants_head_only(p)) and (BRUTE.want_baim(p, b, st) or assist or BRUTE.exploit_unsafe(p)) and true or false
        if b.baim_on ~= baim_want then
            pcall(plist.set, p, "Override prefer body aim", baim_want and "On" or "-")
            b.baim_on = baim_want
            if not baim_want then b.pba = false end
        end
        if a ~= nil then
            pw("Force body yaw", true)
            pw("Force body yaw value", math.floor(a*10 + (a >= 0 and 0.5 or -0.5))/10)
        else pw("Force body yaw", false) end
    end
    function BRUTE.restore(p)
        pcall(plist.set, p, "Correction active", false)
        pcall(plist.set, p, "Force body yaw", false)
        pcall(plist.set, p, "Force pitch", false)
        pcall(plist.set, p, "High priority", false)
        local b = B[p]
        if not b then return end
        if b.sp_on then pcall(plist.set, p, "Override safe point", "-") end
        if b.baim_on or b.pba then pcall(plist.set, p, "Override prefer body aim", "-") end
        b.sp_on, b.baim_on, b.pba, b.hp_on, b.wc = nil, nil, false, nil, nil
        b.applied_src, b.applied_conf, b.applied_seedang, b.applied_how = nil, nil, nil, nil
    end
    BRUTE.run_apply = function(from_net)
        local on = ui.get(enable_resolver)
        local lp = entity.get_local_player()
        local weapon = lp and entity.get_player_weapon(lp) or nil
        for _, p in ipairs(entity.get_players(true)) do
            if on then
                if from_net and entity.is_alive(p) then
                    pcall(process_player_tick, p, weapon)
                end
                local ok, err = pcall(apply, p)
                if not ok and not BRUTE.apply_err then
                    BRUTE.apply_err = true
                    client.log("[BRUTE] eroare apply: " .. tostring(err)) end
            else BRUTE.restore(p) end
        end
    end
    client.set_event_callback("setup_command", function()
        local ok, err = pcall(BRUTE.run_apply, false)
        if not ok and not BRUTE._ra_err then
            BRUTE._ra_err = true
            client.log("[BRUTE] run_apply setup_command err: " .. tostring(err))
        end
    end)
    client.set_event_callback("net_update_end", function()
        local ok, err = pcall(BRUTE.run_apply, true)
        if not ok and not BRUTE._ra_err then
            BRUTE._ra_err = true
            client.log("[BRUTE] run_apply net_update_end err: " .. tostring(err))
        end
    end)
    client.set_event_callback("aim_fire", function(e)
        if not ui.get(enable_resolver) or not e.target then return end
        local grp = group_of(e.target)
        local b = get(e.target)
        b.fired_group = grp
        local sim_now = entity.get_prop(e.target, "m_flSimulationTime")
        local fresh_apply = (b.applied_group == grp)
            and (b.applied_sim == sim_now or (globals.tickcount() - (b.applied_tick or 0)) <= 4)
        b.fired_stage = fresh_apply and b.applied_stage or gstate(e.target, grp).stage
        local prev_dt = ST.dt_burst[e.target]
        local is_dt_second = false
        if prev_dt and (globals.tickcount() - (prev_dt.tick or 0)) <= 4
           and prev_dt.stage == b.fired_stage and not prev_dt.resolved then
            is_dt_second = true
        else
            ST.dt_burst[e.target] = { id = e.id, tick = globals.tickcount(), stage = b.fired_stage, resolved = false }
        end
        b.fired_id = e.id
        BRUTE._ap[e.target] = nil
        BRUTE._sk[e.target] = nil
        local T = BRUTE.T
        if T.n >= 6 and (T.h/T.n) < BRUTE.SEED_TRUST_MIN then
            T.skip = T.skip + 1
            T.probe = (T.skip % 3 == 0)
        else T.probe = false end
        local vx, vy = entity.get_prop(e.target, "m_vecVelocity")
        local used = (fresh_apply and b.applied_stage == b.fired_stage) and b.applied or nil
        b.snap = { tick=globals.tickcount(),
            eye=entity.get_prop(e.target, "m_angEyeAngles[1]") or 0,
            lby=entity.get_prop(e.target, "m_flLowerBodyYawTarget") or 0,
            spd=math.sqrt((vx or 0)^2 + (vy or 0)^2),
            grp=grp, stage=b.fired_stage, ang=used,
            confirmed=(gstate(e.target, grp).hit ~= nil), hc=e.hit_chance or 0,
            bt=(function(v) v = v or 0; if v ~= math.floor(v) then return math.floor(0.5 + v/globals.tickinterval()) end return v end)(e.backtrack),
            dmg=e.damage or 0, hg=e.hitgroup,
            pp11=entity.get_prop(e.target, "m_flPoseParameter", 11) or 0.5,
            pp12=entity.get_prop(e.target, "m_flPoseParameter", 12) or 0.5,
            pitch=entity.get_prop(e.target, "m_angEyeAngles[0]") or 0,
            stale=not fresh_apply,
            flags=(e.teleported and "T" or "") .. (e.extrapolated and "E" or "") .. (e.interpolated and "I" or "") .. (e.boosted and "B" or ""),
            tp=(e.teleported == true), ext=(e.extrapolated == true),
            unsafe=BRUTE.recent_unsafe(e.target) and true or false,
            dt_second=is_dt_second, local_dt=is_local_dt_active(), local_hs=is_local_hs_active(),
            hard=ST.hard_recent(e.target, 3) and true or false }
        local sd = ST.resolver_seed[e.target]
        if fresh_apply and b.applied_src then
            b.snap.sseed = string.format("%s/%d/%+d{%s}", b.applied_src, b.applied_conf or 0,
                b.applied_seedang or 0, b.applied_how or "?")
            b.snap.src = b.applied_src
        else
            b.snap.sseed = "no_apply"; b.snap.src = nil
        end
        b.snap.raw_side = nil
        if sd and sd.tick and (globals.tickcount() - sd.tick) <= 8 and (sd.angle or 0) > 0 and (sd.side or 0) ~= 0
           and (sd.confidence or 0) >= ui.get(BRUTE.seedmin_ui) and tostring(sd.source):sub(1, 9) ~= "emergency" then
            b.snap.raw_side = (sd.side > 0) and 1 or -1 end
        local pv11 = entity.get_prop(e.target, "m_flPoseParameter", 11)
        b.snap.pure_side = (type(pv11) == "number" and math.abs((pv11 - 0.5)*C.PP11_SCALE) >= C.PP11_SIDE_MIN_DEG)
            and ((pv11 > 0.5) and 1 or -1) or nil
        b.snap.via_seed = fresh_apply and (b.fired_stage == 0) and (b.applied_stage == 0) and (b.applied_via_seed == true)
        b.snap.amp = b.snap.via_seed and b.applied_amp or nil
        b.snap.bd = math.floor(pp11_body_delta(e.target) + 0.5)
        local okr, rel = pcall(function()
            local me = entity.get_local_player()
            if not me then return nil end
            local mx, my = entity.get_origin(me)
            local ex, ey = entity.get_origin(e.target)
            if not (mx and my and ex and ey) then return nil end
            return ((b.snap.eye - math.deg(math.atan2(my - ey, mx - ex)) + 540) % 360) - 180
        end)
        b.snap.rel = okr and rel or nil
        local cl = BRUTE.cls_of(b.snap.pitch, b.snap.pp12)
        if cl == "hvh" then b.cls = "hvh" elseif not b.cls then b.cls = "normal" end
        b.snap.cls = b.cls
        b.shots = b.shots or {}
        b.shots[e.id or 0] = { stage=b.fired_stage, grp=grp, snap=b.snap }
        b.last_shot_rec = b.shots[e.id or 0]
        local now = globals.tickcount()
        for id, r in pairs(b.shots) do if now - r.snap.tick > 256 then b.shots[id] = nil end end
    end)
    client.set_event_callback("aim_hit", function(e)
        if not ui.get(enable_resolver) or not e.target then return end
        local b = get(e.target)
        local rec = (b.shots and b.shots[e.id or 0]) or b.last_shot_rec
        if not rec then
            BRUTE.clean_log("HIT", e.target, { what="fara snapshot pentru shot id; nu invat", used="fara_snapshot", snap=nil })
            return
        end
        local fstage, grp, sn = rec.stage, rec.grp, rec.snap
        if b.shots then b.shots[e.id or 0] = nil end
        local dtb = ST.dt_burst[e.target]
        if dtb and dtb.id == e.id then dtb.resolved = true end
        local head_shot = BRUTE.is_head(e.hitgroup)
        if sn.stale then
            BRUTE.clean_log("HIT", e.target, { what="snapshot plist vechi; nu confirm unghiul", used="stale", snap=sn })
            return
        end
        if sn and sn.ang == 0 then ST.aligned_miss_n[e.target] = 0 end
        if not head_shot then
            BRUTE.clean_log("HIT", e.target, { what=string.format("%s %ddmg [corp: nu confirma unghiul]",
                HITGROUP_NAMES[e.hitgroup or 0] or "?", e.damage or 0),
                used=BRUTE.fmt_stage(e.target, fstage, sn and sn.ang), snap=sn })
            return
        end
        if sn and (fstage or 0) == 0 then
            if sn.via_seed then
                BRUTE.seed_result(true, false)
                if sn.amp then BRUTE.amp_result(sn.amp, true) end
                if sn.src then BRUTE.src_result(sn.src, true) end
            elseif sn.ang == nil then BRUTE.base_result(true) end
        end
        b.filt, b.filt_lag = 0, 0
        local st = gstate(e.target, grp)
        local was_confirmed = (st.hit ~= nil)
        if sn and sn.ang ~= nil then pcall(ST.learn, e.target, true, sn.ang, sn.src) end
        b.tried = nil
        b.s0_streak = 0
        b.s0_consec_fail = 0
        b.flip_first = nil
        b.last_missed_ang = nil
        local no_sign_learn = (fstage or 0) == 0 and sn and sn.src
            and (sn.src:find("pp11") or sn.src:find("bullet_pick")
                 or sn.src:find("defensive") or sn.src:find("desync_measured")) and true or false
        if head_shot and not was_confirmed and sn and sn.raw_side and sn.ang and sn.ang ~= 0 and not no_sign_learn then
            BRUTE.ss_vote(((sn.ang > 0) and 1 or -1)*sn.raw_side*BRUTE.sgn_for(sn.src, e.target)) end
        if head_shot and not was_confirmed and sn and sn.pure_side and (fstage or 0) > 0 and sn.ang and sn.ang ~= 0 then
            BRUTE.ss_vote(((sn.ang > 0) and 1 or -1)*sn.pure_side) end
        if head_shot and not was_confirmed and sn and sn.raw_side and sn.ang and sn.ang ~= 0 and sn.src and not no_sign_learn then
            ST.sgn_player[e.target] = ST.sgn_player[e.target] or {}
            local psg = ST.sgn_player[e.target][sn.src]
            if not psg then psg = { agree=0, dis=0, sign=1 }; ST.sgn_player[e.target][sn.src] = psg end
            local sg = ST.sgn[sn.src]
            if not sg then sg = { agree=0, dis=0, sign=1 }; ST.sgn[sn.src] = sg end
            local applied_side = ((sn.ang > 0) and 1 or -1)*BRUTE.seed_sign()
            if applied_side == sn.raw_side then
                sg.agree = sg.agree + 1; psg.agree = psg.agree + 1
            else
                sg.dis = sg.dis + 1; psg.dis = psg.dis + 1
            end
            local ptot = psg.agree + psg.dis
            if ptot >= 3 then
                if psg.dis >= 0.70*ptot then psg.sign = -1 elseif psg.agree >= 0.70*ptot then psg.sign = 1 end
            end
            local tot = sg.agree + sg.dis
            if tot >= 10 then
                if sg.dis >= 0.75*tot and sg.sign ~= -1 then
                    sg.sign = -1
                    client.log("[SGN] sursa " .. tostring(sn.src) .. " -> SEMN INVERSAT automat.")
                elseif sg.agree >= 0.75*tot and sg.sign ~= 1 then sg.sign = 1 end
            end
        end
        st.stage = fstage or st.stage
        st.hit, st.hit_tick = st.stage, globals.tickcount()
        st.hit_angle = (sn and sn.ang ~= nil) and sn.ang or nil
        st.misses, st.filt = 0, 0
        local pmx = ST.player_memory[e.target]
        if pmx then pmx.misses = 0 end
        b.total_h = (b.total_h or 0) + 1
        if st.stage == 0 then b.nhit = b.nhit + 1
        else
            b.last_hit_stage, b.search = st.stage, st.stage
            for _, s2 in pairs(b.g) do if s2.hit == nil then s2.stage = st.stage end end
        end
        if head_shot and st.stage > 0 and not was_confirmed and sn and sn.pp11 and sn.grp ~= "air" and b.order then
            local M = BRUTE.M
            local dev = sn.pp11 - 0.5
            local ang = b.order[st.stage]
            if math.abs(dev) >= M.dev_min and ang then
                if (ang > 0) == (dev > 0) then M.agree = M.agree + 1 else M.dis = M.dis + 1 end
                BRUTE.m_update()
            end
        end
        if not was_confirmed and b.cls then BRUTE.cstat(b.cls, st.stage).h = BRUTE.cstat(b.cls, st.stage).h + 1 end
        BRUTE.clean_log("HIT", e.target, { what=string.format("%s %ddmg%s", HITGROUP_NAMES[e.hitgroup or 0] or "?",
            e.damage or 0, head_shot and "" or " [corp]"),
            used=BRUTE.fmt_stage(e.target, fstage, sn and sn.ang) .. (was_confirmed and "*" or "(nou)"), snap=sn })
    end)
    client.set_event_callback("aim_miss", function(e)
        if not ui.get(enable_resolver) or not e.target then return end
        local b = get(e.target)
        local rec = (b.shots and b.shots[e.id or 0]) or b.last_shot_rec
        if not rec then
            BRUTE.clean_log("MISS", e.target, { what=tostring(e.reason) .. " (fara snapshot; nu invat)", used="fara_snapshot", snap=nil })
            return
        end
        local fstage, sn, grp = rec.stage, rec.snap, rec.grp
        if b.shots then b.shots[e.id or 0] = nil end
        local dtb = ST.dt_burst[e.target]
        if dtb and dtb.id == e.id then dtb.resolved = true end
        local st = gstate(e.target, grp)
        local used = fstage or st.stage
        if sn and sn.dt_second and st.stage ~= used then
            BRUTE.clean_log("MISS", e.target, { what=tostring(e.reason) .. " (DT al 2-lea glont pe acelasi unghi: nu avansez dublu)",
                used=BRUTE.fmt_stage(e.target, used, sn and sn.ang), snap=sn })
            return
        end
        local head_shot = (sn and BRUTE.is_head(sn.hg)) or BRUTE.is_head(e.hitgroup)
        if sn and sn.ang == 0 then
            local n0 = (ST.aligned_miss_n[e.target] or 0) + 1
            if n0 >= C.ALIGN_MISS_BLOCK then
                ST.instant_block[e.target] = globals.tickcount() + C.ALIGN_BLOCK_TICKS
                ST.last_result[e.target], ST.last_result_sim[e.target] = nil, nil
                n0 = 0
                client.log("[ALIGN] P" .. tostring(e.target) .. " aligned ratat de " ..
                    C.ALIGN_MISS_BLOCK .. "x -> blocat " .. C.ALIGN_BLOCK_TICKS .. " tick")
            end
            ST.aligned_miss_n[e.target] = n0
        end
        local soft
        if e.reason ~= nil and e.reason ~= "?" then soft = tostring(e.reason)
        elseif sn and sn.tp then soft = "teleport/lagcomp"
        elseif sn and (sn.spd or 0) > 700 then soft = "teleport/lagcomp"
        elseif sn and sn.ext then soft = "extrapolat"
        elseif ui.get(BRUTE.bt_ui) > 0 and sn and (sn.bt or 0) > ui.get(BRUTE.bt_ui) then soft = "backtrack"
        end
        if sn.stale then soft = "snapshot plist vechi" end
        if not soft and sn and (sn.hc or 0) > 0 and (sn.hc or 0) < 65 then soft = "spread (hc mic)" end
        if soft then
            BRUTE.clean_log("MISS", e.target, { what=tostring(e.reason) .. " (" .. soft .. ": nu invat si nu avansez)",
                used=BRUTE.fmt_stage(e.target, used, sn and sn.ang), snap=sn })
            return
        end
        b.filt, b.filt_lag = 0, 0
        if head_shot and sn and (fstage or 0) == 0 then
            if sn.via_seed then
                BRUTE.seed_result(false)
                if sn.amp then BRUTE.amp_result(sn.amp, false) end
                if sn.src then BRUTE.src_result(sn.src, false) end
            elseif sn.ang == nil then BRUTE.base_result(false) end
        end
        st.hit = nil
        st.misses = st.misses + 1
        b.total_m = (b.total_m or 0) + 1
        b.last_missed_ang = (sn and sn.ang) or b.applied or nil
        if sn and sn.ang ~= nil then pcall(ST.learn, e.target, false, sn.ang, sn.src) end
        if used == 0 then b.nfail = b.nfail + 1; b.s0_consec_fail = (b.s0_consec_fail or 0) + 1
        else b.s0_consec_fail = 0 end
        if b.cls then BRUTE.cstat(b.cls, used).m = BRUTE.cstat(b.cls, used).m + 1 end
        local pmx = ST.player_memory[e.target]
        if pmx then pmx.misses = (pmx.misses or 0) + 1 end
        local nxt = BRUTE.next_stage(b, e.target, used)
        st.stage, b.search = nxt, nxt
        if nxt > 0 then
            for g2, s2 in pairs(b.g) do
                if g2 ~= grp then s2.stage = nxt; s2.hit = nil end
            end
        end
        BRUTE.clean_log("MISS", e.target, { what="RESOLVER (?)", used=BRUTE.fmt_stage(e.target, used, sn and sn.ang), snap=sn })
    end)
    pcall(function()
        local d = database.read("res12_cstats_v5")
        if type(d) == "table" and type(d.hvh) == "table" then
            for k = 0, NSTAGE do
                local c = d.hvh["s" .. k]
                if type(c) == "table" then
                    BRUTE.C.hvh[k] = { h=math.floor((tonumber(c.h) or 0)/2), m=math.floor((tonumber(c.m) or 0)/2) } end
            end
        end
        if type(d) == "table" and type(d.ss) == "table" then
            BRUTE.SS.cal = (tonumber(d.ss.cal) == -1) and -1 or 1
            BRUTE.SS.p, BRUTE.SS.n = math.floor((tonumber(d.ss.p) or 0)/2), math.floor((tonumber(d.ss.n) or 0)/2)
        end
        if type(d) == "table" and type(d.sgn) == "table" then
            for src, v in pairs(d.sgn) do
                if type(v) == "table" then
                    ST.sgn[src] = { agree=math.floor((tonumber(v.a) or 0)/2), dis=math.floor((tonumber(v.d) or 0)/2),
                                    sign=(tonumber(v.s) == -1) and -1 or 1 } end
            end
        end
    end)
    BRUTE.m_update()
    BRUTE.save = function()
        pcall(function()
            local d = { hvh={}, ss={ cal=BRUTE.SS.cal, p=BRUTE.SS.p, n=BRUTE.SS.n }, sgn={} }
            for k = 0, NSTAGE do
                local c = BRUTE.C.hvh[k]
                if type(c) == "table" then d.hvh["s" .. k] = { h=c.h or 0, m=c.m or 0 } end
            end
            for src, v in pairs(ST.sgn) do d.sgn[src] = { a=v.agree or 0, d=v.dis or 0, s=v.sign or 1 } end
            database.write("res12_cstats_v5", d)
        end)
    end
    client.set_event_callback("round_end", BRUTE.save)
    client.set_event_callback("shutdown", function()
        BRUTE.save()
        for p in pairs(B) do BRUTE.restore(p) end
    end)
    client.set_event_callback("level_init", function()
        BRUTE.reset()
        for _, cls in pairs(BRUTE.C) do
            for _, c in pairs(cls) do
                if type(c) == "table" then c.h, c.m = math.floor((c.h or 0)/2), math.floor((c.m or 0)/2) end end
        end
    end)
    client.set_event_callback("player_disconnect", function(e)
        local v = client.userid_to_entindex(e.userid)
        if v and v ~= 0 then BRUTE.restore(v); B[v] = nil end
    end)
    client.set_event_callback("round_start", function()
        for _, b in pairs(B) do b.fired_stage, b.fired_group, b.snap, b.filt, b.filt_lag, b.s0_streak, b.s0_consec_fail, b.flip_first = nil, nil, nil, 0, 0, 0, 0, nil; b.applied_src, b.applied_conf, b.applied_seedang, b.applied_how = nil, nil, nil, nil end
    end)
end

-- 37 ── watchdog
ST._wd = { last=0, rep={}, wipe={ cache_data=true, cache_timestamp=true, cache_session=true,
    entity_cache=true, pose_parameter_cache=true, bone_matrix_cache=true } }
client.set_event_callback("setup_command", function()
    if globals.realtime() - ST._wd.last < 5 then return end
    ST._wd.last = globals.realtime()
    for name, t in pairs(ST) do
        if type(t) == "table" and name ~= "_wd" and name ~= "_dot" then
            local n = 0
            for _, v in pairs(t) do
                n = n + 1
                if type(v) == "table" then for _ in pairs(v) do n = n + 1 end end
                if n > 6000 then break end
            end
            if n > 6000 then
                local last = ST._wd.rep[name] or 0
                if globals.realtime() - last > 30 then
                    ST._wd.rep[name] = globals.realtime()
                    if ST._wd.wipe[name] then
                        ST[name] = {}
                        client.log(string.format("[WATCHDOG] ST.%s >%d intrari -> golit.", name, n))
                    else client.log(string.format("[WATCHDOG] ST.%s >%d intrari (creste).", name, n)) end
                end
            end
        end
    end
end)

-- 38 ── debug vizual
ST._dot = { ui = ui.new_checkbox("RAGE", "Other", "Min resolver: puncte debug"), aim = {} }
client.set_event_callback("aim_fire", function(e)
    if e.x and e.y and e.z then ST._dot.aim = { x=e.x, y=e.y, z=e.z, t=globals.realtime() } end
end)
client.set_event_callback("paint", function()
    if not ui.get(ST._dot.ui) then return end
    for _, p in ipairs(entity.get_players(true)) do
        local hx, hy, hz = entity.hitbox_position(p, C.HITBOX_HEAD)
        if hx then
            local sx, sy = renderer.world_to_screen(hx, hy, hz)
            if sx then renderer.circle(sx, sy, 255, 0, 0, 230, 4, 0, 1) end
        end
    end
    local a = ST._dot.aim
    if a.t and globals.realtime() - a.t < 1.5 then
        local sx, sy = renderer.world_to_screen(a.x, a.y, a.z)
        if sx then renderer.circle(sx, sy, 60, 140, 255, 230, 4, 0, 1) end
    end
end)

-- 39 ── statistici
do
    local S = { hits=0, total=0, reasons={}, th=0, tb=0, head_shots=0, head_hits=0,
        unknown_head=0, unknown_body=0 }
    local function summary(tag)
        if not ui.get(debug_log) then return end
        local parts = {}
        for r, n in pairs(S.reasons) do parts[#parts+1] = string.format("%s=%d", r, n) end
        table.sort(parts)
        local res = S.reasons["?"] or 0
        local sp = {}
        for k, r in pairs(BRUTE.SRC) do
            if r.n > 0 then
                local sg = ST.sgn[k]
                sp[#sp+1] = string.format("%s=%d/%d%s", k, r.h, r.n, (sg and sg.sign == -1) and "INV" or "") end
        end
        table.sort(sp)
        if #sp > 0 then client.log("[SRC] hit/shot pe sursa de seed: " .. table.concat(sp, " ")) end
        local sgns = {}
        for k, v in pairs(ST.sgn) do
            if (v.agree + v.dis) >= 10 and v.sign == -1 then sgns[#sgns+1] = k end
        end
        if #sgns > 0 then
            table.sort(sgns)
            client.log("[SGN] surse cu SEMN INVERSAT automat (vs pp11): " .. table.concat(sgns, " "))
        end
        client.log(string.format("[TGT] tinte ragebot: cap=%d corp=%d", S.th, S.tb))
        client.log(string.format("[ORD] reset_la_miss_s0=%d invalidari_baza=%d", BRUTE.ord_reset or 0, BRUTE.ord_inval or 0))
        client.log(string.format("[PP11-SGN] semn=%+d acord=%d/%d", BRUTE.M.sign or 1,
            ST.pp11_sign_agree or 0, ST.pp11_sign_n or 0))
        local hr = S.head_shots > 0 and (100*S.head_hits/S.head_shots) or 0
        client.log(string.format("[STATS%s] shots=%d hits=%d | HITRATE CAP=%.0f%% (%d/%d) | miss: %s | unknown(?)=%d (%.0f%%, head=%d body=%d) | seed=%.1f/%d base=%d/%d amp[det=%d/%d max=%d/%d] | semn_seed=%+d",
            tag or "", S.total, S.hits, hr, S.head_hits, S.head_shots,
            #parts > 0 and table.concat(parts, " ") or "-", res,
            S.total > 0 and (100*res/S.total) or 0, S.unknown_head, S.unknown_body, BRUTE.T.h, BRUTE.T.n, BRUTE.T0.h, BRUTE.T0.n,
            BRUTE.AMP.det.h, BRUTE.AMP.det.n, BRUTE.AMP.max.h, BRUTE.AMP.max.n, BRUTE.seed_sign()))
    end
    client.set_event_callback("aim_fire", function(e)
        if not ui.get(enable_resolver) then return end
        if BRUTE.is_head(e.hitgroup) then
            S.th = S.th + 1; S.head_shots = S.head_shots + 1
        else S.tb = S.tb + 1 end
    end)
    client.set_event_callback("aim_hit", function(e)
        if not ui.get(enable_resolver) then return end
        S.hits, S.total = S.hits + 1, S.total + 1
        if e and BRUTE.is_head(e.hitgroup) then S.head_hits = S.head_hits + 1 end
        if S.total % 10 == 0 then summary("") end
    end)
    client.set_event_callback("aim_miss", function(e)
        if not ui.get(enable_resolver) then return end
        local r = tostring(e.reason or "?")
        S.reasons[r] = (S.reasons[r] or 0) + 1
        if r == "?" then
            if BRUTE.is_head(e.hitgroup) then S.unknown_head = S.unknown_head + 1
            else S.unknown_body = S.unknown_body + 1 end
        end
        if r ~= "death" then S.total = S.total + 1 end
        if S.total % 10 == 0 then summary("") end
    end)
    client.set_event_callback("round_end", function() summary(" round_end") end)
    client.set_event_callback("level_init", function()
        S.hits, S.total, S.reasons, S.th, S.tb, S.head_shots, S.head_hits, S.unknown_head, S.unknown_body =
            0, 0, {}, 0, 0, 0, 0, 0, 0
    end)
end

-- 40 ── plasa de siguranta finala + anti-overflow
do
    local fixed = {}
    local function need(tbl, key, def)
        if type(tbl[key]) ~= "table" then tbl[key] = def; fixed[#fixed+1] = key end
    end
    need(BRUTE, "_sf", {}); need(BRUTE, "_amp", {}); need(BRUTE, "_ap", {}); need(BRUTE, "_sk", {})
    need(BRUTE, "SRC", {}); need(BRUTE, "WEAK", {}); need(BRUTE, "warned", {})
    need(BRUTE, "C", {hvh={}, normal={}}); need(BRUTE, "AMP", {max={h=0,n=0}, det={h=0,n=0}})
    need(BRUTE, "T", {h=0,n=0,skip=0}); need(BRUTE, "T0", {h=0,n=0}); need(BRUTE, "SS", {p=0,n=0,cal=1})
    need(BRUTE, "M", {agree=0,dis=0,sign=1,dev_min=0.10,gen=0})
    if BRUTE.T.h == nil then BRUTE.T.h = 0 end
    if BRUTE.T.n == nil then BRUTE.T.n = 0 end
    if BRUTE.T.skip == nil then BRUTE.T.skip = 0 end
    if BRUTE.T0.h == nil then BRUTE.T0.h = 0 end
    if BRUTE.T0.n == nil then BRUTE.T0.n = 0 end
    if BRUTE.SS.cal == nil then BRUTE.SS.cal = 1 end
    if BRUTE.M.sign == nil then BRUTE.M.sign = 1 end
    if BRUTE.M.gen == nil then BRUTE.M.gen = 0 end
    if BRUTE.M.dev_min == nil then BRUTE.M.dev_min = 0.10 end
    if BRUTE.AMP.max == nil then BRUTE.AMP.max = {h=0,n=0} end
    if BRUTE.AMP.det == nil then BRUTE.AMP.det = {h=0,n=0} end
    if BRUTE.SEED_TRUST_MIN == nil then BRUTE.SEED_TRUST_MIN = 0.55 end
    if BRUTE.STALL_MAX == nil then BRUTE.STALL_MAX = 3 end
    if BRUTE.STALL_LAG == nil then BRUTE.STALL_LAG = 2 end
    client.log("[SELFTEST] BRUTE: " .. (type(BRUTE._sf) == "table" and "OK" or "LIPSA _sf !!") ..
        (#fixed > 0 and (" | reparat: " .. table.concat(fixed, ",")) or " | nimic lipsa"))

    local MAXENT = 3500
    local function count(t)
        local n = 0
        for _ in pairs(t) do n = n + 1; if n > MAXENT then return n end end
        return n
    end
    local PER = {
        "player_memory","player_animation_data","simtime_history","layer_history",
        "shot_context","last_applied","resolver_seed","angle_hit_data","last_valid_pos",
        "last_valid_vel","last_valid_tick","resolver_lock","lby_update_cache",
        "side_flip_history","side_score","fs_bait","animation_records","bone_matrix_cache",
        "pose_parameter_cache","tickbase_data","desync_data","jitter_data_v",
        "confidence_data","bruteforce_data","safe_head_data","last_resolve_tick",
        "network_angle_history","lby_broke","lby_broke_side","lby_broke_ang","flip_history","aa_state",
        "break_lc","instant_block","last_moving_cache","yaw_accel_history","entity_cache",
        "crouch_cache","baim_req","unsafe","hard_tick","pp_hist","thrash","break_lc_until","vote_side",
        "last_result","last_result_sim","lby_change_tick","eye_change_tick","aligned_miss_n",
        "pitch_hist","clean_pp11","anim_interp","sgn_player","dt_burst","on_shot",
    }
    local function clean_ST()
        for _, name in ipairs(PER) do
            local t = ST[name]
            if type(t) == "table" then
                for k in pairs(t) do
                    if type(k) == "number" and (k < 1 or k > 64 or not entity.is_player(k)) then
                        t[k] = nil
                    end
                end
                if count(t) > MAXENT then ST[name] = {} end
            end
        end
        for _, name in ipairs({"cache_data","cache_timestamp","cache_session","sgn"}) do
            local t = ST[name]
            if type(t) == "table" and count(t) > MAXENT then ST[name] = {} end
        end
    end
    local function clean_BRUTE()
        if type(BRUTE) ~= "table" then return end
        for _, name in ipairs({"_sf","_amp","_ap","_sk","SRC","warned"}) do
            local t = BRUTE[name]
            if type(t) == "table" then
                for k in pairs(t) do
                    if type(k) == "number" and (k < 1 or k > 64 or not entity.is_player(k)) then
                        t[k] = nil
                    end
                end
                if count(t) > MAXENT then BRUTE[name] = {} end
            end
        end
    end
    if plist and plist.set and not __RES_PLIST_GUARD then
        __RES_PLIST_GUARD = true
        local oset, oget = plist.set, plist.get
        plist.set = function(p, f, v)
            if type(p) ~= "number" or p < 1 or p > 64 then return end
            return oset(p, f, v)
        end
        plist.get = function(p, f)
            if type(p) ~= "number" or p < 1 or p > 64 then return nil end
            return oget(p, f)
        end
    end
    local last_clean = 0
    client.set_event_callback("setup_command", function()
        if globals.realtime() - last_clean < 5 then return end
        last_clean = globals.realtime()
        pcall(clean_ST); pcall(clean_BRUTE)
    end)
    client.set_event_callback("round_end",   function() pcall(clean_ST); pcall(clean_BRUTE) end)
    client.set_event_callback("round_start", function() pcall(clean_ST); pcall(clean_BRUTE) end)
    client.set_event_callback("level_init",  function() pcall(clean_ST); pcall(clean_BRUTE) end)
    pcall(clean_ST); pcall(clean_BRUTE)
    client.log("[RES] v10.0 anti-overflow activ | snapshot-uri pastrate in runda")
end

-- 41 ── auto-config la load
do
    local cfg = {
        { enable_resolver, true }, { crouch_fix, true }, { head_priority, true }, { threat_priority, true },
        { smart_cache, true }, { zeus_resolver, true }, { debug_log, true },
        { BRUTE.always_ui, true }, { BRUTE.pp11amp_ui, false }, { BRUTE.head_ui, true },
        { BRUTE.air_sp_ui, false }, { BRUTE.exp_sp_ui, false }, { BRUTE.skipbody_ui, false },
        { BRUTE.native_ui, false }, { BRUTE.assist_ui, false }, { BRUTE.bullet_ui, false },
        { BRUTE.pitch_ui, true }, { BRUTE.say_ui, false },
        { BRUTE.seedmin_ui, 50 },
        { BRUTE.bt_ui, 16 }, { BRUTE.snip_ui, 2 }, { BRUTE.lowhp_ui, 0 },
        { BRUTE.timing_ui, "net_update_end" }, { BRUTE.aim_ui, "Head-first (fara baim fortat)" },
        { BRUTE.ss_mode_ui, "Normal" }, { BRUTE.ffistruct_ui, "C_AnimLayer_t (pad 0x14, implicit)" },
    }
    local ok_n, bad_n = 0, 0
    for _, c in ipairs(cfg) do
        if c[1] ~= nil and pcall(ui.set, c[1], c[2]) then ok_n = ok_n + 1 else bad_n = bad_n + 1 end
    end
    client.log(string.format("[AUTOCFG] %d setari aplicate automat%s", ok_n,
        bad_n > 0 and (" (" .. bad_n .. " ignorate)") or ""))

    client.delay_call(2, function()
        local me = entity.get_local_player()
        if not me then client.log("[SELFTEST] fara jucator local, sar peste plist"); return end
        local t = entity.get_players(true)[1]
        if t then
            local w = pcall(plist.set, t, "Correction active", true)
            local okr, v = pcall(plist.get, t, "Correction active")
            client.log(string.format("[SELFTEST] plist scriere=%s citire=%s => %s", tostring(w),
                tostring(okr and v), (w and okr and v == true) and "OK" or "PROBLEMA"))
            pcall(test_ffi)
        else
            client.log("[SELFTEST] niciun inamic acum; plist se verifica la primul aim_fire")
        end
        client.log("[RES] gata: v10.0 ACTIV | Pure Deterministic Resolver | 3D Freestand + Air-Strafe Turn + SSG08 Head")
    end)
end

-- 42 ── restore wrapper
if __RES_ORIG_SEC then
    pcall(function() client.set_event_callback = __RES_ORIG_SEC end)
    __RES_ORIG_SEC = nil
end
