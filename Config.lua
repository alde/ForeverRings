-- Saved settings: loading, migration and every change to them, shared by
-- the slash commands and the options panel.
--
-- ForeverRingsDB = {
--   version = SCHEMA_VERSION,
--   rings = { [name] = { key = "CTRL-Q", slots = { slot, ... } } },
--   animation = { style = "grow", duration = 0.15 },
-- }
-- A slot is one of { category = key }, { item = itemID },
-- { spell = spellID } or { macro = name }.
local _, ns = ...

-- 1: rings held a categories list. 2: rings hold slots.
-- 3: potions and food & drink split into best-item categories.
-- 4: a Mounts ring.
local SCHEMA_VERSION = 4

-- The default rings as of version 2. Later migrations bring them up to
-- date along with everyone else's rings.
local DEFAULT_RINGS = {
    Consumables = { "potion", "flask", "food", "bandage" },
    Travel = { "hearthstone", "teleport", "portal" },
    Buffs = { "buff" },
    Quest = { "quest" },
}

-- Version 3 category splits: old key -> the keys that replace it.
local SPLIT_CATEGORIES = {
    potion = { "healing", "mana", "potion" },
    food = { "food", "water" },
}

ns.Config = {}
local Config = ns.Config

local function CategorySlots(keys)
    local slots = {}
    for index, key in ipairs(keys) do
        slots[index] = { category = key }
    end
    return slots
end

local function SplitSlots(slots)
    local split = {}
    for _, slot in ipairs(slots) do
        for _, key in ipairs(SPLIT_CATEGORIES[slot.category] or {}) do
            split[#split + 1] = { category = key }
        end
        if not SPLIT_CATEGORIES[slot.category] then
            split[#split + 1] = slot
        end
    end
    return split
end

-- MIGRATIONS[n] takes saved settings from version n to n + 1. Settings
-- saved before versioning count as version 1, as does a fresh install.
local MIGRATIONS = {
    function(db)
        for _, ring in pairs(db.rings) do
            ring.slots = ring.slots or CategorySlots(ring.categories or {})
            ring.categories = nil
        end
        for name, keys in pairs(DEFAULT_RINGS) do
            db.rings[name] = db.rings[name] or { slots = CategorySlots(keys) }
        end
    end,
    function(db)
        for _, ring in pairs(db.rings) do
            ring.slots = SplitSlots(ring.slots)
        end
    end,
    function(db)
        db.rings.Mounts = db.rings.Mounts or { slots = CategorySlots({ "randommount", "mount" }) }
    end,
}

local function FillAnimationDefaults(animation)
    animation.style = animation.style or ns.Animation.DEFAULT_STYLE
    animation.duration = animation.duration or ns.Animation.DEFAULT_DURATION
    return animation
end

-- Returns the saved table brought up to the current schema.
function Config.Load(saved)
    local db = saved or {}
    db.rings = db.rings or {}
    for version = db.version or 1, SCHEMA_VERSION - 1 do
        MIGRATIONS[version](db)
    end
    db.version = SCHEMA_VERSION
    db.animation = FillAnimationDefaults(db.animation or {})
    return db
end

-- Ring changes touch protected frames, so in combat they wait.
local function ApplyRingChanges()
    if InCombatLockdown() then
        ns.Print("in combat; ring changes apply when it ends.")
    end
    ns.RunOutOfCombat("rebuild", ns.RebuildRings)
    ns.RunOutOfCombat("bindings", ns.ApplyBindings)
end

function Config.RingNames()
    local names = {}
    for name in pairs(ForeverRingsDB.rings) do
        names[#names + 1] = name
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function Config.Ring(name)
    return ForeverRingsDB.rings[name]
end

function Config.FindRingName(input)
    for name in pairs(ForeverRingsDB.rings) do
        if name:lower() == (input or ""):lower() then
            return name
        end
    end
end

-- Returns a problem description, or nil when the name is usable.
function Config.ValidateNewRingName(name)
    if not name or not name:match("^[%w_%-]+$") then
        return "ring names are letters, digits, - and _ only."
    end
    if Config.FindRingName(name) then
        return "there is already a ring called " .. name .. "."
    end
end

function Config.CreateRing(name, categoryKeys)
    ForeverRingsDB.rings[name] = { slots = CategorySlots(categoryKeys or {}) }
    ApplyRingChanges()
end

function Config.DeleteRing(name)
    ForeverRingsDB.rings[name] = nil
    ApplyRingChanges()
end

function Config.SetRingKey(name, key)
    ForeverRingsDB.rings[name].key = key
    ApplyRingChanges()
end

local function SlotKey(slot)
    if slot.category then return "category:" .. slot.category end
    if slot.item then return "item:" .. slot.item end
    if slot.spell then return "spell:" .. slot.spell end
    return "macro:" .. slot.macro
end

-- Returns false when the ring already holds the same slot.
function Config.AddSlot(name, slot)
    local slots = ForeverRingsDB.rings[name].slots
    for _, existing in ipairs(slots) do
        if SlotKey(existing) == SlotKey(slot) then
            return false
        end
    end
    slots[#slots + 1] = slot
    ApplyRingChanges()
    return true
end

function Config.RemoveSlot(name, index)
    table.remove(ForeverRingsDB.rings[name].slots, index)
    ApplyRingChanges()
end

-- Swaps a slot with its neighbour; delta is -1 (earlier) or 1 (later).
function Config.MoveSlot(name, index, delta)
    local slots = ForeverRingsDB.rings[name].slots
    local target = index + delta
    if not slots[index] or not slots[target] then
        return
    end
    slots[index], slots[target] = slots[target], slots[index]
    ApplyRingChanges()
end

function Config.Animation()
    return ForeverRingsDB.animation
end

function Config.SetAnimationStyle(style)
    ForeverRingsDB.animation.style = style
end

function Config.SetAnimationDuration(seconds)
    ForeverRingsDB.animation.duration = seconds
end
