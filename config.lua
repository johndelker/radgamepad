local config = {}
config.defaults = {
    distance = 6, horizontalOffset = 0, verticalOffset = 0.25,
    lockonDistance = 9, horizontalOffsetLockon = 2, verticalOffsetLockon = 0.5,
    cameraSensitivity = 1.25, horizontalSensitivity = 1, verticalSensitivity = 1,
    invertHorizontal = false, invertVertical = false,
    zoomModifierSource = 1, zoomModifierButton = 16, zoomSpeed = 0.05,
}
config.ranges = {
    distance = {1, 20}, horizontalOffset = {-8, 8}, verticalOffset = {-2, 2},
    lockonDistance = {1, 20}, horizontalOffsetLockon = {-8, 8}, verticalOffsetLockon = {-2, 2},
    cameraSensitivity = {0.1, 3}, horizontalSensitivity = {0.1, 3}, verticalSensitivity = {0.1, 3},
    zoomModifierSource = {0, 2}, zoomModifierButton = {0, 257}, zoomSpeed = {0.05, 0.50},
}
local function normalize(key, value, defaults)
    local default = (defaults and defaults[key])
    if default == nil then default = config.defaults[key] end
    if type(default) == 'boolean' then
        if type(value) == 'boolean' then return value end
        return default
    end
    if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then return default end
    local range = config.ranges[key]
    value = math.max(range[1], math.min(range[2], value))
    if key == 'zoomModifierSource' or key == 'zoomModifierButton' then value = math.floor(value) end
    return value
end
local function read_game_camera_inversion()
    local ok, horizontal, vertical = pcall(function()
        local ffi = require('ffi')
        if not pcall(ffi.typeof, 'radgamepad_get_config_t') then
            ffi.cdef[[typedef int32_t (__cdecl* radgamepad_get_config_t)(int32_t);]]
        end
        local signature = ashita.memory.find(0, 0,
            '8B0D????????85C974??8B44240450E8????????C383C8FFC3', 0, 0)
        if not signature or signature == 0 then return nil, nil end
        local get_config = ffi.cast('radgamepad_get_config_t', signature)
        local x_axis, y_axis = tonumber(get_config(139)), tonumber(get_config(140))
        if (x_axis ~= 0 and x_axis ~= 1) or (y_axis ~= 0 and y_axis ~= 1) then return nil, nil end
        return x_axis == 1, y_axis == 1
    end)
    if not ok then return nil, nil end
    return horizontal, vertical
end
function config.load()
    local manager = AshitaCore:GetConfigurationManager()
    local loaded = manager:Load('radgamepad', 'radgamepad.ini')
    local defaults = {}
    for key, value in pairs(config.defaults) do defaults[key] = value end
    if not loaded then
        local horizontal, vertical = read_game_camera_inversion()
        if horizontal ~= nil then defaults.invertHorizontal = horizontal end
        if vertical ~= nil then defaults.invertVertical = vertical end
    end
    local settings = {}
    for key, default in pairs(defaults) do
        local value = default
        if loaded then
            if type(default) == 'boolean' then value = manager:GetBool('radgamepad', 'default', key, default)
            else value = manager:GetFloat('radgamepad', 'default', key, default) end
        end
        settings[key] = normalize(key, value, defaults)
    end
    return settings
end
function config.save(settings)
    local manager = AshitaCore:GetConfigurationManager()
    manager:Delete('radgamepad', 'radgamepad.ini')
    for key in pairs(config.defaults) do
        settings[key] = normalize(key, settings[key])
        manager:SetValue('radgamepad', 'default', key, tostring(settings[key]))
    end
    manager:Save('radgamepad', 'radgamepad.ini')
end
return config
