-- Group health probe (developer tool, /wv ghprobe): checks in game what the
-- group health monitor's readback (retail/groupHealth/readback.lua) rests
-- on. Separate from the monitor: it only uses the monitor's public pieces
-- and can be left out without the monitor noticing.
--
-- /wv ghprobe check [voice]   samples of fixed levels (no health): twelve
--                              pairs of digits (does each read back as
--                              called, the lower utterance id the first
--                              digit?) and the sixteen levels one utterance
--                              uses (up to 1.8 seconds); do the played
--                              times lie on the readback's fixed line on
--                              this machine and voice, the long ones too?
-- /wv ghprobe watch [voice] [unit]
--                              toggles: a readback in ten percent steps on one
--                              unit (default you), woken by its health events;
--                              each new step is said with the true percent,
--                              which only the engine can speak
-- /wv ghprobe flood [voice]   10, 20, 40, then 80 silent utterances in one
--                              frame each: how many the engine starts and
--                              finishes, and whether they still play their
--                              length
-- /wv ghprobe events [seconds] counts health and power events per unit
--
-- Results go to chat, a results window and WowVisionDump.groupHealthProbe
-- (saved at the next /reload). The voice defaults to 0: the readback's
-- fixed values were measured on real SAPI voices.

local GroupHealth = WowVision.groupHealth
local R = GroupHealth.readbackConstants

-- The first sample only after our own announcement has ended.
local START_DELAY = 2.5

local function chat(text)
    for line in tostring(text):gmatch("[^\n]+") do
        print("WowVision probe: " .. line)
    end
end

local function say(text)
    chat(text)
    WowVision:speak(text)
end

local function round(x)
    return math.floor(x + 0.5)
end

local function framerate()
    local ok, fps = pcall(GetFramerate)
    if ok and type(fps) == "number" then
        return round(fps) .. " fps"
    end
    return "fps unknown"
end

-- A finished run: chat, the results window and the dump (the last six).
local function report(name, lines)
    WowVisionDump = WowVisionDump or {}
    local runs = WowVisionDump.groupHealthProbe or {}
    tinsert(runs, { name = name, at = date("%Y-%m-%d %H:%M:%S"), lines = lines })
    while #runs > 6 do
        tremove(runs, 1)
    end
    WowVisionDump.groupHealthProbe = runs
    local text = table.concat(lines, "\n")
    chat(text)
    WowVision.testing.showResults(text)
end

local function monitor()
    return WowVision.base.groupHealth
end

-- Speech straight to the engine beside the queue, as the monitor speaks.
local function speakAside(voice, text, rate, volume)
    WowVision.base.speech:speakAside(voice, text, rate, volume)
end

-- Curves ------------------------------------------------------------------------

local curves = {}

local function curveFor(points)
    local key = GroupHealth.pointsKey(points)
    if curves[key] == nil then
        local curve = C_CurveUtil.CreateCurve()
        curve:SetType(Enum.LuaCurveType.Step)
        for _, point in ipairs(points) do
            curve:AddPoint(point[1], point[2])
        end
        curves[key] = curve
    end
    return curves[key]
end

local function through(unit, points)
    local ok, value = pcall(UnitHealthPercent, unit, true, curveFor(points))
    if ok then
        return value
    end
    return nil
end

local PERCENT_POINTS = {}
for k = 0, 100 do
    tinsert(PERCENT_POINTS, { k / 100, k })
end

-- Ten percent steps (step k from k/10, full health is step 10).
local STEP_POINTS = {}
for k = 0, 10 do
    tinsert(STEP_POINTS, { k / 10, k })
end
local stepPlan = GroupHealth.readbackPlan("steps", 4, STEP_POINTS)

local function stepText(step)
    if step >= 10 then
        return "100 percent"
    end
    return (step * 10) .. " to " .. (step * 10 + 9) .. " percent"
end

-- Readbacks ---------------------------------------------------------------------

