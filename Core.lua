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

-- Rings deleted from settings keep their frames but go empty.
function ns.RebuildRings()
    EnsureRingObjects()
    local context = ns.Context.Build()
    for name, ring in pairs(ringObjects) do
        local config = ForeverRingsDB.rings[name]
        ring:SetActions(config and ns.Actions.Resolve(config.slots, context, ns.Ring.MAX_SLICES) or {})
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

local handlers = {
    ADDON_LOADED = function(loadedName)
        if loadedName == addonName then
            ForeverRingsDB = ns.Config.Load(ForeverRingsDB)
        end
    end,
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
