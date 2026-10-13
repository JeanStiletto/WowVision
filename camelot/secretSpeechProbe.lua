-- Secret speech probe (diagnostic, WoW: Forever).
--
-- Question: can a SECRET value steer HOW the engine speaks, without the
-- addon ever learning the value? Two engine facts make it plausible:
--
-- 1. UnitHealthPercent(unit, usePredicted, curve) takes a curve object that
--    WE build. The engine reads the real health, runs it through our curve
--    and hands back the result as a new secret. We never see the health or
--    the result, but the lookup table (health range -> number) is ours.
-- 2. A secret survives concatenation, and C_VoiceChat.SpeakText accepts
--    secret text with SAPI XML tags. So the secret result can become the
--    number inside a <pitch absmiddle="..."> or <volume level="..."> tag.
--
-- /wv sprobe run [voiceID] [unit]  fifteen steps, each names itself (ten
--                                   speech, five beacon sounds); say what you hear
-- /wv sprobe events [seconds]      counts health and power events per unit
-- /wv sprobe monitor [voiceID] [percent]
--                                   toggles a Sku-style party health monitor:
--                                   party number (player 1, party1-4 = 2-5),
--                                   higher pitch the more damaged, silent at
--                                   or above the percent (default 90)
-- /wv sprobe log                    every recorded step with engine statuses;
--                                   /reload writes it to WowVisionDump
-- /wv sprobe timing [voiceID] [unit]
--                                   silent utterances at rate 10: does the
--                                   played time carry a health bucket back?
--                                   (see "Timing readback" below)
-- /wv sprobe twatch [voiceID] [unit]
--                                   toggles: the group health monitor's step
--                                   readback on one unit, woken by its health
--                                   events; says each new step followed by the
--                                   true percent (engine-spoken secret)
-- /wv sprobe tpar [count]          samples your health count times at once
--                                   (default 5, at most 20): does the engine
--                                   play that many side by side?
-- /wv sprobe tpair                  two-digit samples: is the lower utterance
--                                   id the first call? Then your health
--
-- Speech goes straight to the engine's own SpeakText, captured here at file
-- load, before the speech module's queue replaces the global (that happens on
-- enable). The queue's foreign-text buster may put no-break spaces BEFORE the
-- text, which could stop the engine detecting the text as XML; the probe
-- busts its own texts inside the tags instead (see step four).

local engineSpeak = C_VoiceChat.SpeakText

local probe = {
    entries = {},
    rawEvents = {},
    registerErrors = {},
    eventCounts = nil,
    monitor = nil,
}
WowVision.secretSpeechProbe = probe

local MAX_ENTRIES = 80
local STEP_SECONDS = 3.5
local NBSP = "\194\160"
local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local PARTY_INDEX = { player = 1, party1 = 2, party2 = 3, party3 = 4, party4 = 5 }

local isSecret = WowVision.secrets.isSecret

-- Bust the engine's audio cache from the inside of the tags: trailing
-- no-break spaces are inaudible, and the engine keys its cache after
-- stripping markup, so two pitches of one word would otherwise collide.
local bustRun = 0
local function bust()
    bustRun = bustRun % 64 + 1
    return string.rep(NBSP, bustRun)
end

local statusNames = {}
if Enum ~= nil and Enum.VoiceTtsStatusCode ~= nil then
    for name, value in pairs(Enum.VoiceTtsStatusCode) do
        statusNames[value] = name
    end
end

local function statusName(code)
    return statusNames[code] or tostring(code)
end

local function speechSettings()
    local speech = WowVision.base ~= nil and WowVision.base.speech or nil
    local settings = speech ~= nil and speech.settings or nil
    local voice = settings ~= nil and settings.voiceID or 0
    local rate = settings ~= nil and settings.speechRate or 0
    local volume = settings ~= nil and settings.speechVolume or 100
    return voice, rate, math.max(0, math.min(100, volume))
end

-- Every probe result is printed to chat as well as spoken: chat can be
-- reread and copied afterwards, speech is gone once heard.
local function chat(text)
    for line in tostring(text):gmatch("[^\n]+") do
        print("WowVision probe: " .. line)
    end
end

local function say(text)
    chat(text)
    if WowVision.base ~= nil and WowVision.base.speech ~= nil then
        WowVision:speak(text)
    end
end

-- Curves ----------------------------------------------------------------------

local function stepCurve(points)
    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    for _, point in ipairs(points) do
        curve:AddPoint(point[1], point[2])
    end
    return curve
end

local curves = nil

-- Built on first use: C_CurveUtil may not exist at file load on every client.
local function getCurves()
    if curves ~= nil then
        return curves
    end
    local percent = {}
    for i = 0, 100 do
        tinsert(percent, { i / 100, i })
    end
    -- Sku style: the more damaged, the higher. Ten steps of ten percent.
    local pitch = {}
    for i = 0, 9 do
        tinsert(pitch, { i / 10, 10 - 2 * i })
    end
    tinsert(pitch, { 1.0, -10 })
    -- Beacon distance 1 (near) when badly damaged up to 30 (far) at full.
    local distance = {}
    for i = 0, 9 do
        tinsert(distance, { i / 10, 1 + 3 * i })
    end
    tinsert(distance, { 1.0, 30 })
    curves = {
        percent = stepCurve(percent),
        pitch = stepCurve(pitch),
        constLow = stepCurve({ { 0, -10 }, { 1, -10 } }),
        constHigh = stepCurve({ { 0, 10 }, { 1, 10 } }),
        constZero = stepCurve({ { 0, 0 }, { 1, 0 } }),
        constNear = stepCurve({ { 0, 1 }, { 1, 1 } }),
        constFar = stepCurve({ { 0, 30 }, { 1, 30 } }),
        distance = stepCurve(distance),
        belowHalf = stepCurve({ { 0, 100 }, { 0.5, 0 } }),
        aboveHalf = stepCurve({ { 0, 0 }, { 0.5, 100 } }),
        gates = {},
    }
    return curves
end

-- Volume 100 below the threshold, 0 at or above it.
local function gateCurve(threshold)
    local c = getCurves()
    if c.gates[threshold] == nil then
        c.gates[threshold] = stepCurve({ { 0, 100 }, { threshold, 0 } })
    end
    return c.gates[threshold]
end

local function healthThrough(unit, curve)
    return UnitHealthPercent(unit, true, curve)
end

-- Recording -------------------------------------------------------------------

local pending = nil

local function record(entry)
    tinsert(probe.entries, entry)
    while #probe.entries > MAX_ENTRIES do
        tremove(probe.entries, 1)
    end
end

-- Speaks through the engine and records what the engine reports back.
-- `secrets` lists the values that went into the text, to log which were secret.
local function speak(label, voice, buildText, secrets, overlap)
    local entry = {
        label = label,
        voice = voice,
        calledAt = GetTime(),
        statuses = {},
    }
    record(entry)
    local okBuild, text = pcall(buildText)
    if not okBuild then
        entry.error = "build: " .. tostring(text)
        return entry
    end
    local flags = {}
    for _, item in ipairs(secrets or {}) do
        tinsert(flags, item[1] .. "=" .. (isSecret(item[2]) and "secret" or "plain"))
    end
    entry.secrets = table.concat(flags, ", ")
    entry.textSecret = isSecret(text)
    local _, rate, volume = speechSettings()
    pending = entry
    local okSpeak, err = pcall(engineSpeak, voice, text, rate, volume, overlap == true)
    if not okSpeak then
        entry.error = "speak: " .. tostring(err)
    end
    if entry.utteranceID == nil then
        entry.noSyncUpdate = true
    end
    return entry
