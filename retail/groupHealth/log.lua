-- LOCAL (not for a PR): the group health monitor's measurement. Always on:
-- it starts with the first thing it records in a session, keeps that
-- session's log in WowVisionDump.groupHealthLog.current and the session
-- before in .previous (on disk after /reload or logout). /wv ghlog prints a
-- summary to chat.
--
-- It wraps the monitor's own methods (module.lua stays as upstream has it)
-- and records, per announcement ("turn"):
-- - when the member's health first changed since their last turn, and how
--   long the turn then waited;
-- - how long the member was due while other speech held the line (the
--   repeat speaks only while the speech queue is idle);
-- - when the speech queue sent it, when the game started playing it and when
--   it ended (sent to ended = how long the announcement held the line).
-- The monitor never knows whether a turn was audible (the volume gate is
-- inside the secret), so neither does this log. Health events are counted
-- per member, not logged one by one (hundreds a second in a big fight).

local GroupHealth = WowVision.groupHealth
local module = WowVision.base.groupHealth
local speech = WowVision.base.speech

local LOG_MAX = 2000
local ROLE_KEYS = { TANK = "tank", HEALER = "healer", DAMAGER = "damager", NONE = "none" }

local log -- this session's { entries, stats, started }, made on first use
local firstChange = {} -- unit -> time of the first health event since its last turn
local blockedSince = {} -- unit -> time it was first due while speech was busy
local pending = {} -- queue item -> entry, until the item ended
local lastTurn = {} -- unit -> its previous turn's time (the monitor stamps the new one before announcing)

local function clock()
    local now = GetTime()
    return date("%H:%M:%S") .. string.format(".%02d", math.floor((now % 1) * 100))
end

local function session()
    if log ~= nil then
        return log
    end
    WowVisionDump = WowVisionDump or {}
    local saved = WowVisionDump.groupHealthLog
    if type(saved) ~= "table" then
        saved = {}
    end
    log = {
        started = date("%Y-%m-%d %H:%M:%S"),
        entries = {},
        stats = { healthEvents = {}, turns = 0, sent = 0, fights = 0 },
    }
    WowVisionDump.groupHealthLog = { current = log, previous = saved.current }
    return log
end

local function add(entry)
    local entries = session().entries
    entry.at = clock()
    entry.time = GetTime()
    tinsert(entries, entry)
    while #entries > LOG_MAX do
        tremove(entries, 1)
    end
    return entry
end

local function interval(member)
    local values = module.settings[ROLE_KEYS[member.role] or "none"]
    local value = values ~= nil and values.repeatInterval or nil
    return value or 3
end

-- Whether the repeat would pick this member now, were the line free
-- (module:checkRepeats and GroupHealth.mostOverdue).
local function due(member, now)
    if module.settings.repeatOnlyAfterChange and not member.changed then
        return false
    end
    local every = interval(member)
    if every == nil or every <= 0 then
        return false
    end
    return member.lastRepeat == nil or now - member.lastRepeat >= every
end

local function round(x)
    if x == nil then
        return nil
    end
    return math.floor(x * 100 + 0.5) / 100
end

-- Wraps ----------------------------------------------------------------------------

local onHealth = module.onHealth
function module:onHealth(unit)
    local member = self:memberFor(unit)
    if member ~= nil then
        local stats = session().stats
        stats.healthEvents[member.number] = (stats.healthEvents[member.number] or 0) + 1
        if firstChange[member.unit] == nil then
            firstChange[member.unit] = GetTime()
        end
    end
    return onHealth(self, unit)
end

local checkRepeats = module.checkRepeats
function module:checkRepeats()
    for _, member in pairs(self.members) do
        lastTurn[member.unit] = member.lastRepeat
    end
    if not self:silenced() and not speech:idle() then
        local now = GetTime()
        for _, member in pairs(self.members) do
            if blockedSince[member.unit] == nil and not member.dead and due(member, now) then
                blockedSince[member.unit] = now
            end
        end
    end
    return checkRepeats(self)
end

