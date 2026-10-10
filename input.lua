-- Axes are updated from Ashita's xinput_state event in radgamepad.lua.
local directory = debug.getinfo(1, 'S').source:sub(2):match('(.*[\\/])') or './'
local axes = dofile(directory .. 'input_axes.lua')
local input = {}
local source_ids = {xinput = 1, dinput = 2}
local held, binding = {}, false
local trigger_held = {left = false, right = false}

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
end
function input.shutdown() input.initialize() end
function input.update_axes(horizontal, vertical) axes.update(horizontal, vertical) end
function input.get_horizontal() return axes.horizontal() end
function input.get_vertical() return axes.vertical() end
function input.get_camera_rotation_axes(settings)
    if input.zoom_modifier_held(settings) then return 0, 0 end
    return axes.horizontal(), axes.vertical()
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
