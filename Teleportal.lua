--[[
    Teleportal - Portals and teleports from spellbook in two columns.
    Author: Codermik
    License: All rights reserved.
]]

local ADDON_NAME = "Teleportal"
local ADDON_VERSION = "1.1.130726"
local BOOKTYPE = (BOOKTYPE_SPELL ~= nil) and BOOKTYPE_SPELL or "spell"
local isRetail = (WOW_PROJECT_MAINLINE and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

-- Saved position for toggle button (persists across sessions)
if not TeleportalDB then
    TeleportalDB = {}
end

-- Paired rows: { teleport = spellInfo|nil, portal = spellInfo|nil }
-- spellInfo = { name = localizedName, spellID = id }
local spellRows = {}

-- Rune reagent item IDs (mage)
local RUNE_TELEPORT_ITEM_ID = 17031
local RUNE_PORTAL_ITEM_ID = 17032

-- { teleportID, portalID } — portalID may be nil for teleport-only spells
local TELEPORT_PORTAL_PAIRS = {
    -- Classic / Era / Anniversary
    { 3561, 10059 },   -- Stormwind
    { 3562, 11416 },   -- Ironforge
    { 3565, 11419 },   -- Darnassus
    { 3567, 11417 },   -- Orgrimmar
    { 3563, 11418 },   -- Undercity
    { 3566, 11420 },   -- Thunder Bluff
    -- TBC
    { 32271, 32266 },  -- Exodar
    { 32272, 32267 },  -- Silvermoon
    { 33690, 33691 },  -- Shattrath (Alliance)
    { 35715, 35717 },  -- Shattrath (Horde)
    -- Wrath
    { 49359, 49360 },  -- Theramore
    { 49358, 49361 },  -- Stonard
    { 53140, 53142 },  -- Dalaran (Northrend)
    -- Cataclysm
    { 88342, 88345 },  -- Tol Barad (Alliance)
    { 88344, 88346 },  -- Tol Barad (Horde)
    -- MoP
    { 132621, 132620 }, -- Vale of Eternal Blossoms (Alliance)
    { 132627, 132626 }, -- Vale of Eternal Blossoms (Horde)
    -- WoD
    { 176248, 176246 }, -- Stormshield
    { 176242, 176244 }, -- Warspear
    -- Legion
    { 224869, 224871 }, -- Dalaran (Broken Isles)
    { 120145, 120146 }, -- Ancient Teleport/Portal: Dalaran
    { 193759, nil },    -- Hall of the Guardian
    -- BfA
    { 281403, 281400 }, -- Boralus
    { 281404, 281402 }, -- Dazar'alor
    -- Shadowlands
    { 344587, 344597 }, -- Oribos
    -- Dragonflight
    { 395277, 395289 }, -- Valdrakken
    -- The War Within
    { 446540, 446534 }, -- Dornogal
}

-- Rune reagent item IDs (mage)
local RUNE_TELEPORT_ITEM_ID = 17031
local RUNE_PORTAL_ITEM_ID = 17032

-- UI references
local toggleButton
local mainPanel
local teleportContent
local portalContent
local teleportRuneHeader
local portalRuneHeader
local teleportRuneIconRef
local portalRuneIconRef
local teleportRuneCountText
local portalRuneCountText
local teleportButtons = {}
local portalButtons = {}
local teleportButtonPool = {}
local portalButtonPool = {}
local teleportBlankPool = {}
local portalBlankPool = {}
local teleportPlaceholders = {}
local portalPlaceholders = {}

-- Spell IDs that should auto-close the panel when cast completes (teleports + portals)
local closeOnCastSpellIDs = {}

local BUTTON_SIZE = 32
local BUTTON_PADDING = 1
local COLUMN_WIDTH = 32
local PANEL_PADDING = 1

local COLUMN_GAP = 1
local PANEL_TOP_INSET = 1
local PANEL_BOTTOM_INSET = 1

-- Content height = one header row + N spell rows (Classic); N spell rows only (Retail)
local function GetContentHeightForButtonCount(count)
    local rows = isRetail and count or (1 + count)
    return math.max(0, rows * (BUTTON_SIZE + BUTTON_PADDING) - BUTTON_PADDING)
end

local function UpdatePanelHeight()
    if not mainPanel or not teleportContent then return end
    local rowCount = #spellRows
    local contentHeight = GetContentHeightForButtonCount(rowCount)
    local panelHeight = PANEL_TOP_INSET + contentHeight + PANEL_BOTTOM_INSET
    mainPanel:SetHeight(panelHeight)
    teleportContent:SetHeight(contentHeight)
    portalContent:SetHeight(contentHeight)
end

-- ---------------------------------------------------------------------------
-- Spell discovery (spell IDs + localized name fallback)
-- ---------------------------------------------------------------------------

local function PlayerKnowsSpell(spellID)
    if not spellID then return false end
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
        local ok, result = pcall(C_SpellBook.IsSpellInSpellBook, spellID)
        if ok and result then return true end
    end
    if IsPlayerSpell and IsPlayerSpell(spellID) then
        return true
    end
    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellID) then
        return true
    end
    if IsSpellKnown and IsSpellKnown(spellID) then
        return true
    end
    return false