local announce = module.announce
function module:announce(member, lane)
    local now = GetTime()
    local entry = {
        what = "turn",
        lane = lane,
        number = member.number,
        role = member.role,
        unit = member.unit,
        combat = InCombatLockdown() and true or false,
        sinceChange = firstChange[member.unit] ~= nil and round(now - firstChange[member.unit]) or nil,
        heldBySpeech = blockedSince[member.unit] ~= nil and round(now - blockedSince[member.unit]) or 0,
        sinceLastTurn = lane == "repeat" and lastTurn[member.unit] ~= nil and round(now - lastTurn[member.unit]) or nil,
        queueBefore = #speech.queue,
        speakingBefore = speech.speaking and true or false,
    }
    firstChange[member.unit] = nil
    blockedSince[member.unit] = nil
    local current = speech.current
    local queued = #speech.queue
    local sent = announce(self, member, lane)
    local stats = session().stats
    stats.turns = stats.turns + 1
    entry.sent = sent and true or false
    if sent then
        stats.sent = stats.sent + 1
        -- The item the queue made of it: sent at once, or waiting last.
        local item
        if speech.current ~= current then
            item = speech.current
        elseif #speech.queue > queued then
            item = speech.queue[#speech.queue]
        end
        if item ~= nil then
            pending[item] = entry
            if speech.current == item then
                entry.sentAfter = 0
            end
        else
            entry.noQueue = true
        end
    end
    add(entry)
    return sent
end

-- Queue items and playback ------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_STARTED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event)
    if event == "VOICE_CHAT_TTS_PLAYBACK_STARTED" then
        local entry = speech.current ~= nil and pending[speech.current] or nil
        if entry ~= nil and entry.startedAfter == nil then
            entry.startedAfter = round(GetTime() - entry.time)
        end
    elseif not module.enabled then
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        local stats = session().stats
        stats.fights = stats.fights + 1
        local members = 0
        for _ in pairs(module.members) do
            members = members + 1
        end
        add({ what = "fight start", members = members })
    else
        add({ what = "fight end" })
    end
end)
frame:SetScript("OnUpdate", function()
    if next(pending) == nil then
        return
    end
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
            -- Dropped by a stop before it was sent.
            entry.dropped = true
            pending[item] = nil
        end
    end
end)

-- Summary ----------------------------------------------------------------------------

local function median(list)
    if #list == 0 then
        return nil
    end
    table.sort(list)
    return list[math.ceil(#list / 2)]
end

local function p90(list)
    if #list == 0 then
        return nil
    end
    table.sort(list)
    return list[math.ceil(#list * 0.9)]
end

local function fmt(x)
    return x ~= nil and string.format("%.2f s", x) or "none"
end

local function summary(which)
    local saved = WowVisionDump and WowVisionDump.groupHealthLog or nil
    local data = saved ~= nil and saved[which] or nil
    if data == nil then
        return { "WowVision group health log: nothing recorded (" .. which .. ")" }
    end
    local sinceChange, held, length, waitSend, start = {}, {}, {}, {}, {}
    local dropped, combatTurns = 0, 0
    for _, entry in ipairs(data.entries) do
        if entry.what == "turn" then
            if entry.combat then
                combatTurns = combatTurns + 1
            end
            if entry.sinceChange ~= nil then
                tinsert(sinceChange, entry.sinceChange)
            end
            tinsert(held, entry.heldBySpeech or 0)
            if entry.sentAfter ~= nil then
                tinsert(waitSend, entry.sentAfter)
            end
            if entry.startedAfter ~= nil then
                tinsert(start, entry.startedAfter)
            end
            if entry.endedAfter ~= nil and entry.sentAfter ~= nil then
                tinsert(length, entry.endedAfter - entry.sentAfter)
            end
            if entry.dropped then
                dropped = dropped + 1
            end
        end
    end
    local events = 0
    for _, count in pairs(data.stats.healthEvents) do
        events = events + count
    end
    local lines = {
        "WowVision group health log (" .. which .. ", since " .. data.started .. "): " .. data.stats.turns .. " turns ("
            .. combatTurns .. " in combat, " .. data.stats.sent .. " sent, " .. dropped .. " dropped by a stop), "
            .. events .. " health events, " .. data.stats.fights .. " fights",
        "From the first health change to the turn: median " .. fmt(median(sinceChange)) .. ", 90 percent within "
            .. fmt(p90(sinceChange)),
        "Held back by other speech: median " .. fmt(median(held)) .. ", 90 percent within " .. fmt(p90(held)),
        "Turn to sent: median " .. fmt(median(waitSend)) .. "; turn to playing: median " .. fmt(median(start)),
        "Announcement length on the line: median " .. fmt(median(length)) .. ", 90 percent within " .. fmt(p90(length)),
    }
    return lines
end

module:registerCommand({
    name = "ghlog",
    scope = "WowVision",
    description = "Group health monitor measurement: summary of this session (ghlog previous: the one before)",
    func = function(args)
        local which = (type(args) == "string" and args:find("prev")) and "previous" or "current"
        for _, line in ipairs(summary(which)) do
            print(line)
        end
    end,
})
