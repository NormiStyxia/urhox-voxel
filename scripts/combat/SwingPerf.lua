-- R10: elapsed seconds timestamp frames; static milliseconds measure stages.
-- No per-sample wrappers/tables, file IO, or forced GC.
local P={frame=0,revision=0,enabled=true,attackId=0,combo=0,clip='none',
    motionRays=0,rangeRays=0,gridCalls=0,volumes=0,cells=0,substeps=0,
    fallbackReason='none',fallbacks=0,gridBudgetExceeded=0,rangeUsed=0}
local names={'input','motion','QueryZone','HitEvent','recovery','GridHit','range'}
local stages={}
for _,name in ipairs(names) do stages[name]={ms=0,calls=0} end
P.stages=stages
local nextLog=-math.huge
function P.Clock()
    if Time and Time.GetSystemTime then return Time:GetSystemTime() end
    return 0 -- offline tests supply a strict static clock
end
function P.BeginFrame(state)
    P.frame=P.frame+1;P.revision=P.revision+1
    if state then
        if state.swingPerf==nil then state.swingPerf=true end
        P.enabled=state.swingPerf~=false
    end
    P.motionRays,P.rangeRays,P.gridCalls,P.volumes,P.cells,P.substeps=0,0,0,0,0,0
    P.fallbacks,P.gridBudgetExceeded,P.rangeUsed=0,0,0
    P.fallbackReason='none'
    for _,stage in pairs(stages) do stage.ms,stage.calls=0,0 end
    if P.enabled then
        P.at=time and time:GetElapsedTime() or 0
        P.heap=collectgarbage('count')
    end
end
-- Engine exposes no world revision; only cache in explicit read-only scopes.
function P.Invalidate() P.revision=P.revision+1 end
function P.Begin() return P.enabled and P.Clock() or nil end
function P.Finish(name,start)
    if not start or not P.enabled then return end
    local elapsed=P.Clock()-start
    if elapsed<0 then return end
    local stage=stages[name]
    stage.ms=stage.ms+elapsed;stage.calls=stage.calls+1
end
function P.Context(id,combo,clip)
    P.attackId,P.combo,P.clip=id or 0,combo or 0,clip or 'none'
end
function P.EndFrame()
    if not P.enabled then return end
    local peak,name=0,'rays'
    for id,stage in pairs(stages) do if stage.ms>peak then peak,name=stage.ms,id end end
    P.heapDelta=collectgarbage('count')-(P.heap or collectgarbage('count'))
    if peak<8 and P.motionRays<=96 and P.rangeRays<=16 and P.fallbacks<=4 then return end
    local now=time and time:GetElapsedTime() or 0
    if now<(P.lastAt or now) then nextLog=now end
    P.lastAt=now
    if now<nextLog then return end
    nextLog=now+.5
    print(string.format('SwingPerf stage=%s ms=%.0f frame=%d attackId=%d combo=%d clip=%s motionRays=%d rangeRays=%d substeps=%d gridCalls=%d fallbackReason=%s fallbacks=%d volumes=%d cells=%d gridBudgetExceeded=%d heapDeltaKB=%.2f clock=static-ms at=%.3f',
        name,peak,P.frame,P.attackId,P.combo,P.clip,P.motionRays,P.rangeRays,P.substeps,P.gridCalls,P.fallbackReason,P.fallbacks,P.volumes,P.cells,P.gridBudgetExceeded,P.heapDelta,now))
end
return P
