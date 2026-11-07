-- The options: one content frame, shown either in its own movable window
-- or under Game Menu > Options > AddOns > ForeverRings. The Settings panel
-- takes the keyboard and blocks bags and the spellbook, so dragging
-- spells and items in only works in the window.
-- Widgets are built on first show, once saved variables have loaded.
local addonName, ns = ...
local Config = ns.Config

local MARGIN = 16
local SECTION_GAP = 20
local ROW_GAP = 8
local ROW_HEIGHT = 30
local ICON_SIZE = 24
local LIST_WIDTH = 580
local LIST_HEIGHT = 230
local BUTTON_HEIGHT = 22
local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true,
}
local NEW_RING_POPUP = "FOREVERRINGS_NEW_RING"
local DELETE_RING_POPUP = "FOREVERRINGS_DELETE_RING"
local WINDOW_WIDTH = 640
local WINDOW_HEIGHT = 560
-- Height of ButtonFrameTemplate's title bar, which the content sits below.
local WINDOW_TITLE_HEIGHT = 24

local content = CreateFrame("Frame")
local widgets = {}
local selectedRing

local Refresh -- defined once the widgets it updates exist

---------------------------------------------------------------- widgets

local function Label(parent, text, font)
    local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    label:SetText(text)
    return label
end

local function Button(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, BUTTON_HEIGHT)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function Dropdown(parent, width, setupMenu)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(width)
    dropdown:SetupMenu(setupMenu)
    return dropdown
end

---------------------------------------------------------------- ring actions

local function CreateRingNamed(name)
    local problem = Config.ValidateNewRingName(name)
    if problem then
        ns.Print(problem)
        return
    end
    Config.CreateRing(name)
    selectedRing = name
    Refresh()
end

local function AddSlot(slot)
    if not Config.AddSlot(selectedRing, slot) then
        ns.Print("that is already in " .. selectedRing .. ".")
    end
    Refresh()
end

-- Spells arrive as (spellbook slot, book, spellID); macros as an index.
local function SlotFromCursor()
    local kind, id, _, spellID = GetCursorInfo()
    if kind == "item" then return { item = id } end
    if kind == "spell" then return spellID and { spell = spellID } end
    if kind == "macro" then
        local name = GetMacroInfo(id)
        return name and { macro = name }
    end
end

local function AcceptCursor()
    if not GetCursorInfo() then return end
    local slot = SlotFromCursor()
    ClearCursor()
    if not slot then
        ns.Print("rings take spells, items and macros.")
        return
    end
    AddSlot(slot)
end

local function PopupEditBox(dialog)
    return dialog.editBox or dialog:GetEditBox()
end

StaticPopupDialogs[NEW_RING_POPUP] = {
    text = "Name for the new ring (letters, digits, spaces, - and _):",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function(dialog) CreateRingNamed(PopupEditBox(dialog):GetText()) end,
    EditBoxOnEnterPressed = function(editBox)
        CreateRingNamed(editBox:GetText())
        StaticPopup_Hide(NEW_RING_POPUP)
    end,
    EditBoxOnEscapePressed = function() StaticPopup_Hide(NEW_RING_POPUP) end,
}

StaticPopupDialogs[DELETE_RING_POPUP] = {
    text = "Delete the ring %s?",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function(_, name)
        Config.DeleteRing(name)
        selectedRing = nil
        Refresh()
    end,
}

---------------------------------------------------------------- key capture

local function KeyWithModifiers(key)
    return (IsAltKeyDown() and "ALT-" or "")
        .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "")
        .. (IsMetaKeyDown and IsMetaKeyDown() and "META-" or "")
        .. key
end

local function StopListening(button)
    button.listening = false
    button:EnableKeyboard(false)
end

local function StartListening(button)
    button.listening = true
    button:SetText("Press a key...")
    button:EnableKeyboard(true)
    button:SetPropagateKeyboardInput(false)
end

local function OnKeyCaptured(button, key)
    if MODIFIER_KEYS[key] then return end
    StopListening(button)
    if key ~= "ESCAPE" then
        Config.SetRingKey(selectedRing, KeyWithModifiers(key))
    end
    Refresh()
end

local function KeyButton(parent)
    local button = Button(parent, "", 160)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            StopListening(self)
            Config.SetRingKey(selectedRing, nil)
            Refresh()
        else
            StartListening(self)
        end
    end)
    button:SetScript("OnKeyDown", OnKeyCaptured)
    return button
end

---------------------------------------------------------------- slot list

local function CreateSlotRow(content)
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(LIST_WIDTH - 2 * ROW_GAP, ROW_HEIGHT)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", 4, 0)
    row.remove = Button(row, "Remove", 70)
    row.remove:SetPoint("RIGHT")
    row.down = Button(row, "Down", 56)
    row.down:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
    row.up = Button(row, "Up", 56)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)
    row.label = Label(row, "")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", ROW_GAP, 0)
    row.label:SetPoint("RIGHT", row.up, "LEFT", -ROW_GAP, 0)
    row.label:SetJustifyH("LEFT")
    return row
