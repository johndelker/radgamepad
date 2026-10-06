-- Camera behavior extracted from moderncam.lua (SlowCircuit).
local input = ...
local ffi = require('ffi')
local bit = require('bit')
if not pcall(ffi.typeof, 'struct radgamepad_camera_t') then
    ffi.cdef[[
        struct radgamepad_camera_t {
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

function camera_module.initialize()
    local pointer_signature = ashita.memory.find('FFXiMain.dll', 0, '83C40485C974118B116A01FF5218C705', 0, 0)
    if not pointer_signature or pointer_signature == 0 then error('[radgamepad] Missing camera signature.') end
    local slot = ashita.memory.read_uint32(pointer_signature + 0x10)
    if not slot or slot == 0 then error('[radgamepad] Missing camera pointer.') end
    local connection_signature = ashita.memory.find('FFXiMain.dll', 0, '80A0B2000000FBC605????????00', 0x09, 0)
    if not connection_signature or connection_signature == 0 then error('[radgamepad] Missing camera connection signature.') end
    local connection = ashita.memory.read_uint32(connection_signature)
    if not connection or connection == 0 then error('[radgamepad] Missing camera connection pointer.') end
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
    return ffi.cast('struct radgamepad_camera_t*', address)
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
    local x, y, z = get_bone(entity:GetActorPointer(player.TargetIndex), 2)
    if x == nil then return false end
    player_x, player_y, player_z = x, y, z + 0.5
    player_heading = entity:GetHeading(player.TargetIndex) % (math.pi * 2)
    locked_on = bit.band(target:GetLockedOnFlags(), 1) == 1
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
    input.connect_gamepad()
    if just_zoned then theta, phi, just_zoned = player_heading, 1.85, false end
    local horizontal_direction = settings.invertHorizontal and -1 or 1
    theta = (theta + input.get_horizontal() * horizontal_direction * 0.033333
        * settings.cameraSensitivity * settings.horizontalSensitivity) % (math.pi * 2)
    local vertical_direction = settings.invertVertical and -1 or 1
    phi = math.max(0.5, math.min(math.pi - 0.5, phi + input.get_vertical() * vertical_direction
        * 0.033333 * settings.cameraSensitivity * settings.verticalSensitivity))
end

local function offsets(settings)
    local horizontal = -(locked_on and settings.horizontalOffsetLockon or settings.horizontalOffset)
    local vertical = -(locked_on and settings.verticalOffsetLockon or settings.verticalOffset)
    return horizontal * math.sin(theta), horizontal * math.cos(theta), vertical
end

local function update_position(camera, distance, settings)
    local ox, oy, oz = offsets(settings)
    local ax, ay, az = player_x + ox, player_y + oy, player_z + oz
    if locked_on then
        theta = -math.atan2(target_y - player_y, target_x - player_x) % (math.pi * 2)
        phi = 1.85
    end
    camera.FocalX = locked_on and target_x or ax
    camera.FocalY = locked_on and target_y or ay
    camera.FocalZ = locked_on and target_z or az
    camera.X = ax - distance * math.sin(phi) * math.cos(-theta)
    camera.Y = ay - distance * math.sin(phi) * math.sin(-theta)
    camera.Z = az + distance * math.cos(phi)
end

function camera_module.begin_scene(settings)
    began = false
    local camera = get_camera()
    if camera == nil or not update_anchors() then return end
    update_rotation(settings)
    update_position(camera, locked_on and settings.lockonDistance or settings.distance, settings)
    began = true
end

function camera_module.end_scene(settings)
    if not began then return end
    began = false
    local camera = get_camera()
    if camera == nil then return end
    -- Keep the game's collision correction, excluding planar offsets from distance.
    local ox, oy, oz = offsets(settings)
    local dx, dy, dz = camera.X - player_x - ox, camera.Y - player_y - oy, camera.Z - player_z - oz
    local distance = dx * -math.sin(phi) * math.cos(-theta)
        + dy * -math.sin(phi) * math.sin(-theta) + dz * math.cos(phi)
    if not update_anchors() then return end
    update_position(camera, distance, settings)
end

function camera_module.zone_in() ready, just_zoned, began = base_camera ~= nil, true, false end
function camera_module.logout() ready, began = false, false end
return camera_module
