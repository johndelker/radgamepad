local panel = {}
local module_directory = debug.getinfo(1, 'S').source:sub(2):match('(.*[\\/])' ) or './'
local header_drag = nil
local pending_window_pos = nil
local ui_text = {}
local shared_font_cache = rawget(_G, '__radgamepad_bettertarget_panel_fonts')
if not shared_font_cache then shared_font_cache = {}; rawset(_G, '__radgamepad_bettertarget_panel_fonts', shared_font_cache) end
local cached_fonts = {}
local font_choices = {'Default'}
local font_files = {
    {'Arial', 'arial.ttf'},
    {'Calibri', 'calibri.ttf'},
    {'Consolas', 'consola.ttf'},
    {'Segoe UI', 'segoeui.ttf'},
    {'Tahoma', 'tahoma.ttf'},
    {'Times New Roman', 'times.ttf'},
    {'Verdana', 'verdana.ttf'},
}
local font_sizes = {10, 12, 14, 16, 18, 20, 22, 24}
local dynamic_font_size = false

local function font_directory()
    local root = os.getenv('WINDIR') or os.getenv('SYSTEMROOT') or 'C:\\Windows'
    return root:gsub('[\\/]$', '') .. '\\Fonts\\'
end

local function has_file(path)
    local file = io.open(path, 'rb')
    if not file then return false end
    file:close()
    return true
end