end

local function GetSpellNameByID(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    local name = GetSpellInfo(spellID)
    return name
end

local function MakeSpellInfo(spellID)
    if not spellID then return nil end
    local name = GetSpellNameByID(spellID)
    if not name or name == "" then return nil end
    return { name = name, spellID = spellID }
end

local function GetLocaleSpellPatterns()
    if TeleportalSpellPatterns then
        return TeleportalSpellPatterns()
    end
    return nil
end

local function ClassifySpellName(name, patterns)
    if not name or not patterns then return nil end
    -- Check portal before teleport so locale prefixes that share a root still classify correctly
    if patterns.portal and name:match(patterns.portal) then
        return "portal"
    end
    if patterns.teleport and name:match(patterns.teleport) then
        return "teleport"
    end
    return nil
end

local function GetDestination(spellName, kind)
    if not spellName then return nil end
    local patterns = GetLocaleSpellPatterns()
    if kind == "portal" then
        return spellName:match(patterns.portalDest)
    end
    if kind == "teleport" then
        return spellName:match(patterns.teleDest)
    end
    return spellName:match(patterns.teleDest) or spellName:match(patterns.portalDest)
end

local function ScanSpellbookByLocalizedNames(seenIDs)
    local patterns = GetLocaleSpellPatterns()
    local foundTeleports = {}
    local foundPortals = {}

    local function consider(name, spellID)
        if not name or not spellID or seenIDs[spellID] then return end
        if C_Spell and C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(spellID) then return end
        local kind = ClassifySpellName(name, patterns)
        if kind == "teleport" then
            tinsert(foundTeleports, { name = name, spellID = spellID })
            seenIDs[spellID] = true
        elseif kind == "portal" then
            tinsert(foundPortals, { name = name, spellID = spellID })
            seenIDs[spellID] = true
        end
    end

    if isRetail and C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local spellBank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
        local flyoutType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout or 4
        local numLines = C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetNumSpellBookSkillLines() or 0
        for lineIndex = 1, numLines do
            local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
            if skillLineInfo then
                local offset, numSlots = skillLineInfo.itemIndexOffset or 0, skillLineInfo.numSpellBookItems or 0
                for j = offset + 1, offset + numSlots do
                    local info = C_SpellBook.GetSpellBookItemInfo(j, spellBank)
                    if not info then break end
                    if info.itemType == spellType and info.name and not info.isPassive then
                        consider(info.name, info.spellID or info.actionID)
                    elseif info.itemType == flyoutType and info.actionID and GetFlyoutInfo and GetFlyoutSlotInfo then
                        local flyoutID = info.actionID
                        local _, _, flyoutNumSlots = GetFlyoutInfo(flyoutID)
                        if flyoutNumSlots and flyoutNumSlots > 0 then
                            for slot = 1, flyoutNumSlots do
                                local slotSpellID, overrideSpellID, isKnown, spellName = GetFlyoutSlotInfo(flyoutID, slot)
                                if isKnown and spellName and (slotSpellID or overrideSpellID) then
                                    consider(spellName, overrideSpellID or slotSpellID)
                                end
                            end
                        end
                    end
                end
            end
        end
    else
        local i = 1
        while true do
            local name = GetSpellBookItemName(i, BOOKTYPE)
            if not name then break end
            local skillType, spellID = GetSpellBookItemInfo(i, BOOKTYPE)
            if skillType == "SPELL" and spellID then
                local passive = (IsPassiveSpell and IsPassiveSpell(i, BOOKTYPE))
                if not passive then
                    consider(name, spellID)
                end
            end
            i = i + 1
        end
    end

    -- Pair leftover teleports/portals by localized destination
    local portalByDest = {}
    for _, portalInfo in ipairs(foundPortals) do
        local dest = GetDestination(portalInfo.name, "portal")
        if dest and not portalByDest[dest] then
            portalByDest[dest] = portalInfo
        end
    end

    local usedPortals = {}
    for _, teleInfo in ipairs(foundTeleports) do
        local dest = GetDestination(teleInfo.name, "teleport")
        local portalInfo = dest and portalByDest[dest] or nil
        if portalInfo then
            usedPortals[portalInfo.spellID] = true
        end
        tinsert(spellRows, { teleport = teleInfo, portal = portalInfo })
    end

    for _, portalInfo in ipairs(foundPortals) do
        if not usedPortals[portalInfo.spellID] then
            tinsert(spellRows, { teleport = nil, portal = portalInfo })
        end
    end
end

local function ScanSpellbook()
    spellRows = {}
    local seenIDs = {}

    for _, pair in ipairs(TELEPORT_PORTAL_PAIRS) do
        local teleID, portalID = pair[1], pair[2]
        local teleKnown = PlayerKnowsSpell(teleID)
        local portalKnown = portalID and PlayerKnowsSpell(portalID)
        if teleKnown or portalKnown then
            local teleInfo = teleKnown and MakeSpellInfo(teleID) or nil
            local portalInfo = portalKnown and MakeSpellInfo(portalID) or nil
            if teleInfo or portalInfo then
                tinsert(spellRows, { teleport = teleInfo, portal = portalInfo })
                if teleInfo then seenIDs[teleID] = true end
                if portalInfo and portalID then seenIDs[portalID] = true end
            end
        end
    end

    -- Catch any mage teleports/portals missing from the ID table (localized names)
    ScanSpellbookByLocalizedNames(seenIDs)
end

-- ---------------------------------------------------------------------------
-- Rebuild spell buttons in both columns
-- ---------------------------------------------------------------------------

local function GetOrCreateSpellButton(parent, pool, spellInfo, index)
    local btn = tremove(pool)
    if not btn then
        btn = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
        btn:SetHeight(BUTTON_SIZE)
        btn:SetWidth(BUTTON_SIZE)
        btn:RegisterForClicks("LeftButtonUp")
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        icon:SetPoint("CENTER", 0, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon = icon
        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(btn)
        highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        highlight:SetBlendMode("ADD")
        highlight:SetAlpha(0.5)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetSpellByID then
                GameTooltip:SetSpellByID(self.spellID)
            else
                GameTooltip:SetText(self.spellName or "")
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    btn.spellID = spellInfo.spellID
    btn.spellName = spellInfo.name
    btn:SetParent(parent)
    btn:ClearAllPoints()
    -- Classic: first spell below header (index 1 at -1 row). Retail: first spell at top (index 1 at 0).
    local rowOffset = isRetail and (index - 1) or index
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -rowOffset * (BUTTON_SIZE + BUTTON_PADDING))
    btn:SetAttribute("type", "spell")
    -- Prefer spell ID so casting works regardless of client language
    btn:SetAttribute("spell", spellInfo.spellID or spellInfo.name)
    local tex
    if isRetail and C_Spell and C_Spell.GetSpellTexture then
        tex = C_Spell.GetSpellTexture(spellInfo.spellID)
    else
        tex = GetSpellTexture(spellInfo.spellID) or GetSpellTexture(spellInfo.name)
    end
    if tex then
        btn.icon:SetTexture(tex)
    end
    btn:Show()
    return btn
end

-- Blank placeholder to keep column rows aligned when one side has no spell at that row
local function GetOrCreateBlankPlaceholder(parent, pool, index)
    local ph = tremove(pool)
    if not ph then
        ph = CreateFrame("Frame", nil, parent)
        ph:SetHeight(BUTTON_SIZE)
        ph:SetWidth(BUTTON_SIZE)
    end
    ph:SetParent(parent)
    ph:ClearAllPoints()
    local rowOffset = isRetail and (index - 1) or index
    ph:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -rowOffset * (BUTTON_SIZE + BUTTON_PADDING))
    ph:Show()
    return ph
