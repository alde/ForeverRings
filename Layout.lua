-- Ring geometry. Pure functions, unit tested.
--
-- The secure release snippet in Ring.lua repeats NearestSlice because
-- restricted code cannot call insecure functions. Keep the two in step.
local _, ns = ...

ns.Layout = {}

-- Unit vectors for each slice: the first points straight up, the rest
-- follow clockwise at equal angles.
function ns.Layout.SliceDirections(count)
    local directions = {}
    for index = 1, count do
        local angle = (index - 1) * 2 * math.pi / count
        directions[index] = { x = math.sin(angle), y = math.cos(angle) }
    end
    return directions
end

-- A direction turned clockwise by angle radians, as x, y.
function ns.Layout.Rotate(direction, angle)
    local cos, sin = math.cos(angle), math.sin(angle)
    return direction.x * cos + direction.y * sin, direction.y * cos - direction.x * sin
end

-- The slice whose direction is closest to the cursor offset (dx, dy),
-- or nil when the cursor sits inside the dead zone.
function ns.Layout.NearestSlice(dx, dy, directions, deadzone)
    if dx * dx + dy * dy < deadzone * deadzone then
        return nil
    end
    local best, bestDot
    for index, direction in ipairs(directions) do
        local dot = dx * direction.x + dy * direction.y
        if not bestDot or dot > bestDot then
            best, bestDot = index, dot
        end
    end
    return best
end