function panel.initialize(imgui)
    local file = io.open(module_directory .. 'ui_text.json', 'rb')
    if file then
        local contents = file:read('*a')
        file:close()
        local ok, decoded = pcall(function() return require('json').decode(contents) end)
        if ok and type(decoded) == 'table' then ui_text = decoded else ui_text = {} end
    end
    cached_fonts = {}
    font_choices = {'Default'}
    local ok, style = pcall(imgui.GetStyle)
    dynamic_font_size = ok and style ~= nil and type(style.FontSizeBase) == 'number'
    local directory = font_directory()
    for _, item in ipairs(font_files) do
        local family, filename = item[1], item[2]
        local path = directory .. filename
        if has_file(path) then
            local family_fonts = {}
            for _, size in ipairs(font_sizes) do
                local cache_key = filename:lower() .. ':' .. tostring(size)
                local font = shared_font_cache[cache_key]
                if font == nil then
                    local loaded, result = pcall(imgui.AddFontFromFileTTF, path, size)
                    font = loaded and result or false
                    shared_font_cache[cache_key] = font
                end
                if font then family_fonts[size] = font end
            end
            if next(family_fonts) then
                cached_fonts[family] = family_fonts
                font_choices[#font_choices + 1] = family
            end
        end
    end
end

function panel.setting_label(key, fallback)
    local item = ui_text.settings and (ui_text.settings[key] or ui_text.settings[fallback])
    return type(item) == 'table' and item.label or fallback
end

function panel.setting_description(key)
    local item = ui_text.settings and ui_text.settings[key]
    if type(item) == 'table' and type(item.description) == 'string' and item.description ~= '' then
        return item.description
    end
    return 'Configure ' .. tostring(key) .. '.'
end

function panel.option_description(dropdown, option)
    local options = ui_text.options and ui_text.options[dropdown]
    local description = type(options) == 'table' and options[tostring(option)] or nil
    if type(description) == 'string' and description ~= '' then return description end
    return 'Select ' .. tostring(option) .. '.'
end

function panel.show_tooltip(imgui, description)
    if description and imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.PushTextWrapPos(imgui.GetFontSize() * 22)
        imgui.TextWrapped(description)
        imgui.PopTextWrapPos()
        imgui.EndTooltip()
    end
end

function panel.section_text(title, fallback)
    local item = ui_text.sections and ui_text.sections[title]
    if type(item) ~= 'table' then return title, fallback end
    return item.title or title, item.description or fallback
end

function panel.tab_label(label)
    return (ui_text.tabs and ui_text.tabs[label]) or label
end

function panel.centered_selectable(imgui, label, selected, settings, dropdown_key)
    local x, y = imgui.GetCursorScreenPos()
    local width = imgui.GetContentRegionAvail()
    local height = imgui.GetTextLineHeightWithSpacing()
    imgui.PushID(label)
    local clicked = imgui.Selectable('##CenteredChoice', selected, ImGuiSelectableFlags_None, {width, height})
    panel.show_tooltip(imgui, panel.option_description(dropdown_key, label))
    imgui.PopID()
    local text_width, text_height = imgui.CalcTextSize(label)
    local draw = imgui.GetWindowDrawList()
    draw:AddText({x + (width - text_width) * 0.5, y + (height - text_height) * 0.5},
        panel.color_u32(imgui, settings, 'Text'), label)
    return clicked
end

function panel.draw_combo_preview(imgui, key, preview, settings, width)
    local x, y = imgui.GetCursorScreenPos()
    imgui.SetNextItemWidth(width)
    local open = imgui.BeginCombo('##combo_' .. key, '')
    local frame_height = imgui.GetFrameHeight()
    local text_width, text_height = imgui.CalcTextSize(preview)
    local preview_width = math.max(0, width - frame_height)
    imgui.GetWindowDrawList():AddText({x + (preview_width - text_width) * 0.5,
        y + (frame_height - text_height) * 0.5}, panel.color_u32(imgui, settings, 'Text'), preview)
    return open
end

function panel.font_choices()
    return font_choices
end

function panel.push_font(imgui, settings)
    local family = settings.panelFont or 'Default'
    local size = tonumber(settings.panelFontSize) or 16
    local font
    if family == 'Default' then
        font = imgui.GetFont()
    else
        local sizes = cached_fonts[family]
        font = sizes and sizes[size]
        if not font and sizes then
            local nearest, distance
            for candidate_size, candidate_font in pairs(sizes) do
                local delta = math.abs(candidate_size - size)
                if not distance or delta < distance then nearest, distance = candidate_font, delta end
            end
            font = nearest
        end
        if not font then font = imgui.GetFont() end
    end
    local ok
    if dynamic_font_size then
        ok = pcall(imgui.PushFont, font, size)
    else
        ok = pcall(imgui.PushFont, font)
    end
    return ok
end

function panel.pop_font(imgui, pushed)
    if pushed then imgui.PopFont() end
end

function panel.color(settings, name)
    return {settings['panel' .. name .. 'R'], settings['panel' .. name .. 'G'],
        settings['panel' .. name .. 'B'], settings['panel' .. name .. 'A']}
end

function panel.color_u32(imgui, settings, name, alpha)
    local value = panel.color(settings, name)
    if alpha then value[4] = value[4] * alpha end
    return imgui.GetColorU32(value)
end

function panel.slider_width(settings, available)
    return math.max(80, math.min(available, tonumber(settings.panelControlWidth) or 220))
end
function panel.dropdown_width(settings, available)
    return math.max(80, math.min(available, tonumber(settings.panelControlWidth) or 220))
end
function panel.toggle_width(settings, available)
    local width = math.max(72, tonumber(settings.panelControlWidth) or 220)
    if available then width = math.min(width, available) end
    return width
end

function panel.push_theme(imgui, settings)
    local bg = panel.color(settings, 'Background')
    local text = panel.color(settings, 'Text')
    local dim = panel.color(settings, 'SecondaryText')
    local highlight = panel.color(settings, 'Highlight')
    local hover = panel.color(settings, 'HighlightHover')
    for _, item in ipairs({
        {ImGuiCol_WindowBg, bg}, {ImGuiCol_ChildBg, {0, 0, 0, 0}}, {ImGuiCol_Border, highlight},
        {ImGuiCol_Text, text}, {ImGuiCol_TextDisabled, dim},
        {ImGuiCol_FrameBg, bg}, {ImGuiCol_FrameBgHovered, hover}, {ImGuiCol_FrameBgActive, highlight},
        {ImGuiCol_Header, highlight}, {ImGuiCol_HeaderHovered, hover}, {ImGuiCol_HeaderActive, highlight},
        {ImGuiCol_Button, highlight}, {ImGuiCol_ButtonHovered, hover}, {ImGuiCol_ButtonActive, highlight},
        {ImGuiCol_CheckMark, hover}, {ImGuiCol_SliderGrab, text}, {ImGuiCol_SliderGrabActive, hover},
    }) do imgui.PushStyleColor(item[1], item[2]) end
end
function panel.pop_theme(imgui)
    imgui.PopStyleColor(17)
end


function panel.has_font(family)
    if family == 'Default' then return true end
    return cached_fonts[family] ~= nil
end

function panel.draw_navigation_item(imgui, label, index, selected, settings)
    local x, y = imgui.GetCursorScreenPos()
    local width = imgui.GetContentRegionAvail()
    local height = 38
    label = panel.tab_label(label)
    local text_width, text_height = imgui.CalcTextSize(label)
    imgui.PushStyleColor(ImGuiCol_Header, {0, 0, 0, 0})
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, {0, 0, 0, 0})
    imgui.PushStyleColor(ImGuiCol_HeaderActive, {0, 0, 0, 0})
    local clicked = imgui.Selectable('##PanelPage' .. tostring(index), selected, ImGuiSelectableFlags_None, {width, height})
    local hovered = imgui.IsItemHovered()
    imgui.PopStyleColor(3)
    local tx = x + (width - text_width) * 0.5
    local ty = y + (height - text_height) * 0.5
    local draw = imgui.GetWindowDrawList()
    if hovered or selected then
        local color_name = hovered and 'HighlightHover' or 'Highlight'
        draw:AddRectFilled({x, y}, {x + width, y + height}, panel.color_u32(imgui, settings, color_name), height * 0.28)
    end
    local color = panel.color_u32(imgui, settings, 'Text')
    -- A second half-pixel pass gives the label a heavier weight without loading a separate font.
    draw:AddText({tx, ty}, color, label)
    draw:AddText({tx + 0.5, ty}, color, label)
    return clicked
