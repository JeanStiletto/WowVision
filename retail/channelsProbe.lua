-- Developer tool (local only): why the chat channels window screen does not
-- take over when ChannelFrame opens. /wv chanprobe prints the window's state
-- to chat and keeps it in WowVisionDump.channelsProbe (/reload writes it).

local function describe()
    local lines = {}
    local function add(text)
        tinsert(lines, text)
    end

    local frame = rawget(_G, "ChannelFrame")
    add("ChannelFrame: " .. tostring(frame ~= nil))
    if frame ~= nil then
        add("shown " .. tostring(frame:IsShown()) .. ", visible " .. tostring(frame:IsVisible()))
        local list = frame.ChannelList
        add("list buttons: " .. tostring(list ~= nil and list.buttons ~= nil and #list.buttons or "none"))
    end

    local manager = WowVision.UIHost ~= nil and WowVision.UIHost.windowManager or nil
    local window = manager ~= nil and manager.windows["ChannelFrame"] or nil
    add("window registered: " .. tostring(window ~= nil))
    if window ~= nil then
        local polled = false
        for _, auto in ipairs(manager.autoWindows) do
            if auto == window then
                polled = true
            end
        end
        add("polled " .. tostring(polled) .. ", open state " .. tostring(window._isCurrentlyOpen))
        add("open instance " .. tostring(window._openInstance ~= nil) .. ", can open " .. tostring(window:canOpen()))
    end
    local channelsModule = WowVision.base.windows.channels
    if channelsModule ~= nil then
        add("module enabled: " .. tostring(channelsModule:getEnabled()))
    else
        add("module: missing")
    end

    local host = WowVision.graphHost
    add("stacks: " .. tostring(#host.stacks) .. ", focused " .. tostring(host.focusedIndex))
    for index, stack in ipairs(host.stacks) do
        add("stack " .. index .. ": " .. tostring(stack.config ~= nil and stack.config.key or "?"))
    end

    if window ~= nil and window.graphScreen ~= nil then
        local builder = WowVision.graph.Builder:new({})
        local ok, err = xpcall(window.graphScreen.render, function(message)
            return tostring(message) .. "\n" .. debugstack(2)
        end, builder, { state = { expanded = {} } })
        if not ok then
            add("render error: " .. tostring(err))
        else
            local buildOk, render = pcall(builder.build, builder)
            if not buildOk then
                add("build error: " .. tostring(render))
            else
                add("rendered nodes: " .. tostring(render ~= nil and #render.order or 0))
            end
        end
    end
    return lines
end

WowVision.base:registerCommand({
    name = "chanprobe",
    description = "Chat channels window probe: prints why its screen does or does not open",
    func = function()
        local ok, lines = pcall(describe)
        if not ok then
            lines = { "probe error: " .. tostring(lines) }
        end
        WowVisionDump = WowVisionDump or {}
        WowVisionDump.channelsProbe = lines
        for _, line in ipairs(lines) do
            print("chanprobe: " .. line)
        end
    end,
})
