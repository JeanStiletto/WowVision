local testRunner = WowVision.testing.testRunner
local stall = WowVision.speechStall

-- A speech queue like tbc/ and retail/speech.lua, on a clock the test turns.
local function queue()
    local q = { module = { queue = {}, speaking = false, current = nil }, clock = 0, spoken = {} }
    local module = q.module
    local function poll()
        if module.speaking then
            return
        end
        local item = table.remove(module.queue, 1)
        if item == nil then
            return
        end
        module.speaking = true
        module.current = item
        q.guard:sent(item)
        q.spoken[#q.spoken + 1] = item.text
    end
    q.guard = stall.new(module, poll, function()
        return q.clock
    end)
    function q.say(text, tag)
        table.insert(module.queue, { text = text, tag = tag })
        poll()
    end
    function q.finish(id)
        if q.guard:ended(id) then
            module.speaking = false
            module.current = nil
            poll()
        end
    end
    return q
end

local function withDump(body)
    return function(t)
        local saved = WowVisionDump
        WowVisionDump = {}
        local ok, err = pcall(body, t)
        WowVisionDump = saved
        if not ok then
            error(err, 0)
        end
    end
end

testRunner:addSuite("Speech stall", {
    ["a stop frees the queue: the next line is spoken without a finished event"] = function(t)
        local q = queue()
        q.say("Road")
        q.guard:started(1)
        q.say("Bridge")
        q.guard:stopped()
        t:assertEqual(q.spoken[2], "Bridge")
        t:assertEqual(q.module.current.text, "Bridge")
    end,

    ["the late end of a stopped line does not end the next one"] = function(t)
        local q = queue()
        q.say("Road")
        q.guard:started(1)
        q.guard:stopped()
        q.say("Bridge")
        q.say("Gate")
        q.finish(1)
        t:assertEqual(q.module.current.text, "Bridge")
        q.guard:started(2)
        q.finish(2)
        t:assertEqual(q.module.current.text, "Gate")
    end,

    ["another line's end does not end ours while ours plays"] = function(t)
        local q = queue()
        q.say("Road")
        q.say("Bridge")
        q.guard:started(7)
        q.finish(9)
        t:assertEqual(q.module.current.text, "Road")
        q.finish(7)
        t:assertEqual(q.module.current.text, "Bridge")
    end,

    ["a line that never starts frees the queue and is written down"] = withDump(function(t)
        local q = queue()
        q.say("Road", { kind = "place" })
        q.say("Bridge")
        q.clock = stall.NOT_STARTED - 1
        t:assertEqual(q.guard:check(), nil)
        q.clock = stall.NOT_STARTED + 1
        t:assertEqual(q.guard:check(), "never started")
        t:assertEqual(q.module.current.text, "Bridge")
        local entry = WowVisionDump.speechStalls[1]
        t:assertEqual(entry.reason, "never started")
        t:assertEqual(entry.kind, "place")
        t:assertEqual(entry.waiting, 1)
    end),

    ["a long line that plays is left alone until the longest wait"] = withDump(function(t)
        local q = queue()
        q.say("Road")
        q.guard:started(1)
        q.clock = stall.LONGEST - 1
        t:assertEqual(q.guard:check(), nil)
        q.clock = stall.LONGEST + 1
        t:assertEqual(q.guard:check(), "never ended")
        t:assertEqual(q.module.speaking, false)
    end),

    ["someone else's line that never ends frees the queue after the longest wait"] = withDump(function(t)
        local q = queue()
        q.guard:started(5)
        q.say("Road")
        t:assertEqual(#q.spoken, 0)
        q.clock = stall.LONGEST + 1
        t:assertEqual(q.guard:check(), "other speech never ended")
        t:assertEqual(q.spoken[1], "Road")
    end),

    ["an idle queue is never stuck"] = withDump(function(t)
        local q = queue()
        q.clock = 1000
        t:assertEqual(q.guard:check(), nil)
        t:assertEqual(WowVisionDump.speechStalls, nil)
    end),
})
