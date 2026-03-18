if not Infusion or Infusion.Disabled then
    return
end

-- Create the physical minimap button
local minimapBtn = CreateFrame("Button", "InfusionMinimapBtn", Minimap)
minimapBtn:SetWidth(32)
minimapBtn:SetHeight(32)
minimapBtn:SetFrameStrata("MEDIUM")
minimapBtn:SetPoint("CENTER", Minimap, "BOTTOMLEFT", 15, 15)

-- Blessing of Protection icon
local icon = minimapBtn:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\Icons\\Spell_Holy_SealOfProtection")
icon:SetWidth(20)
icon:SetHeight(20)
icon:SetPoint("CENTER", minimapBtn, "CENTER", -1, 1)

-- The standard Minimap Button Border
local border = minimapBtn:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetWidth(54)
border:SetHeight(54)
border:SetPoint("TOPLEFT", minimapBtn, "TOPLEFT", 0, 0)

-- Hover highlight effect
minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Hover Tooltip Logic
minimapBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:SetText("Infusion|cfff58cbaPally|r")
    GameTooltip:Show()
end)

minimapBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Click Logic: Toggle the MainUI we created in MainUI.lua
minimapBtn:SetScript("OnClick", function()
    if Infusion.MainUI:IsVisible() then
        Infusion.MainUI:Hide()
    else
        Infusion.MainUI:Show()
    end
end)