end

local function ConfigureRow(row, index, slot, slotCount)
    local label, icon = ns.Context.DescribeSlot(slot)
    row:SetPoint("TOPLEFT", widgets.slotContent, "TOPLEFT", ROW_GAP, -(index - 1) * ROW_HEIGHT)
    row.label:SetText(label)
    row.icon:SetTexture(icon)
    row.up:SetEnabled(index > 1)
    row.down:SetEnabled(index < slotCount)
    row.up:SetScript("OnClick", function() Config.MoveSlot(selectedRing, index, -1); Refresh() end)
    row.down:SetScript("OnClick", function() Config.MoveSlot(selectedRing, index, 1); Refresh() end)
    row.remove:SetScript("OnClick", function() Config.RemoveSlot(selectedRing, index); Refresh() end)
    row:Show()
end

local function RefreshSlotList()
    local slots = selectedRing and Config.Ring(selectedRing).slots or {}
    local rows = widgets.slotRows
    for index, slot in ipairs(slots) do
        rows[index] = rows[index] or CreateSlotRow(widgets.slotContent)
        ConfigureRow(rows[index], index, slot, #slots)
    end
    for index = #slots + 1, #rows do
        rows[index]:Hide()
    end
    widgets.slotContent:SetHeight(math.max(1, #slots * ROW_HEIGHT))
    widgets.emptyHint:SetShown(#slots == 0)
end

---------------------------------------------------------------- sections

local function BuildAnimationSection(anchor)
    local heading = Label(content, "Spawn animation", "GameFontNormal")
    heading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -SECTION_GAP)
    widgets.style = Dropdown(content, 180, function(_, root)
        for _, style in ipairs(ns.Animation.STYLES) do
            root:CreateRadio(style.label,
                function() return Config.Animation().style == style.key end,
                function() Config.SetAnimationStyle(style.key) end)
        end
    end)
    widgets.style:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -ROW_GAP)
    local duration = Label(content, "Duration")
    duration:SetPoint("LEFT", widgets.style, "RIGHT", SECTION_GAP, 0)
    widgets.duration = CreateFrame("Frame", nil, content, "MinimalSliderWithSteppersTemplate")
    widgets.duration:SetWidth(220)
    widgets.duration:SetPoint("LEFT", duration, "RIGHT", ROW_GAP, 0)
    return widgets.style
end

local function InitDurationSlider()
    local animation, slider = ns.Animation, MinimalSliderWithSteppersMixin
    local steps = math.floor((animation.MAX_DURATION - animation.MIN_DURATION) / animation.DURATION_STEP + 0.5)
    local formatter = CreateMinimalSliderFormatter(slider.Label.Right, function(value)
        return ("%.2f s"):format(value)
    end)
    widgets.duration:Init(Config.Animation().duration, animation.MIN_DURATION, animation.MAX_DURATION,
        steps, { [slider.Label.Right] = formatter })
    widgets.duration:RegisterCallback(slider.Event.OnValueChanged, function(_, value)
        Config.SetAnimationDuration(value)
    end, content)
end

local function BuildRingPicker(anchor)
    local heading = Label(content, "Rings", "GameFontNormal")
    heading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -SECTION_GAP)
    widgets.ring = Dropdown(content, 180, function(_, root)
        for _, name in ipairs(Config.RingNames()) do
            root:CreateRadio(name,
                function() return selectedRing == name end,
                function() selectedRing = name; Refresh() end)
        end
    end)
    widgets.ring:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -ROW_GAP)
    local new = Button(content, "New ring", 100, function() StaticPopup_Show(NEW_RING_POPUP) end)
    new:SetPoint("LEFT", widgets.ring, "RIGHT", SECTION_GAP, 0)
    widgets.delete = Button(content, "Delete", 100, function()
        StaticPopup_Show(DELETE_RING_POPUP, selectedRing, nil, selectedRing)
    end)
    widgets.delete:SetPoint("LEFT", new, "RIGHT", ROW_GAP, 0)
    return widgets.ring
end

local function BuildKeyRow(anchor)
    local label = Label(content, "Key")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -SECTION_GAP)
    widgets.key = KeyButton(content)
    widgets.key:SetPoint("LEFT", label, "LEFT", 60, 0)
    local hint = Label(content, "Click, then press a key. Right-click clears.", "GameFontDisableSmall")
    hint:SetPoint("LEFT", widgets.key, "RIGHT", ROW_GAP, 0)
    return label
end

-- Other rings can be added as slices that open them; never the ring
-- being edited.
local function AddRingEntries(root)
    root:CreateDivider()
    root:CreateTitle("Open another ring")
    for _, name in ipairs(Config.RingNames()) do
        if name ~= selectedRing then
            root:CreateButton(name, function() AddSlot({ ring = name }) end)
        end
    end
end

