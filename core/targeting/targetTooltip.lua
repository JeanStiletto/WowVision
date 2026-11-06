-- Shorter target announcements: one switch per kind of tooltip line, saying
-- whether the hard and soft target alerts read it (sorted by
-- core/targeting/tooltipLines.lua). All switches default on, so the full
-- tooltip is read until the player turns one off. Lines that cannot be
-- recognised (secret text without a line type, in instances and fights on
-- WoW: Forever) are always read.
--
-- Every hard target change is also recorded, quietly, in
-- WowVisionDump.targetTooltip (the last CAPTURE_MAX): how each line was
-- sorted and whether its type and text were secret, with the restriction
-- state of the moment. /wv tooltipcheck prints the newest ones to chat;
-- /wv secretforce turns the client's forced restriction settings on and
-- off, to see the dungeon rules in the open world.
local module = WowVision.base.targeting:createModule("targetTooltip")
local L = module.L
module:setLabel(L["Target Tooltip"])
local settings = module:hasSettings()

local tooltipLines = WowVision.tooltipLines
local secrets = WowVision.secrets

local CAPTURE_MAX = 30

local SWITCHES = {
    { kind = "level", key = "readLevel", label = L["Read Level and Type"] },
    { kind = "guild", key = "readGuild", label = L["Read Guild"] },
    { kind = "pvp", key = "readPvP", label = L["Read PvP and Faction"] },
    { kind = "quest", key = "readQuest", label = L["Read Quest Lines"] },
    { kind = "owner", key = "readOwner", label = L["Read Pet Owner"] },
    { kind = "other", key = "readOther", label = L["Read Other Information"] },
}

for _, switch in ipairs(SWITCHES) do
    settings:add({
        type = "Bool",
        key = switch.key,
        label = switch.label,
        default = true,
    })
end

-- The client's switches that force a restriction anywhere (Retail and WoW:
-- Forever; a client without them reads them as missing).
local FORCE_CVARS = {
    map = "secretMapRestrictionsForced",
    combat = "secretCombatRestrictionsForced",
    encounter = "secretEncounterRestrictionsForced",
    challenge = "secretChallengeModeRestrictionsForced",
    pvp = "secretPvPMatchRestrictionsForced",
}
local FORCE_ORDER = { "map", "combat", "encounter", "challenge", "pvp" }

local function plain(value)
    if value == nil or secrets.isSecret(value) then
        return nil
    end
    return value
end

local function flag(value)
    if value == nil then
        return "nil"
    end
    if secrets.isSecret(value) then
        return "secret"
    end
    return value and "yes" or "no"
end

-- Enum.TooltipDataLineType values to their names.
local lineTypeNames = {}
if Enum ~= nil and Enum.TooltipDataLineType ~= nil then
    for name, value in pairs(Enum.TooltipDataLineType) do
        lineTypeNames[value] = name
    end
end

-- Pet, minion, guardian lines ("Name's Pet"), from the game's own words.
local ownerPatterns = {}
for _, format in ipairs({
    UNITNAME_TITLE_PET,
    UNITNAME_TITLE_MINION,
    UNITNAME_TITLE_GUARDIAN,
    UNITNAME_TITLE_CREATION,
    UNITNAME_TITLE_COMPANION,
    UNITNAME_TITLE_CHARM,
}) do
    if type(format) == "string" then
        tinsert(ownerPatterns, tooltipLines.formatPattern(format))
    end
end

local function wordSet(words, lower)
    local set = {}
    for _, word in pairs(words) do
        if type(word) == "string" and word ~= "" then
            set[lower and word:lower() or word] = true
        end
    end
    return set
end

-- What the text rules compare lines with. Every read that comes back secret
-- is left out, so its lines stay.
local function unitFacts(unit)
    local facts = {
        levelWord = type(LEVEL) == "string" and LEVEL or nil,
        keepWords = wordSet({ DEAD, CORPSE }),
        pvpWords = wordSet({ PVP, PVP_ENABLED, FACTION_ALLIANCE, FACTION_HORDE }, true),
        ownerPatterns = ownerPatterns,
    }
    local _, factionName = UnitFactionGroup(unit)
    factionName = plain(factionName)
    if factionName ~= nil and factionName ~= "" then
        facts.pvpWords[factionName:lower()] = true
    end
    local level = plain(UnitLevel(unit))
    if type(level) == "number" then
        facts.level = level
    end
    local className = plain(UnitClass(unit))
    if type(className) == "string" and className ~= "" then
        facts.className = className
    end
    facts.isPlayer = plain(UnitIsPlayer(unit)) == true
    facts.playerControlled = plain(UnitPlayerControlled(unit)) == true
    if facts.isPlayer and GetGuildInfo ~= nil then
        local guild = plain(GetGuildInfo(unit))
        if guild ~= nil and guild ~= "" then
            facts.guild = guild
        end
    end
    return facts
