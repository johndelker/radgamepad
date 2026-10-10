addon.name = 'radgamepad'
addon.author = 'SlowCircuit'
addon.version = '1.0.10'
addon.desc = 'Modern third-person gamepad camera with independent configuration.'

require('common')
local ffi = require('ffi')
if not pcall(ffi.typeof, 'radgamepad_xinput_state_t*') then
    ffi.cdef[[
        typedef struct radgamepad_xinput_gamepad_t {
            uint16_t wButtons;
            uint8_t bLeftTrigger;
            uint8_t bRightTrigger;
            int16_t sThumbLX;
            int16_t sThumbLY;
            int16_t sThumbRX;
            int16_t sThumbRY;
        } radgamepad_xinput_gamepad_t;
        typedef struct radgamepad_xinput_state_t {
            uint32_t dwPacketNumber;
            radgamepad_xinput_gamepad_t Gamepad;
        } radgamepad_xinput_state_t;
    ]]
end
local imgui = require('imgui')
-- Load by absolute local path: generic module names cannot collide with another addon.
local directory = debug.getinfo(1, 'S').source:sub(2):match('(.*[\\/])') or './'
local config = dofile(directory .. 'config.lua')
local input = dofile(directory .. 'input.lua')
local camera = assert(loadfile(directory .. 'camera.lua'))(input)
local settings, loaded, zoom_dirty = nil, false, false
local menu_open = {false}

local function flush_zoom()
    if zoom_dirty and settings then
        config.save(settings)
        zoom_dirty = false
    end
end

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
    imgui.SetNextWindowSize({540, 590}, ImGuiCond_Once)
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
        imgui.Spacing(); imgui.Text('Modifiers'); imgui.Separator()
        imgui.Text('Zoom Modifier: ' .. input.zoom_modifier_label(settings))
        slider('Zoom Speed', 'zoomSpeed')
        if input.zoom_binding() then imgui.TextDisabled('Press a gamepad button or trigger to bind...') end
        if imgui.Button('Bind Zoom Modifier') then
            flush_zoom()
            input.begin_zoom_binding()
        end
        imgui.SameLine()
        if imgui.Button('Clear Zoom Modifier') then
            flush_zoom()
            input.clear_zoom_binding(settings)
            config.save(settings)
        end
    end
    imgui.End()
end
ashita.events.register('load', 'radgamepad_load', function()
    settings = config.load()
    camera.initialize()
    input.initialize()
    loaded = true
end)
ashita.events.register('xinput_state', 'radgamepad_xinput_state', function(e)
    if not loaded or not e.state then return end
    local ok, state = pcall(function() return ffi.cast('radgamepad_xinput_state_t*', e.state) end)
    if not ok or state == nil then return end
    local horizontal, vertical
    ok = pcall(function()
        horizontal = tonumber(state.Gamepad.sThumbRX)
        vertical = tonumber(state.Gamepad.sThumbRY)
    end)
    if ok then
        input.update_axes(horizontal, vertical)
        local left, right
        ok = pcall(function()
            left = tonumber(state.Gamepad.bLeftTrigger)
            right = tonumber(state.Gamepad.bRightTrigger)
        end)
        if not ok or left == nil or right == nil then return end
        local _, _, left_released = input.handle_trigger(settings, 'left', left, config.save)
        local _, _, right_released = input.handle_trigger(settings, 'right', right, config.save)
        if left_released or right_released then flush_zoom() end
    end
end)
for _, source in ipairs({'xinput', 'dinput'}) do
    local backend = source
    ashita.events.register(backend .. '_button', 'radgamepad_zoom_' .. backend, function(e)
        if not loaded then return end
        local _, _, released
        _, _, released = input.handle_button(settings, backend, e, config.save)
        if released then flush_zoom() end
    end)
end
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
    if loaded and back_buffer then zoom_dirty = camera.begin_scene(settings) or zoom_dirty end
end)
ashita.events.register('d3d_endscene', 'radgamepad_endscene', function(back_buffer)
    if loaded and back_buffer then camera.end_scene(settings) end
end)
ashita.events.register('packet_in', 'radgamepad_packet_in', function(e)
    if e.id == 0x00A then flush_zoom(); camera.zone_in(); input.initialize()
    elseif e.id == 0x00B then flush_zoom(); camera.logout(); input.shutdown() end -- Zone Out; 0x04B is Delivery Box.
end)
ashita.events.register('unload', 'radgamepad_unload', function()
    loaded = false
    flush_zoom()
    camera.logout()
    input.shutdown()
    if settings then config.save(settings) end
end)
