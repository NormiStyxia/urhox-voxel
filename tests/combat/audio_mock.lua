-- Offline Lua 5.4 engine doubles. No Runtime, network or media decoding.
local Mock = {}
function Mock.New(config)
    config = config or {}
    local state = { nodes = {}, sources = {}, reads = {}, sounds = {}, attempts3D = 0 }
    local sourceMethods = {}
    function sourceMethods:Play(sound, frequency, gain)
        if config.playError then error('unsupported playback') end
        assert(frequency > 1000, 'frequency must be Hz, not pitch multiplier')
        self.sound, self.frequency, self.gain, self.playing = sound, frequency, gain, true
        self.timePosition = 0
    end
    function sourceMethods:Stop()
        if config.stopError then error('stop unsupported') end
        self.stopCalls = (self.stopCalls or 0) + 1
        self.playing, self.fadingOut = false, true
    end
    function sourceMethods:StopImmediate()
        self.playing, self.fadingOut = false, false
        self.immediateCalls = (self.immediateCalls or 0) + 1
    end
    function sourceMethods:SetGain(value) self.gain = value end
    function sourceMethods:SetSoundType(value) self.soundType = value end
    function sourceMethods:SetAutoRemoveMode(value) self.autoRemoveMode = value end
    function sourceMethods:SetDeclickEnabled(value) self.declickEnabled = value end
    function sourceMethods:IsPlaying() return self.playing == true end
    function sourceMethods:SetDistanceAttenuation(near, far, rolloff) self.near, self.far, self.rolloff = near, far, rolloff end
    function sourceMethods:Seek(time)
        if config.seekError then error('seek unavailable') end
        self.seek = time
    end
    local nodeMethods = {}
    function nodeMethods:CreateComponent(kind)
        if kind == 'SoundSource3D' then
            state.attempts3D = state.attempts3D + 1
            if config.no3D then error('3D unavailable') end
        end
        if config.noSource then return nil end
        local source = setmetatable({kind = kind, node = self}, {__index = sourceMethods})
        state.sources[#state.sources + 1] = source
        return source
    end
    function nodeMethods:Remove() self.removed = true end
    function nodeMethods:Dispose() self.disposed = true end
    state.scene = {}
    function state.scene:CreateChild(name)
        if config.noScene then error('scene unavailable') end
        local node = setmetatable({name = name}, {__index = nodeMethods})
        state.nodes[#state.nodes + 1] = node
        return node
    end
    _G.cache = {GetResource = function(_, kind, path)
        assert(kind == 'Sound')
        state.reads[path] = (state.reads[path] or 0) + 1
        if config.resourceError then error('cache unavailable') end
        if config.missing then return nil end
        if not state.sounds[path] then
            local sound = { path = path, frequency = path:find('whoosh') and 44100 or 48000 }
            function sound:GetFrequency() return self.frequency end
            function sound:SetLooped(looped) self.looped = looped end
            state.sounds[path] = sound
        end
        return state.sounds[path]
    end}
    _G.audio = {GetListener = function() return state.listener end}
    _G.SOUND_EFFECT = 'Effect'
    return state
end
function Mock.Active(state)
    local count = 0
    for _, source in ipairs(state.sources) do if source.playing or source.fadingOut then count = count + 1 end end
    return count
end
return Mock