end

local byUtterance = {}

local ttsFrame = CreateFrame("Frame")
for _, event in ipairs({
    "VOICE_CHAT_TTS_SPEAK_TEXT_UPDATE",
    "VOICE_CHAT_TTS_PLAYBACK_STARTED",
    "VOICE_CHAT_TTS_PLAYBACK_FINISHED",
    "VOICE_CHAT_TTS_PLAYBACK_FAILED",
}) do
    local ok, err = pcall(ttsFrame.RegisterEvent, ttsFrame, event)
    if not ok then
        tinsert(probe.registerErrors, event .. ": " .. tostring(err))
    end
end

-- Every engine speech event, ours or not, so the log shows which events this
-- client actually sends (the first in-game run matched none of them).
local MAX_RAW = 120
local function rawEvent(now, event, a, b)
    tinsert(probe.rawEvents, string.format("%.3f %s %s %s", now, event, tostring(a), tostring(b)))
    while #probe.rawEvents > MAX_RAW do
        tremove(probe.rawEvents, 1)
    end
end

ttsFrame:SetScript("OnEvent", function(_, event, a, b)
    local now = GetTime()
    rawEvent(now, event, a, b)
    if event == "VOICE_CHAT_TTS_SPEAK_TEXT_UPDATE" then
        local status, utteranceID = a, b
        local entry = byUtterance[utteranceID]
        if entry == nil and pending ~= nil and pending.utteranceID == nil then
            entry = pending
            entry.utteranceID = utteranceID
            byUtterance[utteranceID] = entry
            pending = nil
        end
        if entry ~= nil then
            tinsert(entry.statuses, statusName(status))
        end
        return
    end
    local entry = byUtterance[a]
    -- No text update came for our call: the first unknown start is ours.
    if entry == nil and event == "VOICE_CHAT_TTS_PLAYBACK_STARTED" and pending ~= nil and pending.utteranceID == nil then
        entry = pending
        entry.utteranceID = a
        entry.mappedByStart = true
        byUtterance[a] = entry
        pending = nil
    end
    if entry == nil then
        return
    end
    if event == "VOICE_CHAT_TTS_PLAYBACK_STARTED" then
        entry.startedAt = now
    elseif event == "VOICE_CHAT_TTS_PLAYBACK_FINISHED" then
        entry.finishedAt = now
    else
        entry.failedAt = now
        entry.failStatus = statusName(b)
    end
end)

local function ms(from, to)
    if from == nil or to == nil then
        return "-"
    end
    return tostring(math.floor((to - from) * 1000 + 0.5)) .. " ms"
end

local function entryLine(entry)
    if entry.marker then
        return entry.label
    end
    local parts = { entry.label, "voice " .. tostring(entry.voice) }
    if entry.secrets ~= nil and entry.secrets ~= "" then
        tinsert(parts, entry.secrets)
    end
    if entry.textSecret ~= nil then
        tinsert(parts, "text " .. (entry.textSecret and "secret" or "plain"))
    end
    if entry.error ~= nil then
        tinsert(parts, "ERROR " .. entry.error)
    end
    if entry.sound == nil then
        tinsert(parts, "utterance " .. tostring(entry.utteranceID))
    end
    if #entry.statuses > 0 then
        tinsert(parts, "status " .. table.concat(entry.statuses, " "))
    end
    if entry.mappedByStart then
        tinsert(parts, "matched by its start, no text update")
    elseif entry.noSyncUpdate and entry.utteranceID ~= nil then
        tinsert(parts, "update came late")
    end
    if entry.sound ~= nil then
        tinsert(parts, entry.sound)
        return table.concat(parts, "; ")
    end
    tinsert(parts, "start after " .. ms(entry.calledAt, entry.startedAt))
    if entry.failedAt ~= nil then
        tinsert(parts, "FAILED " .. tostring(entry.failStatus) .. " after " .. ms(entry.calledAt, entry.failedAt))
    else
        tinsert(parts, "played " .. ms(entry.startedAt, entry.finishedAt))
    end
    return table.concat(parts, "; ")
end

-- The ten steps ---------------------------------------------------------------

local BEACON = "Interface/AddOns/WowVision/audio/beacons/probe_mid_1/probe_mid_1;0;"

local function describe(value)
    if isSecret(value) then
        return "secret"
    end
    return tostring(value)
end

-- Plays a sound file whose path may be secret, and records what came back.
local function playSound(label, buildPath, secrets)
    local entry = { label = label, voice = "-", calledAt = GetTime(), statuses = {} }
    record(entry)
    local flags = {}
    for _, item in ipairs(secrets or {}) do
        tinsert(flags, item[1] .. "=" .. (isSecret(item[2]) and "secret" or "plain"))
    end
    entry.secrets = table.concat(flags, ", ")
    local okBuild, path = pcall(buildPath)
    if not okBuild then
        entry.error = "build: " .. tostring(path)
        return
    end
    entry.textSecret = isSecret(path)
    local ok, willPlay, handle = pcall(PlaySoundFile, path, "Master")
    if not ok then
        entry.error = "play: " .. tostring(willPlay)
        return
    end
    entry.sound = "willPlay " .. describe(willPlay) .. ", handle " .. describe(handle)
end

local function buildSteps(unit)
    local c = getCurves()
    local function h(curve)
        return healthThrough(unit, curve)
    end
    return {
        {
            label = "1 plain pitch low",
            text = function()
                return '<pitch absmiddle="-10">one, low pitch' .. bust() .. "</pitch>"
            end,
        },
        {
            label = "2 plain pitch high",
            text = function()
                return '<pitch absmiddle="10">two, high pitch' .. bust() .. "</pitch>"
            end,
        },
        {
            label = "3 plain volume zero",
            text = function()
                return 'three, next word silent, <volume level="0">wrong</volume> done' .. bust()
            end,
        },
        {
            label = "4 plain pitch after a leading space",
            text = function()
                return NBSP .. '<pitch absmiddle="10">four, high pitch after a space' .. bust() .. "</pitch>"
            end,
        },
        {
            label = "5 secret percent, no markup",
            secrets = function()
                return { { "percent", h(c.percent) } }
            end,
            text = function()
                return "five, health " .. h(c.percent) .. " percent" .. bust()
            end,
        },
        {
            label = "6 secret pitch, constant low",
            secrets = function()
                return { { "pitch", h(c.constLow) } }
            end,
            text = function()
                return '<pitch absmiddle="' .. h(c.constLow) .. '">six, low pitch from a secret' .. bust() .. "</pitch>"
            end,
        },
        {
            label = "7 secret pitch, constant high",
            secrets = function()
                return { { "pitch", h(c.constHigh) } }
            end,
            text = function()
                return '<pitch absmiddle="' .. h(c.constHigh) .. '">seven, high pitch from a secret' .. bust() .. "</pitch>"
            end,
        },
        {
            label = "8 secret volume gate at half",
            secrets = function()
                return { { "below", h(c.belowHalf) }, { "above", h(c.aboveHalf) } }
            end,
            text = function()
                return "eight, health is "
                    .. '<volume level="' .. h(c.belowHalf) .. '">below half</volume>'
                    .. '<volume level="' .. h(c.aboveHalf) .. '">above half</volume>'
                    .. bust()
            end,
        },
        {
            label = "9 secret pitch from health",
            secrets = function()
                return { { "pitch", h(c.pitch) } }
            end,
            text = function()
                return '<pitch absmiddle="' .. h(c.pitch) .. '">nine, your health as pitch' .. bust() .. "</pitch>"
            end,
        },
        {
            label = "10 secret volume zero",
            secrets = function()
                return { { "volume", h(c.constZero) } }
            end,
            text = function()
                return 'ten, next word silent, <volume level="' .. h(c.constZero) .. '">wrong</volume> done' .. bust()
            end,
        },
        -- Sound files: the beacon files are named <angle>;<distance>, so a
        -- secret number can pick the distance in the file name.
        {
            label = "11 plain sound, near",
            path = function()
                return BEACON .. "1.mp3"
            end,
        },
        {
            label = "12 plain sound, far",
            path = function()
                return BEACON .. "30.mp3"
            end,
        },
        {
            label = "13 secret sound, constant near",
            secrets = function()
                return { { "distance", h(c.constNear) } }
            end,
            path = function()
                return BEACON .. h(c.constNear) .. ".mp3"
            end,
        },
        {
            label = "14 secret sound, constant far",
            secrets = function()
                return { { "distance", h(c.constFar) } }
            end,
            path = function()
                return BEACON .. h(c.constFar) .. ".mp3"
            end,
        },
        {
            label = "15 secret sound from health",
            secrets = function()
                return { { "distance", h(c.distance) } }
            end,
            path = function()
                return BEACON .. h(c.distance) .. ".mp3"
            end,
        },
    }
