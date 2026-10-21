local scan_count = 0
local x_value, y_value = 1, 0
local edge_panning_value = 0

package.preload.ffi = function()
    return {
        typeof = function() return true end,
        cdef = function() end,
        cast = function(kind)
            assert(kind == 'moderncam_get_config_t')
            return function(id)
                if id == 139 then return x_value end
                if id == 140 then return y_value end
                if id == 143 then return edge_panning_value end
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
local modern_loaded, legacy_loaded = false, false
local written = {}
local manager = {
    Load = function(_, name, file)
        if name == 'moderncam' then assert(file == 'moderncam.ini'); return modern_loaded end
        if name == 'radgamepad' then assert(file == 'radgamepad.ini'); return legacy_loaded end
        error('unexpected config name: ' .. tostring(name))
    end,
    GetBool = function(_, _, _, key, default)
        if saved[key] ~= nil then return saved[key] end
        return default
    end,
    GetFloat = function(_, _, _, key, default)
        if saved[key] ~= nil then return saved[key] end
        return default
    end,
    GetString = function(_, _, _, key)
        if saved[key] ~= nil then return tostring(saved[key]) end
        return nil
    end,
    Delete = function(_, name, file)
        assert(name == 'moderncam' and file == 'moderncam.ini')
    end,
    SetValue = function(_, name, section, key, value)
        assert(name == 'moderncam' and section == 'default')
        written[key] = value
    end,
    Save = function(_, name, file)
        assert(name == 'moderncam' and file == 'moderncam.ini')
    end,
}
AshitaCore = {GetConfigurationManager = function() return manager end}

local config = dofile('config.lua')
local settings = config.load()
assert(settings.invertHorizontal == true and settings.invertVertical == false,
    'first-run inversion defaults should match FFXI config IDs 139/140')
assert(scan_count == 1, 'first-run settings should read the FFXI camera config once')

-- A saved false value must remain false even when the imported game default is true.
modern_loaded = true
saved = {invertHorizontal = false, invertVertical = true}
settings = config.load()
assert(settings.invertHorizontal == false and settings.invertVertical == true,
    'saved Radgamepad inversion choices must override FFXI defaults')
assert(scan_count == 1, 'existing settings must not read or replace defaults from FFXI')

assert(config.is_edge_panning_enabled(), 'edge panning should follow FFXI config ID 143')
edge_panning_value = 1
assert(not config.is_edge_panning_enabled(), 'config ID 143 value 1 should disable edge panning')

-- Existing Radgamepad settings should load once and be written using the new identity.
modern_loaded = false
legacy_loaded = false
ashita.memory.find = function() error('legacy migration should not re-read defaults') end
legacy_loaded = true
saved = {distance = 8.5, invertHorizontal = true}
settings = config.load()
assert(settings.distance == 8.5 and settings.invertHorizontal == true,
    'legacy Radgamepad values should be preserved during migration')
assert(written.distance == '8.5' and written.invertHorizontal == 'true',
    'legacy values should be saved to ModernCam settings')
print('moderncam config default tests passed')
