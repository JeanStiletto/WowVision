local module = WowVision.base.windows:createModule("mail")
local L = module.L
module:setLabel(L["Mail"])

local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId
local kinds = graph.kinds

-- The mailbox: tabs, the inbox page, the open letter, and the send tab.
-- Classic clients re-register the window (they poll MailFrame instead of the
-- interaction event). Inbox labels read live; the per-tick rebuild picks up
-- MAIL_INBOX_UPDATE arrivals without event plumbing.

function module.editBoxNode(editBox, label)
    return nodes.proxyEditBox({ editBox = editBox, label = label })
end

function module.checkButtonNode(button, label)
    return nodes.proxyCheckButton({ target = button, label = label })
end

function module.moneyText(frame)
    local money = frame ~= nil and (frame.staticMoney or frame.money) or nil
    if money == nil then
        return nil
    end
    return C_CurrencyInfo.GetCoinText(money)
end

local function getInboxItemLabel(item)
    local elementName = item:GetName()
    local sender = _G[elementName .. "Sender"]:GetText() or ""
    local subject = _G[elementName .. "Subject"]:GetText() or ""
    return L["From"] .. ": " .. sender .. ", " .. L["Subject"] .. ": " .. subject
end

local function renderTabs(builder)
    builder:beginStop("tabs")
    builder:pushContext("tabs", L["Tabs"])
    builder:startRow()
    for i = 1, 2 do
        local tab = _G["MailFrameTab" .. i]
        local tabIndex = i
        if tab ~= nil and tab:IsShown() then
            local vtable = nodes.proxyButton({ target = tab })
            tinsert(vtable.announcements, {
                text = function()
                    if MailFrame.selectedTab == tabIndex then
                        return L["selected"]
                    end
                    return nil
                end,
                kind = kinds.selected,
            })
            builder:addItem(ControlId.forObject(tab), vtable)
        end
    end
    builder:endRow()
    builder:popContext()
end

local function renderInbox(builder)
    if OpenAllMail ~= nil and OpenAllMail:IsShown() then
        builder:beginStop("openAll")
        builder:addItem(ControlId.forObject(OpenAllMail), nodes.proxyButton({ target = OpenAllMail }))
    end

    builder:beginStop("inboxItems")
    builder:pushContext("inbox", L["Inbox"])
    local emitted = 0
    for i = 1, INBOXITEMS_TO_DISPLAY do
        local item = _G["MailItem" .. i]
        if item ~= nil and item.Button:IsShown() then
            local captured = item
            builder:addItem(
                ControlId.forObject(item.Button),
                nodes.proxyButton({
                    target = item.Button,
                    label = function()
                        return getInboxItemLabel(captured)
                    end,
                })
            )
            emitted = emitted + 1
        end
    end
    if emitted == 0 then
        builder:addItem(ControlId.structural("inboxEmpty"), nodes.text({ label = L["Empty"] }))
    end
    builder:popContext()

    if InboxPrevPageButton ~= nil and InboxPrevPageButton:IsShown() then
        builder:beginStop("prevPage")
        builder:addItem(
            ControlId.forObject(InboxPrevPageButton),
            nodes.proxyButton({ target = InboxPrevPageButton, label = L["Previous Page"] })
        )
    end
    if InboxNextPageButton ~= nil and InboxNextPageButton:IsShown() then
        builder:beginStop("nextPage")
        builder:addItem(
            ControlId.forObject(InboxNextPageButton),
            nodes.proxyButton({ target = InboxNextPageButton, label = L["Next Page"] })
        )
    end
end

local function invoiceText(builder, id, label)
    builder:addItem(id, nodes.text({ label = label }))
end

