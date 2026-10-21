-- Camera behavior extracted from moderncam.lua (SlowCircuit).
local input = ...
local ffi = require('ffi')
local bit = require('bit')
if not pcall(ffi.typeof, 'struct moderncam_camera_t') then
    ffi.cdef[[
        struct moderncam_camera_t {
            uint8_t Unknown0000[0x44];
            float X, Z, Y;
            float FocalX, FocalZ, FocalY;
        };
    ]]
end
local camera_module = {}
local base_camera, connected, follow
local ready, just_zoned, began = false, true, false
local theta, phi, player_heading = 0, 1.85, 0
local player_x, player_y, player_z = 0, 0, 0
local target_x, target_y, target_z = 0, 0, 0
local locked_on = false
local mounted = false
--[[
TEMPORARY COLLISION TEST: the old sampling/adjustment implementation is
kept here as comments so it can be restored after the zoom-jitter check.
local COLLISION_DISTANCE_EPSILON = 0.05
local LOCKON_COLLISION_IMMEDIATE = 0.5
local LOCKON_FOCAL_EPSILON = 0.15
local LOCKON_COLLISION_STABILITY = 0.75
local LOCKON_COLLISION_TREND_TOLERANCE = 0.02
local LOCKON_COLLISION_CONFIRM_SAMPLES = 3
local lockon_collision_base, lockon_collision_pending, lockon_collision_confirmed, lockon_collision_pending_samples
]]
local began_distance, began_focused = nil, true
local last_rgp_distance, last_vanilla_distance, last_distance_delta = nil, nil, nil

function camera_module.initialize()
    local pointer_signature = ashita.memory.find('FFXiMain.dll', 0, '83C40485C974118B116A01FF5218C705', 0, 0)
    if not pointer_signature or pointer_signature == 0 then error('[ModernCam] Missing camera signature.') end
    local slot = ashita.memory.read_uint32(pointer_signature + 0x10)
    if not slot or slot == 0 then error('[ModernCam] Missing camera pointer.') end
    local connection_signature = ashita.memory.find('FFXiMain.dll', 0, '80A0B2000000FBC605????????00', 0x09, 0)
    if not connection_signature or connection_signature == 0 then error('[ModernCam] Missing camera connection signature.') end
    local connection = ashita.memory.read_uint32(connection_signature)
    if not connection or connection == 0 then error('[ModernCam] Missing camera connection pointer.') end
    base_camera = ffi.cast('uint32_t*', slot)
    connected = ffi.cast('bool*', connection)
    follow = AshitaCore:GetMemoryManager():GetAutoFollow()
    ready = true
end

local function get_camera()
    if not ready or not base_camera or not connected or not connected[0]
        or follow:GetIsFirstPersonCamera() ~= 0 or GetPlayerEntity() == nil then return nil end
    local address = base_camera[0]
    if not address or address == 0 then return nil end
    return ffi.cast('struct moderncam_camera_t*', address)
end

local function get_bone(actor, bone)
    if not actor or actor == 0 then return nil end
    local x = ashita.memory.read_float(actor + 0x678)
    local y = ashita.memory.read_float(actor + 0x680)
    local z = ashita.memory.read_float(actor + 0x67C)
    local skeleton_base = ashita.memory.read_uint32(actor + 0x6B8)
    if not skeleton_base or skeleton_base == 0 then return x, y, z end
    local skeleton_offset = ashita.memory.read_uint32(skeleton_base + 0x0C)
    if not skeleton_offset or skeleton_offset == 0 then return x, y, z end
    local skeleton = ashita.memory.read_uint32(skeleton_offset)
    if not skeleton or skeleton == 0 then return x, y, z end
    local count = ashita.memory.read_uint16(skeleton + 0x32)
    if bone >= count then return x, y, z end
    local generators = skeleton + 0x30 + 0x04 + 0x1E * count + 4
    return x + ashita.memory.read_float(generators + bone * 0x1A + 0x0E),
        y + ashita.memory.read_float(generators + bone * 0x1A + 0x16),
        z + ashita.memory.read_float(generators + bone * 0x1A + 0x12)
end

local function update_anchors()
    local player = GetPlayerEntity()
    if not player then return false end
    local manager = AshitaCore:GetMemoryManager()
    local entity, target = manager:GetEntity(), manager:GetTarget()
    -- Follow the rendered player transform for responsive movement and the
    -- original camera height; entity-table roots lag behind animated models.
    local x, y, z = get_bone(entity:GetActorPointer(player.TargetIndex), 2)
    if x == nil then return false end
    player_x, player_y, player_z = x, y, z + 0.5
    player_heading = entity:GetHeading(player.TargetIndex) % (math.pi * 2)
    locked_on = bit.band(target:GetLockedOnFlags(), 1) == 1
    local mount_id = 0
    pcall(function() mount_id = entity:GetMountId(player.TargetIndex) or 0 end)
    mounted = mount_id ~= 0
    if locked_on then
        local index = target:GetTargetIndex(0)
        if not index or index <= 0 or index >= 0x900 then locked_on = false; return true end
        local entity_type, flags = entity:GetType(index), entity:GetRenderFlags0(index)
        if entity_type == 3 then
            target_x, target_y, target_z = entity:GetLocalPositionX(index), entity:GetLocalPositionY(index), entity:GetLocalPositionZ(index)
        elseif flags == 0 and entity_type == 0 then
            target_x, target_y, target_z = entity:GetLastPositionX(index), entity:GetLastPositionY(index), entity:GetLastPositionZ(index)
        else
            local tx, ty, tz = get_bone(entity:GetActorPointer(index), 2)
            if tx == nil then locked_on = false; return true end
            target_x, target_y, target_z = tx, ty, tz
        end
        target_z = target_z + 1.5
    end
    return true
