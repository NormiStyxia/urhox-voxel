-- Additive action camera, evaluated once per real-time PostUpdate. The ordinary
-- camera owns framing/collision; these offsets never feed its follow accumulator.
local A={}; A.__index=A
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function ease(t) t=clamp(t,0,1);return t*t*(3-2*t) end
local function pulse(t,rise,fall)
    if t<0 or t>=rise+fall then return 0 end
    return t<rise and ease(t/rise) or 1-ease((t-rise)/fall)
end
function A.New()
    return setmetatable({time=0,bow=0,bowRelease=0,output={focus=Vector3.ZERO,distance=0,fov=0,look=1,cross=0}},A)
end
function A:Land() self.landAt,self.landFresh=self.time,true end
function A:Full() self.fullAt=self.time end
function A:Cancel()
    self.landAt,self.fullAt=nil,nil
    self.landFresh=false;self.sprint=0
end
function A:Update(dt,moves,enabled,shakeEnabled,impactEnabled)
    self.time=self.time+math.max(0,dt)
    if self.landFresh then self.landAt,self.landFresh=self.time,false end
    local out=self.output
    out.focus,out.distance,out.fov,out.cross,out.impact=Vector3.ZERO,0,0,0,Vector3.ZERO
    local drawing=moves.clip=='bow_draw' or moves.clip=='bow_hold'
    if drawing then
        self.bow=clamp(moves.charge or 0,0,1)^2
        self.bowRelease=self.bow
        self.bowReleasedAt=nil
    else
        self.bowReleasedAt=self.bowReleasedAt or self.time-dt
        self.bow=self.bowRelease*(1-ease((self.time-self.bowReleasedAt)/.12))
    end
    self.bowDrawing=drawing
    out.cross=math.sqrt(self.bow)
    out.look=enabled and math.tan(math.rad((55-8.25*self.bow)/2))/math.tan(math.rad(55/2)) or 1
    local sprint=enabled and impactEnabled~=false and not drawing and self.bow<=0 and (moves.sprintWeight or 0) or 0
    local oldSprint=self.sprint or 0
    self.sprint=sprint>oldSprint and math.min(sprint,oldSprint+dt/.22) or math.max(sprint,oldSprint-dt/.18)
    if not enabled then self.sprint=0;return out end
    -- Single source: 55*(1-.15*u^2), full 46.75 degrees.
    out.fov=-8.25*self.bow
    local id=moves.clip
    if impactEnabled~=false and id and (id:find('sword_light_',1,true) or id=='sword_heavy_release') then
        local clip=require('combat.AnimClips').Clips[id]
        local t=moves.whooshTime or 0 -- existing action clock, frozen by hitstop
        local start=clip.phases.active[1]
        if t<start and t>=start-.06 then
            out.distance=out.distance+.08*math.sin(math.pi*(t-start+.06)/.06)
        end
        if id=='sword_heavy_release' and t>=start then
            out.fov=math.max(out.fov,2*pulse(t-start,.02,.12))
        end
    end
    if self.bow<=0 and impactEnabled~=false and self.sprint>0 then
        out.distance=math.max(out.distance,.20*self.sprint)
        out.fov=math.max(out.fov,1.5*self.sprint)
    end
    if self.landAt and shakeEnabled~=false and impactEnabled~=false then
        out.impact=Vector3(0,-.03*pulse(self.time-self.landAt,.02,.10),0)
    end
    return out
end
A.Pulse=pulse
return A
