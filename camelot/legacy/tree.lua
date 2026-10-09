local module = WowVision.base.windows.legacy
local L = module.L

local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId
local kinds = graph.kinds

-- The tree page: three Legacy talent trees (professions, adventure,
-- progression) bought with Legacy points. The tree buttons pick the tree;
-- the points line reads what is left to spend; the shown tree reads its
-- name and the points spent in it; then the talent search, the talents row
-- by row as drawn (top to bottom, left to right), and the apply, undo, and
-- reset buttons. Buying is staged as on the class talent tree: nothing is
-- learned until Apply.
--
-- The talent part works on any tree built on the shared talent frame
-- (TalentFrameBaseMixin), which Forever's class talents also use.

-- ---- talents ----

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

-- The state the button's border shows: available (buyable now), locked
-- (with what it waits for), or invalid (a refund broke what depends on it).
-- Partly bought, maxed, and unaffordable read through the rank alone.
local function stateText(button)
    local states = TalentButtonUtil.BaseVisualState
    local state = button:GetVisualState()
    if state == states.Selectable then
        return L["Available"]
    elseif state == states.Gated or state == states.Locked then
        return nodes.joinLabel(L["Locked"], requirementsText(button:GetTalentFrame(), button:GetNodeID()))
    elseif state == states.RefundInvalid or state == states.DisplayError then
        return L["Invalid"]
    end
    return nil
end

local function talentLabel(button)
    return nodes.joinLabel(
        talentName(button),
        rankText(button),
        stateText(button),
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
local function talentNode(talentFrame, nodeID)
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
        label = talentLabel,
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

-- The tree's talents grouped into the rows they are drawn in, top to
-- bottom, each left to right.
local function talentRows(talentFrame)
    local rows = {}
    local byY = {}
    for button in talentFrame:EnumerateAllTalentButtons() do
        local nodeInfo = button:GetNodeInfo()
        if nodeInfo ~= nil and nodeInfo.isVisible and button:IsShown() then
            local row = byY[nodeInfo.posY]
            if row == nil then
                row = { posY = nodeInfo.posY, buttons = {} }
                byY[nodeInfo.posY] = row
                tinsert(rows, row)
            end
            tinsert(row.buttons, button)
        end
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

-- One stop: a context per row (with its gate, if any) over the row's
-- talents, so up and down move between rows and left and right along one.
function module.renderTalents(builder, talentFrame, key)
    local rows = talentRows(talentFrame)
    builder:beginStop(key)
    builder:pushContext(key, L["Talents"])
    if #rows == 0 then
        builder:addItem(ControlId.structural(key .. ":empty"), nodes.text({ label = L["Empty"] }))
    end
    local gates = gateTexts(talentFrame)
    for rowIndex, row in ipairs(rows) do
        local gateText = nil
        for _, button in ipairs(row.buttons) do
            gateText = gateText or gates[button:GetNodeID()]
        end
        builder:pushContext("row:" .. row.posY, nodes.joinLabel(L["Row"] .. " " .. rowIndex, gateText))
        builder:startRow()
        for _, button in ipairs(row.buttons) do
            local nodeID = button:GetNodeID()
            builder:addItem(ControlId.structural("talent:" .. nodeID), talentNode(talentFrame, nodeID))
        end
        builder:endRow()
        builder:popContext()
    end
    builder:popContext()
end

-- ---- the Legacy tree page ----

-- The three tree buttons: a click shows that tree. They switch what the
-- page below shows, so they read as a row, like tabs.
local function renderTreeButtons(builder, panel)
    builder:beginStop("trees")
    builder:pushContext("trees", L["Trees"])
    builder:startRow()
    for _, button in ipairs(panel.treeButtons) do
        local captured = button
        local vtable = nodes.proxyButton({
            target = captured,
            hover = false,
            label = captured.treeData.name,
        })
        if vtable ~= nil then
            tinsert(vtable.announcements, {
                text = function()
                    return captured:GetChecked() and L["selected"] or nil
                end,
                kind = kinds.selected,
            })
            builder:addItem(ControlId.structural("tree:" .. captured.treeData.treeID), vtable)
        end
    end
    builder:endRow()
    builder:popContext()
end

-- The points left to spend (the summary's own line) with the season's cap
-- (its hover tooltip), and the shown tree with the points spent in it.
local function renderPoints(builder, page)
    local summary = page.LegacyTreePointSummary
    local panel = page.LegacyTreeTraitPanel
    builder:beginStop("points")
    builder:addItem(
        ControlId.structural("available"),
        nodes.text({
            label = function()
                local currencyInfo = LegacySystem.GetCurrencyInfo()
                local cap = nil
                if currencyInfo ~= nil and currencyInfo.maxQuantity ~= nil then
                    cap = LEGACY_POINTS_SEASONAL_CAP:format(currencyInfo.maxQuantity)
                end
                return nodes.joinLabel(nodes.shownText(summary.AvailablePointsLabel), cap)
            end,
        })
    )
    builder:addItem(
        ControlId.structural("spent"),
        nodes.text({
            label = function()
                return nodes.joinLabel(
                    nodes.shownText(panel.SelectedTreeIcon.SelectedTreeLabel),
                    L["Points spent: %s"]:format(panel.SpentPointsFrame.Text:GetText() or "0")
                )
            end,
        })
    )
end

-- Apply (saying when changes wait for it), then undo (shown while changes
-- wait) or reset (refunds the whole tree, also staged until Apply).
local function renderCommitButtons(builder, panel)
    builder:beginStop("commit")
    builder:startRow()
    local apply = nodes.proxyButton({ target = panel.ApplyButton, hover = false })
    if apply ~= nil then
        tinsert(apply.announcements, {
            text = function()
                return panel:HasAnyConfigChanges() and L["Unsaved Changes"] or nil
            end,
            kind = kinds.value,
        })
    end
    builder:addItem(ControlId.forObject(panel.ApplyButton), apply)
    builder:addItem(
        ControlId.forObject(panel.UndoButton),
        nodes.proxyButton({ target = panel.UndoButton, hover = false, label = L["Undo Changes"] })
    )
    builder:addItem(
        ControlId.forObject(panel.ResetButton),
        nodes.proxyButton({ target = panel.ResetButton, hover = false, label = L["Reset Tree"] })
    )
    builder:endRow()
end

function module.renderTree(builder, page)
    local panel = page.LegacyTreeTraitPanel
    renderTreeButtons(builder, page.LegacyTreeSelectionPanel)
    renderPoints(builder, page)
    builder:beginStop("search")
    builder:addItem(ControlId.structural("search"), nodes.proxyEditBox({ editBox = panel.SearchBox, label = L["Search"] }))
    module.renderTalents(builder, panel, "talents")
    renderCommitButtons(builder, panel)
end