end

-- Puts each line's tooltip data type on it, where the frame was filled from
-- tooltip data (Retail, WoW: Forever): Blizzard's handler keeps the data on
-- the frame and notes each line's place as lineIndex. Returns whether there
-- was data.
local function attachLineTypes(frame, lines)
    if frame == nil or frame.GetPrimaryTooltipData == nil then
        return false
    end
    local data = frame:GetPrimaryTooltipData()
    if data == nil or (canaccesstable ~= nil and not canaccesstable(data)) then
        return false
    end
    local dataLines = data.lines
    if type(dataLines) ~= "table" or (canaccesstable ~= nil and not canaccesstable(dataLines)) then
        return false
    end
    for _, lineData in ipairs(dataLines) do
        local index = plain(lineData.lineIndex)
        local line = index ~= nil and lines[index] or nil
        if line ~= nil then
            local lineType = lineData.type
            if secrets.isSecret(lineType) then
                line.typeName = tooltipLines.SECRET
            elseif lineType ~= nil then
                line.typeName = lineTypeNames[lineType] or ("type " .. tostring(lineType))
            end
        end
    end
    return true
end

-- The tooltip's lines, each with its kind; hasData says whether line types
-- were there.
function module:sortLines(tooltip, unit)
    local lines = tooltip:readLines()
    local hasData = attachLineTypes(tooltip.activeFrame, lines)
    local facts = unitFacts(unit)
    local kinds = tooltipLines.classify(lines, facts)
    return lines, kinds, hasData, facts
end

-- The kinds switched off (left out), or nil when the full tooltip is read.
function module:dropSet()
    if not self:getEnabled() then
        return nil
    end
    local drop
    for _, switch in ipairs(SWITCHES) do
        if self.settings[switch.key] == false then
            drop = drop or {}
            drop[switch.kind] = true
        end
    end
    return drop
end

-- What a target alert says: the tooltip without the switched-off kinds.
-- The text may be secret (joined, never compared).
function module:read(tooltip, unit)
    local drop = self:dropSet()
    if drop == nil or tooltip.activeFrame == nil then
        return tooltip:getText()
    end
    local lines, kinds = self:sortLines(tooltip, unit)
    local result = {}
    for _, line in ipairs(tooltipLines.filter(lines, kinds, drop)) do
        tinsert(result, tooltip.reader:formatLine(line[1], line[2]))
    end
    return tooltip.reader:joinLines(result)
end

local function captureList()
    WowVisionDump = WowVisionDump or {}
    if type(WowVisionDump.targetTooltip) ~= "table" then
        WowVisionDump.targetTooltip = {}
    end
    return WowVisionDump.targetTooltip
end

local function activeRestrictions()
    if C_RestrictedActions == nil or C_RestrictedActions.IsAddOnRestrictionActive == nil then
        return "n/a"
    end
    if Enum == nil or Enum.AddOnRestrictionType == nil then
        return "n/a"
    end
    local active = {}
    for name, value in pairs(Enum.AddOnRestrictionType) do
        if plain(C_RestrictedActions.IsAddOnRestrictionActive(value)) == true then
            tinsert(active, name)
        end
    end
    table.sort(active)
    if #active == 0 then
        return "none"
    end
    return table.concat(active, ",")
end

local function forcedState()
    local parts = {}
    for _, key in ipairs(FORCE_ORDER) do
        local value = C_CVar.GetCVar(FORCE_CVARS[key])
        tinsert(parts, key .. "=" .. (value == nil and "missing" or tostring(value)))
    end
    return table.concat(parts, " ")
end

-- Shortened, with every byte outside plain ASCII written as \number, so
-- a no-break space or an odd character shows in the saved file.
local function short(text)
    if #text > 60 then
        text = text:sub(1, 57) .. "..."
    end
    return (text:gsub("[^\32-\126]", function(c)
        return "\\" .. c:byte()
    end))
end

-- The words and facts the text rules compared with.
local function factsText(facts)
    local pvp = {}
    for word in pairs(facts.pvpWords) do
        tinsert(pvp, short(word))
    end
    table.sort(pvp)
    return string.format(
        "level word %s, level %s, class %s, player %s, pvp words %s",
        facts.levelWord and short(facts.levelWord) or "none",
        tostring(facts.level),
        facts.className and short(facts.className) or "none",
        tostring(facts.isPlayer),
        table.concat(pvp, " / ")
    )
