-- LOCAL: /wv selftest -- checks the dungeon error fixes without a dungeon.
-- 1. Which LibRangeCheck copy runs: ours is 99; a lower number means another
--    addon's copy won and the secret GUID patch is not active.
-- 2. One deliberate error in a module update, next frame: the menus must
--    still update in that same frame, and the error must show in /wv errors.
local module = WowVision.base:createModule("selfTest")
module:setLabel("Self test")
module.hiddenFromMenu = true

local armed = false
local thrownAt = nil
local hooked = false

local function say(text)
    print("WowVision self test: " .. text)
end

function module:onEnable()
    self:hasUpdate(function()
        if not armed then
            return
        end
        armed = false
        thrownAt = GetTime()
        error("WowVision self test: deliberate update error (expected)")
    end)
end

local function hookMenus()
    if hooked then
        return
    end
    hooked = true
    local host = WowVision.UIHost
    local original = host.update
    host.update = function(...)
        original(...)
        if thrownAt == nil then
            return
        end
        local same = GetTime() == thrownAt
        thrownAt = nil
        if same then
            say("pass, the menus updated in the same frame as the error. /wv errors should list the deliberate error.")
        else
            say("fail, the menus only updated in a later frame.")
        end
    end
end

module:registerCommand({
    name = "selftest",
    scope = "WowVision",
    description = "Self test of the dungeon error fixes (range library, update errors)",
    func = function()
        local _, minor = LibStub("LibRangeCheck-3.0")
        if minor == 99 then
            say("range library version 99, ours.")
        else
            say("range library version " .. tostring(minor) .. ", another addon's copy, not ours.")
        end
        if InCombatLockdown() then
            say("update test skipped, leave combat first.")
            return
        end
        hookMenus()
        armed = true
        -- No answer within a second: the frame never reached the menus.
        C_Timer.After(1, function()
            if armed or thrownAt ~= nil then
                armed = false
                thrownAt = nil
                say("fail, no answer from the menus.")
            end
        end)
    end,
})
