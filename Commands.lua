if not Infusion or Infusion.Disabled then
    return
end

-- Slash commands for Infusion main UI and tracker control.

local function ToggleMainUI()
    if not Infusion or not Infusion.MainUI then
        return
    end

    if Infusion.MainUI:IsVisible() then
        Infusion.MainUI:Hide()
    else
        Infusion.MainUI:Show()
    end
end


local function CloseTrackers()
    if not Infusion or not Infusion.CloseTrackers then
        return
    end

    if Infusion.AreTrackersVisible and not Infusion.AreTrackersVisible() then
        DEFAULT_CHAT_FRAME:AddMessage("Infusion: tracking widgets are already closed.", 1.0, 0.2, 0.2)
        return
    end

    local hasRealPallies = (not Infusion.NoPallyInRaid) and (next(Infusion.scannedPallies) ~= nil)
    if hasRealPallies then
        DEFAULT_CHAT_FRAME:AddMessage("Infusion: Cannot close trackers while raid pallies are being tracked.", 1.0, 0.2, 0.2)
        return
    end

    Infusion.CloseTrackers()
end
local function ShowWidgetConfig()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("Infusion: cannot use configuration windows when inside a raid.", 1.0, 0.2, 0.2)
        return
    end

    if Infusion and Infusion.ShowWidgetConfig then
        Infusion.ShowWidgetConfig()
    end
end

SLASH_INFUSION1 = "/infusionpally"
SlashCmdList["INFUSION"] = function()
    ToggleMainUI()
end


SLASH_INFUSIONCLOSE1 = "/infpclose"
SLASH_INFUSIONCLOSE2 = "/infpc"
SlashCmdList["INFUSIONCLOSE"] = function()
    CloseTrackers()
end

SLASH_INFUSIONWIDGET1 = "/infpwidget"
SLASH_INFUSIONWIDGET2 = "/infpw"
SlashCmdList["INFUSIONWIDGET"] = function()
    ShowWidgetConfig()
end
