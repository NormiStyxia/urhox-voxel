-- Offline Lua 5.4 engine doubles. No Runtime, network or media decoding.
local Mock = {}
function Mock.New(config)
    config = config or {}
    local state = { nodes = {}, sources = {}, reads = {}, sounds = {}, attempts3D = 0, nowMs = 0, readCount = 0, syncReads = 0, order = {}, pending = {} }
    local sourceMethods = {}
    function sourceMethods:Play(sound, frequency, gain)
        assert(type(frequency)=='number' and type(gain)=='number')
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
    function sourceMethods:SetGain(value) assert(type(value)=='number'); self.gain = value end
    function sourceMethods:SetSoundType(value) assert(type(value)=='string'); self.soundType = value end
    function sourceMethods:SetAutoRemoveMode(value) assert(math.type(value)=='integer'); self.autoRemoveMode = value end
    function sourceMethods:SetDeclickEnabled(value) assert(type(value)=='boolean'); self.declickEnabled = value end
    function sourceMethods:IsPlaying() return self.playing == true end
    function sourceMethods:SetDistanceAttenuation(near, far, rolloff)
        assert(type(near)=='number' and type(far)=='number' and type(rolloff)=='number')
        self.near, self.far, self.rolloff = near, far, rolloff
    end
    function sourceMethods:Seek(time)
        if config.seekError then error('seek unavailable') end
        self.seek = time
    end
    local nodeMethods = {}
    function nodeMethods:CreateComponent(kind)
        assert(type(kind) == 'string')
        state.nowMs = state.nowMs + (config.createMs or 0)
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
        assert(type(name) == 'string')
        state.nowMs = state.nowMs + (config.createMs or 0)
        if config.noScene then error('scene unavailable') end
        local node = setmetatable({name = name}, {__index = nodeMethods})
        state.nodes[#state.nodes + 1] = node
        return node
    end
    local function resource(path)
        if config.missing then return nil end
        if not state.sounds[path] then
            local sound = {path = path, frequency = path:find('whoosh') and 44100 or 48000}
            function sound:GetFrequency() return self.frequency end
            function sound:SetLooped(looped) assert(type(looped)=='boolean'); self.looped = looped end
            state.sounds[path] = sound
        end
        return state.sounds[path]
    end
    local function record(kind, path, sendFailure)
        assert(kind == 'Sound' and type(kind)=='string' and type(path)=='string')
        assert(type(sendFailure)=='boolean', 'ResourceCache sendEventOnFailure is boolean')
        state.reads[path] = (state.reads[path] or 0) + 1
        state.readCount = state.readCount + 1
        state.order[#state.order+1] = path
        state.nowMs = state.nowMs + (config.loadMs or 0)
    end
    _G.cache = {
        GetResource = function(_, kind, path, sendFailure)
            record(kind, path, sendFailure)
            state.syncReads = state.syncReads + 1
            if config.resourceError then error('cache unavailable') end
            return resource(path)
        end,
        BackgroundLoadResource = function(_, kind, path, sendFailure)
            if config.noAsync then error('unsupported async API') end
            record(kind, path, sendFailure)
            if config.resourceError or config.asyncReject then return false end
            state.pending[path] = config.asyncDelay or 1
            return true
        end,
        GetExistingResource = function(_, kind, path)
            assert(kind=='Sound' and type(path)=='string')
            if state.pending[path] then
                state.pending[path] = state.pending[path] - 1
                if state.pending[path] <= 0 then
                    state.pending[path] = nil
                    return resource(path)
                end
            end
            return state.sounds[path]
        end,
        GetNumBackgroundLoadResources = function()
            local count = 0
            for _ in pairs(state.pending) do count = count + 1 end
            return count
        end,
    }
    _G.audio = {GetListener = function()
        state.nowMs = state.nowMs + (state.listenerMs or 0)
        return state.listener
    end}
    -- 区分静态 Time 类表与实例；错误接收者不能静默通过预算测试。
    local timeClass = {}
    function timeClass:GetSystemTime()
        assert(self == timeClass, 'GetSystemTime requires Time class')
        return state.nowMs
    end
    _G.Time = timeClass
    _G.time = {GetSystemTime = timeClass.GetSystemTime,
        GetFrameNumber = function() return state.engineFrame end}
    _G.SOUND_EFFECT = 'Effect'
    return state
end
function Mock.Active(state)
    local count = 0
    for _, source in ipairs(state.sources) do if source.playing or source.fadingOut then count = count + 1 end end
    return count
end
return Mock