end

local function update_rotation(settings)
    if just_zoned then theta, phi, just_zoned = player_heading, 1.85, false end
    local horizontal_axis, vertical_axis = input.get_camera_rotation_axes(settings)
    local horizontal_direction = settings.invertHorizontal and 1 or -1
    theta = (theta + horizontal_axis * horizontal_direction * 0.033333
        * settings.cameraSensitivity * settings.horizontalSensitivity) % (math.pi * 2)
    local vertical_direction = settings.invertVertical and -1 or 1
    phi = math.max(0.5, math.min(math.pi - 0.5, phi + vertical_axis * vertical_direction
        * 0.033333 * settings.cameraSensitivity * settings.verticalSensitivity))
end

local function offsets(settings)
    local horizontal = -(mounted and settings.mountedHorizontalOffset
        or locked_on and settings.horizontalOffsetLockon or settings.horizontalOffset)
    local vertical = -(mounted and settings.mountedVerticalOffset
        or locked_on and settings.verticalOffsetLockon or settings.verticalOffset)
    return horizontal * math.sin(theta), horizontal * math.cos(theta), vertical
end

local function reset_lockon_collision()
    lockon_collision_base, lockon_collision_pending, lockon_collision_confirmed,
        lockon_collision_pending_samples = nil, nil, nil, nil
end

local function observe_lockon_collision(measured, settings)
    local requested_distance = settings.lockonDistance
    if lockon_collision_base ~= requested_distance then
        lockon_collision_base, lockon_collision_pending, lockon_collision_confirmed,
            lockon_collision_pending_samples = requested_distance, nil, nil, nil
    end
    if measured >= requested_distance - COLLISION_DISTANCE_EPSILON then
        lockon_collision_pending, lockon_collision_confirmed, lockon_collision_pending_samples = nil, nil, nil
        return requested_distance
    end
    if requested_distance - measured >= LOCKON_COLLISION_IMMEDIATE then
        lockon_collision_pending, lockon_collision_confirmed, lockon_collision_pending_samples = nil, measured, nil
        return measured
    end
    if lockon_collision_confirmed ~= nil
        and math.abs(measured - lockon_collision_confirmed) <= LOCKON_COLLISION_STABILITY then
        lockon_collision_pending = nil
        return lockon_collision_confirmed
    end
    if lockon_collision_pending ~= nil
        and measured <= lockon_collision_pending + LOCKON_COLLISION_TREND_TOLERANCE
        and lockon_collision_pending - measured <= LOCKON_COLLISION_STABILITY then
        lockon_collision_pending = measured
        lockon_collision_pending_samples = (lockon_collision_pending_samples or 1) + 1
        if lockon_collision_pending_samples >= LOCKON_COLLISION_CONFIRM_SAMPLES then
            lockon_collision_confirmed, lockon_collision_pending,
                lockon_collision_pending_samples = measured, nil, nil
            return measured
        end
    else
        lockon_collision_pending, lockon_collision_pending_samples = measured, 1
    end
    return lockon_collision_confirmed or requested_distance
end

local function lockon_camera_distance(camera, settings)
    -- If the game replaced the target-centered focal point, the XYZ pose is its
    -- native lock-on camera pose rather than a collision adjustment to ours.
    if math.abs(camera.FocalX - target_x) > LOCKON_FOCAL_EPSILON
        or math.abs(camera.FocalY - target_y) > LOCKON_FOCAL_EPSILON
        or math.abs(camera.FocalZ - target_z) > LOCKON_FOCAL_EPSILON then
        return nil
    end
    theta = -math.atan2(target_y - player_y, target_x - player_x) % (math.pi * 2)
    phi = 1.85
    local ox, oy, oz = offsets(settings)
    local anchor_x, anchor_y, anchor_z = player_x + ox, player_y + oy, player_z + oz
    local actual_x, actual_y, actual_z = camera.X - anchor_x, camera.Y - anchor_y,
        camera.Z - anchor_z
    local measured = math.sqrt(actual_x * actual_x + actual_y * actual_y + actual_z * actual_z)
    return math.max(1, measured)
end

