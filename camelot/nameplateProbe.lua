-- Nameplate probe (developer tool, /wv plates): checks in game what an
-- enemy count built on nameplates would rest on. Separate from every
-- module; it can be left out without anything noticing.
--
-- /wv plates         the nameplate settings (value and game default) and
--                    one line per nameplate right now: hostile, in combat,
--                    your threat, elite, range, behind the camera, which
--                    values come back secret
-- /wv plates watch   toggles: notes the range at which enemy plates appear
--                    and vanish, and says the enemy count whenever it
--                    changes (the rule the planned count would use: enemies
--                    on a plate that you, your pet or your group are on the
--                    threat list of); a second /wv plates watch stops and
--                    reports
--
-- Results go to chat and WowVisionDump.nameplateProbe (saved at the next
-- /reload).

local secrets = WowVision.secrets
local rangeCheck = LibStub("LibRangeCheck-3.0", true)

local SETTINGS = {
    "nameplateMaxDistance",
    "nameplateShowEnemies",
    "nameplateShowAll",
    "nameplateShowEnemyMinions",
    "nameplateShowEnemyMinus",
    "nameplateShowOffscreen",
    "nameplateOccludedAlphaMult",
}

-- A new count is said only after it held this long.
local SETTLE = 0.5

local function chat(text)
    for line in tostring(text):gmatch("[^\n]+") do
        print("WowVision probe: " .. line)
    end
end

local function say(text)
    chat(text)
    WowVision:speak(text)
end

local function report(name, lines)
    WowVisionDump = WowVisionDump or {}
    local runs = WowVisionDump.nameplateProbe or {}
    tinsert(runs, { name = name, at = date("%Y-%m-%d %H:%M:%S"), lines = lines })
    while #runs > 6 do
        tremove(runs, 1)
    end
    WowVisionDump.nameplateProbe = runs
    for _, line in ipairs(lines) do
        chat(line)
    end
end

local function plateUnits()
    local units = {}
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            tinsert(units, unit)
        end
    end
    return units
end

local function settingLine(name)
    local ok, value, default = pcall(C_CVar.GetCVarInfo, name)
    if not ok or value == nil then
        return name .. ": unknown"
    end
    return name .. ": " .. tostring(value) .. ", game default " .. tostring(default)
end

-- min and max yards, or nil when LibRangeCheck cannot tell.
local function range(unit)
    if rangeCheck == nil then
        return nil
    end
    local ok, minRange, maxRange = pcall(rangeCheck.GetRange, rangeCheck, unit)
    if not ok or secrets.isSecret(minRange) or secrets.isSecret(maxRange) then
        return nil
    end
    return minRange, maxRange
end

local function rangeText(minRange, maxRange)
    if minRange == nil then
        return "range unknown"
    end
    return "range " .. minRange .. " to " .. tostring(maxRange or "far")
end

-- Sku's rule: reaction 4 or lower is hostile. Unlike UnitCanAttack it
-- holds while an enemy is immune or flagged not attackable mid-fight.
local function isHostile(unit)
    local reaction = UnitReaction("player", unit)
    if reaction == nil or secrets.isSecret(reaction) then
        return false
    end
    return reaction <= 4
end

local function behindCamera(unit)
    if C_NamePlateManager == nil or C_NamePlateManager.IsNamePlateUnitBehindCamera == nil then
        return false
    end
    local ok, behind = pcall(C_NamePlateManager.IsNamePlateUnitBehindCamera, unit)
    return ok and behind == true
end

local function groupUnits()
    local units = { "player", "pet" }
    if IsInRaid() then
        for i = 1, 40 do
            tinsert(units, "raid" .. i)
            tinsert(units, "raidpet" .. i)
        end
    else
        for i = 1, 4 do
            tinsert(units, "party" .. i)
            tinsert(units, "partypet" .. i)
        end
    end
    return units
end

-- Counters for the watch report: how many threat answers came back secret.
local threatAsked, threatSecret = 0, 0

-- Whether you, your pet or a group member is on the enemy's threat list.
-- A secret answer still says "on the list" (truthiness works on secrets).
local function groupFights(unit, group)
    for _, member in ipairs(group) do
        if UnitExists(member) then
            local status = UnitThreatSituation(member, unit)
            threatAsked = threatAsked + 1
            if secrets.isSecret(status) then
                threatSecret = threatSecret + 1
                return true
            end
            if status ~= nil then
                return true
            end
        end
    end
    return false
end

local function enemyCount()
    local group = groupUnits()
    local count = 0
    for _, unit in ipairs(plateUnits()) do
        if isHostile(unit) and not UnitIsDead(unit) and groupFights(unit, group) then
            count = count + 1
        end
    end
    return count
end

-- Snapshot ----------------------------------------------------------------

