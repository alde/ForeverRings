-- A ring: a protected header frame holding slice icons, and a hidden secure
-- action button that a keybinding clicks. Key down opens the ring at the
-- cursor; key up uses the slice the cursor points at. Both happen in
-- restricted code so the ring works in combat. Contents can only change
-- out of combat (see ns.RunOutOfCombat); the spawn animation only moves
-- the insecure slice frames, so it runs in combat too.
local _, ns = ...

local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount

local SLICE_SIZE = 40
-- Twelve 40px icons need about 76px of radius to clear each other;
-- 90 leaves a visible gap.
local RING_RADIUS = 90
-- Releasing within this many pixels of the centre cancels.
local DEADZONE = 20
local HIGHLIGHT_TEXTURE = "Interface\\Buttons\\ButtonHilight-Square"

ns.Ring = { MAX_SLICES = 12 }

-- Restricted Lua: self is the binding button, owner the ring header.
-- The slice choice mirrors ns.Layout.NearestSlice; keep them in step.
-- Each slice's action type ("item", "spell" or "macro") doubles as the
-- name of the attribute SecureActionButtonTemplate reads its value from.
local CLICK_SNIPPET = [[
    local screen = owner:GetFrameRef("screen")
    local mouseX, mouseY = screen:GetMousePosition()
    if not mouseX then return false end
    local x, y = mouseX * screen:GetWidth(), mouseY * screen:GetHeight()

    if down then
        owner:SetAttribute("center-x", x)
        owner:SetAttribute("center-y", y)
        owner:ClearAllPoints()
        owner:SetPoint("CENTER", screen, "BOTTOMLEFT", x, y)
        owner:Show()
        return false
    end

    if not owner:IsShown() then return false end
    owner:Hide()

    local dx, dy = x - owner:GetAttribute("center-x"), y - owner:GetAttribute("center-y")
    local deadzone = owner:GetAttribute("deadzone")
    if dx * dx + dy * dy < deadzone * deadzone then return false end

    local best, bestDot
    for index = 1, owner:GetAttribute("slice-count") do
        local dot = dx * owner:GetAttribute("slice-x-" .. index)
                  + dy * owner:GetAttribute("slice-y-" .. index)
        if not bestDot or dot > bestDot then best, bestDot = index, dot end
    end
    if not best then return false end
    local actionType = owner:GetAttribute("slice-type-" .. best)
    self:SetAttribute("type", actionType)
    self:SetAttribute(actionType, owner:GetAttribute("slice-value-" .. best))
]]
ns.Ring.CLICK_SNIPPET = CLICK_SNIPPET

local screen

-- A protected full-screen frame giving restricted code a coordinate space.
local function GetScreen()
    if not screen then
        screen = CreateFrame("Frame", "ForeverRingsScreen", UIParent, "SecureHandlerBaseTemplate")
        screen:SetAllPoints(UIParent)
    end
    return screen
end

local function CreateHeader()
    local header = CreateFrame("Frame", nil, GetScreen(), "SecureHandlerBaseTemplate")
    local diameter = 2 * RING_RADIUS + SLICE_SIZE
    header:SetSize(diameter, diameter)
    header:SetFrameStrata("DIALOG")
    SecureHandlerSetFrameRef(header, "screen", GetScreen())
    header:SetAttribute("deadzone", DEADZONE)
    header:SetAttribute("slice-count", 0)
    header:Hide()
    return header
end

local function CreateBindingButton(index, header)
    local button = CreateFrame("Button", "ForeverRingsButton" .. index, UIParent, "SecureActionButtonTemplate")
    button:SetSize(1, 1)
    button:EnableMouse(false)
    button:RegisterForClicks("AnyDown", "AnyUp")
    -- The action must fire on key up, after the player has aimed.
    button:SetAttribute("useOnKeyDown", false)
    SecureHandlerWrapScript(button, "OnClick", header, CLICK_SNIPPET)
    return button
end

local function CreateSlice(header)
    local slice = CreateFrame("Frame", nil, header)
    slice:SetSize(SLICE_SIZE, SLICE_SIZE)
    slice.icon = slice:CreateTexture(nil, "ARTWORK")
    slice.icon:SetAllPoints()
    slice.highlight = slice:CreateTexture(nil, "OVERLAY")
    slice.highlight:SetAllPoints()
    slice.highlight:SetTexture(HIGHLIGHT_TEXTURE)
    slice.highlight:SetBlendMode("ADD")
    slice.highlight:Hide()
    slice.count = slice:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    slice.count:SetPoint("BOTTOMRIGHT", -2, 2)
    return slice
end

-- count is nil for spells and macros, which have no stack to show.
local function ShowCount(slice, count)
    slice.count:SetText(count and count > 1 and count or "")
    slice.icon:SetDesaturated(count == 0)
