addon.name = 'radgamepad'
addon.author = 'SlowCircuit'
addon.version = '1.0.10'
addon.desc = 'Modern third-person gamepad camera with independent configuration.'

require('common')
local ffi = require('ffi')
require('win32types')
pcall(ffi.cdef, [[
    HWND __stdcall GetForegroundWindow(void);
    DWORD __stdcall GetWindowThreadProcessId(HWND hWnd, LPDWORD lpdwProcessId);
]])
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
local focus = dofile(directory .. 'focus.lua')
local function game_window_focused()
    local raw_hwnd = AshitaCore:GetProperties():GetFinalFantasyHwnd()
    if raw_hwnd == nil or raw_hwnd == 0 then return false end
    local hwnd = ffi.cast('HWND', raw_hwnd)
    if hwnd == ffi.NULL then return false end
    local foreground = ffi.C.GetForegroundWindow()
    if foreground == nil or foreground == ffi.NULL then return false end
    local function process_id(window)
        local result = ffi.new('DWORD[1]')
        if ffi.C.GetWindowThreadProcessId(window, result) == 0 then return nil end
        return tonumber(result[0])
    end
    return focus.is_game_process_foreground(hwnd, function() return foreground end, process_id)
end
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
local watch_file, watch_label = nil, nil
local function camera_distance_log_path()
    local install_path = AshitaCore:GetInstallPath()
    local separator = install_path:match('[\\/]$') and '' or '\\'
    return install_path .. separator .. 'config\\addons\\radgamepad_camera_distance.log'
end
local function write_camera_distance(file, label)
    local rgp_distance, vanilla_distance, delta = camera.get_distance_sample()
    if delta == nil then return false, 'No camera distance sample is available yet.' end
    local ok, err = file:write(string.format('%s\tRGP=%.4f\tvanilla=%.4f\tdelta=%.4f\n',
        label, rgp_distance, vanilla_distance, delta))
    if not ok then return false, err end
    ok, err = file:flush()
    if not ok then return false, err end
    return true, rgp_distance, vanilla_distance, delta
end
local function log_camera_distance(label)
    local file, err = io.open(camera_distance_log_path(), 'a')
    if not file then
        print('[radgamepad] Could not open camera distance log: ' .. tostring(err))
        return
    end
    local ok, result, vanilla_distance, delta = write_camera_distance(file, label)
    file:close()
    if not ok then
        print('[radgamepad] ' .. tostring(result))
        return
    end
    print(string.format('[radgamepad] Logged %s: RGP %.4f, vanilla %.4f, delta %.4f yalms.',
        label, result, vanilla_distance, delta))
end
local function toggle_camera_distance_watch(label)
    if watch_file then
        watch_file:flush()
        watch_file:close()
        watch_file, watch_label = nil, nil
        print('[radgamepad] Camera distance watch stopped.')
        return
    end
    if not label or label == '' then
        print('[radgamepad] Usage: /rgp watch <label> (run /rgp watch again to stop)')
        return
    end
    local file, err = io.open(camera_distance_log_path(), 'a')
    if not file then
        print('[radgamepad] Could not open camera distance log: ' .. tostring(err))
        return
    end
    watch_file, watch_label = file, label
    print(string.format('[radgamepad] Watching camera distance each frame as "%s". Run /rgp watch again to stop.', label))
end
local function write_watched_camera_distance()
    if not watch_file then return end
    local ok, err = write_camera_distance(watch_file, watch_label)
    if not ok and err ~= 'No camera distance sample is available yet.' then
        print('[radgamepad] Camera distance watch stopped: ' .. tostring(err))
        pcall(function() watch_file:close() end)
        watch_file, watch_label = nil, nil
    end
end
ashita.events.register('command', 'radgamepad_command', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    local command = args[1]:lower()
    if command ~= '/radgamepad' and command ~= '/rgp' then return end
    e.blocked = true
    if command == '/rgp' and #args >= 2 and args[2]:lower() == 'watch' then
        if watch_file then
            toggle_camera_distance_watch()
        elseif #args == 3 then
            toggle_camera_distance_watch(args[3])
        else
            toggle_camera_distance_watch(nil)
        end
        return
    end
    if command == '/rgp' and #args >= 2 and args[2]:lower() == 'log' then
        if #args ~= 3 or args[3] == '' then
            print('[radgamepad] Usage: /rgp log <label>')
            return
        end
        log_camera_distance(args[3])
        return
    end
    if #args ~= 1 then
        print('[radgamepad] Usage: /rgp [log <label> | watch [label]]')
        return
    end
    menu_open[1] = not menu_open[1]
end)
ashita.events.register('d3d_present', 'radgamepad_present', function()
    if loaded and menu_open[1] then draw_menu() end
end)
ashita.events.register('d3d_beginscene', 'radgamepad_beginscene', function(back_buffer)
    if loaded and back_buffer then
        zoom_dirty = camera.begin_scene(settings, game_window_focused()) or zoom_dirty
        write_watched_camera_distance()
    end
end)
ashita.events.register('d3d_endscene', 'radgamepad_endscene', function(back_buffer)
    if loaded and back_buffer then camera.end_scene(settings, game_window_focused()) end
end)
ashita.events.register('packet_in', 'radgamepad_packet_in', function(e)
    if e.id == 0x00A then flush_zoom(); camera.zone_in(); input.initialize()
    elseif e.id == 0x00B then flush_zoom(); camera.logout(); input.shutdown() end -- Zone Out; 0x04B is Delivery Box.
end)
ashita.events.register('unload', 'radgamepad_unload', function()
    loaded = false
    if watch_file then
        pcall(function() watch_file:flush(); watch_file:close() end)
        watch_file, watch_label = nil, nil
    end
    flush_zoom()
    camera.logout()
    input.shutdown()
    if settings then config.save(settings) end
end)
