-- Additive action camera, evaluated once per real-time PostUpdate. The ordinary
-- camera owns framing/collision; these offsets never feed its follow accumulator.
local A={}; A.__index=A
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function ease(t) t=clamp(t,0,1);return t*t*(3-2*t) end
local function pulse(t,rise,fall)
    if t<0 or t>=rise+fall then return 0 end
    return t<rise and ease(t/rise) or 1-ease((t-rise)/fall)
end
-- Unit displacement response, zero initial velocity. zeta=.745 gives 3%
-- overshoot; first crossing at .18s. Analytic solution is independent of FPS.
function A.Spring(t)
    if t<0 then return 1 end
    if t>.65 then return 0 end
    local z=.745
    local q=math.sqrt(1-z*z)
    local w=(math.pi-math.atan(q/z))/(.18*q)
    return math.exp(-z*w*t)*(math.cos(w*q*t)+z/q*math.sin(w*q*t))
end
function A.New()
    return setmetatable({time=0,bow=0,bowRelease=0,output={focus=Vector3.ZERO,distance=0,fov=0,look=1,cross=0}},A)
end
function A:Slide(direction)
    self.slideAt,self.slideDir,self.followAt=self.time,direction,nil
end
function A:Follow()
    self.slideAt=nil;self.followAt=self.time
end
function A:Land() self.landAt=self.time end
function A:Full() self.fullAt=self.time end
function A:Cancel()
    self.slideAt,self.followAt,self.landAt,self.fullAt=nil,nil,nil,nil
end
function A:Update(dt,moves,enabled,shakeEnabled)
    self.time=self.time+math.max(0,dt)
    local out=self.output
    out.focus,out.distance,out.fov,out.cross=Vector3.ZERO,0,0,0
    local drawing=moves.clip=='bow_draw' or moves.clip=='bow_hold'
    if drawing then
        if not self.bowDrawing then self.bowStart,self.bowFrom=self.time-dt,self.bow end
        self.bow=self.bowFrom+(1-self.bowFrom)*ease((self.time-self.bowStart)/.20)
        self.bowRelease=self.bow
        self.bowReleasedAt=nil
    else
        self.bowReleasedAt=self.bowReleasedAt or self.time-dt
        self.bow=self.bowRelease*(1-ease((self.time-self.bowReleasedAt)/.10))
    end
    self.bowDrawing=drawing
    out.cross=self.bow
    out.look=enabled and (1-.40*self.bow) or 1
    if not enabled then return out end
    -- Base camera remains 55. This is the sole bow FOV source (55 -> 43).
    out.fov=-12*self.bow
    if self.slideAt then
        local t=self.time-self.slideAt
        -- Lag opposes travel; neither yaw/pitch/roll nor screen-space reticle move.
        out.focus=-(self.slideDir or Vector3.FORWARD)*(.30*A.Spring(t))
        out.distance=.25*pulse(t,.08,.25)
        out.fov=out.fov+3*pulse(t,.05,.20)
    end
    if self.followAt then out.distance=-.15*pulse(self.time-self.followAt,.04,.14) end
    local id=moves.clip
    if id and (id:find('sword_light_',1,true) or id=='sword_heavy_release') then
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
    if self.landAt then out.focus=out.focus+Vector3(0,-.03*pulse(self.time-self.landAt,.02,.10),0) end
    if shakeEnabled and self.fullAt and self.time-self.fullAt<.08 then
        local t=self.time-self.fullAt
        out.focus=out.focus+Vector3(0,.006*math.sin(t*math.pi*2/.08)*(1-t/.08),0)
    end
    return out
end
A.Pulse=pulse
return A
