local vector = require 'vector'
local c_entity = require 'gamesense/entity'
local http = require 'gamesense/http'
local base64 = require 'gamesense/base64'
local clipboard = require 'gamesense/clipboard'
local steamworks = require 'gamesense/steamworks'

local client_set_event_callback, client_unset_event_callback = client.set_event_callback, client.unset_event_callback
local entity_get_local_player, entity_get_player_weapon, entity_get_prop = entity.get_local_player, entity.get_player_weapon, entity.get_prop
local ui_get, ui_set, ui_set_callback, ui_set_visible, ui_reference, ui_new_checkbox, ui_new_slider = ui.get, ui.set, ui.set_callback, ui.set_visible, ui.reference, ui.new_checkbox, ui.new_slider

local reference = {
    double_tap = {ui.reference('RAGE', 'Aimbot', 'Double tap')},
    duck_peek_assist = ui.reference('RAGE', 'Other', 'Duck peek assist'),
	pitch = {ui.reference('AA', 'Anti-aimbot angles', 'Pitch')},
    yaw_base = ui.reference('AA', 'Anti-aimbot angles', 'Yaw base'),
    yaw = {ui.reference('AA', 'Anti-aimbot angles', 'Yaw')},
    yaw_jitter = {ui.reference('AA', 'Anti-aimbot angles', 'Yaw jitter')},
    body_yaw = {ui.reference('AA', 'Anti-aimbot angles', 'Body yaw')},
    freestanding_body_yaw = ui.reference('AA', 'anti-aimbot angles', 'Freestanding body yaw'),
	edge_yaw = ui.reference('AA', 'Anti-aimbot angles', 'Edge yaw'),
	freestanding = {ui.reference('AA', 'Anti-aimbot angles', 'Freestanding')},
    roll = ui.reference('AA', 'Anti-aimbot angles', 'Roll'),
    on_shot_anti_aim = {ui.reference('AA', 'Other', 'On shot anti-aim')},
    slow_motion = {ui.reference('AA', 'Other', 'Slow motion')}
}

local globals_frametime = globals.frametime
local globals_tickinterval = globals.tickinterval
local entity_is_enemy = entity.is_enemy
local entity_is_dormant = entity.is_dormant
local entity_is_alive = entity.is_alive
local entity_get_origin = entity.get_origin
local entity_get_player_resource = entity.get_player_resource
local table_insert = table.insert
local math_floor = math.floor

local direction = 0
local anti_aim_on_use_direction = 0
local cheked_ticks = nil
local delayed_jitter = false

-- Runtime state is cleared between lives and rounds.
local ab_state = {
    phase = 1,
    enemy_phase = {},
    impact_tick = {},
    manual_keys = {},
    manual_direction = nil,
    last_impact_time = -999,
    impact_count = 0,
    way_step = 1,
    pkt_count = 0,
    last_choke_cycle = 0,
    sway_dir = 1,
    sway_ang = 58,
    def_until = -1,
    def_tick_start = -999,
    peek_threat = false,
    peek_until = -1,
    fs_side = 0,
    fs_best_yaw = 0,
    target_idx = nil,
    last_trace_tick = -1
}

local EXACT_AB_JITTER = { 43, -51, 33, -47, 25, -39 }
local EXACT_AB_CENTER = { -8, 11, -13, 9, -6, 12 }
local EXACT_AB_BODY   = { -116, 94, -68, 124, -84, 108 }
local EXACT_TANK_J    = { 44, -46, 41, -48, 36, -42 }
local EXACT_DEF_YAW   = { -126, 122, -96, 104 }

local E_POSE_PARAMETERS = {
    STRAFE_YAW = 0,
    STAND = 1,
    LEAN_YAW = 2,
    SPEED = 3,
    LADDER_YAW = 4,
    LADDER_SPEED = 5,
    JUMP_FALL = 6,
    MOVE_YAW = 7,
    MOVE_BLEND_CROUCH = 8,
    MOVE_BLEND_WALK = 9,
    MOVE_BLEND_RUN = 10,
    BODY_YAW = 11,
    BODY_PITCH = 12,
    AIM_BLEND_STAND_IDLE = 13,
    AIM_BLEND_STAND_WALK = 14,
    AIM_BLEND_STAND_RUN = 14,
    AIM_BLEND_CROUCH_IDLE = 16,
    AIM_BLEND_CROUCH_WALK = 17,
    DEATH_YAW = 18
}

local function contains(source, target)
	for id, name in pairs(ui.get(source)) do
		if name == target then
			return true
		end
	end

	return false
end

local function normalize_yaw(value)
    return (value + 180) % 360 - 180
end

local function reset_aa_runtime()
    cheked_ticks = nil
    ab_state.last_command, ab_state.random_packet, ab_state.random_state = nil, nil, nil
    ab_state.random_offset = 0
    direction, anti_aim_on_use_direction = 0, 0
    delayed_jitter = false
    ab_state.phase, ab_state.pkt_count, ab_state.way_step = 1, 0, 1
    ab_state.enemy_phase, ab_state.impact_tick, ab_state.manual_keys = {}, {}, {}
    ab_state.manual_direction = nil
    ab_state.last_impact_time, ab_state.impact_count = -999, 0
    ab_state.sway_dir, ab_state.sway_ang = 1, 58
    ab_state.def_until, ab_state.def_tick_start = -1, -999
    ab_state.peek_threat, ab_state.peek_until = false, -1
    ab_state.fs_side, ab_state.fs_best_yaw = 0, 0
    ab_state.fs_candidate, ab_state.fs_samples = 0, 0
    ab_state.target_idx, ab_state.last_trace_tick = nil, -1
end

local function is_defensive(index)
    local tb = entity.get_prop(index, 'm_nTickBase')
    if not tb then return false end
    local previous = cheked_ticks
    cheked_ticks = tb
    local now = globals.tickcount()
    if previous then
        local rollback = previous - tb
        -- A request or a nearby impact does not prove a tickbase shift.
        if rollback > 0 and rollback <= 16 then
            ab_state.def_until = now + rollback - 1
            ab_state.def_tick_start = now
        elseif math.abs(rollback) > 16 then
            ab_state.def_until = -1
        end
    end
    return now <= ab_state.def_until
end

local function update_tactical_awareness(self, eye_x, eye_y, eye_z, cam_yaw, vel_vec, spd2d)
    local now_tick = globals.tickcount()

    local enemies = entity.get_players(true)
    if not enemies or #enemies == 0 then
        ab_state.target_idx = nil
        ab_state.peek_threat = false
        ab_state.fs_side, ab_state.fs_best_yaw = 0, 0
        ab_state.peek_until, ab_state.last_trace_tick = -1, -1
        ab_state.fs_candidate, ab_state.fs_samples = 0, 0
        return
    end

    local best_enemy = nil
    local best_fov = 999
    for i = 1, #enemies do
        local en = enemies[i]
        if entity.is_alive(en) and not entity.is_dormant(en) then
            local ex, ey, ez = entity.get_origin(en)
            if ex then
                local ang_to = math.deg(math.atan2(ey - eye_y, ex - eye_x))
                local diff = (ang_to - cam_yaw) % 360
                if diff > 180 then diff = diff - 360 end
                local adiff = math.abs(diff)
                if adiff < best_fov then
                    best_fov = adiff
                    best_enemy = en
                end
            end
        end
    end

    local changed_target = ab_state.target_idx ~= best_enemy
    ab_state.target_idx = best_enemy
    if not best_enemy then
        ab_state.peek_threat = false
        ab_state.fs_side, ab_state.fs_best_yaw = 0, 0
        ab_state.peek_until, ab_state.last_trace_tick = -1, -1
        ab_state.fs_candidate, ab_state.fs_samples = 0, 0
        return
    end

    if changed_target then
        ab_state.fs_side, ab_state.fs_best_yaw = 0, 0
        ab_state.fs_candidate, ab_state.fs_samples = 0, 0
        ab_state.peek_threat, ab_state.peek_until = false, -1
    elseif now_tick >= ab_state.last_trace_tick and now_tick - ab_state.last_trace_tick < 4 then
        return
    end
    ab_state.last_trace_tick = now_tick
    local ex, ey, ez = entity.get_origin(best_enemy)
    if not ex then return end
    local e_eye_z = ez + (entity.get_prop(best_enemy, 'm_vecViewOffset[2]') or 64)
    local yaw_to_enemy = math.atan2(ey - eye_y, ex - eye_x)
    local deg_to_enemy = math.deg(yaw_to_enemy)
    local back_yaw = deg_to_enemy + 180

    -- Sample cover; these points are not reconstructed player hitboxes.
    local left_exposure, right_exposure = 0, 0
    for _, off_deg in ipairs({ -58, -36, -20, 20, 36, 58 }) do
        local world_rad = math.rad(back_yaw + off_deg)
        local hx = eye_x + math.cos(world_rad) * 24
        local hy = eye_y + math.sin(world_rad) * 24
        local frac = client.trace_line(best_enemy, ex, ey, e_eye_z, hx, hy, eye_z) or 1
        local dmg = 0
        if client.trace_bullet then
            local _, tdmg = client.trace_bullet(best_enemy, ex, ey, e_eye_z, hx, hy, eye_z, true)
            dmg = tdmg or 0
        end
        local score = frac * 50 + dmg
        if off_deg < 0 then
            left_exposure = left_exposure + score
        else
            right_exposure = right_exposure + score
        end
    end
    local candidate = math.abs(left_exposure - right_exposure) > 12
        and ((left_exposure < right_exposure) and -1 or 1) or 0
    if candidate == 0 then
        ab_state.fs_side, ab_state.fs_best_yaw = 0, 0
        ab_state.fs_candidate, ab_state.fs_samples = 0, 0
    else
        ab_state.fs_samples = (ab_state.fs_candidate == candidate) and (ab_state.fs_samples + 1) or 1
        ab_state.fs_candidate = candidate
        if ab_state.fs_samples >= 2 then
            ab_state.fs_side, ab_state.fs_best_yaw = candidate, candidate * 14
        end
    end

    if spd2d > 35 then
        local ti = globals.tickinterval() or 0.015625
        local pred_x = eye_x + (vel_vec.x or 0) * ti * 6
        local pred_y = eye_y + (vel_vec.y or 0) * ti * 6
        local pred_z = eye_z
        if client.trace_bullet then
            local _, dmg = client.trace_bullet(best_enemy, ex, ey, e_eye_z, pred_x, pred_y, pred_z, true)
            if dmg and dmg > 0 then
                ab_state.peek_threat = true
                ab_state.peek_until = now_tick + 8
                return
            end
        end
        local f_peek = client.trace_line(best_enemy, ex, ey, e_eye_z, pred_x, pred_y, pred_z)
        if f_peek and f_peek > 0.92 then
            ab_state.peek_threat = true
            ab_state.peek_until = now_tick + 6
            return
        end
    end
    ab_state.peek_threat = now_tick <= (ab_state.peek_until or -1)
end

local settings = {}
local anti_aim_settings = {}
local anti_aim_states = {'Global', 'Standing', 'Moving', 'Slow motion', 'Crouching', 'Crouching & moving', 'In air', 'In air & crouching', 'No exploits', 'On use'}
local anti_aim_different = {'', ' ', '  ', '   ', '    ', '     ', '      ', '       ', '        ', '         '}

current_tab = ui.new_combobox('AA', 'Anti-aimbot angles', 'Tabs', {'Home', 'Anti-Aim', 'Misc/Vis'})
local text1 = ui.new_label('AA', 'Anti-aimbot angles', 'mytools for gs ~ \a95b806ffbeta test', 'string')
local text2 = ui.new_label('AA', 'Anti-aimbot angles', 'last upd ~ 23.10.2023', 'string')
local text3 = ui.new_label('AA', 'Anti-aimbot angles', 'if you find a bug, write to discord ticket', 'string')
settings.anti_aim_state = ui.new_combobox('AA', 'Anti-aimbot angles', 'Anti-aimbot state', anti_aim_states)

local master_switch = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Log Aimbot Shots')
local console_filter = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Console Filter')
local anim_breakerx = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Animation Breaker')
local force_safe_point = ui.reference('RAGE', 'Aimbot', 'Force safe point')
local trashtalk = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Trash Talk')
local clantagchanger = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Clan Tag')
local fastladder = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Fast Ladder')
local hitmarker = ui.new_checkbox('AA', 'Anti-aimbot angles', '3D Hit Marker')

local aspectratio = ui.new_slider('AA', 'Anti-aimbot angles', 'Aspect Ratio', 0, 200, 0, true, nil, 0.01, {[0] = "Off"})

