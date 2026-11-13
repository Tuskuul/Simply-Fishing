-- Simply Fishing 1.1.0 (WoW Forever 1.60.1 / interface 16001)
local addonName = ...
local prefix = "|cff66ddffSimply Fishing|r: "
local function say(s) print(prefix .. tostring(s)) end
local fishingID = 7620
local owner, listener
local ready = false
local pending = false
local fishing = false
local poleEquipped = false
local mode = "unknown"
local appliedMode, appliedKey
-- Event-driven loot protection. No timer polls and no automatic casting.
local lootOpen = false
local lastFishingActivity = -1000
local FAST_LOOT_WINDOW = 3.0
local fastLootEnabled = true
local protectionUntil = 0
local protectionToken = 0
local LOOT_GRACE = 0.55
-- After a fast catch, the next *player* keypress can cast immediately.
-- This never casts fishing from a timer or event (protected action).
local fastCatchFinishedAt = -1000
local function now() return GetTime and GetTime() or 0 end
-- Fast-loot only a recent fishing catch, not ordinary corpses or containers.
local function isFishingCatch()
    if IsFishingLoot then
        local ok, value = pcall(IsFishingLoot)
        if ok and value == true then return true end
    end
    return now() - lastFishingActivity <= FAST_LOOT_WINDOW
end
local safeUpdate -- filled in below

local function protectFor(seconds)
    local deadline = now() + seconds
    if deadline > protectionUntil then protectionUntil = deadline end
    protectionToken = protectionToken + 1
    local token = protectionToken
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds + 0.03, function()
            if token == protectionToken and safeUpdate then safeUpdate() end
        end)
    end
end
local cvars = nil
local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function fishName()
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(fishingID)
    end
    if GetSpellInfo then return GetSpellInfo(fishingID) end
end
local function isFishing()
    if not UnitChannelInfo then return false end
    local name, _, _, _, _, _, _, id = UnitChannelInfo("player")
    return name and (id == fishingID or (fishName() and name == fishName())) or false
end
-- Fishing poles are weapon class 2, subclass 20. Check item type, not
-- an English item name, so named and localized fishing poles also work.
local function hasFishingPole()
    if not GetInventoryItemID then return false end
    local itemID = GetInventoryItemID("player", 16) -- main-hand equipment slot
    if not itemID then return false end
    local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if info then
        local _, _, _, _, _, classID, subClassID = info(itemID)
        if classID ~= nil then return classID == 2 and subClassID == 20 end
    end
    if GetItemInfo then
        local _, _, _, _, _, _, _, _, _, _, _, classID, subClassID = GetItemInfo(itemID)
        if classID ~= nil then return classID == 2 and subClassID == 20 end
    end
    -- Fail safe: do not hijack F for fishing if the item is unrecognized.
    return false
end
local function setInteraction(active)
    if not GetCVar or not SetCVar or inCombat() then return end
    if active and not cvars then
        cvars = {}
        for _, name in ipairs({"SoftTargetInteract", "SoftTargetInteractRange"}) do
            local ok, value = pcall(GetCVar, name)
            if ok and value ~= nil then cvars[name] = value end
        end
        if cvars.SoftTargetInteract then pcall(SetCVar, "SoftTargetInteract", "3") end
        if cvars.SoftTargetInteractRange then pcall(SetCVar, "SoftTargetInteractRange", "30") end
    elseif not active and cvars then
        for name, value in pairs(cvars) do pcall(SetCVar, name, value) end
        cvars = nil
    end
end
local function update()
    if not ready then return end
    if inCombat() then pending = true return end
    pending = false
    fishing = not not isFishing()
    if fishing then lastFishingActivity = now() end
    poleEquipped = hasFishingPole()
    -- Out of combat: cast only with a fishing pole actually equipped.
    -- While channeling or holding an ordinary weapon, the assigned key means Interact.
    -- Keep the assigned key in Interact while the loot window is open or just closed.
    -- This prevents rapid key repeats from starting the next cast too soon.
    local waitingForLoot = lootOpen or (now() < protectionUntil and
        (not fastLootEnabled or fastCatchFinishedAt < lastFishingActivity))
    mode = (poleEquipped and not fishing and not waitingForLoot) and "cast" or "interact"
    local key = SimplyFishingDB and SimplyFishingDB.key
    -- Avoid rewriting protected keybindings every polling tick.
    if appliedMode == mode and appliedKey == key then return end
    setInteraction(mode == "interact")
    ClearOverrideBindings(owner)
    appliedMode, appliedKey = nil, nil
    if not key then
        appliedMode, appliedKey = mode, key
        setInteraction(false)
        return
    end
    if mode == "interact" then
        SetOverrideBinding(owner, true, key, "INTERACTTARGET")
    else
        local name = fishName()
        if not name or name == "" then
            say("Fishing spell name unavailable; try /sfish refresh.")
            return
        end
        SetOverrideBindingSpell(owner, true, key, name)
    end
    appliedMode, appliedKey = mode, key
