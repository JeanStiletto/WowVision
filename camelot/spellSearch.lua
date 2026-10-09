local spellSearch = {}
WowVision.spellSearch = spellSearch

local L = WowVision:getLocale()
local nodes = WowVision.graph.nodes

-- The modern spell search box (the spellbook, the class talents, the Legacy
-- trees). Typing fills a suggestion list under the box; while the box has
-- the keyboard, Up and Down move the list's highlight and Enter picks the
-- highlighted suggestion (else it searches the typed text). Those are the
-- game's own keys, but the highlight is only drawn, so a hook after the
-- list's highlight call speaks it: the suggestion, its position, and on the
-- last one the game's line for the matches that did not fit.

-- Containers already hooked; hooksecurefunc stacks, so each gets one.
local hooked = setmetatable({}, { __mode = "k" })

local function highlightedText(container)
    local index = container.highlightedIndex
    if index == nil or index <= 0 then
        return nil
    end
    local scrollBox = container.ScrollBox
    if scrollBox:HasDataProvider() then
        local count = scrollBox:GetDataProviderSize()
        local data = scrollBox:GetDataProvider():Find(index)
        local name = data ~= nil and data.resultInfo ~= nil and data.resultInfo.name or nil
        local overflow = nil
        if index == count and container.OverflowCount:IsShown() then
            overflow = container.OverflowCount.Text:GetText()
        end
        return nodes.joinLabel(name, index .. " " .. L["of"] .. " " .. count, overflow)
    end
    -- No matches: the list offers the frame's suggested searches instead.
    for button in container.suggestedResultButtonsPool:EnumerateActive() do
        if button.displayIndex == index then
            return button.Text:GetText()
        end
    end
    return nil
end

local function watch(container)
    if container == nil or hooked[container] then
        return
    end
    hooked[container] = true
    hooksecurefunc(container, "HighlightPreviewResult", function(self)
        local text = highlightedText(self)
        if text ~= nil then
            WowVision:speak(text)
        end
    end)
end

-- The search box as an edit box node, its suggestions spoken.
function spellSearch.node(editBox)
    if editBox.GetSearchPreviewContainer ~= nil then
        watch(editBox:GetSearchPreviewContainer())
    end
    return nodes.proxyEditBox({ editBox = editBox, label = L["Search"] })
end