local override_zoom_fov = ui_reference("Misc", "Miscellaneous", "Override zoom FOV")
local cache = ui.get(override_zoom_fov)
local scope_fov = ui_new_slider('AA', 'Anti-aimbot angles', "Second Zoom FOV", -0, 100, 0, true, '%', 1, {[0] = "Off"})

for i = 1, #anti_aim_states do
    anti_aim_settings[i] = {
        override_state = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Override ' .. string.lower(anti_aim_states[i])),
        pitch1 = ui.new_combobox('AA', 'Anti-aimbot angles', 'Pitch' .. anti_aim_different[i], 'Off', 'Default', 'Up', 'Down', 'Minimal', 'Random', 'Custom'),
        pitch2 = ui.new_slider('AA', 'Anti-aimbot angles', '\nPitch' .. anti_aim_different[i], -89, 89, 0, true, '°'),
        yaw_base = ui.new_combobox('AA', 'Anti-aimbot angles', 'Yaw base' .. anti_aim_different[i], 'Local view', 'At targets'),
        yaw1 = ui.new_combobox('AA', 'Anti-aimbot angles', 'Yaw' .. anti_aim_different[i], 'Off', '180', 'Spin', 'Static', '180 Z', 'Crosshair'),
        yaw2_left = ui.new_slider('AA', 'Anti-aimbot angles', 'Yaw left' .. anti_aim_different[i], -180, 180, 0, true, '°'),
        yaw2_right = ui.new_slider('AA', 'Anti-aimbot angles', 'Yaw right' .. anti_aim_different[i], -180, 180, 0, true, '°'),
        yaw2_randomize = ui.new_slider('AA', 'Anti-aimbot angles', 'Yaw randomize' .. anti_aim_different[i], 0, 180, 0, true, '°'),
        yaw_jitter1 = ui.new_combobox('AA', 'Anti-aimbot angles', 'Yaw jitter' .. anti_aim_different[i], 'Off', 'Offset', 'Center', 'Random', 'Skitter', 'Delay', '3-Way', '5-Way', 'Anti-Brute', 'Tank-AA', 'Adaptive', 'Micro-Sway'),
        yaw_jitter2_left = ui.new_slider('AA', 'Anti-aimbot angles', 'Yaw jitter left' .. anti_aim_different[i], -180, 180, 0, true, '°'),
        yaw_jitter2_right = ui.new_slider('AA', 'Anti-aimbot angles', 'Yaw jitter right' .. anti_aim_different[i], -180, 180, 0, true, '°'),
        yaw_jitter2_randomize = ui.new_slider('AA', 'Anti-aimbot angles', 'Yaw jitter randomize' .. anti_aim_different[i], 0, 180, 0, true, '°'),
        yaw_jitter2_delay = ui.new_slider('AA', 'Anti-aimbot angles', 'Yaw jitter delay' .. anti_aim_different[i], 2, 10, 2, true, 't'),
        body_yaw1 = ui.new_combobox('AA', 'Anti-aimbot angles', 'Body yaw' .. anti_aim_different[i], 'Off', 'Opposite', 'Jitter', 'Static', 'Opposite Jitter', 'Anti-Brute', 'Sway', 'Adaptive Desync'),
        body_yaw2 = ui.new_slider('AA', 'Anti-aimbot angles', 'Body Yaw' .. anti_aim_different[i], -180, 180, 0, true, '°'),
        freestanding_body_yaw = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Freestanding body yaw' .. anti_aim_different[i]),
        roll = ui.new_slider('AA', 'Anti-aimbot angles', 'Roll' .. anti_aim_different[i], -45, 45, 0, true, '°'),
        force_defensive = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Force defensive' .. anti_aim_different[i]),
        defensive_anti_aimbot = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aB6B665FF✥ Defensive AA' .. anti_aim_different[i]),
        defensive_pitch = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aB6B665FF· Pitch' .. anti_aim_different[i]),
        defensive_pitch1 = ui.new_combobox('AA', 'Anti-aimbot angles', '\n· Pitch 2' .. anti_aim_different[i], 'Off', 'Default', 'Up', 'Down', 'Minimal', 'Random', 'Custom'),
        defensive_pitch2 = ui.new_slider('AA', 'Anti-aimbot angles', '\n· Pitch 3' .. anti_aim_different[i], -89, 89, 0, true, '°'),
        defensive_pitch3 = ui.new_slider('AA', 'Anti-aimbot angles', '\n· Pitch 4' .. anti_aim_different[i], -89, 89, 0, true, '°'),
        defensive_yaw = ui.new_checkbox('AA', 'Anti-aimbot angles', '\aB6B665FF· Yaw' .. anti_aim_different[i]),
        defensive_yaw1 = ui.new_combobox('AA', 'Anti-aimbot angles', '· Yaw 1' .. anti_aim_different[i], '180', 'Spin', '180 Z', 'Sideways', 'Random', '3-Way Flick', 'Anti-Resolver', 'Hidden-Head Flick'),
        defensive_yaw2 = ui.new_slider('AA', 'Anti-aimbot angles', '· Yaw 2' .. anti_aim_different[i], -180, 180, 0, true, '°')
    }
end

settings.warmup_disabler = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Warmup disabler')
settings.avoid_backstab = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Avoid backstab')
settings.safe_head_in_air = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Safe head in air')
settings.manual_forward = ui.new_hotkey('AA', 'Anti-aimbot angles', 'Manual forward')
settings.manual_right = ui.new_hotkey('AA', 'Anti-aimbot angles', 'Manual right')
settings.manual_left = ui.new_hotkey('AA', 'Anti-aimbot angles', 'Manual left')
settings.edge_yaw = ui.new_hotkey('AA', 'Anti-aimbot angles', 'Edge yaw')
settings.freestanding = ui.new_hotkey('AA', 'Anti-aimbot angles', 'Freestanding')
settings.freestanding_conditions = ui.new_multiselect('AA', 'Anti-aimbot angles', '\nFreestanding', 'Standing', 'Moving', 'Slow motion', 'Crouching', 'In air')
settings.tweaks = ui.new_multiselect('AA', 'Anti-aimbot angles', '\nTweaks', 'Off jitter while freestanding', 'Off jitter on manual')
settings.anti_brute_head = ui.new_checkbox('AA', 'Anti-aimbot angles', '\a95b806ff★ Unhittable Anti-Brute Head')
settings.anti_move_res = ui.new_checkbox('AA', 'Anti-aimbot angles', '\a95b806ff★ Anti-Move-Yaw & Layer6 Breaker')
settings.defensive_peek = ui.new_checkbox('AA', 'Anti-aimbot angles', '\a95b806ff★ Dynamic Defensive on Peek/Threat')