end

local pendingSpellRebuild = false
local pendingPanelHide = false

local function RebuildSpellLists()
    if InCombatLockdown() then
        pendingSpellRebuild = true
        return
    end

    local rowCount = #spellRows

    -- Return current buttons to spell pools and placeholders to blank pools
    for _, b in ipairs(teleportButtons) do
        b:Hide()
        b:ClearAllPoints()
        tinsert(teleportButtonPool, b)
    end
    teleportButtons = {}
    for _, ph in ipairs(teleportPlaceholders) do
        ph:Hide()
        ph:ClearAllPoints()
        tinsert(teleportBlankPool, ph)
    end
    teleportPlaceholders = {}
    for _, b in ipairs(portalButtons) do
        b:Hide()
        b:ClearAllPoints()
        tinsert(portalButtonPool, b)
    end
    portalButtons = {}
    for _, ph in ipairs(portalPlaceholders) do
        ph:Hide()
        ph:ClearAllPoints()
        tinsert(portalBlankPool, ph)
    end
    portalPlaceholders = {}

    closeOnCastSpellIDs = {}

    for row = 1, rowCount do
        local rowInfo = spellRows[row]
        local teleInfo = rowInfo.teleport
        local portalInfo = rowInfo.portal

        if teleInfo then
            local btn = GetOrCreateSpellButton(teleportContent, teleportButtonPool, teleInfo, row)
            tinsert(teleportButtons, btn)
            if teleInfo.spellID then closeOnCastSpellIDs[teleInfo.spellID] = true end
        else
            local ph = GetOrCreateBlankPlaceholder(teleportContent, teleportBlankPool, row)
            tinsert(teleportPlaceholders, ph)
        end

        if portalInfo then
            local pbtn = GetOrCreateSpellButton(portalContent, portalButtonPool, portalInfo, row)
            tinsert(portalButtons, pbtn)
            if portalInfo.spellID then closeOnCastSpellIDs[portalInfo.spellID] = true end
        else
            local ph = GetOrCreateBlankPlaceholder(portalContent, portalBlankPool, row)
            tinsert(portalPlaceholders, ph)
        end
    end

    UpdatePanelHeight()
