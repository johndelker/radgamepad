local input = dofile('input.lua')
local settings = {
    mouseKeyboardEnabled = true,
    mouseSensitivity = 1,
    keyboardSensitivity = 1,
    cameraLeftKey = 203,
    cameraRightKey = 205,
    cameraUpKey = 200,
    cameraDownKey = 208,
    zoomModifierSource = 0,
    zoomModifierButton = 0,
}
input.initialize()

local left = {key = 0xCB, down = true}
assert(input.handle_key(settings, left, false) and left.blocked == true,
    'camera arrow keys should be intercepted while keyboard camera input is enabled')
local horizontal, vertical = input.get_camera_rotation_axes(settings)
assert(horizontal == -1 and vertical == 0, 'left arrow should rotate left')

local release = {key = 0xCB, down = false}
input.handle_key(settings, release, false)
horizontal, vertical = input.get_camera_rotation_axes(settings)
assert(horizontal == 0 and vertical == 0, 'released arrow keys should stop camera rotation')

input.set_viewport(1920, 1080)
local move = {message = 0x0200, x = 0, y = 540}
assert(input.handle_mouse(settings, move, false, false) and move.blocked == true,
    'edge events should be intercepted when disabled to stop native camera panning')
horizontal, vertical = input.get_camera_rotation_axes(settings)
assert(horizontal == 0 and vertical == 0,
    'screen edge panning should not move the custom camera when the base-game setting is disabled')
move = {message = 0x0200, x = 0, y = 540}
assert(input.handle_mouse(settings, move, false, true) and move.blocked == true,
    'mouse movement at the window edge should be intercepted when base-game edge panning is enabled')
horizontal, vertical = input.get_camera_rotation_axes(settings)
assert(horizontal == -1 and vertical == 0, 'left window edge should pan camera left')
local center = {message = 0x0200, x = 960, y = 540}
assert(not input.handle_mouse(settings, center, false, true), 'ordinary mouse movement should pass through')
horizontal, vertical = input.get_camera_rotation_axes(settings)
assert(horizontal == 0 and vertical == 0, 'moving away from the edge should stop mouse camera movement')

local click = {message = 0x0201, x = 800, y = 500}
assert(not input.handle_mouse(settings, click, false, true), 'mouse click should pass through to the game')
local drag = {message = 0x0200, x = 810, y = 500}
assert(input.handle_mouse(settings, drag, false, true) and drag.blocked == true,
    'mouse movement during a left-button camera drag should be intercepted')
horizontal, vertical = input.get_camera_rotation_axes(settings)
assert(horizontal == 1 and vertical == 0, 'mouse drag should rotate the custom camera')
input.handle_mouse(settings, {message = 0x0202, x = 810, y = 500}, false, true)

local menu_move = {message = 0x0200, x = 0, y = 540}
assert(not input.handle_mouse(settings, menu_move, true, true) and menu_move.blocked ~= true,
    'mouse movement should pass through and not pan while a menu is open')
input.set_menu_open(true)
local menu_key = {key = 0xCD, down = true}
assert(not input.handle_key(settings, menu_key, false, nil, true) and menu_key.blocked ~= true,
    'camera arrow keys should pass through while a game menu is open')
horizontal, vertical = input.get_camera_rotation_axes(settings)
assert(horizontal == 0 and vertical == 0, 'menu-open state should suppress held camera keys')
input.set_menu_open(false)

settings.mouseKeyboardEnabled = false
local ignored = {key = 0xCD, down = true}
assert(not input.handle_key(settings, ignored, false) and ignored.blocked ~= true,
    'disabled keyboard camera input should pass through')

input.begin_camera_key_binding('left')
local custom_key = {key = 0x1E, down = true}
local _, changed = input.handle_key(settings, custom_key, true, function() end)
assert(changed and custom_key.blocked == true and settings.cameraLeftKey == 0x1E,
    'camera direction should accept a new DirectInput key binding from the config menu')
settings.mouseKeyboardEnabled = true
local custom_release = {key = 0x1E, down = false}
input.handle_key(settings, custom_release, false)
local custom_press = {key = 0x1E, down = true}
assert(input.handle_key(settings, custom_press, false) and custom_press.blocked == true,
    'rebound camera key should be captured during play')
horizontal, vertical = input.get_camera_rotation_axes(settings)
assert(horizontal == -1 and vertical == 0, 'rebound left key should rotate left')
print('moderncam keyboard and mouse input tests passed')
