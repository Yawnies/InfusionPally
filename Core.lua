-- Initialize the global namespace for our addon.
-- Every other file will be able to read and write to this table.
Infusion = {}

-- Infusion state data
Infusion.scannedPallies = {} -- Shared paladin roster from last scan
Infusion.pallies = {} -- Hand of Protection cooldowns by paladin name
Infusion.pallyProfiles = {} -- Talent-derived cooldown profiles by paladin name
Infusion.pallySignatures = {} -- Paladin talent signatures by name (Guardian's Favor rank based)
Infusion.pendingTalentScans = {} -- Paladins we still need to inspect for Guardian's Favor
Infusion.pendingTalentScanReasons = {} -- Debug reason for pending talent scan
Infusion.IsTrackingActive = false
Infusion.CompactEnabled = false
Infusion.NoPallyInRaid = false
Infusion.MOCK_PALLY_NAME = "NO PALLY IN RAID"

local DEFAULT_OPTIONS = {
    compact = false,
}

local HOP_BASE_CD = 300
local HAND_OF_PROTECTION_SPELL_IDS = {
    [1022] = true,  -- Rank 1
    [5599] = true,  -- Rank 2
    [10278] = true, -- Rank 3
}

local TALENT_SCAN_RETRY_INTERVAL = 2.0
local INSPECT_TIMEOUT_SECONDS = 3.0
local INSPECT_THROTTLE_SECONDS = 1.0
local TALENT_SIGNATURE_RESCAN_INTERVAL = 600.0 -- Production interval (10 minutes).

local lastTalentScanRetry = 0
local lastInspectRequest = 0
local nextTalentSignatureRescanAt = 0
local lastKnownRaidSize = 0
local activeInspectName = nil
local activeInspectUnit = nil
local activeInspectStartedAt = 0
local activeInspectResolvedRank = nil
local activeInspectSawTalentData = false
local activeInspectSawTabData = false
local activeInspectSawProtectionTree = false
local activeInspectSawRetributionTree = false
local activeInspectLastTalentName = nil
local inspectSuppressionInstalled = false
local originalTWInspectTalentsShow = nil
local lastSuppressionInstallTry = 0

Infusion.DebugTalentScan = false
Infusion.SuppressInspectTalentWindow = true

local function DebugScan(msg)
    if not Infusion.DebugTalentScan then
        return
    end

    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[InfusionPally:DBG]|r " .. msg)
    end
end

local function BoolText(value)
    return value and "true" or "false"
end

local function NormalizeTalentName(value)
    if not value then
        return ""
    end

    local lowered = string.lower(value)
    return string.gsub(lowered, "[^%a%d]", "")
end

local function SplitByDelimiter(str, delimiter)
    local result = {}
    local from = 1
    local delimFrom, delimTo = string.find(str, delimiter, from, true)
    while delimFrom do
        table.insert(result, string.sub(str, from, delimFrom - 1))
        from = delimTo + 1
        delimFrom, delimTo = string.find(str, delimiter, from, true)
    end
    table.insert(result, string.sub(str, from))
    return result
end

local function BuildPallySignatureFromRank(guardianFavorRank)
    local rank = tonumber(guardianFavorRank) or 0
    if rank < 0 then
        rank = 0
    elseif rank > 2 then
        rank = 2
    end

    return "gf:" .. tostring(rank), rank
end

local function SetNextTalentSignatureRescan(reason)
    if GetNumRaidMembers() <= 0 then
        nextTalentSignatureRescanAt = 0
        DebugScan("Talent signature timer disabled: reason=" .. tostring(reason))
        return
    end

    nextTalentSignatureRescanAt = GetTime() + TALENT_SIGNATURE_RESCAN_INTERVAL
    DebugScan("Talent signature timer reset: reason=" .. tostring(reason) .. " next_in=" .. tostring(TALENT_SIGNATURE_RESCAN_INTERVAL) .. "s")
end

local function IsAutomatedScanActive()
    return activeInspectName ~= nil
end

local function TryInstallInspectSuppression()
    if inspectSuppressionInstalled then
        return true
    end

    if type(TWInspectTalents_Show) ~= "function" then
        return false
    end

    originalTWInspectTalentsShow = TWInspectTalents_Show
    TWInspectTalents_Show = function()
        if Infusion.SuppressInspectTalentWindow and IsAutomatedScanActive() then
            DebugScan("Suppressed TWInspectTalents_Show during automated talent scan for " .. tostring(activeInspectName))
            if TWTalentFrame and TWTalentFrame.Hide and TWTalentFrame:IsVisible() then
                TWTalentFrame:Hide()
            end
            return
        end

        originalTWInspectTalentsShow()
    end

    inspectSuppressionInstalled = true
    DebugScan("Installed inspect window suppression hook (TWInspectTalents_Show)")
    return true
end

function Infusion.InitPrefs()
    if type(INFUSIONPALLY_PREFS) ~= "table" then
        INFUSIONPALLY_PREFS = {}
    end

    if type(INFUSIONPALLY_PREFS.options) ~= "table" then
        INFUSIONPALLY_PREFS.options = {}
    end

    if type(INFUSIONPALLY_PREFS.positions) ~= "table" then
        INFUSIONPALLY_PREFS.positions = {}
    end
end

function Infusion.LoadPrefs()
    Infusion.InitPrefs()

    local opts = INFUSIONPALLY_PREFS.options
    if opts.compact == nil then
        opts.compact = DEFAULT_OPTIONS.compact
    end

    Infusion.CompactEnabled = opts.compact and true or false
end

function Infusion.SaveOptionPrefs()
    Infusion.InitPrefs()

    INFUSIONPALLY_PREFS.options.compact = Infusion.CompactEnabled and true or false
end

function Infusion.SaveFramePosition(prefKey, frame)
    if not prefKey or not frame then
        return
    end

    Infusion.InitPrefs()

    local point, _, relativePoint, x, y = frame:GetPoint()
    INFUSIONPALLY_PREFS.positions[prefKey] = {
        point = point or "CENTER",
        relativePoint = relativePoint or point or "CENTER",
        x = x or 0,
        y = y or 0,
    }
end

function Infusion.RestoreFramePosition(prefKey, frame, defaultPoint, defaultRelativeFrame, defaultRelativePoint, defaultX, defaultY)
    if not prefKey or not frame then
        return
    end

    Infusion.InitPrefs()

    local pos = INFUSIONPALLY_PREFS.positions[prefKey]
    frame:ClearAllPoints()

    if pos and pos.point and pos.relativePoint and pos.x and pos.y then
        frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
        return
    end

    frame:SetPoint(
        defaultPoint or "CENTER",
        defaultRelativeFrame or UIParent,
        defaultRelativePoint or defaultPoint or "CENTER",
        defaultX or 0,
        defaultY or 0
    )
end

local function IsSuperWoWReady()
    if IsAddOnLoaded and (IsAddOnLoaded("SuperWoW") or IsAddOnLoaded("SuperWOW")) then
        return true
    end

    local knownGlobals = {
        "SUPERWOW_VERSION",
        "SuperWoWVersion",
        "SuperWOWVersion",
        "GetSuperWowVersion",
    }

    for _, globalName in ipairs(knownGlobals) do
        if _G[globalName] ~= nil then
            return true
        end
    end

    return false
end

if not IsSuperWoWReady() then
    Infusion.Disabled = true

    StaticPopupDialogs["INFUSION_NO_SUPERWOW"] = {
        text = "SuperWoW is required to run Infusion. Please install it before reloading the addon.",
        button1 = OKAY,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        showAlert = 1,
    }

    StaticPopup_Show("INFUSION_NO_SUPERWOW")
    return
end

Infusion.HasSuperWoW = true

local function EnsureProfileTable(name)
    if not Infusion.pallyProfiles[name] then
        Infusion.pallyProfiles[name] = {
            scanned = false,
            guardianFavorRank = nil,
            cooldown = nil,
        }
    end
    return Infusion.pallyProfiles[name]
end

local function ApplyCooldownProfile(name, guardianFavorRank)
    local rank = tonumber(guardianFavorRank) or 0
    if rank < 0 then
        rank = 0
    elseif rank > 2 then
        rank = 2
    end

    local cooldown = HOP_BASE_CD - (rank * 60)
    if cooldown < 180 then
        cooldown = 180
    end

    local oldProfile = Infusion.pallyProfiles[name]
    local oldRank = oldProfile and oldProfile.guardianFavorRank or nil
    local oldCooldown = oldProfile and oldProfile.cooldown or nil
    local oldSignature = Infusion.pallySignatures[name]

    Infusion.pallyProfiles[name] = {
        scanned = true,
        guardianFavorRank = rank,
        cooldown = cooldown,
    }
    Infusion.pendingTalentScans[name] = nil
    Infusion.pendingTalentScanReasons[name] = nil

    if name ~= Infusion.MOCK_PALLY_NAME then
        local newSignature = BuildPallySignatureFromRank(rank)
        Infusion.pallySignatures[name] = newSignature

        if oldSignature == nil then
            DebugScan("Paladin signature created: " .. tostring(name) .. " signature=" .. tostring(newSignature))
        elseif oldSignature == newSignature then
            DebugScan("Paladin signature matched: " .. tostring(name) .. " signature=" .. tostring(newSignature) .. " (no profile change)")
        else
            DebugScan("Paladin signature mismatch: " .. tostring(name)
                .. " old=" .. tostring(oldSignature)
                .. " new=" .. tostring(newSignature)
                .. " oldCooldown=" .. tostring(oldCooldown)
                .. " newCooldown=" .. tostring(cooldown))
        end
    end

    if Infusion.pallies[name] == nil then
        Infusion.pallies[name] = 0
    end

    DebugScan("Profile assigned: " .. tostring(name)
        .. " rank=" .. tostring(rank)
        .. " cooldown=" .. tostring(cooldown)
        .. "s oldRank=" .. tostring(oldRank))
end

local function MarkPendingTalentScan(name, reason)
    local profile = EnsureProfileTable(name)
    profile.scanned = false
    profile.guardianFavorRank = nil
    profile.cooldown = nil
    Infusion.pendingTalentScans[name] = true
    Infusion.pendingTalentScanReasons[name] = reason or Infusion.pendingTalentScanReasons[name] or "unspecified"
    DebugScan("Marked pending scan: " .. tostring(name) .. " reason=" .. tostring(Infusion.pendingTalentScanReasons[name]))
end

function Infusion.RefreshTrackingState()
    local inRaid = GetNumRaidMembers() > 0
    local hasRealPally = (next(Infusion.scannedPallies) ~= nil) and (not Infusion.NoPallyInRaid)
    local shouldTrack = inRaid and hasRealPally

    Infusion.IsTrackingActive = shouldTrack
end

function Infusion.EnsurePlaceholderPally(forceBoth)
    if next(Infusion.scannedPallies) ~= nil then
        return
    end

    local mockName = Infusion.MOCK_PALLY_NAME
    Infusion.NoPallyInRaid = true
    Infusion.scannedPallies[mockName] = true

    ApplyCooldownProfile(mockName, 0)
    Infusion.pallies[mockName] = 0
end

function Infusion.ResetToPlaceholderState(forceBoth)
    Infusion.scannedPallies = {}
    Infusion.pallies = {}
    Infusion.pallyProfiles = {}
    Infusion.pallySignatures = {}
    Infusion.pendingTalentScans = {}
    Infusion.pendingTalentScanReasons = {}
    Infusion.EnsurePlaceholderPally(forceBoth)
    Infusion.RefreshTrackingState()
end

function Infusion.ShowWidgetConfig()
    Infusion.ResetToPlaceholderState(true)

    if Infusion.BuildTracker then
        Infusion.BuildTracker(true)
    end
end

Infusion.ResetToPlaceholderState(true)

local function GetRaidUnitByName(name)
    if not name or name == "" then
        return nil
    end

    local numRaid = GetNumRaidMembers()
    for i = 1, numRaid do
        local unit = "raid" .. i
        if UnitName(unit) == name then
            return unit
        end
    end

    return nil
end

local function CanInspectRaidUnit(unit)
    if not unit or not UnitExists(unit) then
        return false, "unit_missing_or_not_exists"
    end

    if UnitIsConnected and (not UnitIsConnected(unit)) then
        return false, "unit_not_connected"
    end

    -- Talent retrieval uses Turtle's addon-message protocol, so no local inspect-distance gating is needed.
    return true, "protocol_ok"
end

local function RequestInspect(unit)
    local name = UnitName(unit)
    if not name or name == "" then
        DebugScan("Talent protocol request failed: missing unit name for unit=" .. tostring(unit))
        return false
    end

    SendAddonMessage("TW_CHAT_MSG_WHISPER<" .. name .. ">", "INSShowTalents", "GUILD")
    DebugScan("Talent protocol request sent: prefix=TW_CHAT_MSG_WHISPER target=" .. tostring(name) .. " unit=" .. tostring(unit) .. " payload=INSShowTalents")
    return true
end

local function FinishActiveInspect(success)
    if not activeInspectName then
        return
    end

    local inspectedName = activeInspectName
    local inspectedUnit = activeInspectUnit
    activeInspectName = nil
    activeInspectUnit = nil
    activeInspectStartedAt = 0

    DebugScan("Inspect completion: name=" .. tostring(inspectedName) .. " unit=" .. tostring(inspectedUnit) .. " success=" .. BoolText(success))

    if success then
        local rank = activeInspectResolvedRank
        activeInspectResolvedRank = nil

        if (not activeInspectSawTalentData) then
            MarkPendingTalentScan(inspectedName, "inspect_no_talent_payload")
            DebugScan("Inspect completion unresolved: no INSTalentInfo data received; keeping pending for " .. tostring(inspectedName))
        elseif (not activeInspectSawProtectionTree) or (not activeInspectSawRetributionTree) then
            MarkPendingTalentScan(inspectedName, "inspect_non_paladin_tree_payload")
            DebugScan("Inspect completion unresolved: non-paladin tree payload (protection="
                .. BoolText(activeInspectSawProtectionTree) .. ", retribution=" .. BoolText(activeInspectSawRetributionTree)
                .. "); keeping pending for " .. tostring(inspectedName))
        elseif rank ~= nil then
            ApplyCooldownProfile(inspectedName, rank)
        else
            DebugScan("Guardian's Favor not present in payload; defaulting rank=0 for " .. tostring(inspectedName))
            ApplyCooldownProfile(inspectedName, 0)
        end
    else
        activeInspectResolvedRank = nil
        MarkPendingTalentScan(inspectedName, "inspect_timeout_or_failed")
    end

    activeInspectSawTalentData = false
    activeInspectSawTabData = false
    activeInspectSawProtectionTree = false
    activeInspectSawRetributionTree = false
    activeInspectLastTalentName = nil

    if ClearInspectPlayer then
        ClearInspectPlayer()
    end

    if Infusion.UpdateTrackerDisplay then
        Infusion.UpdateTrackerDisplay()
    end
end

local function HandleTalentProtocolAddonMessage(prefix, message, channel, from)
    if prefix ~= "TW_CHAT_MSG_WHISPER" then
        return
    end

    if not activeInspectName then
        return
    end

    if from ~= activeInspectName then
        DebugScan("Ignoring addon talent payload from stale sender=" .. tostring(from) .. " while waiting for " .. tostring(activeInspectName))
        return
    end

    if string.find(message, "INSTalentTabInfo;", 1, true) then
        local parts = SplitByDelimiter(message, ";")
        local tabIndex = tonumber(parts[2])
        local tabName = parts[3]
        local pointsSpent = tonumber(parts[4])
        local numTalents = tonumber(parts[5])
        activeInspectSawTabData = true

        local normalizedTab = NormalizeTalentName(tabName)
        if string.find(normalizedTab, "protection") then
            activeInspectSawProtectionTree = true
        end
        if string.find(normalizedTab, "retribution") then
            activeInspectSawRetributionTree = true
        end

        DebugScan("Talent protocol tab payload: from=" .. tostring(from)
            .. " tab=" .. tostring(tabIndex)
            .. " name=" .. tostring(tabName)
            .. " points=" .. tostring(pointsSpent)
            .. " talents=" .. tostring(numTalents))
        return
    end

    if string.find(message, "INSTalentInfo;", 1, true) then
        local parts = SplitByDelimiter(message, ";")
        local tabIndex = tonumber(parts[2])
        local talentIndex = tonumber(parts[3])
        local talentName = parts[4]
        local currentRank = tonumber(parts[7])
        activeInspectSawTalentData = true
        activeInspectLastTalentName = talentName

        DebugScan("Talent protocol talent payload: from=" .. tostring(from)
            .. " tab=" .. tostring(tabIndex)
            .. " index=" .. tostring(talentIndex)
            .. " name=" .. tostring(talentName)
            .. " rank=" .. tostring(currentRank))

        local normalized = NormalizeTalentName(talentName)
        if string.find(normalized, "guardian") and (string.find(normalized, "favor") or string.find(normalized, "favour")) then
            activeInspectResolvedRank = currentRank or 0
            DebugScan("Guardian's Favor detected from payload: rank=" .. tostring(activeInspectResolvedRank) .. " target=" .. tostring(from))
        end
        return
    end

    if string.find(message, "INSTalentEND", 1, true) then
        DebugScan("Talent protocol end payload received from " .. tostring(from))
        FinishActiveInspect(true)
        return
    end

    if string.find(message, "INS", 1, true) then
        DebugScan("Unhandled talent protocol payload from " .. tostring(from) .. ": " .. tostring(message))
    end
end

local function TryScanPendingTalents(force)
    if activeInspectName then
        if force then
            DebugScan("TryScanPendingTalents skipped: inspect in progress for " .. tostring(activeInspectName))
        end
        return
    end

    if next(Infusion.pendingTalentScans) == nil then
        return
    end

    local now = GetTime()
    if (now - lastTalentScanRetry) < TALENT_SCAN_RETRY_INTERVAL then
        if force then
            DebugScan("TryScanPendingTalents throttled: retry_interval remaining="
                .. string.format("%.2f", TALENT_SCAN_RETRY_INTERVAL - (now - lastTalentScanRetry)) .. "s")
        end
        return
    end

    if (now - lastInspectRequest) < INSPECT_THROTTLE_SECONDS then
        if force then
            DebugScan("TryScanPendingTalents throttled: lastInspectAgo=" .. string.format("%.2f", now - lastInspectRequest) .. "s")
        end
        return
    end

    lastTalentScanRetry = now
    DebugScan("TryScanPendingTalents start: force=" .. BoolText(force))

    for name in pairs(Infusion.pendingTalentScans) do
        local pendingReason = Infusion.pendingTalentScanReasons[name] or "unknown"
        DebugScan("Pending candidate: " .. tostring(name) .. " reason=" .. tostring(pendingReason))
        if (not Infusion.scannedPallies[name]) or name == Infusion.MOCK_PALLY_NAME then
            Infusion.pendingTalentScans[name] = nil
            Infusion.pendingTalentScanReasons[name] = nil
            DebugScan("Pending removed: " .. tostring(name) .. " reason=not_in_raid_or_mock")
        else
            local unit = GetRaidUnitByName(name)
            if not unit then
                DebugScan("Inspect blocked: " .. tostring(name) .. " reason=no_raid_unit_by_name")
            else
                local canInspect, reason = CanInspectRaidUnit(unit)
                if canInspect then
                    if RequestInspect(unit) then
                        DebugScan("Inspect accepted: " .. tostring(name) .. " unit=" .. tostring(unit) .. " pendingReason=" .. tostring(pendingReason))
                        activeInspectName = name
                        activeInspectUnit = unit
                        activeInspectStartedAt = now
                        lastInspectRequest = now
                        activeInspectResolvedRank = nil
                        activeInspectSawTalentData = false
                        activeInspectSawTabData = false
                        activeInspectSawProtectionTree = false
                        activeInspectSawRetributionTree = false
                        activeInspectLastTalentName = nil
                        return
                    else
                        DebugScan("Inspect call failed for " .. tostring(name))
                    end
                else
                    DebugScan("Inspect blocked: " .. tostring(name) .. " reason=" .. tostring(reason) .. " unit=" .. tostring(unit))
                end
            end
        end
    end

    DebugScan("TryScanPendingTalents done: no inspect request sent")
end

local BuildRosterSignature
local lastRosterSignature = ""

local function ClearRosterSignature(reason)
    lastRosterSignature = ""
    DebugScan("Roster signature cleared: " .. tostring(reason))
end

local function PerformRaidScan(preserveCooldowns)
    local numRaid = GetNumRaidMembers()
    DebugScan("PerformRaidScan start: raidMembers=" .. tostring(numRaid) .. " preserveCooldowns=" .. BoolText(preserveCooldowns))
    if numRaid == 0 then
        DebugScan("PerformRaidScan: no raid, reset to placeholder")
        Infusion.ResetToPlaceholderState(true)
        nextTalentSignatureRescanAt = 0
        lastKnownRaidSize = 0
        lastRosterSignature = BuildRosterSignature()
        Infusion.BuildTracker()
        return
    end

    local oldCooldowns = Infusion.pallies
    local oldProfiles = Infusion.pallyProfiles
    local oldSignatures = Infusion.pallySignatures
    local oldPending = Infusion.pendingTalentScans
    local oldPendingReasons = Infusion.pendingTalentScanReasons

    local newScannedPallies = {}
    local newCooldowns = {}
    local newProfiles = {}
    local newSignatures = {}
    local newPending = {}
    local newPendingReasons = {}

    for i = 1, numRaid do
        local name, _, _, _, _, fileName = GetRaidRosterInfo(i)
        if name and fileName == "PALADIN" then
            DebugScan("Raid paladin detected: " .. tostring(name))
            newScannedPallies[name] = true

            if preserveCooldowns and oldCooldowns[name] ~= nil then
                newCooldowns[name] = oldCooldowns[name]
            else
                newCooldowns[name] = 0
            end

            if oldProfiles[name] then
                newProfiles[name] = oldProfiles[name]
            else
                newProfiles[name] = {
                    scanned = false,
                    guardianFavorRank = nil,
                    cooldown = nil,
                }
            end

            if oldSignatures[name] then
                newSignatures[name] = oldSignatures[name]
            end

            if oldPending[name] or (not newProfiles[name].scanned) then
                newPending[name] = true
                newPendingReasons[name] = oldPendingReasons[name] or "join_or_unscanned"
                DebugScan("Paladin pending talent scan: " .. tostring(name) .. " scanned=" .. BoolText(newProfiles[name].scanned))
            else
                DebugScan("Paladin already scanned: " .. tostring(name) .. " rank=" .. tostring(newProfiles[name].guardianFavorRank))
            end
        end
    end

    for oldName in pairs(oldSignatures) do
        if oldName ~= Infusion.MOCK_PALLY_NAME and (not newScannedPallies[oldName]) then
            DebugScan("Paladin signature removed (left raid): " .. tostring(oldName) .. " oldSignature=" .. tostring(oldSignatures[oldName]))
        end
    end

    Infusion.scannedPallies = newScannedPallies
    Infusion.pallies = newCooldowns
    Infusion.pallyProfiles = newProfiles
    Infusion.pallySignatures = newSignatures
    Infusion.pendingTalentScans = newPending
    Infusion.pendingTalentScanReasons = newPendingReasons

    if next(Infusion.scannedPallies) == nil then
        Infusion.EnsurePlaceholderPally(false)
    else
        Infusion.NoPallyInRaid = false
    end

    Infusion.RefreshTrackingState()
    SetNextTalentSignatureRescan("raid_scan_complete")
    lastRosterSignature = BuildRosterSignature()
    Infusion.BuildTracker()
    TryScanPendingTalents(true)
end

function Infusion.ScanRaid()
    DebugScan("ScanRaid invoked")
    PerformRaidScan(true)
end

BuildRosterSignature = function()
    local numRaid = GetNumRaidMembers()
    if numRaid == 0 then
        return ""
    end

    local members = {}
    for i = 1, numRaid do
        local unit = "raid" .. i
        local exists, guid = UnitExists(unit)
        local name = UnitName(unit)

        if exists then
            table.insert(members, (guid and guid ~= "") and guid or (name or ("unknown:" .. i)))
        end
    end

    table.sort(members)
    return table.concat(members, "|")
end

local function RequestAutoScan(force)
    local now = GetTime()
    local previousSignature = lastRosterSignature or ""
    local currentSignature = BuildRosterSignature() or ""
    local currentRaidSize = GetNumRaidMembers()

    if (not force) and (previousSignature == currentSignature) then
        DebugScan("RequestAutoScan: roster unchanged, only pending scan retry path")
        if next(Infusion.pendingTalentScans) ~= nil and now - lastTalentScanRetry >= TALENT_SCAN_RETRY_INTERVAL then
            TryScanPendingTalents(false)
        end
        return
    end

    DebugScan("RequestAutoScan: roster changed or forced (force=" .. BoolText(force) .. ")")
    if currentRaidSize ~= lastKnownRaidSize then
        DebugScan("Raid size changed: old=" .. tostring(lastKnownRaidSize) .. " new=" .. tostring(currentRaidSize) .. " -> reset talent signature timer")
        SetNextTalentSignatureRescan("raid_size_changed")
    end
    lastKnownRaidSize = currentRaidSize
    Infusion.ScanRaid()
end

local function TriggerPeriodicTalentSignatureScan()
    if GetNumRaidMembers() <= 0 then
        nextTalentSignatureRescanAt = 0
        DebugScan("Periodic talent signature scan skipped: not in raid")
        return
    end

    if Infusion.NoPallyInRaid or next(Infusion.scannedPallies) == nil then
        DebugScan("Periodic talent signature scan skipped: no paladins in raid")
        SetNextTalentSignatureRescan("periodic_no_paladins")
        return
    end

    local queued = 0
    for name in pairs(Infusion.scannedPallies) do
        if name ~= Infusion.MOCK_PALLY_NAME then
            Infusion.pendingTalentScans[name] = true
            Infusion.pendingTalentScanReasons[name] = "periodic_signature_rescan"
            queued = queued + 1
        end
    end

    DebugScan("Periodic talent signature scan triggered: queued=" .. tostring(queued))
    SetNextTalentSignatureRescan("periodic_trigger")

    if queued > 0 then
        TryScanPendingTalents(true)
    end
end

local function GetRaidNameByGUID(casterGUID)
    if not casterGUID then
        return nil
    end

    local numRaid = GetNumRaidMembers()
    for i = 1, numRaid do
        local unit = "raid" .. i
        local exists, guid = UnitExists(unit)
        if exists and guid == casterGUID then
            return UnitName(unit)
        end
    end

    return nil
end

local function HandleUnitCastEvent()
    if not Infusion.IsTrackingActive then
        return
    end

    local casterGUID = arg1
    local castEventType = arg3
    local spellID = tonumber(arg4)

    -- Use CAST to avoid duplicate START/CAST triggers on some abilities.
    if castEventType ~= "CAST" then
        return
    end

    local isHoPCast = (spellID and HAND_OF_PROTECTION_SPELL_IDS[spellID])
    if not isHoPCast then
        return
    end

    local casterName = GetRaidNameByGUID(casterGUID)
    if not casterName then
        DebugScan("UNIT_CASTEVENT HoP detected but casterName not found by GUID=" .. tostring(casterGUID))
        return
    end

    local profile = Infusion.pallyProfiles[casterName]
    if not profile or not profile.scanned then
        DebugScan("HoP cast by unscanned paladin: " .. tostring(casterName) .. " => mark pending + retry")
        MarkPendingTalentScan(casterName, "cast_seen_before_scan")
        TryScanPendingTalents(true)
        if Infusion.UpdateTrackerDisplay then
            Infusion.UpdateTrackerDisplay()
        end
        return
    end

    if Infusion.pallies[casterName] ~= nil then
        DebugScan("HoP cast applied: " .. tostring(casterName) .. " cooldown=" .. tostring(profile.cooldown or HOP_BASE_CD) .. "s")
        Infusion.pallies[casterName] = profile.cooldown or HOP_BASE_CD
        Infusion.UpdateTrackerDisplay()
    end
end

-- Combat log listener & timer loop
local coreFrame = CreateFrame("Frame")
coreFrame:RegisterEvent("ADDON_LOADED")
coreFrame:RegisterEvent("UNIT_CASTEVENT")
coreFrame:RegisterEvent("RAID_ROSTER_UPDATE")
coreFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
coreFrame:RegisterEvent("CHAT_MSG_ADDON")

coreFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "InfusionPally" then
        DebugScan("Event: ADDON_LOADED for InfusionPally")
        TryInstallInspectSuppression()
        Infusion.LoadPrefs()
        if Infusion.SyncMainUIFromPrefs then
            Infusion.SyncMainUIFromPrefs()
        end

        if next(Infusion.scannedPallies) == nil then
            Infusion.EnsurePlaceholderPally(true)
        end

        if GetNumRaidMembers() > 0 then
            RequestAutoScan(true)
        else
            Infusion.RefreshTrackingState()
        end
        return
    end

    if event == "RAID_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        DebugScan("Event: " .. tostring(event))
        TryInstallInspectSuppression()
        local inRaid = GetNumRaidMembers() > 0

        if not inRaid and Infusion.CloseTrackers then
            ClearRosterSignature("left_raid")
            nextTalentSignatureRescanAt = 0
            lastKnownRaidSize = 0
            Infusion.pallySignatures = {}
            Infusion.pendingTalentScans = {}
            Infusion.pendingTalentScanReasons = {}
            DebugScan("Not in raid; closing trackers")
            Infusion.CloseTrackers()
            return
        end

        RequestAutoScan(false)
        return
    end

    if event == "CHAT_MSG_ADDON" then
        HandleTalentProtocolAddonMessage(arg1, arg2, arg3, arg4)
        return
    end

    if event == "UNIT_CASTEVENT" then
        HandleUnitCastEvent()
        return
    end
end)

