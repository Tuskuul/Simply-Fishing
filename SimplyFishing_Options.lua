-- Simply Fishing 1.1.0 - native AddOns settings page.
-- The slash handler remains the single source of truth for changes so
-- options and chat commands do not drift apart.
local PANEL_NAME = "Simply Fishing"
local panel = CreateFrame("Frame", "SimplyFishingOptionsPanel", UIParent)
panel.name = PANEL_NAME
local category


local logo = panel:CreateTexture(nil, "ARTWORK")
logo:SetSize(64, 64)
logo:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, -18)
logo:SetTexture("Interface\\AddOns\\SimplyFishing\\SimplyFishingIcon")

local function label(parent, text, anchor, x, y, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
    fs:SetPoint("TOPLEFT", anchor or parent, "TOPLEFT", x or 0, y or 0)
    fs:SetText(text)
    return fs
end

local title = label(panel, "Simply Fishing", panel, 20, -20, "GameFontNormalLarge")
local intro = label(panel, "One key to cast, catch, and interact. Fishing requires an equipped pole.", panel, 20, -52, "GameFontHighlightSmall")
local controls = label(panel, "Fishing controls", panel, 20, -91, "GameFontNormal")

local keyLabel = label(panel, "Fishing / Interact key", panel, 22, -121, "GameFontHighlight")
local keyEdit = CreateFrame("EditBox", "SimplyFishingKeyEdit", panel, "InputBoxTemplate")
keyEdit:SetSize(190, 27)
keyEdit:SetPoint("TOPLEFT", panel, "TOPLEFT", 25, -145)
keyEdit:SetAutoFocus(false)
keyEdit:SetMaxLetters(40)
keyEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local function button(text, x, y, width, func)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", func)
    return b
end

local sync
local function dispatch(text)
    if SlashCmdList and SlashCmdList.SIMPLYFISHING then
        SlashCmdList.SIMPLYFISHING(text)
        if sync then sync() end
    end
end
local function applyKey()
    local entered = keyEdit:GetText() or ""
    entered = entered:upper():gsub("%s+", "")
    keyEdit:SetText(entered)
    keyEdit:ClearFocus()
    if entered ~= "" then dispatch("bind " .. entered) end
end
local applyBtn = button("Apply key", 330, -147, 92, applyKey)
local removeBtn = button("Unbind", 431, -147, 87, function()
    dispatch("unbind")
    keyEdit:SetText("")
end)
keyEdit:SetScript("OnEnterPressed", applyKey)
local example = label(panel, "Examples: CTRL-SPACE, RALT-SPACE, SHIFT-PAD1. Bind outside combat.", panel, 22, -181, "GameFontDisableSmall")

-- The text box is for manually entering native binding tokens. For physical
-- keyboard input, capture raw keys instead of text input: edit boxes
-- intentionally do not treat Ctrl-F (or most modified keys) as typed text.
local captureActive = false
local capture = CreateFrame("Frame", "SimplyFishingCaptureFrame", panel)
capture:SetSize(510, 120)
capture:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -195)
capture:SetFrameStrata("DIALOG")
capture:EnableMouse(true)
capture:EnableMouseWheel(false)
capture:EnableKeyboard(false)
local shade = capture:CreateTexture(nil, "BACKGROUND")
shade:SetAllPoints()
shade:SetColorTexture(0.05, 0.09, 0.12, 0.96)
local captureHelp = capture:CreateFontString(nil, "ARTWORK", "GameFontNormal")
captureHelp:SetPoint("TOP", capture, "TOP", 0, -18)
captureHelp:SetText("Press a keyboard or controller key with optional modifiers")
local captureHint = capture:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
captureHint:SetPoint("TOP", captureHelp, "BOTTOM", 0, -12)
captureHint:SetText("Esc cancels. Modifier keys alone wait for another key.")
capture:Hide()

local modifierKeyNames = {
    LSHIFT = true, RSHIFT = true, SHIFT = true,
    LCTRL = true, RCTRL = true, CTRL = true, LCONTROL = true, RCONTROL = true,
    LALT = true, RALT = true, ALT = true,
}
-- Use side-specific modifier states when the client exposes them.
-- Otherwise use standard WoW modifier tokens; never guess left/right.
local function modifierPart(group, leftFunc, rightFunc, genericFunc)
    if type(leftFunc) == "function" and type(rightFunc) == "function" then
        if leftFunc() and not rightFunc() then return "L" .. group end
        if rightFunc() and not leftFunc() then return "R" .. group end
    end
    if type(genericFunc) == "function" and genericFunc() then return group end
