if not Infusion or Infusion.Disabled then
    return
end

-- BoP tracker frame (click-to-whisper enabled for scanned/ready paladins)
local bopTrackerFrame = CreateFrame("Frame", "InfusionTrackerFrame", UIParent)
bopTrackerFrame:SetWidth(200)
bopTrackerFrame:SetMovable(true)
bopTrackerFrame:EnableMouse(true)
bopTrackerFrame:SetScript("OnMouseDown", function() if arg1 == "LeftButton" then this:StartMoving() end end)
bopTrackerFrame:SetScript("OnMouseUp", function()
    if arg1 == "LeftButton" then
        this:StopMovingOrSizing()
        if Infusion.SaveFramePosition then
            Infusion.SaveFramePosition("bop_tracker", this)
        end
    end
end)
bopTrackerFrame:Hide()

if Infusion.RestoreFramePosition then
    Infusion.RestoreFramePosition("bop_tracker", bopTrackerFrame, "CENTER", UIParent, "CENTER", 200, 0)
else
    bopTrackerFrame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
end

local footerText = bopTrackerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
footerText:SetWidth(180)
footerText:SetPoint("BOTTOM", bopTrackerFrame, "BOTTOM", 0, 15)
footerText:SetJustifyH("CENTER")
footerText:SetJustifyV("TOP")
footerText:SetText("Click on a name to request Hand of Protection.")

local dragLabelBoP = bopTrackerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dragLabelBoP:SetPoint("BOTTOM", bopTrackerFrame, "BOTTOM", 0, 2)
dragLabelBoP:SetJustifyH("CENTER")
dragLabelBoP:SetText("[DRAG]")
dragLabelBoP:Hide()

local bopRows = {}

local function IsCompact()
    return Infusion.CompactEnabled and true or false
end

local function IsMockPally(name)
    return name and Infusion and Infusion.MOCK_PALLY_NAME and name == Infusion.MOCK_PALLY_NAME
end

local function IsPallyScanned(name)
    if IsMockPally(name) then
        return true
    end

    local profile = Infusion.pallyProfiles and Infusion.pallyProfiles[name]
    return profile and profile.scanned
end

local function ApplyFrameStyle(frame)
    local compact = IsCompact()
    local inset = compact and 0 or 4
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true,
        tileSize = 16,
        insets = { left = inset, right = inset, top = inset, bottom = inset }
    })
    frame:SetBackdropColor(0, 0, 0, 0.65)
    frame:SetWidth(compact and 130 or 200)
end

local function WhisperBoPRequest(pallyName)
    if not pallyName or pallyName == "" then
        return
    end

    local requester = UnitName("player") or "Unknown"
    local requesterColored = "|cffffffff" .. requester .. "|r"
    local bopColored = "|cff9fd3ffBoP (Hand of Protection)|r"
    local message = "[InfusionP] " .. requesterColored .. " requests " .. bopColored .. "!"
    SendChatMessage(message, "WHISPER", nil, pallyName)
end

local function GetSortedPallies()
    local count = 0
    local sortedNames = {}

    for name in pairs(Infusion.scannedPallies) do
        count = count + 1
        table.insert(sortedNames, name)
    end

    table.sort(sortedNames)
    return count, sortedNames
end

local function GetLayout()
    local compact = IsCompact()
    if compact then
        return {
            compact = true,
            rowWidth = 130,
            rowHeight = 20,
            topPadding = 0,
            rowStep = 20,
            bottomExtra = 16,
            leftPad = 0,
            rightPad = 0,
            nameGap = 4,
            nameWidth = 76,
            cdWidth = 32,
            readyText = "RDY",
            notScannedText = "NSC",
            showFooter = false,
            showDrag = true,
        }
    end

    return {
        compact = false,
        rowWidth = 180,
        rowHeight = 20,
        topPadding = 15,
        rowStep = 25,
        bottomExtra = 30,
        leftPad = 5,
        rightPad = 5,
        nameGap = 8,
        nameWidth = 75,
        cdWidth = 65,
        readyText = "CD Ready",
        notScannedText = "Not Scanned",
        showFooter = true,
        showDrag = false,
    }
end

local function EnsureBoPRow(i)
    local row = bopRows[i]
    if row then
        return row
    end

    row = CreateFrame("Frame", nil, bopTrackerFrame)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(16)
    icon:SetHeight(16)
    icon:SetTexture("Interface\\Icons\\Spell_Holy_SealOfProtection")
    row.icon = icon

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    local requestOverlay = CreateFrame("Button", nil, row)
    requestOverlay:SetHeight(20)
    requestOverlay:RegisterForClicks("LeftButtonUp")
    requestOverlay:SetScript("OnClick", function()
        local rowParent = this:GetParent()
        if not rowParent or not rowParent.pallyName then
            return
        end

        if IsMockPally(rowParent.pallyName) or (not IsPallyScanned(rowParent.pallyName)) then
            return
        end

        local cd = Infusion.pallies[rowParent.pallyName]
        if cd and cd <= 0 then
            WhisperBoPRequest(rowParent.pallyName)
        end
    end)
    requestOverlay:Hide()
    row.requestOverlay = requestOverlay

    local cdText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cdText:SetJustifyH("RIGHT")
    row.cdText = cdText

    bopRows[i] = row
    return row
