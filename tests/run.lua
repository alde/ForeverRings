-- Plain-Lua tests for the parts that do not need the game client.
-- Run from the repository root: luajit tests/run.lua
local ns = {}
-- Commands.lua registers slash commands and a login frame as it loads.
SlashCmdList = {}
CreateFrame = function()
    return { RegisterEvent = function() end, SetScript = function() end }
end
for _, path in ipairs({ "SpellLists.lua", "Categories.lua", "Actions.lua", "Layout.lua",
                        "Animation.lua", "Config.lua", "Ring.lua", "Commands.lua" }) do
    assert(loadfile(path))("ForeverRings", ns)
end

local failures, passed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failures = failures + 1
        print("FAIL " .. name .. "\n  " .. tostring(err))
    end
end

local function eq(actual, expected, label)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(label or "value", tostring(expected), tostring(actual)), 2)
    end
end

local function near(actual, expected, label)
    if math.abs(actual - expected) > 1e-9 then
        error(("%s: expected %s, got %s"):format(label or "value", expected, actual), 2)
    end
end

---------------------------------------------------------------- Actions.Resolve

local POTION, ELIXIR, FLASK, FOOD, BANDAGE = 1, 2, 3, 5, 7
-- Reference spells Categories.lua compares use-spell names against.
local SPELL_NAMES = { [430] = "Drink", [439] = "Healing Potion", [437] = "Restore Mana" }

local function item(itemID, subclassID, overrides)
    local record = {
        type = "item", value = "item:" .. itemID, itemID = itemID, classID = 0,
        subclassID = subclassID, itemLevel = 1, minLevel = 0, count = 1,
    }
    for key, value in pairs(overrides or {}) do record[key] = value end
    return record
end

local function food(itemID, overrides)
    local record = item(itemID, FOOD, { useSpellName = "Food" })
    for key, value in pairs(overrides or {}) do record[key] = value end
    return record
end

local function water(itemID, itemLevel)
    return item(itemID, FOOD, { useSpellName = "Drink", itemLevel = itemLevel or 1 })
end

local function healingPotion(itemID, overrides)
    local record = item(itemID, POTION, { useSpellName = "Healing Potion" })
    for key, value in pairs(overrides or {}) do record[key] = value end
    return record
end

-- A game stand-in: bag contents plus the spells and macros the player has.
local function context(bags, options)
    options = options or {}
    local known, macros = options.knownSpells or {}, options.macros or {}
    return {
        items = bags,
        playerLevel = options.playerLevel or 60,
        spellName = function(spellID) return SPELL_NAMES[spellID] end,
        item = function(itemID) return item(itemID, 0, { count = 0 }) end,
        spell = function(spellID)
            return known[spellID] and { type = "spell", value = known[spellID] } or nil
        end,
        macro = function(name)
            return macros[name] and { type = "macro", value = name } or nil
        end,
        addonLoaded = function(name) return options.addons and options.addons[name] or false end,
        spellUses = function(name) return options.uses and options.uses[name] or 0 end,
        randomFavoriteMount = function() return options.randomMount end,
        favoriteMounts = function() return options.mounts or {} end,
    }
end

local function mount(name)
    return { type = "spell", value = name, label = name }
end

local function categories(...)
    local slots = {}
    for index, key in ipairs({ ... }) do slots[index] = { category = key } end
    return slots
end

local function values(actions)
    local out = {}
    for index, action in ipairs(actions) do out[index] = action.value end
    return table.concat(out, ",")
end

local resolve = ns.Actions.Resolve

test("groups by the ring's slot order", function()
    local bags = { food(10), healingPotion(20), item(30, BANDAGE) }
    eq(values(resolve(categories("bandage", "healing", "food"), context(bags), 12)), "item:30,item:20,item:10")
end)

test("food and drink get a slice each, best one only", function()
    local bags = { food(1, { itemLevel = 5 }), food(2, { itemLevel = 25 }), water(3, 15), water(4, 35) }
    eq(values(resolve(categories("food", "water"), context(bags), 12)), "item:2,item:4")
end)

