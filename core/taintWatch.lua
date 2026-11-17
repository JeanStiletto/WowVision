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

local watchedGlobals = {}

-- Watched lists: tables the game makes and drops while it runs (the damage
-- meter's rows). get returns { { name = ..., tbl = ... }, ... } or nil.
local watchedLists = {}

-- Recent actions: a short ring of what changed game state just before a
-- scan found new taint -- every SetCVar (anyone's: the record says whether
-- the call ran tainted and which file made it). A run of the same setting
-- from the same caller (turn speed during a turn) is one entry with a
-- count. Copied into the timeline entry of each new taint.
local MAX_RECENT = 40
local recent = {}

-- key: what makes a run (setting, tainted or not, caller); text: the
-- newest call, value included.
local function addRecent(key, text, caller)
    local last = recent[#recent]
    if last ~= nil and last.key == key and last.caller == caller then
        last.count = last.count + 1
        last.last = GetTime()
        last.text = text
        return
    end
    tinsert(recent, { at = GetTime(), clock = date("%H:%M:%S"), key = key, text = text, caller = caller, count = 1 })
    while #recent > MAX_RECENT do
        tremove(recent, 1)
    end
end

local function recentSnapshot()
    local now = GetTime()
    local lines = {}
    for _, entry in ipairs(recent) do
        local line = string.format("%s (%.1f s ago) %s", entry.clock, now - entry.at, entry.text)
        if entry.count > 1 then
            line = line .. string.format(" x%d, last %.1f s ago", entry.count, now - entry.last)
        end
        tinsert(lines, line .. " <- " .. tostring(entry.caller))
    end
    return lines
end

-- The first stack line outside this file and the hook wrapper: who called.
local function callerLine()
    local stack = debugstack(3, 4, 0) or ""
    for line in stack:gmatch("[^\n]+") do
        if not line:find("taintWatch", 1, true) and not line:find("^%[C%]") then
            line = line:gsub("^%[string \"@?", ""):gsub("^%[", ""):gsub("\"?%]:", ":"):gsub(": in .*$", "")
            return (line:gsub("^Interface/AddOns/", ""))
        end
    end
    return "?"
end

local function hookCVar(owner, name, label)
    if owner == nil or type(owner[name]) ~= "function" then
        return
    end
    hooksecurefunc(owner, name, function(cvar, value)
        pcall(function()
            local secure = issecure ~= nil and issecure() and "secure" or "tainted"
            local key = label .. " " .. tostring(cvar) .. " (" .. secure .. ")"
            addRecent(key, key .. " last value " .. tostring(value), callerLine())
        end)
    end)
end
hookCVar(_G, "SetCVar", "SetCVar")
hookCVar(C_CVar, "SetCVar", "C_CVar.SetCVar")

-- Every watched field addon code wrote: { [ "Table.key" ] = addon }.
-- Number keys count too (tables keyed by ID, such as the group finder's
-- selected activities); globals are listed as _G.name.
local function scanTainted()
    local found = {}
    for _, name in ipairs(watchedGlobals) do
        local okCheck, secure, taintedBy = pcall(issecurevariable, name)
        if okCheck and not secure then
            found["_G." .. name] = tostring(taintedBy)
        end
    end
    -- One table per pcall: a table the game guards (secret keys) must not
    -- end the scan of the others.
    local function scanTable(name, tbl)
        for key in pairs(tbl) do
            if type(key) == "string" or type(key) == "number" then
                local okCheck, secure, taintedBy = pcall(issecurevariable, tbl, key)
                if okCheck and not secure then
                    found[name .. "." .. key] = tostring(taintedBy)
                end
            end
        end
    end
    for _, entry in ipairs(watched) do
        local ok, tbl = pcall(entry.get)
        if ok and type(tbl) == "table" then
            pcall(scanTable, entry.name, tbl)
        end
    end
    for _, entry in ipairs(watchedLists) do
        local ok, list = pcall(entry.get)
        if ok and type(list) == "table" then
            for _, item in ipairs(list) do
                if type(item.tbl) == "table" then
                    pcall(scanTable, entry.name .. "." .. item.name, item.tbl)
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
        return (#watched > 0 or #watchedGlobals > 0) and "none" or nil
    end
    table.sort(found)
    return table.concat(found, ", ")
end

-- The taint timeline: once a second the watched fields are scanned, and a
-- field that turns tainted (or clean again) is saved with the time and the
-- graph's focus then -- which action wrote it, read from the file after a
-- reload with no probe typed in game. WowVisionDump.taintTimeline, newest
-- last, MAX_TIMELINE entries.
local MAX_TIMELINE = 300
local lastTainted = nil
local ticker = nil

local function addTimeline(change, field, addon, withRecent)
    WowVisionDump = WowVisionDump or {}
    local list = WowVisionDump.taintTimeline or {}
    WowVisionDump.taintTimeline = list
    local okFocus, focus = pcall(focusDescription)
    local entry = {
        time = date("%Y-%m-%d %H:%M:%S"),
        change = change,
        field = field,
        addon = addon,
        focus = okFocus and focus or ("focus error: " .. tostring(focus)),
        inCombat = InCombatLockdown ~= nil and InCombatLockdown() or nil,
    }
    if withRecent then
        local okRecent, lines = pcall(recentSnapshot)
        entry.recent = okRecent and lines or { "recent error: " .. tostring(lines) }
    end
    tinsert(list, entry)
    while #list > MAX_TIMELINE do
        tremove(list, 1)
    end
end

-- Fields whose taint is announced (spoken and in chat), once per scan, with
-- what to say: the damage meter's, which break its rows in combat (Forever
-- 2026-11-14), and the action bars' and the quest map's, which block the
-- bars in combat (Forever 2026-11-17). Spoken when it happens, the player
-- knows which action did it.
local ANNOUNCED = {
    { pattern = "^DamageMeter", speech = "Damage meter tainted" },
    { pattern = "^EditModeManagerFrame", speech = "Action bars tainted" },
    { pattern = "^ActionBar", speech = "Action bars tainted" },
    { pattern = "^MicroMenuContainer", speech = "Action bars tainted" },
    { pattern = "^GamepadMainActionBarFrame", speech = "Gamepad bars tainted" },
    { pattern = "^QuestMapFrame", speech = "Quest log tainted" },
    { pattern = "^Bags%.", speech = "Bags tainted" },
    { pattern = "^MerchantFrame", speech = "Bags tainted" },
    { pattern = "^BankFrame", speech = "Bags tainted" },
    { pattern = "^ItemButtonUtil", speech = "Bags tainted" },
    { pattern = "^ItemLocation", speech = "Bags tainted" },
    { pattern = "^ContainerFrame", speech = "Bags tainted" },
}
-- The bag click's globals (BAG_CLICK_GLOBALS, below) are recorded as _G.name.
local bagGlobals = {}
local function announcement(field)
    local global = field:match("^_G%.(.+)$")
    if global ~= nil and bagGlobals[global] then
        return "Bags tainted"
    end
    for _, entry in ipairs(ANNOUNCED) do
        if field:find(entry.pattern) ~= nil then
            return entry.speech
        end
    end
    return nil
end

-- One timeline entry per scan, change and area: a bag frame built under
-- taint turns hundreds of fields at once, and one entry per field pushed the
-- moment it happened out of the list (2026-11-17: the "clean" of 150 bag
-- fields left none of their "tainted"). The area is the field's first two
-- parts (Bags.Bag1, ActionBars.StanceBar, _G.PENDING_LISTING_UPDATE); the
-- entry keeps the count and the first fields by name.
local SAMPLE_FIELDS = 12

local function areaOf(field)
    return field:match("^([^%.]+%.[^%.]+)") or field
end

local function addGrouped(change, fields, addons, withRecent)
    table.sort(fields)
    local areas, order = {}, {}
    for _, field in ipairs(fields) do
        local area = areaOf(field)
        local group = areas[area]
        if group == nil then
            group = { fields = {}, count = 0, addons = {} }
            areas[area] = group
            tinsert(order, area)
        end
        group.count = group.count + 1
        if #group.fields < SAMPLE_FIELDS then
            tinsert(group.fields, field)
        end
        if addons ~= nil and addons[field] ~= nil then
            group.addons[addons[field]] = true
        end
    end
    for index, area in ipairs(order) do
        local group = areas[area]
        local names = {}
        for addon in pairs(group.addons) do
            tinsert(names, addon)
        end
        table.sort(names)
        local field = area .. " (" .. group.count .. "): " .. table.concat(group.fields, ", ")
        -- The recent actions go with the first area of the scan.
        addTimeline(change, field, #names > 0 and table.concat(names, ", ") or nil, withRecent and index == 1)
    end
end

local function scanTimeline()
    local now = scanTainted()
    if lastTainted ~= nil then
        local fresh = {}
        for field in pairs(now) do
            if lastTainted[field] == nil then
                tinsert(fresh, field)
            end
        end
        table.sort(fresh)
        local announced, speech = nil, nil
        for _, field in ipairs(fresh) do
            speech = announcement(field)
            if speech ~= nil then
                announced = field
                break
            end
        end
        addGrouped("tainted", fresh, now, true)
        if announced ~= nil then
            print("WowVision taint: " .. announced .. " (" .. tostring(now[announced]) .. "), saved to WowVisionDump.taintTimeline")
            if WowVision.base ~= nil and WowVision.base.speech ~= nil then
                WowVision:speak(speech)
            end
        end
        local gone = {}
        for field in pairs(lastTainted) do
            if now[field] == nil then
                tinsert(gone, field)
            end
        end
        addGrouped("clean", gone, nil, false)
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

-- A global variable (by name), checked the same way.
function WowVision.taintWatch.watchGlobal(name)
    tinsert(watchedGlobals, name)
    startTimeline()
end

-- A changing set of tables: get returns { { name = ..., tbl = ... }, ... }.
function WowVision.taintWatch.watchList(name, get)
    tinsert(watchedLists, { name = name, get = get })
    startTimeline()
end

-- Blizzard's damage meter (WoW: Forever, Retail): on 2026-11-14 its rows
-- compared a secret spec icon "while execution tainted by 'WowVision'", in
-- every fight until a reload, though no WowVision code touches the meter.
-- Watched: the meter, its window list, each session window (up to 3), its
-- scroll box and view, the visible rows, the own-player row, the row data
-- the rows are built from, and Blizzard's cached setting values (a value
-- cached from tainted code taints every later read). Only reads here; every
-- get is nil where the meter does not exist (TBC, Era).
do
    local watch = WowVision.taintWatch.watch
    local MAX_WINDOWS = 3
    local function sessionWindow(index)
        return _G["DamageMeterSessionWindow" .. index]
    end
    local function scrollBox(window)
        local container = window ~= nil and window.MinimizeContainer or nil
        return container ~= nil and container.ScrollBox or nil, container
    end
    watch("DamageMeter", function()
        return DamageMeter
    end)
    watch("DamageMeter.windowDataList", function()
        return DamageMeter ~= nil and DamageMeter.windowDataList or nil
    end)
    watch("CVarCallbackRegistry.cvarValueCache", function()
        return CVarCallbackRegistry ~= nil and CVarCallbackRegistry.cvarValueCache or nil
    end)
    WowVision.taintWatch.watchList("DamageMeterWindows", function()
        local list = {}
        for index = 1, MAX_WINDOWS do
            local window = sessionWindow(index)
            if window ~= nil then
                local prefix = "w" .. index
                tinsert(list, { name = prefix, tbl = window })
                local box, container = scrollBox(window)
                if container ~= nil and container.LocalPlayerEntry ~= nil then
                    tinsert(list, { name = prefix .. ".LocalPlayerEntry", tbl = container.LocalPlayerEntry })
                end
                if box ~= nil then
                    tinsert(list, { name = prefix .. ".ScrollBox", tbl = box })
                    local okView, view = pcall(box.GetView, box)
                    if okView and type(view) == "table" then
                        tinsert(list, { name = prefix .. ".view", tbl = view })
                        if type(view.frames) == "table" then
                            for row, frame in ipairs(view.frames) do
                                tinsert(list, { name = prefix .. ".row" .. row, tbl = frame })
                            end
                        end
                        local provider = view.dataProvider
                        if type(provider) == "table" and type(provider.collection) == "table" then
                            for row, data in ipairs(provider.collection) do
                                tinsert(list, { name = prefix .. ".data" .. row, tbl = data })
                            end
                        end
                    end
                end
            end
        end
        return list
    end)
end

-- The group finder (WoW: Forever, TBC): which value the post or the
-- follow-up browse search read was written by addon code. The listing's
-- post reads its dirty flag, selected activities, play style and voice
-- mode; Blizzard's handler for the listing update reads
-- PENDING_LISTING_UPDATE and then runs the browse search, which reads the
-- browse frame and its dropdowns. The activity list's scroll box is here
-- because focus scrolls it from addon code. Every get returns nil until
-- the load-on-demand group finder is loaded.
do
    local watch = WowVision.taintWatch.watch
    WowVision.taintWatch.watchGlobal("PENDING_LISTING_UPDATE")
    local function listing()
        return LFGListingFrame
    end
    local function activityView()
        local frame = listing()
        return frame ~= nil and frame.ActivityView or nil
    end
    local function activityScrollBox()
        local view = activityView()
        return view ~= nil and view.ScrollBox or nil
    end
    local function browse()
        return LFGBrowseFrame
    end
    watch("LFGListingFrame", listing)
    watch("LFGListingFrame.activities", function()
        local frame = listing()
        return frame ~= nil and frame.activities or nil
    end)
    watch("LFGListingFrame.ActivityView", activityView)
    watch("ActivityView.ScrollBox", activityScrollBox)
    watch("ActivityView.ScrollBox.view", function()
        local box = activityScrollBox()
        return box ~= nil and box.GetView ~= nil and box:GetView() or nil
    end)
    watch("ActivityView.PlayStyleDropdown", function()
        local view = activityView()
        return view ~= nil and view.PlayStyleDropdown or nil
    end)
    watch("ActivityView.VoiceChatDropdown", function()
        local view = activityView()
        return view ~= nil and view.VoiceChatDropdown or nil
    end)
    watch("LFGBrowseFrame", browse)
    watch("LFGBrowseFrame.CategoryDropdown", function()
        local frame = browse()
        return frame ~= nil and frame.CategoryDropdown or nil
    end)
    watch("LFGBrowseFrame.ActivityDropdown", function()
        local frame = browse()
        return frame ~= nil and frame.ActivityDropdown or nil
    end)
    watch("LFGBrowseFrame.ActivityDropdown.selectedValues", function()
        local frame = browse()
        local dropdown = frame ~= nil and frame.ActivityDropdown or nil
        return dropdown ~= nil and dropdown.selectedValues or nil
    end)
end

-- The action bars (WoW: Forever): on 2026-11-17 a fight in Bear Form had
-- the stance bar's and the pet bar's own event handlers run "tainted by
-- WowVision", so Edit Mode's moves of every bottom bar were blocked and the
-- bars stayed broken until a reload; no WowVision key was pressed in that
-- fight. Those handlers read the bars' fields (showAllButtons,
-- isShownExternal, shownButtonContainers, the grid settings), the buttons',
-- Edit Mode's and the controller's event frames, so all of them are
-- watched, and the gamepad bars too (their flyout update failed in the same
-- fight). The quest map is watched because its log was walked in a fight
-- before. Only reads; a get is nil where the frame does not exist.
local BAR_NAMES = {
    "MainActionBar",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarRight",
    "MultiBarLeft",
    "MultiBar5",
    "MultiBar6",
    "MultiBar7",
    "StanceBar",
    "PetActionBar",
    "OverrideActionBar",
}
do
    local watch = WowVision.taintWatch.watch
    local function global(name)
        return function()
            local value = _G[name]
            return type(value) == "table" and value or nil
        end
    end
    for _, name in ipairs({
        "EditModeManagerFrame",
        "ActionBarButtonEventsFrame",
        "ActionBarActionEventsFrame",
        "MicroMenuContainer",
        "GamepadMainActionBarFrame",
        "QuestMapFrame",
    }) do
        watch(name, global(name))
    end
    watch("GamepadMainActionBarFrame.PageUnit", function()
        local frame = _G.GamepadMainActionBarFrame
        return type(frame) == "table" and frame.PageUnit or nil
    end)
    for _, part in ipairs({ "QuestsFrame", "DetailsFrame" }) do
        watch("QuestMapFrame." .. part, function()
            local frame = _G.QuestMapFrame
            return type(frame) == "table" and frame[part] or nil
        end)
    end
    WowVision.taintWatch.watchList("ActionBars", function()
        local list = {}
        for _, name in ipairs(BAR_NAMES) do
            local bar = _G[name]
            if type(bar) == "table" then
                tinsert(list, { name = name, tbl = bar })
                for _, key in ipairs({ "shownButtonContainers", "oldGridSettings" }) do
                    if type(bar[key]) == "table" then
                        tinsert(list, { name = name .. "." .. key, tbl = bar[key] })
                    end
                end
                if type(bar.actionButtons) == "table" then
                    for index, button in ipairs(bar.actionButtons) do
                        tinsert(list, { name = name .. ".button" .. index, tbl = button })
                    end
                end
            end
        end
        return list
    end)
end

-- The bags (WoW: Forever): on 2026-11-17, out of combat and in a session
-- without a fight, using an armour set from the bags by WowVision's secure
-- right click was refused (UseContainerItem forbidden, "WowVision"). The
-- click (ContainerFrameItemButton_OnClick) reads the item button, the
-- merchant's refund item, the bank's panel and type, ItemButtonUtil,
-- ItemLocation, and the globals of every window it checks (several are
-- made by load-on-demand addons: a load run by addon code makes them
-- tainted globals). All of them are watched.
local BAG_CLICK_GLOBALS = {
    "ContainerFrameItemButton_OnClick",
    "MerchantFrame_ResetRefundItem",
    "BankUtil_IsAccountBankDepositRefundable",
    "ItemButtonUtil",
    "ItemLocation",
    "MerchantFrame",
    "AuctionHouseFrame",
    "AzeriteRespecFrame",
    "RuneforgeFrame",
    "BankFrame",
    "GuildBankFrame",
    "MailFrame",
    "AuctionFrame",
    "TradeFrame",
    "ItemUpgradeFrame",
    "ObliterumForgeFrame",
    "ChallengesKeystoneFrame",
    "CollectionsJournal",
    "OpenAllBags",
    "CloseAllBags",
    "ContainerFrame_GenerateFrame",
    "UpdateContainerFrameAnchors",
    "ContainerFrameSettingsManager",
}
do
    local watch = WowVision.taintWatch.watch
    for _, name in ipairs(BAG_CLICK_GLOBALS) do
        WowVision.taintWatch.watchGlobal(name)
        bagGlobals[name] = true
    end
    -- What building a bag frame reads as the bags open (OpenAllBags,
    -- ContainerFrame_GenerateFrame, UpdateContainerFrameAnchors): on
    -- 2026-11-17 every field of every bag button was WowVision's at a refused
    -- use, so the build that wrote them had read something of WowVision's.
    for _, name in ipairs({
        "MerchantFrame",
        "BankFrame",
        "ItemButtonUtil",
        "ItemLocation",
        "ContainerFrameSettingsManager",
        "ContainerFrameContainer",
    }) do
        watch(name, function()
            local value = _G[name]
            return type(value) == "table" and value or nil
        end)
    end
    watch("BankFrame.BankPanel", function()
        local frame = _G.BankFrame
        return type(frame) == "table" and frame.BankPanel or nil
    end)
    WowVision.taintWatch.watchList("Bags", function()
        local list = {}
        local frames = { { name = "Combined", frame = _G.ContainerFrameCombinedBags } }
        for index = 1, (NUM_CONTAINER_FRAMES or 13) do
            tinsert(frames, { name = "Bag" .. index, frame = _G["ContainerFrame" .. index] })
        end
        for _, entry in ipairs(frames) do
            local frame = entry.frame
            if type(frame) == "table" and frame:IsShown() then
                tinsert(list, { name = entry.name, tbl = frame })
                if type(frame.Items) == "table" then
                    for index, button in ipairs(frame.Items) do
                        tinsert(list, { name = entry.name .. ".item" .. index, tbl = button })
                    end
                end
            end
        end
        return list
    end)
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