local data = {
    integers = {
        settings.anti_aim_state,
        anti_aim_settings[1].override_state, anti_aim_settings[2].override_state, anti_aim_settings[3].override_state, anti_aim_settings[4].override_state, anti_aim_settings[5].override_state, anti_aim_settings[6].override_state, anti_aim_settings[7].override_state, anti_aim_settings[8].override_state, anti_aim_settings[9].override_state, anti_aim_settings[10].override_state,
        anti_aim_settings[1].force_defensive, anti_aim_settings[2].force_defensive, anti_aim_settings[3].force_defensive, anti_aim_settings[4].force_defensive, anti_aim_settings[5].force_defensive, anti_aim_settings[6].force_defensive, anti_aim_settings[7].force_defensive, anti_aim_settings[8].force_defensive, anti_aim_settings[9].force_defensive, anti_aim_settings[10].force_defensive,
        anti_aim_settings[1].pitch1, anti_aim_settings[2].pitch1, anti_aim_settings[3].pitch1, anti_aim_settings[4].pitch1, anti_aim_settings[5].pitch1, anti_aim_settings[6].pitch1, anti_aim_settings[7].pitch1, anti_aim_settings[8].pitch1, anti_aim_settings[9].pitch1, anti_aim_settings[10].pitch1,
        anti_aim_settings[1].pitch2, anti_aim_settings[2].pitch2, anti_aim_settings[3].pitch2, anti_aim_settings[4].pitch2, anti_aim_settings[5].pitch2, anti_aim_settings[6].pitch2, anti_aim_settings[7].pitch2, anti_aim_settings[8].pitch2, anti_aim_settings[9].pitch2, anti_aim_settings[10].pitch2,
        anti_aim_settings[1].yaw_base, anti_aim_settings[2].yaw_base, anti_aim_settings[3].yaw_base, anti_aim_settings[4].yaw_base, anti_aim_settings[5].yaw_base, anti_aim_settings[6].yaw_base, anti_aim_settings[7].yaw_base, anti_aim_settings[8].yaw_base, anti_aim_settings[9].yaw_base, anti_aim_settings[10].yaw_base,
        anti_aim_settings[1].yaw1, anti_aim_settings[2].yaw1, anti_aim_settings[3].yaw1, anti_aim_settings[4].yaw1, anti_aim_settings[5].yaw1, anti_aim_settings[6].yaw1, anti_aim_settings[7].yaw1, anti_aim_settings[8].yaw1, anti_aim_settings[9].yaw1, anti_aim_settings[10].yaw1,
        anti_aim_settings[1].yaw2_left, anti_aim_settings[2].yaw2_left, anti_aim_settings[3].yaw2_left, anti_aim_settings[4].yaw2_left, anti_aim_settings[5].yaw2_left, anti_aim_settings[6].yaw2_left, anti_aim_settings[7].yaw2_left, anti_aim_settings[8].yaw2_left, anti_aim_settings[9].yaw2_left, anti_aim_settings[10].yaw2_left,
        anti_aim_settings[1].yaw2_right, anti_aim_settings[2].yaw2_right, anti_aim_settings[3].yaw2_right, anti_aim_settings[4].yaw2_right, anti_aim_settings[5].yaw2_right, anti_aim_settings[6].yaw2_right, anti_aim_settings[7].yaw2_right, anti_aim_settings[8].yaw2_right, anti_aim_settings[9].yaw2_right, anti_aim_settings[10].yaw2_right,
        anti_aim_settings[1].yaw2_randomize, anti_aim_settings[2].yaw2_randomize, anti_aim_settings[3].yaw2_randomize, anti_aim_settings[4].yaw2_randomize, anti_aim_settings[5].yaw2_randomize, anti_aim_settings[6].yaw2_randomize, anti_aim_settings[7].yaw2_randomize, anti_aim_settings[8].yaw2_randomize, anti_aim_settings[9].yaw2_randomize, anti_aim_settings[10].yaw2_randomize,
        anti_aim_settings[1].yaw_jitter1, anti_aim_settings[2].yaw_jitter1, anti_aim_settings[3].yaw_jitter1, anti_aim_settings[4].yaw_jitter1, anti_aim_settings[5].yaw_jitter1, anti_aim_settings[6].yaw_jitter1, anti_aim_settings[7].yaw_jitter1, anti_aim_settings[8].yaw_jitter1, anti_aim_settings[9].yaw_jitter1, anti_aim_settings[10].yaw_jitter1,
        anti_aim_settings[1].yaw_jitter2_left, anti_aim_settings[2].yaw_jitter2_left, anti_aim_settings[3].yaw_jitter2_left, anti_aim_settings[4].yaw_jitter2_left, anti_aim_settings[5].yaw_jitter2_left, anti_aim_settings[6].yaw_jitter2_left, anti_aim_settings[7].yaw_jitter2_left, anti_aim_settings[8].yaw_jitter2_left, anti_aim_settings[9].yaw_jitter2_left, anti_aim_settings[10].yaw_jitter2_left,
        anti_aim_settings[1].yaw_jitter2_right, anti_aim_settings[2].yaw_jitter2_right, anti_aim_settings[3].yaw_jitter2_right, anti_aim_settings[4].yaw_jitter2_right, anti_aim_settings[5].yaw_jitter2_right, anti_aim_settings[6].yaw_jitter2_right, anti_aim_settings[7].yaw_jitter2_right, anti_aim_settings[8].yaw_jitter2_right, anti_aim_settings[9].yaw_jitter2_right, anti_aim_settings[10].yaw_jitter2_right,
        anti_aim_settings[1].yaw_jitter2_randomize, anti_aim_settings[2].yaw_jitter2_randomize, anti_aim_settings[3].yaw_jitter2_randomize, anti_aim_settings[4].yaw_jitter2_randomize, anti_aim_settings[5].yaw_jitter2_randomize, anti_aim_settings[6].yaw_jitter2_randomize, anti_aim_settings[7].yaw_jitter2_randomize, anti_aim_settings[8].yaw_jitter2_randomize, anti_aim_settings[9].yaw_jitter2_randomize, anti_aim_settings[10].yaw_jitter2_randomize,
        anti_aim_settings[1].yaw_jitter2_delay, anti_aim_settings[2].yaw_jitter2_delay, anti_aim_settings[3].yaw_jitter2_delay, anti_aim_settings[4].yaw_jitter2_delay, anti_aim_settings[5].yaw_jitter2_delay, anti_aim_settings[6].yaw_jitter2_delay, anti_aim_settings[7].yaw_jitter2_delay, anti_aim_settings[8].yaw_jitter2_delay, anti_aim_settings[9].yaw_jitter2_delay, anti_aim_settings[10].yaw_jitter2_delay,
        anti_aim_settings[1].body_yaw1, anti_aim_settings[2].body_yaw1, anti_aim_settings[3].body_yaw1, anti_aim_settings[4].body_yaw1, anti_aim_settings[5].body_yaw1, anti_aim_settings[6].body_yaw1, anti_aim_settings[7].body_yaw1, anti_aim_settings[8].body_yaw1, anti_aim_settings[9].body_yaw1, anti_aim_settings[10].body_yaw1,
        anti_aim_settings[1].body_yaw2, anti_aim_settings[2].body_yaw2, anti_aim_settings[3].body_yaw2, anti_aim_settings[4].body_yaw2, anti_aim_settings[5].body_yaw2, anti_aim_settings[6].body_yaw2, anti_aim_settings[7].body_yaw2, anti_aim_settings[8].body_yaw2, anti_aim_settings[9].body_yaw2, anti_aim_settings[10].body_yaw2,
        anti_aim_settings[1].freestanding_body_yaw, anti_aim_settings[2].freestanding_body_yaw, anti_aim_settings[3].freestanding_body_yaw, anti_aim_settings[4].freestanding_body_yaw, anti_aim_settings[5].freestanding_body_yaw, anti_aim_settings[6].freestanding_body_yaw, anti_aim_settings[7].freestanding_body_yaw, anti_aim_settings[8].freestanding_body_yaw, anti_aim_settings[9].freestanding_body_yaw, anti_aim_settings[10].freestanding_body_yaw,
        anti_aim_settings[1].roll, anti_aim_settings[2].roll, anti_aim_settings[3].roll, anti_aim_settings[4].roll, anti_aim_settings[5].roll, anti_aim_settings[6].roll, anti_aim_settings[7].roll, anti_aim_settings[8].roll, anti_aim_settings[9].roll, anti_aim_settings[10].roll,
        anti_aim_settings[1].defensive_anti_aimbot, anti_aim_settings[2].defensive_anti_aimbot, anti_aim_settings[3].defensive_anti_aimbot, anti_aim_settings[4].defensive_anti_aimbot, anti_aim_settings[5].defensive_anti_aimbot, anti_aim_settings[6].defensive_anti_aimbot, anti_aim_settings[7].defensive_anti_aimbot, anti_aim_settings[8].defensive_anti_aimbot, anti_aim_settings[9].defensive_anti_aimbot, anti_aim_settings[10].defensive_anti_aimbot,
        anti_aim_settings[1].defensive_pitch, anti_aim_settings[2].defensive_pitch, anti_aim_settings[3].defensive_pitch, anti_aim_settings[4].defensive_pitch, anti_aim_settings[5].defensive_pitch, anti_aim_settings[6].defensive_pitch, anti_aim_settings[7].defensive_pitch, anti_aim_settings[8].defensive_pitch, anti_aim_settings[9].defensive_pitch, anti_aim_settings[10].defensive_pitch,
        anti_aim_settings[1].defensive_pitch1, anti_aim_settings[2].defensive_pitch1, anti_aim_settings[3].defensive_pitch1, anti_aim_settings[4].defensive_pitch1, anti_aim_settings[5].defensive_pitch1, anti_aim_settings[6].defensive_pitch1, anti_aim_settings[7].defensive_pitch1, anti_aim_settings[8].defensive_pitch1, anti_aim_settings[9].defensive_pitch1, anti_aim_settings[10].defensive_pitch1,
        anti_aim_settings[1].defensive_pitch2, anti_aim_settings[2].defensive_pitch2, anti_aim_settings[3].defensive_pitch2, anti_aim_settings[4].defensive_pitch2, anti_aim_settings[5].defensive_pitch2, anti_aim_settings[6].defensive_pitch2, anti_aim_settings[7].defensive_pitch2, anti_aim_settings[8].defensive_pitch2, anti_aim_settings[9].defensive_pitch2, anti_aim_settings[10].defensive_pitch2,
        anti_aim_settings[1].defensive_pitch3, anti_aim_settings[2].defensive_pitch3, anti_aim_settings[3].defensive_pitch3, anti_aim_settings[4].defensive_pitch3, anti_aim_settings[5].defensive_pitch3, anti_aim_settings[6].defensive_pitch3, anti_aim_settings[7].defensive_pitch3, anti_aim_settings[8].defensive_pitch3, anti_aim_settings[9].defensive_pitch3, anti_aim_settings[10].defensive_pitch3,
        anti_aim_settings[1].defensive_yaw, anti_aim_settings[2].defensive_yaw, anti_aim_settings[3].defensive_yaw, anti_aim_settings[4].defensive_yaw, anti_aim_settings[5].defensive_yaw, anti_aim_settings[6].defensive_yaw, anti_aim_settings[7].defensive_yaw, anti_aim_settings[8].defensive_yaw, anti_aim_settings[9].defensive_yaw, anti_aim_settings[10].defensive_yaw,
        anti_aim_settings[1].defensive_yaw1, anti_aim_settings[2].defensive_yaw1, anti_aim_settings[3].defensive_yaw1, anti_aim_settings[4].defensive_yaw1, anti_aim_settings[5].defensive_yaw1, anti_aim_settings[6].defensive_yaw1, anti_aim_settings[7].defensive_yaw1, anti_aim_settings[8].defensive_yaw1, anti_aim_settings[9].defensive_yaw1, anti_aim_settings[10].defensive_yaw1,
        anti_aim_settings[1].defensive_yaw2, anti_aim_settings[2].defensive_yaw2, anti_aim_settings[3].defensive_yaw2, anti_aim_settings[4].defensive_yaw2, anti_aim_settings[5].defensive_yaw2, anti_aim_settings[6].defensive_yaw2, anti_aim_settings[7].defensive_yaw2, anti_aim_settings[8].defensive_yaw2, anti_aim_settings[9].defensive_yaw2, anti_aim_settings[10].defensive_yaw2,
        settings.avoid_backstab,
        settings.safe_head_in_air,
        settings.freestanding_conditions,
        settings.tweaks, master_switch, console_filter, anim_breakerx, scope_fov, trashtalk, aspectratio, hitmarker, fastladder, clantagchanger, settings.warmup_disabler
    }
}

local function import(text)
    local status, config =
        pcall(
        function()
            return json.parse(base64.decode(text))
        end
    )

    if not status or status == nil then
        client.color_log(255, 0, 0, "mytools ~\0")
	    client.color_log(200, 200, 200, " error while importing!")
        return
    end

    if config ~= nil then
        for k, v in pairs(config) do
            k = ({[1] = 'integers'})[k]

            for k2, v2 in pairs(v) do
                if k == 'integers' then
                    ui.set(data[k][k2], v2)
                end
            end
        end
    end

    client.color_log(124, 252, 0, "mytools ~\0")
	client.color_log(200, 200, 200, " config successfully imported!")

end

