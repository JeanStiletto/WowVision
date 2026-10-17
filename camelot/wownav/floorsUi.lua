-- The floor choice for a WowNav route: opens only when floors are stacked at the start or at the target and nothing
-- tells which one is meant (no height from the game, no route state, no height of the target). One button per
-- floor, lowest first; Enter picks it and the route request goes on with that floor's height.

local module = WowVision.base.navigation.wownav
local L = module.L

local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId

local WINDOW = "wownavFloors"

local function floorLabel(floor, count)
    local text = string.format(L["Floor %d of %d"], floor.index, count)
    if floor.index == 1 then
        text = text .. ", " .. L["lowest"]
    elseif floor.index == count then
        text = text .. ", " .. L["highest"]
    end
    return text
end

local function render(builder, screen)
    local choice = module:floorChoice()
    builder:beginStop("floors")
    local title = choice ~= nil and choice.kind == "start" and L["Choose your floor"] or L["Choose the target's floor"]
    builder:pushContext("floors", title)
    if choice == nil then
        builder:addItem(ControlId.structural("empty"), nodes.text({ label = L["Empty"] }))
    else
        local count = #choice.floors
        for _, floor in ipairs(choice.floors) do
            local captured = floor
            builder:addItem(ControlId.structural("floor:" .. floor.index), nodes.button({
                label = floorLabel(floor, count),
                onActivate = function()
                    module:chooseFloor(captured)
                end,
            }))
        end
    end
    builder:popContext()
end

module:registerWindow({
    type = "ManualWindow",
    name = WINDOW,
    graphScreen = { render = render, captureClose = true },
})