local function BuildAddRow(anchor)
    widgets.addCategory = Dropdown(content, 200, function(_, root)
        for _, category in ipairs(ns.Categories.All()) do
            root:CreateButton(category.label, function() AddSlot({ category = category.key }) end)
        end
        AddRingEntries(root)
    end)
    widgets.addCategory:SetDefaultText("Add a category or ring...")
    widgets.addCategory:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -SECTION_GAP)
    widgets.drop = Button(content, "Drop a spell, item or macro here", 260, AcceptCursor)
    widgets.drop:SetScript("OnReceiveDrag", AcceptCursor)
    widgets.drop:SetPoint("LEFT", widgets.addCategory, "RIGHT", SECTION_GAP, 0)
    return widgets.addCategory
end

local function BuildSlotList(anchor)
    local scroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scroll:SetSize(LIST_WIDTH, LIST_HEIGHT)
    scroll:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -ROW_GAP)
    local background = scroll:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.3)
    widgets.slotContent = CreateFrame("Frame", nil, scroll)
    widgets.slotContent:SetSize(LIST_WIDTH, 1)
    scroll:SetScrollChild(widgets.slotContent)
    widgets.slotRows = {}
    widgets.emptyHint = Label(scroll, "Empty. Add a category, or drop something from your spellbook or bags.",
        "GameFontDisable")
    widgets.emptyHint:SetPoint("CENTER")
    local footer = Label(content, "A ring shows its first " .. ns.Ring.MAX_SLICES
        .. " actions in this order. Categories fill themselves from your bags and spellbook.", "GameFontDisableSmall")
    footer:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -ROW_GAP)
end

local function BuildTitleRow(openWindow)
    widgets.title = Label(content, addonName, "GameFontNormalLarge")
    widgets.title:SetPoint("TOPLEFT", MARGIN, -MARGIN)
    widgets.popOut = Button(content, "Open in a window", 160, openWindow)
    widgets.popOut:SetPoint("LEFT", widgets.title, "RIGHT", SECTION_GAP, 0)
    local hint = Label(content, "to drag in spells and items", "GameFontDisableSmall")
    hint:SetPoint("LEFT", widgets.popOut, "RIGHT", ROW_GAP, 0)
    widgets.popOutHint = hint
    return widgets.title
end

local function Build(openWindow)
    local anchor = BuildAnimationSection(BuildTitleRow(openWindow))
    InitDurationSlider()
    anchor = BuildRingPicker(anchor)
    anchor = BuildKeyRow(anchor)
    anchor = BuildAddRow(anchor)
    BuildSlotList(anchor)
    widgets.built = true
end

---------------------------------------------------------------- refresh

function Refresh()
    if not widgets.built then return end
    if not (selectedRing and Config.Ring(selectedRing)) then
        selectedRing = Config.RingNames()[1]
    end
    local ring = selectedRing and Config.Ring(selectedRing)
    widgets.ring:GenerateMenu()
    widgets.style:GenerateMenu()
    if not widgets.key.listening then
        widgets.key:SetText(ring and ring.key or "Not bound")
    end
    for _, widget in ipairs({ widgets.delete, widgets.key, widgets.addCategory, widgets.drop }) do
        widget:SetEnabled(ring ~= nil)
    end
    RefreshSlotList()
end

content:SetScript("OnHide", function()
    if widgets.built then StopListening(widgets.key) end
end)

---------------------------------------------------------------- hosts

local settingsHost = CreateFrame("Frame")
local settingsCategory = Settings.RegisterCanvasLayoutCategory(settingsHost, addonName)
Settings.RegisterAddOnCategory(settingsCategory)

local function CreateWindow()
    local window = CreateFrame("Frame", "ForeverRingsOptionsWindow", UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(window)
    ButtonFrameTemplate_HideButtonBar(window)
    window.Inset:Hide()
    window:SetTitle(addonName)
    window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetPoint("CENTER")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()
    tinsert(UISpecialFrames, window:GetName()) -- Escape closes it
    return window
end

local window = CreateWindow()

local function OpenWindow()
    if SettingsPanel and SettingsPanel:IsShown() then
        HideUIPanel(SettingsPanel)
    end
    window:Show()
end

-- Moves the content into host. The title and pop-out button only make
-- sense in the Settings panel; the window has its own title bar.
local function Host(host, topInset)
    if not widgets.built then Build(OpenWindow) end
    content:SetParent(host)
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", 0, -topInset)
    content:SetPoint("BOTTOMRIGHT")
    content:Show()
    local inSettings = host == settingsHost
    widgets.title:SetShown(inSettings)
    widgets.popOut:SetShown(inSettings)
    widgets.popOutHint:SetShown(inSettings)
    Refresh()
end

settingsHost:SetScript("OnShow", function() Host(settingsHost, 0) end)
window:SetScript("OnShow", function() Host(window, WINDOW_TITLE_HEIGHT) end)

function ns.OpenOptions()
    window:SetShown(not window:IsShown())
end
-- Named in the TOC's AddonCompartmentFunc.
ForeverRings_OpenOptions = ns.OpenOptions