end
safeUpdate = function()
    local ok, err = pcall(update)
    if not ok then
        say("Binding error: " .. tostring(err))
        return false
    end
    return true
end

-- Inspect the active override after binding. This verifies registration,
-- not whether a particular physical device sends the expected button code.
local function verifyBinding(key)
    if not ready then return nil, "The addon has not initialized." end
    if inCombat() then return nil, "Binding verification waits until combat ends." end
    if not GetBindingAction then return nil, "This client does not expose binding lookup." end
    local ok, action = pcall(GetBindingAction, key, true)
    if not ok then return nil, "Binding lookup failed." end
    local expected = (mode == "interact") and "INTERACTTARGET" or ("SPELL " .. tostring(fishName() or ""))
    if action == expected then return true, action end
    return false, "Expected " .. expected .. ", got " .. tostring(action)
end
-- Normalize an ordinary key or a side-specific modifier chord to a WoW binding.
-- Examples: F, CTRL-F, LCTRL-F, RSHIFT-ALT-F, LALT-RCTRL-F.
local allowedModifiers = {
    ALT = "ALT", LALT = "ALT", RALT = "ALT",
    CTRL = "CTRL", LCTRL = "CTRL", RCTRL = "CTRL",
    SHIFT = "SHIFT", LSHIFT = "SHIFT", RSHIFT = "SHIFT",
}
-- Mouse buttons/wheel are deliberately unsupported for this release.
-- Retain all keyboard and native controller binding tokens.
local function isMouseBinding(key)
    return key:match("^BUTTON%d+$") ~= nil
        or key:match("^MOUSEWHEEL") ~= nil
        or key:match("^MOUSEBUTTON%d+$") ~= nil
