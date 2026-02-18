--[[
    Teleportal - Portals and teleports from spellbook in two columns.
    Author: Codermik
    License: All rights reserved.
]]

local ADDON_NAME = "Teleportal"
local BOOKTYPE = (BOOKTYPE_SPELL ~= nil) and BOOKTYPE_SPELL or "spell"

-- Saved position for toggle button (persists across sessions)
if not TeleportalDB then
    TeleportalDB = {}
end

-- Spell lists: { name = spellName, spellID = spellID }
local teleportSpells = {}
local portalSpells = {}

-- UI references
local toggleButton
local mainPanel
local teleportContent
local portalContent
local teleportButtons = {}
local portalButtons = {}
local teleportButtonPool = {}
local portalButtonPool = {}

local BUTTON_SIZE = 32
local BUTTON_PADDING = 1
local COLUMN_WIDTH = 32
local PANEL_PADDING = 1

local COLUMN_GAP = 1
local PANEL_TOP_INSET = 1
local PANEL_BOTTOM_INSET = 1

local function GetContentHeightForButtonCount(count)
    if count == 0 then return 0 end
    return count * (BUTTON_SIZE + BUTTON_PADDING) - BUTTON_PADDING
end

local function UpdatePanelHeight()
    if not mainPanel or not teleportContent then return end
    local maxCount = math.max(#teleportSpells, #portalSpells)
    local contentHeight = GetContentHeightForButtonCount(maxCount)
    local panelHeight = PANEL_TOP_INSET + contentHeight + PANEL_BOTTOM_INSET
    mainPanel:SetHeight(panelHeight)
    teleportContent:SetHeight(contentHeight)
    portalContent:SetHeight(contentHeight)
end

-- ---------------------------------------------------------------------------
-- Spellbook scan
-- ---------------------------------------------------------------------------

local function ScanSpellbook()
    teleportSpells = {}
    portalSpells = {}

    local i = 1
    while true do
        local name = GetSpellBookItemName(i, BOOKTYPE)
        if not name then
            break
        end

        local skillType, spellID = GetSpellBookItemInfo(i, BOOKTYPE)
        if skillType == "SPELL" and spellID then
            if name:match("^Teleport") then
                tinsert(teleportSpells, { name = name, spellID = spellID })
            elseif name:match("^Portal") then
                tinsert(portalSpells, { name = name, spellID = spellID })
            end
        end

        i = i + 1
    end
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
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * (BUTTON_SIZE + BUTTON_PADDING))
    btn:SetAttribute("type", "spell")
    btn:SetAttribute("spell", spellInfo.name)
    local tex = GetSpellTexture(spellInfo.spellID) or GetSpellTexture(spellInfo.name)
    if tex then
        btn.icon:SetTexture(tex)
    end
    btn:Show()
    return btn
end

local function RebuildSpellLists()
    -- Return current buttons to pool
    for _, b in ipairs(teleportButtons) do
        b:Hide()
        b:ClearAllPoints()
        tinsert(teleportButtonPool, b)
    end
    teleportButtons = {}
    for _, b in ipairs(portalButtons) do
        b:Hide()
        b:ClearAllPoints()
        tinsert(portalButtonPool, b)
    end
    portalButtons = {}

    -- Teleports column
    for idx, spellInfo in ipairs(teleportSpells) do
        local btn = GetOrCreateSpellButton(teleportContent, teleportButtonPool, spellInfo, idx)
        tinsert(teleportButtons, btn)
    end

    -- Portals column
    for idx, spellInfo in ipairs(portalSpells) do
        local btn = GetOrCreateSpellButton(portalContent, portalButtonPool, spellInfo, idx)
        tinsert(portalButtons, btn)
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
            mainPanel:Hide()
            mainPanel:SetScale(1)
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

-- Panel bottom stays this many pixels above the toggle button's top (button is 36px tall)
local PANEL_ABOVE_BUTTON_OFFSET = 28

