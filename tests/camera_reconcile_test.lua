local camera_state = {X = 0, Y = 0, Z = 0, FocalX = 0, FocalY = 0, FocalZ = 0}
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
    read_float = function() return 0 end,
    read_uint16 = function() return 0 end,
}}
local entity = {
    GetActorPointer = function() return 1 end,
    GetHeading = function() return 0 end,
}
local target = {GetLockedOnFlags = function() return 0 end}
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
    get_camera_rotation_axes = function() return 0, 0 end,
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
assert(camera.begin_scene(settings) == false)

-- Model a one-frame base-game camera adjustment between our scene hooks.
local phi = 1.85
camera_state.X = -7 * math.sin(phi)
camera_state.Y = 0
camera_state.Z = 0.5 + 7 * math.cos(phi)
camera.end_scene(settings)

local observed_distance = math.sqrt(camera_state.X * camera_state.X
    + (camera_state.Z - 0.5) * (camera_state.Z - 0.5))
assert(math.abs(observed_distance - 6) < 0.0001,
    string.format('expected configured exploration distance 6 after transient adjustment, got %.4f', observed_distance))
print('radgamepad camera reconciliation tests passed')
