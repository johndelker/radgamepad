-- SDL input extracted from input_helper.lua (SlowCircuit).
-- Every owner balances its own init/quit; never reset the shared subsystem.
local ffi = require('ffi')
local directory = debug.getinfo(1, 'S').source:sub(2):match('(.*[\\/])') or './'
if not pcall(ffi.typeof, 'SDL_GameController*') then
    ffi.cdef[[typedef struct SDL_GameController SDL_GameController;]]
end
ffi.cdef[[
    int SDL_InitSubSystem(uint32_t flags);
    void SDL_QuitSubSystem(uint32_t flags);
    int SDL_NumJoysticks(void);
    int SDL_IsGameController(int joystick_index);
    SDL_GameController* SDL_GameControllerOpen(int joystick_index);
    void SDL_GameControllerClose(SDL_GameController* controller);
    int SDL_GameControllerGetAttached(SDL_GameController* controller);
    int16_t SDL_GameControllerGetAxis(SDL_GameController* controller, int axis);
    void SDL_PumpEvents(void);
]]
local sdl = ffi.load(directory .. 'SDL2.dll')
local input, controller, initialized = {}, nil, false
local subsystem = 0x00002000
function input.connect_gamepad()
    if not initialized then return end
    sdl.SDL_PumpEvents()
    if controller ~= nil and sdl.SDL_GameControllerGetAttached(controller) == 0 then
        sdl.SDL_GameControllerClose(controller)
        controller = nil
    end
    if controller == nil then
        for index = 0, sdl.SDL_NumJoysticks() - 1 do
            if sdl.SDL_IsGameController(index) ~= 0 then
                controller = sdl.SDL_GameControllerOpen(index)
                if controller ~= nil then break end
            end
        end
    end
end
function input.initialize()
    if initialized then return end
    if sdl.SDL_InitSubSystem(subsystem) ~= 0 then error('[radgamepad] Failed to initialize SDL controller input.') end
    initialized = true
    input.connect_gamepad()
end
function input.shutdown()
    if controller ~= nil then sdl.SDL_GameControllerClose(controller); controller = nil end
    if initialized then sdl.SDL_QuitSubSystem(subsystem); initialized = false end
end
local function axis(index)
    if controller == nil then return 0 end
    local value = tonumber(sdl.SDL_GameControllerGetAxis(controller, index)) / 32767
    return math.max(-1, math.min(1, value))
end
function input.get_horizontal() return axis(2) end
function input.get_vertical() return axis(3) end
return input