test("food with an unusual use spell still counts as food", function()
    local bags = { food(1, { useSpellName = "Well Fed" }) }
    eq(values(resolve(categories("food"), context(bags), 12)), "item:1")
end)

test("healing and mana potions get a slice each, the rest share one group", function()
    local bags = {
        healingPotion(1), healingPotion(2, { itemLevel = 20 }),
        item(3, POTION, { useSpellName = "Restore Mana" }),
        item(4, POTION, { useSpellName = "Free Action" }), item(5, POTION, { useSpellName = "Swiftness" }),
    }
    eq(values(resolve(categories("healing", "mana", "potion"), context(bags), 12)), "item:2,item:3,item:5,item:4")
end)

test("an empty best-item category adds no slice", function()
    eq(values(resolve(categories("mana", "food"), context({ food(1) }), 12)), "item:1")
end)

test("puts the highest item level first within a category", function()
    local bags = { item(1, FLASK, { itemLevel = 5 }), item(2, FLASK, { itemLevel = 45 }) }
    eq(values(resolve(categories("flask"), context(bags), 12)), "item:2,item:1")
end)

test("breaks item level ties by the newer item ID", function()
    eq(values(resolve(categories("flask"), context({ item(5, FLASK), item(9, FLASK) }), 12)), "item:9,item:5")
end)

test("leaves out items above the player's level", function()
    local bags = { healingPotion(1, { minLevel = 10 }), healingPotion(2, { minLevel = 50, itemLevel = 50 }) }
    eq(values(resolve(categories("healing"), context(bags, { playerLevel = 20 }), 12)), "item:1")
end)

test("elixirs and flasks share a category", function()
    eq(values(resolve(categories("flask"), context({ item(1, ELIXIR), item(2, FLASK) }), 12)), "item:2,item:1")
end)

test("ignores non-consumables with a matching subclass number", function()
    eq(values(resolve(categories("potion"), context({ item(1, POTION, { classID = 2 }) }), 12)), "")
end)

test("finds the hearthstone by item ID", function()
    local bags = { item(6948, 8, { classID = 15 }) }
    eq(values(resolve(categories("hearthstone"), context(bags), 12)), "item:6948")
end)

test("offers quest items only when they have a use", function()
    local bags = { item(1, 0, { classID = 12, hasUseEffect = true }), item(2, 0, { classID = 12 }) }
    eq(values(resolve(categories("quest"), context(bags), 12)), "item:1")
end)

test("offers only the teleports the player knows, in list order", function()
    local known = { [3567] = "Teleport: Orgrimmar", [3561] = "Teleport: Stormwind" }
    eq(values(resolve(categories("teleport"), context({}, { knownSpells = known }), 12)),
        "Teleport: Stormwind,Teleport: Orgrimmar")
end)

test("offers known class buffs, conjuring included", function()
    local known = { [1459] = "Arcane Intellect", [5504] = "Conjure Water" }
    eq(values(resolve(categories("buff"), context({}, { knownSpells = known }), 12)), "Arcane Intellect,Conjure Water")
end)

test("the hearthstone slot uses the Hearths macro while Hearths is loaded", function()
    local game = context({ item(6948, 8, { classID = 15 }) },
        { addons = { Hearths = true }, macros = { HEARTHS_BTN = true } })
    eq(values(resolve(categories("hearthstone"), game, 12)), "HEARTHS_BTN")
end)

test("a Hearths macro left behind after removing Hearths is ignored", function()
    local game = context({ item(6948, 8, { classID = 15 }) }, { macros = { HEARTHS_BTN = true } })
    eq(values(resolve(categories("hearthstone"), game, 12)), "item:6948")
end)

