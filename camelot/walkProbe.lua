-- Walk probe (developer tool, local only): records what happens while the
-- player moves, to check wall detection against it. Walks the game makes
-- with no key held (the interact key, autorun) are always kept; walks with a
-- key held only when they got stuck (3 checks or more graded blocked) or had
-- no position (instances). Recording is automatic and quiet: one line per
-- kept walk goes to chat when it ends, the samples to
-- WowVisionDump.walkProbe (saved at the next /reload). Separate from every
-- module; it can be left out without anything noticing.

local CHECK = 0.15
-- Still sampled this long after the game says the player stopped.
local AFTER = 2
-- A walk is cut off after this long.
local LONGEST = 60
local KEEP = 12

local movement = WowVision.movement
local walk = nil
local lastCheck, lastX, lastY = 0, nil, nil

local function chat(text)
    print("WowVision probe: " .. text)
end

local function line(text)
    tinsert(walk.lines, string.format("%.2f %s", GetTime() - walk.startTime, text))
end

local function begin(reason, keyed)
    if walk ~= nil then
        line(reason)
        return
    end
    local _, instanceType = IsInInstance()
    walk = {
        keyed = keyed,
        instance = instanceType,
        blocked = 0,
        noPosition = false,
        at = date("%Y-%m-%d %H:%M:%S"),
        startTime = GetTime(),
        lines = {},
        moves = {},
        graded = 0,
        stoppedAt = nil,
    }
    lastCheck = GetTime()
    lastX, lastY = UnitPosition("player")
    line(reason)
end

local function finish()
    if walk.keyed and walk.blocked < 3 and not walk.noPosition then
        walk = nil
        return
    end
    WowVisionDump = WowVisionDump or {}
    local runs = WowVisionDump.walkProbe or {}
    tinsert(runs, walk)
    while #runs > KEEP do
        tremove(runs, 1)
    end
    WowVisionDump.walkProbe = runs

    local last = {}
    for i = math.max(1, #walk.moves - 3), #walk.moves do
        tinsert(last, walk.moves[i])
    end
    local stopped = walk.stoppedAt and string.format("the game stopped it at %.1f s", walk.stoppedAt - walk.startTime)
        or "not stopped by the game"
    chat(string.format(
        "%s walk%s %.1f s, %s, last moves %s yd per check, %d slowed, %d blocked checks",
        walk.keyed and "key" or "game",
        walk.instance ~= "none" and (" in " .. tostring(walk.instance)) or "",
        GetTime() - walk.startTime,
        stopped,
        #last > 0 and table.concat(last, " ") or "none",
        walk.graded,
        walk.blocked
    ))
    walk = nil
end

local function sample()
    local now = GetTime()
    local dt = now - lastCheck
    lastCheck = now
    local x, y = UnitPosition("player")
    local moved = nil
    if x ~= nil and lastX ~= nil then
        moved = math.sqrt((x - lastX) ^ 2 + (y - lastY) ^ 2)
    end
    lastX, lastY = x, y
    local speed = GetUnitSpeed("player")
    if WowVision.isSecret(speed) then
        speed = nil
    end
    local walls = WowVision.base.navigation.walls
    local severity = walls and walls.severity
    if severity ~= nil then
        walk.graded = walk.graded + 1
        if severity <= 2 then
            walk.blocked = walk.blocked + 1
        end
    end
    if x == nil then
        walk.noPosition = true
    end
    local movedText = moved and string.format("%.2f", moved) or "-"
    tinsert(walk.moves, movedText)
    line(string.format(
        "dt %.2f moved %s speed %s gameMoving %s falling %s keys %s wall %s",
        dt,
        movedText,
        speed and string.format("%.1f", speed) or "secret",
        tostring(IsPlayerMoving()),
        tostring(IsFalling()),
        tostring(movement:isTranslating() and true or false),
        tostring(severity)
    ))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_STARTED_MOVING")
frame:RegisterEvent("PLAYER_STOPPED_MOVING")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_STARTED_MOVING" then
        if walk ~= nil then
            walk.stoppedAt = nil
            line("game started moving")
        elseif movement:isTranslating() then
            begin("game started moving, key held", true)
        else
            begin("game started moving, no key held", false)
        end
    elseif walk == nil then
        return
    elseif event == "PLAYER_STOPPED_MOVING" then
        walk.stoppedAt = GetTime()
        line("game stopped moving")
    elseif event == "UI_ERROR_MESSAGE" then
        local _, message = ...
        line("error message: " .. (WowVision.isSecret(message) and "secret" or tostring(message)))
    end
end)
frame:SetScript("OnUpdate", function()
    if walk == nil or GetTime() - lastCheck < CHECK then
        return
    end
    sample()
    local now = GetTime()
    if (walk.stoppedAt ~= nil and now - walk.stoppedAt >= AFTER) or now - walk.startTime >= LONGEST then
        finish()
    end
end)

if C_PlayerInteractionManager ~= nil and C_PlayerInteractionManager.InteractUnit ~= nil then
    hooksecurefunc(C_PlayerInteractionManager, "InteractUnit", function(unit)
        begin("interact " .. tostring(unit), false)
    end)
end