client.set_event_callback('setup_command', function(cmd)
    local self = entity.get_local_player()

    if not self or not entity.is_alive(self) then return end
    if entity.get_player_weapon(self) == nil then return end

    local using = false
    local anti_aim_on_use = false
    local is_defusing = false

    local inverted = (entity.get_prop(self, "m_flPoseParameter", 11) or 0.5) * 120 - 60

    local is_planting = entity.get_prop(self, 'm_bInBombZone') == 1 and entity.get_classname(entity.get_player_weapon(self)) == 'CC4' and entity.get_prop(self, 'm_iTeamNum') == 2
    local CPlantedC4 = entity.get_all('CPlantedC4')[1]

    local eye_x, eye_y, eye_z = client.eye_position()
	local pitch, yaw = client.camera_angles()

    local sin_pitch = math.sin(math.rad(pitch))
	local cos_pitch = math.cos(math.rad(pitch))

	local sin_yaw = math.sin(math.rad(yaw))
	local cos_yaw = math.cos(math.rad(yaw))

    local direction_vector = {cos_pitch * cos_yaw, cos_pitch * sin_yaw, -sin_pitch}

    local fraction, entity_index = client.trace_line(self, eye_x, eye_y, eye_z, eye_x + (direction_vector[1] * 8192), eye_y + (direction_vector[2] * 8192), eye_z + (direction_vector[3] * 8192))

    if CPlantedC4 ~= nil then
        local dist_to_c4 = vector(entity.get_prop(self, 'm_vecOrigin')):dist(vector(entity.get_prop(CPlantedC4, 'm_vecOrigin')))

        if entity.get_prop(CPlantedC4, 'm_bBombDefused') == 1 then dist_to_c4 = 56 end

        is_defusing = dist_to_c4 < 56 and entity.get_prop(self, 'm_iTeamNum') == 3
    end

    if entity_index and entity_index > 0 then
        if vector(entity.get_prop(self, 'm_vecOrigin')):dist(vector(entity.get_prop(entity_index, 'm_vecOrigin'))) < 146 then
            using = entity.get_classname(entity_index) ~= 'CWorld' and entity.get_classname(entity_index) ~= 'CFuncBrush' and entity.get_classname(entity_index) ~= 'CCSPlayer'
        end
    end

    local vel_vec = vector(entity.get_prop(self, 'm_vecVelocity'))
    local spd2d = vel_vec:length2d()
    local airborne = cmd.in_jump == 1 or bit.band(entity.get_prop(self, 'm_fFlags') or 0, 1) == 0
    local crouched = (entity.get_prop(self, 'm_flDuckAmount') or 0) >= 0.8 or ui.get(reference.duck_peek_assist)
    local moving = spd2d > 2
    local slow = ui.get(reference.slow_motion[1]) and ui.get(reference.slow_motion[2])
    local dt_active = ui.get(reference.double_tap[1]) and ui.get(reference.double_tap[2])
    local hs_active = ui.get(reference.on_shot_anti_aim[1]) and ui.get(reference.on_shot_anti_aim[2])
    local movement_state = airborne and (crouched and 8 or 7)
        or (crouched and (moving and 6 or 5) or (moving and (slow and 4 or 3) or 2))
    freestanding_state_id = airborne and 5 or (crouched and 4 or (moving and (slow and 3 or 2) or 1))
    if cmd.in_use == 1 and not using and not is_planting and not is_defusing and ui.get(anti_aim_settings[10].override_state) then
        cmd.in_use = 0
        anti_aim_on_use, state_id = true, 10
    elseif not dt_active and not hs_active and ui.get(anti_aim_settings[9].override_state) then
        state_id = 9
    else
        state_id = ui.get(anti_aim_settings[movement_state].override_state) and movement_state or 1
    end

    local manual_refs = {settings.manual_left, settings.manual_right, settings.manual_forward}
    local manual_angles = {-90, 90, 180}
    for i = 1, #manual_refs do
        ui.set(manual_refs[i], 'On hotkey')
        local pressed = ui.get(manual_refs[i])
        if pressed and not ab_state.manual_keys[i] then
            ab_state.manual_direction = ab_state.manual_direction ~= manual_angles[i] and manual_angles[i] or nil
        end
        ab_state.manual_keys[i] = pressed
    end
    local is_manual_dir = ab_state.manual_direction ~= nil and not anti_aim_on_use
    update_tactical_awareness(self, eye_x, eye_y, eye_z, yaw, vel_vec, spd2d)
    local active_phase = (ab_state.target_idx and (ab_state.enemy_phase[ab_state.target_idx] or 1)) or ab_state.phase
    local force_def = ui.get(anti_aim_settings[state_id].force_defensive)
    if ui.get(settings.defensive_peek) and (dt_active or hs_active) then
        if ab_state.peek_threat or state_id == 6 or state_id == 7 or state_id == 8 or (globals.realtime() - ab_state.last_impact_time < 1.0) then
            force_def = true
        end
    end
    if force_def and (dt_active or hs_active) and not anti_aim_on_use and not is_manual_dir then
        cmd.force_defensive = true
    end
    local choked_now = cmd.chokedcommands or 0
    local is_defensive_active = globals.tickcount() <= ab_state.def_until

    if choked_now == 0 and ab_state.last_command ~= cmd.command_number then
        ab_state.last_command = cmd.command_number
        ab_state.pkt_count = ab_state.pkt_count + 1
        ab_state.way_step = (ab_state.pkt_count % 6) + 1
        ab_state.sway_ang = ab_state.sway_ang + ab_state.sway_dir * 6
        if ab_state.sway_ang >= 58 then
            ab_state.sway_ang = 58
            ab_state.sway_dir = -1
        elseif ab_state.sway_ang <= -58 then
            ab_state.sway_ang = -58
            ab_state.sway_dir = 1
        end
    end

    local cfg = anti_aim_settings[state_id]
    ui.set(reference.pitch[1], ui.get(cfg.pitch1))
    ui.set(reference.pitch[2], ui.get(cfg.pitch2))
    ui.set(reference.yaw_base, is_manual_dir and 'Local view' or ui.get(cfg.yaw_base))
    ui.set(reference.yaw[1], is_manual_dir and '180' or ui.get(cfg.yaw1))

    local delay_mode = ui.get(cfg.yaw1) ~= 'Off' and ui.get(cfg.yaw_jitter1) == 'Delay'
    local left = ui.get(delay_mode and cfg.yaw_jitter2_left or cfg.yaw2_left)
    local right = ui.get(delay_mode and cfg.yaw_jitter2_right or cfg.yaw2_right)
    local randomize = ui.get(delay_mode and cfg.yaw_jitter2_randomize or cfg.yaw2_randomize)
    if ab_state.random_packet ~= ab_state.pkt_count or ab_state.random_state ~= state_id then
        ab_state.random_offset = math.random(-randomize, randomize)
        local jitter_randomize = ui.get(cfg.yaw_jitter2_randomize)
        ab_state.jitter_random_offset = math.random(-jitter_randomize, jitter_randomize)
        ab_state.random_packet, ab_state.random_state = ab_state.pkt_count, state_id
    end
    local base_yaw = normalize_yaw((inverted > 0 and left or right) + ab_state.random_offset)
    direction = is_manual_dir and ab_state.manual_direction or base_yaw
    anti_aim_on_use_direction = base_yaw

    local jmode = ui.get(anti_aim_settings[state_id].yaw_jitter1)
    local bmode = ui.get(anti_aim_settings[state_id].body_yaw1)
    local final_yaw_offset = anti_aim_on_use == false and direction or anti_aim_on_use_direction

    if ui.get(settings.anti_move_res) and not is_manual_dir and not anti_aim_on_use and spd2d > 25 then
        local phase_shift = EXACT_AB_CENTER[active_phase] or -8
        local micro = (ab_state.pkt_count % 2 == 0) and phase_shift or -math.floor(phase_shift * 0.75)
        final_yaw_offset = final_yaw_offset + micro + (ab_state.fs_best_yaw or 0)
    elseif not is_manual_dir and not anti_aim_on_use and ab_state.fs_side ~= 0 and spd2d <= 25 then
        final_yaw_offset = final_yaw_offset + (ab_state.fs_best_yaw or (ab_state.fs_side * 12))
    end

    local native_jmode = jmode
    local custom_jval = nil
    local jl_cfg = ui.get(anti_aim_settings[state_id].yaw_jitter2_left)
    local jr_cfg = ui.get(anti_aim_settings[state_id].yaw_jitter2_right)
    local jrand = ui.get(anti_aim_settings[state_id].yaw_jitter2_randomize)
    local det_mod = (jrand > 0) and (((ab_state.pkt_count % 3) - 1) * jrand) or 0
    if jmode == '3-Way' then
        native_jmode = 'Off'
        local w3 = ({ jl_cfg, math.floor((jl_cfg + jr_cfg) * 0.5), jr_cfg })[(ab_state.pkt_count % 3) + 1]
        final_yaw_offset = final_yaw_offset + w3 + det_mod
        custom_jval = 0
    elseif jmode == '5-Way' then
        native_jmode = 'Off'
        local w5 = ({ jl_cfg, math.floor(jl_cfg * 0.55), 0, math.floor(jr_cfg * 0.55), jr_cfg })[(ab_state.pkt_count % 5) + 1]
        final_yaw_offset = final_yaw_offset + w5 + det_mod
        custom_jval = 0
    elseif jmode == 'Anti-Brute' then
        native_jmode = 'Center'
        local base_j = EXACT_AB_JITTER[active_phase] or 43
        custom_jval = base_j + det_mod
        final_yaw_offset = final_yaw_offset + (EXACT_AB_CENTER[active_phase] or -8)
    elseif jmode == 'Tank-AA' then
        native_jmode = 'Center'
        local tank_j = EXACT_TANK_J[((ab_state.pkt_count + active_phase) % 6) + 1] or 44
        custom_jval = tank_j
        final_yaw_offset = final_yaw_offset + ((ab_state.pkt_count % 2 == 0) and -7 or 9)
    elseif jmode == 'Adaptive' then
        native_jmode = 'Center'
        local adapt_base = (spd2d > 135) and 45 or ((spd2d > 5) and 39 or 49)
        if (active_phase % 2) == 0 then adapt_base = -adapt_base end
        custom_jval = adapt_base + det_mod
    elseif jmode == 'Micro-Sway' then
        native_jmode = 'Offset'
        custom_jval = ((ab_state.pkt_count % 2 == 0) and jl_cfg or jr_cfg)
    end

    if is_manual_dir and contains(settings.tweaks, 'Off jitter on manual') then
        final_yaw_offset = ab_state.manual_direction
    end
    final_yaw_offset = normalize_yaw(final_yaw_offset)

    ui.set(reference.yaw[2], final_yaw_offset)
    ui.set(reference.yaw_jitter[1], (is_manual_dir and contains(settings.tweaks, 'Off jitter on manual') or jmode == 'Delay' or ui.get(anti_aim_settings[state_id].yaw1) == 'Off') and 'Off' or native_jmode)

    if custom_jval ~= nil then
        if custom_jval > 180 then custom_jval = 180 elseif custom_jval < -180 then custom_jval = -180 end
        ui.set(reference.yaw_jitter[2], ui.get(anti_aim_settings[state_id].yaw1) ~= 'Off' and custom_jval or 0)
    else
        local native_value = (inverted > 0 and jl_cfg or jr_cfg) + ab_state.jitter_random_offset
        ui.set(reference.yaw_jitter[2], ui.get(cfg.yaw1) ~= 'Off' and math.max(-180, math.min(180, native_value)) or 0)
    end

    delayed_jitter = math.floor(ab_state.pkt_count / ui.get(cfg.yaw_jitter2_delay)) % 2 == 1

    local by_cfg = ui.get(anti_aim_settings[state_id].body_yaw2)
    if is_manual_dir and contains(settings.tweaks, 'Off jitter on manual') then
        ui.set(reference.body_yaw[1], 'Opposite')
        ui.set(reference.body_yaw[2], 0)
    elseif ui.get(anti_aim_settings[state_id].yaw1) ~= 'Off' and jmode == 'Delay' then
        if dt_active or hs_active then
            ui.set(reference.body_yaw[1], 'Static')
            ui.set(reference.body_yaw[2], delayed_jitter and -90 or 90)
        else
            ui.set(reference.body_yaw[1], 'Jitter')
            ui.set(reference.body_yaw[2], -40)
        end
    elseif bmode == 'Opposite Jitter' then
        if (ab_state.pkt_count % 2) == 0 then
            ui.set(reference.body_yaw[1], 'Opposite')
            ui.set(reference.body_yaw[2], 0)
        else
            ui.set(reference.body_yaw[1], 'Jitter')
            local oj_val = EXACT_AB_BODY[active_phase] or -116
            ui.set(reference.body_yaw[2], oj_val)
        end
    elseif bmode == 'Anti-Brute' then
        ui.set(reference.body_yaw[1], 'Jitter')
        local ab_by = EXACT_AB_BODY[active_phase] or -116
        if ab_state.fs_side ~= 0 then
            ab_by = math.abs(ab_by) * ab_state.fs_side
        elseif (ab_state.pkt_count % 3) == 0 then
            ab_by = -ab_by
        end
        ui.set(reference.body_yaw[2], ab_by)
    elseif bmode == 'Sway' then
        ui.set(reference.body_yaw[1], 'Static')
        ui.set(reference.body_yaw[2], ab_state.sway_ang * 2)
    elseif bmode == 'Adaptive Desync' then
        if spd2d < 4 then
            ui.set(reference.body_yaw[1], (ab_state.pkt_count % 3 == 0) and 'Opposite' or 'Jitter')
            ui.set(reference.body_yaw[2], EXACT_AB_BODY[active_phase] or -116)
        else
            ui.set(reference.body_yaw[1], 'Jitter')
            ui.set(reference.body_yaw[2], ({ -94, 112, -76, 104, -88, 118 })[active_phase] or -94)
        end
    else
        ui.set(reference.body_yaw[1], bmode)
        ui.set(reference.body_yaw[2], by_cfg)
    end

    ui.set(reference.freestanding_body_yaw, not delay_mode and ui.get(cfg.freestanding_body_yaw))
    ui.set(reference.roll, ui.get(anti_aim_settings[state_id].roll))

    if ui.get(anti_aim_settings[state_id].defensive_anti_aimbot) and is_defensive_active and (dt_active or hs_active) and not is_manual_dir and not anti_aim_on_use then
        local def_age = globals.tickcount() - (ab_state.def_tick_start or 0)
        if ui.get(anti_aim_settings[state_id].defensive_pitch) then
            local dp_mode = ui.get(anti_aim_settings[state_id].defensive_pitch1)
            if dp_mode == 'Random' or dp_mode == 'Custom' then
                ui.set(reference.pitch[1], 'Custom')
                local exact_dp = ui.get(anti_aim_settings[state_id].defensive_pitch2)
                if dp_mode == 'Random' then
                    local other = ui.get(anti_aim_settings[state_id].defensive_pitch3)
                    exact_dp = math.random(math.min(exact_dp, other), math.max(exact_dp, other))
                end
                ui.set(reference.pitch[2], exact_dp)
            else
                ui.set(reference.pitch[1], dp_mode)
                ui.set(reference.pitch[2], ui.get(anti_aim_settings[state_id].defensive_pitch2))
            end
        end

        if ui.get(anti_aim_settings[state_id].defensive_yaw) then
            ui.set(reference.yaw_jitter[1], 'Off')
            ui.set(reference.body_yaw[1], 'Opposite')

            if ui.get(anti_aim_settings[state_id].defensive_yaw1) == '180' then
                ui.set(reference.yaw[1], '180')

                ui.set(reference.yaw[2], ui.get(anti_aim_settings[state_id].defensive_yaw2))
            elseif ui.get(anti_aim_settings[state_id].defensive_yaw1) == 'Spin' then
                ui.set(reference.yaw[1], 'Spin')

                ui.set(reference.yaw[2], ui.get(anti_aim_settings[state_id].defensive_yaw2))
            elseif ui.get(anti_aim_settings[state_id].defensive_yaw1) == '180 Z' then
                ui.set(reference.yaw[1], '180 Z')

                ui.set(reference.yaw[2], ui.get(anti_aim_settings[state_id].defensive_yaw2))
            elseif ui.get(anti_aim_settings[state_id].defensive_yaw1) == 'Sideways' then
                ui.set(reference.yaw[1], '180')

                if cmd.command_number % 4 >= 2 then
                    ui.set(reference.yaw[2], math.random(85, 100))
                else
                    ui.set(reference.yaw[2], math.random(-100, -85))
                end
            elseif ui.get(anti_aim_settings[state_id].defensive_yaw1) == 'Random' then
                ui.set(reference.yaw[1], '180')

                ui.set(reference.yaw[2], math.random(-180, 180))
            elseif ui.get(anti_aim_settings[state_id].defensive_yaw1) == '3-Way Flick' then
                ui.set(reference.yaw[1], '180')
                local flick3 = ({ -118, 0, 118 })[(cmd.command_number % 3) + 1]
                ui.set(reference.yaw[2], flick3)
            elseif ui.get(anti_aim_settings[state_id].defensive_yaw1) == 'Anti-Resolver' then
                ui.set(reference.yaw[1], '180 Z')
                local ar_flick = EXACT_DEF_YAW[(cmd.command_number % 4) + 1]
                ui.set(reference.yaw[2], ar_flick)
            elseif ui.get(anti_aim_settings[state_id].defensive_yaw1) == 'Hidden-Head Flick' then
                ui.set(reference.yaw[1], '180')
                local hh_side = (ab_state.fs_side ~= 0) and ab_state.fs_side or ((active_phase % 2 == 0) and 1 or -1)
                ui.set(reference.yaw[2], (def_age <= 2) and (hh_side * 124) or (-hh_side * 11) )
            end
        end
    end

    if ui.get(settings.safe_head_in_air) and (cmd.in_jump == 1 or bit.band(entity.get_prop(self, 'm_fFlags'), 1) == 0) and entity.get_prop(self, 'm_flDuckAmount') > 0.8 and (entity.get_classname(entity.get_player_weapon(self)) == 'CKnife' or entity.get_classname(entity.get_player_weapon(self)) == 'CWeaponTaser') and anti_aim_on_use == false and not is_manual_dir then
        ui.set(reference.pitch[1], 'Down')
        ui.set(reference.yaw[1], '180')
        ui.set(reference.yaw[2], 0)
        ui.set(reference.yaw_jitter[1], 'Off')
        ui.set(reference.body_yaw[1], 'Off')
        ui.set(reference.roll, 0)
    end

    ui.set(reference.edge_yaw, ui.get(settings.edge_yaw) and anti_aim_on_use == false and true or false)

    if ui.get(settings.freestanding) and ((contains(settings.freestanding_conditions, 'Standing') and freestanding_state_id == 1) or (contains(settings.freestanding_conditions, 'Moving') and freestanding_state_id == 2) or (contains(settings.freestanding_conditions, 'Slow motion') and freestanding_state_id == 3) or (contains(settings.freestanding_conditions, 'Crouching') and freestanding_state_id == 4) or (contains(settings.freestanding_conditions, 'In air') and freestanding_state_id == 5)) and anti_aim_on_use == false and not is_manual_dir then
        ui.set(reference.freestanding[1], true)
        ui.set(reference.freestanding[2], 'Always on')

        if contains(settings.tweaks, 'Off jitter while freestanding') then
            ui.set(reference.yaw[1], '180')
            ui.set(reference.yaw[2], 0)
            ui.set(reference.yaw_jitter[1], 'Off')
            ui.set(reference.body_yaw[1], 'Opposite')
            ui.set(reference.body_yaw[2], 0)
            ui.set(reference.freestanding_body_yaw, true)
        end
    else
        ui.set(reference.freestanding[1], false)
        ui.set(reference.freestanding[2], 'On hotkey')
    end

    if ui.get(settings.avoid_backstab) and anti_aim_on_use == false and not is_manual_dir then
        for _, enemy in ipairs(entity.get_players(true) or {}) do
            if entity.is_alive(enemy) and not entity.is_dormant(enemy) then
                local weapon = entity.get_player_weapon(enemy)
                local ex, ey, ez = entity.get_origin(enemy)
                if weapon and entity.get_classname(weapon) == 'CKnife' and ex
                    and vector(ex, ey, ez):dist(vector(entity.get_origin(self))) <= 250 then
                    for h = 0, 18 do
                        local hx, hy, hz = entity.hitbox_position(enemy, h)
                        if hx then
                            local fraction, hit = client.trace_line(self, eye_x, eye_y, eye_z, hx, hy, hz)
                            if hit == enemy or fraction == 1 then
                                ui.set(reference.yaw[1], '180')
                                ui.set(reference.yaw[2], -180)
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end)