test("with Hearths loaded but no macro yet, the hearthstone item is used", function()
    local game = context({ item(6948, 8, { classID = 15 }) }, { addons = { Hearths = true } })
    eq(values(resolve(categories("hearthstone"), game, 12)), "item:6948")
end)

test("random favourite mount is one slice when the journal offers it", function()
    local game = context({}, { randomMount = { type = "spell", value = 150544, label = "Random" } })
    eq(values(resolve(categories("randommount"), game, 12)), "150544")
    eq(values(resolve(categories("randommount"), context({}), 12)), "", "unavailable")
end)

test("favourite mounts come one per slice, sorted by name", function()
    local game = context({}, { mounts = { mount("Swift Razzashi Raptor"), mount("Black Stallion") } })
    eq(values(resolve(categories("mount"), game, 12)), "Black Stallion,Swift Razzashi Raptor")
end)

test("a ring slot becomes one slice when the context offers that ring", function()
    local game = context({})
    game.ring = function(name)
        return name == "Fire" and { type = "ring", value = "Fire" } or nil
    end
    eq(values(resolve({ { ring = "Fire" }, { ring = "Gone" } }, game, 12)), "Fire")
end)

test("each totem element has its own category", function()
    local known = { [3599] = "Searing Totem", [5675] = "Mana Spring Totem" }
    local game = context({}, { knownSpells = known })
    eq(values(resolve(categories("firetotem"), game, 12)), "Searing Totem", "fire")
    eq(values(resolve(categories("watertotem"), game, 12)), "Mana Spring Totem", "water")
    eq(values(resolve(categories("airtotem"), game, 12)), "", "air")
end)

test("most used totems: top four by casts, ties in list order, unused left out", function()
    local known = {
        [8075] = "Strength of Earth Totem", [2484] = "Earthbind Totem", [3599] = "Searing Totem",
        [5675] = "Mana Spring Totem", [8512] = "Windfury Totem", [8177] = "Grounding Totem",
    }
    local uses = {
        ["Windfury Totem"] = 9, ["Searing Totem"] = 4, ["Mana Spring Totem"] = 4,
        ["Strength of Earth Totem"] = 2, ["Grounding Totem"] = 1,
    }
    local game = context({}, { knownSpells = known, uses = uses })
    eq(values(resolve(categories("frequenttotem"), game, 12)),
        "Windfury Totem,Searing Totem,Mana Spring Totem,Strength of Earth Totem")
end)

test("most used totems skip totems the character no longer knows", function()
    local game = context({}, { uses = { ["Searing Totem"] = 5 } })
    eq(values(resolve(categories("frequenttotem"), game, 12)), "")
end)

local function subring(rings, parent, target, game)
    return ns.Actions.SubringAction(rings, game or context({}), parent, target, 12)
end

test("a sub-ring slice shows the target's first icon and opens it", function()
    local rings = { Fire = { slots = { { macro = "Searing" } } } }
    local game = context({}, { macros = { Searing = true } })
    local action = subring(rings, "Totems", "Fire", game)
    eq(action.type, "ring")
    eq(action.value, "Fire")
end)

test("no sub-ring slice for a missing, empty or self-referencing ring", function()
    local rings = { Empty = { slots = {} }, Totems = { slots = { { ring = "Totems" } } } }
    eq(subring(rings, "Totems", "Gone"), nil, "missing")
    eq(subring(rings, "Totems", "Empty"), nil, "empty")
    eq(subring(rings, "Totems", "Totems"), nil, "itself")
end)

test("a sub-ring's own ring slots are ignored, so nesting stops at one level", function()
    local rings = { Middle = { slots = { { ring = "Inner" } } }, Inner = { slots = { { macro = "X" } } } }
    local game = context({}, { macros = { X = true } })
    game.ring = function(name) return subring(rings, "Middle", name, game) end
    eq(subring(rings, "Outer", "Middle", game), nil)
end)