end

-- One capture entry; only plain values go in (SavedVariables refuse
-- secrets).
function module:capture(tooltip, unit)
    if tooltip.activeFrame == nil then
        return
    end
    local lines, kinds, hasData, facts = self:sortLines(tooltip, unit)
    local drop = self:dropSet() or {}
    local identity = "n/a"
    if C_Secrets ~= nil and C_Secrets.ShouldUnitIdentityBeSecret ~= nil then
        identity = flag(C_Secrets.ShouldUnitIdentityBeSecret(unit))
    end
    local inInstance, instanceType = IsInInstance()
    local entry = {
        time = date("%Y-%m-%d %H:%M:%S"),
        unit = unit,
        state = string.format(
            "identity secret %s, combat %s, instance %s, restrictions %s, tooltip data %s",
            identity,
            flag(InCombatLockdown()),
            inInstance and tostring(instanceType) or "no",
            activeRestrictions(),
            flag(hasData)
        ),
        forced = forcedState(),
        facts = factsText(facts),
        lines = {},
    }
    for index, line in ipairs(lines) do
        local typeName = line.typeName
        if typeName == tooltipLines.SECRET then
            typeName = "secret"
        end
        local left, right = line[1], line[2]
        local textSecret = secrets.isSecret(left) or secrets.isSecret(right)
        local text = ""
        if not textSecret then
            text = short(tooltipLines.strip((left or "") .. " " .. (right or "")))
        end
        local kept = kinds[index] ~= "blank" and not drop[kinds[index]]
        tinsert(
            entry.lines,
            string.format(
                "%d %s, type %s, text %s, %s%s",
                index,
                kinds[index],
                tostring(typeName or "none"),
                textSecret and "secret" or "plain",
                kept and "read" or "left out",
                text ~= "" and (": " .. text) or ""
            )
        )
    end
    local list = captureList()
    tinsert(list, entry)
    while #list > CAPTURE_MAX do
        tremove(list, 1)
    end
end

-- Called by the targeting module after the hard target's tooltip is set;
-- a broken capture must not stop the announcement.
function module:captureSafely(tooltip, unit)
    local ok, err = pcall(self.capture, self, tooltip, unit)
    if not ok then
        geterrorhandler()(err)
    end
end

module:registerCommand({
    name = "tooltipcheck",
    scope = "WowVision",
    description = "Print the newest target tooltip captures to chat. Usage: /wv tooltipcheck [count]",
    func = function(args)
        local list = captureList()
        local count = tonumber(args) or 1
        if #list == 0 then
            print("Target tooltip check: no capture yet, target something.")
            WowVision:speak("No capture yet")
            return
        end
        local first = math.max(1, #list - count + 1)
        for i = first, #list do
            local entry = list[i]
            print(string.format("Target tooltip %d of %d, %s", i, #list, entry.time))
            print(entry.state)
            print("forced: " .. entry.forced)
            if entry.facts ~= nil then
                print("facts: " .. entry.facts)
            end
            for _, line in ipairs(entry.lines) do
                print(line)
            end
        end
        WowVision:speak(string.format("%d captures printed to chat", #list - first + 1))
    end,
})

module:registerCommand({
    name = "secretforce",
    scope = "WowVision",
    description = "Force the client's addon restrictions anywhere. Usage: /wv secretforce map|combat|encounter|challenge|pvp|off|status",
    func = function(args)
        local which = strtrim(args or ""):lower()
        if which == "" or which == "status" then
            print("Forced restrictions: " .. forcedState())
            WowVision:speak(forcedState())
            return
        end
        if which ~= "off" and FORCE_CVARS[which] == nil then
            print("Usage: /wv secretforce map|combat|encounter|challenge|pvp|off|status")
            return
        end
        for _, key in ipairs(FORCE_ORDER) do
            local name = FORCE_CVARS[key]
            if C_CVar.GetCVar(name) ~= nil then
                local value = (key == which) and "1" or "0"
                C_CVar.SetCVar(name, value)
            end
        end
        local state = forcedState()
        if C_CVar.GetCVar(FORCE_CVARS[which] or FORCE_CVARS.map) == nil then
            print("This client has no forced restriction settings: " .. state)
            WowVision:speak("Not in this client")
            return
        end
        print("Forced restrictions: " .. state)
        WowVision:speak(state)
    end,
})
