addon.name = 'moderncam'
addon.author = 'SlowCircuit'
addon.version = '1.0.10'
addon.desc = 'Modern third-person gamepad camera with independent configuration.'

require('common')
local ffi = require('ffi')
require('win32types')
pcall(ffi.cdef, [[
    HWND __stdcall GetForegroundWindow(void);
    DWORD __stdcall GetWindowThreadProcessId(HWND hWnd, LPDWORD lpdwProcessId);
    BOOL __stdcall GetClientRect(HWND hWnd, LPRECT lpRect);
]])
if not pcall(ffi.typeof, 'moderncam_xinput_state_t*') then
    ffi.cdef[[
        typedef struct moderncam_xinput_gamepad_t {
            uint16_t wButtons;
            uint8_t bLeftTrigger;
            uint8_t bRightTrigger;
            int16_t sThumbLX;
            int16_t sThumbLY;
            int16_t sThumbRX;
            int16_t sThumbRY;
        } moderncam_xinput_gamepad_t;
        typedef struct moderncam_xinput_state_t {
            uint32_t dwPacketNumber;
            moderncam_xinput_gamepad_t Gamepad;
        } moderncam_xinput_state_t;
    ]]
end
local imgui = require('imgui')
-- Load by absolute local path: generic module names cannot collide with another addon.
local directory = debug.getinfo(1, 'S').source:sub(2):match('(.*[\\/])') or './'
local config = dofile(directory .. 'config.lua')
local panel = dofile(directory .. 'panel_config.lua')
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
local function update_camera_input_viewport()
    local raw_hwnd = AshitaCore:GetProperties():GetFinalFantasyHwnd()
    if raw_hwnd == nil or raw_hwnd == 0 then input.set_viewport(0, 0); return end
    local rect = ffi.new('RECT[1]')
    local ok = pcall(function()
        if ffi.C.GetClientRect(ffi.cast('HWND', raw_hwnd), rect) ~= 0 then
            input.set_viewport(tonumber(rect[0].right - rect[0].left), tonumber(rect[0].bottom - rect[0].top))
        else
            input.set_viewport(0, 0)
        end
    end)
    if not ok then input.set_viewport(0, 0) end
end
local settings, loaded, zoom_dirty = nil, false, false
local panel_draft = nil
local menu_open = {false}
local menu_page = 1
local game_menu_global = 0

local function resolve_game_menu_global()
    local ok, address = pcall(function()
        return ashita.memory.find('FFXiMain.dll', 0,
            '8B480C85C974??8B510885D274??3B05', 16, 0)
    end)
    game_menu_global = ok and tonumber(address) or 0
end

local function game_menu_open()
    local target_menu_open = false
    local ok = pcall(function()
        local target = AshitaCore:GetMemoryManager():GetTarget()
        target_menu_open = target:GetIsMenuOpen() ~= 0 or target:GetIsSubTargetActive() ~= 0
    end)
    if not ok then target_menu_open = false end
    if target_menu_open then return true end

    if game_menu_global ~= 0 then
        local read_ok, active = pcall(function()
            local menu_pointer = ashita.memory.read_uint32(game_menu_global)
            if menu_pointer == nil or menu_pointer == 0 then return false end
            local menu_value = ashita.memory.read_uint32(menu_pointer)
            return menu_value ~= nil and menu_value ~= 0
        end)
        if read_ok then return active end
    end
    return false
end

local function push_settings_style()
    panel.push_theme(imgui, settings)
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0)
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, settings.panelBorderWidth)
    imgui.PushStyleVar(ImGuiStyleVar_ChildBorderSize, settings.panelBorderWidth)
    imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 5.0)
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 8.0)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {12, 12})
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {8, 7})
    imgui.PushStyleVar(ImGuiStyleVar_GrabMinSize, 5.0)
    imgui.PushStyleVar(ImGuiStyleVar_GrabRounding, 4.0)
end
local function pop_settings_style()
    imgui.PopStyleVar(9)
    panel.pop_theme(imgui)
end
local function flush_zoom()
    if zoom_dirty and settings then
        config.save(settings)
        zoom_dirty = false
    end
end

