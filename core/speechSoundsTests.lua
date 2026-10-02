local testRunner = WowVision.testing.testRunner
local sounds = WowVision.speechSounds

-- A game-side store standing in for C_TTSSettings: records every write.
local function gameStore()
    local store = { values = {}, writes = 0 }
    local function set(option, enabled)
        store.values[option] = enabled
        store.writes = store.writes + 1
    end
    return store, set
end

-- A settings facade standing in for module:hasSettings(): keeps the
-- declared fields and gives each a valueChange event.
local function settingsFacade()
    local facade = { fields = {} }
    function facade:add(def)
        local field = { def = def, events = { valueChange = WowVision.Event:new("valueChange") } }
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
    ["a fresh character gets the line-break sound off and the activity sound on"] = function(t)
        local store, set = gameStore()
        sounds.apply({}, set)
        t:assertEqual(store.values.PlaySoundSeparatingChatLineBreaks, false)
        t:assertEqual(store.values.PlayActivitySoundWhenNotFocused, true)
        t:assertEqual(store.writes, 2)
    end,

    ["stored values win over the defaults, a stored false included"] = function(t)
        local store, set = gameStore()
        sounds.apply({ chatLineSound = true, unfocusedActivitySound = false }, set)
        t:assertEqual(store.values.PlaySoundSeparatingChatLineBreaks, true)
        t:assertEqual(store.values.PlayActivitySoundWhenNotFocused, false)
    end,

    ["both settings are declared as Bool settings with their defaults"] = function(t)
        local facade = settingsFacade()
        local store, set = gameStore()
        sounds.addSettings(facade, untranslated(), set)
        local line = facade.fields.chatLineSound
        local activity = facade.fields.unfocusedActivitySound
        t:assertNotNil(line)
        t:assertNotNil(activity)
        t:assertEqual(line.def.type, "Bool")
        t:assertEqual(line.def.default, false)
        t:assertEqual(line.def.label, "Sound Between Chat Lines")
        t:assertEqual(activity.def.type, "Bool")
        t:assertEqual(activity.def.default, true)
        t:assertEqual(store.writes, 0, "declaring does not write to the game")
    end,

    ["toggling a setting writes it into the game at once"] = function(t)
        local facade = settingsFacade()
        local store, set = gameStore()
        sounds.addSettings(facade, untranslated(), set)
        facade.fields.chatLineSound.events.valueChange:emit({}, "chatLineSound", true)
        t:assertEqual(store.values.PlaySoundSeparatingChatLineBreaks, true)
        facade.fields.unfocusedActivitySound.events.valueChange:emit({}, "unfocusedActivitySound", false)
        t:assertEqual(store.values.PlayActivitySoundWhenNotFocused, false)
        t:assertEqual(store.writes, 2)
    end,

    ["the game setter is a no-op without the game API"] = function(t)
        t:assertNil(C_TTSSettings)
        t:assertFalse(sounds.gameSetter("PlaySoundSeparatingChatLineBreaks", false))
    end,
})
