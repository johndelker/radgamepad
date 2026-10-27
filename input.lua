-- Controller axes are updated from Ashita's xinput_state event in moderncam.lua.
local directory = debug.getinfo(1, 'S').source:sub(2):match('(.*[\\/])') or './'
local axes = dofile(directory .. 'input_axes.lua')
local input = {}
local source_ids = {xinput = 1, dinput = 2}
local held, binding = {}, false
local trigger_held = {left = false, right = false}
local viewport_width, viewport_height = 0, 0
local mouse_edge_x, mouse_edge_y = 0, 0
local edge_panning_enabled = false
local ui_menu_open = false
local mouse_buttons = {left = false, right = false}
local mouse_drag_x, mouse_drag_y = 0, 0
local mouse_last_x, mouse_last_y = nil, nil
local camera_cursor_drag_x, camera_cursor_drag_y = 0, 0
local camera_cursor_was_active = false
local keyboard_held = {up = false, down = false, left = false, right = false}
local camera_key_binding = nil
local camera_key_settings = {
    left = 'cameraLeftKey', right = 'cameraRightKey',
    up = 'cameraUpKey', down = 'cameraDownKey',
}

local function input_key(source, button)
    return source .. ':' .. tostring(button)
end

local function is_modifier_key(settings, source, button)
    if settings.zoomModifierSource ~= source_ids[source] then return false end
    if settings.zoomModifierButton == button then return true end
    -- Ashita reports XInput triggers as xinput_button IDs 16/17. Preserve
    -- compatibility with saved analog aliases 256/257 from earlier builds.
    return source == 'xinput' and (
        (settings.zoomModifierButton == 16 or settings.zoomModifierButton == 256)
            and (button == 16 or button == 256)
        or (settings.zoomModifierButton == 17 or settings.zoomModifierButton == 257)
            and (button == 17 or button == 257))
end

function input.initialize()
    axes.reset()
    held, binding = {}, false
    trigger_held.left, trigger_held.right = false, false
    mouse_edge_x, mouse_edge_y = 0, 0
    edge_panning_enabled = false
    ui_menu_open = false
    mouse_buttons.left, mouse_buttons.right = false, false
    mouse_drag_x, mouse_drag_y = 0, 0
    mouse_last_x, mouse_last_y = nil, nil
    camera_cursor_drag_x, camera_cursor_drag_y = 0, 0
    camera_cursor_was_active = false
    for key in pairs(keyboard_held) do keyboard_held[key] = false end
    camera_key_binding = nil
end
function input.shutdown() input.initialize() end
function input.update_axes(horizontal, vertical) axes.update(horizontal, vertical) end
function input.get_horizontal() return axes.horizontal() end
function input.get_vertical() return axes.vertical() end
function input.get_camera_rotation_axes(settings)
    local drag_x, drag_y = mouse_drag_x, mouse_drag_y
    mouse_drag_x, mouse_drag_y = 0, 0
    if input.zoom_modifier_held(settings) then return 0, 0 end
    local horizontal, vertical = axes.horizontal(), axes.vertical()
    local mouse_sensitivity = settings.mouseSensitivity or 1
    horizontal = horizontal + drag_x * mouse_sensitivity
    vertical = vertical + drag_y * mouse_sensitivity
    if settings.mouseKeyboardEnabled and not ui_menu_open then
        if keyboard_held.left then horizontal = horizontal - settings.keyboardSensitivity end
        if keyboard_held.right then horizontal = horizontal + settings.keyboardSensitivity end
        if keyboard_held.up then vertical = vertical + settings.keyboardSensitivity end
        if keyboard_held.down then vertical = vertical - settings.keyboardSensitivity end
        horizontal = horizontal + mouse_edge_x * settings.mouseSensitivity
        vertical = vertical + mouse_edge_y * settings.mouseSensitivity
    end
    return horizontal, vertical
end

function input.set_viewport(width, height)
    viewport_width, viewport_height = tonumber(width) or 0, tonumber(height) or 0
end

function input.clear_mouse_input()
    mouse_edge_x, mouse_edge_y = 0, 0
end

function input.set_edge_panning_enabled(value)
    edge_panning_enabled = value == true
    if not edge_panning_enabled then input.clear_mouse_input() end
end

function input.get_edge_pan_state()
    return edge_panning_enabled, mouse_edge_x, mouse_edge_y
end

function input.clear_mouse_buttons()
    mouse_buttons.left, mouse_buttons.right = false, false
    mouse_drag_x, mouse_drag_y = 0, 0
    mouse_last_x, mouse_last_y = nil, nil
    camera_cursor_drag_x, camera_cursor_drag_y = 0, 0
    camera_cursor_was_active = false
end

