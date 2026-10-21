local config = {}
config.defaults = {
    distance = 6, horizontalOffset = 0, verticalOffset = 0.25,
    lockonDistance = 9, horizontalOffsetLockon = 2, verticalOffsetLockon = 0.5,
    mountedDistance = 6, mountedHorizontalOffset = 0, mountedVerticalOffset = 0.25,
    cameraSensitivity = 1.25, horizontalSensitivity = 1, verticalSensitivity = 1,
    mouseKeyboardEnabled = true, mouseSensitivity = 1, keyboardSensitivity = 1,
    cameraLeftKey = 203, cameraRightKey = 205, cameraUpKey = 200, cameraDownKey = 208,
    invertHorizontal = false, invertVertical = false,
    zoomModifierSource = 1, zoomModifierButton = 16, zoomSpeed = 0.05,
    panelFont = 'Default', panelFontSize = 16,
    panelBackgroundR = 0.055, panelBackgroundG = 0.045, panelBackgroundB = 0.055, panelBackgroundA = 0.98,
    panelSecondaryR = 0.105, panelSecondaryG = 0.085, panelSecondaryB = 0.10, panelSecondaryA = 1,
    panelTextR = 0.93, panelTextG = 0.91, panelTextB = 0.90, panelTextA = 1,
    panelSecondaryTextR = 0.58, panelSecondaryTextG = 0.56, panelSecondaryTextB = 0.55, panelSecondaryTextA = 1,
    panelHighlightR = 0.36, panelHighlightG = 0.14, panelHighlightB = 0.16, panelHighlightA = 1,
    panelHighlightHoverR = 0.55, panelHighlightHoverG = 0.24, panelHighlightHoverB = 0.25, panelHighlightHoverA = 1,
    panelControlWidth = 220, panelBorderWidth = 1,
}
config.ranges = {
    distance = {1, 20}, horizontalOffset = {-8, 8}, verticalOffset = {-2, 2},
    lockonDistance = {1, 20}, horizontalOffsetLockon = {-8, 8}, verticalOffsetLockon = {-2, 2},
    mountedDistance = {1, 20}, mountedHorizontalOffset = {-8, 8}, mountedVerticalOffset = {-2, 2},
    cameraSensitivity = {0.1, 3}, horizontalSensitivity = {0.1, 3}, verticalSensitivity = {0.1, 3},
    mouseSensitivity = {0.1, 3}, keyboardSensitivity = {0.1, 3},
    cameraLeftKey = {0, 255}, cameraRightKey = {0, 255}, cameraUpKey = {0, 255}, cameraDownKey = {0, 255},
    zoomModifierSource = {0, 2}, zoomModifierButton = {0, 257}, zoomSpeed = {0.05, 0.50},
    panelFontSize = {10, 24}, panelControlWidth = {100, 500}, panelBorderWidth = {0, 5},
    panelBackgroundR = {0, 1}, panelBackgroundG = {0, 1}, panelBackgroundB = {0, 1}, panelBackgroundA = {0, 1},
    panelSecondaryR = {0, 1}, panelSecondaryG = {0, 1}, panelSecondaryB = {0, 1}, panelSecondaryA = {0, 1},
    panelSecondaryTextR = {0, 1}, panelSecondaryTextG = {0, 1}, panelSecondaryTextB = {0, 1}, panelSecondaryTextA = {0, 1},
    panelTextR = {0, 1}, panelTextG = {0, 1}, panelTextB = {0, 1}, panelTextA = {0, 1},
    panelHighlightR = {0, 1}, panelHighlightG = {0, 1}, panelHighlightB = {0, 1}, panelHighlightA = {0, 1},
    panelHighlightHoverR = {0, 1}, panelHighlightHoverG = {0, 1}, panelHighlightHoverB = {0, 1}, panelHighlightHoverA = {0, 1},
}
local function normalize(key, value, defaults)
    local default = (defaults and defaults[key])
    if default == nil then default = config.defaults[key] end
    if type(default) == 'boolean' then
        if type(value) == 'boolean' then return value end
        return default
    elseif type(default) == 'string' then
        if key == 'panelFont' then
            for _, family in ipairs({'Default', 'Arial', 'Calibri', 'Consolas', 'Segoe UI', 'Tahoma', 'Times New Roman', 'Verdana'}) do
                if value == family then return value end
            end
            return default
        end
        return type(value) == 'string' and value or default
    end
    if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then return default end
    local range = config.ranges[key]
    value = math.max(range[1], math.min(range[2], value))
    if key == 'zoomModifierSource' or key == 'zoomModifierButton'
        or key:match('^camera.*Key$') then value = math.floor(value) end
    return value
end
local game_get_config = nil
local game_get_config_resolved = false
local function resolve_game_get_config()
    if game_get_config_resolved then return game_get_config end
    game_get_config_resolved = true
    local ok, result = pcall(function()
        local ffi = require('ffi')
        if not pcall(ffi.typeof, 'moderncam_get_config_t') then
            ffi.cdef[[typedef int32_t (__cdecl* moderncam_get_config_t)(int32_t);]]
        end
        local signature = ashita.memory.find(0, 0,
            '8B0D????????85C974??8B44240450E8????????C383C8FFC3', 0, 0)
        if not signature or signature == 0 then return nil end
        return ffi.cast('moderncam_get_config_t', signature)
    end)
    if ok then game_get_config = result end
    return game_get_config
end
local function read_game_camera_inversion()
    local ok, horizontal, vertical = pcall(function()
        local get_config = resolve_game_get_config()
        if not get_config then return nil, nil end
        local x_axis, y_axis = tonumber(get_config(139)), tonumber(get_config(140))
        if (x_axis ~= 0 and x_axis ~= 1) or (y_axis ~= 0 and y_axis ~= 1) then return nil, nil end
        return x_axis == 1, y_axis == 1
    end)
    if not ok then return nil, nil end
    return horizontal, vertical
end
function config.get_game_config_value(id)
    local ok, value = pcall(function()
        local get_config = resolve_game_get_config()
        if not get_config then return nil end
        return tonumber(get_config(id))
    end)
    if not ok then return nil end
    return value
end
function config.is_edge_panning_enabled()
    return config.get_game_config_value(143) == 0
end
function config.load()
    local manager = AshitaCore:GetConfigurationManager()
    local loaded = manager:Load('moderncam', 'moderncam.ini')
    local config_name = 'moderncam'
    local migrate = false
    if not loaded then
        loaded = manager:Load('radgamepad', 'radgamepad.ini')
        if loaded then config_name, migrate = 'radgamepad', true end
    end
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
            if type(default) == 'boolean' then value = manager:GetBool(config_name, 'default', key, default)
            elseif type(default) == 'string' then value = manager:GetString(config_name, 'default', key) or default
            else value = manager:GetFloat(config_name, 'default', key, default) end
        end
        settings[key] = normalize(key, value, defaults)
    end
    if migrate then config.save(settings) end
    return settings
end
function config.save(settings)
    local manager = AshitaCore:GetConfigurationManager()
    manager:Delete('moderncam', 'moderncam.ini')
    for key in pairs(config.defaults) do
        settings[key] = normalize(key, settings[key])
        manager:SetValue('moderncam', 'default', key, tostring(settings[key]))
    end
    manager:Save('moderncam', 'moderncam.ini')
end
return config
