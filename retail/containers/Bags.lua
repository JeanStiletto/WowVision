local module = WowVision.base.windows.containers
local L = module.L

local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId

-- Retail bags: one component covering every shown container frame, in
-- either bag mode.
--
-- COMBINED mode (ContainerFrameCombinedBags) is what a sighted player
-- sees as ONE inventory: a grid ten slots wide with no bag boundaries
-- drawn, the backpack first and the other bags following, wrapping every
-- ten. The screen mirrors that: one tab stop, rows of ten in visual order
-- (derived from the buttons' actual positions, so it always matches the
-- picture), column-preserving up and down, and no mention of which bag a
-- slot sits in, since the picture shows none. The bag slot buttons follow
-- as their own bar. Players who want bags kept apart switch the game to
-- individual mode.
--
-- INDIVIDUAL mode is one frame per bag: one tab stop per bag, the bag slot
-- button first, then the slots in order, as on classic. The game opens
-- only the bags it was asked for (the backpack key alone opens just the
-- backpack); Open All Bags, Shift plus the backpack key by default, opens
-- every bag, exactly as sighted players use it.
--
-- After the bags each frame contributes its own stops: the search box (an
-- edit box, alone in its stop), then the frame's controls -- the bag menu
-- (filters, cleanup, mode switch: a modern dropdown), the sort button,
-- money, and the extra-slots purchase button when offered.
--
-- WoW: Forever adds the keyring as a held bag (bag id Enum.BagIndex.Keyring,
-- its own frame in both modes) with KeyRingButton as its slot button.
local Bags = WowVision.components.createType("containers", { key = "RetailBags" })

local KEYRING_ID = KEYRING_CONTAINER or (Enum.BagIndex ~= nil and Enum.BagIndex.Keyring) or nil

local BAG_SLOT_BUTTONS = {
    [0] = "MainMenuBarBackpackButton",
    [1] = "CharacterBag0Slot",
    [2] = "CharacterBag1Slot",
    [3] = "CharacterBag2Slot",
    [4] = "CharacterBag3Slot",
    [5] = "CharacterReagentBag0Slot",
}

-- Every held bag, in bar order: backpack, bags, reagent bag, keyring.
local HELD_BAG_IDS = { 0, 1, 2, 3, 4, 5 }
if KEYRING_ID ~= nil then
    tinsert(HELD_BAG_IDS, KEYRING_ID)
end

local function bagSlotButton(bagID)
    if KEYRING_ID ~= nil and bagID == KEYRING_ID then
        return KeyRingButton
    end
    return _G[BAG_SLOT_BUTTONS[bagID] or ""]
end

local function shownContainerFrames()
    local frames = {}
    if ContainerFrameUtil_EnumerateContainerFrames == nil then
        return frames
    end
    for _, frame in ContainerFrameUtil_EnumerateContainerFrames() do
        if frame ~= nil and frame:IsShown() then
            tinsert(frames, frame)
        end
    end
    return frames
end

function Bags:isOpen()
    return #shownContainerFrames() > 0
end

-- The backpack of an account without an authenticator draws four extra
-- slots that cannot hold anything (the client marks them extended; the
-- Add Slots button sits on them). They are not slots, so they are not
-- read.
local function usableSlot(itemButton)
    if not itemButton:IsShown() then
        return false
    end
    return not (itemButton.IsExtended ~= nil and itemButton:IsExtended())
end

local function usableSlots(buttons)
    local list = {}
    for _, itemButton in ipairs(buttons or {}) do
        if usableSlot(itemButton) then
            tinsert(list, itemButton)
        end
    end
    return list
end

-- The frame's shown item buttons grouped by bag id, slots ascending.
local function slotsByBag(frame)
    local groups = {}
    local order = {}
    for _, itemButton in ipairs(frame.Items or {}) do
        if usableSlot(itemButton) then
            local bagID = itemButton.GetBagID ~= nil and itemButton:GetBagID() or frame:GetID()
            local list = groups[bagID]
            if list == nil then
                list = {}
                groups[bagID] = list
                tinsert(order, bagID)
            end
            tinsert(list, itemButton)
        end
    end
    table.sort(order)
    for _, list in pairs(groups) do
        table.sort(list, function(a, b)
            return a:GetID() < b:GetID()
        end)
    end
    return order, groups
end

local function bagLabel(bagID)
    local name = C_Container.GetBagName(bagID)
    if name == nil or name == "" then
        if bagID == 0 then
            return BACKPACK_TOOLTIP or L["Bags"]
        end
        if KEYRING_ID ~= nil and bagID == KEYRING_ID then
            return KEYRING or L["Keyring"]
        end
        return L["Bags"] .. " " .. bagID
    end
    return name
end

local function renderBag(builder, frame, bagID, buttons)
    local label = bagLabel(bagID)
    builder:beginStop("bag:" .. bagID)
    -- Keyed: two identical bags must not share a context identity.
    builder:pushContext("bag:" .. bagID, label)
    local slotButton = bagSlotButton(bagID)
    if slotButton ~= nil then
        builder:addItem(
            ControlId.structural("bagButton:" .. bagID),
            module.itemSlotNode(slotButton, L["Bag Slot"] .. " " .. label)
        )
    end
    module.renderSlots(builder, buttons)
    builder:popContext()
end