local function renderOpenMail(builder)
    builder:beginStop("letter")
    builder:pushContext("letter", L["Mail"])

    invoiceText(builder, ControlId.structural("sender"), function()
        return OpenMailSender.Name:GetText()
    end)
    invoiceText(builder, ControlId.structural("subject"), function()
        return L["Subject"] .. ": " .. (OpenMailSubject:GetText() or "")
    end)
    if OpenMailBodyText ~= nil and OpenMailBodyText:IsShown() then
        invoiceText(builder, ControlId.structural("body"), function()
            return GetInboxText(InboxFrame.openMailID)
        end)
    end

    if OpenMailInvoiceFrame ~= nil and OpenMailInvoiceFrame:IsShown() then
        invoiceText(builder, ControlId.structural("invoiceItem"), function()
            return OpenMailInvoiceItemLabel:GetText()
        end)
        invoiceText(builder, ControlId.structural("invoiceBuyer"), function()
            return (OpenMailInvoicePurchaser:GetText() or "")
                .. " "
                .. (OpenMailInvoiceBuyMode:GetText() or "")
        end)
        invoiceText(builder, ControlId.structural("invoiceSale"), function()
            return (OpenMailInvoiceSalePrice:GetText() or "") .. " " .. (module.moneyText(OpenMailSalePriceMoneyFrame) or "")
        end)
        invoiceText(builder, ControlId.structural("invoiceDeposit"), function()
            return (OpenMailInvoiceDeposit:GetText() or "") .. " " .. (module.moneyText(OpenMailDepositMoneyFrame) or "")
        end)
        invoiceText(builder, ControlId.structural("invoiceCut"), function()
            return (OpenMailInvoiceHouseCut:GetText() or "") .. " " .. (module.moneyText(OpenMailHouseCutMoneyFrame) or "")
        end)
        invoiceText(builder, ControlId.structural("invoiceTotal"), function()
            return (OpenMailInvoiceAmountReceived:GetText() or "")
                .. " "
                .. (module.moneyText(OpenMailTransactionAmountMoneyFrame) or "")
        end)
    end

    for i, button in ipairs(OpenMailFrame.activeAttachmentButtons or {}) do
        local captured = button
        local label
        if captured == OpenMailLetterButton then
            label = L["Letter"]
        elseif captured == OpenMailMoneyButton then
            label = function()
                if OpenMailFrame.money ~= nil and OpenMailFrame.money > 0 then
                    return C_CurrencyInfo.GetCoinText(OpenMailFrame.money)
                end
                return L["Empty"]
            end
        else
            -- Data-first: the buttons are plain ItemButtonTemplates whose
            -- Count fontstring is a global, not a keyed child, so read the
            -- attachment straight from the inbox API by slot id.
            label = function()
                local name, _, _, count, quality = GetInboxItem(InboxFrame.openMailID, captured:GetID())
                if name == nil then
                    return L["Empty"]
                end
                local label = WowVision.items.formatName(name, quality)
                if count ~= nil and count > 1 then
                    return label .. " x " .. count
                end
                return label
            end
        end
        builder:addItem(ControlId.forObject(captured), nodes.proxyButton({ target = captured, label = label }))
    end
    builder:popContext()

    for _, button in ipairs({
        OpenMailReplyButton,
        OpenMailDeleteButton,
        OpenMailCloseButton,
        OpenMailReportSpamButton,
    }) do
        if button ~= nil and button:IsShown() then
            builder:beginStop()
            builder:addItem(ControlId.forObject(button), nodes.proxyButton({ target = button }))
        end
    end
end

-- The letter body: Classic clients (TBC, Mists) wrap it in MailEditBox, a
-- ScrollingEditBox frame; mainline clients (Forever, Retail) have a plain
-- SendMailBodyEditBox.
local function getBodyEditBox()
    if MailEditBox ~= nil then
        if MailEditBox.GetEditBox then
            return MailEditBox:GetEditBox()
        end
        return MailEditBox
    end
    return SendMailBodyEditBox
end

-- Route Tab presses on a Blizzard EditBox to the graph host instead of
-- cycling through Blizzard's built-in EditBox tab chain.
local function routeTabToWV(editBox)
    if not editBox or not editBox.SetScript then
        return
    end
    editBox:SetScript("OnTabPressed", function()
        editBox:ClearFocus()
        if IsShiftKeyDown() then
            WowVision.graphHost:onKey("previous")
        else
            WowVision.graphHost:onKey("next")
        end
    end)
end