local function on_paint()
    local me = entity.get_local_player()
    if me == nil then return end
    local rr,gg,bb = 87, 235, 61
    local width, height = client.screen_size()
    local r2, g2, b2, a2 = 55, 55, 55,255
    local highlight_fraction =  (globals.realtime() / 2 % 1.2 * 2) - 1.2
    local output = ""
    local text_to_draw = "M Y T O O L S"
    for idx = 1, #text_to_draw do
        local character = text_to_draw:sub(idx, idx)
        local character_fraction = idx / #text_to_draw
        local r1, g1, b1, a1 = 255, 255, 255, 255
        local highlight_delta = (character_fraction - highlight_fraction)
        if highlight_delta >= 0 and highlight_delta <= 1.4 then
            if highlight_delta > 0.7 then
            highlight_delta = 1.4 - highlight_delta
            end
            local r_fraction, g_fraction, b_fraction, a_fraction = r2 - r1, g2 - g1, b2 - b1
            r1 = r1 + r_fraction * highlight_delta / 0.8
            g1 = g1 + g_fraction * highlight_delta / 0.8
            b1 = b1 + b_fraction * highlight_delta / 0.8
        end
        output = output .. ('\a%02x%02x%02x%02x%s'):format(r1, g1, b1, 255, text_to_draw:sub(idx, idx))
    end
    output = output
    
    local r,g,b,a = 87, 235, 61
    renderer.text(width - (width-70), height - 555, r, g, b, 255, "c", 0, output .. ' \afa5757FF[DEV]')
end
client.set_event_callback("paint", on_paint)

client.set_event_callback('paint_ui', function()
    if entity.get_local_player() == nil then cheked_ticks = nil end

    if ui.is_menu_open() then
        ui.set_visible(reference.pitch[1], false)
        ui.set_visible(reference.pitch[2], false)
        ui.set_visible(reference.yaw_base, false)
        ui.set_visible(reference.yaw[1], false)
        ui.set_visible(reference.yaw[2], false)
        ui.set_visible(reference.yaw_jitter[1], false)
        ui.set_visible(reference.yaw_jitter[2], false)
        ui.set_visible(reference.body_yaw[1], false)
        ui.set_visible(reference.body_yaw[2], false)
        ui.set_visible(reference.freestanding_body_yaw, false)
        ui.set_visible(reference.edge_yaw, false)
        ui.set_visible(reference.freestanding[1], false)
        ui.set_visible(reference.freestanding[2], false)
        ui.set_visible(reference.roll, false)
        ui.set_visible(settings.anti_aim_state, ui.get(current_tab) == 'Anti-Aim')
        ui.set_visible(settings.avoid_backstab, ui.get(current_tab) == 'Anti-Aim')
        ui.set_visible(settings.safe_head_in_air, ui.get(current_tab) == 'Anti-Aim')
        ui.set_visible(settings.manual_forward, ui.get(current_tab) == 'Anti-Aim')
        ui.set_visible(settings.manual_right, ui.get(current_tab) == 'Anti-Aim')
        ui.set_visible(settings.manual_left, ui.get(current_tab) == 'Anti-Aim')
        ui.set_visible(settings.edge_yaw, ui.get(current_tab) == 'Anti-Aim')
        ui.set_visible(settings.freestanding, ui.get(current_tab) == 'Anti-Aim')
        ui.set_visible(settings.warmup_disabler, ui.get(current_tab) == 'Anti-Aim')
        ui.set_visible(settings.freestanding_conditions, ui.get(current_tab) == 'Anti-Aim')
        ui.set_visible(settings.tweaks, ui.get(current_tab) == 'Anti-Aim')
        ui.set_visible(settings.anti_brute_head, ui.get(current_tab) == 'Anti-Aim')
        ui.set_visible(settings.anti_move_res, ui.get(current_tab) == 'Anti-Aim')
        ui.set_visible(settings.defensive_peek, ui.get(current_tab) == 'Anti-Aim')
        ui.set_visible(trashtalk, ui.get(current_tab) == 'Misc/Vis')
        ui.set_visible(master_switch, ui.get(current_tab) == 'Misc/Vis')
        ui.set_visible(console_filter, ui.get(current_tab) == 'Misc/Vis')
        ui.set_visible(anim_breakerx, ui.get(current_tab) == 'Misc/Vis')
        ui.set_visible(aspectratio, ui.get(current_tab) == 'Misc/Vis')
        ui.set_visible(scope_fov, ui.get(current_tab) == 'Misc/Vis')
        ui.set_visible(hitmarker, ui.get(current_tab) == 'Misc/Vis')
        ui.set_visible(fastladder, ui.get(current_tab) == 'Misc/Vis')
        ui.set_visible(clantagchanger, ui.get(current_tab) == 'Misc/Vis')
        ui.set_visible(text1, ui.get(current_tab) == 'Home')
        ui.set_visible(text2, ui.get(current_tab) == 'Home')
        ui.set_visible(text3, ui.get(current_tab) == 'Home')

        for i = 1, #anti_aim_states do
            ui.set_visible(anti_aim_settings[i].override_state, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i]); ui.set(anti_aim_settings[1].override_state, true); ui.set_visible(anti_aim_settings[1].override_state, false)
            ui.set_visible(anti_aim_settings[i].force_defensive, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i]); ui.set_visible(anti_aim_settings[9].force_defensive, false)
            ui.set_visible(anti_aim_settings[i].pitch1,ui.get(current_tab) == 'Anti-Aim' and  ui.get(settings.anti_aim_state) == anti_aim_states[i])
            ui.set_visible(anti_aim_settings[i].pitch2, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].pitch1) == 'Custom')
            ui.set_visible(anti_aim_settings[i].yaw_base, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i])
            ui.set_visible(anti_aim_settings[i].yaw1, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i])
            ui.set_visible(anti_aim_settings[i].yaw2_left, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].yaw1) ~= 'Off' and ui.get(anti_aim_settings[i].yaw_jitter1) ~= 'Delay')
            ui.set_visible(anti_aim_settings[i].yaw2_right, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].yaw1) ~= 'Off' and ui.get(anti_aim_settings[i].yaw_jitter1) ~= 'Delay')
            ui.set_visible(anti_aim_settings[i].yaw2_randomize, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].yaw1) ~= 'Off' and ui.get(anti_aim_settings[i].yaw_jitter1) ~= 'Delay')
            ui.set_visible(anti_aim_settings[i].yaw_jitter1, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].yaw1) ~= 'Off')
            ui.set_visible(anti_aim_settings[i].yaw_jitter2_left, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].yaw1) ~= 'Off' and ui.get(anti_aim_settings[i].yaw_jitter1) ~= 'Off')
            ui.set_visible(anti_aim_settings[i].yaw_jitter2_right, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].yaw1) ~= 'Off' and ui.get(anti_aim_settings[i].yaw_jitter1) ~= 'Off')
            ui.set_visible(anti_aim_settings[i].yaw_jitter2_randomize, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].yaw1) ~= 'Off' and ui.get(anti_aim_settings[i].yaw_jitter1) ~= 'Off')
            ui.set_visible(anti_aim_settings[i].yaw_jitter2_delay, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].yaw1) ~= 'Off' and ui.get(anti_aim_settings[i].yaw_jitter1) == 'Delay')
            ui.set_visible(anti_aim_settings[i].body_yaw1, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].yaw_jitter1) ~= 'Delay')
            ui.set_visible(anti_aim_settings[i].body_yaw2, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and (ui.get(anti_aim_settings[i].body_yaw1) ~= 'Off' and ui.get(anti_aim_settings[i].body_yaw1) ~= 'Opposite') and ui.get(anti_aim_settings[i].yaw_jitter1) ~= 'Delay')
            ui.set_visible(anti_aim_settings[i].freestanding_body_yaw, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].body_yaw1) ~= 'Off' and ui.get(anti_aim_settings[i].yaw_jitter1) ~= 'Delay')
            ui.set_visible(anti_aim_settings[i].roll, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i])
            ui.set_visible(anti_aim_settings[i].defensive_anti_aimbot, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i]); ui.set_visible(anti_aim_settings[9].defensive_anti_aimbot, false)
            ui.set_visible(anti_aim_settings[i].defensive_pitch, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].defensive_anti_aimbot)); ui.set_visible(anti_aim_settings[9].defensive_pitch, false)
            ui.set_visible(anti_aim_settings[i].defensive_pitch1, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].defensive_anti_aimbot) and ui.get(anti_aim_settings[i].defensive_pitch)); ui.set_visible(anti_aim_settings[9].defensive_pitch1, false)
            ui.set_visible(anti_aim_settings[i].defensive_pitch2, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].defensive_anti_aimbot) and ui.get(anti_aim_settings[i].defensive_pitch) and (ui.get(anti_aim_settings[i].defensive_pitch1) == 'Random' or ui.get(anti_aim_settings[i].defensive_pitch1) == 'Custom')); ui.set_visible(anti_aim_settings[9].defensive_pitch2, false)
            ui.set_visible(anti_aim_settings[i].defensive_pitch3, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].defensive_anti_aimbot) and ui.get(anti_aim_settings[i].defensive_pitch) and ui.get(anti_aim_settings[i].defensive_pitch1) == 'Random'); ui.set_visible(anti_aim_settings[9].defensive_pitch3, false)
            ui.set_visible(anti_aim_settings[i].defensive_yaw, ui.get(current_tab) == 'Anti-Aim' and  ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].defensive_anti_aimbot)); ui.set_visible(anti_aim_settings[9].defensive_yaw, false)
            ui.set_visible(anti_aim_settings[i].defensive_yaw1, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].defensive_anti_aimbot) and ui.get(anti_aim_settings[i].defensive_yaw)); ui.set_visible(anti_aim_settings[9].defensive_yaw1, false)
            ui.set_visible(anti_aim_settings[i].defensive_yaw2, ui.get(current_tab) == 'Anti-Aim' and ui.get(settings.anti_aim_state) == anti_aim_states[i] and ui.get(anti_aim_settings[i].defensive_anti_aimbot) and ui.get(anti_aim_settings[i].defensive_yaw) and (ui.get(anti_aim_settings[i].defensive_yaw1) == '180' or ui.get(anti_aim_settings[i].defensive_yaw1) == 'Spin' or ui.get(anti_aim_settings[i].defensive_yaw1) == '180 Z')); ui.set_visible(anti_aim_settings[9].defensive_yaw2, false)
        end
    end