-- The OnUpdate function runs every visual frame.
-- In 1.12.1, arg1 inside OnUpdate represents elapsed time in seconds.
coreFrame:SetScript("OnUpdate", function()
    local elapsed = arg1
    local needsBoPUIUpdate = false
    local now = GetTime()

    if not inspectSuppressionInstalled and (now - lastSuppressionInstallTry) >= 2.0 then
        lastSuppressionInstallTry = now
        TryInstallInspectSuppression()
    end

    if Infusion.IsTrackingActive then
        for name, cd in pairs(Infusion.pallies) do
            if cd > 0 then
                Infusion.pallies[name] = cd - elapsed
                if Infusion.pallies[name] <= 0 then
                    Infusion.pallies[name] = 0
                end
                needsBoPUIUpdate = true
            end
        end
    end

    if activeInspectName then
        if activeInspectName and (now - activeInspectStartedAt) >= INSPECT_TIMEOUT_SECONDS then
            DebugScan("Inspect timeout for " .. tostring(activeInspectName))
            FinishActiveInspect(false)
        end
    end

    if GetNumRaidMembers() > 0 then
        if nextTalentSignatureRescanAt > 0 and now >= nextTalentSignatureRescanAt then
            TriggerPeriodicTalentSignatureScan()
        end
        if next(Infusion.pendingTalentScans) ~= nil then
            TryScanPendingTalents(false)
        end
    end

    if needsBoPUIUpdate then
        Infusion.UpdateTrackerDisplay()
    end
end)
