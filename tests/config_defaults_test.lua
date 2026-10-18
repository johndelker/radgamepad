local scan_count = 0
local x_value, y_value = 1, 0

package.preload.ffi = function()
    return {
        typeof = function() return true end,
        cdef = function() end,
        cast = function(kind)
            assert(kind == 'radgamepad_get_config_t')
            return function(id)
                if id == 139 then return x_value end
                if id == 140 then return y_value end
                error('unexpected FFXI config id: ' .. tostring(id))
            end
        end,
    }
end

ashita = {memory = {find = function(_, _, pattern, _, _)
    scan_count = scan_count + 1
    assert(pattern == '8B0D????????85C974??8B44240450E8????????C383C8FFC3')
    return 123
end}}

local saved = {}
local is_loaded = false
local manager = {
    Load = function() return is_loaded end,
    GetBool = function(_, _, _, key, default)
        if saved[key] ~= nil then return saved[key] end
        return default
    end,
    GetFloat = function(_, _, _, key, default)
        if saved[key] ~= nil then return saved[key] end
        return default
    end,
}
AshitaCore = {GetConfigurationManager = function() return manager end}

local config = dofile('config.lua')
local settings = config.load()
assert(settings.invertHorizontal == true and settings.invertVertical == false,
    'first-run inversion defaults should match FFXI config IDs 139/140')
assert(scan_count == 1, 'first-run settings should read the FFXI camera config once')

-- A saved false value must remain false even when the imported game default is true.
is_loaded = true
saved = {invertHorizontal = false, invertVertical = true}
settings = config.load()
assert(settings.invertHorizontal == false and settings.invertVertical == true,
    'saved Radgamepad inversion choices must override FFXI defaults')
assert(scan_count == 1, 'existing settings must not read or replace defaults from FFXI')

-- A missing settings file falls back safely when the game signature cannot be found.
is_loaded = false
ashita.memory.find = function() scan_count = scan_count + 1; return 0 end
settings = config.load()
assert(settings.invertHorizontal == false and settings.invertVertical == false,
    'missing game config function should retain built-in defaults')
print('radgamepad config default tests passed')
