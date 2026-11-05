-- Spell IDs for the spell categories. Rank 1 IDs: rings cast by name,
-- which picks the highest rank the player knows. Spells the player does
-- not know are skipped, so one flat list covers every class and faction.
-- These are classic-era IDs; check them with /frings scan in game.
local _, ns = ...

ns.SpellLists = {}

ns.SpellLists.teleport = {
    3561,  -- Teleport: Stormwind
    3562,  -- Teleport: Ironforge
    3565,  -- Teleport: Darnassus
    32271, -- Teleport: Exodar
    49359, -- Teleport: Theramore
    33690, -- Teleport: Shattrath (Alliance)
    3567,  -- Teleport: Orgrimmar
    3563,  -- Teleport: Undercity
    3566,  -- Teleport: Thunder Bluff
    32272, -- Teleport: Silvermoon
    49358, -- Teleport: Stonard
    35715, -- Teleport: Shattrath (Horde)
    53140, -- Teleport: Dalaran
    18960, -- Teleport: Moonglade
    556,   -- Astral Recall
    50977, -- Death Gate
}

ns.SpellLists.portal = {
    10059, -- Portal: Stormwind
    11416, -- Portal: Ironforge
    11419, -- Portal: Darnassus
    32266, -- Portal: Exodar
    49360, -- Portal: Theramore
    33691, -- Portal: Shattrath (Alliance)
    11417, -- Portal: Orgrimmar
    11418, -- Portal: Undercity
    11420, -- Portal: Thunder Bluff
    32267, -- Portal: Silvermoon
    49361, -- Portal: Stonard
    35717, -- Portal: Shattrath (Horde)
    53142, -- Portal: Dalaran
}

ns.SpellLists.buff = {
    -- Mage
    1459,  -- Arcane Intellect
    23028, -- Arcane Brilliance
    168,   -- Frost Armor
    7302,  -- Ice Armor
    6117,  -- Mage Armor
    30482, -- Molten Armor
    1008,  -- Amplify Magic
    604,   -- Dampen Magic
    587,   -- Conjure Food
    5504,  -- Conjure Water
    42955, -- Conjure Refreshment
    -- Priest
    1243,  -- Power Word: Fortitude
    21562, -- Prayer of Fortitude
    14752, -- Divine Spirit
    27681, -- Prayer of Spirit
    976,   -- Shadow Protection
    27683, -- Prayer of Shadow Protection
    588,   -- Inner Fire
    -- Druid
    1126,  -- Mark of the Wild
    21849, -- Gift of the Wild
    467,   -- Thorns
    -- Paladin
    19740, -- Blessing of Might
    19742, -- Blessing of Wisdom
    20217, -- Blessing of Kings
    1038,  -- Blessing of Salvation
    19977, -- Blessing of Light
    20911, -- Blessing of Sanctuary
    25782, -- Greater Blessing of Might
    25894, -- Greater Blessing of Wisdom
    25898, -- Greater Blessing of Kings
    25895, -- Greater Blessing of Salvation
    -- Warlock
    687,   -- Demon Skin
    706,   -- Demon Armor
    28176, -- Fel Armor
    5697,  -- Unending Breath
    132,   -- Detect Lesser Invisibility
    -- Shaman
    324,   -- Lightning Shield
    24398, -- Water Shield
    -- Warrior
    6673,  -- Battle Shout
    469,   -- Commanding Shout
    -- Hunter
    13165, -- Aspect of the Hawk
    13163, -- Aspect of the Monkey
    5118,  -- Aspect of the Cheetah
    13159, -- Aspect of the Pack
    20043, -- Aspect of the Wild
    19506, -- Trueshot Aura
}