local function begin_setting_row(label)
    label = panel.setting_label(label, label)
    local start_x = imgui.GetCursorPosX()
    local width = imgui.GetContentRegionAvail()
    imgui.AlignTextToFramePadding()
    imgui.Text(label)
    imgui.SameLine()
    local label_column = math.min(190, math.max(120, width * 0.43))
    imgui.SetCursorPosX(start_x + label_column)
    return math.max(90, width - label_column), start_x, width
end
local function binding_row(label, binding_text, waiting, id, on_bind, on_clear)
    local _, start_x, row_width = begin_setting_row(label)
    local bind_width, clear_width, spacing = 52, 56, 8
    local button_x = start_x + row_width - bind_width - clear_width - spacing
    local label_x = start_x + math.min(190, math.max(120, row_width * 0.43))
    local text_width = imgui.CalcTextSize(binding_text)
    imgui.SetCursorPosX(math.max(label_x, button_x - spacing - text_width))
    if waiting then imgui.TextDisabled(binding_text) else imgui.Text(binding_text) end
    imgui.SameLine()
    imgui.SetCursorPosX(button_x)
    if imgui.Button('Bind##' .. id, {bind_width, 0}) then on_bind() end
    imgui.SameLine()
    if imgui.Button('Clear##' .. id, {clear_width, 0}) then on_clear() end
end
local function combo(label, key, choices, edit_settings, save_on_change)
    local width, start_x, row_width = begin_setting_row(label)
    local target = edit_settings or settings
    local control_width = panel.dropdown_width(settings, width)
    imgui.SetCursorPosX(start_x + row_width - control_width)
    imgui.SetNextItemWidth(control_width)
    imgui.PushStyleVar(ImGuiStyleVar_ButtonTextAlign, {0.5, 0.5})
    if imgui.BeginCombo('##combo_' .. key, tostring(target[key])) then
        for _, choice in ipairs(choices) do
            if panel.centered_selectable(imgui, panel.setting_label(tostring(choice), tostring(choice)), target[key] == choice, settings) then
                target[key] = choice
                if save_on_change ~= false then config.save(settings) end
            end
        end
        imgui.EndCombo()
    end
    imgui.PopStyleVar()
end

local function draw_slider_track(width, ratio)
    local x, y = imgui.GetCursorScreenPos()
    local height = imgui.GetFrameHeight()
    local clamped = math.max(0, math.min(1, ratio))
    local draw = imgui.GetWindowDrawList()
    draw:AddRectFilled({x, y}, {x + width, y + height}, panel.color_u32(imgui, settings, 'Secondary'), height * 0.35)
    if clamped > 0 then
        draw:AddRectFilled({x, y}, {x + width * clamped, y + height}, panel.color_u32(imgui, settings, 'Highlight', 0.70), height * 0.35)
    end
end
local function slider(label, key, edit_settings, save_on_change)
    local available, start_x, row_width = begin_setting_row(label)
    local width = panel.slider_width(settings, available)
    imgui.SetCursorPosX(start_x + row_width - width)
    local target = edit_settings or settings
    -- Each integer tick is 0.05, so dragging and keyboard navigation are discrete.
    local value, range = {math.floor(target[key] * 20 + 0.5)}, config.ranges[key]
    if key:find('^panel') then
        value[1] = math.floor(target[key] + 0.5)
        draw_slider_track(width, (value[1] - range[1]) / math.max(1, range[2] - range[1]))
        imgui.PushStyleColor(ImGuiCol_FrameBg, 0x00392426)
        imgui.PushStyleColor(ImGuiCol_FrameBgHovered, 0x00392426)
        imgui.PushStyleColor(ImGuiCol_FrameBgActive, 0x00392426)
        imgui.SetNextItemWidth(width)
        if imgui.SliderInt('##slider_' .. key, value, range[1], range[2], tostring(value[1]), ImGuiSliderFlags_NoInput) then
            if key == 'panelFontSize' then value[1] = math.max(10, math.min(24, math.floor(value[1] / 2 + 0.5) * 2)) end
            target[key] = value[1]
        end
        imgui.PopStyleColor(3)
        if save_on_change ~= false and imgui.IsItemDeactivatedAfterEdit() then config.save(settings) end
        return
    end
    local minimum, maximum = math.floor(range[1] * 20 + 0.5), math.floor(range[2] * 20 + 0.5)
    draw_slider_track(width, (value[1] - minimum) / math.max(1, maximum - minimum))
    imgui.PushStyleColor(ImGuiCol_FrameBg, 0x00392426)
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, 0x00392426)
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, 0x00392426)
    imgui.SetNextItemWidth(width)
    if imgui.SliderInt('##slider_' .. key, value, minimum, maximum,
        string.format('%.2f', value[1] / 20), ImGuiSliderFlags_NoInput) then
        target[key] = value[1] / 20
    end
    imgui.PopStyleColor(3)
    if save_on_change ~= false and imgui.IsItemDeactivatedAfterEdit() then config.save(settings) end
