-- Detect FFXI's blue camera cursor from the active Windows cursor image.
-- HeadsUp replaces mousenor.ani and mousehit.ani, but passes the camera arrows
-- through unchanged, so inspecting GetCursor() still sees the blue arw_*.ani.
local ffi = require('ffi')
pcall(ffi.cdef, [[
    typedef struct moderncam_bitmap_t {
        int32_t type, width, height, width_bytes;
        uint16_t planes, bits_pixel;
        void* bits;
    } moderncam_bitmap_t;
    typedef struct moderncam_iconinfo_t {
        int32_t is_icon;
        uint32_t hot_x, hot_y;
        void* mask_bitmap;
        void* color_bitmap;
    } moderncam_iconinfo_t;
    typedef struct moderncam_bitmapinfoheader_t {
        uint32_t size;
        int32_t width, height;
        uint16_t planes, bit_count;
        uint32_t compression, image_size;
        int32_t x_pixels_per_meter, y_pixels_per_meter;
        uint32_t colors_used, colors_important;
    } moderncam_bitmapinfoheader_t;
    typedef struct moderncam_bitmapinfo_t {
        moderncam_bitmapinfoheader_t header;
        uint32_t colors[1];
    } moderncam_bitmapinfo_t;
    void* __stdcall GetModuleHandleA(const char* name);
    uint32_t __stdcall GetModuleFileNameA(void* module, char* path, uint32_t size);
    void* __stdcall LoadCursorFromFileA(const char* path);
    void* __stdcall SetCursor(void* cursor);
    int32_t __stdcall DestroyCursor(void* cursor);
    void* __stdcall GetCursor(void);
    int32_t __stdcall GetIconInfo(void* cursor, moderncam_iconinfo_t* info);
    int32_t __stdcall GetObjectA(void* object, int32_t size, void* buffer);
    void* __stdcall GetDC(void* window);
    int32_t __stdcall ReleaseDC(void* window, void* dc);
    int32_t __stdcall GetDIBits(void* dc, void* bitmap, uint32_t start, uint32_t lines,
        void* bits, moderncam_bitmapinfo_t* info, uint32_t usage);
    int32_t __stdcall DeleteObject(void* object);
]])
local user32 = ffi.load('user32')
local gdi32 = ffi.load('gdi32')

local cursor_state = {}
local cursor_cache = {}
local last_active = false
local camera_cursors = {}
local cursor_direction = nil
local last_requested_cursor

local function cursor_pixels(dc, bitmap, width, height)
    local info = ffi.new('moderncam_bitmapinfo_t[1]')
    info[0].header.size = ffi.sizeof('moderncam_bitmapinfoheader_t')
    info[0].header.width = width
    info[0].header.height = -height
    info[0].header.planes = 1
    info[0].header.bit_count = 32
    info[0].header.compression = 0
    local pixels = ffi.new('uint8_t[?]', width * height * 4)
    if gdi32.GetDIBits(dc, bitmap, 0, height, pixels, info, 0) ~= height then return nil end
    return pixels
end

local function is_blue_camera_arrow(cursor)
    if cursor == nil then cursor = user32.GetCursor() end
    if cursor == nil or cursor == ffi.NULL then return false end
    local handle = tonumber(ffi.cast('uint32_t', cursor))
    if cursor_cache[handle] ~= nil then return cursor_cache[handle] end

    local icon = ffi.new('moderncam_iconinfo_t[1]')
    if user32.GetIconInfo(cursor, icon) == 0 then
        cursor_cache[handle] = false
        return false
    end

    local result = false
    local ok = pcall(function()
        if icon[0].color_bitmap == nil or icon[0].color_bitmap == ffi.NULL then return end
        local bitmap = ffi.new('moderncam_bitmap_t[1]')
        if gdi32.GetObjectA(icon[0].color_bitmap, ffi.sizeof('moderncam_bitmap_t'), bitmap) == 0 then return end
        local width, height = tonumber(bitmap[0].width), tonumber(bitmap[0].height)
        -- FFXI's directional cursor files are 32 by 32. This also keeps the
        -- pixel scan bounded if Windows returns another kind of cursor.
        if width ~= 32 or height ~= 32 then return end

        local dc = user32.GetDC(nil)
        if dc == nil or dc == ffi.NULL then return end
        local color = cursor_pixels(dc, icon[0].color_bitmap, width, height)
        local mask
        if icon[0].mask_bitmap ~= nil and icon[0].mask_bitmap ~= ffi.NULL then
            mask = cursor_pixels(dc, icon[0].mask_bitmap, width, height)
        end
        user32.ReleaseDC(nil, dc)
        if color == nil then return end

        local visible, blue = 0, 0
        for pixel = 0, width * height - 1 do
            local at = pixel * 4
            local transparent = false
            if mask ~= nil then
                transparent = (mask[at] + mask[at + 1] + mask[at + 2]) ~= 0
            end
            if not transparent then
                local b, g, r = tonumber(color[at]), tonumber(color[at + 1]), tonumber(color[at + 2])
                visible = visible + 1
                if b > 40 and b > r * 1.25 and b > g * 1.05 then blue = blue + 1 end
            end
        end
        -- The installed arw_*.ani cursors have 83 blue pixels out of 86-87
        -- visible pixels. The normal, hover, and orange oarw_* cursors have
        -- none, so this leaves a little room for Windows' bitmap conversion.
        if mask ~= nil then
            result = visible >= 60 and blue / visible >= 0.80
        else
            result = blue >= 70
        end
    end)

    if icon[0].color_bitmap ~= nil and icon[0].color_bitmap ~= ffi.NULL then
        pcall(gdi32.DeleteObject, icon[0].color_bitmap)
    end
    if icon[0].mask_bitmap ~= nil and icon[0].mask_bitmap ~= ffi.NULL then
        pcall(gdi32.DeleteObject, icon[0].mask_bitmap)
    end
    cursor_cache[handle] = ok and result or false
    return cursor_cache[handle]
