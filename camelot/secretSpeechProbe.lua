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
-- /wv sprobe run [voiceID] [unit]  ten spoken steps, each names itself;
--                                   say what you hear for each number
-- /wv sprobe events [seconds]      counts health and power events per unit
-- /wv sprobe monitor [voiceID] [percent]
--                                   toggles a Sku-style party health monitor:
--                                   party number (player 1, party1-4 = 2-5),
--                                   higher pitch the more damaged, silent at
--                                   or above the percent (default 90)
-- /wv sprobe log                    every recorded step with engine statuses;
--                                   /reload writes it to WowVisionDump
--
-- Speech goes straight to the engine's own SpeakText, captured here at file
-- load, before the speech module's queue replaces the global (that happens on
-- enable). The queue's foreign-text buster may put no-break spaces BEFORE the
-- text, which could stop the engine detecting the text as XML; the probe
-- busts its own texts inside the tags instead (see step four).

local engineSpeak = C_VoiceChat.SpeakText

local probe = {
    entries = {},
    eventCounts = nil,
    monitor = nil,
}
WowVision.secretSpeechProbe = probe

local MAX_ENTRIES = 80
local STEP_SECONDS = 3.5
local NBSP = "\194\160"
local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local PARTY_INDEX = { player = 1, party1 = 2, party2 = 3, party3 = 4, party4 = 5 }

local function isSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

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

local function say(text)
    if WowVision.base ~= nil and WowVision.base.speech ~= nil then
        WowVision:speak(text)
    else
        print(text)
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
    curves = {
        percent = stepCurve(percent),
        pitch = stepCurve(pitch),
        constLow = stepCurve({ { 0, -10 }, { 1, -10 } }),
        constHigh = stepCurve({ { 0, 10 }, { 1, 10 } }),
        constZero = stepCurve({ { 0, 0 }, { 1, 0 } }),
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
    pcall(ttsFrame.RegisterEvent, ttsFrame, event)
end
ttsFrame:SetScript("OnEvent", function(_, event, a, b)
    local now = GetTime()
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
    tinsert(parts, "utterance " .. tostring(entry.utteranceID))
    if #entry.statuses > 0 then
        tinsert(parts, "status " .. table.concat(entry.statuses, " "))
    end
    if entry.noSyncUpdate and entry.utteranceID ~= nil then
        tinsert(parts, "update came late")
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
    }
end

local running = false

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
            speak(step.label, voice, step.text, secrets, true)
        end)
    end
    C_Timer.After((#steps + 1) * STEP_SECONDS, function()
        running = false
        say("Probe done. Type slash w v s probe log for the engine statuses")
    end)
    say("Secret speech probe, unit " .. unit .. ", voice " .. tostring(voice) .. ". Ten steps follow")
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
    WowVisionDump = WowVisionDump or {}
    WowVisionDump.secretProbe = lines
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
    description = "Secret speech probe: 'run [voice] [unit]' ten spoken steps, 'events [seconds]' counts health and power events, 'monitor [voice] [percent]' toggles a pitch party health monitor, 'log' shows the engine statuses",
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
        elseif command == "log" then
            showLog()
        else
            say("Usage: slash w v s probe run, events, monitor, or log")
        end
    end,
})