end

local running = false

-- Pitch range test: can steps get bigger than the -10..10 of absmiddle
-- allows? Nested relative <pitch middle> on top of absmiddle (does it go
-- beyond 10?), a value past the edge (clamped?), and a fraction (finer
-- steps?). Plain markup only, each line says what it should sound like.
local PITCH_TESTS = {
    { "pitch 1, top of the range", '<pitch absmiddle="10">one, top', "</pitch>" },
    { "pitch 2, top plus 5 nested", '<pitch absmiddle="10"><pitch middle="5">two, above the top?', "</pitch></pitch>" },
    { "pitch 3, top plus 10 nested", '<pitch absmiddle="10"><pitch middle="10">three, even higher?', "</pitch></pitch>" },
    { "pitch 4, absmiddle 15", '<pitch absmiddle="15">four, fifteen', "</pitch>" },
    { "pitch 5, bottom of the range", '<pitch absmiddle="-10">five, bottom', "</pitch>" },
    { "pitch 6, bottom minus 5 nested", '<pitch absmiddle="-10"><pitch middle="-5">six, below the bottom?', "</pitch></pitch>" },
    { "pitch 7, absmiddle 2", '<pitch absmiddle="2">seven, two', "</pitch>" },
    { "pitch 8, absmiddle 2.5", '<pitch absmiddle="2.5">eight, two and a half', "</pitch>" },
    { "pitch 9, absmiddle 3", '<pitch absmiddle="3">nine, three', "</pitch>" },
}

