local module = WowVision.base.navigation:createModule("compass")
local L = module.L
module:setLabel(L["Compass"])
local pi = math.pi
local settings = module:hasSettings()

-- How WowVision names a direction, here and in every module that speaks one (surroundings): the
-- 8 compass words, or the 12 hours of a clock laid on the map (12 = north, 3 = east), said as
-- bare numbers ("12", not "12 o'clock"; user 2026-10-01: shorter, and finer than the words).
settings:add({
    key = "directions",
    type = "Choice",
    label = L["Directions"],
    default = "compass",
    choices = {
        { label = L["Compass Words"], value = "compass" },
        { label = L["Clock Hours"], value = "clock" },
    },
})

local directionAlert = module:addAlert({
    key = "direction",
    label = L["Speak Compass Direction"],
})

directionAlert:addOutput({
    type = "Voice",
    key = "voice",
    label = L["Voice Alert"],
    getPath = function(self, message)
        if message.hour then
            -- no voice files for hours: the TTS output speaks them
            return nil
        end
        return "Path", "directions/" .. message.direction .. ".mp3"
    end,
})

directionAlert:addOutput({
    type = "TTS",
    key = "tts",
    label = L["TTS Alert"],
    enabled = false,
    buildMessage = function(self, message)
        if message.hour then
            return tostring(message.hour)
        end
        return L[message.direction]
    end,
})

local zoneChanged = module:addAlert({
    key = "zoneChanged",
    label = L["Zone Changed Alert"],
})

zoneChanged:addOutput({
    type = "TTS",
    key = "tts",
    label = L["TTS Alert"],
    shouldFire = function(self, message)
        return message.zone ~= ""
    end,
    buildMessage = function(self, message)
        return message.zone
    end,
})

zoneChanged:addOutput({
    type = "Sound",
    key = "sound",
    label = L["Sound Alert"],
    enabled = false,
})

local subzoneChanged = module:addAlert({
    key = "subzoneChanged",
    label = L["Subzone Changed Alert"],
})

subzoneChanged:addOutput({
    type = "TTS",
    key = "tts",
    label = L["TTS Alert"],
    shouldFire = function(self, message)
        return message.subzone ~= ""
    end,
    buildMessage = function(self, message)
        return message.subzone
    end,
})

subzoneChanged:addOutput({
    type = "Sound",
    key = "sound",
    label = L["Sound Alert"],
    enabled = false,
})

local outdoorsAlert = module:addAlert({
    key = "outdoors",
    label = L["Outdoors Alert"],
})

outdoorsAlert:addOutput({
    type = "TTS",
    key = "tts",
    label = L["TTS Alert"],
    buildMessage = function(self, message)
        return L["outdoors"]
    end,
})

outdoorsAlert:addOutput({
    type = "Sound",
    key = "sound",
    label = L["Sound Alert"],
    enabled = false,
})

local indoorsAlert = module:addAlert({
    key = "indoors",
    label = L["Indoors Alert"],
})

indoorsAlert:addOutput({
    type = "TTS",
    key = "tts",
    label = L["TTS Alert"],
    buildMessage = function(self, message)
        return L["indoors"]
    end,
})

indoorsAlert:addOutput({
    type = "Sound",
    key = "sound",
    label = L["Sound Alert"],
    enabled = false,
})

local flyingStartedAlert = module:addAlert({
    key = "flyingStarted",
    label = L["Flying Started Alert"],
})

flyingStartedAlert:addOutput({
    type = "TTS",
    key = "tts",
    label = L["TTS Alert"],
    buildMessage = function(self, message)
        return L["flying"]
    end,
})

flyingStartedAlert:addOutput({
    type = "Sound",
    key = "sound",
    label = L["Sound Alert"],
    enabled = false,
})

local flyingEndedAlert = module:addAlert({
    key = "flyingEnded",
    label = L["Flying Ended Alert"],
})

flyingEndedAlert:addOutput({
    type = "TTS",
    key = "tts",
    label = L["TTS Alert"],
    buildMessage = function(self, message)
        return L["flying ended"]
    end,
})

flyingEndedAlert:addOutput({
    type = "Sound",
    key = "sound",
    label = L["Sound Alert"],
    enabled = false,
})

local swimmingAlert = module:addAlert({
    key = "swimming",
    label = L["Swimming Alert"],
})

swimmingAlert:addOutput({
    type = "TTS",
    key = "tts",
    label = L["TTS Alert"],
    buildMessage = function(self, message)
        return L["swimming"]
    end,
})

swimmingAlert:addOutput({
    type = "Sound",
    key = "sound",
    label = L["Sound Alert"],
    enabled = false,
})

local divingAlert = module:addAlert({
    key = "diving",
    label = L["Diving Alert"],
})

divingAlert:addOutput({
    type = "TTS",
    key = "tts",
    label = L["TTS Alert"],
    buildMessage = function(self, message)
        return L["diving"]
    end,
})

divingAlert:addOutput({
    type = "Sound",
    key = "sound",
    label = L["Sound Alert"],
    enabled = false,
})