local function AnimatePanelOpen()
    if not mainPanel or not toggleButton then return end
    StopPanelAnimator()
    -- If ActionButtonUseKeyDown is 1, set to 0 so click works; remember to restore when we close
    if GetCVar("ActionButtonUseKeyDown") == "1" then
        SetCVar("ActionButtonUseKeyDown", "0")
        actionButtonUseKeyDownRestore = true
    else
        actionButtonUseKeyDownRestore = false
    end
    -- Zoom up from above the button: panel bottom stays 30px above button so button is never covered
    mainPanel:ClearAllPoints()
    mainPanel:SetPoint("BOTTOM", toggleButton, "CENTER", 0, PANEL_ABOVE_BUTTON_OFFSET)
    mainPanel:SetScale(ANIM_START_SCALE)
    mainPanel:Show()
    ScanAndRebuild()
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
    StopPanelAnimator()
    -- Zoom back down: panel bottom stays 30px above button
    mainPanel:ClearAllPoints()
    mainPanel:SetPoint("BOTTOM", toggleButton, "CENTER", 0, PANEL_ABOVE_BUTTON_OFFSET)
    animatorDirection = "out"
    animatorStartTime = GetTime()
    animatorRunning = true
    if not animatorFrame then
        animatorFrame = CreateFrame("Frame")
    end
    animatorFrame:SetScript("OnUpdate", RunPanelAnimator)
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

    local portalChild = CreateFrame("Frame", nil, panel)
    portalChild:SetSize(COLUMN_WIDTH, 0)
    portalChild:SetPoint("TOPLEFT", portalX, contentY)
    portalChild:SetFrameLevel(panel:GetFrameLevel() + 10)
    portalChild:EnableMouse(false)

    mainPanel = panel
    teleportContent = teleportChild
    portalContent = portalChild

    return panel
end

-- ---------------------------------------------------------------------------
-- Toggle button
-- ---------------------------------------------------------------------------

local function CreateToggleButton()
    local iconPath = "Interface/AddOns/Teleportal/assets/teleportal.tga"
    local fallbackIcon = "Interface/Icons/Spell_Arcane_Teleport"

    local btn = CreateFrame("Button", "TeleportalToggleButton", UIParent)
    btn:SetSize(36, 36)
    -- Restore saved position (WoW may use TOPLEFT etc. after drag, so save full anchor)
    local db = TeleportalDB
    if type(db.buttonPoint) == "string" and type(db.buttonX) == "number" and type(db.buttonY) == "number" then
        btn:SetPoint(db.buttonPoint, UIParent, db.buttonRelativePoint or db.buttonPoint, db.buttonX, db.buttonY)
    else
        btn:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    end
    btn:SetMovable(true)
    btn:SetClampedToScreen(true)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self) self:StartMoving() end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        if point and type(x) == "number" and type(y) == "number" then
            TeleportalDB.buttonPoint = point
            TeleportalDB.buttonRelativePoint = relativePoint or point
            TeleportalDB.buttonX = x
            TeleportalDB.buttonY = y
        end
    end)
    btn:SetScript("OnClick", function()
        if mainPanel:IsShown() then
            AnimatePanelClose()
        else
            AnimatePanelOpen()
        end
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
    return btn
end

-- ---------------------------------------------------------------------------
-- Events and init
-- ---------------------------------------------------------------------------

local addonLoadedForMage = false
local frame = CreateFrame("Frame")

local function OnEvent(_, event, arg1)
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
            local cyan = "\124cFF00FFFF"
            local yellow = "\124cFFFFFF00"
            local r = "\124r"
            DEFAULT_CHAT_FRAME:AddMessage(cyan .. "Teleportal" .. r .. " : loaded! - Created by Codermik, join Discord for support at: " .. yellow .. "https://discord.gg/R6EkZ94TKK" .. r)
            frame:RegisterEvent("SPELLS_CHANGED")
        else
            ScanAndRebuild()
        end
    elseif event == "SPELLS_CHANGED" then
        ScanAndRebuild()
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", OnEvent)
