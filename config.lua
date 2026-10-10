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
local function normalize(key, value)
    local default = config.defaults[key]
    if type(default) == 'boolean' then return type(value) == 'boolean' and value or default end
    if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then return default end
    local range = config.ranges[key]
    value = math.max(range[1], math.min(range[2], value))
    if key == 'zoomModifierSource' or key == 'zoomModifierButton' then value = math.floor(value) end
    return value
end
function config.load()
    local manager = AshitaCore:GetConfigurationManager()
    local loaded = manager:Load('radgamepad', 'radgamepad.ini')
    local settings = {}
    for key, default in pairs(config.defaults) do
        local value = default
        if loaded then
            if type(default) == 'boolean' then value = manager:GetBool('radgamepad', 'default', key, default)
            else value = manager:GetFloat('radgamepad', 'default', key, default) end
        end
        settings[key] = normalize(key, value)
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