local mailEditBoxesGuarded = false
local function guardMailEditBoxes()
    if not mailEditBoxesGuarded then
        mailEditBoxesGuarded = true
        -- Disable autoFocus and route Tab to WV on all mail EditBoxes
        local editBoxes = {
            SendMailMoneyGold,
            SendMailMoneySilver,
            SendMailMoneyCopper,
            SendMailNameEditBox,
            SendMailSubjectEditBox,
            getBodyEditBox(),
        }
        for _, editBox in ipairs(editBoxes) do
            if editBox then
                editBox:SetAutoFocus(false)
                routeTabToWV(editBox)
            end
        end
        -- Break Blizzard's Lua-level focus chain links on the money frame
        SendMailMoney.previousFocus = nil
        SendMailMoney.nextFocus = nil
        -- Unregister the ScrollingEditBox wrapper's OnTabPressed callback.
        -- MailEditBox is a ScrollingEditBoxTemplate (Frame, not EditBox).
        -- Blizzard registers: MailEditBox:RegisterCallback("OnTabPressed", SendMailEditBox_OnTabPressed, MailEditBox)
        -- This fires EditBox_HandleTabbing(self, SEND_MAIL_TAB_LIST) INDEPENDENTLY of the
        -- inner EditBox's OnTabPressed (which WV overrides via routeTabToWV).  Both fire on
        -- every Tab press, causing Blizzard's tab list to simultaneously set focus on
        -- Gold (forward) or Subject (backward) while WV navigates elsewhere.
        if MailEditBox ~= nil and MailEditBox.UnregisterCallback then
            MailEditBox:UnregisterCallback("OnTabPressed", MailEditBox)
        end
        -- Remove body/money entries from the tab list as a safety net.
        -- WV overrides OnTabPressed on all mail EditBoxes, so this list should
        -- never be consulted, but nil the dangerous entries just in case.
        SEND_MAIL_TAB_LIST[3] = nil -- the body box
        SEND_MAIL_TAB_LIST[4] = nil -- SendMailMoneyGold
        SEND_MAIL_TAB_LIST[5] = nil -- SendMailMoneyCopper
    end
end

local sendFrameHooked = false
local function hookSendFrame()
    if sendFrameHooked or SendMailFrame == nil then
        return
    end
    sendFrameHooked = true
    SendMailFrame:HookScript("OnShow", function()
        guardMailEditBoxes()
        -- Runs every show: Blizzard's OnShow calls SetFocus(), steal it back
        SendMailNameEditBox:ClearFocus()
    end)
end
hookSendFrame()

local function getAttachmentLabel(i)
    local itemName, _, _, stackCount, quality = GetSendMailItem(i)
    if itemName then
        local label = WowVision.items.formatName(itemName, quality)
        if stackCount and stackCount > 1 then
            label = label .. " x " .. stackCount
        end
        return label
    end
    return nil
end

local function getFirstEmptySlot()
    for i = 1, ATTACHMENTS_MAX_SEND do
        if not HasSendMailItem(i) then
            local slot = SendMailFrame.SendMailAttachments[i]
            -- Slot may not exist yet if Blizzard creates them lazily
            if slot then
                return slot
            end
        end
    end
    return nil
end

local function attachmentNode(slot, label)
    local vtable = nodes.proxyButton({ target = slot, label = label })
    if vtable == nil then
        return nil
    end
    tinsert(vtable.bindings, {
        binding = "drag",
        type = "Function",
        func = function()
            local script = slot:GetScript("OnDragStart")
            if script ~= nil then
                script(slot)
            end
        end,
    })
    return vtable
end