end

local function ApplyRowLayout(row, layout)
    row:SetWidth(layout.rowWidth)
    row:SetHeight(layout.rowHeight)

    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", layout.leftPad, 0)

    row.nameText:ClearAllPoints()
    row.nameText:SetPoint("LEFT", row.icon, "RIGHT", layout.nameGap, 0)
    row.nameText:SetWidth(layout.nameWidth)

    row.cdText:ClearAllPoints()
    row.cdText:SetPoint("RIGHT", row, "RIGHT", -layout.rightPad, 0)
    row.cdText:SetWidth(layout.cdWidth)

    if row.requestOverlay then
        row.requestOverlay:ClearAllPoints()
        row.requestOverlay:SetPoint("LEFT", row, "LEFT", layout.leftPad, 0)
        row.requestOverlay:SetPoint("RIGHT", row, "RIGHT", -layout.rightPad, 0)
    end
end

function Infusion.BuildTracker(forceShow)
    ApplyFrameStyle(bopTrackerFrame)

    local pallyCount, sortedNames = GetSortedPallies()
    if pallyCount == 0 then
        bopTrackerFrame:Hide()
        return
    end

    local layout = GetLayout()
    if layout.compact then
        bopTrackerFrame:SetHeight((pallyCount * layout.rowStep) + layout.bottomExtra)
    else
        bopTrackerFrame:SetHeight(30 + (pallyCount * 25) + 30)
    end
    bopTrackerFrame:Show()

    if layout.showFooter then
        footerText:Show()
    else
        footerText:Hide()
    end

    if layout.showDrag then
        dragLabelBoP:Show()
    else
        dragLabelBoP:Hide()
    end

    for _, row in ipairs(bopRows) do
        row:Hide()
    end

    for i, name in ipairs(sortedNames) do
        local row = EnsureBoPRow(i)
        ApplyRowLayout(row, layout)
        row:ClearAllPoints()
        row:SetPoint("TOP", bopTrackerFrame, "TOP", 0, -layout.topPadding - ((i - 1) * layout.rowStep))
        row.nameText:SetText(name)
        if IsMockPally(name) then
            row.nameText:SetTextColor(1.0, 0.2, 0.2)
            row.nameText:SetWidth(layout.rowWidth - layout.leftPad - layout.rightPad - 16 - layout.nameGap)
            row.cdText:SetWidth(0)
        else
            row.nameText:SetTextColor(1.0, 0.82, 0.0)
            row.nameText:SetWidth(layout.nameWidth)
            row.cdText:SetWidth(layout.cdWidth)
        end
        row.pallyName = name
        row:Show()
    end

    Infusion.UpdateTrackerDisplay(forceShow)
end

function Infusion.UpdateTrackerDisplay(forceShow)
    local layout = GetLayout()

    for _, row in ipairs(bopRows) do
        if row:IsVisible() and row.pallyName then
            if IsMockPally(row.pallyName) then
                row:SetAlpha(1.0)
                row.nameText:SetTextColor(1.0, 0.2, 0.2)
                row.cdText:SetText("")
                if row.requestOverlay then
                    row.requestOverlay:Hide()
                    row.requestOverlay:EnableMouse(false)
                end
            else
                local scanned = IsPallyScanned(row.pallyName)
                local cd = Infusion.pallies[row.pallyName]
                row.nameText:SetTextColor(1.0, 0.82, 0.0)

                if not scanned then
                    row:SetAlpha(0.4)
                    row.cdText:SetText(layout.notScannedText)
                    row.cdText:SetTextColor(1.0, 0.65, 0.0)
                    if row.requestOverlay then
                        row.requestOverlay:Hide()
                        row.requestOverlay:EnableMouse(false)
                    end
                elseif cd and cd > 0 then
                    row:SetAlpha(0.4)
                    row.cdText:SetText(math.ceil(cd) .. "s")
                    row.cdText:SetTextColor(1.0, 0.0, 0.0)
                    if row.requestOverlay then
                        row.requestOverlay:Hide()
                        row.requestOverlay:EnableMouse(false)
                    end
                else
                    row:SetAlpha(1.0)
                    row.cdText:SetText(layout.readyText)
                    row.cdText:SetTextColor(0.0, 1.0, 0.0)
                    if row.requestOverlay then
                        row.requestOverlay:Show()
                        row.requestOverlay:EnableMouse(true)
                    end
                end
            end
        end
    end
end

function Infusion.AreTrackersVisible()
    return (bopTrackerFrame and bopTrackerFrame:IsVisible())
end

function Infusion.CloseTrackers()
    local wasVisible = Infusion.AreTrackersVisible()

    if bopTrackerFrame then
        bopTrackerFrame:Hide()
    end

    if Infusion.ResetToPlaceholderState then
        Infusion.ResetToPlaceholderState(true)
    else
        Infusion.scannedPallies = {}
        Infusion.pallies = {}
        Infusion.pallyProfiles = {}
        Infusion.pendingTalentScans = {}
        Infusion.NoPallyInRaid = false

        if Infusion.RefreshTrackingState then
            Infusion.RefreshTrackingState()
        end
    end

    return wasVisible
end
