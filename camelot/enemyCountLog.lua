-- LOCAL (not for a PR): the enemy count's measurement. Always on: it keeps
-- this session's fights in WowVisionDump.enemyCountLog.current and the
-- session before in .previous (on disk after /reload or logout). /wv eclog
-- prints a summary to chat.
--
-- Per fight it records when each step happened, counted from the fight's
-- start (the first moment you or a group member is in combat):
-- - you in combat (the game shows enemy plates only in combat unless Always
--   Show Nameplates is on, so this may be the step everything waits for);
-- - the first enemy plate and every plate that comes (hostile, in combat,
--   your target);
-- - countable: the first moment the count's own rule finds an enemy, run
--   here every 0.05 s, independent of the combat module's events;
-- - said: when the combat module fired the count, and with which number;
-- - when the speech queue sent it, when the game started playing it and when
--   it ended.
-- With the nameplate settings at the fight's start, so fights with and
-- without Always Show Nameplates can be told apart.

local enemyCount = WowVision.enemyCount
local secrets = WowVision.secrets
local combat = WowVision.base.ui.combat
local speech = WowVision.base.speech
local alert = combat.alerts.enemyCount

local LOG_MAX = 3000 -- detail lines per session
local FIGHTS_MAX = 200
local QUIET_END = 3 -- seconds with nobody in combat and nothing counted: the fight is over
local SCAN_EVERY = 0.05
local CVARS = { "nameplateShowAll", "nameplateShowEnemies", "nameplateMaxDistance", "nameplateShowOffscreen" }

local PLATES = {}
for i = 1, 40 do
    PLATES[i] = "nameplate" .. i
end

local log -- this session's { started, fights, lines }
local fight -- the fight in progress, nil between fights
local pending = {} -- speech queue item -> said entry, until it ended

local function round(x)
    if x == nil then
        return nil
    end
    return math.floor(x * 100 + 0.5) / 100
end

local function session()
    if log ~= nil then
        return log
    end
    WowVisionDump = WowVisionDump or {}
    local saved = WowVisionDump.enemyCountLog
    if type(saved) ~= "table" then
        saved = {}
    end
    log = { started = date("%Y-%m-%d %H:%M:%S"), fights = {}, lines = {} }
    WowVisionDump.enemyCountLog = { current = log, previous = saved.current }
    return log
end

-- One detail line, with its time in the fight.
local function line(text)
    local lines = session().lines
    local at = fight ~= nil and string.format("%.2f", GetTime() - fight.t0) or "-"
    tinsert(lines, date("%H:%M:%S") .. " +" .. at .. " " .. text)
    while #lines > LOG_MAX do
        tremove(lines, 1)
    end
end

-- A plain boolean from a game answer; a secret one is unknown (nil).
local function plain(value)
    if secrets.isSecret(value) then
        return nil
    end
    return value and true or false
end

local function cvar(name)
    local get = C_CVar ~= nil and C_CVar.GetCVar or GetCVar
    local ok, value = pcall(get, name)
    return ok and value or "?"
end

-- The count's own rule, with the game's answers (as the combat module asks them).
local plates = {}
local api = {
    plates = function()
        wipe(plates)
        for _, unit in ipairs(PLATES) do
            if UnitExists(unit) then
                tinsert(plates, unit)
            end
        end
        return plates
    end,
    group = function()
        return WowVision.utils.groupUnits(IsInRaid(), IsInGroup())
    end,
    exists = UnitExists,
    reaction = function(unit)
        return UnitReaction("player", unit)
    end,
    isDead = UnitIsDead,
    inCombat = UnitAffectingCombat,
    classification = UnitClassification,
    threat = UnitThreatSituation,
    inGroup = function()
        return IsInGroup()
    end,
    tapDenied = UnitIsTapDenied,
    isSecret = secrets.isSecret,
}

local function countNow()
    local ok, count = pcall(enemyCount.count, api, combat.settings.enemyCountMode, combat.settings.enemyCountEliteOnly)
    return ok and count or nil
end

-- The first group unit in combat (you included), or nil.
local function groupInCombat()
    for _, unit in ipairs(api.group()) do
        if UnitExists(unit) and plain(UnitAffectingCombat(unit)) then
            return unit
        end
    end
    return nil
end

local function plateState(unit)
    local reaction = UnitReaction("player", unit)
    local hostile = reaction ~= nil and not secrets.isSecret(reaction) and reaction <= 4
    local inCombat = plain(UnitAffectingCombat(unit))
    local isTarget = plain(UnitIsUnit(unit, "target"))
    local tapped = plain(UnitIsTapDenied(unit))
    return (hostile and "hostile" or "not hostile")
        .. (inCombat == nil and ", combat secret" or inCombat and ", in combat" or ", idle")
        .. (tapped == nil and ", tap secret" or tapped and ", tapped by others" or "")
        .. (isTarget and ", your target" or "")
