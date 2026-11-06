-- Sorts the lines of a unit tooltip into kinds, so the target announcements
-- can leave some kinds out (core/targeting/targetTooltip.lua). Pure Lua so
-- the headless tests run it.
--
-- A line is sorted by its tooltip data line type where the client gives one
-- (Retail and WoW: Forever fill unit tooltips from C_TooltipInfo), else by
-- comparing its text with the game's own words and the unit's own facts
-- (classic clients, and the untyped lines of the others). A line that can
-- be neither (secret text, no type) is "keep": a switch never drops a line
-- it cannot recognise.
local tooltipLines = {}
WowVision.tooltipLines = tooltipLines

-- The typeName of a line whose type came back secret.
tooltipLines.SECRET = {}

-- Kinds a switch can leave out. "name" (line 1), "keep" and "blank" are not
-- among them.
tooltipLines.KINDS = { "level", "guild", "pvp", "quest", "owner", "other" }

-- Enum.TooltipDataLineType names to kinds; a typed line not listed here is
-- "other", "None" goes to the text rules.
local TYPE_KINDS = {
    UnitName = "name",
    UnitLevel = "level",
    UnitType = "level",
    UnitDead = "keep",
    UnitOwner = "owner",
    QuestTitle = "quest",
    QuestObjective = "quest",
    QuestPlayer = "quest",
    UnitCriteriaProgress = "quest",
    Blank = "blank",
}

local function isSecret(value)
    return WowVision.secrets.isSecret(value)
end

-- The text without colour codes, textures, atlas and hyperlink markup,
-- trimmed (as Tooltip:isBlank strips it).
function tooltipLines.strip(text)
    local stripped =
        text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h", "")
    return (stripped:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A Lua pattern matching a whole line made from a game format string:
-- "%s's Pet" becomes "^.+'s Pet$".
function tooltipLines.formatPattern(format)
    local marked = format:gsub("%%%d%$s", "\001"):gsub("%%s", "\001")
    local escaped = marked:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    return "^" .. escaped:gsub("\001", ".+") .. "$"
end

-- facts: levelWord ("Level"), keepWords / pvpWords (sets of whole lines),
-- guild (the unit's guild name), ownerPatterns, isPlayer, playerControlled.
local function classifyText(index, left, right, facts)
    if isSecret(left) or isSecret(right) then
        return "keep"
    end
    local text = tooltipLines.strip(left or "")
    if text == "" then
        if tooltipLines.strip(right or "") == "" then
            return "blank"
        end
        return "other"
    end
    if facts.keepWords ~= nil and facts.keepWords[text] then
        return "keep"
    end
    local levelWord = facts.levelWord
    if levelWord ~= nil and text:sub(1, #levelWord + 1) == levelWord .. " " then
        return "level"
    end
    if facts.guild ~= nil and index <= 3 and text:find(facts.guild, 1, true) ~= nil then
        return "guild"
    end
    if facts.pvpWords ~= nil and facts.pvpWords[text] then
        return "pvp"
    end
    if facts.ownerPatterns ~= nil and facts.playerControlled and not facts.isPlayer then
        for _, pattern in ipairs(facts.ownerPatterns) do
            if text:find(pattern) ~= nil then
                return "owner"
            end
        end
    end
    -- An NPC's title ("<Innkeeper>") says what the NPC is for: always read.
    if index == 2 and not facts.isPlayer and text:find("^<.+>$") ~= nil then
        return "keep"
    end
    return "other"
end

-- lines: { left, right, typeName = name | SECRET | nil } per tooltip line.
-- Returns one kind per line.
function tooltipLines.classify(lines, facts)
    local kinds = {}
    for index, line in ipairs(lines) do
        local kind
        if index == 1 then
            kind = "name"
        else
            local typeName = line.typeName
            if typeName ~= nil and typeName ~= tooltipLines.SECRET and typeName ~= "None" then
                kind = TYPE_KINDS[typeName] or "other"
            end
            if kind == nil then
                kind = classifyText(index, line[1], line[2], facts)
            end
        end
        kinds[index] = kind
    end
    return kinds
end

-- The lines left after dropping the kinds in drop (a set); blank lines go
-- too once anything is dropped.
function tooltipLines.filter(lines, kinds, drop)
    local kept = {}
    for index, line in ipairs(lines) do
        local kind = kinds[index]
        if kind ~= "blank" and not drop[kind] then
            tinsert(kept, line)
        end
    end
    return kept
end
