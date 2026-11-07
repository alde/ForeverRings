-- Category definitions. An item category matches bag items; a spell
-- category lists spells to offer when the player knows them; a collect
-- category asks the context for its actions directly. A "best" item
-- category fills a single slice with its best item, AutoBar style.
local _, ns = ...

-- Enum.ItemClass values.
local CONSUMABLE_CLASS = 0
local QUEST_CLASS = 12

-- Enum.ItemConsumableSubclass values on the Mainline item data.
local SUBCLASS = {
    POTION = 1,
    ELIXIR = 2,
    FLASK = 3,
    FOOD_AND_DRINK = 5,
    BANDAGE = 7,
}

-- Items in one subclass are told apart by the spell they cast on use.
-- These reference spells give the localised names to compare against.
local USE_SPELL = {
    DRINK = 430,          -- "Drink", cast by every water
    HEALING_POTION = 439, -- "Healing Potion", cast by healing potions
    RESTORE_MANA = 437,   -- "Restore Mana", cast by mana potions
}

-- Slices the Most Used Totems category fills, one per element on average.
local MOST_USED_TOTEM_SLICES = 4

local HEARTHSTONE_ITEM_IDS = {
    [6948] = true, -- Hearthstone
}

-- The Hearths addon keeps this macro pointed at its current hearthstone.
local HEARTHS_MACRO = { addon = "Hearths", macro = "HEARTHS_BTN" }

local function ByLabel(a, b)
    return a.label < b.label
end

local function SortedByLabel(actions)
    local sorted = {}
    for index, action in ipairs(actions) do sorted[index] = action end
    table.sort(sorted, ByLabel)
    return sorted
end

-- Known spells from spellIDs that have been cast at least once, most
-- cast first, list order breaking ties, capped at limit.
local function MostUsed(context, spellIDs, limit)
    local used = {}
    for order, spellID in ipairs(spellIDs) do
        local action = context.spell(spellID)
        local uses = action and context.spellUses(action.value) or 0
        if uses > 0 then
            used[#used + 1] = { action = action, uses = uses, order = order }
        end
    end
    table.sort(used, function(a, b)
        if a.uses ~= b.uses then return a.uses > b.uses end
        return a.order < b.order
    end)
    local actions = {}
    for index = 1, math.min(limit, #used) do
        actions[index] = used[index].action
    end
    return actions
end

local function IsConsumable(item, ...)
    if item.classID ~= CONSUMABLE_CLASS then
        return false
    end
    for _, subclass in ipairs({ ... }) do
        if item.subclassID == subclass then
            return true
        end
    end
    return false
end

local function UsesSpell(item, context, referenceSpellID)
    return item.useSpellName ~= nil and item.useSpellName == context.spellName(referenceSpellID)
end

-- Anything that is not recognised as healing or mana lands here, so a
-- potion is never lost to an unexpected spell name.
local function IsOtherPotion(item, context)
    return IsConsumable(item, SUBCLASS.POTION)
        and not UsesSpell(item, context, USE_SPELL.HEALING_POTION)
        and not UsesSpell(item, context, USE_SPELL.RESTORE_MANA)
end

local CATEGORIES = {
    {
        key = "healing", label = "Healing Potion", best = true,
        matchesItem = function(item, context)
            return IsConsumable(item, SUBCLASS.POTION) and UsesSpell(item, context, USE_SPELL.HEALING_POTION)
        end,
    },
    {
        key = "mana", label = "Mana Potion", best = true,
        matchesItem = function(item, context)
            return IsConsumable(item, SUBCLASS.POTION) and UsesSpell(item, context, USE_SPELL.RESTORE_MANA)
        end,
    },
    { key = "potion", label = "Other Potions", matchesItem = IsOtherPotion },
    {
        key = "flask", label = "Elixirs & Flasks",
        matchesItem = function(item) return IsConsumable(item, SUBCLASS.ELIXIR, SUBCLASS.FLASK) end,
    },
    -- Food is whatever in the subclass does not drink, so food with an
    -- unusual use spell (well fed, conjured) still turns up.
    {
        key = "food", label = "Food", best = true,
        matchesItem = function(item, context)
            return IsConsumable(item, SUBCLASS.FOOD_AND_DRINK) and not UsesSpell(item, context, USE_SPELL.DRINK)
        end,
    },
    {
        key = "water", label = "Drink", best = true,
        matchesItem = function(item, context)
            return IsConsumable(item, SUBCLASS.FOOD_AND_DRINK) and UsesSpell(item, context, USE_SPELL.DRINK)
        end,
    },
    {
        key = "bandage", label = "Bandage", best = true,
        matchesItem = function(item) return IsConsumable(item, SUBCLASS.BANDAGE) end,
    },
    {
        key = "quest", label = "Usable Quest Items",
        matchesItem = function(item) return item.classID == QUEST_CLASS and item.hasUseEffect end,
    },
    {
        key = "hearthstone", label = "Hearthstone", best = true, preferMacro = HEARTHS_MACRO,
        matchesItem = function(item) return HEARTHSTONE_ITEM_IDS[item.itemID] == true end,
    },
    { key = "teleport", label = "Teleports", spellIDs = ns.SpellLists.teleport },
    { key = "portal", label = "Portals", spellIDs = ns.SpellLists.portal },
    { key = "buff", label = "Class Buffs", spellIDs = ns.SpellLists.buff },
    { key = "earthtotem", label = "Earth Totems", spellIDs = ns.SpellLists.earthTotem },
    { key = "firetotem", label = "Fire Totems", spellIDs = ns.SpellLists.fireTotem },
    { key = "watertotem", label = "Water Totems", spellIDs = ns.SpellLists.waterTotem },
    { key = "airtotem", label = "Air Totems", spellIDs = ns.SpellLists.airTotem },
    {
        key = "frequenttotem", label = "Most Used Totems",
        collect = function(context) return MostUsed(context, ns.SpellLists.totem, MOST_USED_TOTEM_SLICES) end,
    },
    {
        key = "randommount", label = "Random Favourite Mount",
        collect = function(context) return { context.randomFavoriteMount() } end,
    },
    {
        key = "mount", label = "Favourite Mounts",
        collect = function(context) return SortedByLabel(context.favoriteMounts()) end,
    },
}

local categoryByKey = {}
for _, category in ipairs(CATEGORIES) do
    categoryByKey[category.key] = category
end

ns.Categories = {}

function ns.Categories.All()
    return CATEGORIES
end

function ns.Categories.Get(key)
    return categoryByKey[key]
end
