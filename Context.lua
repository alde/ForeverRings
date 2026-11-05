-- The game-facing side of Actions.Resolve: reads bags, spells and macros
-- into action records.
local _, ns = ...

local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetItemSpell = C_Item and C_Item.GetItemSpell or GetItemSpell
local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount
local GetSpellName = C_Spell and C_Spell.GetSpellName or function(spellID) return (GetSpellInfo(spellID)) end
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture

local FIRST_BAG = 0 -- the backpack
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS
local CATEGORY_ICON = "Interface\\Icons\\INV_Misc_Bag_08"

ns.Context = {}

local function ItemAction(itemID, count)
    local _, _, _, _, icon, classID, subclassID = GetItemInfoInstant(itemID)
    -- Uncached items report nil here; GET_ITEM_INFO_RECEIVED triggers a rescan.
    local name, _, _, itemLevel, minLevel = GetItemInfo(itemID)
    local useSpellName = GetItemSpell(itemID)
    return {
        type = "item",
        value = "item:" .. itemID,
        itemID = itemID,
        label = name or ("item:" .. itemID),
        icon = icon,
        count = count,
        classID = classID,
        subclassID = subclassID,
        itemLevel = itemLevel or 0,
        minLevel = minLevel or 0,
        useSpellName = useSpellName,
        hasUseEffect = useSpellName ~= nil,
    }
end

-- Looking a spell up by name gives the rank a cast by that name uses,
-- the highest known. Falls back to the ID we started from.
local function CastSpellID(name, fallbackID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(name)
        return info and info.spellID or fallbackID
    end
    return select(7, GetSpellInfo(name)) or fallbackID
end

-- Cast by name so the highest known rank is used; spellID is that rank,
-- for the tooltip.
local function SpellAction(spellID)
    local name = GetSpellName(spellID)
    if not name or not IsPlayerSpell(spellID) then
        return nil
    end
    return {
        type = "spell",
        value = name,
        label = name,
        icon = GetSpellTexture(spellID),
        spellID = CastSpellID(name, spellID),
    }
end

local function MacroAction(name)
    if GetMacroIndexByName(name) == 0 then
        return nil
    end
    local _, icon = GetMacroInfo(name)
    return { type = "macro", value = name, label = name, icon = icon }
end

local function CountItemsInBags()
    local counts = {}
    for bag = FIRST_BAG, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                counts[info.itemID] = (counts[info.itemID] or 0) + info.stackCount
            end
        end
    end
    return counts
end

local function ScanBags()
    local items = {}
    for itemID, count in pairs(CountItemsInBags()) do
        items[#items + 1] = ItemAction(itemID, count)
    end
    return items
end

function ns.Context.Build()
    return {
        items = ScanBags(),
        playerLevel = UnitLevel("player"),
        spellName = GetSpellName,
        item = function(itemID) return ItemAction(itemID, GetItemCount(itemID)) end,
        spell = SpellAction,
        macro = MacroAction,
    }
end

-- Label and icon for the options list, whether or not the player can
-- use the slot right now.
function ns.Context.DescribeSlot(slot)
    if slot.category then
        local category = ns.Categories.Get(slot.category)
        local label = category and category.label or slot.category
        local suffix = category and category.best and " (best one)" or ""
        return "Category: " .. label .. suffix, CATEGORY_ICON
    end
    if slot.item then
        local action = ItemAction(slot.item, 0)
        return action.label, action.icon
    end
    if slot.spell then
        return GetSpellName(slot.spell) or ("spell:" .. slot.spell), GetSpellTexture(slot.spell)
    end
    local _, icon = GetMacroInfo(slot.macro)
    return "Macro: " .. slot.macro, icon
end