end
local function toggle_control(key, enabled, configured_width)
    local toggle_width, toggle_height = configured_width or panel.toggle_width(settings), 25
    local x, y = imgui.GetCursorScreenPos()
    local clicked = imgui.InvisibleButton('##toggle_' .. key, {toggle_width, toggle_height})
    local draw = imgui.GetWindowDrawList()
    local right = x + toggle_width
    local bottom = y + toggle_height
    local fill = enabled and panel.color_u32(imgui, settings, 'Highlight', 0.48) or panel.color_u32(imgui, settings, 'Secondary')
    draw:AddRectFilled({x, y}, {right, bottom}, fill, toggle_height * 0.28)
    local inset = 4
    local peg_width = 38
    local peg_x = enabled and (right - peg_width - inset) or (x + inset)
    local peg_color = enabled and panel.color_u32(imgui, settings, 'Highlight') or panel.color_u32(imgui, settings, 'Text', 0.45)
    draw:AddRectFilled({peg_x, y + inset}, {peg_x + peg_width, bottom - inset}, peg_color, 4.0)
    local state = enabled and 'ON' or 'OFF'
    local text_width, text_height = imgui.CalcTextSize(state)
    draw:AddText({x + (toggle_width - text_width) * 0.5, y + (toggle_height - text_height) * 0.5}, panel.color_u32(imgui, settings, 'Text'), state)
    return clicked
end
local function checkbox(label, key)
    local _, start_x, width = begin_setting_row(label)
    local toggle_width = panel.toggle_width(settings, width)
    imgui.SetCursorPosX(start_x + width - toggle_width)
    if toggle_control(key, settings[key], toggle_width) then
        settings[key] = not settings[key]
        config.save(settings)
    end
end
local function settings_card(title, description)
    title, description = panel.section_text(title, description)
    imgui.PushStyleColor(ImGuiCol_ChildBg, panel.color(settings, 'Secondary'))
    imgui.PushStyleColor(ImGuiCol_Border, panel.color(settings, 'Highlight'))
    local card_width = math.max(100, imgui.GetContentRegionAvail() - 12)
    imgui.BeginChild('##card_' .. title, {card_width, 0}, bit.bor(ImGuiChildFlags_Borders, ImGuiChildFlags_AutoResizeY))
    imgui.PopStyleColor(2)
    if not imgui.CollapsingHeader(title, ImGuiTreeNodeFlags_DefaultOpen) then return false end
    if description and description ~= '' then
        imgui.PushStyleColor(ImGuiCol_Text, panel.color(settings, 'SecondaryText'))
        imgui.TextWrapped(description)
        imgui.PopStyleColor()
    end
    return true
end
local function end_settings_card()
    imgui.EndChild()
    imgui.Spacing()