test("mixes fixed entries with categories in slot order", function()
    local slots = { { macro = "Mount" }, { category = "food" }, { item = 6948 }, { spell = 1459 } }
    local game = context({ food(5) }, { knownSpells = { [1459] = "Arcane Intellect" }, macros = { Mount = true } })
    eq(values(resolve(slots, game, 12)), "Mount,item:5,item:6948,Arcane Intellect")
end)

test("keeps a fixed item that is not in the bags", function()
    local actions = resolve({ { item = 6948 } }, context({}), 12)
    eq(actions[1].count, 0)
end)

test("drops unknown spells and missing macros", function()
    eq(values(resolve({ { spell = 1459 }, { macro = "Gone" } }, context({}), 12)), "")
end)

test("caps the ring at the slice limit", function()
    local bags = {}
    for index = 1, 20 do bags[index] = item(index, FLASK) end
    eq(#resolve(categories("flask"), context(bags), 12), 12)
end)

test("lists an action once even when two slots produce it", function()
    eq(values(resolve({ { category = "healing" }, { item = 1 } }, context({ healingPotion(1) }), 12)), "item:1")
end)

test("skips unknown category keys", function()
    eq(values(resolve(categories("nonsense", "flask"), context({ item(1, FLASK) }), 12)), "item:1")
end)

---------------------------------------------------------------- Config

ns.Print = function() end
ns.RunOutOfCombat = function(_, fn) fn() end
ns.RebuildRings = function() end
ns.ApplyBindings = function() end
InCombatLockdown = function() return false end

local function categoryList(slots)
    local out = {}
    for index, slot in ipairs(slots) do
        out[index] = slot.category or slot.item or slot.spell or slot.macro or slot.ring
    end
    return table.concat(out, ",")
end

test("a fresh install gets the default rings with split categories", function()
    local db = ns.Config.Load(nil)
    eq(categoryList(db.rings.Consumables.slots), "healing,mana,potion,flask,food,water,bandage")
    eq(categoryList(db.rings.Travel.slots), "hearthstone,teleport,portal")
    eq(categoryList(db.rings.Buffs.slots), "buff")
    eq(categoryList(db.rings.Quest.slots), "quest")
    eq(categoryList(db.rings.Mounts.slots), "randommount,mount")
    eq(categoryList(db.rings.Totems.slots), "Earth Totems,Fire Totems,Water Totems,Air Totems,frequenttotem")
    eq(categoryList(db.rings["Fire Totems"].slots), "firetotem")
    eq(db.animation.style, ns.Animation.DEFAULT_STYLE)
end)

test("migrates version 1 category lists to split slots and keeps the key", function()
    local db = ns.Config.Load({ rings = { Consumables = { key = "CTRL-Q", categories = { "food", "potion" } } } })
    local ring = db.rings.Consumables
    eq(ring.categories, nil, "categories")
    eq(ring.key, "CTRL-Q")
    eq(categoryList(ring.slots), "food,water,healing,mana,potion")
end)

test("splits version 2 slots in place and leaves fixed entries alone", function()
    local db = ns.Config.Load({ version = 2, rings = {
        Mine = { slots = { { spell = 1459 }, { category = "food" }, { category = "bandage" } } },
    } })
    eq(categoryList(db.rings.Mine.slots), "1459,food,water,bandage")
end)

test("version 3 settings gain a Mounts ring, keeping one the user made", function()
    eq(categoryList(ns.Config.Load({ version = 3, rings = {} }).rings.Mounts.slots), "randommount,mount")
    local own = ns.Config.Load({ version = 3, rings = { Mounts = { slots = { { macro = "Mine" } } } } })
    eq(categoryList(own.rings.Mounts.slots), "Mine", "user's own ring")
end)

test("version 4 settings gain the Totems rings", function()
    local db = ns.Config.Load({ version = 4, rings = {} })
    eq(categoryList(db.rings["Air Totems"].slots), "airtotem", "element ring")
    eq(categoryList(db.rings.Totems.slots), "Earth Totems,Fire Totems,Water Totems,Air Totems,frequenttotem")
end)

test("casts are counted per spell name", function()
    ForeverRingsCharDB = ns.Config.LoadCharacter(nil)
    ns.Config.RecordSpellUse("Searing Totem")
    ns.Config.RecordSpellUse("Searing Totem")
    eq(ns.Config.SpellUses("Searing Totem"), 2, "counted")
    eq(ns.Config.SpellUses("Magma Totem"), 0, "never cast")
    eq(ns.Config.LoadCharacter(ForeverRingsCharDB).spellUses["Searing Totem"], 2, "kept on reload")
end)

test("default rings deleted before an upgrade stay deleted", function()
    eq(ns.Config.Load({ version = 2, rings = {} }).rings.Travel, nil)
end)

test("loading current settings changes nothing", function()
    local db = ns.Config.Load(nil)
    db.rings.Travel = nil
    local reloaded = ns.Config.Load(db)
    eq(reloaded.rings.Travel, nil, "deleted ring")
    eq(categoryList(reloaded.rings.Consumables.slots), "healing,mana,potion,flask,food,water,bandage")
end)

test("ring names are validated", function()
    ForeverRingsDB = ns.Config.Load(nil)
    eq(ns.Config.ValidateNewRingName("My_Ring-2"), nil, "valid")
    eq(ns.Config.ValidateNewRingName("Two Words"), nil, "inner space")
    assert(ns.Config.ValidateNewRingName(" Leading"), "leading space")
    assert(ns.Config.ValidateNewRingName("Trailing "), "trailing space")
    assert(ns.Config.ValidateNewRingName("a/b"), "punctuation")
    assert(ns.Config.ValidateNewRingName("travel"), "taken, any case")
    assert(ns.Config.ValidateNewRingName(nil), "missing")
end)

local function slotSummary(name)
    return categoryList(ForeverRingsDB.rings[name].slots)
end

test("slots can be added, moved and removed", function()
    ForeverRingsDB = ns.Config.Load(nil)
    ns.Config.CreateRing("Mine", { "food" })
    eq(ns.Config.AddSlot("Mine", { spell = 1459 }), true, "added")
    eq(ns.Config.AddSlot("Mine", { macro = "Mount" }), true, "added")
    ns.Config.MoveSlot("Mine", 3, -1)
    eq(slotSummary("Mine"), "food,Mount,1459")
    ns.Config.RemoveSlot("Mine", 1)
    eq(slotSummary("Mine"), "Mount,1459")
end)

test("the same slot cannot be added twice", function()
    ForeverRingsDB = ns.Config.Load(nil)
    ns.Config.CreateRing("Mine")
    ns.Config.AddSlot("Mine", { item = 6948 })
    eq(ns.Config.AddSlot("Mine", { item = 6948 }), false)
end)

test("moving past either end does nothing", function()
    ForeverRingsDB = ns.Config.Load(nil)
    ns.Config.CreateRing("Mine", { "food", "healing" })
    ns.Config.MoveSlot("Mine", 1, -1)
    ns.Config.MoveSlot("Mine", 2, 1)
    eq(slotSummary("Mine"), "food,healing")
end)

---------------------------------------------------------------- /rl

test("/rl counts as taken when another addon registered it", function()
    local globals = { SLASH_OTHER1 = "/reload", SLASH_OTHER2 = "/RL" }
    eq(ns.SlashCommandTaken("/rl", { OTHER = true }, globals), true)
end)

test("/rl is free when nobody registered it", function()
    local globals = { SLASH_OTHER1 = "/rld", SLASH_FOREVERRINGS1 = "/frings" }
    eq(ns.SlashCommandTaken("/rl", { OTHER = true, FOREVERRINGS = true }, globals), false)
end)

---------------------------------------------------------------- Layout

local directions = ns.Layout.SliceDirections(4)
local DEADZONE = 20

test("first slice points up, then clockwise", function()
    eq(ns.Layout.NearestSlice(0, 100, directions, DEADZONE), 1, "up")
    eq(ns.Layout.NearestSlice(100, 0, directions, DEADZONE), 2, "right")
    eq(ns.Layout.NearestSlice(0, -100, directions, DEADZONE), 3, "down")
    eq(ns.Layout.NearestSlice(-100, 0, directions, DEADZONE), 4, "left")
end)

test("releasing inside the dead zone selects nothing", function()
    eq(ns.Layout.NearestSlice(5, 5, directions, DEADZONE), nil)
end)

test("an empty ring selects nothing", function()
    eq(ns.Layout.NearestSlice(0, 100, {}, DEADZONE), nil)
end)

test("rotating up by a quarter turn points right", function()
    local x, y = ns.Layout.Rotate({ x = 0, y = 1 }, math.pi / 2)
    near(x, 1, "x")
    near(y, 0, "y")
end)

---------------------------------------------------------------- Animation

test("every style ends at rest", function()
    for _, style in ipairs(ns.Animation.STYLES) do
        local radius, alpha, scale, turn, done = ns.Animation.Pose(style.key, 1, 0.15)
        near(radius, 1, style.key .. " radius")
        near(alpha, 1, style.key .. " alpha")
        near(scale, 1, style.key .. " scale")
        near(turn, 0, style.key .. " turn")
        eq(done, true, style.key .. " done")
    end
end)

test("unfold starts at the centre, invisible", function()
    local radius, alpha, _, _, done = ns.Animation.Pose("unfold", 0, 0.15)
    near(radius, 0, "radius")
    near(alpha, 0, "alpha")
    eq(done, false, "done")
end)

test("grow never scales to zero", function()
    local _, _, scale = ns.Animation.Pose("grow", 0, 0.15)
    assert(scale > 0, "scale " .. scale)
end)

test("spiral starts turned back and has not finished halfway", function()
    local _, _, _, turn = ns.Animation.Pose("spiral", 0, 0.15)
    assert(turn < 0, "turn " .. turn)
    eq(select(5, ns.Animation.Pose("spiral", 0.075, 0.15)), false)
end)

test("zero duration and unknown styles show the ring at rest", function()
    eq(select(5, ns.Animation.Pose("unfold", 0, 0)), true, "zero duration")
    near(ns.Animation.Pose("nonsense", 0, 0.15), 1, "unknown radius")
end)

---------------------------------------------------------------- secure snippet

-- Runs the restricted snippets against fake frame handles.
local function Handle(attributes)
    local handle = { attributes = attributes or {}, shown = false, refs = {} }
    function handle:GetAttribute(name) return self.attributes[name] end
    function handle:SetAttribute(name, value) self.attributes[name] = value end
    function handle:GetFrameRef(label) return self.refs[label] end
    function handle:Show() self.shown = true end
    function handle:Hide() self.shown = false end
    function handle:IsShown() return self.shown end
    function handle:ClearAllPoints() end
    function handle:SetPoint() end
    return handle
end

-- A ring header with slices; values are "<prefix>value-<index>".
local function Header(screen, sliceDirections, sliceTypes, prefix)
    local header = Handle({ deadzone = DEADZONE, ["slice-count"] = #sliceDirections })
    header.refs.screen = screen
    for index, direction in ipairs(sliceDirections) do
        header.attributes["slice-x-" .. index] = direction.x
        header.attributes["slice-y-" .. index] = direction.y
        header.attributes["slice-type-" .. index] = sliceTypes and sliceTypes[index] or "item"
        header.attributes["slice-value-" .. index] = (prefix or "") .. "value-" .. index
    end
    return header
end

local function Snippet(source, signature, owner)
    local chunk = assert(loadstring(signature .. "\n" .. source))
    setfenv(chunk, { owner = owner })
    return chunk
end

-- subrings maps a slice index of the main ring to the slice types of
-- the ring it opens, which always has four slices.
local function SnippetHarness(sliceDirections, sliceTypes, subrings)
    local screen = Handle()
    screen.mouse = { 0.5, 0.5 }
    function screen:GetMousePosition() return self.mouse[1], self.mouse[2] end
    function screen:GetWidth() return 1000 end
    function screen:GetHeight() return 1000 end

    local owner = Header(screen, sliceDirections, sliceTypes)
    local opened = {}
    for index, types in pairs(subrings or {}) do
        opened[index] = Header(screen, ns.Layout.SliceDirections(4), types, "sub" .. index .. "-")
        owner.refs["subring-" .. index] = opened[index]
    end
    local click = Snippet(ns.Ring.CLICK_SNIPPET, "local self, button, down = ...", owner)
    local open = Snippet(ns.Ring.OPEN_SUBRING_SNIPPET, "local self = ...", owner)
    local button = Handle()
    return {
        owner = owner,
        button = button,
        subrings = opened,
        Click = function(down, mouseX, mouseY)
            screen.mouse = { mouseX, mouseY }
            return click(button, "LeftButton", down)
        end,
        Hover = function(index, mouseX, mouseY)
            screen.mouse = { mouseX, mouseY }
            open(Handle({ ["slice-index"] = index }))
        end,
    }
end

test("snippet: key down opens the ring and blocks the action", function()
    local harness = SnippetHarness(directions)
    eq(harness.Click(true, 0.5, 0.5), false, "returned")
    eq(harness.owner:IsShown(), true, "shown")
end)

test("snippet: key up closes the ring and sets the aimed slice's action", function()
    local harness = SnippetHarness(directions, { "item", "spell", "macro", "item" })
    harness.Click(true, 0.5, 0.5)
    eq(harness.Click(false, 0.6, 0.5), nil, "returned")
    eq(harness.owner:IsShown(), false, "shown")
    eq(harness.button:GetAttribute("type"), "spell")
    eq(harness.button:GetAttribute("spell"), "value-2")
end)

test("snippet: key up inside the dead zone cancels", function()
    local harness = SnippetHarness(directions)
    harness.Click(true, 0.5, 0.5)
    eq(harness.Click(false, 0.505, 0.5), false)
end)

test("snippet: key up without a key down does nothing", function()
    eq(SnippetHarness(directions).Click(false, 0.9, 0.5), false)
end)

test("snippet agrees with Layout.NearestSlice all round the ring", function()
    local twelve = ns.Layout.SliceDirections(12)
    for step = 0, 71 do
        -- Half-step offset keeps samples off slice boundaries, where
        -- either neighbour is a correct answer.
        local angle = (step + 0.5) * 2 * math.pi / 72
        local dx, dy = 100 * math.sin(angle), 100 * math.cos(angle)
        local harness = SnippetHarness(twelve)
        harness.Click(true, 0.5, 0.5)
        harness.Click(false, 0.5 + dx / 1000, 0.5 + dy / 1000)
        local expected = "value-" .. ns.Layout.NearestSlice(dx, dy, twelve, DEADZONE)
        eq(harness.button:GetAttribute("item"), expected, "angle step " .. step)
    end
end)

---------------------------------------------------------------- Cooldowns

-- Stand-ins for the game's cooldown APIs, set before Cooldowns.lua loads
-- because it captures some of them at load time.
local itemCooldowns, spellDurations, macroSpells, macroItems = {}, {}, {}, {}
C_Item = {
    GetItemCooldown = function(itemID) return unpack(itemCooldowns[itemID] or { 0, 0, 1 }) end,
    GetItemInfoInstant = function(link) return tonumber(link:match("item:(%d+)")) end,
}
C_Spell = { GetSpellCooldownDuration = function(spellID) return spellDurations[spellID] end }
GetMacroSpell = function(name) return macroSpells[name] end
GetMacroItem = function(name) return nil, macroItems[name] end
CooldownFrame_Set = function(cooldown, start, duration) cooldown.shown = { "item", start, duration } end
assert(loadfile("Context.lua"))("ForeverRings", ns)
assert(loadfile("Cooldowns.lua"))("ForeverRings", ns)

local function CooldownFrame()
    return {
        SetCooldownFromDurationObject = function(self, object) self.shown = { "spell", object } end,
        Clear = function(self) self.shown = { "clear" } end,
    }
end

local function shown(action)
    local cooldown = CooldownFrame()
    ns.Cooldowns.Show(cooldown, action)
    return table.concat(cooldown.shown, ",")
end

test("an item slice shows the item's cooldown", function()
    itemCooldowns[118] = { 100, 120, 1 }
    eq(shown({ type = "item", itemID = 118 }), "item,100,120")
end)

test("a spell slice passes the duration object straight through", function()
    spellDurations[1459] = "duration-object"
    eq(shown({ type = "spell", spellID = 1459 }), "spell,duration-object")
end)

test("a macro shows the cooldown of the spell it casts", function()
    macroSpells.Nuke, spellDurations[133] = 133, "fireball-duration"
    eq(shown({ type = "macro", value = "Nuke" }), "spell,fireball-duration")
end)

test("a macro shows the cooldown of the item it uses", function()
    macroItems.Pot, itemCooldowns[929] = "|Hitem:929::|h[Healing Potion]|h", { 50, 120, 1 }
    eq(shown({ type = "macro", value = "Pot" }), "item,50,120")
end)

test("a macro with neither spell nor item clears the swipe", function()
    eq(shown({ type = "macro", value = "Chat" }), "clear")
end)

test("snippet: hovering a ring slice opens that ring at the cursor", function()
    local harness = SnippetHarness(directions, { "ring", "item", "item", "item" }, { [1] = {} })
    harness.Click(true, 0.5, 0.5)
    harness.Hover(1, 0.5, 0.6)
    eq(harness.owner:IsShown(), false, "main ring")
    eq(harness.subrings[1]:IsShown(), true, "sub-ring")
    eq(harness.subrings[1]:GetAttribute("center-y"), 600, "centred on cursor")
end)

test("snippet: key up in a sub-ring uses the sub-ring's aimed slice", function()
    local harness = SnippetHarness(directions, { "ring", "item", "item", "item" },
        { [1] = { "spell", "spell", "spell", "spell" } })
    harness.Click(true, 0.5, 0.5)
    harness.Hover(1, 0.5, 0.6)
    harness.Click(false, 0.6, 0.6)
    eq(harness.subrings[1]:IsShown(), false, "sub-ring closed")
    eq(harness.button:GetAttribute("type"), "spell")
    eq(harness.button:GetAttribute("spell"), "sub1-value-2")
end)

test("snippet: releasing on a ring slice without opening it does nothing", function()
    local harness = SnippetHarness(directions, { "ring", "item", "item", "item" }, { [1] = {} })
    harness.Click(true, 0.5, 0.5)
    eq(harness.Click(false, 0.5, 0.6), false)
    eq(harness.button:GetAttribute("type"), nil)
end)

test("snippet: the next key down closes a sub-ring left open", function()
    local harness = SnippetHarness(directions, { "ring", "item", "item", "item" }, { [1] = {} })
    harness.Click(true, 0.5, 0.5)
    harness.Hover(1, 0.5, 0.6)
    harness.Click(true, 0.5, 0.5)
    eq(harness.subrings[1]:IsShown(), false, "sub-ring")
    eq(harness.owner:IsShown(), true, "main ring")
end)

test("snippet: hovering does nothing while the ring is closed", function()
    local harness = SnippetHarness(directions, { "ring", "item", "item", "item" }, { [1] = {} })
    harness.Hover(1, 0.5, 0.6)
    eq(harness.subrings[1]:IsShown(), false)
end)

print(("%d passed, %d failed"):format(passed, failures))
os.exit(failures == 0 and 0 or 1)
