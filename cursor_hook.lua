-- Observe the cursor handle FFXiMain asks SetCursor to use. Chain the current
-- IAT target so another addon (notably HeadsUp) keeps its cursor replacement.
local ffi = require('ffi')
local bit = require('bit')
pcall(ffi.cdef, 'typedef void* (__stdcall *moderncam_setcursor_fn_t)(void* cursor);')
pcall(ffi.cdef, 'void* __stdcall GetModuleHandleA(const char* name);')
pcall(ffi.cdef, 'void* __stdcall GetProcAddress(void* module, const char* name);')
pcall(ffi.cdef, 'void* __stdcall GetCursor(void);')
pcall(ffi.cdef, 'int32_t __stdcall VirtualProtect(void* address, uint32_t size, uint32_t protection, uint32_t* old_protection);')

local hook = {}
local user32 = ffi.load('user32')
local PAGE_READWRITE = 0x04
local running = false
local import_slot
local previous_set_cursor
local pending_handles = {}
local seen_handles = {}
local logging_enabled = false
local last_cursor_handle
local camera_cursor_override

local function set_cursor_hook(cursor)
    local handle
    if cursor == nil or cursor == ffi.NULL then
        handle = 0
    else
        handle = tonumber(ffi.cast('uint32_t', cursor))
    end
    last_cursor_handle = handle
    if logging_enabled and not seen_handles[handle] then
        seen_handles[handle] = true
        pending_handles[#pending_handles + 1] = handle
    end
    if previous_set_cursor ~= nil then
        if camera_cursor_override ~= nil then
            local current = user32.GetCursor()
            if current == camera_cursor_override then return current end
            return previous_set_cursor(camera_cursor_override)
        end
        return previous_set_cursor(cursor)
    end
    return nil
end

local callback = ffi.cast('moderncam_setcursor_fn_t', set_cursor_hook)
local callback_address = ffi.cast('void*', callback)

local function find_set_cursor_slot()
    local module = ffi.C.GetModuleHandleA('FFXiMain.dll')
    if module == nil or module == ffi.NULL then return nil, 'FFXiMain.dll is not loaded.' end
    local base = ffi.cast('uint8_t*', module)
    local nt_offset = tonumber(ffi.cast('uint32_t*', base + 0x3C)[0])
    if not nt_offset or nt_offset <= 0 then return nil, 'Could not read the FFXiMain PE header.' end

    -- IMAGE_NT_HEADERS32.OptionalHeader.DataDirectory[IMPORT], where the
    -- optional header begins after the four-byte signature and file header.
    local optional_header = base + nt_offset + 24
    local import_rva = tonumber(ffi.cast('uint32_t*', optional_header + 104)[0])
    if not import_rva or import_rva == 0 then return nil, 'FFXiMain has no import table.' end

    local descriptor = base + import_rva
    for _ = 1, 512 do
        local fields = ffi.cast('uint32_t*', descriptor)
        local original_thunk, library_name, first_thunk = tonumber(fields[0]), tonumber(fields[3]), tonumber(fields[4])
        if not library_name or library_name == 0 then break end
        if ffi.string(base + library_name):lower() == 'user32.dll' then
            if not original_thunk or original_thunk == 0 then
                return nil, 'FFXiMain has no import-name table for USER32.dll.'
            end
            for index = 0, 2047 do
                local thunk = tonumber(ffi.cast('uint32_t*', base + original_thunk + index * 4)[0])
                if not thunk or thunk == 0 then break end
                if bit.band(thunk, 0x80000000) == 0 then
                    local name = ffi.string(base + thunk + 2)
                    if name == 'SetCursor' then
                        return ffi.cast('void**', base + first_thunk + index * 4)
                    end
                end
            end
        end
        descriptor = descriptor + 20 -- sizeof(IMAGE_IMPORT_DESCRIPTOR)
    end
    return nil, 'Could not find FFXiMain.dll’s USER32 SetCursor import.'
end

local function write_slot(slot, target)
    local old_protection = ffi.new('uint32_t[1]')
    if ffi.C.VirtualProtect(slot, ffi.sizeof('void*'), PAGE_READWRITE, old_protection) == 0 then
        return false
    end
    slot[0] = target
    local ignored = ffi.new('uint32_t[1]')
    ffi.C.VirtualProtect(slot, ffi.sizeof('void*'), old_protection[0], ignored)
    return true
end

function hook.ensure()
    local slot, reason = find_set_cursor_slot()
    if slot == nil then return false, reason end
    local current = slot[0]
    if current == nil or current == ffi.NULL then return false, 'The SetCursor import is empty.' end
    local user32 = ffi.C.GetModuleHandleA('user32.dll')
    if user32 == nil or user32 == ffi.NULL then return false, 'USER32.dll is not loaded.' end
    local real_set_cursor = ffi.C.GetProcAddress(user32, 'SetCursor')
    if real_set_cursor == nil or real_set_cursor == ffi.NULL then return false, 'Could not find USER32 SetCursor.' end

    if current == callback_address then
        running, import_slot = true, slot
        return true
    end
    -- Do not take the game's import when no other hook is present. This leaves
    -- HeadsUp free to install its replacement later; attach once a plugin has
    -- put its own SetCursor hook into the slot.
    if current == real_set_cursor then
        running, import_slot, previous_set_cursor, last_cursor_handle = false, nil, nil, nil
        return false, 'No upstream SetCursor hook is active yet.'
    end

    previous_set_cursor = ffi.cast('moderncam_setcursor_fn_t', current)
    if not write_slot(slot, callback_address) then
        previous_set_cursor = nil
        return false, 'Could not write FFXiMain SetCursor import.'
    end
    import_slot = slot
    last_cursor_handle = nil
    running = true
    return true
end

-- If HeadsUp refreshes its own hook, wrap the new target on the next frame.
-- This keeps its replacement intact while letting ModernCam observe the
-- original HCURSOR argument first.
function hook.stop()
    if not running then return end
    if import_slot ~= nil and import_slot[0] == callback_address and previous_set_cursor ~= nil then
        write_slot(import_slot, ffi.cast('void*', previous_set_cursor))
    end
    running = false
    import_slot = nil
    previous_set_cursor = nil
    pending_handles = {}
    seen_handles = {}
    logging_enabled = false
    last_cursor_handle = nil
    camera_cursor_override = nil
end

function hook.is_running() return running end
function hook.is_logging() return logging_enabled end
function hook.current_handle() return running and last_cursor_handle or nil end
function hook.set_camera_cursor(cursor)
    if cursor == nil or cursor == ffi.NULL then
        camera_cursor_override = nil
    else
        camera_cursor_override = ffi.cast('void*', cursor)
    end
end

function hook.set_logging(enabled)
    logging_enabled = enabled == true
    pending_handles = {}
    seen_handles = {}
    if logging_enabled and running and last_cursor_handle ~= nil then
        seen_handles[last_cursor_handle] = true
        pending_handles[1] = last_cursor_handle
    end
end

function hook.flush()
    local pending = pending_handles
    pending_handles = {}
    return pending
end

return hook