end
local function normalizeBinding(text)
    local input = (text or ""):upper():gsub("%s+", "")
    if input == "" or input:find("[^A-Z0-9%-]") then
        return nil, "Enter a key such as RCTRL-PAD1, LSHIFT-SPACE, or ALT-SPACE."
    end
    -- A binding uses single hyphens between modifier tokens and the key.
    -- Reject malformed separators without confusing CTRL-F with CTRL--F.
    if input:sub(1, 1) == "-" or input:sub(-1) == "-" or input:find("--", 1, true) then
        return nil, "Empty key component in binding."
    end
    local tokens = {}
    for token in input:gmatch("[^-]+") do
        tokens[#tokens + 1] = token
    end
    local key = tokens[#tokens]
    -- Keep native keyboard/gamepad key names while rejecting mouse bindings.
    if not key:match("^[A-Z0-9_]+$") or allowedModifiers[key] then
        return nil, "Enter a keyboard or controller key after modifiers."
    end
    if isMouseBinding(key) then
        return nil, "Mouse buttons and wheel are disabled in this release. Use a keyboard or controller key."
    end
    local mods = {}
    for i = 1, #tokens - 1 do
        local token = tokens[i]
        local group = allowedModifiers[token]
        if not group then return nil, "Unknown modifier: " .. token end
        if mods[group] then return nil, "Use only one " .. group .. " modifier per binding." end
        mods[group] = token
    end
    local parts = {}
    for _, group in ipairs({"ALT", "CTRL", "SHIFT"}) do
        if mods[group] then parts[#parts + 1] = mods[group] end
    end
    parts[#parts + 1] = key
    return table.concat(parts, "-")
end

-- Register chat command FIRST. Even if later setup fails, /sfish remains usable.
SLASH_SIMPLYFISHING1 = "/sfish"
SLASH_SIMPLYFISHING2 = "/simplyfishing"
SlashCmdList.SIMPLYFISHING = function(text)
    local cmd, arg = (text or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "bind" then
        if not arg or arg == "" then
            say("Use /sfish bind KEY, e.g. LCTRL-PAD1, RALT-SPACE, or SHIFT-SPACE.")
            return
        end
        if inCombat() then say("Change your fishing key outside combat.") return end
        local key, issue = normalizeBinding(arg)
        if not key then say("Invalid binding: " .. issue) return end
        SimplyFishingDB = SimplyFishingDB or {}
        SimplyFishingDB.key = key
        appliedMode, appliedKey = nil, nil
        if not safeUpdate() then
            say("Key stored, but the binding could not be applied. Run /sfish debug.")
            return
        end
        local verified, detail = verifyBinding(key)
        if verified == true then
            say("Key assigned: " .. key .. " (" .. mode .. " mode).")
        elseif verified == false then
            say("Key stored: " .. key .. ". Binding verification failed: " .. detail .. ". Run /sfish debug.")
        else
            say("Key stored: " .. key .. ". " .. detail)
        end
    elseif cmd == "unbind" or cmd == "off" then
        if inCombat() then say("Unbind outside combat.") return end
        SimplyFishingDB = SimplyFishingDB or {}
        SimplyFishingDB.key = nil
        safeUpdate()
        say("Fishing key removed.")
    elseif cmd == "debug" then
        safeUpdate()
        local key = SimplyFishingDB and SimplyFishingDB.key
        say("v1.1.0 | ready=" .. tostring(ready) .. " | channeling=" .. tostring(isFishing()))
        local itemID = GetInventoryItemID and GetInventoryItemID("player", 16)
        local classID, subclassID = "?", "?"
        local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if itemID and info then
            local _, _, _, _, _, c, s = info(itemID)
            classID, subclassID = tostring(c), tostring(s)
        end
        say("mainhand=" .. tostring(itemID) .. " | class=" .. tostring(classID) .. "/" .. tostring(subclassID))
        say("poleEquipped=" .. tostring(hasFishingPole()) .. " | mode=" .. mode .. " | combat=" .. tostring(inCombat()))
        say("key=" .. tostring(key) .. " | spellID=" .. tostring(fishingID) .. " | spellName=" .. tostring(fishName()))
        if key and GetBindingAction then
            local ok1, action = pcall(GetBindingAction, key, true)
            say("effective binding=" .. (ok1 and tostring(action) or "lookup failed"))
        end
        say("lootOpen=" .. tostring(lootOpen) .. " | graceRemaining=" .. string.format("%.2f", math.max(0, protectionUntil-now())) .. "s" .. " | fastReady=" .. tostring(fastLootEnabled and fastCatchFinishedAt >= 0 and now()-fastCatchFinishedAt < 1))
        say("autoLootDefault=" .. tostring(GetCVar and GetCVar("autoLootDefault") or "unknown") .. " | fastLoot=" .. tostring(fastLootEnabled))
        say("cast method=SetOverrideBindingSpell (localized name)")
    elseif cmd == "fastloot" then
        local value = (arg or ""):lower()
        if value == "on" or value == "off" then
            SimplyFishingDB = SimplyFishingDB or {}
            SimplyFishingDB.fastLoot = value == "on"
            fastLootEnabled = SimplyFishingDB.fastLoot
            -- Updating the toggle does not issue a cast; it only rebinds the selected key.
            if fastLootEnabled and not lootOpen then
                protectionUntil = 0
                protectionToken = protectionToken + 1
            end
            safeUpdate()
            say("Fast fishing loot " .. value .. (fastLootEnabled and ": next assigned-key press recasts as soon as the catch is collected." or ": normal loot-window/recast handling."))
        else
            say("Use /sfish fastloot on or /sfish fastloot off.")
        end
    elseif cmd == "autoloot" then
        -- Explicit opt-in: changes WoW's native, global Auto Loot setting.
        local value = (arg or ""):lower()
        if value == "on" or value == "off" then
            if SetCVar then
                local ok, err = pcall(SetCVar, "autoLootDefault", value == "on" and "1" or "0")
                if ok then
                    say("WoW Auto Loot is now " .. value .. " (global setting, also applies outside fishing).")
                else
                    say("Could not update Auto Loot: " .. tostring(err))
                end
            else
                say("This client does not expose SetCVar; enable Auto Loot in game settings.")
            end
        else
            say("Use /sfish autoloot on or /sfish autoloot off (changes WoW's global Auto Loot setting).")
        end
    elseif cmd == "options" or cmd == "settings" then
        if SimplyFishing_OpenOptions then
            SimplyFishing_OpenOptions()
        else
            say("Options panel is not ready yet. Try again after logging in.")
        end
    elseif cmd == "refresh" then
        appliedMode, appliedKey = nil, nil
        safeUpdate()
        say("Binding refreshed.")
    elseif cmd == "" or cmd == "status" then
        say("v1.1.0 | initialized: " .. tostring(ready) .. " | key: " .. tostring(SimplyFishingDB and SimplyFishingDB.key or "none"))
        say("/sfish options | /sfish bind F | /sfish fastloot on/off")
    else
        say("Commands: options, bind KEY, fastloot on/off, autoloot on/off, unbind, status, debug, refresh")
    end
end
local function initialize()
    owner = CreateFrame("Frame", "SimplyFishingBindings", UIParent)
    listener = CreateFrame("Frame")
    fastLootEnabled = SimplyFishingDB == nil or SimplyFishingDB.fastLoot ~= false
    if SimplyFishingDB and type(SimplyFishingDB.key) == "string" then
        local valid = normalizeBinding(SimplyFishingDB.key)
        if not valid then
            SimplyFishingDB.key = nil
            say("Previous binding is no longer supported. Assign a keyboard or controller key in settings.")
        end
    end
    for _, evt in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_INTERRUPTED", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED"}) do
        listener:RegisterEvent(evt)
    end
    listener:SetScript("OnEvent", function(_, evt, unit, arg2)
        if evt == "PLAYER_REGEN_ENABLED" then
            if pending then safeUpdate() end
        elseif evt == "PLAYER_ENTERING_WORLD" then
            lootOpen = false
            protectionUntil = 0
            fastCatchFinishedAt = -1000
            safeUpdate()
        elseif evt == "LOOT_READY" then
            -- LOOT_READY fires before the loot window appears. The slots are
            -- already available, so collect them now instead of waiting.
            -- Respect native Auto Loot and the user's modifier-key override.
            if hasFishingPole() and isFishingCatch() then
                lootOpen = true
                protectFor(LOOT_GRACE)
                safeUpdate()
                local nativeAuto = GetCVar and GetCVar("autoLootDefault") == "1"
                local modifier = IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE")
                if fastLootEnabled and nativeAuto and not modifier and GetNumLootItems and LootSlot then
                    local n = GetNumLootItems()
                    for i = n, 1, -1 do
                        -- Locked loot and rolls are left to the default UI.
                        local locked = false
                        if GetLootSlotInfo then
                            local _, _, _, _, _, isLocked = GetLootSlotInfo(i)
                            locked = isLocked
                        end
                        if not locked then pcall(LootSlot, i) end
                    end
                end
            end
        elseif evt == "LOOT_OPENED" then
            if hasFishingPole() and isFishingCatch() then
                lootOpen = true
                protectFor(LOOT_GRACE)
                safeUpdate()
            end
        elseif evt == "LOOT_CLOSED" then
            if lootOpen then
                lootOpen = false
                if fastLootEnabled then
                    -- Fast mode: loot is gone; no artificial recast delay.
                    -- A NEW assigned-key press is still required to cast.
                    protectionUntil = 0
                    protectionToken = protectionToken + 1
                    fastCatchFinishedAt = now()
                else
                    -- Normal mode: let Blizzard's loot window settle.
                    protectFor(LOOT_GRACE)
                end
                safeUpdate()
            end
        elseif evt == "PLAYER_EQUIPMENT_CHANGED" then
            -- First event argument is the slot ID. Main hand = 16.
            if unit == 16 then safeUpdate() end
        elseif evt == "UNIT_INVENTORY_CHANGED" then
            -- Some client variants notify unit inventory instead of equipment.
            -- Event-driven fallback: no per-frame or timed polling.
            if unit == "player" then safeUpdate() end
        elseif unit == "player" then
            -- Channel completion may precede the fishing loot window opening.
            -- Hold Interact during that brief gap; never cast automatically.
            if evt == "UNIT_SPELLCAST_CHANNEL_START" then
                fastCatchFinishedAt = -1000
            elseif evt == "UNIT_SPELLCAST_CHANNEL_STOP" or evt == "UNIT_SPELLCAST_INTERRUPTED" then
                if fishing or isFishing() then
                    lastFishingActivity = now()
                    -- In fast mode, don't add a delay *after* LOOT_CLOSED.
                    if not (fastLootEnabled and now() - fastCatchFinishedAt < 1.0) then
                        protectFor(LOOT_GRACE)
                    end
                end
            end
            safeUpdate()
        end
    end)
    ready = true
    safeUpdate()
end
local ok, err = pcall(initialize)
if not ok then
    say("Startup error: " .. tostring(err))
end