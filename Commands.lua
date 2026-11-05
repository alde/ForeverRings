-- Slash commands. /frings opens the options panel; /rl reloads the UI
-- unless another addon has already claimed it.
local _, ns = ...

local RELOAD_COMMAND = "/rl"

-- True when any registered command (SLASH_<KEY>1, SLASH_<KEY>2, ...)
-- matches command, ignoring case.
function ns.SlashCommandTaken(command, slashCmdList, globals)
    for key in pairs(slashCmdList) do
        local index = 1
        local registered = globals["SLASH_" .. key .. index]
        while registered do
            if registered:lower() == command then
                return true
            end
            index = index + 1
            registered = globals["SLASH_" .. key .. index]
        end
    end
    return false
end

SLASH_FOREVERRINGS1 = "/frings"
SLASH_FOREVERRINGS2 = "/foreverrings"
SlashCmdList.FOREVERRINGS = function()
    ns.OpenOptions()
end

-- Checked at login, once every addon has had the chance to register its own.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
    if not ns.SlashCommandTaken(RELOAD_COMMAND, SlashCmdList, _G) then
        SLASH_FOREVERRINGS_RELOAD1 = RELOAD_COMMAND
        SlashCmdList.FOREVERRINGS_RELOAD = ReloadUI
    end
end)