end

local function ScanAndRebuild()
    ScanSpellbook()
    RebuildSpellLists()
end

-- ---------------------------------------------------------------------------
-- Main panel (two columns)
-- ---------------------------------------------------------------------------

local PANEL_WIDTH = PANEL_PADDING * 2 + COLUMN_WIDTH * 2 + COLUMN_GAP

local ANIM_DURATION_IN = 0.22
local ANIM_DURATION_OUT = 0.18
local ANIM_START_SCALE = 0.05
local ANIM_OVERSHOOT_SCALE = 1.12
local animatorRunning = false
local animatorStartTime = 0
local animatorDirection = nil
local animatorFrame = nil
local actionButtonUseKeyDownRestore = false

local function StopPanelAnimator()
    animatorRunning = false
    if animatorFrame then
        animatorFrame:SetScript("OnUpdate", nil)
    end
end

local function RunPanelAnimator()
    if not mainPanel then return end
    local now = GetTime()
    local elapsed = now - animatorStartTime
    local duration = (animatorDirection == "in") and ANIM_DURATION_IN or ANIM_DURATION_OUT

    if elapsed >= duration then
        mainPanel:SetScale(animatorDirection == "in" and 1 or ANIM_START_SCALE)
        if animatorDirection == "out" then
            if actionButtonUseKeyDownRestore then
                SetCVar("ActionButtonUseKeyDown", "1")
                actionButtonUseKeyDownRestore = false
            end
            if not InCombatLockdown() then
                mainPanel:Hide()
                mainPanel:SetScale(1)
            else
                pendingPanelHide = true
            end
        end
        StopPanelAnimator()
        return
    end

    local t = elapsed / duration
    local scale
    if animatorDirection == "in" then
       if t < 0.7 then
            local s = t / 0.7
            scale = ANIM_START_SCALE + (ANIM_OVERSHOOT_SCALE - ANIM_START_SCALE) * (1 - (1 - s) * (1 - s))
        else
            local s = (t - 0.7) / 0.3
            scale = ANIM_OVERSHOOT_SCALE + (1 - ANIM_OVERSHOOT_SCALE) * s
        end
    else
        scale = 1 + (ANIM_START_SCALE - 1) * t
    end
    mainPanel:SetScale(scale)
