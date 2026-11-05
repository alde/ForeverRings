-- Spawn animations. Pure, unit tested. A pose is four numbers applied to
-- every slice: radius factor, alpha, scale and turn (radians, clockwise).
local _, ns = ...

-- SetScale rejects zero.
local MIN_SCALE = 0.01
-- Spiral slices start a quarter turn back and sweep clockwise into place.
local SPIRAL_TURN = -math.pi / 2

ns.Animation = {
    DEFAULT_STYLE = "grow",
    DEFAULT_DURATION = 0.15, -- seconds; long enough to read, short enough not to slow aiming
    MIN_DURATION = 0.05,
    MAX_DURATION = 0.5,
    DURATION_STEP = 0.05,
    STYLES = {
        { key = "none", label = "None" },
        { key = "fade", label = "Fade in" },
        { key = "grow", label = "Grow" },
        { key = "unfold", label = "Unfold from centre" },
        { key = "spiral", label = "Spiral out" },
    },
}

local POSES = {
    none = function() return 1, 1, 1, 0 end,
    fade = function(progress) return 1, progress, 1, 0 end,
    grow = function(progress) return 1, progress, math.max(progress, MIN_SCALE), 0 end,
    unfold = function(progress) return progress, progress, 1, 0 end,
    spiral = function(progress) return progress, progress, 1, (1 - progress) * SPIRAL_TURN end,
}

local function EaseOutCubic(t)
    return 1 - (1 - t) ^ 3
end

-- Returns radius factor, alpha, scale, turn and whether the animation
-- has finished. Unknown styles behave as "none".
function ns.Animation.Pose(style, elapsed, duration)
    local t = duration > 0 and math.min(elapsed / duration, 1) or 1
    local radius, alpha, scale, turn = (POSES[style] or POSES.none)(EaseOutCubic(t))
    return radius, alpha, scale, turn, t >= 1
end

function ns.Animation.RestPose()
    return POSES.none()
end