end
local function currentModifiers()
    local result = {}
    local alt = modifierPart("ALT", IsLeftAltKeyDown, IsRightAltKeyDown, IsAltKeyDown)
    local ctrl = modifierPart("CTRL", IsLeftControlKeyDown, IsRightControlKeyDown, IsControlKeyDown)
    local shift = modifierPart("SHIFT", IsLeftShiftKeyDown, IsRightShiftKeyDown, IsShiftKeyDown)
    if alt then result[#result + 1] = alt end
    if ctrl then result[#result + 1] = ctrl end
    if shift then result[#result + 1] = shift end
    return result
end
local function stopCapture()
    captureActive = false
    capture:EnableKeyboard(false)
    capture:Hide()
end
local function commitCapture(key)
    if not captureActive or not key then return end
    local token = tostring(key):upper()
    if token == "ESCAPE" then stopCapture() return end
    if modifierKeyNames[token] then return end
    if token == "UNKNOWN" then return end
    if not token:match("^BUTTON%d+$") and not token:match("^MOUSEWHEEL")
       and not token:match("^MOUSEBUTTON%d+$") and token:match("^[A-Z0-9_]+$") then
        local pieces = currentModifiers()
        pieces[#pieces + 1] = token
        local binding = table.concat(pieces, "-")
        stopCapture()
        keyEdit:SetText(binding)
        dispatch("bind " .. binding)
    end
end
capture:SetScript("OnKeyDown", function(self, key)
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
    commitCapture(key)
end)
local captureBtn = button("Capture key", 230, -147, 90, function()
    if InCombatLockdown and InCombatLockdown() then return end
    keyEdit:ClearFocus()
    captureActive = true
    capture:Show()
    capture:EnableKeyboard(true)
end)


local function makeCheckbox(text, y, onClick)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y)
    local caption = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    caption:SetPoint("LEFT", cb, "RIGHT", 5, 0)
    caption:SetText(text)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return cb
end
local fast = makeCheckbox("Fast Loot (fishing catches only)", -221, function(on)
    dispatch("fastloot " .. (on and "on" or "off"))
end)
local fastNote = label(panel, "Collect fish on LOOT_READY; ready to cast again on your next keypress.", panel, 55, -249, "GameFontDisableSmall")
local auto = makeCheckbox("WoW Auto Loot (global setting)", -285, function(on)
    dispatch("autoloot " .. (on and "on" or "off"))
end)
local autoNote = label(panel, "Required for Fast Loot. Also affects looting outside fishing.", panel, 55, -313, "GameFontDisableSmall")

local statusHeading = label(panel, "Current status", panel, 20, -362, "GameFontNormal")
local status = label(panel, "", panel, 22, -389, "GameFontHighlightSmall")
local refresh = button("Refresh binding", 20, -422, 145, function()
    dispatch("refresh")
    panel:Show()
end)
local hint = label(panel, "Other commands: /sfish status   /sfish options", panel, 20, -464, "GameFontDisableSmall")

sync = function()
    local db = SimplyFishingDB or {}
    keyEdit:SetText(db.key or "")
    fast:SetChecked(db.fastLoot ~= false)
    auto:SetChecked(GetCVar and GetCVar("autoLootDefault") == "1" or false)
    status:SetText("Assigned key: " .. tostring(db.key or "None") .. "     Fast Loot: " .. (db.fastLoot ~= false and "On" or "Off"))
    local locked = InCombatLockdown and InCombatLockdown()
    keyEdit:SetEnabled(not locked)
    applyBtn:SetEnabled(not locked)
    removeBtn:SetEnabled(not locked)
    refresh:SetEnabled(not locked)
    captureBtn:SetEnabled(not locked)
    if locked then stopCapture() end
end
panel:SetScript("OnShow", sync)
panel:SetScript("OnHide", stopCapture)
panel:RegisterEvent("PLAYER_REGEN_ENABLED")
panel:RegisterEvent("PLAYER_REGEN_DISABLED")
panel:SetScript("OnEvent", function(self) if self:IsShown() then sync() end end)

local function register()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, result = pcall(Settings.RegisterCanvasLayoutCategory, panel, PANEL_NAME)
        if ok and result then
            category = result
            Settings.RegisterAddOnCategory(category)
            return true
        end
    end
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        return true
    end
    return false
end
local registered = register()

function SimplyFishing_OpenOptions()
    if not registered then registered = register() end
    if Settings and Settings.OpenToCategory and category then
        local id = category.GetID and category:GetID() or category.ID or category
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    else
        print("|cff66ddffSimply Fishing|r: Settings API unavailable; use /sfish commands.")
    end
end

function SimplyFishing_OnCompartmentClick()
    SimplyFishing_OpenOptions()
end