end

-- Panel bottom stays this many pixels above the toggle button's top (from toggle center: center + 28)
local PANEL_ABOVE_BUTTON_OFFSET = 28
-- Vertical offset from toggle BOTTOM to panel BOTTOM so panel sits above buttons
local PANEL_BOTTOM_OFFSET = (BUTTON_SIZE / 2) + PANEL_ABOVE_BUTTON_OFFSET

local function UpdateRuneHeader()
    if isRetail then return end
    local teleCount = GetItemCount(RUNE_TELEPORT_ITEM_ID) or 0
    local portalCount = GetItemCount(RUNE_PORTAL_ITEM_ID) or 0
    if teleportRuneCountText and portalRuneCountText then
        teleportRuneCountText:SetText(tostring(teleCount))
        portalRuneCountText:SetText(tostring(portalCount))
    end
    if teleportRuneIconRef then
        local tex = GetItemIcon(RUNE_TELEPORT_ITEM_ID)
        if tex then teleportRuneIconRef:SetTexture(tex) end
    end
    if portalRuneIconRef then
        local tex = GetItemIcon(RUNE_PORTAL_ITEM_ID)
        if tex then portalRuneIconRef:SetTexture(tex) end
    end
    if toggleButton and toggleButton.runeCountText then
        toggleButton.runeCountText:SetText(teleCount .. " / " .. portalCount)
    end
end

local function AnimatePanelOpen()
    if not mainPanel or not toggleButton then return end
    if InCombatLockdown() then return end
    StopPanelAnimator()
    -- If ActionButtonUseKeyDown is 1, set to 0 so click works; remember to restore when we close
    if GetCVar("ActionButtonUseKeyDown") == "1" then
        SetCVar("ActionButtonUseKeyDown", "0")
        actionButtonUseKeyDownRestore = true
    else
        actionButtonUseKeyDownRestore = false
    end
    mainPanel:ClearAllPoints()
    mainPanel:SetPoint("BOTTOM", toggleButton, "BOTTOM", 0, PANEL_BOTTOM_OFFSET)
    mainPanel:SetScale(ANIM_START_SCALE)
    mainPanel:Show()
    ScanAndRebuild()
    UpdateRuneHeader()
    animatorDirection = "in"
    animatorStartTime = GetTime()
    animatorRunning = true
    if not animatorFrame then
        animatorFrame = CreateFrame("Frame")
    end
    animatorFrame:SetScript("OnUpdate", RunPanelAnimator)
end

local function AnimatePanelClose()
    if not mainPanel or not mainPanel:IsShown() or not toggleButton then return end
    if InCombatLockdown() then
        pendingPanelHide = true
        return
    end
    StopPanelAnimator()
    mainPanel:ClearAllPoints()
    mainPanel:SetPoint("BOTTOM", toggleButton, "BOTTOM", 0, PANEL_BOTTOM_OFFSET)
    animatorDirection = "out"
    animatorStartTime = GetTime()
    animatorRunning = true
    if not animatorFrame then
        animatorFrame = CreateFrame("Frame")
    end
    animatorFrame:SetScript("OnUpdate", RunPanelAnimator)
end

local function ToggleTeleportalPanel()
    if not mainPanel then return end
    if mainPanel:IsShown() then
        AnimatePanelClose()
    else
        AnimatePanelOpen()
    end
end