local function snapshot()
    local lines = {}
    for _, name in ipairs(SETTINGS) do
        tinsert(lines, settingLine(name))
    end
    local units = plateUnits()
    tinsert(lines, #units .. " nameplates now, enemy count by the planned rule: " .. enemyCount())
    for _, unit in ipairs(units) do
        local parts = { unit }
        tinsert(parts, isHostile(unit) and "hostile" or "not hostile")
        if UnitIsDead(unit) then
            tinsert(parts, "dead")
        end
        tinsert(parts, UnitAffectingCombat(unit) and "in combat" or "not in combat")
        local threat = UnitThreatSituation("player", unit)
        if secrets.isSecret(threat) then
            tinsert(parts, "your threat secret")
        else
            tinsert(parts, "your threat " .. tostring(threat))
        end
        tinsert(parts, tostring(UnitClassification(unit)))
        tinsert(parts, rangeText(range(unit)))
        if behindCamera(unit) then
            tinsert(parts, "behind camera")
        end
        local name = UnitName(unit)
        if secrets.isSecret(name) then
            tinsert(parts, "name secret")
        else
            tinsert(parts, tostring(name))
        end
        tinsert(parts, secrets.isSecret(UnitGUID(unit)) and "guid secret" or "guid readable")
        tinsert(lines, table.concat(parts, ", "))
    end
    report("snapshot", lines)
    WowVision:speak(#units .. " nameplates, details in chat")
end

-- Watch -------------------------------------------------------------------

local watchFrame
local watching = false
local stats
local lastSaid, pending
local ticker

local function newStats()
    return {
        started = GetTime(),
        added = 0,
        hostileAdded = 0,
        removed = 0,
        farthestAdd = nil,
        nearestRemove = nil,
        removeRanges = {},
        behindChanges = 0,
        said = 0,
    }
end

local function settle()
    pending = nil
    local count = enemyCount()
    if count ~= lastSaid then
        lastSaid = count
        stats.said = stats.said + 1
        WowVision:speak(tostring(count))
    end
end

local function recount()
    local count = enemyCount()
    if count == lastSaid then
        pending = nil
        return
    end
    if pending ~= count then
        pending = count
        C_Timer.After(SETTLE, function()
            if watching and pending == count then
                settle()
            end
        end)
    end
end

local function onPlateAdded(unit)
    stats.added = stats.added + 1
    if not isHostile(unit) then
        return
    end
    stats.hostileAdded = stats.hostileAdded + 1
    local minRange = range(unit)
    if minRange ~= nil and (stats.farthestAdd == nil or minRange > stats.farthestAdd) then
        stats.farthestAdd = minRange
    end
end

local function onPlateRemoved(unit)
    stats.removed = stats.removed + 1
    if not UnitExists(unit) or not isHostile(unit) or UnitIsDead(unit) then
        return
    end
    local minRange, maxRange = range(unit)
    if minRange ~= nil then
        if #stats.removeRanges < 20 then
            tinsert(stats.removeRanges, minRange .. "-" .. tostring(maxRange or "far"))
        end
        if stats.nearestRemove == nil or minRange < stats.nearestRemove then
            stats.nearestRemove = minRange
        end
    end
end

local function stopWatch()
    watching = false
    watchFrame:UnregisterAllEvents()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    local removes = #stats.removeRanges > 0 and table.concat(stats.removeRanges, ", ") or "none"
    report("watch", {
        string.format("watched %d seconds", math.floor(GetTime() - stats.started)),
        string.format("plates appeared %d, hostile %d", stats.added, stats.hostileAdded),
        "farthest hostile plate appeared at " .. tostring(stats.farthestAdd or "unknown") .. " yards or more",
        "living hostile plates vanished at (yards): " .. removes,
        "nearest such vanish at " .. tostring(stats.nearestRemove or "none") .. " yards or more",
        string.format("behind camera changes %d", stats.behindChanges),
        string.format("threat answers %d, secret %d", threatAsked, threatSecret),
        string.format("counts said %d", stats.said),
    })
    say("Nameplate watch stopped, report in chat")
end

local function startWatch()
    if watchFrame == nil then
        watchFrame = CreateFrame("Frame")
        watchFrame:SetScript("OnEvent", function(_, event, unit)
            if event == "NAME_PLATE_UNIT_ADDED" then
                onPlateAdded(unit)
            elseif event == "NAME_PLATE_UNIT_REMOVED" then
                onPlateRemoved(unit)
            elseif event == "NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED" then
                stats.behindChanges = stats.behindChanges + 1
                return
            end
            recount()
        end)
    end
    stats = newStats()
    threatAsked, threatSecret = 0, 0
    lastSaid, pending = enemyCount(), nil
    watching = true
    watchFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    watchFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    watchFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    watchFrame:RegisterEvent("UNIT_FLAGS")
    watchFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    watchFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    pcall(watchFrame.RegisterEvent, watchFrame, "NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED")
    -- Events miss a mob that dies or evades quietly; one recount a second
    -- catches it.
    ticker = C_Timer.NewTicker(1, recount)
    say("Nameplate watch started, enemy count " .. lastSaid)
end

-- Command -----------------------------------------------------------------

WowVision.base:registerCommand({
    name = "plates",
    description = "Nameplate probe: no argument lists the nameplate settings and every nameplate now, 'watch' toggles range notes and a spoken enemy count",
    func = function(args)
        local command = tostring(args or ""):lower():match("%S+")
        if command == "watch" then
            if watching then
                stopWatch()
            else
                startWatch()
            end
        elseif command == nil then
            snapshot()
        else
            say("Usage: slash w v plates, or plates watch")
        end
    end,
})
