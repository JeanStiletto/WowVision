local testRunner = WowVision.testing.testRunner
local sounds = WowVision.speechSounds

local LINE = "PlaySoundSeparatingChatLineBreaks"
local ACTIVITY = "PlayActivitySoundWhenNotFocused"

-- A game standing in for C_TTSSettings: both sounds on, like a fresh
-- client, every write counted; refuse makes writes fail.
local function fakeGame(refuse)
    local store = { values = { [LINE] = true, [ACTIVITY] = true }, writes = 0 }
    local game = {
        get = function(option)
            return store.values[option]
        end,
        set = function(option, enabled)
            if refuse then
                return false
            end
            store.values[option] = enabled
            store.writes = store.writes + 1
            return true
        end,
    }
    return store, game
end

-- A settings facade standing in for module:hasSettings(): keeps the
-- declared fields and reads or writes each through its accessors.
local function settingsFacade()
    local facade = { fields = {} }
    function facade:add(def)
        local field = { def = def, persist = true }
        function field:read()
            return self.def.get(nil, self.def.key)
        end
        function field:write(value)
            self.def.set(nil, self.def.key, value)
        end
        self.fields[def.key] = field
        return field
    end
    return facade
end

local function untranslated()
    return setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    })
end

testRunner:addSuite("Speech sounds", {
    ["a fresh character gets the line-break sound turned off once"] = function(t)
        local state = { chatLineSoundOff = false }
        local store, game = fakeGame()
        t:assertTrue(sounds.silenceOnce(state, game))
        t:assertEqual(store.values[LINE], false)
        t:assertEqual(store.values[ACTIVITY], true, "the activity sound is left alone")
        t:assertEqual(store.writes, 1)
        t:assertTrue(state.chatLineSoundOff)
    end,

    ["a sound that is already off is not written and still counts as handled"] = function(t)
        local state = { chatLineSoundOff = false }
        local store, game = fakeGame()
        store.values[LINE] = false
        t:assertFalse(sounds.silenceOnce(state, game))
        t:assertEqual(store.writes, 0)
        t:assertTrue(state.chatLineSoundOff)
    end,

    ["a character that was handled keeps the sound the player chose"] = function(t)
        local state = { chatLineSoundOff = true }
        local store, game = fakeGame()
        t:assertFalse(sounds.silenceOnce(state, game))
        t:assertEqual(store.values[LINE], true)
        t:assertEqual(store.writes, 0)
    end,

    ["a refused write is tried again next login"] = function(t)
        local state = { chatLineSoundOff = false }
        local store, game = fakeGame(true)
        t:assertFalse(sounds.silenceOnce(state, game))
        t:assertEqual(store.values[LINE], true)
        t:assertFalse(state.chatLineSoundOff)
    end,

    ["the toggles read and write the game setting and store nothing"] = function(t)
        local facade = settingsFacade()
        local store, game = fakeGame()
        sounds.addSettings(facade, untranslated(), game)
        local line = facade.fields.chatLineSound
        local activity = facade.fields.unfocusedActivitySound
        t:assertEqual(line.def.type, "Bool")
        t:assertEqual(line.def.label, "Sound Between Chat Lines")
        t:assertFalse(line.persist, "the game keeps the value")
        t:assertFalse(activity.persist)
        t:assertEqual(line:read(), true)
        store.values[LINE] = false
        t:assertEqual(line:read(), false, "reads are live")
        activity:write(false)
        t:assertEqual(store.values[ACTIVITY], false)
        t:assertEqual(store.writes, 1)
    end,

    ["the silenced flag is a hidden per-character setting"] = function(t)
        local facade = settingsFacade()
        local _, game = fakeGame()
        sounds.addSettings(facade, untranslated(), game)
        local flag = facade.fields.chatLineSoundOff
        t:assertNotNil(flag)
        t:assertEqual(flag.def.default, false)
        t:assertEqual(flag.def.global, false)
        t:assertEqual(flag.def.showInUI, false)
        t:assertTrue(flag.persist)
    end,

    ["the game accessors are harmless without the game API"] = function(t)
        t:assertNil(C_TTSSettings)
        t:assertNil(sounds.game.get(LINE))
        t:assertFalse(sounds.game.set(LINE, false))
    end,
})
