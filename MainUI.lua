if not Infusion or Infusion.Disabled then
    return
end

local mainUI = CreateFrame("Frame", "InfusionMainFrame", UIParent)
mainUI:SetWidth(150)
mainUI:SetHeight(200)

mainUI:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    tile = true,
    tileSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
mainUI:SetBackdropColor(0, 0, 0, 0.65)

mainUI:SetMovable(true)
mainUI:EnableMouse(true)
mainUI:SetScript("OnMouseDown", function()
    if arg1 == "LeftButton" then
        this:StartMoving()
    end
end)
mainUI:SetScript("OnMouseUp", function()
    if arg1 == "LeftButton" then
        this:StopMovingOrSizing()
        if Infusion.SaveFramePosition then
            Infusion.SaveFramePosition("main_ui", this)
        end
    end
end)

if Infusion.RestoreFramePosition then
    Infusion.RestoreFramePosition("main_ui", mainUI, "CENTER", UIParent, "CENTER", 0, 0)
else
    mainUI:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local title = mainUI:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", mainUI, "TOP", 0, -12)
title:SetText("InfusionPally")

local byline = mainUI:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
byline:SetPoint("TOP", title, "BOTTOM", 0, -2)
byline:SetText("by |cfff5b5ffYawnies|r!")

local closeBtn = CreateFrame("Button", nil, mainUI, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", mainUI, "TOPRIGHT", -2, -2)
closeBtn:SetScript("OnClick", function()
    mainUI:Hide()
end)

local desc = mainUI:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
desc:SetWidth(120)
desc:SetPoint("TOP", byline, "BOTTOM", 0, -12)
desc:SetJustifyH("CENTER")
desc:SetJustifyV("TOP")
desc:SetText("A cute little addon that lets you track BoP (Hand of Protection) cooldowns.")

local raidWarning = mainUI:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
raidWarning:SetWidth(120)
raidWarning:SetPoint("TOP", desc, "BOTTOM", 0, -10)
raidWarning:SetJustifyH("CENTER")
raidWarning:SetTextColor(1.0, 0.0, 0.0)
raidWarning:SetText("Make sure you're in a raid group!")

local function PrintHelp()
    local neonGreen = "|cff00ff00"
    local reset = "|r"

    DEFAULT_CHAT_FRAME:AddMessage("--- " .. neonGreen .. "InfusionPally Help" .. reset .. " ---")
    DEFAULT_CHAT_FRAME:AddMessage(neonGreen .. "/infusionpally" .. reset .. " - opens the Scan/Help window.")
    DEFAULT_CHAT_FRAME:AddMessage(neonGreen .. "/infpclose" .. reset .. " or " .. neonGreen .. "/infpc" .. reset .. " - closes the tracking window. It will re-open on the next autoscan.")
    DEFAULT_CHAT_FRAME:AddMessage(neonGreen .. "/infpwidget" .. reset .. " or " .. neonGreen .. "/infpw" .. reset .. " - opens placeholder trackers for positioning outside raids.")
end

local function SyncSelectionsToTrackedData()
    for name in pairs(Infusion.scannedPallies) do
        if Infusion.pallies[name] == nil then
            Infusion.pallies[name] = 0
        end

        if name ~= Infusion.MOCK_PALLY_NAME and (not Infusion.pallyProfiles[name] or not Infusion.pallyProfiles[name].scanned) then
            Infusion.pendingTalentScans[name] = true
        end
    end
end

local function RefreshTrackerWindowsFromSelections()
    SyncSelectionsToTrackedData()
    Infusion.RefreshTrackingState()

    if Infusion.BuildTracker then
        Infusion.BuildTracker()
    end
end

local actionBtnWidth = 74
local actionBtnHeight = 24
local actionYOffset = 52

local helpBtn = CreateFrame("Button", "InfusionHelpButton", mainUI, "UIPanelButtonTemplate")
helpBtn:SetWidth(actionBtnWidth)
helpBtn:SetHeight(actionBtnHeight)
helpBtn:SetPoint("BOTTOM", mainUI, "BOTTOM", 0, actionYOffset)
helpBtn:SetText("Help")
helpBtn:SetScript("OnClick", function()
    PrintHelp()
end)

local compactCheck = CreateFrame("CheckButton", "InfusionCompactCheck", mainUI, "UICheckButtonTemplate")
compactCheck:SetPoint("BOTTOMLEFT", mainUI, "BOTTOMLEFT", 11, 12)
compactCheck:SetScript("OnClick", function()
    Infusion.CompactEnabled = this:GetChecked() and true or false
    Infusion.SaveOptionPrefs()
    RefreshTrackerWindowsFromSelections()
end)
getglobal(compactCheck:GetName() .. "Text"):SetText("Compact")

function Infusion.SyncMainUIFromPrefs()
    compactCheck:SetChecked(Infusion.CompactEnabled)
end

Infusion.SyncMainUIFromPrefs()
mainUI:Hide()

Infusion.MainUI = mainUI
