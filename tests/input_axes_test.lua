local axes = dofile('input_axes.lua')
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.0001, string.format('expected %.4f, got %.4f', expected, actual))
end

axes.update(32767, -32768)
near(axes.horizontal(), 1)
near(axes.vertical(), -1)

axes.update(16384, -8192)
near(axes.horizontal(), 16384 / 32767)
near(axes.vertical(), -8192 / 32767)

axes.update(nil, 32767)
near(axes.horizontal(), 0)
near(axes.vertical(), 1)

axes.reset()
near(axes.horizontal(), 0)
near(axes.vertical(), 0)

print('radgamepad input axis tests passed')
