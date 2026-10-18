local camera_state = {X = 0, Y = 0, Z = 0, FocalX = 0, FocalY = 0, FocalZ = 0}
local player_x = 0
local player_root_x = 0
local horizontal_axis = 0
local is_locked_on = false
local fake_ffi = {
    typeof = function() return true end,
    cast = function(kind, address)
        if kind == 'uint32_t*' then return {[0] = 100} end
        if kind == 'bool*' then return {[0] = true} end
        if kind == 'struct radgamepad_camera_t*' then return camera_state end
        error('unexpected ffi cast: ' .. kind)
    end,
}
package.preload.ffi = function() return fake_ffi end
package.preload.bit = function()
    return {band = function(value, mask) return value % (mask + 1) end}
end

ashita = {memory = {
    find = function(_, _, signature)
        if signature == '83C40485C974118B116A01FF5218C705' then return 10 end
        return 20
    end,
    read_uint32 = function(address)
        if address == 26 then return 30 end
        if address == 20 then return 40 end
        return 0
    end,
    read_float = function(address)
        if address == 0x679 then return player_x end
        return 0
    end,
    read_uint16 = function() return 0 end,
}}
local entity = {
    GetActorPointer = function() return 1 end,
    GetHeading = function() return 0 end,
    GetType = function() return 3 end,
    GetRenderFlags0 = function() return 1 end,
    GetLocalPositionX = function(_, index) return index == 1 and player_root_x or 10 end,
    GetLocalPositionY = function() return 0 end,
    GetLocalPositionZ = function() return 0 end,
}
local target = {
    GetLockedOnFlags = function() return is_locked_on and 1 or 0 end,
    GetTargetIndex = function() return 2 end,
}
local manager = {GetEntity = function() return entity end, GetTarget = function() return target end}
AshitaCore = {GetMemoryManager = function()
    return {
        GetAutoFollow = function() return {GetIsFirstPersonCamera = function() return 0 end} end,
        GetEntity = function() return entity end,
        GetTarget = function() return target end,
    }
end}
GetPlayerEntity = function() return {TargetIndex = 1} end

local input = {
    get_camera_rotation_axes = function() return horizontal_axis, 0 end,
    get_vertical = function() return 0 end,
    zoom_modifier_held = function() return false end,
    adjust_distance = function(distance) return distance, false end,
}
local camera = assert(loadfile('camera.lua'))(input)
camera.initialize()
local settings = {
    distance = 6, lockonDistance = 9,
    horizontalOffset = 0, verticalOffset = 0,
    horizontalOffsetLockon = 0, verticalOffsetLockon = 0,
    cameraSensitivity = 1, horizontalSensitivity = 1, verticalSensitivity = 1,
    invertHorizontal = false, invertVertical = false, zoomSpeed = 0.05,
}
local phi = 1.85
local function set_camera_distance(distance)
    camera_state.X = -distance * math.sin(phi)
    camera_state.Y = 0
    camera_state.Z = 0.5 + distance * math.cos(phi)
end
local function read_camera_distance(origin_x)
    return math.sqrt((camera_state.X - (origin_x or 0)) ^ 2
        + camera_state.Y * camera_state.Y + (camera_state.Z - 0.5) ^ 2)
end

-- The diagnostic samples the native pose before RadGamepad writes its own pose.
set_camera_distance(4.5)
assert(camera.begin_scene(settings, true) == false)
local rgp_distance, vanilla_distance, distance_delta = camera.get_distance_sample()
assert(math.abs(rgp_distance - 6) < 0.0001, 'diagnostic should report configured RadGamepad distance')
assert(math.abs(vanilla_distance - 4.5) < 0.0001, 'diagnostic should capture the pre-override game camera distance')
assert(math.abs(distance_delta - 1.5) < 0.0001, 'diagnostic should report RGP minus vanilla distance')
set_camera_distance(4.5)
camera.end_scene(settings, true)
assert(math.abs(read_camera_distance() - settings.distance) < 0.0001,
    'temporary diagnostic should bypass exploration collision adjustments')

-- Lock-on placement remains custom, but its native collision clamp is ignored too.
is_locked_on = true
assert(camera.begin_scene(settings, true) == false)
set_camera_distance(7)
camera.end_scene(settings, true)
assert(math.abs(read_camera_distance() - settings.lockonDistance) < 0.0001,
    'temporary diagnostic should bypass lock-on collision adjustments')
assert(math.abs(camera_state.FocalX - 10) < 0.0001
    and math.abs(camera_state.FocalZ - 1.5) < 0.0001,
    'lock-on camera should retain Radgamepad target-centered placement')

-- Background frames use the same configured distance without collision feedback.
assert(camera.begin_scene(settings, false) == false)
set_camera_distance(3)
camera.end_scene(settings, false)
assert(math.abs(read_camera_distance() - settings.lockonDistance) < 0.0001,
    'unfocused camera noise should not alter lock-on zoom during the diagnostic')

-- Controller camera rotation should continue to work with FFXI in the background.
is_locked_on = false
horizontal_axis = 0
assert(camera.begin_scene(settings, false) == false)
camera.end_scene(settings, false)
local before_x, before_y = camera_state.X, camera_state.Y
horizontal_axis = 1
assert(camera.begin_scene(settings, false) == false)
camera.end_scene(settings, false)
assert(math.abs(camera_state.X - before_x) + math.abs(camera_state.Y - before_y) > 0.001,
    'camera stick input should still rotate the camera while FFXI is unfocused')
print('radgamepad camera collision bypass tests passed')
