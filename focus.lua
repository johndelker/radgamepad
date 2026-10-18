local focus = {}

function focus.is_game_process_foreground(game_window, get_foreground_window, get_process_id)
    if game_window == nil or type(get_foreground_window) ~= 'function'
        or type(get_process_id) ~= 'function' then return false end
    local ok, foreground = pcall(get_foreground_window)
    if not ok or foreground == nil then return false end
    local game_ok, game_pid = pcall(get_process_id, game_window)
    local foreground_ok, foreground_pid = pcall(get_process_id, foreground)
    return game_ok and foreground_ok and game_pid ~= nil and game_pid ~= 0
        and game_pid == foreground_pid
end

return focus