end

function cursor_state.update(cursor)
	-- When supplied, inspect the cursor handle requested by FFXiMain instead
	-- of GetCursor(). Another addon may replace the displayed image afterward.
	if cursor ~= nil and cursor ~= ffi.NULL then last_requested_cursor = cursor end
	local active = is_blue_camera_arrow(cursor)
    local changed = active ~= last_active
    last_active = active
    return active, changed
end

function cursor_state.is_camera_cursor() return is_blue_camera_arrow(nil) end
function cursor_state.is_camera_handle(cursor) return is_blue_camera_arrow(cursor) end

local function load_camera_cursors()
    if next(camera_cursors) ~= nil then return true end
    local module = ffi.C.GetModuleHandleA('FFXiMain.dll')
    if module == nil or module == ffi.NULL then return false end
    local path_buffer = ffi.new('char[1024]')
    local length = tonumber(ffi.C.GetModuleFileNameA(module, path_buffer, 1024))
    if not length or length == 0 or length >= 1024 then return false end
    local module_path = ffi.string(path_buffer, length)
    local slash = module_path:match('^.*()[\\/]')
    if not slash then return false end
    local folder = module_path:sub(1, slash)
    for _, direction in ipairs({'n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw'}) do
        local cursor = user32.LoadCursorFromFileA(folder .. 'arw_' .. direction .. '.ani')
        if cursor ~= nil and cursor ~= ffi.NULL then camera_cursors[direction] = cursor end
    end
    return next(camera_cursors) ~= nil
end

local direction_names = {'e', 'se', 's', 'sw', 'w', 'nw', 'n', 'ne'}
local direction_indexes = {}
for index, direction in ipairs(direction_names) do direction_indexes[direction] = index end
function cursor_state.set_camera_direction(delta_x, delta_y)
    delta_x, delta_y = tonumber(delta_x) or 0, tonumber(delta_y) or 0
    if math.sqrt(delta_x * delta_x + delta_y * delta_y) < 1.5 then
        return cursor_direction and camera_cursors[cursor_direction] or nil
    end
    local angle = math.deg(math.atan2(delta_y, delta_x))
    if angle < 0 then angle = angle + 360 end
    local sector = math.floor((angle + 22.5) / 45) % 8 + 1
    if cursor_direction ~= nil then
        local previous_sector = direction_indexes[cursor_direction]
        local previous_center = (previous_sector - 1) * 45
        local offset = (angle - previous_center + 180) % 360 - 180
        -- Keep the current image until the drag direction has clearly crossed
        -- the sector boundary. This prevents tiny diagonal corrections from
        -- making the arrow flicker between neighboring directions.
        if math.abs(offset) <= 28.5 then sector = previous_sector end
    end
    local direction = direction_names[sector]
    if not load_camera_cursors() then return nil end
    local cursor = camera_cursors[direction]
    if cursor == nil then return nil end
    if cursor_direction == direction then return cursor end
    cursor_direction = direction
    user32.SetCursor(cursor)
    return cursor
end

function cursor_state.current_camera_direction() return cursor_direction end

function cursor_state.restore_requested_cursor(cursor)
    cursor = cursor or last_requested_cursor
    if cursor ~= nil and cursor ~= ffi.NULL then user32.SetCursor(cursor) end
    cursor_direction = nil
end

function cursor_state.release()
    cursor_state.restore_requested_cursor()
    for _, cursor in pairs(camera_cursors) do
        pcall(user32.DestroyCursor, cursor)
    end
    camera_cursors = {}
    cursor_direction = nil
end

return cursor_state