local function CreateMainPanel()
    local panel = CreateFrame("Frame", "TeleportalPanel", UIParent)
    panel:SetSize(PANEL_WIDTH, 100)
    panel:SetPoint("CENTER", 0, 0)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:SetFrameStrata("DIALOG")
    panel:Hide()
    panel:EnableMouse(false)

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(panel)
    bg:SetColorTexture(0.1, 0.1, 0.15, 0.95)
    local edge = panel:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(panel)
    edge:SetColorTexture(0.4, 0.4, 0.5, 1)

    local drag = CreateFrame("Frame", nil, panel)
    drag:SetPoint("TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    drag:SetHeight(PANEL_TOP_INSET)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() panel:StartMoving() end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)

    local contentY = -PANEL_TOP_INSET

    local portalX = PANEL_PADDING + COLUMN_WIDTH + COLUMN_GAP
    local teleportX = portalX - COLUMN_GAP - COLUMN_WIDTH

    local teleportChild = CreateFrame("Frame", nil, panel)
    teleportChild:SetSize(COLUMN_WIDTH, 0)
    teleportChild:SetPoint("TOPLEFT", teleportX, contentY)
    teleportChild:SetFrameLevel(panel:GetFrameLevel() + 10)
    teleportChild:EnableMouse(false)

    if not isRetail then
        -- Left column: rune of teleportation header (icon + count)
        local teleportRuneFrame = CreateFrame("Frame", nil, teleportChild)
        teleportRuneFrame:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        teleportRuneFrame:SetPoint("TOPLEFT", teleportChild, "TOPLEFT", 0, 0)
        teleportRuneFrame:EnableMouse(true)
        teleportRuneFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText((TeleportalLocale and TeleportalLocale("RUNE_OF_TELEPORTATION_TOOLTIP")) or "Rune of Teleportation currently\nin your bags.")
            GameTooltip:Show()
        end)
        teleportRuneFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local teleportRuneIcon = teleportRuneFrame:CreateTexture(nil, "ARTWORK")
        teleportRuneIcon:SetAllPoints(teleportRuneFrame)
        teleportRuneIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        teleportRuneIcon:SetAlpha(0.5)
        local teleportRuneCount = teleportRuneFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        teleportRuneCount:SetPoint("CENTER", teleportRuneFrame, "CENTER", 0, 0)
        teleportRuneCount:SetJustifyH("CENTER")
        teleportRuneCount:SetJustifyV("MIDDLE")
        teleportRuneHeader = teleportRuneFrame
        teleportRuneIconRef = teleportRuneIcon
        teleportRuneCountText = teleportRuneCount
    end

    local portalChild = CreateFrame("Frame", nil, panel)
    portalChild:SetSize(COLUMN_WIDTH, 0)
    portalChild:SetPoint("TOPLEFT", portalX, contentY)
    portalChild:SetFrameLevel(panel:GetFrameLevel() + 10)
    portalChild:EnableMouse(false)

    if not isRetail then
        -- Right column: rune of portals header (icon + count)
        local portalRuneFrame = CreateFrame("Frame", nil, portalChild)
        portalRuneFrame:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        portalRuneFrame:SetPoint("TOPLEFT", portalChild, "TOPLEFT", 0, 0)
        portalRuneFrame:EnableMouse(true)
        portalRuneFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText((TeleportalLocale and TeleportalLocale("RUNE_OF_PORTALS_TOOLTIP")) or "Rune of Portals currently\nin your bags.")
            GameTooltip:Show()
        end)
        portalRuneFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local portalRuneIcon = portalRuneFrame:CreateTexture(nil, "ARTWORK")
        portalRuneIcon:SetAllPoints(portalRuneFrame)
        portalRuneIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        portalRuneIcon:SetAlpha(0.5)
        local portalRuneCount = portalRuneFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        portalRuneCount:SetPoint("CENTER", portalRuneFrame, "CENTER", 0, 0)
        portalRuneCount:SetJustifyH("CENTER")
        portalRuneCount:SetJustifyV("MIDDLE")
        portalRuneHeader = portalRuneFrame
        portalRuneIconRef = portalRuneIcon
        portalRuneCountText = portalRuneCount
    end

    mainPanel = panel
    teleportContent = teleportChild
    portalContent = portalChild

    return panel