end
local function profile_matrix()
    local columns = {
        {panel.setting_label('Standard','Standard'),'distance','horizontalOffset','verticalOffset'},
        {panel.setting_label('Locked-On','Locked-On'),'lockonDistance','horizontalOffsetLockon','verticalOffsetLockon'},
        {panel.setting_label('Mounted','Mounted'),'mountedDistance','mountedHorizontalOffset','mountedVerticalOffset'},
    }
    local flags = ImGuiTableFlags_SizingStretchSame + ImGuiTableFlags_NoSavedSettings
    local table_width = math.max(100, imgui.GetContentRegionAvail() - 24)
    imgui.PushStyleVar(ImGuiStyleVar_CellPadding, {9, 4})
    if not imgui.BeginTable('##CameraProfileMatrix', 4, flags, {table_width, 0}) then
        imgui.PopStyleVar()
        return
    end
    imgui.TableSetupColumn('##CameraProfileRowLabel', ImGuiTableColumnFlags_WidthFixed + ImGuiTableColumnFlags_NoResize, 112)
    for _, column in ipairs(columns) do
        imgui.TableSetupColumn(column[1], ImGuiTableColumnFlags_WidthStretch + ImGuiTableColumnFlags_NoResize)
    end
    imgui.TableNextRow()
    imgui.TableSetColumnIndex(0)
    for index, column in ipairs(columns) do
        imgui.TableSetColumnIndex(index)
        local available = imgui.GetContentRegionAvail()
        local text_width = imgui.CalcTextSize(column[1])
        imgui.SetCursorPosX(imgui.GetCursorPosX() + math.max(0, (available - text_width) * 0.5))
        imgui.Text(column[1])
    end
    local rows = {{'Distance',2}, {'X Offset',3}, {'Y Offset',4}}
    for _, row in ipairs(rows) do
        imgui.TableNextRow()
        imgui.TableSetColumnIndex(0)
        local label = panel.setting_label(row[1], row[1])
        imgui.AlignTextToFramePadding()
        local available, text_width = imgui.GetContentRegionAvail(), imgui.CalcTextSize(label)
        imgui.SetCursorPosX(imgui.GetCursorPosX() + math.max(0, available - text_width))
        imgui.Text(label)
        for index, column in ipairs(columns) do
            imgui.TableSetColumnIndex(index)
            local key = column[row[2]]
            local range, value = config.ranges[key], {math.floor(settings[key] * 20 + 0.5)}
            local lo, hi = math.floor(range[1] * 20 + 0.5), math.floor(range[2] * 20 + 0.5)
            imgui.SetNextItemWidth(imgui.GetContentRegionAvail())
            if imgui.SliderInt('##profile_' .. key, value, lo, hi,
                string.format('%.2f', value[1] / 20), ImGuiSliderFlags_NoInput) then
                settings[key] = value[1] / 20
            end
            if imgui.IsItemDeactivatedAfterEdit() then config.save(settings) end
        end
    end
    imgui.EndTable()
    imgui.PopStyleVar()