end

local function since(at)
    return at ~= nil and round(at - fight.t0) or nil
end

local function startFight(now, by)
    local hostile, total = 0, 0
    for _, unit in ipairs(api.plates()) do
        total = total + 1
        local reaction = UnitReaction("player", unit)
        if reaction ~= nil and not secrets.isSecret(reaction) and reaction <= 4 then
            hostile = hostile + 1
        end
    end
    local settings = {}
    for _, name in ipairs(CVARS) do
        settings[name] = cvar(name)
    end
    fight = {
        t0 = now,
        at = date("%H:%M:%S"),
        startedBy = by,
        group = IsInRaid() and "raid" or IsInGroup() and "party" or "solo",
        mode = combat.settings.enemyCountMode,
        control = combat.settings.enemyCountControlMode,
        cvars = settings,
        platesAtStart = total,
        hostilePlatesAtStart = hostile,
        targetAtStart = UnitExists("target") and plateState("target") or "none",
        plates = 0,
        said = {},
        lastBusy = now,
    }
    if plain(UnitAffectingCombat("player")) then
        fight.playerCombat = now
    end
    if hostile > 0 then
        fight.firstPlate = now
    end
    tinsert(session().fights, fight)
    while #session().fights > FIGHTS_MAX do
        tremove(session().fights, 1)
    end
    line("fight start by " .. by .. ", " .. fight.group .. ", plates " .. total .. " (" .. hostile .. " hostile), target "
        .. fight.targetAtStart .. ", Always Show Nameplates " .. settings.nameplateShowAll
        .. ", plate distance " .. settings.nameplateMaxDistance)
end

local function endFight()
    -- Plain numbers for the saved file and the summary.
    fight.youInCombat = since(fight.playerCombat)
    fight.groupInCombat = since(fight.groupCombat)
    fight.firstPlateAt = since(fight.firstPlate)
    fight.countableAt = since(fight.countable)
    fight.saidAt = fight.said[1] ~= nil and fight.said[1].at or nil
    fight.length = round(fight.lastBusy - fight.t0)
    fight.lastBusy, fight.playerCombat, fight.groupCombat, fight.firstPlate, fight.countable = nil, nil, nil, nil, nil
    line("fight end: you in combat " .. tostring(fight.youInCombat) .. ", first plate " .. tostring(fight.firstPlateAt)
        .. ", countable " .. tostring(fight.countableAt) .. ", said " .. tostring(fight.saidAt))
    fight = nil
end

-- Wraps --------------------------------------------------------------------------------