end

-- ---------------------------------------------------------------------------
-- Toggle button
-- ---------------------------------------------------------------------------

local function SaveToggleButtonPosition(btn)
    local point, _, relativePoint, x, y = btn:GetPoint(1)
    if point and type(x) == "number" and type(y) == "number" then
        TeleportalDB.buttonPoint = point
        TeleportalDB.buttonRelativePoint = relativePoint or point
        TeleportalDB.buttonX = x
        TeleportalDB.buttonY = y
    end
end

local function ApplyToggleButtonLock()
    if not toggleButton then return end
    local locked = TeleportalDB.buttonLocked == true
    toggleButton:SetMovable(not locked)
end

local function ToggleButtonLock()
    TeleportalDB.buttonLocked = not (TeleportalDB.buttonLocked == true)
    ApplyToggleButtonLock()
    local cyan = "\124cFF00FFFF"
    local r = "\124r"
    local suffix
    if TeleportalDB.buttonLocked then
        suffix = (TeleportalLocale and TeleportalLocale("BUTTON_LOCKED")) or " : Button position locked."
    else
        suffix = (TeleportalLocale and TeleportalLocale("BUTTON_UNLOCKED")) or " : Button position unlocked."
    end
    DEFAULT_CHAT_FRAME:AddMessage(cyan .. "Teleportal" .. r .. suffix .. r)
end

local function ApplyToggleButtonVisibility()
    if not toggleButton then return end
    if TeleportalDB.toggleButtonHidden then
        toggleButton:Hide()
    else
        toggleButton:Show()
    end
end

local function ToggleToggleButtonHide()
    TeleportalDB.toggleButtonHidden = not (TeleportalDB.toggleButtonHidden == true)
    if TeleportalDB.toggleButtonHidden and mainPanel and mainPanel:IsShown() then
        AnimatePanelClose()
    end
    ApplyToggleButtonVisibility()
    local cyan = "\124cFF00FFFF"
    local r = "\124r"
    local suffix
    if TeleportalDB.toggleButtonHidden then
        suffix = (TeleportalLocale and TeleportalLocale("TOGGLE_BUTTON_HIDDEN")) or " : Launcher button hidden."
    else
        suffix = (TeleportalLocale and TeleportalLocale("TOGGLE_BUTTON_SHOWN")) or " : Launcher button shown."
    end
    DEFAULT_CHAT_FRAME:AddMessage(cyan .. "Teleportal" .. r .. suffix .. r)
end

local function CreateToggleButton()
    local iconPath = "Interface/AddOns/Teleportal/assets/teleportal.tga"
    local fallbackIcon = "Interface/Icons/Spell_Arcane_Teleport"

    local btn = CreateFrame("Button", "TeleportalToggleButton", UIParent)
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    -- Restore saved position (WoW may use TOPLEFT etc. after drag, so save full anchor)
    local db = TeleportalDB
    if type(db.buttonPoint) == "string" and type(db.buttonX) == "number" and type(db.buttonY) == "number" then
        btn:SetPoint(db.buttonPoint, UIParent, db.buttonRelativePoint or db.buttonPoint, db.buttonX, db.buttonY)
    else
        btn:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    end
    btn:SetClampedToScreen(true)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        if TeleportalDB.buttonLocked then return end
        self:StartMoving()
    end)
    btn:SetScript("OnDragStop", function(self)
        if TeleportalDB.buttonLocked then return end
        self:StopMovingOrSizing()
        SaveToggleButtonPosition(self)
    end)
    btn:SetScript("OnClick", ToggleTeleportalPanel)

    -- Tooltip for main Teleportal button
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if TeleportalDB.buttonLocked then
            GameTooltip:SetText((TeleportalLocale and TeleportalLocale("TOGGLE_BUTTON_TOOLTIP_LOCKED")) or "Teleportal (locked)\n/teleportal lock to move")
        else
            GameTooltip:SetText((TeleportalLocale and TeleportalLocale("TOGGLE_BUTTON_TOOLTIP")) or "Teleportal\nDrag to move, /teleportal lock to fix")
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Small button border around the icon
    local borderSize = 2
    local r, g, b, a = 0, 0, 0, 0.5
    local top = btn:CreateTexture(nil, "OVERLAY")
    top:SetColorTexture(r, g, b, a)
    top:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    top:SetHeight(borderSize)
    local bottom = btn:CreateTexture(nil, "OVERLAY")
    bottom:SetColorTexture(r, g, b, a)
    bottom:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(borderSize)
    local left = btn:CreateTexture(nil, "OVERLAY")
    left:SetColorTexture(r, g, b, a)
    left:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    left:SetWidth(borderSize)
    local right = btn:CreateTexture(nil, "OVERLAY")
    right:SetColorTexture(r, g, b, a)
    right:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(borderSize)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(btn)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:SetTexture(iconPath)
    tex:SetAlpha(0.55)

    btn:SetScript("OnShow", function()
        if not tex:GetTexture() or tex:GetTexture() == "" then
            tex:SetTexture(fallbackIcon)
        else
            tex:SetTexture(iconPath)
        end
    end)

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(btn)
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    toggleButton = btn
    ApplyToggleButtonLock()
    ApplyToggleButtonVisibility()
    return btn
