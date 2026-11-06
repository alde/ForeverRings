-- Turns a ring's slots into the ordered actions shown as slices. Pure:
-- everything that needs the game arrives through the context table
-- (see Context.lua), so this is unit tested.
--
-- An action is { type = "item"|"spell"|"macro", value = <attribute value>,
-- label, icon, count (items only), itemID (items only) }.
local _, ns = ...

ns.Actions = {}

-- Best first: higher item level wins, ties go to the higher item ID,
-- which in practice is the newer (and usually stronger) item.
local function IsBetter(a, b)
    if a.itemLevel ~= b.itemLevel then
        return a.itemLevel > b.itemLevel
    end
    return a.itemID > b.itemID
end

local function MatchingItems(context, category)
    local matches = {}
    for _, item in ipairs(context.items) do
        if item.minLevel <= context.playerLevel and category.matchesItem(item, context) then
            matches[#matches + 1] = item
        end
    end
    table.sort(matches, IsBetter)
    if category.best then
        return { matches[1] }
    end
    return matches
end

local function KnownSpells(context, category)
    local actions = {}
    for _, spellID in ipairs(category.spellIDs) do
        actions[#actions + 1] = context.spell(spellID)
    end
    return actions
end

-- A category may hand its slot to another addon's macro while that
-- addon is loaded. The addon check guards against a macro left behind
-- after the addon was removed.
local function PreferredMacro(context, category)
    local preferred = category.preferMacro
    if preferred and context.addonLoaded(preferred.addon) then
        return context.macro(preferred.macro)
    end
end

local function ExpandCategory(context, key)
    local category = ns.Categories.Get(key)
    if not category then
        return {}
    end
    local macro = PreferredMacro(context, category)
    if macro then
        return { macro }
    end
    if category.collect then
        return category.collect(context)
    end
    if category.spellIDs then
        return KnownSpells(context, category)
    end
    return MatchingItems(context, category)
end

-- Fixed entries yield one action, or none when the context returns nil.
local function ExpandSlot(context, slot)
    if slot.category then return ExpandCategory(context, slot.category) end
    if slot.item then return { context.item(slot.item) } end
    if slot.spell then return { context.spell(slot.spell) } end
    if slot.macro then return { context.macro(slot.macro) } end
    return {}
end

-- Slots in order, without duplicate actions, capped at maxSlices.
function ns.Actions.Resolve(slots, context, maxSlices)
    local selected, seen = {}, {}
    for _, slot in ipairs(slots) do
        for _, action in ipairs(ExpandSlot(context, slot)) do
            if #selected >= maxSlices then
                return selected
            end
            local key = action.type .. ":" .. action.value
            if not seen[key] then
                seen[key] = true
                selected[#selected + 1] = action
            end
        end
    end
    return selected
end