function input.set_menu_open(value)
    ui_menu_open = value == true
    if ui_menu_open then
        input.clear_mouse_input()
        input.clear_mouse_buttons()
        for key in pairs(keyboard_held) do keyboard_held[key] = false end
    end
end

function input.begin_camera_key_binding(direction)
    if camera_key_settings[direction] == nil then return false end
    camera_key_binding = direction
    for key in pairs(keyboard_held) do keyboard_held[key] = false end
    return true
end

function input.camera_key_binding() return camera_key_binding end

function input.camera_key_label(settings, direction)
    local setting = camera_key_settings[direction]
    local code = setting and settings[setting] or 0
    if not code or code == 0 then return 'Unbound' end
    local ok, value = pcall(function() return AshitaCore:GetInputManager():GetKeyboard():D2S(code) end)
    return tostring(ok and value or ('Key ' .. tostring(code)))
end

function input.handle_key(settings, event, menu_open, save, game_menu_open)
    local code = tonumber(event.key)
    if not code then return false end
    local direction
    for candidate, setting in pairs(camera_key_settings) do
        if settings[setting] == code then direction = candidate; break end
    end
    if event.down ~= true then
        if direction then keyboard_held[direction] = false end
        return false
    end
    if event.injected or event.blocked then return false end
    if camera_key_binding and menu_open then
        local setting = camera_key_settings[camera_key_binding]
        for other_direction, other_setting in pairs(camera_key_settings) do
            if other_direction ~= camera_key_binding and settings[other_setting] == code then settings[other_setting] = 0 end
        end
        settings[setting] = code
        camera_key_binding = nil
        if save then save(settings) end
        event.blocked = true
        return true, true
    end
    if not direction or menu_open or game_menu_open or not settings.mouseKeyboardEnabled then return false end
    keyboard_held[direction] = true
    event.blocked = true
    return true
end

function input.handle_mouse(settings, event, menu_open, edge_panning_enabled, camera_cursor_active)
    local message = tonumber(event.message)
    if not message then return false end
    if message == 0x0201 or message == 0x0204 then
        if not menu_open and settings.mouseKeyboardEnabled then
            local x, y = tonumber(event.x), tonumber(event.y)
            if message == 0x0201 then mouse_buttons.left = true else mouse_buttons.right = true end
            mouse_last_x, mouse_last_y = x, y
            camera_cursor_drag_x, camera_cursor_drag_y = 0, 0
            camera_cursor_was_active = false
        end
        return false
    elseif message == 0x0202 or message == 0x0205 then
        if message == 0x0202 then mouse_buttons.left = false else mouse_buttons.right = false end
        if not mouse_buttons.left and not mouse_buttons.right then
            mouse_last_x, mouse_last_y = nil, nil
            camera_cursor_drag_x, camera_cursor_drag_y = 0, 0
            camera_cursor_was_active = false
        end
        return false
    end
    if message ~= 0x0200 then return false end
    local x, y = tonumber(event.x), tonumber(event.y)
    if not x or not y then return false end
    if not settings.mouseKeyboardEnabled or menu_open then
        input.clear_mouse_input()
        input.clear_mouse_buttons()
        return false
    end
    input.set_edge_panning_enabled(edge_panning_enabled)

    -- The blue camera cursor is the game's authoritative indication that a
    -- mouse gesture is rotating the camera. Do not require that ModernCam
    -- also observed the button-down event; another callback may have consumed
    -- it before this addon saw it.
    if camera_cursor_active then
        if not camera_cursor_was_active then
            camera_cursor_drag_x, camera_cursor_drag_y = 0, 0
        end
        camera_cursor_was_active = true
        local delta_x, delta_y = 0, 0
        if mouse_last_x ~= nil and mouse_last_y ~= nil then
            delta_x, delta_y = x - mouse_last_x, y - mouse_last_y
            mouse_drag_x = mouse_drag_x + math.max(-10, math.min(10, delta_x * 0.1))
            mouse_drag_y = mouse_drag_y - math.max(-10, math.min(10, delta_y * 0.1))
            -- Favor recent motion so a long drag in one direction does not
            -- make the cursor sluggish when the user changes direction.
            camera_cursor_drag_x = camera_cursor_drag_x * 0.65 + delta_x
            camera_cursor_drag_y = camera_cursor_drag_y * 0.65 + delta_y
        end
        mouse_last_x, mouse_last_y = x, y
        event.blocked = true
        return true, camera_cursor_drag_x, camera_cursor_drag_y
    end
    camera_cursor_was_active = false
    if mouse_buttons.left or mouse_buttons.right then
        -- A held button without the camera cursor belongs to normal mouse/UI
        -- interaction. Keep the origin current so it cannot create a jump if
        -- the game later switches the cursor into camera mode.
        mouse_last_x, mouse_last_y = x, y
        mouse_drag_x, mouse_drag_y = 0, 0
        camera_cursor_drag_x, camera_cursor_drag_y = 0, 0
        return false
    end

    if viewport_width <= 0 or viewport_height <= 0 then
        input.clear_mouse_input()
        return false
    end
    local horizontal, vertical = 0, 0
    local edge = 18
    if x >= 0 and x < edge then horizontal = -(edge - x) / edge
    elseif x <= viewport_width and x > viewport_width - edge then horizontal = (x - (viewport_width - edge)) / edge end
    if y >= 0 and y < edge then vertical = (edge - y) / edge
    elseif y <= viewport_height and y > viewport_height - edge then vertical = -(y - (viewport_height - edge)) / edge end
    if edge_panning_enabled then
        mouse_edge_x = math.max(-1, math.min(1, horizontal))
        mouse_edge_y = math.max(-1, math.min(1, vertical))
    else
        input.clear_mouse_input()
    end
    if horizontal ~= 0 or vertical ~= 0 then event.blocked = true; return true end
    return false
