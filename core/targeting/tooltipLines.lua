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
    -- A no-break space counts as a space.
    stripped = stripped:gsub("\194\160", " ")
    return (stripped:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A Lua pattern matching a whole line made from a game format string:
-- "%s's Pet" becomes "^.+'s Pet$".
function tooltipLines.formatPattern(format)
    local marked = format:gsub("%%%d%$s", "\001"):gsub("%%s", "\001")
    local escaped = marked:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    return "^" .. escaped:gsub("\001", ".+") .. "$"
end

-- facts: levelWord ("Level"), level (the unit's level number), className
-- (its class, as the game names it), creatureType, keepWords (set of whole lines),
-- pvpWords (set of whole lines in lower case), guild (the unit's guild
-- name), ownerPatterns, isPlayer, playerControlled.
local function isLevelLine(index, text, facts, seenLevel)
    local levelWord = facts.levelWord
    if levelWord ~= nil and text:lower():sub(1, #levelWord + 1) == levelWord:lower() .. " " then
        return true
    end
    -- The unit's level as the first number of the first line that could
    -- hold it (name, title or guild, level: line 3 at most). Counts ("2/8"),
    -- objectives ("Kobolde: 2") and percentages never are the level line.
    local level = facts.level
    if seenLevel or level == nil or level <= 0 or index > 3 then
        return false
    end
    if text:find("[/:%%]") ~= nil then
        return false
    end
    return text:match("%d+") == tostring(level)
end

local function classifyText(index, left, right, facts, seenLevel)
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
    if isLevelLine(index, text, facts, seenLevel) then
        return "level"
    end
    -- A player's class on a line of its own (WoW: Forever).
    if facts.isPlayer and facts.className ~= nil and text == facts.className then
        return "level"
    end
    -- An NPC's creature type on a line of its own ("Wildtier", WoW: Forever).
    if not facts.isPlayer and facts.creatureType ~= nil and text == facts.creatureType then
        return "level"
    end
    if facts.guild ~= nil and index <= 3 and text:find(facts.guild, 1, true) ~= nil then
        return "guild"
    end
    if facts.pvpWords ~= nil and facts.pvpWords[text:lower()] then
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
    local seenLevel = false
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
                kind = classifyText(index, line[1], line[2], facts, seenLevel)
                -- An NPC's line between its name and its level is its title
                -- ("Gastwirt" on WoW: Forever, without the brackets).
                if kind == "other" and not seenLevel and not facts.isPlayer and not facts.playerControlled then
                    kind = "keep"
                end
            end
        end
        if kind == "level" then
            seenLevel = true
        end
        kinds[index] = kind
    end
    -- No level line found: the title rule had nothing to go by.
    if not seenLevel then
        for index, kind in ipairs(kinds) do
            if kind == "keep" and index > 1 and not facts.isPlayer then
                kinds[index] = classifyText(index, lines[index][1], lines[index][2], facts)
            end
        end
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
