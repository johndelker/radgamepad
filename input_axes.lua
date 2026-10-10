local axes = {}
local horizontal, vertical = 0, 0

local function normalize(value)
    if type(value) ~= 'number' then return 0 end
    return math.max(-1, math.min(1, value / 32767))
end

function axes.update(horizontal_axis, vertical_axis)
    horizontal, vertical = normalize(horizontal_axis), normalize(vertical_axis)
end

function axes.horizontal() return horizontal end
function axes.vertical() return vertical end
function axes.reset() horizontal, vertical = 0, 0 end

return axes
