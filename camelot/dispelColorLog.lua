-- LOCAL (not for a PR): can an addon tell an aura's dispel type in combat?
-- Always on: it keeps this session's readings in
-- WowVisionDump.dispelColorLog.current and the session before in .previous
-- (on disk after /reload or logout). /wv dispellog prints a summary to chat.
--
-- The question behind it (Sku's debuff monitor port): in combat every aura
-- read is closed to addons, and our own tooltip filled with an aura gives
-- its dispel type only as a secret word (line 1, right side). The game
-- colours that word by type. If the COLOUR can still be read in combat, the
-- type is known as a plain fact and short forms, per-type sounds and
-- per-type switches all work.
--
-- No debuff on a party member is needed: it reads every typed aura it can
-- fill a tooltip with, on you, your target, your focus and the party,
-- buffs and debuffs alike (your own magic buffs, your DoTs on a mob), at
-- every aura change, at the start and end of each fight, and every 2
-- seconds in a fight. Out of combat the same readings are the positive
-- control: the colour must be plain there, and the plain dispel type from
-- the index read says which colour belongs to which type.
--
-- Per reading it records whether each of these is plain or secret: the
-- tooltip's line count, the type word, its colour, its width, whether the
-- right side is shown, and the left side's colour (a control). A reading
-- that looks like the one before for the same aura only counts up.

local secrets = WowVision.secrets
local module = WowVision.base.groupHealth

local LOG_MAX = 5000 -- readings per session; repeats count up instead
local MAX_INDEX = 40 -- auras per unit and filter
local SCAN_EVERY = 2 -- seconds, in a fight
local UNITS = { "player", "target", "focus", "party1", "party2", "party3", "party4" }
local FILTERS = { "HELPFUL", "HARMFUL", "HARMFUL|RAID" }
local TIP = "WowVisionDispelColorTooltip"

local isSecret = secrets.isSecret

local log -- this session's { started, entries, stats }
local lastByAura = {} -- unit|filter|index -> the last entry for it
local tooltip

local function clock()
    local now = GetTime()
    return date("%H:%M:%S") .. string.format(".%02d", math.floor((now % 1) * 100))
end

local function newStats()
    return { readings = 0, fights = 0, combat = {}, calm = {}, printed = {} }
end

local function session()
    if log ~= nil then
        return log
    end
    WowVisionDump = WowVisionDump or {}
    local saved = WowVisionDump.dispelColorLog
    if type(saved) ~= "table" then
        saved = {}
    end
    log = { started = date("%Y-%m-%d %H:%M:%S"), entries = {}, stats = newStats() }
    WowVisionDump.dispelColorLog = { current = log, previous = saved.current }
    return log
end

local function count(bucket, key)
    bucket[key] = (bucket[key] or 0) + 1
end

-- A value as the log keeps it: "secret", or the plain value (numbers
-- rounded so tiny drifts do not make new entries).
local function plain(value)
    if isSecret(value) then
        return "secret"
    end
    if type(value) == "number" then
        return math.floor(value * 1000 + 0.5) / 1000
    end
    return value
end

-- The dispel type a plain colour belongs to, by the game's own colours.
local TYPE_COLORS = {
    Magic = "DEBUFF_TYPE_MAGIC_COLOR",
    Curse = "DEBUFF_TYPE_CURSE_COLOR",
    Disease = "DEBUFF_TYPE_DISEASE_COLOR",
    Poison = "DEBUFF_TYPE_POISON_COLOR",
    Bleed = "DEBUFF_TYPE_BLEED_COLOR",
    None = "DEBUFF_TYPE_NONE_COLOR",
}

local function typeOfColor(r, g, b)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end
    for name, global in pairs(TYPE_COLORS) do
        local color = _G[global]
        if color ~= nil and color.r ~= nil then
            if math.abs(color.r - r) < 0.02 and math.abs(color.g - g) < 0.02 and math.abs(color.b - b) < 0.02 then
                return name
            end
        end
    end
    return "other"
end

local function fill(unit, index, filter)
    if tooltip == nil then
        tooltip = CreateFrame("GameTooltip", TIP, UIParent, "GameTooltipTemplate")
    end
    tooltip:ClearLines()
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    local ok, err = pcall(tooltip.SetUnitAura, tooltip, unit, index, filter)
    if not ok then
        return nil, err
    end
    local okLines, lines = pcall(tooltip.NumLines, tooltip)
    if not okLines then
        return nil, lines
    end
    return lines
end

local function call(object, method)
    local results = { pcall(object[method], object) }
    if not results[1] then
        return "refused"
    end
    return select(2, unpack(results))
end

-- The plain dispel type from the index read, where the game allows it.
local function indexType(unit, index, filter)
    if C_UnitAuras == nil or C_UnitAuras.GetAuraDataByIndex == nil then
        return "no api"
    end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
    if not ok then
        return "refused"
    end
    if aura == nil then
        return "none"
    end
    if isSecret(aura.dispelName) then
        return "secret"
    end
    return aura.dispelName or "untyped"
end

local function signature(entry)
    return table.concat({
        tostring(entry.combat), tostring(entry.lines), tostring(entry.rightShown), tostring(entry.word),
        tostring(entry.r), tostring(entry.g), tostring(entry.b), tostring(entry.width), tostring(entry.indexType),
        tostring(entry.leftR), tostring(entry.name),
    }, "|")
end

-- Prints the first in-combat reading of each kind once per session.
local function firstOfKind(entry)
    if not entry.combat or entry.word == nil then
        return
    end
    local kind = entry.r == "secret" and "colour secret" or ("colour readable" .. (entry.colorType and (", " .. entry.colorType) or ""))
    local printed = session().stats.printed
    if printed[kind] then
        return
    end
    printed[kind] = true
    print("WowVision dispel colour test, in combat: " .. kind .. " (" .. entry.unit .. " " .. entry.filter .. " " .. entry.index .. ")")
end

local function record(unit, index, filter, lines)
    local inCombat = InCombatLockdown() and true or false
    local right = _G[TIP .. "TextRight1"]
    local left = _G[TIP .. "TextLeft1"]
    local entry = {
        unit = unit,
        filter = filter,
        index = index,
        combat = inCombat,
        lines = plain(lines),
        indexType = indexType(unit, index, filter),
    }
    if right ~= nil then
        entry.rightShown = plain(call(right, "IsShown"))
        local text = call(right, "GetText")
        if text == nil then
            entry.word = nil
        elseif isSecret(text) then
            entry.word = "secret"
        else
            entry.word = text
        end
        local r, g, b = call(right, "GetTextColor")
        entry.r, entry.g, entry.b = plain(r), plain(g), plain(b)
        entry.width = plain(call(right, "GetStringWidth"))
        entry.colorType = typeOfColor(entry.r, entry.g, entry.b)
    end
    if left ~= nil then
        local text = call(left, "GetText")
        entry.name = isSecret(text) and "secret" or text
        entry.leftR = plain((call(left, "GetTextColor")))
    end
    -- only auras with a type word are what the question is about; untyped
    -- ones are counted, not listed
    local stats = session().stats
    stats.readings = stats.readings + 1
    local bucket = inCombat and stats.combat or stats.calm
    if entry.word == nil or entry.word == "" then
        count(bucket, "no type word")
        return
    end
    count(bucket, "type word " .. (entry.word == "secret" and "secret" or "plain"))
    count(bucket, "colour " .. (entry.r == "secret" and "secret" or (entry.r == "refused" and "refused" or "plain")))
    count(bucket, "width " .. (entry.width == "secret" and "secret" or "plain"))
    if entry.colorType ~= nil then
        count(bucket, "colour type " .. entry.colorType)
    end
    firstOfKind(entry)

    local key = unit .. "|" .. filter .. "|" .. index
    entry.sig = signature(entry)
    local last = lastByAura[key]
    if last ~= nil and last.sig == entry.sig then
        last.seen = (last.seen or 1) + 1
        return
    end
    entry.at = clock()
    local entries = session().entries
    tinsert(entries, entry)
    while #entries > LOG_MAX do
        tremove(entries, 1)
    end
    lastByAura[key] = entry
end

local function scanUnit(unit)
    local okExists, exists = pcall(UnitExists, unit)
    if not okExists or isSecret(exists) or not exists then
        return
    end
    for _, filter in ipairs(FILTERS) do
        for index = 1, MAX_INDEX do
            local lines, err = fill(unit, index, filter)
            if lines == nil then
                count(session().stats, "fill refused")
                session().lastRefusal = tostring(err)
                break
            end
            if isSecret(lines) then
                -- cannot tell where the list ends: record this one, go on
                record(unit, index, filter, lines)
                if index >= 3 then
                    break
                end
            elseif lines == 0 then
                break
            else
                record(unit, index, filter, lines)
            end
        end
    end
end

local dirty = {}
local anyDirty = false
local nextScan = 0

local function markAll()
    for _, unit in ipairs(UNITS) do
        dirty[unit] = true
    end
    anyDirty = true
end

local frame = CreateFrame("Frame")
-- one frame per unit, so the event's unit never has to be compared
for _, unit in ipairs(UNITS) do
    local unitFrame = CreateFrame("Frame")
    unitFrame:RegisterUnitEvent("UNIT_AURA", unit)
    unitFrame:SetScript("OnEvent", function()
        dirty[unit] = true
        anyDirty = true
    end)
end
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
        dirty.target = true
        anyDirty = true
        return
    elseif event == "PLAYER_FOCUS_CHANGED" then
        dirty.focus = true
        anyDirty = true
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        local stats = session().stats
        stats.fights = stats.fights + 1
        tinsert(session().entries, { at = clock(), what = "fight start" })
    elseif event == "PLAYER_REGEN_ENABLED" then
        tinsert(session().entries, { at = clock(), what = "fight end" })
    end
    markAll()
end)
frame:SetScript("OnUpdate", function()
    local now = GetTime()
    if InCombatLockdown() and now >= nextScan then
        nextScan = now + SCAN_EVERY
        markAll()
    end
    if not anyDirty then
        return
    end
    anyDirty = false
    for unit in pairs(dirty) do
        dirty[unit] = nil
        local ok, err = pcall(scanUnit, unit)
        if not ok then
            session().lastError = tostring(err)
            count(session().stats, "scan errors")
        end
    end
end)

