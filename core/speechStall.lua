-- Keeping WowVision's speech queue moving when the game never ends a line.
--
-- The queue (tbc/ and retail/speech.lua) sends one line at a time and waits
-- for VOICE_CHAT_TTS_PLAYBACK_FINISHED (or FAILED) before the next. A line
-- thrown away by StopSpeakingText never gets either: Blizzard's own chat
-- speech says so ("Purged utterances never signal
-- VOICE_CHAT_TTS_PLAYBACK_FINISHED", TextToSpeech_StopAll in
-- Blizzard_ChatFrame/Shared/TextToSpeechFrame.lua) and clears its playback
-- state itself. Ours stayed busy, and everything after it waited unspoken
-- until something called the queue's stop (Escape, a window); the
-- surroundings cut their own line at every new place (user 2026-11-05).
--
-- So: any stop (whoever calls it) frees the queue, the end of a line that was
-- stopped is not taken for the end of the next one, and a line that never
-- starts or never ends frees it after a while. Each time that last net
-- catches one it is written to WowVisionDump.speechStalls, to read after a
-- walk.
local stall = {}

-- seconds a sent line may wait for its start, and play, before the queue moves on
stall.NOT_STARTED = 5
stall.LONGEST = 60
stall.MAX_LOG = 50
-- ends of stopped lines remembered at most (they may never come)
local MAX_STALE = 20

local Guard = {}
Guard.__index = Guard

-- module: the speech module (queue, speaking, current); poll: its pollQueue;
-- now: the clock (GetTime in the game).
function stall.new(module, poll, now)
    return setmetatable({ module = module, poll = poll, now = now, stale = {}, staleCount = 0, busySince = nil }, Guard)
end

function Guard:sent(item)
    item.sentAt = self.now()
    self.busySince = nil
end

function Guard:started(utteranceID)
    local module = self.module
    local current = module.current
    if current ~= nil then
        if current.id == nil then
            current.id = utteranceID
            current.startedAt = self.now()
        end
    elseif not module.speaking then
        -- someone else's line (the game's own alerts speak past the queue)
        self.busySince = self.now()
    end
    module.speaking = true
end

-- Whether this end frees the queue: not the end of a line already stopped,
-- nor of another line while ours plays.
function Guard:ended(utteranceID)
    if self.stale[utteranceID] then
        self.stale[utteranceID] = nil
        self.staleCount = self.staleCount - 1
        return false
    end
    local current = self.module.current
    if current ~= nil and current.id ~= nil and current.id ~= utteranceID then
        return false
    end
    self.busySince = nil
    return true
end

function Guard:free()
    local module = self.module
    module.speaking = false
    module.current = nil
    self.busySince = nil
    self.poll()
end

-- After C_VoiceChat.StopSpeakingText, whoever called it.
function Guard:stopped()
    local current = self.module.current
    if current ~= nil and current.id ~= nil then
        if self.staleCount >= MAX_STALE then
            self.stale, self.staleCount = {}, 0
        end
        self.stale[current.id] = true
        self.staleCount = self.staleCount + 1
    end
    self:free()
end

function Guard:watchStops()
    if C_VoiceChat ~= nil and C_VoiceChat.StopSpeakingText ~= nil and hooksecurefunc ~= nil then
        hooksecurefunc(C_VoiceChat, "StopSpeakingText", function()
            self:stopped()
        end)
    end
end

-- Why the queue is stuck, or nil.
function Guard:stuck()
    local module = self.module
    if not module.speaking then
        return nil
    end
    local now = self.now()
    local current = module.current
    if current ~= nil then
        if current.startedAt ~= nil then
            if now - current.startedAt > stall.LONGEST then
                return "never ended", now - current.startedAt
            end
        elseif current.sentAt ~= nil and now - current.sentAt > stall.NOT_STARTED then
            return "never started", now - current.sentAt
        end
    elseif self.busySince ~= nil and now - self.busySince > stall.LONGEST then
        return "other speech never ended", now - self.busySince
    end
    return nil
end

local function record(entry)
    if type(WowVisionDump) ~= "table" then
        return
    end
    local list = WowVisionDump.speechStalls
    if type(list) ~= "table" then
        list = {}
        WowVisionDump.speechStalls = list
    end
    if #list >= stall.MAX_LOG then
        table.remove(list, 1)
    end
    list[#list + 1] = entry
end

-- Run every second: frees a stuck queue and writes it down.
function Guard:check()
    local reason, seconds = self:stuck()
    if reason == nil then
        return nil
    end
    local current = self.module.current
    local tag = current and current.tag
    record({
        time = date and date("%Y-%m-%d %H:%M:%S") or nil,
        reason = reason,
        seconds = math.floor(seconds * 10 + 0.5) / 10,
        kind = tag and tag.kind or nil,
        waiting = #self.module.queue,
    })
    self:free()
    return reason
end

WowVision.speechStall = stall