-- The bag slot buttons as one row under their own stop: the shown
-- buttons of the bags the filter accepts. False when none qualifies.
local function renderBagBar(builder, key, label, idPrefix, include)
    local entries = {}
    for _, bagID in ipairs(HELD_BAG_IDS) do
        local slotButton = bagSlotButton(bagID)
        if slotButton ~= nil and slotButton:IsShown() and include(bagID) then
            tinsert(entries, { bagID = bagID, button = slotButton })
        end
    end
    if #entries == 0 then
        return false
    end
    builder:beginStop(key)
    builder:pushContext(key, label)
    builder:startRow()
    for _, entry in ipairs(entries) do
        builder:addItem(
            ControlId.structural(idPrefix .. entry.bagID),
            module.itemSlotNode(entry.button, L["Bag Slot"] .. " " .. bagLabel(entry.bagID))
        )
    end
    builder:endRow()
    builder:popContext()
    return true
end

-- One grid for a combined frame: plain rows, no bag boundaries, exactly
-- as drawn (or one flat list under the list shape). Which physical bag a
-- slot belongs to is not part of the picture, so it is not spoken
-- either; individual mode is the view for that.
local function renderGrid(builder, frame, frameKey, separateBags)
    builder:beginStop(frameKey .. ":grid")
    builder:pushContext(frameKey .. ":grid", L["Bags"])
    local rows = module.renderSlots(builder, usableSlots(frame.Items))
    if rows == 0 then
        builder:addItem(ControlId.structural(frameKey .. ":empty"), nodes.text({ label = L["Empty"] }))
    end
    builder:popContext()

    -- The grid fills from the bottom-right, so a short row sits at the top
    -- pushed right. Up and down deliberately follow POSITION in the row,
    -- not the screen column: from the short row's first cell, down lands
    -- on the full row's first cell, so no column is ever skipped for a
    -- reader who starts top-left and works down.

    -- The bag slot buttons as one bar after the grid. A bag the game
    -- still shows as its own frame (the reagent bag and the keyring do,
    -- even in combined mode) keeps its slot button with that frame.
    local any = renderBagBar(builder, frameKey .. ":bagSlots", L["Bag Slots"], "bagButton:", function(bagID)
        return not separateBags[bagID]
    end)
    if not any then
        builder:beginStop(frameKey .. ":bagSlots")
        builder:pushContext(frameKey .. ":bagSlots", L["Bag Slots"])
        builder:addItem(ControlId.structural(frameKey .. ":noBagSlots"), nodes.text({ label = L["Empty"] }))
        builder:popContext()
    end
end

local function moneyText()
    local money = GetMoney()
    if money == nil or WowVision.isSecret(money) then
        return nil
    end
    return GetCoinText(money, " ")
end

local function renderFrameControls(builder, frame, frameKey)
    -- The search box is one shared edit box parented to the frame that
    -- owns it; it gets a stop of its own so tabbing in starts typing.
    local searchBox = BagItemSearchBox
    if searchBox ~= nil and searchBox:GetParent() == frame and searchBox:IsShown() then
        builder:beginStop(frameKey .. ":search")
        builder:addItem(
            ControlId.forObject(searchBox),
            nodes.proxyEditBox({ editBox = searchBox, label = L["Search"] })
        )
    end

    builder:beginStop(frameKey .. ":controls")
    builder:pushContext(frameKey .. ":controls", L["Bag Controls"])
    if frame.PortraitButton ~= nil then
        builder:addItem(
            ControlId.forObject(frame.PortraitButton),
            nodes.proxyDropdown({ target = frame.PortraitButton, label = L["Bag Menu"] })
        )
    end
    local sortButton = BagItemAutoSortButton
    if sortButton ~= nil and sortButton:GetParent() == frame then
        builder:addItem(ControlId.forObject(sortButton), nodes.proxyButton({ target = sortButton, label = L["Sort Bags"] }))
    end
    if frame.MoneyFrame ~= nil and frame.MoneyFrame:IsShown() then
        builder:addItem(
            ControlId.structural(frameKey .. ":money"),
            nodes.text({
                label = function()
                    local text = moneyText()
                    if text == nil then
                        return L["Money"]
                    end
                    return L["Money"] .. ", " .. text
                end,
            })
        )
    end
    if frame.AddSlotsButton ~= nil then
        builder:addItem(
            ControlId.forObject(frame.AddSlotsButton),
            nodes.proxyButton({ target = frame.AddSlotsButton, label = L["Add Slots"] })
        )
    end
    builder:popContext()
end

function Bags:renderGraph(builder)
    local frames = shownContainerFrames()
    -- Bags shown as their own frame alongside the combined grid.
    local separateBags = {}
    for _, frame in ipairs(frames) do
        if not (frame.IsCombinedBagContainer ~= nil and frame:IsCombinedBagContainer()) then
            separateBags[frame:GetID()] = true
        end
    end
    for _, frame in ipairs(frames) do
        local frameKey = "frame:" .. (frame:GetName() or tostring(frame:GetID()))
        if frame.IsCombinedBagContainer ~= nil and frame:IsCombinedBagContainer() then
            renderGrid(builder, frame, frameKey, separateBags)
        else
            local order, groups = slotsByBag(frame)
            for _, bagID in ipairs(order) do
                renderBag(builder, frame, bagID, groups[bagID])
            end
        end
        renderFrameControls(builder, frame, frameKey)
    end
end