-- Summary ----------------------------------------------------------------------------

local function bucketLine(label, bucket)
    local parts = {}
    for key, value in pairs(bucket) do
        tinsert(parts, key .. " " .. value)
    end
    table.sort(parts)
    if #parts == 0 then
        return label .. ": no typed aura read"
    end
    return label .. ": " .. table.concat(parts, ", ")
end

-- Out of combat: which plain colour came with which plain dispel type.
local function mapping(data)
    local seen = {}
    for _, entry in ipairs(data.entries) do
        if entry.combat == false and entry.colorType ~= nil and entry.indexType ~= nil then
            seen[entry.indexType .. " -> " .. entry.colorType] = true
        end
    end
    local parts = {}
    for key in pairs(seen) do
        tinsert(parts, key)
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

local function summary(which)
    local saved = WowVisionDump and WowVisionDump.dispelColorLog or nil
    local data = saved ~= nil and saved[which] or nil
    if data == nil then
        return { "WowVision dispel colour test: nothing recorded (" .. which .. ")" }
    end
    local stats = data.stats
    local lines = {
        "WowVision dispel colour test (" .. which .. ", since " .. data.started .. "): " .. stats.readings
            .. " readings, " .. stats.fights .. " fights, " .. #data.entries .. " log entries",
        bucketLine("In combat", stats.combat),
        bucketLine("Out of combat", stats.calm),
        "Out of combat, type to colour: " .. mapping(data),
    }
    if stats["fill refused"] then
        tinsert(lines, "Tooltip fill refused " .. stats["fill refused"] .. " times, last: " .. tostring(data.lastRefusal))
    end
    if stats["scan errors"] then
        tinsert(lines, "Scan errors " .. stats["scan errors"] .. ", last: " .. tostring(data.lastError))
    end
    return lines
end

module:registerCommand({
    name = "dispellog",
    scope = "WowVision",
    description = "Dispel colour test: summary of this session (dispellog previous: the one before)",
    func = function(args)
        local which = (type(args) == "string" and args:find("prev")) and "previous" or "current"
        for _, line in ipairs(summary(which)) do
            print(line)
        end
    end,
})