end)

import_btn = ui.new_button("AA", "Anti-aimbot angles", "Import settings", function() import(clipboard.get()) end)
export_btn = ui.new_button("AA", "Anti-aimbot angles", "Export settings", function() 
    local code = {{}}

    for i, integers in pairs(data.integers) do
        table.insert(code[1], ui.get(integers))
    end

    clipboard.set(base64.encode(json.stringify(code)))
    client.color_log(124, 252, 0, "mytools ~\0")
	client.color_log(200, 200, 200, " config successfully exported!")
end)
default_btn = ui.new_button("AA", "Anti-aimbot angles", "Default Config", function() 
    import('W1siTW92aW5nIix0cnVlLHRydWUsdHJ1ZSx0cnVlLHRydWUsdHJ1ZSx0cnVlLHRydWUsdHJ1ZSx0cnVlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLHRydWUsdHJ1ZSxmYWxzZSxmYWxzZSwiT2ZmIiwiTWluaW1hbCIsIk1pbmltYWwiLCJNaW5pbWFsIiwiTWluaW1hbCIsIk1pbmltYWwiLCJNaW5pbWFsIiwiTWluaW1hbCIsIk1pbmltYWwiLCJPZmYiLDAsMCwwLDAsMCwwLDAsMCwwLDAsIkxvY2FsIHZpZXciLCJBdCB0YXJnZXRzIiwiQXQgdGFyZ2V0cyIsIkF0IHRhcmdldHMiLCJBdCB0YXJnZXRzIiwiQXQgdGFyZ2V0cyIsIkF0IHRhcmdldHMiLCJBdCB0YXJnZXRzIiwiQXQgdGFyZ2V0cyIsIkxvY2FsIHZpZXciLCJPZmYiLCIxODAiLCIxODAiLCIxODAiLCIxODAiLCIxODAiLCIxODAiLCIxODAiLCIxODAiLCJPZmYiLDAsOCwtMzMsLTE0LDAsLTE1LDAsMCw3LDAsMCw4LC0zMywtMTQsMCwtMTUsMCwwLDcsMCwwLDAsMCwwLDAsMCwwLDAsMCwwLCJPZmYiLCJDZW50ZXIiLCJPZmZzZXQiLCJPZmZzZXQiLCJEZWxheSIsIk9mZnNldCIsIkRlbGF5IiwiRGVsYXkiLCJDZW50ZXIiLCJPZmYiLDAsNTQsNjgsNDAsLTI5LDUxLC0yNSwtMjMsNTAsMCwwLDU0LDY4LDQwLDQzLDUxLDQwLDQxLDUwLDAsMCwwLDUsNCwwLDMsMCwwLDAsMCwyLDIsMiwyLDQsMiw2LDQsMiwyLCJPZmYiLCJKaXR0ZXIiLCJKaXR0ZXIiLCJKaXR0ZXIiLCJPZmYiLCJKaXR0ZXIiLCJPZmYiLCJPZmYiLCJKaXR0ZXIiLCJPcHBvc2l0ZSIsMCwtNDAsLTQwLC00MCwwLC00MCwwLDAsLTQwLDAsZmFsc2UsZmFsc2UsZmFsc2UsZmFsc2UsZmFsc2UsZmFsc2UsZmFsc2UsZmFsc2UsZmFsc2UsdHJ1ZSwwLDAsMCwwLDAsMCwwLDAsMCwwLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLGZhbHNlLCJPZmYiLCJPZmYiLCJPZmYiLCJPZmYiLCJPZmYiLCJPZmYiLCJPZmYiLCJPZmYiLCJPZmYiLCJPZmYiLDAsMCwwLDAsMCwwLDAsMCwwLDAsMCwwLDAsMCwwLDAsMCwwLDAsMCxmYWxzZSxmYWxzZSxmYWxzZSxmYWxzZSxmYWxzZSxmYWxzZSxmYWxzZSxmYWxzZSxmYWxzZSxmYWxzZSwiMTgwIiwiMTgwIiwiMTgwIiwiMTgwIiwiMTgwIiwiMTgwIiwiMTgwIiwiMTgwIiwiMTgwIiwiMTgwIiwwLDAsMCwwLDAsMCwwLDAsMCwwLHRydWUsdHJ1ZSxbIlN0YW5kaW5nIiwiTW92aW5nIiwiQ3JvdWNoaW5nIl0sWyJPZmYgaml0dGVyIHdoaWxlIGZyZWVzdGFuZGluZyIsIk9mZiBqaXR0ZXIgb24gbWFudWFsIl0sdHJ1ZSx0cnVlLHRydWUsMzUsdHJ1ZSwxNTAsZmFsc2UsZmFsc2UsdHJ1ZSx0cnVlXV0=')
end)

local function apply_adaptive_preset()
    ui.set(settings.anti_brute_head, true)
    ui.set(settings.anti_move_res, true)
    ui.set(settings.defensive_peek, true)
    ui.set(settings.avoid_backstab, true)
    ui.set(settings.safe_head_in_air, true)
    ui.set(settings.warmup_disabler, false)
    ui.set(settings.freestanding_conditions, {'Standing', 'Moving', 'Slow motion', 'Crouching'})
    ui.set(settings.tweaks, {'Off jitter on manual'})

    local presets = {
        -- 1: Global
        [1] = {
            override = true, pitch1 = 'Down', pitch2 = 89, yaw_base = 'At targets', yaw1 = '180',
            y_l = -8, y_r = 11, y_rand = 0,
            j_mode = 'Anti-Brute', j_l = -43, j_r = 51, j_rand = 0, j_delay = 2,
            by_mode = 'Opposite Jitter', by_val = -116, fs_by = true, roll = 0,
            f_def = false, def_aa = true, def_p = true, def_p1 = 'Custom', def_p2 = -89, def_p3 = 89,
            def_y = true, def_y1 = 'Hidden-Head Flick', def_y2 = -124
        },
        -- 2: Standing
        [2] = {
            override = true, pitch1 = 'Down', pitch2 = 89, yaw_base = 'At targets', yaw1 = '180',
            y_l = -8, y_r = 11, y_rand = 0,
            j_mode = 'Anti-Brute', j_l = -43, j_r = 51, j_rand = 0, j_delay = 2,
            by_mode = 'Opposite Jitter', by_val = -116, fs_by = true, roll = 0,
            f_def = false, def_aa = true, def_p = true, def_p1 = 'Custom', def_p2 = -89, def_p3 = 89,
            def_y = true, def_y1 = 'Hidden-Head Flick', def_y2 = 124
        },
        -- 3: Moving
        [3] = {
            override = true, pitch1 = 'Down', pitch2 = 89, yaw_base = 'At targets', yaw1 = '180',
            y_l = -9, y_r = 11, y_rand = 0,
            j_mode = 'Tank-AA', j_l = -44, j_r = 46, j_rand = 0, j_delay = 2,
            by_mode = 'Anti-Brute', by_val = -116, fs_by = true, roll = 0,
            f_def = false, def_aa = true, def_p = true, def_p1 = 'Custom', def_p2 = -89, def_p3 = 89,
            def_y = true, def_y1 = 'Hidden-Head Flick', def_y2 = -126
        },
        -- 4: Slow motion
        [4] = {
            override = true, pitch1 = 'Down', pitch2 = 89, yaw_base = 'At targets', yaw1 = '180',
            y_l = -7, y_r = 10, y_rand = 0,
            j_mode = 'Anti-Brute', j_l = -39, j_r = 43, j_rand = 0, j_delay = 2,
            by_mode = 'Adaptive Desync', by_val = -94, fs_by = true, roll = 0,
            f_def = false, def_aa = true, def_p = true, def_p1 = 'Custom', def_p2 = -89, def_p3 = 89,
            def_y = true, def_y1 = 'Hidden-Head Flick', def_y2 = 118
        },
        -- 5: Crouching
        [5] = {
            override = true, pitch1 = 'Down', pitch2 = 89, yaw_base = 'At targets', yaw1 = '180',
            y_l = -8, y_r = 11, y_rand = 0,
            j_mode = 'Anti-Brute', j_l = -43, j_r = 47, j_rand = 0, j_delay = 2,
            by_mode = 'Opposite Jitter', by_val = -94, fs_by = true, roll = 0,
            f_def = false, def_aa = true, def_p = true, def_p1 = 'Custom', def_p2 = -89, def_p3 = 89,
            def_y = true, def_y1 = '3-Way Flick', def_y2 = -118
        },
        -- 6: Crouching & moving
        [6] = {
            override = true, pitch1 = 'Down', pitch2 = 89, yaw_base = 'At targets', yaw1 = '180',
            y_l = -9, y_r = 12, y_rand = 0,
            j_mode = 'Tank-AA', j_l = -44, j_r = 46, j_rand = 0, j_delay = 2,
            by_mode = 'Anti-Brute', by_val = -108, fs_by = true, roll = 0,
            f_def = true, def_aa = true, def_p = true, def_p1 = 'Custom', def_p2 = -89, def_p3 = 89,
            def_y = true, def_y1 = 'Hidden-Head Flick', def_y2 = 124
        },
        -- 7: In air
        [7] = {
            override = true, pitch1 = 'Down', pitch2 = 89, yaw_base = 'At targets', yaw1 = '180',
            y_l = -11, y_r = 13, y_rand = 0,
            j_mode = 'Tank-AA', j_l = -44, j_r = 48, j_rand = 0, j_delay = 2,
            by_mode = 'Anti-Brute', by_val = -116, fs_by = false, roll = 0,
            f_def = true, def_aa = true, def_p = true, def_p1 = 'Custom', def_p2 = -89, def_p3 = 89,
            def_y = true, def_y1 = '3-Way Flick', def_y2 = -118
        },
        -- 8: In air & crouching
        [8] = {
            override = true, pitch1 = 'Down', pitch2 = 89, yaw_base = 'At targets', yaw1 = '180',
            y_l = -9, y_r = 11, y_rand = 0,
            j_mode = 'Anti-Brute', j_l = -43, j_r = 47, j_rand = 0, j_delay = 2,
            by_mode = 'Opposite Jitter', by_val = -116, fs_by = false, roll = 0,
            f_def = true, def_aa = true, def_p = true, def_p1 = 'Custom', def_p2 = -89, def_p3 = 89,
            def_y = true, def_y1 = 'Anti-Resolver', def_y2 = 126
        },
        -- 9: No exploits
        [9] = {
            override = true, pitch1 = 'Down', pitch2 = 89, yaw_base = 'At targets', yaw1 = '180',
            y_l = -8, y_r = 11, y_rand = 0,
            j_mode = 'Anti-Brute', j_l = -43, j_r = 51, j_rand = 0, j_delay = 2,
            by_mode = 'Opposite Jitter', by_val = -116, fs_by = true, roll = 0,
            f_def = false, def_aa = false, def_p = false, def_p1 = 'Off', def_p2 = 0, def_p3 = 0,
            def_y = false, def_y1 = '180', def_y2 = 0
        },
        -- 10: On use
        [10] = {
            override = true, pitch1 = 'Off', pitch2 = 0, yaw_base = 'Local view', yaw1 = 'Off',
            y_l = 0, y_r = 0, y_rand = 0,
            j_mode = 'Micro-Sway', j_l = -6, j_r = 6, j_rand = 0, j_delay = 2,
            by_mode = 'Opposite', by_val = 0, fs_by = true, roll = 0,
            f_def = false, def_aa = false, def_p = false, def_p1 = 'Off', def_p2 = 0, def_p3 = 0,
            def_y = false, def_y1 = '180', def_y2 = 0
        }
    }

    for i, p in ipairs(presets) do
        local s = anti_aim_settings[i]
        ui.set(s.override_state, p.override)
        ui.set(s.pitch1, p.pitch1)
        ui.set(s.pitch2, p.pitch2)
        ui.set(s.yaw_base, p.yaw_base)
        ui.set(s.yaw1, p.yaw1)
        ui.set(s.yaw2_left, p.y_l)
        ui.set(s.yaw2_right, p.y_r)
        ui.set(s.yaw2_randomize, p.y_rand)
        ui.set(s.yaw_jitter1, p.j_mode)
        ui.set(s.yaw_jitter2_left, p.j_l)
        ui.set(s.yaw_jitter2_right, p.j_r)
        ui.set(s.yaw_jitter2_randomize, p.j_rand)
        ui.set(s.yaw_jitter2_delay, p.j_delay)
        ui.set(s.body_yaw1, p.by_mode)
        ui.set(s.body_yaw2, p.by_val)
        ui.set(s.freestanding_body_yaw, p.fs_by)
        ui.set(s.roll, p.roll)
        ui.set(s.force_defensive, p.f_def)
        ui.set(s.defensive_anti_aimbot, p.def_aa)
        ui.set(s.defensive_pitch, p.def_p)
        ui.set(s.defensive_pitch1, p.def_p1)
        ui.set(s.defensive_pitch2, p.def_p2)
        ui.set(s.defensive_pitch3, p.def_p3)
        ui.set(s.defensive_yaw, p.def_y)
        ui.set(s.defensive_yaw1, p.def_y1)
        ui.set(s.defensive_yaw2, p.def_y2)
    end

    client.color_log(124, 252, 0, "mytools ~\0")
    client.color_log(255, 255, 255, " Adaptive preset loaded. Validate it in-game for your configuration.")
