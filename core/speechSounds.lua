-- The game's own sounds around text-to-speech, owned by the speech module.
--
-- The client plays two sounds around the text it speaks: one separating
-- chat line breaks (between two messages) and an activity sound when a
-- message is spoken while the chat window is hidden. Both are game settings
-- (C_TTSSettings; the /tts playline and /tts playactivity commands toggle
-- them) that default to on, so every fresh character hears the line-break
-- sound between WowVision's announcements. The speech module declares a
-- setting for each and writes them into the game on every login and on
-- every change, so the WowVision value is the one that counts: a /tts
-- toggle lasts until the next login. The line-break sound is off by
-- default; the activity sound keeps the game's default.
--
-- Kept free of frames and game globals so it runs in the headless tests;
-- the game is reached only through the setter passed in.
local sounds = {}

-- One entry per game setting: the WowVision setting key and label, the
-- default WowVision applies, and the Enum.TtsBoolSetting name.
sounds.defs = {
    {
        key = "chatLineSound",
        label = "Sound Between Chat Lines",
        default = false,
        option = "PlaySoundSeparatingChatLineBreaks",
    },
    {
        key = "unfocusedActivitySound",
        label = "Activity Sound When Unfocused",
        default = true,
        option = "PlayActivitySoundWhenNotFocused",
    },
}

-- Declares one Bool setting per entry on a speech module's settings facade
-- and writes each change straight into the game. setter(optionName, enabled)
-- is the game write, sounds.gameSetter in the addon.
function sounds.addSettings(settings, L, setter)
    for _, def in ipairs(sounds.defs) do
        local field = settings:add({
            type = "Bool",
            key = def.key,
            label = L[def.label],
            default = def.default,
        })
        field.events.valueChange:subscribe(nil, function(event, obj, key, value)
            setter(def.option, value == true)
        end)
    end
end

-- Writes every setting from state (the module's settings object) into the
-- game. A stored false is a value; only a missing value falls back to the
-- default.
function sounds.apply(state, setter)
    for _, def in ipairs(sounds.defs) do
        local value = state[def.key]
        if value == nil then
            value = def.default
        end
        setter(def.option, value == true)
    end
end

-- The game write: C_TTSSettings.SetSetting with the option looked up by
-- name, since Enum is a game global. Returns true when the game took it.
function sounds.gameSetter(optionName, enabled)
    if C_TTSSettings == nil or Enum == nil or Enum.TtsBoolSetting == nil then
        return false
    end
    local option = Enum.TtsBoolSetting[optionName]
    if option == nil then
        return false
    end
    return (pcall(C_TTSSettings.SetSetting, option, enabled))
end

WowVision.speechSounds = sounds