end

function panel.draw_header(imgui, title, menu_open, settings)
    local x, y = imgui.GetCursorScreenPos()
    local width = imgui.GetContentRegionAvail()
    local height, close_width = 34, 38
    local drag_width = math.max(80, width - close_width - 6)
    local draw = imgui.GetWindowDrawList()
    imgui.InvisibleButton('##PanelHeaderDrag', {drag_width, height})
    if imgui.IsItemActive() then
        if imgui.IsItemActivated() then
            local mouse_x, mouse_y = imgui.GetMousePos()
            local window_x, window_y = imgui.GetWindowPos()
            header_drag = {mouse_x = mouse_x, mouse_y = mouse_y,
                window_x = window_x, window_y = window_y}
        end
        if header_drag then
            local mouse_x, mouse_y = imgui.GetMousePos()
            pending_window_pos = {
                header_drag.window_x + mouse_x - header_drag.mouse_x,
                header_drag.window_y + mouse_y - header_drag.mouse_y,
            }
        end
    else
        header_drag = nil
    end
    local font, font_size = imgui.GetFont(), imgui.GetFontSize() * 1.5
    local title_text = (ui_text.window and ui_text.window.title) or title
    imgui.PushFont(font, font_size)
    local _, text_height = imgui.CalcTextSize(title_text)
    imgui.PopFont()
    local text_x, text_y = x + 10, y + (height - text_height) * 0.5
    local text_color = panel.color_u32(imgui, settings, 'Text')
    draw:AddText(font, font_size, {text_x, text_y}, text_color, title_text)
    draw:AddText(font, font_size, {text_x + 0.5, text_y}, text_color, title_text)
    imgui.SameLine(0, 6)
    if imgui.Button('X##PanelClose', {close_width, height}) then menu_open[1] = false end
    imgui.Spacing()
end

function panel.apply_pending_window_pos(imgui)
    if pending_window_pos then
        imgui.SetNextWindowPos(pending_window_pos, ImGuiCond_Always)
        pending_window_pos = nil
    end
end

function panel.draw_config(imgui, settings, draft, config, slider, combo, card, end_card, begin_row)
    local appearance_title, appearance_description = panel.section_text('Appearance', 'Click Apply to save typeface, size, shared control width, and border width.')
    if card(appearance_title, appearance_description) then
        combo(panel.setting_label('panelFont', 'Font Family'), 'panelFont', panel.font_choices(), draft, false)
        slider(panel.setting_label('panelFontSize', 'Font Size'), 'panelFontSize', draft, false)
        slider(panel.setting_label('panelControlWidth', 'Control Width'), 'panelControlWidth', draft, false)
        slider(panel.setting_label('panelBorderWidth', 'Border Width'), 'panelBorderWidth', draft, false)
        local cursor_x = imgui.GetCursorPosX()
        local available = imgui.GetContentRegionAvail()
        local button_width = 90
        imgui.SetCursorPosX(cursor_x + available - button_width)
        if imgui.Button('Apply##PanelAppearance', {button_width, 0}) then
            for _, key in ipairs({'panelFont', 'panelFontSize', 'panelControlWidth', 'panelBorderWidth'}) do
                settings[key] = draft[key]
            end
            config.save(settings)
        end
    end
    end_card()
    local colors_title, colors_description = panel.section_text('Colors', 'Customize the panel background, text, and interaction colors.')
    if card(colors_title, colors_description) then
        for _, item in ipairs({
            {'Background Color', 'Background'}, {'Secondary Color', 'Secondary'},
            {'Secondary Text Color', 'SecondaryText'}, {'Text Color', 'Text'},
            {'Highlight Color', 'Highlight'}, {'Highlight Hover Color', 'HighlightHover'},
        }) do
            local label, name = item[1], item[2]
            local width = begin_row(label)
            local value = panel.color(settings, name)
            imgui.SetNextItemWidth(width)
            if imgui.ColorEdit4('##PanelColor' .. name, value, ImGuiColorEditFlags_AlphaBar) then
                settings['panel' .. name .. 'R'] = value[1]
                settings['panel' .. name .. 'G'] = value[2]
                settings['panel' .. name .. 'B'] = value[3]
                settings['panel' .. name .. 'A'] = value[4]
                config.save(settings)
            end
        end
    end
    end_card()
end

return panel