end

-- ---------------------------------------------------------------------------
-- Events and init
-- ---------------------------------------------------------------------------

local addonLoadedForMage = false
local frame = CreateFrame("Frame")

local function OnEvent(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- Defer UI to PLAYER_LOGIN so we can check class
    elseif event == "PLAYER_LOGIN" then
        local _, classFilename = UnitClass("player")
        if classFilename ~= "MAGE" then
            return
        end
        if not addonLoadedForMage then
            addonLoadedForMage = true
            CreateMainPanel()
            CreateToggleButton()
            ScanSpellbook()
            RebuildSpellLists()
            UpdateRuneHeader()
            local cyan = "\124cFF00FFFF"
            local yellow = "\124cFFFFFF00"
            local r = "\124r"
            local tocVersion = select(4, GetBuildInfo())
            local tocLabel = tocVersion and tostring(tocVersion) or "?"
            DEFAULT_CHAT_FRAME:AddMessage(cyan .. "Teleportal (" .. tocLabel .. ")" .. r .. " : loaded! - Created by Codermik, join Discord for support at: " .. yellow .. "https://discord.gg/R6EkZ94TKK" .. r)
            frame:RegisterEvent("SPELLS_CHANGED")
            frame:RegisterEvent("BAG_UPDATE_DELAYED")
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
            frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        else
            ScanAndRebuild()
        end
    elseif event == "SPELLS_CHANGED" then
        ScanAndRebuild()
    elseif event == "BAG_UPDATE_DELAYED" then
        UpdateRuneHeader()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingPanelHide and mainPanel then
            pendingPanelHide = false
            mainPanel:Hide()
            mainPanel:SetScale(1)
        end
        if pendingSpellRebuild then
            pendingSpellRebuild = false
            ScanAndRebuild()
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- unitTarget, castGUID, spellID
        if arg1 == "player" and arg3 and closeOnCastSpellIDs[arg3] and mainPanel and mainPanel:IsShown() then
            AnimatePanelClose()
        end
    end
end

SLASH_TELEPORTAL1 = "/teleportal"
SLASH_TELEPORTAL2 = "/tp"
SlashCmdList["TELEPORTAL"] = function(msg)
    msg = (msg and string.lower(msg:match("^%s*(.-)%s*$") or msg)) or ""
    local cyan = "\124cFF00FFFF"
    local r = "\124r"
    if msg == "lock" then
        ToggleButtonLock()
    elseif msg == "hide" then
        ToggleToggleButtonHide()
    elseif msg == "toggle" then
        ToggleTeleportalPanel()
    else
        local help = (TeleportalLocale and TeleportalLocale("SLASH_COMMAND_HELP")) or " : /teleportal toggle - open/close spells. /teleportal hide - hide launcher. /teleportal lock - lock position."
        DEFAULT_CHAT_FRAME:AddMessage(cyan .. "Teleportal" .. r .. help .. r)
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", OnEvent)
