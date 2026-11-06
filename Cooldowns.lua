-- Puts an action's cooldown on a Cooldown frame.
--
-- Spell cooldowns can be secret values in combat on this client, so they
-- go through duration objects, which the Cooldown frame accepts without
-- the addon reading them. Item cooldowns are plain numbers.
local _, ns = ...

local GetItemCooldown = C_Item and C_Item.GetItemCooldown or C_Container.GetItemCooldown

ns.Cooldowns = {}

local function ShowItemCooldown(cooldown, itemID)
    local start, duration, enabled = GetItemCooldown(itemID)
    CooldownFrame_Set(cooldown, start, duration, enabled)
end

local function ShowSpellCooldown(cooldown, spellID)
    if C_Spell.GetSpellCooldownDuration and cooldown.SetCooldownFromDurationObject then
        local durationObject = C_Spell.GetSpellCooldownDuration(spellID)
        if durationObject then
            cooldown:SetCooldownFromDurationObject(durationObject)
        else
            cooldown:Clear()
        end
        return
    end
    local info = C_Spell.GetSpellCooldown(spellID)
    CooldownFrame_Set(cooldown, info.startTime, info.duration, info.isEnabled)
end

local function ShowMacroCooldown(cooldown, name)
    local kind, id = ns.Context.MacroTarget(name)
    if kind == "spell" then
        ShowSpellCooldown(cooldown, id)
    elseif kind == "item" then
        ShowItemCooldown(cooldown, id)
    else
        cooldown:Clear()
    end
end

function ns.Cooldowns.Show(cooldown, action)
    if action.itemID then
        ShowItemCooldown(cooldown, action.itemID)
    elseif action.spellID then
        ShowSpellCooldown(cooldown, action.spellID)
    elseif action.type == "macro" then
        ShowMacroCooldown(cooldown, action.value)
    else
        cooldown:Clear()
    end
end