end

function input.begin_zoom_binding()
    held, binding = {}, true
    -- Match BetterTarget: starting a bind does not synthesize a fresh trigger
    -- edge. Release and press the trigger after opening the bind prompt.
end

function input.zoom_binding() return binding end

function input.clear_zoom_binding(settings)
    settings.zoomModifierSource, settings.zoomModifierButton = 0, 0
    binding = false
end

function input.handle_button(settings, source, event, save)
    local source_id = source_ids[source]
    -- Radgamepad only observes input; it must see handled or injected events
    -- too, since virtual XInput devices can mark their trigger events injected.
    if source_id == nil then return false, false, false end
    local key = input_key(source, event.button)
    -- Ashita reports XInput trigger button events with pressure as state 0..255;
    -- ordinary XInput buttons use 0/1. Treat any nonzero XInput state as down.
    local down = source == 'xinput' and (event.state == 1 or event.state == 255)
        or source == 'dinput' and event.state == 128
    local previous = held[key]
    if not down then
        if previous ~= nil then
            held[key] = nil
            return previous.consumed, false, previous.active == true
        end
        return false, false, false
    end
    if previous ~= nil then return previous.consumed, false, false end

    if binding then
        settings.zoomModifierSource, settings.zoomModifierButton = source_id, event.button
        binding = false
        held[key] = {consumed = true, captured = true, active = true}
        if save then save(settings) end
        return true, true, false
    end

    if not is_modifier_key(settings, source, event.button) then return false, false, false end
    held[key] = {consumed = true, active = true}
    return true, false, false
end

function input.handle_trigger(settings, side, value, save)
    -- Kept in sync with bettertarget/modifiers.lua: analog XInput trigger
    -- values become button 256/257 press/release edges at the same thresholds.
    if (side ~= 'left' and side ~= 'right') or type(value) ~= 'number' then
        return false, false, false
    end
    local was_down = trigger_held[side]
    local is_down = was_down and value > 15 or value >= 30
    -- Binding samples the current analog pressure as well as edges. If Ashita
    -- already considers the trigger down when the prompt opens, waiting for a
    -- second edge would leave Radgamepad stuck in bind mode indefinitely.
    if binding and is_down then
        trigger_held[side] = true
        return input.handle_button(settings, 'xinput', {
            button = side == 'left' and 256 or 257,
            state = 1,
        }, save)
    end
    if is_down == was_down then return false, false, false end
    trigger_held[side] = is_down
    return input.handle_button(settings, 'xinput', {
        button = side == 'left' and 256 or 257,
        state = is_down and 1 or 0,
    }, save)
end

function input.zoom_modifier_held(settings)
    for _, record in pairs(held) do
        if record.active == true then return true end
    end
    return false
end

function input.zoom_modifier_label(settings)
    local source, button = settings.zoomModifierSource, settings.zoomModifierButton
    if source == 1 and (button == 16 or button == 256) then return 'XInput left trigger' end
    if source == 1 and (button == 17 or button == 257) then return 'XInput right trigger' end
    if source == 2 and button == 12 then return 'DirectInput left trigger' end
    if source == 2 and button == 16 then return 'DirectInput right trigger' end
    if source == 1 and button ~= 0 then return 'XInput button ' .. tostring(button) end
    if source == 2 and button ~= 0 then return 'DirectInput button ' .. tostring(button) end
    return 'Unbound'
end

function input.adjust_distance(distance, vertical_axis, enabled, speed, minimum, maximum)
    if not enabled or math.abs(vertical_axis) < 0.15 then return distance, false end
    local adjusted = math.max(minimum, math.min(maximum, distance - vertical_axis * speed))
    return adjusted, adjusted ~= distance
end

return input