local function get_lockon_collision_distance(settings)
    if lockon_collision_base ~= settings.lockonDistance then
        lockon_collision_base, lockon_collision_pending, lockon_collision_confirmed,
            lockon_collision_pending_samples = settings.lockonDistance, nil, nil, nil
    end
    return lockon_collision_confirmed or settings.lockonDistance
end
local function update_position(camera, distance, settings)
    if locked_on then
        theta = -math.atan2(target_y - player_y, target_x - player_x) % (math.pi * 2)
        phi = 1.85
    end
    local ox, oy, oz = offsets(settings)
    local ax, ay, az = player_x + ox, player_y + oy, player_z + oz
    camera.FocalX = locked_on and target_x or ax
    camera.FocalY = locked_on and target_y or ay
    camera.FocalZ = locked_on and target_z or az
    camera.X = ax - distance * math.sin(phi) * math.cos(-theta)
    camera.Y = ay - distance * math.sin(phi) * math.sin(-theta)
    camera.Z = az + distance * math.cos(phi)
end

function camera_module.begin_scene(settings, focused)
    last_rgp_distance, last_vanilla_distance, last_distance_delta = nil, nil, nil
    began = false
    began_focused = focused ~= false
    local camera = get_camera()
    if camera == nil then return false end
    if not update_anchors() then return false end
    local distance_key = mounted and 'mountedDistance' or (locked_on and 'lockonDistance' or 'distance')
    -- Capture the game camera before RadGamepad overwrites its pose.
    if locked_on then
        theta = -math.atan2(target_y - player_y, target_x - player_x) % (math.pi * 2)
    end
    local ox, oy, oz = offsets(settings)
    local anchor_x, anchor_y, anchor_z = player_x + ox, player_y + oy, player_z + oz
    local dx, dy, dz = camera.X - anchor_x, camera.Y - anchor_y, camera.Z - anchor_z
    local vanilla_distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    -- TEMPORARY COLLISION TEST: use the configured distance directly.
    local applied_distance = settings[distance_key]
    -- Camera controls stay live even when the game window is in the background.
    update_rotation(settings)
    local adjusted_distance, zoomed = input.adjust_distance(settings[distance_key], input.get_vertical(),
        input.zoom_modifier_held(settings), settings.zoomSpeed, 1, 20)
    if zoomed then
        settings[distance_key] = adjusted_distance
        applied_distance = adjusted_distance
    end
    began_distance = applied_distance
    last_rgp_distance = applied_distance
    last_vanilla_distance = vanilla_distance
    last_distance_delta = applied_distance - vanilla_distance
    update_position(camera, applied_distance, settings)
    began = true
    return zoomed
end

function camera_module.end_scene(settings, focused)
    if not began then return end
    began = false
    local camera = get_camera()
    if camera == nil then return end
    -- Keep the custom pose stable while the game window is in the background.
    if not began_focused or focused == false then
        if update_anchors() then update_position(camera, began_distance, settings) end
        return
    end
    local previous_lock_state = locked_on
    if not update_anchors() then return end
    if locked_on ~= previous_lock_state then
        update_position(camera, began_distance, settings)
        return
    end
    --[[ TEMPORARY COLLISION TEST: skip native collision sampling and distance
    correction in both exploration and lock-on modes.
    local previous_lock_state = locked_on
    if not update_anchors() then return end
    if locked_on ~= previous_lock_state then
        reset_lockon_collision()
        update_position(camera, locked_on and settings.lockonDistance or settings.distance, settings)
        return
    end
    if locked_on then
        local measured = lockon_camera_distance(camera, settings)
        if measured == nil then
            lockon_collision_pending, lockon_collision_pending_samples = nil, nil
            update_position(camera, get_lockon_collision_distance(settings), settings)
            return
        end
        local applied = observe_lockon_collision(measured, settings)
        update_position(camera, applied, settings)
        return
    end
    -- Preserve camera collision correction, including player movement during the frame.
    local ox, oy, oz = offsets(settings)
    local dx, dy, dz = camera.X - player_x - ox, camera.Y - player_y - oy,
        camera.Z - player_z - oz
    local distance = dx * -math.sin(phi) * math.cos(-theta)
        + dy * -math.sin(phi) * math.sin(-theta) + dz * math.cos(phi)
    if distance >= settings.distance - COLLISION_DISTANCE_EPSILON then
        distance = settings.distance
    end
    update_position(camera, distance, settings)
    ]]
    local distance_key = mounted and 'mountedDistance' or (locked_on and 'lockonDistance' or 'distance')
    update_position(camera, settings[distance_key], settings)
end

function camera_module.get_distance_sample()
    return last_rgp_distance, last_vanilla_distance, last_distance_delta
end
function camera_module.zone_in()
    ready, just_zoned, began = base_camera ~= nil, true, false
    last_rgp_distance, last_vanilla_distance, last_distance_delta = nil, nil, nil
end
function camera_module.logout() ready, began = false, false end
return camera_module