end
local function draw_menu()
    panel.apply_pending_window_pos(imgui)
    imgui.SetNextWindowSize({790, 610}, ImGuiCond_Once)
    local pushed_font = panel.push_font(imgui, settings)
    push_settings_style()
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoCollapse)
    if imgui.Begin('##ModernCamPanel', menu_open, flags) then
        panel.draw_header(imgui, 'ModernCam', menu_open, settings)
        if imgui.BeginChild('##ModernCamSidebar', {158, 0}, ImGuiChildFlags_None) then
            imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 8.0)
            for index, label in ipairs({'Camera Position', 'Camera Rotation', 'Panel Config'}) do
                if panel.draw_navigation_item(imgui, label, index, menu_page == index, settings) then menu_page = index end
            end
            imgui.PopStyleVar()
        end
        imgui.EndChild(); imgui.SameLine()
        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, {26, 12})
        local page_width = imgui.GetContentRegionAvail() + 6
        local page_open = imgui.BeginChild('##ModernCamPage', {page_width, 0}, ImGuiChildFlags_None)
        imgui.PopStyleVar()
        if page_open then
            if menu_page == 1 then
                if settings_card('Camera Profiles', 'Set distance and framing for standard, locked-on, and mounted camera modes.') then profile_matrix() end
                end_settings_card()
                if settings_card('Zoom Modifier', 'Hold the binding and move the right thumbstick up or down to adjust the active camera profile distance.') then
                    binding_row('Zoom Modifier', input.zoom_binding() and 'Press a button...' or input.zoom_modifier_label(settings),
                        input.zoom_binding(), 'zoom_modifier', function()
                            flush_zoom(); input.begin_zoom_binding()
                        end, function()
                            flush_zoom(); input.clear_zoom_binding(settings); config.save(settings)
                        end)
                    slider('Zoom Speed', 'zoomSpeed')
                end
                end_settings_card()
            elseif menu_page == 2 then
                if settings_card('Camera Rotation', 'Adjust the right thumbstick, arrow keys, and mouse-edge camera panning.') then
                    slider('Sensitivity', 'cameraSensitivity')
                    slider('Horizontal Multiplier', 'horizontalSensitivity')
                    slider('Vertical Multiplier', 'verticalSensitivity')
                    checkbox('Invert Horizontal', 'invertHorizontal')
                    checkbox('Invert Vertical', 'invertVertical')
                end
                end_settings_card()
                if settings_card('Mouse and Keyboard', 'Bind camera directions to the keys you use in FFXI. The mouse pans when its cursor reaches a game-window edge.') then
                    checkbox('Enable Mouse and Keyboard', 'mouseKeyboardEnabled')
                    slider('Mouse Sensitivity', 'mouseSensitivity')
                    slider('Keyboard Sensitivity', 'keyboardSensitivity')
                    for _, direction in ipairs({'left', 'right', 'up', 'down'}) do
                        local label = direction:sub(1, 1):upper() .. direction:sub(2)
                        local key = 'camera' .. label .. 'Key'
                        binding_row('Camera ' .. label .. ' Key',
                            input.camera_key_binding() == direction and 'Press a key...' or input.camera_key_label(settings, direction),
                            input.camera_key_binding() == direction, 'camera_' .. direction,
                            function() input.begin_camera_key_binding(direction) end,
                            function()
                            settings[key] = 0
                            config.save(settings)
                            end)
                    end
                end
                end_settings_card()
            else
                panel.draw_config(imgui, settings, panel_draft, config, slider, combo, settings_card, end_settings_card, begin_setting_row)
            end
        end
        imgui.EndChild()
    end
    imgui.End(); pop_settings_style(); panel.pop_font(imgui, pushed_font)
