-- Event wiring, the ring registry and the out-of-combat queue.
local addonName, ns = ...

-- Bag, spell and item-info events arrive in bursts; wait this long
-- (seconds) after the first one before rescanning.
local REBUILD_DELAY = 0.2

local ringObjects = {}
local pendingOutOfCombat = {}
local rebuildScheduled = false

function ns.Print(message)
    print("|cff66ccffForeverRings|r: " .. message)
end

-- Runs fn now, or after combat if protected frames are locked. Calls
-- queued under the same key collapse into the latest one.
function ns.RunOutOfCombat(key, fn)
    if InCombatLockdown() then
        pendingOutOfCombat[key] = fn
    else
        fn()
    end
end

local function FlushOutOfCombat()
    local queued = pendingOutOfCombat
    pendingOutOfCombat = {}
    for _, fn in pairs(queued) do
        fn()
    end
end

-- Creates a ring object for every saved ring. Queued work runs in no
-- fixed order, so both rebuild and bindings call this first.
local function EnsureRingObjects()
    for name in pairs(ForeverRingsDB.rings) do
        ringObjects[name] = ringObjects[name] or ns.Ring.Create()
    end
end

local function ContextFor(context, ringName)
    return setmetatable({
        ring = function(targetName)
            return ns.Actions.SubringAction(ForeverRingsDB.rings, context, ringName, targetName, ns.Ring.MAX_SLICES)
        end,
    }, { __index = context })
end

local function HeaderForRing(name)
    return ringObjects[name] and ringObjects[name].header
end

-- Rings deleted from settings keep their frames but go empty.
function ns.RebuildRings()
    EnsureRingObjects()
    local context = ns.Context.Build()
    for name, ring in pairs(ringObjects) do
        local config = ForeverRingsDB.rings[name]
        local actions = config and ns.Actions.Resolve(config.slots, ContextFor(context, name), ns.Ring.MAX_SLICES)
        ring:SetActions(actions or {}, HeaderForRing)
    end
end

function ns.ApplyBindings()
    EnsureRingObjects()
    for name, ring in pairs(ringObjects) do
        local config = ForeverRingsDB.rings[name]
        ring:Bind(config and config.key)
    end
end

function ns.RequestRebuild()
    if rebuildScheduled then return end
    rebuildScheduled = true
    C_Timer.After(REBUILD_DELAY, function()
        rebuildScheduled = false
        ns.RunOutOfCombat("rebuild", ns.RebuildRings)
    end)
end

local function RefreshCounts()
    for _, ring in pairs(ringObjects) do
        ring:RefreshCounts()
    end
end

-- Names of the spells whose casts are counted, built on first cast:
-- spell names are not available while the addon is still loading.
local countedSpellNames

local function CountedSpellNames()
    if not countedSpellNames then
        countedSpellNames = {}
        for _, spellID in ipairs(ns.SpellLists.totem) do
            local name = C_Spell.GetSpellName(spellID)
            if name then countedSpellNames[name] = true end
        end
    end
    return countedSpellNames
end

-- Counts by name so every rank of a spell adds to one tally. Spell IDs
-- can be secret values in combat on this client; those casts go
-- uncounted rather than erroring.
local function CountCast(unit, _, spellID)
    if unit ~= "player" or (issecretvalue and issecretvalue(spellID)) then return end
    local name = C_Spell.GetSpellName(spellID)
    if name and CountedSpellNames()[name] then
        ns.Config.RecordSpellUse(name)
        ns.RequestRebuild()
    end
end

local handlers = {
    ADDON_LOADED = function(loadedName)
        if loadedName == addonName then
            ForeverRingsDB = ns.Config.Load(ForeverRingsDB)
            ForeverRingsCharDB = ns.Config.LoadCharacter(ForeverRingsCharDB)
        end
    end,
    UNIT_SPELLCAST_SUCCEEDED = CountCast,
    -- A /reload mid-fight logs in under combat lockdown.
    PLAYER_LOGIN = function()
        ns.RunOutOfCombat("rebuild", ns.RebuildRings)
        ns.RunOutOfCombat("bindings", ns.ApplyBindings)
    end,
    PLAYER_REGEN_ENABLED = FlushOutOfCombat,
    BAG_UPDATE_DELAYED = function()
        RefreshCounts()
        ns.RequestRebuild()
    end,
    PLAYER_LEVEL_UP = ns.RequestRebuild,
    GET_ITEM_INFO_RECEIVED = ns.RequestRebuild,
    SPELLS_CHANGED = ns.RequestRebuild,
    UPDATE_MACROS = ns.RequestRebuild,
    NEW_MOUNT_ADDED = ns.RequestRebuild,
}

local eventFrame = CreateFrame("Frame")
for event in pairs(handlers) do
    eventFrame:RegisterEvent(event)
end
eventFrame:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)

-- Favouriting a mount fires no event of its own.
if C_MountJournal then
    hooksecurefunc(C_MountJournal, "SetIsFavorite", function() ns.RequestRebuild() end)
end