local function runPitchTest(voice)
    if running then
        say("Probe already running")
        return
    end
    running = true
    record({ marker = true, label = "pitch test, voice " .. tostring(voice) })
    for index, test in ipairs(PITCH_TESTS) do
        C_Timer.After(index * STEP_SECONDS, function()
            speak(test[1], voice, function()
                return test[2] .. bust() .. test[3]
            end, nil, true)
        end)
    end
    C_Timer.After((#PITCH_TESTS + 1) * STEP_SECONDS, function()
        running = false
        say("Pitch test done")
    end)
    say("Pitch test, voice " .. tostring(voice) .. ". " .. #PITCH_TESTS .. " lines follow")
end

local function runSteps(voice, unit)
    if running then
        say("Probe already running")
        return
    end
    if C_CurveUtil == nil or UnitHealthPercent == nil then
        say("This client has no curves, the probe cannot run")
        return
    end
    running = true
    local steps = buildSteps(unit)
    record({ marker = true, label = "run start, unit " .. unit .. ", voice " .. tostring(voice) .. ", in combat " .. tostring(InCombatLockdown()) })
    for index, step in ipairs(steps) do
        C_Timer.After(index * STEP_SECONDS, function()
            local secrets = nil
            if step.secrets ~= nil then
                local ok, list = pcall(step.secrets)
                secrets = ok and list or { { "secrets error " .. tostring(list), nil } }
            end
            if step.path ~= nil then
                say(step.label:match("^%d+"))
                C_Timer.After(1.2, function()
                    playSound(step.label, step.path, secrets)
                end)
            else
                speak(step.label, voice, step.text, secrets, true)
            end
        end)
    end
    C_Timer.After((#steps + 1) * STEP_SECONDS, function()
        running = false
        say("Probe done. Type slash w v s probe log for the engine statuses")
    end)
    say("Secret speech probe, unit " .. unit .. ", voice " .. tostring(voice) .. ". " .. #steps .. " steps follow")
end

-- Event counting --------------------------------------------------------------

local COUNTED_EVENTS = { "UNIT_HEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT" }

local countFrame = CreateFrame("Frame")
countFrame:SetScript("OnEvent", function(_, event, unit)
    local counts = probe.eventCounts
    if counts == nil then
        return
    end
    local key = tostring(unit)
    if key:match("^nameplate%d+$") then
        key = "nameplates"
    end
    key = event .. " " .. key
    local now = GetTime()
    local row = counts.rows[key]
    if row == nil then
        row = { count = 0 }
        counts.rows[key] = row
    end
    if row.last ~= nil then
        local gap = now - row.last
        row.minGap = row.minGap == nil and gap or math.min(row.minGap, gap)
        row.maxGap = row.maxGap == nil and gap or math.max(row.maxGap, gap)
    end
    row.count = row.count + 1
    row.last = now
end)

local function countEvents(seconds)
    if probe.eventCounts ~= nil then
        say("Already counting")
        return
    end
    probe.eventCounts = { rows = {}, startedAt = GetTime(), seconds = seconds }
    for _, event in ipairs(COUNTED_EVENTS) do
        countFrame:RegisterEvent(event)
    end
    say("Counting health and power events for " .. seconds .. " seconds")
    C_Timer.After(seconds, function()
        countFrame:UnregisterAllEvents()
        local counts = probe.eventCounts
        probe.eventCounts = nil
        local keys = {}
        for key in pairs(counts.rows) do
            tinsert(keys, key)
        end
        table.sort(keys)
        local lines = { "Events in " .. seconds .. " seconds, in combat at the end: " .. tostring(InCombatLockdown()) }
        for _, key in ipairs(keys) do
            local row = counts.rows[key]
            tinsert(
                lines,
                string.format(
                    "%s: %d, %.1f per second, gaps %s to %s",
                    key,
                    row.count,
                    row.count / seconds,
                    row.minGap ~= nil and string.format("%.2f s", row.minGap) or "-",
                    row.maxGap ~= nil and string.format("%.2f s", row.maxGap) or "-"
                )
            )
        end
        if #keys == 0 then
            tinsert(lines, "no events")
        end
        local text = table.concat(lines, "\n")
        WowVisionDump = WowVisionDump or {}
        WowVisionDump.secretProbeEvents = lines
        WowVision.testing.showResults(text)
        say(text)
    end)
end

-- Monitor ---------------------------------------------------------------------

local THROTTLE = 1.0

local monitorFrame = CreateFrame("Frame")

local function monitorSpeak(unit)
    local m = probe.monitor
    if m == nil then
        return
    end
    local state = m.units[unit]
    state.timer = false
    state.lastAt = GetTime()
    -- Either answer could be secret on some unit; a secret cannot be tested,
    -- so only a plain answer may skip the unit.
    local okExists, exists = pcall(UnitExists, unit)
    if okExists and not isSecret(exists) and not exists then
        return
    end
    local okDead, dead = pcall(UnitIsDeadOrGhost, unit)
    if okDead and not isSecret(dead) and dead then
        return
    end
    local index = PARTY_INDEX[unit]
    local c = getCurves()
    local gate = gateCurve(m.threshold)
    m.spoken = m.spoken + 1
    local entry = speak("monitor " .. unit, m.voice, function()
        return '<volume level="'
            .. healthThrough(unit, gate)
            .. '"><pitch absmiddle="'
            .. healthThrough(unit, c.pitch)
            .. '">'
            .. index
            .. bust()
            .. "</pitch></volume>"
    end, nil, true)
    if entry.error ~= nil then
        m.errors = m.errors + 1
        m.lastError = entry.error
    end
end

-- One utterance per unit per THROTTLE; an event inside the window schedules
-- one trailing utterance at its end, which reads the health at that moment.
monitorFrame:SetScript("OnEvent", function(_, _, unit)
    local m = probe.monitor
    if m == nil or PARTY_INDEX[unit] == nil then
        return
    end
    m.events = m.events + 1
    local state = m.units[unit]
    local now = GetTime()
    if state.lastAt == nil or now - state.lastAt >= THROTTLE then
        monitorSpeak(unit)
    elseif not state.timer then
        state.timer = true
        C_Timer.After(THROTTLE - (now - state.lastAt), function()
            monitorSpeak(unit)
        end)
    end
end)

local function toggleMonitor(voice, percent)
    if probe.monitor ~= nil then
        monitorFrame:UnregisterAllEvents()
        local m = probe.monitor
        probe.monitor = nil
        local summary = string.format(
            "Monitor off after %d seconds: %d health events, %d utterances, %d errors%s",
            math.floor(GetTime() - m.startedAt),
            m.events,
            m.spoken,
            m.errors,
            m.lastError ~= nil and (", last error " .. m.lastError) or ""
        )
        WowVisionDump = WowVisionDump or {}
        WowVisionDump.secretProbeMonitor = summary
        say(summary)
        return
    end
    if C_CurveUtil == nil or UnitHealthPercent == nil then
        say("This client has no curves, the monitor cannot run")
        return
    end
    local units = {}
    for _, unit in ipairs(PARTY_UNITS) do
        units[unit] = { timer = false }
    end
    probe.monitor = {
        voice = voice,
        threshold = (percent or 90) / 100,
        units = units,
        events = 0,
        spoken = 0,
        errors = 0,
        startedAt = GetTime(),
    }
    monitorFrame:RegisterEvent("UNIT_HEALTH")
    say("Monitor on, voice " .. tostring(voice) .. ", silent at or above " .. (percent or 90) .. " percent")
end

-- Timing readback -------------------------------------------------------------
--
-- Question: can the TIME an utterance plays carry a health bucket back to the
-- addon? The bucket (ten percent steps) is what the health bar shows every
-- sighted player at one look; only official API is used. Our curve turns the
-- health into a silence length, the engine speaks 'a<silence msec="..."/>' at
-- volume 0 and rate 10, and debugprofilestop() measures PLAYBACK_STARTED to
-- PLAYBACK_FINISHED. A line fitted through plain calibration utterances turns
-- the played time back into the bucket.
--
-- Measured on Forever, first run 2026-10-13 (full health, out of combat):
-- - Volume 0 and a <volume level="0"> tag play in real time, the same as audible speech.
-- - A secret number works inside <silence msec>: secret constants played like
--   the same plain silences.
-- - The speech rate also shortens the silence: at rate 10 the played time grows
--   by about 0.33 ms per ms of silence (about 196 ms + silence / 3).
-- - msec="0" plays LONGER (about 450 ms) than 100 ms of silence; never use it.
-- - The events arrive on frames: repeats spread by about 17 ms (one frame at 60 fps).
-- - The player's health is secret even out of combat.
-- So one bucket is 300 ms of silence (about 100 ms played, several frames).
--
-- Second series (v2, 2026-10-13): a quiet calibration reads every bucket back
-- within 0.27; secret in combat works. But WowVision's own speech stops ALL
-- engine speech (speech:stop calls StopSpeakingText, the queue speaks without
-- overlap), so a sample can end early: one calibration of bucket 10 read 6.7,
-- one watch sample played 16 ms. The fit drops outliers.
--
-- Third series (v3): throwing away every sample with ANY other speech event
-- around it discarded 78 of 84 watch samples, although they read clean: the
-- group health monitor speaks beside us (overlap) all through damage and
-- regeneration and never cuts us. Some samples had adopted its start (called
-- a moment before ours: "start after 21 ms", played 862 ms). Now (v4):
-- - our start is the one start within START_WINDOW_MS of our call; when two
--   start in that window nobody can tell which is ours (the events carry only
--   an id), so the sample is thrown away;
-- - otherwise a sample is disturbed only when something can have cut it: a call of
--   C_VoiceChat.StopSpeakingText (hooked) while it played, or other speech
--   starting right after ours ended (CUT_WINDOW_MS), the mark of an interrupt.
--
-- Fourth series (v4, 2026-10-13): after a death and regeneration to full,
-- every announced step matched the true percent, each heard 0 to 2 percent
-- into the new step. The pooled clean samples of all runs give fixed values
-- (retail/groupHealth/readback.lua), so the watch no longer calibrates: it
-- runs the group health monitor's own readback (v5). A stop ends a sample
-- at once; this timing run stays as the tool to measure another machine.
--
-- The engine keys its audio cache on the text WITHOUT markup, so every
-- utterance gets its own trailing code of no-break spaces and spaces: same
-- length every time, unique per utterance, seeded from the clock because the
-- cache outlives /reload. A cache hit would replay another silence length.

local TIMING_RATE = 10
local SILENCE_OFFSET = 100
local BUCKET_SILENCE = 300
local TIMING_TIMEOUT = 2
local TIMING_GAP = 0.12
local TIMING_START_DELAY = 3
local TIMING_LOG_MAX = 200
local TIMING_RUNS_MAX = 6
-- A calibration point further than this from the fitted line is dropped.
local OUTLIER_BUCKETS = 0.6
-- Our own start comes 35 to 55 ms after the call.
local START_WINDOW_MS = 100
-- Speech starting this soon after ours ended may have cut it.
local CUT_WINDOW_MS = 100

local timing = {
    current = nil,
    foreignStarts = {},
    lastStopMs = nil,
    running = false,
    watch = nil,
    fit = nil,
    lines = {},
    watchLog = {},
}
probe.timing = timing

local timingCode = nil

local function timingBust()
    if timingCode == nil then
        timingCode = (time() * 37) % 65536
    end
    timingCode = (timingCode + 1) % 65536
    local parts = {}
    local value = timingCode
    for _ = 1, 16 do
        tinsert(parts, value % 2 == 1 and (NBSP .. NBSP) or (NBSP .. " "))
        value = math.floor(value / 2)
    end
    return table.concat(parts) .. NBSP
end

local function silenceFor(bucket)
    return SILENCE_OFFSET + bucket * BUCKET_SILENCE
end

-- `ms` may be a secret straight from the curve.
local function silenceText(ms)
    return 'a<silence msec="' .. ms .. '"/>' .. timingBust()
end

local healthCurves = nil

local function getTimingCurves()
    if healthCurves ~= nil then
        return healthCurves
    end
    local health = {}
    for i = 0, 9 do
        tinsert(health, { i / 10, silenceFor(i) })
    end
    tinsert(health, { 1.0, silenceFor(10) })
    healthCurves = {
        health = stepCurve(health),
        bucket3 = stepCurve({ { 0, silenceFor(3) }, { 1, silenceFor(3) } }),
        bucket9 = stepCurve({ { 0, silenceFor(9) }, { 1, silenceFor(9) } }),
    }
    return healthCurves
end

local timingFrame = CreateFrame("Frame")
for _, event in ipairs({
    "VOICE_CHAT_TTS_PLAYBACK_STARTED",
    "VOICE_CHAT_TTS_PLAYBACK_FINISHED",
    "VOICE_CHAT_TTS_PLAYBACK_FAILED",
}) do
    local ok, err = pcall(timingFrame.RegisterEvent, timingFrame, event)
    if not ok then
        tinsert(probe.registerErrors, "timing " .. event .. ": " .. tostring(err))
    end
end

-- The step readbacks running now: the watch's and the parallel test's.
local function activeReadbacks()
    local list = {}
    if timing.watch ~= nil then
        tinsert(list, timing.watch.readback)
    end
    if timing.par ~= nil then
        tinsert(list, timing.par)
    end
    return list
end

-- Every stop of all speech, by anyone: the one thing that cuts us short. A
-- sample out ends at once (no wait for its timeout); the watch and the
-- parallel test hand it to their readback.
if C_VoiceChat.StopSpeakingText ~= nil then
    hooksecurefunc(C_VoiceChat, "StopSpeakingText", function()
        timing.lastStopMs = debugprofilestop()
        if timing.current ~= nil then
            timing.current.finish()
        end
        for _, readback in ipairs(activeReadbacks()) do
            readback:onStop()
        end
    end)
end

-- Beside WowVision's speech queue, which matches every start to its calls in
-- order: a call straight to the engine could be taken for one of its own.
local function asideSpeak(voice, text, rate, volume)
    local speech = WowVision.base ~= nil and WowVision.base.speech or nil
    if speech ~= nil and speech.speakAside ~= nil then
        speech:speakAside(voice, text, rate, volume)
    else
        engineSpeak(voice, text, rate, volume, true)
    end
end

local function foreignStart(now)
    tinsert(timing.foreignStarts, now)
    while #timing.foreignStarts > 16 do
        tremove(timing.foreignStarts, 1)
    end
end

-- Ours is the start within START_WINDOW_MS of our call; a second start in that
-- window makes the sample ambiguous. Finish and fail must match the id.
-- Other speech is only counted.
timingFrame:SetScript("OnEvent", function(_, event, utteranceID, status)
    local now = debugprofilestop()
    for _, readback in ipairs(activeReadbacks()) do
        if event == "VOICE_CHAT_TTS_PLAYBACK_STARTED" then
            readback:onStarted(utteranceID)
        else
            readback:onFinished(utteranceID, event == "VOICE_CHAT_TTS_PLAYBACK_FAILED")
        end
    end
    local m = timing.current
    if event == "VOICE_CHAT_TTS_PLAYBACK_STARTED" then
        if m ~= nil and now - m.calledMs <= START_WINDOW_MS then
            if m.utteranceID == nil then
                m.utteranceID = utteranceID
                m.startMs = now
                m.ids = { [utteranceID] = true }
                return
            end
            -- Ambiguous: it ends with whichever of the two finishes first.
            m.ambiguous = true
            m.ids[utteranceID] = true
        end
        foreignStart(now)
        if m ~= nil then
            m.others = (m.others or 0) + 1
        end
        return
    end
    if m == nil or m.ids == nil or not m.ids[utteranceID] then
        if m ~= nil then
            m.others = (m.others or 0) + 1
        end
        return
    end
    if event == "VOICE_CHAT_TTS_PLAYBACK_FINISHED" then
        m.finishMs = now
    else
        m.failed = statusName(status)
    end
    m.finish()
end)

-- Speaks one utterance and calls done(m) once it finished, failed or timed out.
local function measure(voice, volume, buildText, done)
    local m = { calledMs = debugprofilestop() }
    local finished = false
    function m.finish()
        if finished then
            return
        end
        finished = true
        if timing.current == m then
            timing.current = nil
        end
        if m.startMs ~= nil and m.finishMs ~= nil then
            m.playedMs = m.finishMs - m.startMs
        end
        -- The gap also catches the start of speech that cut ours short.
        C_Timer.After(TIMING_GAP, function()
            local endMs = m.finishMs or debugprofilestop()
            if m.ambiguous then
                m.disturbed = "two speech starts at once"
            elseif timing.lastStopMs ~= nil and timing.lastStopMs >= m.calledMs and timing.lastStopMs <= endMs + 5 then
                m.disturbed = "a stop of all speech"
            elseif m.finishMs ~= nil then
                for _, t in ipairs(timing.foreignStarts) do
                    if t >= m.finishMs and t <= m.finishMs + CUT_WINDOW_MS then
                        m.disturbed = "speech starting right after ours ended"
                    end
                end
            end
            done(m)
        end)
    end
    local okBuild, text = pcall(buildText)
    if not okBuild then
        m.error = "build: " .. tostring(text)
        m.finish()
        return
    end
    m.textSecret = isSecret(text)
    timing.current = m
    local ok, err = pcall(asideSpeak, voice, text, TIMING_RATE, volume)
    if not ok then
        m.error = "speak: " .. tostring(err)
        m.finish()
        return
    end
    C_Timer.After(TIMING_TIMEOUT, function()
        if not finished then
            m.timedOut = true
            m.finish()
        end
    end)
end

-- A step is an utterance to measure, or { action = fn, wait = seconds }.
local function runSequence(steps, onDone)
    local index = 0
    local function nextStep()
        index = index + 1
        local step = steps[index]
        if step == nil then
            onDone()
            return
        end
        if step.action ~= nil then
            step.action()
            C_Timer.After(step.wait or 0, nextStep)
            return
        end
        measure(step.voice, step.volume, step.text, function(m)
            step.result = m
            nextStep()
        end)
    end
    nextStep()
end

local function round(x)
    return math.floor(x + 0.5)
end

-- Least squares line through { bucket, playedMs } pairs: played = a + b * bucket.
local function fitLine(points)
    if #points < 2 then
        return nil
    end
    local sx, sy = 0, 0
    for _, p in ipairs(points) do
        sx = sx + p[1]
        sy = sy + p[2]
    end
    local mx, my = sx / #points, sy / #points
    local sxx, sxy = 0, 0
    for _, p in ipairs(points) do
        sxx = sxx + (p[1] - mx) ^ 2
        sxy = sxy + (p[1] - mx) * (p[2] - my)
    end
    if sxx == 0 then
        return nil
    end
    local b = sxy / sxx
    return { a = my - b * mx, b = b }
end

-- The fractional bucket; decode rounds it.
local function bucketOf(playedMs)
    local fit = timing.fit
    if fit == nil or playedMs == nil or fit.b <= 0 then
        return nil
    end
    return (playedMs - fit.a) / fit.b
end

local function decode(playedMs)
    local raw = bucketOf(playedMs)
    if raw == nil then
        return nil
    end
    return round(raw)
end

local function bucketText(bucket)
    if bucket >= 10 then
        return "100 percent"
    end
    if bucket < 0 then
        return "below zero, bad measurement"
    end
    return (bucket * 10) .. " to " .. (bucket * 10 + 9) .. " percent"
end

local function resultText(m)
    if m.error ~= nil then
        return "ERROR " .. m.error
    end
    local parts = {}
    if m.failed ~= nil then
        tinsert(parts, "FAILED " .. m.failed)
    elseif m.timedOut then
        tinsert(parts, m.startMs == nil and "TIMEOUT, never started" or "TIMEOUT, never finished")
    else
        tinsert(parts, "played " .. round(m.playedMs) .. " ms")
    end
    if m.startMs ~= nil then
        tinsert(parts, "start after " .. round(m.startMs - m.calledMs) .. " ms")
    end
    tinsert(parts, "text " .. (m.textSecret and "secret" or "plain"))
    if m.others ~= nil then
        tinsert(parts, m.others .. " other speech events")
    end
    if m.disturbed ~= nil then
        tinsert(parts, "DISTURBED by " .. m.disturbed .. ", thrown away")
    end
    return table.concat(parts, ", ")
end

local function usable(m)
    return m ~= nil and m.playedMs ~= nil and m.disturbed == nil
end

local function framerate()
    local ok, fps = pcall(GetFramerate)
    if ok and type(fps) == "number" then
        return round(fps) .. " fps"
    end
    return "fps unknown"
end

-- The exact percent, spoken aloud by the engine as the truth to compare with
-- the decoded bucket. It is secret, so only the engine can say it, never chat.
local function speakTruth(unit, voice, prefix)
    local _, rate, volume = speechSettings()
    local c = getCurves()
    pcall(asideSpeak, voice, prefix .. ", true " .. healthThrough(unit, c.percent) .. " percent" .. bust(), rate, volume)
end

local function calibrationSteps(voice, buckets, rounds)
    local steps = {}
    for r = 1, rounds do
        for _, bucket in ipairs(buckets) do
            tinsert(steps, {
                label = "calibration " .. r .. ", bucket " .. bucket .. " (silence " .. silenceFor(bucket) .. ")",
                calibrate = bucket,
                voice = voice,
                volume = 0,
                text = function()
                    return silenceText(silenceFor(bucket))
                end,
            })
        end
    end
    return steps
end

-- Fits the undisturbed calibration points, then drops the worst point while it
-- lies more than OUTLIER_BUCKETS off the line (at most a third of them).
local function fitFrom(steps)
    local points = {}
    for _, step in ipairs(steps) do
        if step.calibrate ~= nil and usable(step.result) then
            tinsert(points, { step.calibrate, step.result.playedMs, step = step })
        end
    end
    local fit = fitLine(points)
    local dropped = {}
    while fit ~= nil and fit.b > 0 and #dropped < math.floor(#points / 3) do
        local worst, worstIndex = 0, nil
        for i, p in ipairs(points) do
            local off = math.abs((p[2] - fit.a) / fit.b - p[1])
            if off > worst then
                worst, worstIndex = off, i
            end
        end
        if worst <= OUTLIER_BUCKETS then
            break
        end
        local p = tremove(points, worstIndex)
        p.step.outlier = true
        tinsert(dropped, p)
        fit = fitLine(points)
    end
    if fit ~= nil then
        fit.used = #points
        fit.dropped = #dropped
    end
    return fit
end

local function timingLines(steps)
    local lines = {}
    local disturbed = 0
    for _, step in ipairs(steps) do
        if step.result ~= nil then
            tinsert(lines, step.label .. ": " .. resultText(step.result))
            if step.result.disturbed ~= nil then
                disturbed = disturbed + 1
            end
        end
    end
    tinsert(lines, disturbed .. " utterances disturbed by other speech and thrown away")
    timing.fit = fitFrom(steps)
    if timing.fit == nil then
        tinsert(lines, "No fit: too few calibration utterances finished. Timing readback does not work this way.")
        return lines
    end
    tinsert(lines, string.format("Fit: played = %d ms + %.1f ms per bucket (%.3f ms per ms of silence), %d points used, %d outliers dropped", round(timing.fit.a), timing.fit.b, timing.fit.b / BUCKET_SILENCE, timing.fit.used, timing.fit.dropped))
    tinsert(lines, "Calibration read back through the fit, in buckets (must stay within 0.5 of the true bucket):")
    local worst = 0
    for _, step in ipairs(steps) do
        if step.calibrate ~= nil and usable(step.result) then
            local raw = bucketOf(step.result.playedMs)
            if not step.outlier then
                worst = math.max(worst, math.abs(raw - step.calibrate))
            end
            tinsert(lines, string.format("  bucket %d -> %.2f%s", step.calibrate, raw, step.outlier and ", OUTLIER dropped" or ""))
        end
    end
    tinsert(lines, string.format("Worst calibration error without outliers %.2f buckets: %s", worst, worst < 0.5 and "every bucket read back right" or "SOME BUCKETS READ BACK WRONG"))
    for _, step in ipairs(steps) do
        local m = step.result
        if m ~= nil and not usable(m) and (step.expect ~= nil or step.health) then
            tinsert(lines, step.label .. ": no usable sample")
        elseif step.expect ~= nil then
            tinsert(lines, string.format("%s: read back %.2f, expected %d", step.label, bucketOf(m.playedMs), step.expect))
        elseif step.health then
            tinsert(lines, string.format("%s: %.2f, decoded %s", step.label, bucketOf(m.playedMs), bucketText(decode(m.playedMs))))
        end
    end
    tinsert(lines, "The engine said the true percent aloud after the first health samples and at the end; compare them with the decoded health.")
    return lines
end

local function healthSteps(voice, unit, when)
    local c = getTimingCurves()
    local steps = {}
    for i = 1, 3 do
        tinsert(steps, {
            label = "health of " .. unit .. " at the " .. when .. " #" .. i,
            health = true,
            voice = voice,
            volume = 0,
            text = function()
                return silenceText(healthThrough(unit, c.health))
            end,
        })
    end
    return steps
end

local function buildTimingSteps(voice, unit)
    local c = getTimingCurves()
    local steps = {}
    local function append(list)
        for _, step in ipairs(list) do
            tinsert(steps, step)
        end
    end
    -- Health first, while a damaged player has not regenerated yet; the true
    -- percent is spoken right after, then a pause lets that speech end.
    append(healthSteps(voice, unit, "start"))
    tinsert(steps, {
        action = function()
            speakTruth(unit, voice, "Start")
        end,
        wait = 4,
    })
    -- Calibration: every bucket twice, plain silences.
    local buckets = {}
    for b = 0, 10 do
        tinsert(buckets, b)
    end
    append(calibrationSteps(voice, buckets, 2))
    -- The silence length from a secret constant.
    for _, const in ipairs({ { 3, c.bucket3 }, { 9, c.bucket9 } }) do
        for i = 1, 2 do
            tinsert(steps, {
                label = "secret constant bucket " .. const[1] .. " #" .. i,
                expect = const[1],
                voice = voice,
                volume = 0,
                text = function()
                    return silenceText(healthThrough(unit, const[2]))
                end,
            })
        end
    end
    append(healthSteps(voice, unit, "end"))
    return steps
end

local function finishTiming(lines)
    timing.lines = lines
    WowVisionDump = WowVisionDump or {}
    -- The last runs survive each other, so a whole test series needs one /reload.
    local runs = WowVisionDump.secretTimingRuns or {}
    tinsert(runs, lines)
    while #runs > TIMING_RUNS_MAX do
        tremove(runs, 1)
    end
    WowVisionDump.secretTimingRuns = runs
    local text = table.concat(lines, "\n")
    chat(text)
    WowVision.testing.showResults(text)
end

local function runTiming(voice, unit)
    if running or timing.running or timing.watch ~= nil or timing.par ~= nil then
        say("Probe already running")
        return
    end
    if C_CurveUtil == nil or UnitHealthPercent == nil then
        say("This client has no curves, the probe cannot run")
        return
    end
    timing.running = true
    local steps = buildTimingSteps(voice, unit)
    local utterances = 0
    for _, step in ipairs(steps) do
        if step.action == nil then
            utterances = utterances + 1
        end
    end
    say("Timing probe, unit " .. unit .. ", voice " .. tostring(voice) .. ", " .. utterances .. " silent utterances, about a minute. Keep still")
    C_Timer.After(TIMING_START_DELAY, function()
        local header = "Timing probe v4, unit " .. unit .. ", voice " .. tostring(voice) .. ", rate " .. TIMING_RATE
            .. ", " .. BUCKET_SILENCE .. " ms silence per bucket, in combat " .. tostring(InCombatLockdown())
            .. ", " .. framerate()
        runSequence(steps, function()
            timing.running = false
            local lines = timingLines(steps)
            tinsert(lines, 1, header .. " at the start; " .. framerate() .. ", in combat " .. tostring(InCombatLockdown()) .. " at the end")
            finishTiming(lines)
            local decoded = "nothing decoded"
            for _, step in ipairs(steps) do
                if step.health and usable(step.result) then
                    decoded = "decoded " .. bucketText(decode(step.result.playedMs))
                end
            end
            speakTruth(unit, voice, "Timing probe done, " .. decoded)
        end)
    end)
end

-- Watch: the group health monitor's own step readback
-- (retail/groupHealth/readback.lua: fixed values, no calibration) on one
-- unit, woken by its health events as in the monitor. Each new step is said
-- with the true percent, which only the engine can speak.
local function watchLog(line)
    tinsert(timing.watchLog, line)
    while #timing.watchLog > TIMING_LOG_MAX do
        tremove(timing.watchLog, 1)
    end
    WowVisionDump = WowVisionDump or {}
    WowVisionDump.secretTimingWatch = timing.watchLog
end

-- Paddings never repeat within a session; seeded from the clock, as the
-- engine's audio cache outlives /reload.
local readbackCount = nil

local function nextReadbackCount()
    if readbackCount == nil then
        readbackCount = (time() % 1048576) * 16
    end
    readbackCount = readbackCount + 1
    return readbackCount
end

local readbackCurves = {}

-- The readback's curves, built once per point list.
local function readbackCurve(points)
    local key = WowVision.groupHealth.pointsKey(points)
    if readbackCurves[key] == nil then
        readbackCurves[key] = stepCurve(points)
    end
    return readbackCurves[key]
end

-- `through` may replace the health (the pair check speaks fixed digits).
local function newReadback(voice, onReading, onDiscard, through)
    local GroupHealth = WowVision.groupHealth
    return GroupHealth.Readback:new({
        now = debugprofilestop,
        after = C_Timer.After,
        speak = function(text)
            asideSpeak(voice, text, GroupHealth.readbackConstants.RATE, 0)
        end,
        through = through or function(unit, points)
            return healthThrough(unit, readbackCurve(points))
        end,
        nextCount = nextReadbackCount,
        onReading = onReading,
        onDiscard = onDiscard,
    })
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

local function readingText(reading)
    return string.format("digits %.2f and %.2f, played %d and %d ms", reading.rawHigh, reading.rawLow, round(reading.playedHigh), round(reading.playedLow))
end

local watchFrame = CreateFrame("Frame")
watchFrame:SetScript("OnEvent", function(_, _, unit)
    local w = timing.watch
    if w ~= nil and unit == w.unit then
        w.events = w.events + 1
        w.readback:request(unit)
    end
end)

local function toggleWatch(voice, unit)
    if timing.watch ~= nil then
        local w = timing.watch
        timing.watch = nil
        watchFrame:UnregisterAllEvents()
        local summary = string.format(
            "Watch off after %d seconds: %d health events, %d step changes; %s",
            math.floor(GetTime() - w.startedAt), w.events, w.changes, readbackSummary(w.readback)
        )
        watchLog(string.format("%.1f %s", GetTime(), summary))
        say(summary)
        return
    end
    if running or timing.running or timing.par ~= nil then
        say("Probe already running")
        return
    end
    if C_CurveUtil == nil or UnitHealthPercent == nil or WowVision.groupHealth == nil or WowVision.groupHealth.Readback == nil then
        say("This client has no step readback, the watch cannot run")
        return
    end
    local w = { unit = unit, voice = voice, events = 0, changes = 0, startedAt = GetTime() }
    w.readback = newReadback(voice, function(u, reading)
        if timing.watch ~= w then
            return
        end
        if reading.step == w.step then
            return
        end
        w.step = reading.step
        w.changes = w.changes + 1
        local text = u .. " " .. bucketText(reading.step)
        watchLog(string.format("%.1f %s, %s, %.2f s after the call, %s, in combat %s", GetTime(), text, readingText(reading), (debugprofilestop() - reading.calledMs) / 1000, framerate(), tostring(InCombatLockdown())))
        chat(text)
        -- In a slot of the readback's line, so its start is known as ours.
        w.readback:speakOwn(function()
            speakTruth(u, voice, text)
        end)
    end, function(u, why, m)
        if timing.watch == w then
            watchLog(string.format("%.1f %s thrown away: %s", GetTime(), u, why))
        end
    end)
    timing.watch = w
    watchFrame:RegisterEvent("UNIT_HEALTH")
    watchLog(string.format("%.1f watch start, %s, fixed values, two digits, %s", GetTime(), unit, framerate()))
    say("Watch on, unit " .. unit .. ", voice " .. tostring(voice))
    -- The first reading after our own announcement has ended.
    C_Timer.After(TIMING_START_DELAY, function()
        if timing.watch == w then
            w.readback:request(unit)
        end
    end)
end

local function saveRun(lines)
    WowVisionDump = WowVisionDump or {}
    local runs = WowVisionDump.secretTimingRuns or {}
    tinsert(runs, lines)
    while #runs > TIMING_RUNS_MAX do
        tremove(runs, 1)
    end
    WowVisionDump.secretTimingRuns = runs
    chat(table.concat(lines, "\n"))
end

local function canReadSteps()
    if running or timing.running or timing.watch ~= nil or timing.par ~= nil then
        say("Probe already running")
        return false
    end
    if C_CurveUtil == nil or UnitHealthPercent == nil or WowVision.groupHealth == nil or WowVision.groupHealth.Readback == nil then
        say("This client has no step readback, the test cannot run")
        return false
    end
    return true
end

-- `count` samples in slots of the line, then done(readings, discards, readback).
local function sampleMany(readback, count, done)
    local readings, discards = {}, {}
    readback.env.onReading = function(_, reading)
        tinsert(readings, reading)
    end
    readback.env.onDiscard = function(_, why)
        tinsert(discards, why)
    end
    timing.par = readback
    for _ = 1, count do
        readback:inSlot(2, function(slot)
            readback:sample("player", slot)
        end)
    end
    C_Timer.After(count * 0.12 + 3, function()
        timing.par = nil
        done(readings, discards)
    end)
end

local function stepCounts(readings)
    local steps = {}
    for _, reading in ipairs(readings) do
        steps[reading.step] = (steps[reading.step] or 0) + 1
    end
    local list = {}
    for step, n in pairs(steps) do
        tinsert(list, bucketText(step) .. " " .. n .. " times")
    end
    table.sort(list)
    return steps, list
end

-- Parallel: n samples of your own health at once, in slots of the line as
-- the monitor would sample a raid (each sample two utterances). Every reading
-- should give the same step.
local function runParallel(voice, count)
    if not canReadSteps() then
        return
    end
    local readback = newReadback(voice)
    say("Parallel test, " .. count .. " samples of your health at once. Keep still")
    C_Timer.After(TIMING_START_DELAY, function()
        sampleMany(readback, count, function(readings, discards)
            local steps, stepList = stepCounts(readings)
            local played = {}
            for _, reading in ipairs(readings) do
                tinsert(played, round(reading.playedHigh) .. "/" .. round(reading.playedLow))
            end
            saveRun({
                string.format("Parallel test, %d samples, %d readings, %d thrown away (%s), most at once %d, %s",
                    count, #readings, #discards, table.concat(discards, ", "), readback.stats.maxInflight, framerate()),
                "Steps read: " .. (#stepList > 0 and table.concat(stepList, "; ") or "none"),
                "Played ms (first digit/second digit): " .. table.concat(played, " "),
            })
            local decoded = #stepList == 1 and ("all " .. bucketText(next(steps))) or (#stepList .. " different steps")
            speakTruth("player", voice, "Parallel test done, " .. #readings .. " of " .. count .. " read, " .. decoded)
        end)
    end)
end

-- Pair check: does the lower utterance id belong to the first call? Fixed
-- digits instead of health: pattern A says digits 0 and 3 (step 3), pattern
-- B digits 2 and 1 (step 9). In the wrong order A would read out of range
-- and B as step 6. Then five samples of your real health.
local function runPairCheck(voice)
    if not canReadSteps() then
        return
    end
    local R = WowVision.groupHealth.readbackConstants
    local patterns = {}
    for i = 1, 10 do
        tinsert(patterns, i % 2 == 1 and { 0, 3 } or { 2, 1 })
    end
    local current
    local readback = newReadback(voice, nil, nil, function(_, _, digit)
        if digit == 1 then
            current = tremove(patterns, 1)
        end
        return R.SILENCE_OFFSET + current[digit] * R.LEVEL_SILENCE
    end)
    say("Pair check, ten fixed samples, then five of your health. Keep still")
    C_Timer.After(TIMING_START_DELAY, function()
        sampleMany(readback, 10, function(readings, discards)
            local steps = stepCounts(readings)
            local fixedLine = string.format(
                "Fixed digits: step 3 read %d of 5, step 9 read %d of 5, other %d, thrown away %d (%s)",
                steps[3] or 0, steps[9] or 0, #readings - (steps[3] or 0) - (steps[9] or 0), #discards, table.concat(discards, ", ")
            )
            local orderOk = (steps[3] or 0) + (steps[9] or 0) == #readings and #readings > 0
            local health = newReadback(voice)
            C_Timer.After(1, function()
                sampleMany(health, 5, function(healthReadings, healthDiscards)
                    local _, list = stepCounts(healthReadings)
                    local played = {}
                    for _, reading in ipairs(healthReadings) do
                        tinsert(played, readingText(reading))
                    end
                    saveRun({
                        "Pair check, " .. framerate(),
                        fixedLine,
                        "Id order " .. (orderOk and "confirmed: the lower id is the first call" or "NOT confirmed"),
                        string.format("Your health: %d readings, %d thrown away; %s", #healthReadings, #healthDiscards, table.concat(list, "; ")),
                        "Health samples: " .. table.concat(played, "; "),
                    })
                    speakTruth("player", voice, "Pair check done, id order " .. (orderOk and "confirmed" or "not confirmed") .. ", health " .. (#list == 1 and list[1] or (#list .. " different steps")))
                end)
            end)
        end)
    end)
end

-- Command ---------------------------------------------------------------------

local function showLog()
    if #probe.entries == 0 then
        say("Nothing recorded yet")
        return
    end
    local lines = {}
    for _, entry in ipairs(probe.entries) do
        tinsert(lines, entryLine(entry))
    end
    for _, err in ipairs(probe.registerErrors) do
        tinsert(lines, "event registration failed: " .. err)
    end
    tinsert(lines, #probe.rawEvents .. " engine speech events seen (time, event, first, second):")
    for _, line in ipairs(probe.rawEvents) do
        tinsert(lines, line)
    end
    WowVisionDump = WowVisionDump or {}
    WowVisionDump.secretProbe = lines
    chat(table.concat(lines, "\n"))
    WowVision.testing.showResults(table.concat(lines, "\n"))
end

local function parseArgs(words)
    local voice, unit, number = nil, nil, nil
    for i = 2, #words do
        local value = tonumber(words[i])
        if value ~= nil then
            if voice == nil then
                voice = value
            else
                number = value
            end
        else
            unit = words[i]
        end
    end
    return voice, unit, number
end

WowVision.base:registerCommand({
    name = "sprobe",
    description = "Secret speech probe: 'run [voice] [unit]' ten spoken steps, 'events [seconds]' counts health and power events, 'monitor [voice] [percent]' toggles a pitch party health monitor, 'pitch [voice]' tests how far pitch reaches, 'timing [voice] [unit]' reads a health bucket back from silent speech timing, 'twatch [voice] [unit]' toggles the monitor's step readback on one unit, 'tpar [count]' samples your health that many times at once, 'tpair' checks the two-digit id order, 'log' shows the engine statuses",
    func = function(args)
        local words = {}
        for word in tostring(args or ""):lower():gmatch("%S+") do
            tinsert(words, word)
        end
        local command = words[1] or "run"
        local defaultVoice = speechSettings()
        if command == "run" then
            local voice, unit = parseArgs(words)
            runSteps(voice or defaultVoice, unit or "player")
        elseif command == "events" then
            countEvents(tonumber(words[2]) or 30)
        elseif command == "monitor" then
            local voice, _, percent = parseArgs(words)
            if voice ~= nil and percent == nil and voice > 20 then
                -- A single number above any voice id is the percent.
                percent, voice = voice, nil
            end
            toggleMonitor(voice or defaultVoice, percent)
        elseif command == "pitch" then
            local voice = parseArgs(words)
            runPitchTest(voice or defaultVoice)
        elseif command == "timing" then
            local voice, unit = parseArgs(words)
            runTiming(voice or 0, unit or "player")
        elseif command == "twatch" then
            local voice, unit = parseArgs(words)
            toggleWatch(voice or 0, unit or "player")
        elseif command == "tpar" then
            -- "tpar 10" is the count; "tpar 0 10" a voice and the count.
            local voice, _, count = parseArgs(words)
            if count == nil then
                count, voice = voice, nil
            end
            runParallel(voice or 0, math.max(1, math.min(20, count or 5)))
        elseif command == "tpair" then
            local voice = parseArgs(words)
            runPairCheck(voice or 0)
        elseif command == "log" then
            showLog()
        else
            say("Usage: slash w v s probe run, events, monitor, pitch, timing, twatch, tpar, tpair, or log")
        end
    end,
})
