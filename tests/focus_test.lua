local focus = dofile('focus.lua')
assert(focus.is_game_process_foreground(10, function() return 20 end,
    function(hwnd) return hwnd == 20 and 7 or 3 end) == false)
assert(focus.is_game_process_foreground(10, function() return 20 end,
    function() return 3 end) == true)
assert(focus.is_game_process_foreground(nil, function() return 20 end,
    function() return 3 end) == false)
assert(focus.is_game_process_foreground(10, function() return nil end,
    function() return 3 end) == false)
print('radgamepad focus tests passed')