module:registerEvent("event", "ZONE_CHANGED_NEW_AREA")
module:registerEvent("event", "ZONE_CHANGED")
module:registerEvent("event", "ZONE_CHANGED_INDOORS")

settings:addRef("direction", directionAlert.parameters)
settings:addRef("zoneChanged", zoneChanged.parameters)
settings:addRef("subzoneChanged", subzoneChanged.parameters)
settings:addRef("outdoors", outdoorsAlert.parameters)
settings:addRef("indoors", indoorsAlert.parameters)
settings:addRef("flyingStarted", flyingStartedAlert.parameters)
settings:addRef("flyingEnded", flyingEndedAlert.parameters)
settings:addRef("swimming", swimmingAlert.parameters)
settings:addRef("diving", divingAlert.parameters)

-- The clock hour (1..12) of a facing (radians, counter-clockwise from north) on a north-up clock.
function module:getHour(angle)
    if angle == nil then
        return nil
    end
    local bearing = (360 - math.deg(angle)) % 360
    local hour = math.floor((bearing + 15) / 30) % 12
    return hour == 0 and 12 or hour
end

-- Whether directions are spoken as clock hours (the Directions setting).
function module:clockMode()
    return self.settings.directions == "clock"
end

function module:getDirection(angle)
    if angle == nil then
        return nil
    end
    if self:clockMode() then
        return "hour" .. self:getHour(angle)
    end
    if angle >= 15 * pi / 8 or angle < pi / 8 then
        return "north"
    elseif angle >= pi / 8 and angle < 3 * pi / 8 then
        return "northwest"
    elseif angle >= 3 * pi / 8 and angle < 5 * pi / 8 then
        return "west"
    elseif angle >= 5 * pi / 8 and angle < 7 * pi / 8 then
        return "southwest"
    elseif angle >= 7 * pi / 8 and angle < 9 * pi / 8 then
        return "south"
    elseif angle >= 9 * pi / 8 and angle < 11 * pi / 8 then
        return "southeast"
    elseif angle >= 11 * pi / 8 and angle < 13 * pi / 8 then
        return "east"
    elseif angle >= 13 * pi / 8 and angle < 15 * pi / 8 then
        return "northeast"
    end
    error("Malformed player angle")
end

function module:getOutdoorsIndoors()
    if IsOutdoors() then
        return "outdoors"
    end
    if IsIndoors() then
        return "indoors"
    end
    return nil
end

function module:onEnable()
    self.angle = GetPlayerFacing()
    self.direction = self:getDirection(self.angle)
    self.outdoorsIndoors = self:getOutdoorsIndoors()
    self.isFlying = IsFlying()
    self.isSwimming = IsSwimming()
    self.isSubmerged = IsSubmerged()
    self:hasUpdate(function(self)
        local angle = GetPlayerFacing()
        if not angle then
            return
        end
        local direction = self:getDirection(angle)
        if direction and direction ~= self.direction then
            local hour = self:clockMode() and self:getHour(angle) or nil
            directionAlert:fire({
                angle = angle,
                direction = direction,
                hour = hour,
            })
            -- the voice output has files for the compass words only: with the hours, it speaks
            -- the number itself unless the TTS output already does
            if hour and directionAlert.enabled then
                local voiceOn, ttsOn = false, false
                for _, output in ipairs(directionAlert.outputs) do
                    if output.key == "voice" and output.enabled then
                        voiceOn = true
                    elseif output.key == "tts" and output.enabled then
                        ttsOn = true
                    end
                end
                if voiceOn and not ttsOn then
                    WowVision:speak(tostring(hour))
                end
            end
        end
        self.angle, self.direction = angle, direction

        local outdoorsIndoors = self:getOutdoorsIndoors()
        if outdoorsIndoors ~= self.outdoorsIndoors and outdoorsIndoors ~= nil then
            if outdoorsIndoors == "outdoors" then
                outdoorsAlert:fire({})
            elseif outdoorsIndoors == "indoors" then
                indoorsAlert:fire({})
            end
            self.outdoorsIndoors = outdoorsIndoors
        end

        local isFlying = IsFlying()
        if isFlying ~= self.isFlying then
            if isFlying then
                flyingStartedAlert:fire({})
            else
                flyingEndedAlert:fire({})
            end
            self.isFlying = isFlying
        end

        local isSwimming = IsSwimming()
        if isSwimming and not self.isSwimming then
            swimmingAlert:fire({})
        end
        self.isSwimming = isSwimming

        local isSubmerged = IsSubmerged()
        if isSubmerged and not self.isSubmerged then
            divingAlert:fire({})
        end
        self.isSubmerged = isSubmerged
    end)
end

function module:onEvent(event, ...)
    if event == "ZONE_CHANGED_NEW_AREA" then
        zoneChanged:fire({
            zone = GetRealZoneText(),
        })
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        subzoneChanged:fire({
            subzone = GetSubZoneText(),
        })
    end
end