-- The probe's readbacks share the monitor's slot line (the default), so
-- they may run beside it. Each gets the engine's events and stops here.
local active = {}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_STARTED")
eventFrame:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FINISHED")
eventFrame:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FAILED")
eventFrame:SetScript("OnEvent", function(_, event, utteranceID)
    for readback in pairs(active) do
        if event == "VOICE_CHAT_TTS_PLAYBACK_STARTED" then
            readback:onStarted(utteranceID)
        else
            readback:onFinished(utteranceID, event == "VOICE_CHAT_TTS_PLAYBACK_FAILED")
        end
    end
end)

hooksecurefunc(C_VoiceChat, "StopSpeakingText", function()
    for readback in pairs(active) do
        readback:onStop()
    end
end)

-- env: as Readback takes it; now, after, speak, nextCount and the health
-- through a curve are filled in (the monitor's counter: no padding of ours
-- may repeat one of the monitor's).
local function newReadback(voice, env)
    env.now = debugprofilestop
    env.after = C_Timer.After
    env.speak = function(text)
        speakAside(voice, text, R.RATE, 0)
    end
    env.nextCount = function()
        return monitor():nextCount()
    end
    env.through = env.through or through
    local readback = GroupHealth.Readback:new(env)
    active[readback] = true
    return readback
end

local function readbackSummary(readback)
    local stats = readback.stats
    local thrown = {}
    for why, n in pairs(stats.discarded) do
        tinsert(thrown, why .. " " .. n)
    end
    table.sort(thrown)
    return string.format(
        "%d samples, %d readings used, thrown away: %s; most at once %d",
        stats.samples, stats.readings, #thrown > 0 and table.concat(thrown, ", ") or "none", stats.maxInflight
    )
end

local busy = nil

local function start(name)
    if busy ~= nil then
        say("Probe busy: " .. busy)
        return false
    end
    if C_CurveUtil == nil or UnitHealthPercent == nil then
        say("This client has no curves, the probe cannot run")
        return false
    end
    busy = name
    return true
end

-- Check -------------------------------------------------------------------------

-- Every pair of digits a plan of base 4 can hold once in each order where
-- they differ: twelve samples, three to a slot as in a fight.
local CHECK_PAIRS = { { 0, 3 }, { 3, 0 }, { 1, 2 }, { 2, 1 }, { 0, 0 }, { 3, 3 }, { 0, 1 }, { 1, 0 }, { 2, 3 }, { 3, 2 }, { 1, 1 }, { 2, 2 } }
-- The sixteen levels of one utterance (R.SINGLE_LEVELS), value by value.
local CHECK_WAIT = 10

-- Least squares line through { level, playedMs }: played = a + b * level.
local function fitLine(points)
    local n = #points
    if n < 2 then
        return nil
    end
    local sx, sy = 0, 0
    for _, p in ipairs(points) do
        sx, sy = sx + p[1], sy + p[2]
    end
    local mx, my = sx / n, sy / n
    local sxx, sxy = 0, 0
    for _, p in ipairs(points) do
        sxx = sxx + (p[1] - mx) ^ 2
        sxy = sxy + (p[1] - mx) * (p[2] - my)
    end
    if sxx == 0 then
        return nil
    end
    local b = sxy / sxx
    return my - b * mx, b
end

local function runCheck(voice)
    if not start("check") then
        return
    end
    local pairsByUnit, singleByUnit = {}, {}
    local right, wrong, discards, played = 0, 0, {}, {}
    local singleRight, singleWrong = 0, 0
    local worst, worstSingle = 0, 0
    local readback
    readback = newReadback(voice, {
        -- Fixed levels instead of health: the unit names them.
        through = function(unit, _, digit)
            if singleByUnit[unit] ~= nil then
                return R.SILENCE_OFFSET + R.SINGLE_LEVELS[singleByUnit[unit] + 1] * R.LEVEL_SILENCE
            end
            return R.SILENCE_OFFSET + pairsByUnit[unit][digit] * R.LEVEL_SILENCE
        end,
        onReading = function(unit, reading)
            local value = singleByUnit[unit]
            if value ~= nil then
                local level = R.SINGLE_LEVELS[value + 1]
                if reading.value == value then
                    singleRight = singleRight + 1
                else
                    singleWrong = singleWrong + 1
                end
                tinsert(played, { level, reading.playedHigh })
                worstSingle = math.max(worstSingle, math.abs(reading.rawHigh - level))
                return
            end
            local pair = pairsByUnit[unit]
            if reading.value == pair[1] * 4 + pair[2] then
                right = right + 1
            else
                wrong = wrong + 1
            end
            tinsert(played, { pair[1], reading.playedHigh })
            tinsert(played, { pair[2], reading.playedLow })
            worst = math.max(worst, math.abs(reading.rawHigh - pair[1]), math.abs(reading.rawLow - pair[2]))
        end,
        onDiscard = function(unit, why)
            tinsert(discards, why)
        end,
        -- No retries: every sample counts once.
        rerequest = function() end,
    })
    say("Probe check, silent, about ten seconds")
    C_Timer.After(START_DELAY, function()
        for i, pair in ipairs(CHECK_PAIRS) do
            local unit = "check" .. i
            pairsByUnit[unit] = pair
            readback:request(unit, { plan = GroupHealth.zoomPlan(0, 100, "pair") })
        end
        local single = GroupHealth.zoomPlan(0, 100, "single")
        for value = 0, #R.SINGLE_LEVELS - 1 do
            local unit = "single" .. value
            singleByUnit[unit] = value
            readback:request(unit, { plan = single })
        end
        C_Timer.After(CHECK_WAIT, function()
            active[readback] = nil
            busy = nil
            local lines = { string.format("Check, voice %d, %s", voice, framerate()) }
            tinsert(lines, string.format("Pairs: %d of %d read as called, %d read wrong; one utterance: %d of %d levels read as called, %d read wrong; thrown away: %s",
                right, #CHECK_PAIRS, wrong, singleRight, #R.SINGLE_LEVELS, singleWrong, #discards > 0 and table.concat(discards, ", ") or "none"))
            local a, b = fitLine(played)
            if a ~= nil then
                tinsert(lines, string.format("Played = %d ms + %.1f ms per level over levels 0 to 16 (fixed values: %d + %.1f); worst %.2f of a level off in pairs, %.2f in one utterance (allowed %.2f)",
                    round(a), b, R.BASE_MS, R.LEVEL_MS, worst, worstSingle, R.MAX_OFF_LEVEL))
            end
            local fits = wrong == 0 and right > 0 and singleWrong == 0 and singleRight > 0
                and worst <= R.MAX_OFF_LEVEL and worstSingle <= R.MAX_OFF_LEVEL
            tinsert(lines, fits and "The readback fits this machine and voice" or "The readback does NOT fit this machine and voice")
            report("check", lines)
            say(lines[#lines])
        end)
    end)
end

-- Watch -------------------------------------------------------------------------

local watch = nil

local watchFrame = CreateFrame("Frame")
watchFrame:SetScript("OnEvent", function(_, _, unit)
    if watch ~= nil and unit == watch.unit then
        watch.events = watch.events + 1
        watch.readback:request(unit)
    end
end)

local function stopWatch()
    local w = watch
    watch = nil
    busy = nil
    watchFrame:UnregisterAllEvents()
    active[w.readback] = nil
    tinsert(w.lines, string.format("Watch off after %d seconds: %d health events, %d step changes; %s",
        round(GetTime() - w.startedAt), w.events, w.changes, readbackSummary(w.readback)))
    report("watch", w.lines)
    say(w.lines[#w.lines])
end

local function toggleWatch(voice, unit)
    if watch ~= nil then
        stopWatch()
        return
    end
    if not start("watch") then
        return
    end
    local w = { unit = unit, events = 0, changes = 0, startedAt = GetTime(), lines = {} }
    tinsert(w.lines, string.format("Watch on %s, voice %d, %s", unit, voice, framerate()))
    w.readback = newReadback(voice, {
        plan = function()
            return stepPlan
        end,
        onReading = function(u, reading)
            if watch ~= w or reading.value == w.step then
                return
            end
            w.step = reading.value
            w.changes = w.changes + 1
            local text = u .. " " .. stepText(reading.value)
            local raws = reading.rawLow ~= nil and string.format("digits %.2f and %.2f", reading.rawHigh, reading.rawLow)
                or string.format("level %.2f", reading.rawHigh)
            tinsert(w.lines, string.format("%.1f %s, %s, %.2f s after the call",
                GetTime(), text, raws, (debugprofilestop() - reading.calledMs) / 1000))
            chat(text)
            -- The truth, which only the engine can say; in a slot of the
            -- line, so its start is known as ours.
            local percent = through(u, PERCENT_POINTS)
            if percent ~= nil then
                local rate = WowVision.base.speech.settings.speechRate
                w.readback:speakOwn(function()
                    speakAside(voice, text .. ", true " .. percent .. " percent" .. GroupHealth.uniquePad(monitor():nextCount()), rate, 100)
                end)
            end
        end,
        onDiscard = function(u, why)
            if watch == w then
                tinsert(w.lines, string.format("%.1f %s thrown away: %s", GetTime(), u, why))
            end
        end,
    })
    watch = w
    watchFrame:RegisterEvent("UNIT_HEALTH")
    say("Watch on, unit " .. unit .. ", voice " .. voice)
    C_Timer.After(START_DELAY, function()
        if watch == w then
            w.readback:request(unit)
        end
    end)
end

-- Flood -------------------------------------------------------------------------

-- Many silent utterances called in one frame, as checks and numbers pile up
-- in a fight. Does the engine drop any (no start, no finish), and does each
-- still play its length? Each is 'a' and 1500 ms of silence at the
-- readback's rate and volume 0.
local FLOOD_SIZES = { 10, 20, 40, 80 }
local FLOOD_SILENCE = 1500
local FLOOD_WAIT = 4
local FLOOD_GAP = 5
local flood = nil

local floodFrame = CreateFrame("Frame")
floodFrame:SetScript("OnEvent", function(_, event, utteranceID)
    if flood == nil then
        return
    end
    local now = debugprofilestop()
    if event == "VOICE_CHAT_TTS_PLAYBACK_STARTED" then
        flood.starts[utteranceID] = now
    elseif event == "VOICE_CHAT_TTS_PLAYBACK_FINISHED" then
        flood.finishes[utteranceID] = now
    else
        flood.failed = flood.failed + 1
    end
end)

local function floodSummary(run)
    local started, finished, played, startAfter = 0, 0, {}, {}
    for id, startMs in pairs(run.starts) do
        started = started + 1
        tinsert(startAfter, startMs - run.calledMs)
        if run.finishes[id] ~= nil then
            tinsert(played, run.finishes[id] - startMs)
        end
    end
    for _ in pairs(run.finishes) do
        finished = finished + 1
    end
    table.sort(played)
    table.sort(startAfter)
    local expected = R.BASE_MS + R.LEVEL_MS * (FLOOD_SILENCE - R.SILENCE_OFFSET) / R.LEVEL_SILENCE
    return string.format(
        "%d called in one frame: %d started, %d finished, %d failed; played min %d, median %d, max %d ms (expected about %d); started %d to %d ms after the call",
        run.count, started, finished, run.failed,
        round(played[1] or 0), round(played[math.max(1, math.ceil(#played / 2))] or 0), round(played[#played] or 0),
        round(expected), round(startAfter[1] or 0), round(startAfter[#startAfter] or 0)
    )
end

local function runFlood(voice)
    if not start("flood") then
        return
    end
    floodFrame:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_STARTED")
    floodFrame:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FINISHED")
    floodFrame:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FAILED")
    local lines = { string.format("Flood, voice %d, %s", voice, framerate()) }
    say("Flood test, silent. Keep still, about 25 seconds")
    local index = 0
    local function nextRound()
        index = index + 1
        local count = FLOOD_SIZES[index]
        if count == nil then
            floodFrame:UnregisterAllEvents()
            busy = nil
            report("flood", lines)
            say("Flood test done")
            return
        end
        flood = { count = count, calledMs = debugprofilestop(), starts = {}, finishes = {}, failed = 0 }
        for _ = 1, count do
            speakAside(voice, 'a<silence msec="' .. FLOOD_SILENCE .. '"/>' .. GroupHealth.readbackPad(monitor():nextCount()), R.RATE, 0)
        end
        C_Timer.After(FLOOD_WAIT, function()
            tinsert(lines, floodSummary(flood))
            flood = nil
            C_Timer.After(FLOOD_GAP - FLOOD_WAIT, nextRound)
        end)
    end
    C_Timer.After(START_DELAY, nextRound)
end

-- Events ------------------------------------------------------------------------

local COUNTED_EVENTS = { "UNIT_HEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT" }
local counts = nil

local countFrame = CreateFrame("Frame")
countFrame:SetScript("OnEvent", function(_, event, unit)
    if counts == nil then
        return
    end
    local key = tostring(unit)
    if key:match("^nameplate%d+$") then
        key = "nameplates"
    end
    key = event .. " " .. key
    local now = GetTime()
    local row = counts[key] or { count = 0 }
    counts[key] = row
    if row.last ~= nil then
        local gap = now - row.last
        row.minGap = math.min(row.minGap or gap, gap)
        row.maxGap = math.max(row.maxGap or gap, gap)
    end
    row.count = row.count + 1
    row.last = now
end)

local function countEvents(seconds)
    if counts ~= nil then
        say("Already counting")
        return
    end
    counts = {}
    for _, event in ipairs(COUNTED_EVENTS) do
        countFrame:RegisterEvent(event)
    end
    say("Counting health and power events for " .. seconds .. " seconds")
    C_Timer.After(seconds, function()
        countFrame:UnregisterAllEvents()
        local rows = counts
        counts = nil
        local keys = {}
        for key in pairs(rows) do
            tinsert(keys, key)
        end
        table.sort(keys)
        local lines = { "Events in " .. seconds .. " seconds, in combat at the end: " .. tostring(InCombatLockdown()) }
        for _, key in ipairs(keys) do
            local row = rows[key]
            tinsert(lines, string.format("%s: %d, %.1f per second, gaps %s to %s", key, row.count, row.count / seconds,
                row.minGap ~= nil and string.format("%.2f s", row.minGap) or "-",
                row.maxGap ~= nil and string.format("%.2f s", row.maxGap) or "-"))
        end
        if #keys == 0 then
            tinsert(lines, "no events")
        end
        report("events", lines)
        say("Event count done")
    end)
end

-- Command -----------------------------------------------------------------------

WowVision.base:registerCommand({
    name = "ghprobe",
    description = "Group health probe: 'check [voice]' tests the readback's fixed timing on this machine, 'watch [voice] [unit]' toggles ten percent step readings on a unit, 'flood [voice]' counts how many silent utterances at once the engine plays, 'events [seconds]' counts health and power events",
    func = function(args)
        local words = {}
        for word in tostring(args or ""):lower():gmatch("%S+") do
            tinsert(words, word)
        end
        local command = words[1]
        local voice = tonumber(words[2]) or 0
        if command == "check" then
            runCheck(voice)
        elseif command == "watch" then
            local unit = words[3] or (tonumber(words[2]) == nil and words[2]) or "player"
            toggleWatch(voice, unit)
        elseif command == "flood" then
            runFlood(voice)
        elseif command == "events" then
            countEvents(tonumber(words[2]) or 30)
        else
            say("Usage: slash w v g h probe check, watch, flood, or events")
        end
    end,
})
