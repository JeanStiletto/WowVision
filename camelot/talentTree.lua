local talentTree = {}
WowVision.talentTree = talentTree

local L = WowVision:getLocale()
local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId
local kinds = graph.kinds

-- Talent trees built on the shared talent frame (TalentFrameBaseMixin):
-- the Legacy trees (legacy/tree.lua) and the class talents (talents.lua).
-- Each talent reads its name, rank, and state; Enter buys a rank (a choice
-- node opens its options), Backspace refunds one. The talents read row by
-- row as drawn, each row a context; a tree holding several groups (the
-- class tree's three specializations) reads a stop per group. The pages
-- around the tree are the callers' own.

-- A count of points, singular for one: "1 Point", "5 Points".
function talentTree.pointsText(count)
    return count .. " " .. (count == 1 and L["Point"] or L["Points"])
end

local function isSelectionNode(nodeInfo)
    return nodeInfo.type == Enum.TraitNodeType.Selection or nodeInfo.type == Enum.TraitNodeType.SubTreeSelection
end

-- An entry's name: a sub tree's, or the talent's (its override name, else
-- its spell's).
local function entryName(talentFrame, entryID)
    local entryInfo = talentFrame:GetAndCacheEntryInfo(entryID)
    if entryInfo.subTreeID ~= nil then
        local subTreeInfo = talentFrame:GetAndCacheSubTreeInfo(entryInfo.subTreeID)
        if subTreeInfo ~= nil and subTreeInfo.name ~= nil then
            return subTreeInfo.name
        end
    end
    if entryInfo.definitionID ~= nil then
        local definitionInfo = talentFrame:GetAndCacheDefinitionInfo(entryInfo.definitionID)
        return TalentUtil.GetTalentNameFromInfo(definitionInfo)
    end
    return ""
end

-- A choice node with nothing chosen shows a question mark; it reads its
-- options instead.
local function talentName(button)
    local name = button:GetName()
    if name ~= nil and name ~= "" then
        return name
    end
    local options = {}
    for _, entryID in ipairs(button:GetNodeInfo().entryIDs) do
        tinsert(options, entryName(button:GetTalentFrame(), entryID))
    end
    return L["Choice"] .. ": " .. table.concat(options, ", ")
end

local function rankText(button)
    local nodeInfo = button:GetNodeInfo()
    if FlagsUtil.IsSet(nodeInfo.flags, Enum.TraitNodeFlag.HideMaxRank) then
        return L["rank"] .. " " .. nodeInfo.currentRank
    end
    return L["rank"] .. " " .. nodeInfo.currentRank .. "/" .. nodeInfo.maxRanks
end

-- The talents a locked talent waits for: the start of every inactive arrow
-- into it, as a sighted player follows the arrows.
local function requirementsText(talentFrame, nodeID)
    local names = {}
    for edge in talentFrame.edgePool:EnumerateActive() do
        local edgeInfo = edge:GetEdgeInfo()
        if edgeInfo ~= nil and edgeInfo.targetNode == nodeID and not edgeInfo.isActive then
            local start = edge:GetStartButton()
            if start ~= nil then
                tinsert(names, talentName(start))
            end
        end
    end
    if #names == 0 then
        return nil
    end
    return L["Requires %s"]:format(table.concat(names, ", "))
end

local function stripColors(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The points a locked talent still waits for, in the game's own words: the
-- largest unmet spend condition on its node, the line its tooltip shows
-- (the classic tiers: so many points in the specialization). Asked of the
-- game directly, so the talent frame's condition cache keeps its colors.
local function pointsRequirementText(button)
    local talentFrame = button:GetTalentFrame()
    local nodeInfo = button:GetNodeInfo()
    local configID = talentFrame:GetConfigID()
    if configID == nil or nodeInfo.conditionIDs == nil then
        return nil
    end
    local treeName = talentFrame:GetTraitTreeName(talentFrame:GetTalentTreeID(), nodeInfo.groupIDs)
    local best = nil
    for _, conditionID in ipairs(nodeInfo.conditionIDs) do
        local condInfo = C_Traits.GetConditionInfo(configID, conditionID, true, treeName)
        if
            condInfo ~= nil
            and condInfo.isGate
            and not condInfo.isMet
            and condInfo.tooltipText ~= nil
            and (best == nil or (condInfo.spentAmountRequired or 0) > (best.spentAmountRequired or 0))
        then
            best = condInfo
        end
    end
    return best ~= nil and stripColors(best.tooltipText) or nil
end

-- The state the button's border shows: available (buyable now), locked
-- (with the points and the talents it waits for), or invalid (a refund
-- broke what depends on it). Partly bought, maxed, and unaffordable read
-- through the rank alone. A row that already says its gate leaves the
-- points out.
local function stateText(button, rowGated)
    local states = TalentButtonUtil.BaseVisualState
    local state = button:GetVisualState()
    if state == states.Selectable then
        return L["Available"]
    elseif state == states.Gated or state == states.Locked then
        return nodes.joinLabel(
            L["Locked"],
            not rowGated and pointsRequirementText(button) or nil,
            requirementsText(button:GetTalentFrame(), button:GetNodeID())
        )
    elseif state == states.RefundInvalid or state == states.DisplayError then
        return L["Invalid"]
    end
    return nil
end

local function talentLabel(button, rowGated)
    return nodes.joinLabel(
        talentName(button),
        rankText(button),
        stateText(button, rowGated),
        button:GetSearchMatchType() ~= nil and L["Search Match"]
    )
end

-- The button's own tooltip (rank, description, next rank, cost, the click
-- instructions, and what blocks it), built into the reader's tooltip the
-- way the button builds it on hover. A choice node's own tooltip is only
-- its errors (its options carry the rest), so it reads the chosen option.
local function talentTooltip(tooltip, button)
    local nodeInfo = button:GetNodeInfo()
    if isSelectionNode(nodeInfo) then
        GameTooltip_SetTitle(tooltip, talentName(button))
        local entryID = button:GetSelectedEntryID()
        if entryID ~= nil then
            tooltip:AppendInfo("GetTraitEntry", entryID, nodeInfo.currentRank)
        end
    else
        button:AddTooltipTitle(tooltip)
        button:AddTooltipInfo(tooltip)
        button:AddTooltipDescription(tooltip)
        button:AddTooltipCost(tooltip)
        if button:ShouldShowTooltipInstructions() then
            button:AddTooltipInstructions(tooltip)
        end
    end
    if button:ShouldShowTooltipErrors() then
        button:AddTooltipErrors(tooltip)
    end
    tooltip:Show()
end

-- A choice is open when the node can take a choice and the option is
-- available (the choice button's own test).
local function choiceAvailable(button, entryID)
    local talentFrame = button:GetTalentFrame()
    return button:CanSelectChoice()
        and talentFrame:GetAndCacheEntryInfo(entryID).isAvailable
        and not talentFrame:IsLocked()
end

-- What clicking an option does: picks it, or buys another rank of the
-- option already chosen. True when it did either.
local function chooseEntry(button, entryID)
    if not choiceAvailable(button, entryID) then
        return false
    end
    if button:GetSelectedEntryID() == entryID then
        local nodeInfo = button:GetNodeInfo()
        if nodeInfo.canPurchaseRank and not button:IsLocked() and button:CanAfford() then
            button:PlaySelectSound()
            button:GetTalentFrame():PurchaseRank(button:GetNodeID())
            return true
        end
        return false
    end
    button:SetSelectedEntryID(entryID)
    return true
end

-- The options of a choice node, as the mouse's hover menu shows them: Enter
-- picks one and returns to the tree; a locked option stays put.
local function renderChoices(builder, talentFrame, nodeID)
    local button = talentFrame:GetTalentButtonByNodeID(nodeID)
    if button == nil or button:GetNodeInfo() == nil then
        return
    end
    builder:pushContext("choices", talentName(button))
    for _, entryID in ipairs(button:GetNodeInfo().entryIDs) do
        local capturedEntry = entryID
        builder:addItem(ControlId.structural("choice:" .. capturedEntry), {
            controlType = graph.controlTypes.button,
            announcements = {
                {
                    text = function()
                        return entryName(talentFrame, capturedEntry)
                    end,
                    kind = kinds.label,
                },
                {
                    text = function()
                        return button:GetSelectedEntryID() == capturedEntry and L["Selected"] or nil
                    end,
                    kind = kinds.selected,
                    live = "focus",
                },
                {
                    text = function()
                        return not choiceAvailable(button, capturedEntry) and L["Locked"] or nil
                    end,
                    kind = kinds.enabled,
                },
            },
            onActivate = function()
                if chooseEntry(button, capturedEntry) then
                    local host = WowVision.graphHost
                    host:pop(host:focusedStack())
                end
            end,
            tooltipFrame = button,
            tooltip = {
                type = "Game",
                mode = "immediate",
                populate = function(tooltip)
                    local nodeInfo = button:GetNodeInfo()
                    local isCurrent = button:GetSelectedEntryID() == capturedEntry
                    GameTooltip_SetTitle(tooltip, entryName(talentFrame, capturedEntry))
                    tooltip:AppendInfo("GetTraitEntry", capturedEntry, isCurrent and nodeInfo.currentRank or 0)
                    tooltip:Show()
                end,
            },
        })
    end
    builder:popContext()
end

-- A talent: Enter buys a rank (a choice node opens its options instead),
-- Backspace refunds one, drag picks up an active ability. The button is
-- pooled and found by its node on every read and press. The context menu
-- adds the shift-clicks: link in chat, and buy back what a reset removed.
local function talentNode(talentFrame, nodeID, rowGated)
    local function find()
        local button = talentFrame:GetTalentButtonByNodeID(nodeID)
        if button ~= nil and button:IsShown() and button:GetNodeInfo() ~= nil then
            return button
        end
        return nil
    end
    local button = find()
    if button == nil then
        return nil
    end
    local choice = isSelectionNode(button:GetNodeInfo())
    local vtable = nodes.proxyFoundButton({
        find = find,
        label = function(button)
            return talentLabel(button, rowGated)
        end,
        tooltip = talentTooltip,
        drag = true,
        clickLabels = { left = not choice and L["Learn"] or nil, right = L["Unlearn"] },
    })
    if choice then
        -- The left click only links; the options open on hover.
        table.remove(vtable.bindings, 1)
        vtable.controlType = graph.controlTypes.dropdown
        vtable.onActivate = function()
            local host = WowVision.graphHost
            local stack = host:focusedStack()
            if stack ~= nil then
                host:push(stack, {
                    key = "choices",
                    render = function(builder)
                        renderChoices(builder, talentFrame, nodeID)
                    end,
                })
            end
        end
    end
    local clickActions = vtable.contextActions
    vtable.contextActions = function(add)
        clickActions(function(entry)
            -- A choice node's left click does nothing unmodified.
            if not (choice and entry.click ~= nil and entry.click.emulatedKey == "LeftButton") then
                add(entry)
            end
        end)
        local current = find()
        if current == nil then
            return
        end
        local spellID = current:GetSpellID()
        if spellID ~= nil then
            add({
                label = L["Link %s in Chat"]:format(talentName(current)),
                onActivate = function()
                    WowVision.chatLinks.shiftClick({ kind = "link", text = C_Spell.GetSpellLink(spellID) })
                end,
            })
        end
        if current:CanCascadeRepurchaseRanks() then
            add({
                label = L["Buy Back"],
                onActivate = function()
                    current:CascadeRepurchaseRanks()
                end,
            })
        end
    end
    return vtable
end

-- The rows a spend gate holds back ("spend 8 more points"), keyed by the
-- gate's first talent, as the gate drawn beside that talent says.
local function gateTexts(talentFrame)
    local texts = {}
    local treeInfo = talentFrame:GetTreeInfo()
    if treeInfo == nil or treeInfo.gates == nil then
        return texts
    end
    for _, gate in ipairs(treeInfo.gates) do
        local condInfo = talentFrame:GetAndCacheCondInfo(gate.conditionID)
        if condInfo ~= nil and not condInfo.isMet and condInfo.spentAmountRequired ~= nil then
            texts[gate.topLeftNodeID] = TALENT_FRAME_GATE_TOOLTIP_FORMAT:format(condInfo.spentAmountRequired)
        end
    end
    return texts
end

local function visibleButtons(talentFrame)
    local buttons = {}
    for button in talentFrame:EnumerateAllTalentButtons() do
        local nodeInfo = button:GetNodeInfo()
        if nodeInfo ~= nil and nodeInfo.isVisible and button:IsShown() then
            tinsert(buttons, button)
        end
    end
    return buttons
end

-- Talents grouped into the rows they are drawn in, top to bottom, each left
-- to right.
local function talentRows(buttons)
    local rows = {}
    local byY = {}
    for _, button in ipairs(buttons) do
        local posY = button:GetNodeInfo().posY
        local row = byY[posY]
        if row == nil then
            row = { posY = posY, buttons = {} }
            byY[posY] = row
            tinsert(rows, row)
        end
        tinsert(row.buttons, button)
    end
    table.sort(rows, function(a, b)
        return a.posY < b.posY
    end)
    for _, row in ipairs(rows) do
        table.sort(row.buttons, function(a, b)
            return a:GetNodeInfo().posX < b:GetNodeInfo().posX
        end)
    end
    return rows
end

-- A context per row (with its gate, if any) over the row's talents, so up
-- and down move between rows and left and right along one.
local function emitRows(builder, talentFrame, buttons, gates)
    for rowIndex, row in ipairs(talentRows(buttons)) do
        local gateText = nil
        for _, button in ipairs(row.buttons) do
            gateText = gateText or gates[button:GetNodeID()]
        end
        builder:pushContext("row:" .. row.posY, nodes.joinLabel(L["Row"] .. " " .. rowIndex, gateText))
        builder:startRow()
        for _, button in ipairs(row.buttons) do
            local nodeID = button:GetNodeID()
            builder:addItem(
                ControlId.structural("talent:" .. nodeID),
                talentNode(talentFrame, nodeID, gateText ~= nil)
            )
        end
        builder:endRow()
        builder:popContext()
    end
end

-- The tree's talents under a context (Talents unless the caller names it;
-- label = false leaves it out, for a page already named so). Without groups
-- they are one stop. With groups ({ { id, label } }, in
-- reading order), each group is a stop of its own under its label, holding
-- the talents whose node belongs to it; talents of no listed group follow
-- in a stop of their own.
-- config: { key, label?, groups? }
function talentTree.renderTalents(builder, talentFrame, config)
    local key = config.key
    local buttons = visibleButtons(talentFrame)
    local gates = gateTexts(talentFrame)
    local wrapped = config.label ~= false
    if wrapped then
        builder:pushContext(key, config.label or L["Talents"])
    end
    if #buttons == 0 then
        builder:beginStop(key)
        builder:addItem(ControlId.structural(key .. ":empty"), nodes.text({ label = L["Empty"] }))
    elseif config.groups == nil then
        builder:beginStop(key)
        emitRows(builder, talentFrame, buttons, gates)
    else
        local listed = {}
        for _, group in ipairs(config.groups) do
            listed[group.id] = {}
        end
        local others = {}
        for _, button in ipairs(buttons) do
            local bucket = others
            for _, groupID in ipairs(button:GetNodeInfo().groupIDs or {}) do
                if listed[groupID] ~= nil then
                    bucket = listed[groupID]
                    break
                end
            end
            tinsert(bucket, button)
        end
        for _, group in ipairs(config.groups) do
            if #listed[group.id] > 0 then
                builder:beginStop(key .. ":" .. group.id)
                builder:pushContext("group:" .. group.id, group.label)
                emitRows(builder, talentFrame, listed[group.id], gates)
                builder:popContext()
            end
        end
        if #others > 0 then
            builder:beginStop(key .. ":others")
            emitRows(builder, talentFrame, others, gates)
        end
    end
    if wrapped then
        builder:popContext()
    end
end

-- Apply (saying when changes wait for it, or why it cannot apply them),
-- then undo (shown while changes wait), then the caller's reset control.
-- One stop; none while all three are hidden (inspecting another player).
function talentTree.renderCommitButtons(builder, talentFrame, resetNode)
    local applyButton = talentFrame.ApplyButton
    local apply = nodes.proxyButton({ target = applyButton, hover = false })
    if apply ~= nil then
        tinsert(apply.announcements, {
            text = function()
                if not applyButton:IsEnabled() then
                    return applyButton.disabledTooltip
                end
                return talentFrame:HasAnyConfigChanges() and L["Unsaved Changes"] or nil
            end,
            kind = kinds.value,
        })
    end
    local undo = nodes.proxyButton({ target = talentFrame.UndoButton, hover = false, label = L["Undo Changes"] })
    if apply == nil and undo == nil and resetNode == nil then
        return
    end
    builder:beginStop("commit")
    builder:startRow()
    builder:addItem(ControlId.forObject(applyButton), apply)
    builder:addItem(ControlId.forObject(talentFrame.UndoButton), undo)
    builder:addItem(ControlId.forObject(talentFrame.ResetButton), resetNode)
    builder:endRow()
end
