-- Taint watch: records every blocked or forbidden protected call into the
-- WowVisionDump saved variable, with the stack and what the graph had
-- focused. Saved variables reach disk on /reload, unlike Logs\taint.log,
-- which a reload starts fresh (and which Forever does not keep enabled
-- across launches). Loaded right after WowVision.lua so the frame listens
-- from the first moment. Read with /wv taint; /wv taint clear resets.
--
-- Every block is recorded, but only WowVision's own are spoken: the game
-- blames the addon whose code made the call, and other addons' blocks are
-- theirs to fix. Macro blocks carry no addon and are always spoken
-- (WowVision clicks through secure macros).

local MAX_ENTRIES = 30

local function focusDescription()
    local host = WowVision.graphHost
    if host == nil then
        return "no graph host"
    end
    local screen = host:focusedScreen()
    if screen == nil then
        return "no focused screen"
    end
    local parts = { "screen " .. tostring(screen.key) }
    local node = screen.keyGraph ~= nil and screen.keyGraph:currentNode() or nil
    if node ~= nil then
        -- Frame-keyed nodes print as "table: ..."; their debug name says which.
        local key = node.id ~= nil and node.id.key or nil
        if type(key) == "table" and key.GetDebugName ~= nil then
            local okName, name = pcall(key.GetDebugName, key)
            if okName and name ~= nil then
                key = name
            end
        end
        tinsert(parts, "node " .. tostring(key))
        local debug = WowVision.graph.scrollBoxDebug ~= nil and WowVision.graph.scrollBoxDebug[tostring(node.id.key)]
            or nil
        if debug ~= nil then
            tinsert(parts, "row " .. tostring(debug.template) .. " '" .. tostring(debug.name) .. "'")
        end
        local first = node.vtable ~= nil and node.vtable.announcements ~= nil and node.vtable.announcements[1] or nil
        local label = first ~= nil and first.text or nil
        if type(label) == "function" then
            local okLabel, text = pcall(label)
            label = okLabel and text or nil
        end
        if type(label) == "string" then
            tinsert(parts, "label '" .. label .. "'")
        end
    end
    return table.concat(parts, ", ")
end

-- What tainted a blocked call: the game names only the addon. Modules
-- register the game tables their screens drive (taintWatch.watch), and each
-- record lists every field of them that addon code wrote, with the addon
-- (issecurevariable) -- the variable Logs\taint.log would name, without the
-- taintLog console variable, which on WoW: Forever raises Lua errors in chat
-- and crashes the client.
local watched = {}

WowVision.taintWatch = {}

-- Every watched field addon code wrote: { [ "Table.key" ] = addon }.
local function scanTainted()
    local found = {}
    for _, entry in ipairs(watched) do
        local ok, tbl = pcall(entry.get)
        if ok and type(tbl) == "table" then
            for key in pairs(tbl) do
                if type(key) == "string" then
                    local okCheck, secure, taintedBy = pcall(issecurevariable, tbl, key)
                    if okCheck and not secure then
                        found[entry.name .. "." .. key] = tostring(taintedBy)
                    end
                end
            end
        end
    end
    return found
end

local function taintedFields()
    if issecurevariable == nil then
        return nil
    end
    local found = {}
    for field, addon in pairs(scanTainted()) do
        tinsert(found, field .. " (" .. addon .. ")")
    end
    if #found == 0 then
        return #watched > 0 and "none" or nil
    end
    table.sort(found)
    return table.concat(found, ", ")
end

-- The taint timeline: once a second the watched fields are scanned, and a
-- field that turns tainted (or clean again) is saved with the time and the
-- graph's focus then -- which action wrote it, read from the file after a
-- reload with no probe typed in game. WowVisionDump.taintTimeline, newest
-- last, MAX_TIMELINE entries.
local MAX_TIMELINE = 150
local lastTainted = nil
local ticker = nil

local function addTimeline(change, field, addon)
    WowVisionDump = WowVisionDump or {}
    local list = WowVisionDump.taintTimeline or {}
    WowVisionDump.taintTimeline = list
    local okFocus, focus = pcall(focusDescription)
    tinsert(list, {
        time = date("%Y-%m-%d %H:%M:%S"),
        change = change,
        field = field,
        addon = addon,
        focus = okFocus and focus or ("focus error: " .. tostring(focus)),
    })
    while #list > MAX_TIMELINE do
        tremove(list, 1)
    end
end

local function scanTimeline()
    local now = scanTainted()
    if lastTainted ~= nil then
        for field, addon in pairs(now) do
            if lastTainted[field] == nil then
                addTimeline("tainted", field, addon)
            end
        end
        for field in pairs(lastTainted) do
            if now[field] == nil then
                addTimeline("clean", field, nil)
            end
        end
    end
    lastTainted = now
end

local function startTimeline()
    if ticker ~= nil or issecurevariable == nil or C_Timer == nil then
        return
    end
    ticker = C_Timer.NewTicker(1, function()
        pcall(scanTimeline)
    end)
end

-- name: how the record names the table; get: returns it (or nil while the
-- game has not built it).
function WowVision.taintWatch.watch(name, get)
    tinsert(watched, { name = name, get = get })
    startTimeline()
end

local function record(event, addon, func)
    WowVisionDump = WowVisionDump or {}
    local list = WowVisionDump.taint or {}
    WowVisionDump.taint = list
    local okFocus, focus = pcall(focusDescription)
    local okTainted, tainted = pcall(taintedFields)
    tinsert(list, {
        time = date("%Y-%m-%d %H:%M:%S"),
        event = event,
        addon = tostring(addon),
        func = tostring(func),
        focus = okFocus and focus or ("focus error: " .. tostring(focus)),
        tainted = okTainted and tainted or ("tainted error: " .. tostring(tainted)),
        stack = debugstack(3, 30, 0),
    })
    while #list > MAX_ENTRIES do
        tremove(list, 1)
    end
    local ours = addon == nil or addon == "WowVision"
    if ours and WowVision.base ~= nil and WowVision.base.speech ~= nil then
        WowVision:notify("Blocked: " .. tostring(func))
    end
end

local frame = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_ACTION_BLOCKED",
    "ADDON_ACTION_FORBIDDEN",
    "MACRO_ACTION_BLOCKED",
    "MACRO_ACTION_FORBIDDEN",
}) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...)
    -- Macro events carry only the function; the addon ones name the addon first.
    local addon, func = ...
    if event:find("^MACRO") then
        addon, func = nil, ...
    end
    pcall(record, event, addon, func)
end)

function WowVision:registerTaintCommand()
    self.base:registerCommand({
        name = "taint",
        description = "Show blocked protected calls recorded in WowVisionDump ('clear' resets); /reload writes them to disk",
        func = function(args)
            WowVisionDump = WowVisionDump or {}
            if args == "clear" then
                WowVisionDump.taint = {}
                WowVisionDump.taintTimeline = {}
                print("Taint records cleared")
                return
            end
            local list = WowVisionDump.taint or {}
            if #list == 0 then
                WowVision:speak("No blocked calls recorded")
                return
            end
            local lines = { #list .. " blocked calls" }
            for _, entry in ipairs(list) do
                tinsert(lines, entry.time .. " " .. entry.event .. " " .. entry.addon .. " " .. entry.func)
                tinsert(lines, "  " .. entry.focus)
                if entry.tainted ~= nil then
                    tinsert(lines, "  tainted: " .. entry.tainted)
                end
            end
            local text = table.concat(lines, "\n")
            WowVision.testing.showResults(text)
            WowVision:speak(text)
        end,
    })
end
