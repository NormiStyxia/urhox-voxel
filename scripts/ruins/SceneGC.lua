-- Scene-local incremental GC pacing. Start/Stop restore the process GC settings.
local G={}
G.__index=G
function G.New()
    return setmetatable({enabled=true,debug=false,state={running=false,configured=false,
        steps=0,cycles=0,skipped=0,maxMs=0,reclaimed=0}},G)
end
function G:SetEnabled(enabled)
    self.enabled=enabled==true
    if self.enabled and self.state.running and not self.state.configured then
        self.state.pause=collectgarbage('setpause',110)
        self.state.stepmul=collectgarbage('setstepmul',300)
        collectgarbage('incremental',110,300)
        self.state.configured=true
    elseif not self.enabled and self.state.configured then
        collectgarbage('setpause',self.state.pause)
        collectgarbage('setstepmul',self.state.stepmul)
        self.state.configured=false
    end
end
function G:Start()
    self.state.running=true
    self.state.steps,self.state.cycles,self.state.skipped,self.state.maxMs,self.state.reclaimed=0,0,0,0,0
    self.state.frameStart=nil
    self.state.at=Time:GetSystemTime()
    self.state.heap=collectgarbage('count')
    self:SetEnabled(self.enabled)
end
function G:BeginFrame()
    if self.state.running then self.state.frameStart=Time:GetSystemTime() end
end
function G:Step()
    if not self.state.running then return end
    self:SetEnabled(self.enabled) -- direct debug flag changes also restore pacing
    local now=Time:GetSystemTime()
    if self.enabled and self.state.frameStart then
        if now-self.state.frameStart<=12 and now>=self.state.frameStart then
            local before=self.debug and collectgarbage('count') or 0
            local t=self.debug and os.clock() or 0
            local completed=collectgarbage('step',8)
            self.state.steps=self.state.steps+1
            if completed then self.state.cycles=self.state.cycles+1 end
            if self.debug then
                self.state.maxMs=math.max(self.state.maxMs,(os.clock()-t)*1000)
                self.state.reclaimed=self.state.reclaimed+math.max(0,before-collectgarbage('count'))
            end
        else self.state.skipped=self.state.skipped+1 end
    end
    self.state.frameStart=nil -- at most one explicit step per frame
    if now-self.state.at>=1000 then
        local heap=collectgarbage('count')
        if self.debug then
            print(string.format('RuinsGC: heapKB=%.1f deltaKB=%+.1f steps=%d completed=%d skipped=%d stepReclaimedKB=%.1f maxStepCPUms=%.3f',
                heap,heap-self.state.heap,self.state.steps,self.state.cycles,self.state.skipped,self.state.reclaimed,self.state.maxMs))
        end
        self.state.at,self.state.heap=now,heap
        self.state.steps,self.state.cycles,self.state.skipped,self.state.maxMs,self.state.reclaimed=0,0,0,0,0
    end
end
function G:Stop()
    local enabled=self.enabled
    self:SetEnabled(false)
    self.enabled=enabled
    self.state.running=false;self.state.frameStart=nil
end



return G