end

local RingMixin = {}
local createdRings = 0

function ns.Ring.Create()
    createdRings = createdRings + 1
    local header = CreateHeader()
    local ring = setmetatable({
        header = header,
        button = CreateBindingButton(createdRings, header),
        slices = {},
        actions = {},
        directions = {},
    }, { __index = RingMixin })
    header:HookScript("OnShow", function() ring:StartAnimation() end)
    header:HookScript("OnHide", function() ring:SetHovered(nil) end)
    header:SetScript("OnUpdate", function()
        ring:Animate()
        ring:TrackHoveredSlice()
    end)
    return ring
end

-- Out of combat only.
function RingMixin:SetActions(actions)
    self:SetHovered(nil) -- the old index may not exist in the new list
    self.actions = actions
    self.directions = ns.Layout.SliceDirections(#actions)
    self.header:SetAttribute("slice-count", #actions)
    for index, action in ipairs(actions) do
        self:ConfigureSlice(index, action, self.directions[index])
    end
    for index = #actions + 1, #self.slices do
        self.slices[index]:Hide()
    end
end

function RingMixin:ConfigureSlice(index, action, direction)
    local slice = self.slices[index] or CreateSlice(self.header)
    self.slices[index] = slice
    slice.icon:SetTexture(action.icon)
    ShowCount(slice, action.count)
    slice:Show()
    self:PlaceSlice(index, ns.Animation.RestPose())
    self.header:SetAttribute("slice-x-" .. index, direction.x)
    self.header:SetAttribute("slice-y-" .. index, direction.y)
    self.header:SetAttribute("slice-type-" .. index, action.type)
    self.header:SetAttribute("slice-value-" .. index, action.value)
end

-- Scale shrinks the slice's own coordinate space, so the distance is
-- divided by it to keep the slice on its circle.
function RingMixin:PlaceSlice(index, radiusFactor, alpha, scale, turn)
    local slice = self.slices[index]
    local x, y = ns.Layout.Rotate(self.directions[index], turn)
    local distance = RING_RADIUS * radiusFactor / scale
    slice:SetScale(scale)
    slice:SetAlpha(alpha)
    slice:ClearAllPoints()
    slice:SetPoint("CENTER", self.header, "CENTER", x * distance, y * distance)
end

function RingMixin:StartAnimation()
    self.shownAt = GetTime()
    self.animating = true
    self:Animate()
end

function RingMixin:Animate()
    if not self.animating then return end
    local settings = ns.Config.Animation()
    local radius, alpha, scale, turn, done =
        ns.Animation.Pose(settings.style, GetTime() - self.shownAt, settings.duration)
    for index = 1, #self.actions do
        self:PlaceSlice(index, radius, alpha, scale, turn)
    end
    self.animating = not done
end

-- Safe in combat: only touches insecure textures and font strings.
function RingMixin:RefreshCounts()
    for index, action in ipairs(self.actions) do
        if action.itemID then
            ShowCount(self.slices[index], GetItemCount(action.itemID))
        end
    end
end

function RingMixin:TrackHoveredSlice()
    local scale = self.header:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    local centerX, centerY = self.header:GetCenter()
    self:SetHovered(ns.Layout.NearestSlice(
        cursorX / scale - centerX, cursorY / scale - centerY, self.directions, DEADZONE))
end

-- The tooltip sits beside the ring so it never covers a slice.
local function ShowTooltip(header, action)
    GameTooltip:SetOwner(header, "ANCHOR_NONE")
    GameTooltip:SetPoint("LEFT", header, "RIGHT")
    if action.itemID then
        GameTooltip:SetItemByID(action.itemID)
    elseif action.spellID then
        GameTooltip:SetSpellByID(action.spellID)
    else
        GameTooltip:SetText(action.label)
    end
    GameTooltip:Show()
end

-- Highlights slice index (nil for none) and shows its tooltip. Does
-- nothing while the hovered slice stays the same, so the tooltip is not
-- rebuilt every frame.
function RingMixin:SetHovered(index)
    if index == self.hovered then return end
    self.hovered = index
    for sliceIndex, slice in ipairs(self.slices) do
        slice.highlight:SetShown(sliceIndex == index)
    end
    if index then
        ShowTooltip(self.header, self.actions[index])
    elseif GameTooltip:IsOwned(self.header) then
        GameTooltip:Hide()
    end
end

-- Out of combat only. A nil key removes the binding.
function RingMixin:Bind(key)
    ClearOverrideBindings(self.button)
    if key then
        SetOverrideBindingClick(self.button, false, key, self.button:GetName(), "LeftButton")
    end
end