local fire = alert.fire
function alert:fire(message)
    local now = GetTime()
    if fight == nil then
        startFight(now, "a count")
    end
    local entry = {
        at = round(now - fight.t0),
        count = message ~= nil and message.count or nil,
        countable = countNow(),
        queueBefore = #speech.queue,
        speakingBefore = speech.speaking and true or false,
        time = now,
    }
    local current = speech.current
    local queued = #speech.queue
    local results = { fire(self, message) }
    local item
    if speech.current ~= current then
        item = speech.current
        entry.sentAfter = 0
    elseif #speech.queue > queued then
        item = speech.queue[#speech.queue]
    end
    if item ~= nil then
        pending[item] = entry
    else
        entry.noQueue = true
    end
    if #fight.said < 30 then
        tinsert(fight.said, entry)
    end
    line("said " .. tostring(entry.count) .. " (the rule counts " .. tostring(entry.countable) .. "), queue before "
        .. entry.queueBefore .. (entry.speakingBefore and ", other speech playing" or ""))
    return unpack(results)
end

-- Fight tracking ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_STARTED")
frame:SetScript("OnEvent", function(_, event, unit)
    if not alert.enabled then
        return
    end
    local now = GetTime()
    if event == "VOICE_CHAT_TTS_PLAYBACK_STARTED" then
        local entry = speech.current ~= nil and pending[speech.current] or nil
        if entry ~= nil and entry.startedAfter == nil then
            entry.startedAfter = round(now - entry.time)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if fight == nil then
            startFight(now, "you")
        end
        if fight.playerCombat == nil then
            fight.playerCombat = now
        end
        line("you in combat")
    elseif event == "PLAYER_REGEN_ENABLED" then
        if fight ~= nil then
            line("you out of combat")
        end
    elseif fight ~= nil then
        if event == "NAME_PLATE_UNIT_ADDED" then
            local state = plateState(unit)
            fight.plates = fight.plates + 1
            if fight.firstPlate == nil and state:find("^hostile") then
                fight.firstPlate = now
            end
            line("plate " .. tostring(unit) .. " added: " .. state)
        else
            line("plate " .. tostring(unit) .. " removed")
        end
    end
end)

local nextScan = 0
local lastCount
frame:SetScript("OnUpdate", function()
    local now = GetTime()
    for item, entry in pairs(pending) do
        if speech.current == item then
            if entry.sentAfter == nil then
                entry.sentAfter = round(now - entry.time)
            end
        elseif entry.sentAfter ~= nil then
            entry.endedAfter = round(now - entry.time)
            pending[item] = nil
        elseif not tContains(speech.queue, item) then
            entry.dropped = true
            pending[item] = nil
        end
    end
    if now < nextScan or not alert.enabled then
        return
    end
    nextScan = now + SCAN_EVERY
    local member = groupInCombat()
    local count = countNow()
    if fight == nil then
        if member ~= nil then
            startFight(now, member)
        elseif count ~= nil and count > 0 then
            startFight(now, "a counted enemy")
        else
            return
        end
    end
    if member ~= nil and fight.groupCombat == nil then
        fight.groupCombat = now
        fight.groupFirst = member
    end
    if count ~= lastCount then
        line("rule counts " .. tostring(count))
        lastCount = count
    end
    if count ~= nil and count > 0 and fight.countable == nil then
        fight.countable = now
        fight.firstCount = count
    end
    if member ~= nil or (count ~= nil and count > 0) or next(pending) ~= nil then
        fight.lastBusy = now
    elseif now - fight.lastBusy >= QUIET_END then
        endFight()
        lastCount = nil
    end
end)

-- Summary ----------------------------------------------------------------------------------

local function median(list)
    if #list == 0 then
        return nil
    end
    table.sort(list)
    return list[math.ceil(#list / 2)]
end

local function fmt(x)
    return x ~= nil and string.format("%.2f s", x) or "none"
end

local function steps(name, list)
    return name .. ": median " .. fmt(median(list)) .. ", slowest " .. fmt(#list > 0 and math.max(unpack(list)) or nil)
        .. " (" .. #list .. " fights)"
end

local function summary(which)
    local saved = WowVisionDump and WowVisionDump.enemyCountLog or nil
    local data = saved ~= nil and saved[which] or nil
    if data == nil or #data.fights == 0 then
        return { "WowVision enemy count log: no fights recorded (" .. which .. ")" }
    end
    local you, plate, countable, said, toSaid, playing, waited = {}, {}, {}, {}, {}, {}, {}
    local before, showAll = 0, {}
    for _, f in ipairs(data.fights) do
        if f.saidAt ~= nil then
            -- Finished fights carry plain numbers; the one in progress is skipped.
            if f.youInCombat ~= nil then
                tinsert(you, f.youInCombat)
            end
            if f.firstPlateAt ~= nil then
                tinsert(plate, f.firstPlateAt)
            end
            if f.countableAt ~= nil then
                tinsert(countable, f.countableAt)
                tinsert(toSaid, f.saidAt - f.countableAt)
                if f.youInCombat ~= nil and f.countableAt >= f.youInCombat and f.youInCombat > 0.3 then
                    before = before + 1
                end
            end
            tinsert(said, f.saidAt)
            local first = f.said[1]
            if first.startedAfter ~= nil then
                tinsert(playing, f.saidAt + first.startedAfter)
                tinsert(waited, first.startedAfter)
            end
        end
        local value = f.cvars and f.cvars.nameplateShowAll or "?"
        showAll[value] = (showAll[value] or 0) + 1
    end
    local settingsText = {}
    for value, n in pairs(showAll) do
        tinsert(settingsText, value .. " in " .. n)
    end
    return {
        "WowVision enemy count log (" .. which .. ", since " .. data.started .. "): " .. #data.fights
            .. " fights, Always Show Nameplates " .. table.concat(settingsText, ", "),
        "All times from the first moment you or a group member was in combat.",
        steps("You in combat", you),
        steps("First enemy plate", plate),
        steps("Countable", countable),
        steps("Said", said),
        steps("Playing", playing),
        steps("Countable to said", toSaid),
        steps("Said to playing", waited),
        "Countable only after you joined the fight (you came in more than 0.3 s late): " .. before .. " fights",
    }
end

combat:registerCommand({
    name = "eclog",
    scope = "WowVision",
    description = "Enemy count measurement: summary of this session (eclog previous: the one before)",
    func = function(args)
        local which = (type(args) == "string" and args:find("prev")) and "previous" or "current"
        for _, text in ipairs(summary(which)) do
            print(text)
        end
    end,
})