end

unhittable_btn = ui.new_button("AA", "Anti-aimbot angles", "★ Load Adaptive Preset", apply_adaptive_preset)

local function point_to_segment_dist(px, py, pz, x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    local len2 = dx * dx + dy * dy + dz * dz
    if len2 <= 0.001 then
        local ex, ey, ez = px - x1, py - y1, pz - z1
        return math.sqrt(ex * ex + ey * ey + ez * ez)
    end
    local t = ((px - x1) * dx + (py - y1) * dy + (pz - z1) * dz) / len2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local cx, cy, cz = x1 + t * dx, y1 + t * dy, z1 + t * dz
    local ex, ey, ez = px - cx, py - cy, pz - cz
    return math.sqrt(ex * ex + ey * ey + ez * ez)
end

client.set_event_callback('bullet_impact', function(e)
    if not ui.get(settings.anti_brute_head) then return end
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return end
    local shooter = client.userid_to_entindex(e.userid)
    if not shooter or shooter == me or not entity.is_enemy(shooter) or entity.is_dormant(shooter) then return end
    local hx, hy, hz = entity.hitbox_position(me, 0)
    local sx, sy, sz = entity.get_origin(shooter)
    if not hx or not sx then return end
    sz = sz + (entity.get_prop(shooter, 'm_vecViewOffset[2]') or 64)
    local dist = point_to_segment_dist(hx, hy, hz, sx, sy, sz, e.x, e.y, e.z)
    local tick = globals.tickcount()
    if dist < 72 and ab_state.impact_tick[shooter] ~= tick then
        ab_state.impact_tick[shooter] = tick
        ab_state.phase = (ab_state.phase % 6) + 1
        local cur_ep = ab_state.enemy_phase[shooter] or 1
        ab_state.enemy_phase[shooter] = (cur_ep % 6) + 1
        ab_state.impact_count = ab_state.impact_count + 1
        ab_state.last_impact_time = globals.realtime()
    end
end)

client.set_event_callback('paint_ui', function()
    if entity.get_local_player() == nil then cheked_ticks = nil end

    ui.set_visible(export_btn, ui.get(current_tab) == 'Home')
    ui.set_visible(import_btn, ui.get(current_tab) == 'Home')
    ui.set_visible(default_btn, ui.get(current_tab) == 'Home')
    ui.set_visible(unhittable_btn, ui.get(current_tab) == 'Home' or ui.get(current_tab) == 'Anti-Aim')
end)

ui.set_callback(console_filter, function()
    cvar.con_filter_text:set_string("cool text")
    cvar.con_filter_enable:set_int(1)
end)

--killsay
local killsay_pharases = {
    {'⠀1', 'nice iq'},
    {'cgb gblfhfc', 'спи пидорас'},
    {'пздц', 'игрок'},
    {'1 моча', 'изи'},
    {'куда ты', 'сынок ебаный'},
    {'найс аа хуесос', 'долго делал?'},
    {'ебать что', 'как я убил ахуеть'},
    {'mytools over all pidoras'},
    {'nice iq', 'churka)'},
    {'1 чмо', 'нищий без майтулса'},
    {'лол', 'как же я тебя выебал'},
    {'че за луашку юзаешь'},
    {'чей кфг юзаешь'},
    {'найс айкью', 'хуесос'},
    {']f]f]f]f]f]f]', 'хахахаха'},
    {'jq ,kz', 'ой бля', 'найс кфг уебище'},
    {'jq', 'я в афк чит настраивал хаха'},
    {'какой же у тебя сочный ник'},
    {'хуйсос анимешный', 'думал не убью тебя?)'},
    {'моча ебаная', 'кого ты пытаешься убить'},
    {'mad cuz bad?', 'hhhhhh retardw'},
    {'учись пока я жив долбаеб'},
    {'еблан', 'включи монитор'},
    {'1', 'опять умер моча'},
    {'egc', 'упссс', 'сорри'},
    {'хахаха ебать я тебя трахнул'},
    {'nice iq', 'u sell'},
    {'изи шлюха', 'че в хуй?'},
    {'получай тварь ебаная', 'фу нахуй'},
    {']f]f]f]f]f]]f]f', 'как же мне похуй долбаеб'},
    {'изи моча', 'я ору с тебя какой же ты сочный'},
    {'ez owned', 'weak dog + rat'},
    {'пиздец ты легкий ботик'},
    {'1', 'не отвечаю?', 'мне похуй'},
    {'как же мне похуй', 'ботик'},
    {'retard', 'just fucking bot'},
    {'♕ M Y T O O L S > A L L ♕'},
    {'закупись майтулсом на скит чмо ебаное'}
}
    
local death_say = {
    {'пиздец че я за хуйню купил', 'лучше бы майтулс купил бля'},
    {'ну фу', 'хуесос'},
    {'что ты делаешь', 'моча умалишенная'},
    {'бля', 'я стрелял вообще чи шо?'},
    {'чит подвел'},
    {'БЛЯЯЯЯЯЯЯЯЯЯЯЯТЬ', 'как же ты меня заебал'},
    {'ну и зачем', 'дал бы клип', 'пиздец клоун'},
    {'ахахахах', 'ну да', 'опять сын шлюхи убил бестолковый'},
    {'м', 'пон)', 'найс чит'},
    {'да блять', 'какой джиттер поставить сука'},
    {'ну фу', 'ублюдок', 'ебаный'},
    {'да сука', 'где тимейты блять', 'как же сука они меня бесят'},
    {'lf ,kznm', 'да блять', 'опять я мисснул'},
    {'да блять', 'ало', 'я вообще стрелять буду нет'},
    {'хех', 'ты сам то хоть понял', 'как меня убил'},
    {'сука', 'опять по дезу ебаному'},
    {'бля', 'клиентнуло', 'лаки'},
    {'понятно', 'ик ак ты так играешь', 'еблан бестолковый'},
    {'ну блять', 'он просто пошел', 'пиздец'},
    {'&', 'и че это', 'откуда ты меня убил?'},
    {'тварь', 'ебаная', 'ЧТО ТЫ ДЕЛАЕШЬ'},
    {'YE LF', 'ну да', 'хуесос', 'норм играешь'},
    {'сочник ебаный', 'как же ты меня заебал уже', 'что ты делаешь'},
    {'хуевый без скита', 'как ты меня убиваешь с пастой своей'},
    {'подпивас ебаный', 'как же ты меня переиграл'},
    {'бля', 'признаю, переиграл'},
    {'как ты меня убиваешь', 'ебаный owosh'},
    {'дефектус че ты делаешь', 'пиздец'},
    {'хуйсосик анимешный', 'как ты убиваешь', 'эт пздц'},
    {'бля ну бро', 'посмотри на мою команду', 'это пзиидец'},
    {'ммм', 'хуесосы бездарные в команде'},
    {'ik.[f', 'шлюха пошла нахуй'},
    {'ndfhm t,fyfz', 'тварь ебаная как же ты меня бесишь'},
    {'фу нахуй', 'опять в бекшут'},
    {'только так и умеешь да?', 'блядь ебаная'},
    {'нахуй ты меня трешкаешь', 'шлюха ебаная'},
    {'ну повезло тебе', 'дальше то что хуесос'},
    {'ебанная ты мразь', 'которая мне все проебала'},
    {'ujcgjlb', 'господи', 'мразь убогая'},
    {'хахахах', 'ну бля заебись фристенд в чите)'},
    {'фу ты заебал конч'},
    {')', 'хорош)'},
    {'норм трекаешь', 'ублюдина'},
    {'а че', 'хайдшоты на фд уже не работают?'}
}

    
client.set_event_callback('player_death', function(e)
    delayed_msg = function(delay, msg)
        return client.delay_call(delay, function() client.exec('say ' .. msg) end)
    end

    local delay = 2.3
    local me = entity_get_local_player()
    local victim = client.userid_to_entindex(e.userid)
    local attacker = client.userid_to_entindex(e.attacker)

    local killsay_delay = 0
    local deathsay_delay = 0

    if entity_get_local_player() == nil then return end

    gamerulesproxy = entity.get_all("CCSGameRulesProxy")[1]
    warmup = entity.get_prop(gamerulesproxy,"m_bWarmupPeriod")
    if warmup == 1 then return end

    if not ui.get(trashtalk) then return end

    if (victim ~= attacker and attacker == me) then
        local phase_block = killsay_pharases[math.random(1, #killsay_pharases)]

            for i=1, #phase_block do
                local phase = phase_block[i]
                local interphrase_delay = #phase_block[i]/24*delay
                killsay_delay = killsay_delay + interphrase_delay

                delayed_msg(killsay_delay, phase)
            end
        end
            
    if (victim == me and attacker ~= me) then
        local phase_block = death_say[math.random(1, #death_say)]

        for i=1, #phase_block do
            local phase = phase_block[i]
            local interphrase_delay = #phase_block[i]/20*delay
            deathsay_delay = deathsay_delay + interphrase_delay

            delayed_msg(deathsay_delay, phase)
        end
    end
end)
    
--

--
local clantag = {
    steam = steamworks.ISteamFriends,
    prev_ct = "",
    orig_ct = "",
    enb = false,
}

local function get_original_clantag()
    local clan_id = cvar.cl_clanid.get_int()
    if clan_id == 0 then return "\0" end

    local clan_count = clantag.steam.GetClanCount()
    for i = 0, clan_count do 
        local group_id = clantag.steam.GetClanByIndex(i)
        if group_id == clan_id then
            return clantag.steam.GetClanTag(group_id)
        end
    end
end

local clantag_anim = function(text, indices)

    time_to_ticks = function(t)
        return math.floor(0.5 + (t / globals.tickinterval()))
    end

    local text_anim = "               " .. text ..                       "" 
    local tickinterval = globals.tickinterval()
    local tickcount = globals.tickcount() + time_to_ticks(client.latency())
    local i = tickcount / time_to_ticks(0.3)
    i = math.floor(i % #indices)
    i = indices[i+1]+1
    return string.sub(text_anim, i, i+15)
end

local function clantag_set()
    local lua_name = "mytools.gs "
    if ui.get(clantagchanger) then
        if ui.get(ui.reference("Misc", "Miscellaneous", "Clan tag spammer")) then ui.set(ui.reference("Misc", "Miscellaneous", "Clan tag spammer"), false) end

		local clan_tag = clantag_anim(lua_name, {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 11, 11, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25})

        if entity.get_prop(entity.get_game_rules(), "m_gamePhase") == 5 then
            clan_tag = clantag_anim('mytools.gs ', {13})
            client.set_clan_tag(clan_tag)
        elseif entity.get_prop(entity.get_game_rules(), "m_timeUntilNextPhaseStarts") ~= 0 then
            clan_tag = clantag_anim('mytools.gs ', {13})
            client.set_clan_tag(clan_tag)
        elseif clan_tag ~= clantag.prev_ct  then
            client.set_clan_tag(clan_tag)
        end

        clantag.prev_ct = clan_tag
        clantag.enb = true
    elseif clantag.enb == true then
        client.set_clan_tag(get_original_clantag())
        clantag.enb = false
    end
end

clantag.paint = function()
    if entity.get_local_player() ~= nil then
        if globals.tickcount() % 2 == 0 then
            clantag_set()
        end
    end
end

clantag.run_command = function(e)
    if entity.get_local_player() ~= nil then 
        if e.chokedcommands == 0 then
            clantag_set()
        end
    end
end

clantag.player_connect_full = function(e)
    if client.userid_to_entindex(e.userid) == entity.get_local_player() then 
        clantag.orig_ct = get_original_clantag()
    end
end

clantag.shutdown = function()
    client.set_clan_tag(get_original_clantag())
end

client.set_event_callback("paint", clantag.paint)
client.set_event_callback("run_command", clantag.run_command)
client.set_event_callback("player_connect_full", clantag.player_connect_full)
client.set_event_callback("shutdown", clantag.shutdown)
--


--[[client.set_event_callback('console_input', function(text)
    if string.find(text, '//export') then
        local code = {{}}

        for i, integers in pairs(data.integers) do
            table.insert(code[1], ui.get(integers))
        end

        clipboard.set(base64.encode(json.stringify(code)))
    elseif string.find(text, '//import') then
        import(clipboard.get())
    elseif string.find(text, '//default') then
        http.get('https://pastebin.com/raw/xJy4ipac', function(success, response)
            if not success or response.status ~= 200 then return end

            import(response.body)
        end)
    end
end)]]

client.set_event_callback('net_update_end', function()
    local me = entity.get_local_player()
    if me and entity.is_alive(me) then is_defensive(me) end
end)

client.set_event_callback('round_prestart', reset_aa_runtime)
client.set_event_callback('level_init', reset_aa_runtime)
client.set_event_callback('player_spawn', function(e)
    if client.userid_to_entindex(e.userid) == entity.get_local_player() then reset_aa_runtime() end
end)
client.set_event_callback('player_disconnect', function(e)
    local player = client.userid_to_entindex(e.userid)
    if player then
        ab_state.enemy_phase[player], ab_state.impact_tick[player] = nil, nil
    end
end)

--fastladder
client.set_event_callback('setup_command', function(cmd)
    if ui.get(fastladder) then
        local pitch, yaw = client.camera_angles()
        if entity.get_prop(entity.get_local_player(), "m_MoveType") == 9 then
            cmd.yaw = math.floor(cmd.yaw+0.5)
            cmd.roll = 0
            
            if cmd.forwardmove > 0 then
                if pitch < 45 then

                    cmd.pitch = 89
                    cmd.in_moveright = 1
                    cmd.in_moveleft = 0
                    cmd.in_forward = 0
                    cmd.in_back = 1

                    if cmd.sidemove == 0 then
                        cmd.yaw = cmd.yaw + 90
                    end

                    if cmd.sidemove < 0 then
                        cmd.yaw = cmd.yaw + 150
                    end

                    if cmd.sidemove > 0 then
                        cmd.yaw = cmd.yaw + 30
                    end
                end 
            end

            if cmd.forwardmove < 0 then
                cmd.pitch = 89
                cmd.in_moveleft = 1
                cmd.in_moveright = 0
                cmd.in_forward = 1
                cmd.in_back = 0
                if cmd.sidemove == 0 then
                    cmd.yaw = cmd.yaw + 90
                end
                if cmd.sidemove > 0 then
                    cmd.yaw = cmd.yaw + 150
                end
                if cmd.sidemove < 0 then
                    cmd.yaw = cmd.yaw + 30
                end
            end

        end
    end
end)

--legbreaker
local ref = {
    leg_movement = ui.reference('AA', 'Other', 'Leg movement')
}

local ab = {}

ab.pre_render = function()
    if ui.get(anim_breakerx) then
        local local_player = entity.get_local_player()
        if not entity.is_alive(local_player) then return end

        entity.set_prop(local_player, "m_flPoseParameter", client.random_float(0.8/10, 1), 0)
        ui.set(ref.leg_movement, client.random_int(1, 2) == 1 and "Off" or "Always slide")
    end
end

ab.setup_command = function(e)
    if not ui.get(anim_breakerx) then return end

    local local_player = entity.get_local_player()
    if not entity.is_alive(local_player) then return end

    ui.set(ref.leg_movement, 'Always slide')
end

local ui_callback = function(c)
    local enabled, addr = ui.get(c), ''

    if not enabled then
        addr = 'un'
    end
    
    local _func = client[addr .. 'set_event_callback']

    _func('pre_render', ab.pre_render)
    _func('setup_command', ab.setup_command)
end

ui.set_callback(master_switch, ui_callback)
ui_callback(master_switch)

local is_on_ground = false

--- @region: process main work
--
client.set_event_callback("setup_command", function()
    if entity.get_local_player() == nil then return end

    gamerulesproxy = entity.get_all("CCSGameRulesProxy")[1]
    warmup = entity.get_prop(gamerulesproxy,"m_bWarmupPeriod")
    --print(warmup)
  
    if ui.get(settings.warmup_disabler) and warmup == 1 then
        ui.set(reference.body_yaw[1], 'Off')
        ui.set(reference.yaw[2], math.random(-180, 180))
        ui.set(reference.yaw_jitter[1], 'Random')
        ui.set(reference.pitch[1], 'Off')
    end
end)
--

client.set_event_callback("setup_command", function(cmd)
    is_on_ground = cmd.in_jump == 0

    if ui.get(anim_breakerx) then
        ui.set(ref.leg_movement, cmd.command_number % 3 == 0 and "Off" or "Always slide")
    end
end)

client.set_event_callback("pre_render", function()
    local self = entity.get_local_player()
    if not self or not entity.is_alive(self) then
        return
    end

    local self_index = c_entity.new(self)
    local self_anim_state = self_index:get_anim_state()

    if not self_anim_state then
        return
    end

    if ui.get(anim_breakerx) then
        entity.set_prop(self, "m_flPoseParameter", E_POSE_PARAMETERS.STAND, globals.tickcount() % 4 > 1 and 5 / 10 or 1)
    
        local self_anim_overlay = self_index:get_anim_overlay(12)
        if not self_anim_overlay then
            return
        end

        local x_velocity = entity.get_prop(self, "m_vecVelocity[0]")
        if math.abs(x_velocity) >= 3 then
            self_anim_overlay.weight = 100 / 100
        end
    end
end)
--- @endregion

--scope
local second_zoom do
    second_zoom = { }

    local old_value

    local function callback(item)
        local fn = client_set_event_callback
        local value = ui_get(item)

        if not value then
            second_zoom.shutdown()
            fn = client_unset_event_callback
        end

        ui_set_visible(scope_fov, value)

        fn("shutdown", second_zoom.shutdown)
        fn("pre_render", second_zoom.pre_render)
    end

    local function reset()
        if old_value == nil then
            return
        end

        ui_set(override_zoom_fov, old_value)
        old_value = nil
    end

    local function update()
        if old_value == nil then
            old_value = ui_get(override_zoom_fov)
        end

        ui_set(override_zoom_fov, ui_get(scope_fov))
    end

    
    client.set_event_callback('paint', function()

    if ui.get(scope_fov) == 0 then
        return
    end

    if ui.get(scope_fov) > 0 then
            local me = entity_get_local_player()

            if me == nil then
                return
            end

            local wpn = entity_get_player_weapon(me)

            if wpn == nil then
                return
            end

            local zoom_level = entity_get_prop(wpn, "m_zoomLevel")

            if zoom_level ~= 2 then
                reset()
                return
            end

            update()
        end
    end)
end
--

client.set_event_callback('paint', function()
    cvar.r_aspectratio:set_float(ui.get(aspectratio)/100)
end)
--

local queue = {}

local function aim_firec(c)
	queue[globals.tickcount()] = {c.x, c.y, c.z, globals.curtime() + 2}
end

local function paintc(c)
	if ui.get(hitmarker) then
        for tick, data in pairs(queue) do
            if globals.curtime() <= data[4] then
                local x1, y1 = renderer.world_to_screen(data[1], data[2], data[3])
                if x1 ~= nil and y1 ~= nil then
                    renderer.line(x1 - 6, y1, x1 + 6, y1, 34, 214, 132, 255)
                    renderer.line(x1, y1 - 6, x1, y1 + 6, 108, 182, 203, 255)
                end
            end
        end
    end
end

client.set_event_callback("aim_fire", aim_firec)
client.set_event_callback("paint", paintc)
client.set_event_callback("round_prestart", function() queue = {} end)
--

local hitgroup_names = {"generic", "head", "chest", "stomach", "left arm", "right arm", "left leg", "right leg", "neck", "?", "gear"}
local weapon_to_verb = { knife = 'Knifed', hegrenade = 'Naded', inferno = 'Burned' }

client.set_event_callback('aim_hit', function(e)
	if not ui.get(master_switch) or e.id == nil then
		return
	end

	local group = hitgroup_names[e.hitgroup + 1] or "?"

	client.color_log(124, 252, 0, "mytools ~\0")
	client.color_log(200, 200, 200, " Hit\0")
	client.color_log(124, 252, 0, string.format(" %s\0", entity.get_player_name(e.target)))
	client.color_log(200, 200, 200, " in the\0")
	client.color_log(124, 252, 0, string.format(" %s\0", group))
	client.color_log(200, 200, 200, " for\0")
	client.color_log(124, 252, 0, string.format(" %s\0", e.damage))
	client.color_log(200, 200, 200, " damage\0")
	client.color_log(200, 200, 200, " (\0")
	client.color_log(124, 252, 0, string.format("%s\0", entity.get_prop(e.target, "m_iHealth")))
	client.color_log(200, 200, 200, " health remaining)")
end)

client.set_event_callback("aim_miss", function(e)
	if not ui.get(master_switch) then
		return
	end

	local group = hitgroup_names[e.hitgroup + 1] or "?"

	client.color_log(255, 0, 0, "mytools ~\0")
	client.color_log(200, 200, 200, " Missed shot in\0")
	client.color_log(255, 0, 0, string.format(" %s\'s\0", entity.get_player_name(e.target)))
	client.color_log(255, 0, 0, string.format(" %s\0", group))
	client.color_log(200, 200, 200, " due to\0")
	client.color_log(255, 0, 0, string.format(" %s", e.reason))
end)

client.set_event_callback('player_hurt', function(e)
	if not ui.get(master_switch) then
		return
	end
	
	local attacker_id = client.userid_to_entindex(e.attacker)

	if attacker_id == nil or attacker_id ~= entity.get_local_player() then
        return
    end

	if weapon_to_verb[e.weapon] ~= nil then
        local target_id = client.userid_to_entindex(e.userid)
		local target_name = entity.get_player_name(target_id)

		--print(string.format("%s %s for %i damage (%i remaining)", weapon_to_verb[e.weapon], string.lower(target_name), e.dmg_health, e.health))
		client.color_log(124, 252, 0, "mytools ~\0")
		client.color_log(200, 200, 200, string.format(" %s\0", weapon_to_verb[e.weapon]))
		client.color_log(124, 252, 0, string.format(" %s\0", target_name))
		client.color_log(200, 200, 200, " for\0")
		client.color_log(124, 252, 0, string.format(" %s\0", e.dmg_health))
		client.color_log(200, 200, 200, " damage\0")
		client.color_log(200, 200, 200, " (\0")
		client.color_log(124, 252, 0, string.format("%s\0", e.health))
		client.color_log(200, 200, 200, " health remaining)")
	end
end)

client.set_event_callback('shutdown', function()
    ui.set_visible(reference.pitch[1], true)
    ui.set_visible(reference.yaw_base, true)
    ui.set_visible(reference.yaw[1], true)
    ui.set_visible(reference.body_yaw[1], true)
    ui.set_visible(reference.edge_yaw, true)
    ui.set_visible(reference.freestanding[1], true)
    ui.set_visible(reference.freestanding[2], true)
    ui.set_visible(reference.roll, true)

    cvar.r_aspectratio:set_float(0)

    ui.set(override_zoom_fov, 0)
    ui.set(reference.pitch[1], 'Off')
    ui.set(reference.pitch[2], 0)
    ui.set(reference.yaw_base, 'Local view')
    ui.set(reference.yaw[1], 'Off')
    ui.set(reference.yaw[2], 0)
    ui.set(reference.yaw_jitter[1], 'Off')
    ui.set(reference.yaw_jitter[2], 0)
    ui.set(reference.body_yaw[1], 'Off')
    ui.set(reference.body_yaw[2], 0)
    ui.set(reference.freestanding_body_yaw, false)
    ui.set(reference.edge_yaw, false)
    ui.set(reference.freestanding[1], false)
    ui.set(reference.freestanding[2], 'On hotkey')
    ui.set(reference.roll, 0)
end)

local IsNewClientAvailable = panorama.loadstring([[
	var oldClientStatus = NewsAPI.IsNewClientAvailable;

	return {
		disable: function(){
			NewsAPI.IsNewClientAvailable = function(){ return false };
		},
		restore: function(){
            NewsAPI.IsNewClientAvailable = oldClientStatus;
		}
	}
]])()

IsNewClientAvailable.disable()

client.set_event_callback("shutdown", function()
	IsNewClientAvailable.restore()
end)
