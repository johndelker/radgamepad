addon.name = 'radgamepad'
addon.author = 'SlowCircuit'
addon.version = '1.0.3'
addon.desc = 'Modern third-person gamepad camera with independent configuration.'

require('common')
local imgui = require('imgui')
-- Load by absolute local path: generic module names cannot collide with another addon.
local directory = debug.getinfo(1, 'S').source:sub(2):match('(.*[\\/])') or './'
local config = dofile(directory .. 'config.lua')
local input = dofile(directory .. 'input.lua')
local camera = assert(loadfile(directory .. 'camera.lua'))(input)
local settings, loaded = nil, false
local menu_open = {false}

local function slider(label, key)
    -- Each integer tick is 0.05, so dragging and keyboard navigation are discrete.
    local value, range = {math.floor(settings[key] * 20 + 0.5)}, config.ranges[key]
    imgui.SetNextItemWidth(300)
    -- Display real camera units and prevent text entry of internal tick counts.
    if imgui.SliderInt(label, value, math.floor(range[1] * 20 + 0.5), math.floor(range[2] * 20 + 0.5),
        string.format('%.2f', value[1] / 20), ImGuiSliderFlags_NoInput) then
        settings[key] = value[1] / 20
    end
    if imgui.IsItemDeactivatedAfterEdit() then config.save(settings) end
end
local function checkbox(label, key)
    local value = {settings[key]}
    if imgui.Checkbox(label, value) then settings[key] = value[1]; config.save(settings) end
end
local function draw_menu()
    imgui.SetNextWindowSize({540, 520}, ImGuiCond_Once)
    if imgui.Begin('Rad Gamepad', menu_open) then
        imgui.Text('Exploration Camera'); imgui.Separator()
        slider('Camera Distance##exploration', 'distance')
        slider('Horizontal Offset##exploration', 'horizontalOffset')
        slider('Vertical Offset##exploration', 'verticalOffset')
        imgui.Spacing(); imgui.Text('Lock-on Camera'); imgui.Separator()
        slider('Camera Distance##lockon', 'lockonDistance')
        slider('Horizontal Offset##lockon', 'horizontalOffsetLockon')
        slider('Vertical Offset##lockon', 'verticalOffsetLockon')
        imgui.Spacing(); imgui.Text('Camera Rotation'); imgui.Separator()
        slider('Sensitivity', 'cameraSensitivity')
        slider('Horizontal Multiplier', 'horizontalSensitivity')
        slider('Vertical Multiplier', 'verticalSensitivity')
        checkbox('Invert Horizontal', 'invertHorizontal')
        checkbox('Invert Vertical', 'invertVertical')
    end
    imgui.End()
end
ashita.events.register('load', 'radgamepad_load', function()
    settings = config.load()
    camera.initialize()
    input.initialize()
    loaded = true
end)
ashita.events.register('command', 'radgamepad_command', function(e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/radgamepad' then return end
    e.blocked = true
    menu_open[1] = not menu_open[1]
end)
ashita.events.register('d3d_present', 'radgamepad_present', function()
    if loaded and menu_open[1] then draw_menu() end
end)
ashita.events.register('d3d_beginscene', 'radgamepad_beginscene', function(back_buffer)
    if loaded and back_buffer then camera.begin_scene(settings) end
end)
ashita.events.register('d3d_endscene', 'radgamepad_endscene', function(back_buffer)
    if loaded and back_buffer then camera.end_scene(settings) end
end)
ashita.events.register('packet_in', 'radgamepad_packet_in', function(e)
    if e.id == 0x00A then camera.zone_in()
    elseif e.id == 0x00B then camera.logout() end -- Zone Out; 0x04B is Delivery Box.
end)
ashita.events.register('unload', 'radgamepad_unload', function()
    loaded = false
    camera.logout()
    input.shutdown()
    if settings then config.save(settings) end
end)