-- The send tab. Same frame names on Classic and mainline clients except the
-- body box (getBodyEditBox).
function module.renderSend(builder, screen)
    -- Fallback in case the mail frame was created after this file loaded.
    hookSendFrame()
    guardMailEditBoxes()
    builder:beginStop("sendTo")
    builder:addItem(ControlId.structural("sendTo"), module.editBoxNode(SendMailNameEditBox, L["Send To"]))
    builder:beginStop("subject")
    builder:addItem(ControlId.structural("subject"), module.editBoxNode(SendMailSubjectEditBox, L["Subject"]))
    local bodyFrame = getBodyEditBox()
    if bodyFrame then
        builder:beginStop("body")
        builder:addItem(ControlId.structural("body"), module.editBoxNode(bodyFrame, L["Body"]))
    end

    builder:beginStop("attachments")
    builder:pushContext("attachments", L["Attachments"])
    local emitted = 0
    for i = 1, ATTACHMENTS_MAX_SEND do
        if HasSendMailItem(i) then
            local slot = SendMailFrame.SendMailAttachments[i]
            if slot then
                local index = i
                builder:addItem(
                    ControlId.structural("attachment:" .. i),
                    attachmentNode(slot, function()
                        return getAttachmentLabel(index) or ""
                    end)
                )
                emitted = emitted + 1
            end
        end
    end
    local emptySlot = getFirstEmptySlot()
    if emptySlot then
        builder:addItem(ControlId.structural("drop"), attachmentNode(emptySlot, L["Drop Item"]))
        emitted = emitted + 1
    end
    if emitted == 0 then
        builder:addItem(ControlId.structural("attachmentsEmpty"), nodes.text({ label = L["Empty"] }))
    end
    builder:popContext()

    -- Send Money and COD are a RADIO pair: clicking one unchecks the other,
    -- and clicking the already-selected one is a no-op. COD is disabled
    -- until an item is attached; it stays visible with its state spoken.
    builder:beginStop("sendMoney")
    builder:addItem(
        ControlId.forObject(SendMailSendMoneyButton),
        module.checkButtonNode(SendMailSendMoneyButton, L["Send Money"])
    )
    builder:beginStop("cod")
    -- The proxy factories announce disabled state themselves.
    builder:addItem(ControlId.forObject(SendMailCODButton), module.checkButtonNode(SendMailCODButton, L["COD"]))

    -- Each coin box is its own stop: tabbing into a box starts typing, and
    -- Tab out goes to the NEXT STOP, so boxes sharing a stop would be
    -- unreachable. The section label follows the mode: Amount to Send or
    -- COD Amount.
    builder:pushContext(
        "money",
        SendMailMoneyText ~= nil and SendMailMoneyText:GetText() or L["Money"]
    )
    builder:beginStop("gold")
    builder:addItem(ControlId.structural("gold"), module.editBoxNode(SendMailMoneyGold, L["Gold"]))
    builder:beginStop("silver")
    builder:addItem(ControlId.structural("silver"), module.editBoxNode(SendMailMoneySilver, L["Silver"]))
    builder:beginStop("copper")
    builder:addItem(ControlId.structural("copper"), module.editBoxNode(SendMailMoneyCopper, L["Copper"]))
    builder:popContext()

    builder:beginStop("postage")
    builder:addItem(
        ControlId.structural("postage"),
        nodes.text({
            label = function()
                return L["Postage"] .. " " .. (module.moneyText(SendMailCostMoneyFrame) or "")
            end,
        })
    )

    builder:beginStop("send")
    builder:addItem(ControlId.forObject(SendMailMailButton), nodes.proxyButton({ target = SendMailMailButton }))
    builder:beginStop("cancel")
    builder:addItem(ControlId.forObject(SendMailCancelButton), nodes.proxyButton({ target = SendMailCancelButton }))
end

function module.renderMail(builder, screen)
    if MailFrame == nil or not MailFrame:IsShown() then
        return
    end
    builder:pushContext("mail", L["Mail"])

    renderTabs(builder)

    if InboxFrame ~= nil and InboxFrame:IsShown() then
        renderInbox(builder)
        if OpenMailFrame ~= nil and OpenMailFrame:IsShown() then
            renderOpenMail(builder)
        end
    end

    if SendMailFrame ~= nil and SendMailFrame:IsShown() then
        module.renderSend(builder, screen)
    end

    builder:popContext()
end

module:registerWindow({
    type = "PlayerInteractionWindow",
    name = "mail",
    conflictingAddons = { "Sku" },
    interactionType = Enum.PlayerInteractionType.MailInfo,
    graphScreen = { render = module.renderMail },
})