end
ashita.events.register('load', 'moderncam_load', function()
    settings = config.load()
    panel.initialize(imgui)
    if not panel.has_font(settings.panelFont) then settings.panelFont = 'Default'; config.save(settings) end
    panel_draft = {panelFont = settings.panelFont, panelFontSize = settings.panelFontSize,
        panelControlWidth = settings.panelControlWidth, panelBorderWidth = settings.panelBorderWidth}
    camera.initialize()
    input.initialize()
    resolve_game_menu_global()
    update_camera_input_viewport()
    loaded = true
end)
ashita.events.register('xinput_state', 'moderncam_xinput_state', function(e)
    if not loaded or not e.state then return end
    local ok, state = pcall(function() return ffi.cast('moderncam_xinput_state_t*', e.state) end)
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
ashita.events.register('key_data', 'moderncam_camera_keys', function(e)
    if not loaded then return end
    input.handle_key(settings, e, menu_open[1], config.save, game_menu_open())
end)
ashita.events.register('mouse', 'moderncam_camera_mouse', function(e)
    if not loaded then return end
    input.handle_mouse(settings, e, menu_open[1] or game_menu_open(), config.is_edge_panning_enabled())
end)
for _, source in ipairs({'xinput', 'dinput'}) do
    local backend = source
    ashita.events.register(backend .. '_button', 'moderncam_zoom_' .. backend, function(e)
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
    return install_path .. separator .. 'config\\addons\\moderncam_camera_distance.log'
end
local function write_camera_distance(file, label)
    local rgp_distance, vanilla_distance, delta = camera.get_distance_sample()
    if delta == nil then return false, 'No camera distance sample is available yet.' end
    local ok, err = file:write(string.format('%s\tModernCam=%.4f\tvanilla=%.4f\tdelta=%.4f\n',
        label, rgp_distance, vanilla_distance, delta))
    if not ok then return false, err end
    ok, err = file:flush()
    if not ok then return false, err end
    return true, rgp_distance, vanilla_distance, delta
end
local function log_camera_distance(label)
    local file, err = io.open(camera_distance_log_path(), 'a')
    if not file then
        print('[ModernCam] Could not open camera distance log: ' .. tostring(err))
        return
    end
    local ok, result, vanilla_distance, delta = write_camera_distance(file, label)
    file:close()
    if not ok then
        print('[ModernCam] ' .. tostring(result))
        return
    end
    print(string.format('[ModernCam] Logged %s: ModernCam %.4f, vanilla %.4f, delta %.4f yalms.',
        label, result, vanilla_distance, delta))
end
local function toggle_camera_distance_watch(label)
    if watch_file then
        watch_file:flush()
        watch_file:close()
        watch_file, watch_label = nil, nil
        print('[ModernCam] Camera distance watch stopped.')
        return
    end
    if not label or label == '' then
        print('[ModernCam] Usage: /mc watch <label> (run /mc watch again to stop)')
        return
    end
    local file, err = io.open(camera_distance_log_path(), 'a')
    if not file then
        print('[ModernCam] Could not open camera distance log: ' .. tostring(err))
        return
    end
    watch_file, watch_label = file, label
    print(string.format('[ModernCam] Watching camera distance each frame as "%s". Run /mc watch again to stop.', label))
end
local function write_watched_camera_distance()
    if not watch_file then return end
    local ok, err = write_camera_distance(watch_file, watch_label)
    if not ok and err ~= 'No camera distance sample is available yet.' then
        print('[ModernCam] Camera distance watch stopped: ' .. tostring(err))
        pcall(function() watch_file:close() end)
        watch_file, watch_label = nil, nil
    end
end
ashita.events.register('command', 'moderncam_command', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    local command = args[1]:lower()
    if command ~= '/moderncam' and command ~= '/mc' then return end
    e.blocked = true
    if #args >= 2 and args[2]:lower() == 'watch' then
        if watch_file then
            toggle_camera_distance_watch()
        elseif #args == 3 then
            toggle_camera_distance_watch(args[3])
        else
            toggle_camera_distance_watch(nil)
        end
        return
    end
    if #args == 2 and args[2]:lower() == 'edgecheck' then
        local value = config.get_game_config_value(143)
        local enabled, x, y = input.get_edge_pan_state()
        print(string.format('[ModernCam] Screen Edge Panning: config 143=%s, enabled=%s, active axes=(%.2f, %.2f).',
            value == nil and 'unavailable' or tostring(value), enabled and 'yes' or 'no', x, y))
        return
    end
    if #args >= 2 and args[2]:lower() == 'log' then
        if #args ~= 3 or args[3] == '' then
            print('[ModernCam] Usage: /mc log <label>')
            return
        end
        log_camera_distance(args[3])
        return
    end
    if #args ~= 1 then
        print('[ModernCam] Usage: /mc [edgecheck | log <label> | watch [label]]')
        return
    end
    menu_open[1] = not menu_open[1]
end)
ashita.events.register('d3d_present', 'moderncam_present', function()
    if loaded and menu_open[1] then draw_menu() end
end)
ashita.events.register('d3d_beginscene', 'moderncam_beginscene', function(back_buffer)
    if loaded and back_buffer then
        input.set_menu_open(menu_open[1] or game_menu_open())
        input.set_edge_panning_enabled(config.is_edge_panning_enabled())
        local focused = game_window_focused()
        if not focused then
            input.clear_mouse_input()
            input.clear_mouse_buttons()
        end
        zoom_dirty = camera.begin_scene(settings, focused) or zoom_dirty
        update_camera_input_viewport()
        write_watched_camera_distance()
    end
end)
ashita.events.register('d3d_endscene', 'moderncam_endscene', function(back_buffer)
    if loaded and back_buffer then camera.end_scene(settings, game_window_focused()) end
end)
ashita.events.register('packet_in', 'moderncam_packet_in', function(e)
    if e.id == 0x00A then flush_zoom(); camera.zone_in(); input.initialize()
    elseif e.id == 0x00B then flush_zoom(); camera.logout(); input.shutdown() end -- Zone Out; 0x04B is Delivery Box.
end)
ashita.events.register('unload', 'moderncam_unload', function()
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
