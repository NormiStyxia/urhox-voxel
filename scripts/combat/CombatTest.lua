-- PC F11 diagnostics. Drives the same input port as human controls; never calls
-- ApplyHit, Action or animation Play to manufacture a successful measurement.
-- Scene supplies safe BETWEEN-step staging; displacement uses controller position.
local T={}; T.__index=T
local Clips=require('combat.AnimClips').Clips
local function distance(a,b) return Vector3(a.x-b.x,0,a.z-b.z):Length() end
function T.New(o)
    local self=setmetatable({o=o,active=true,index=0,passed=0,failed=0,steps={
        {id='combo',weapon='sword'}, {id='heavy_short',weapon='sword'},
        {id='heavy_full',weapon='sword'},
        {id='slide_forward',weapon='sword',axis=Vector3(0,0,1)},
        {id='slide_back',weapon='sword',axis=Vector3(0,0,-1)},
        {id='slide_left',weapon='sword',axis=Vector3(-1,0,0)},
        {id='slide_right',weapon='sword',axis=Vector3(1,0,0)},
        {id='slide_cancel',weapon='sword',axis=Vector3(0,0,-1),cancel=true},
        {id='attack_slide_attack',weapon='sword',axis=Vector3(0,0,-1),cancel=true},
        {id='arrow_weak',weapon='bow',charge=.18},
        {id='arrow_mid',weapon='bow',charge=.5},
        {id='arrow_full',weapon='bow',charge=1},
        {id='arrow_cancel',weapon='bow',cancel=true},
    }},T)
    o.moves.observe=function(kind,data) self:Observe(kind,data) end
    self:Log('BEGIN; safe staging between steps; real input/physics/hit settlement; any key aborts')
    return self
end
function T:Log(text) (self.o.log or print)('CombatTest: '..text) end
function T:Result(name,ok,values)
    self[ok and 'passed' or 'failed']=self[ok and 'passed' or 'failed']+1
    self:Log(name..' '..(ok and 'PASS' or 'FAIL')..' '..(values or ''))
end
function T:Stop(reason)
    if not self.active then return end
    self.active=false; self.o.moves.observe=nil
    self.o.moves:Cancel('selftest-'..reason)
    self.o.cleanup(reason)
    self:Log(string.format('END %s pass=%d fail=%d; synthetic inputs cleared',reason,self.passed,self.failed))
end
function T:Observe(kind,e)
    if not self.active or not self.step then return end
    local m=self.o.moves
    if kind=='start' then
        self.starts[e.clip]=(self.starts[e.clip] or 0)+1
        if e.clip=='dodge_slide' then
            self.slideAt=e.age; self.slideOrigin=self.o.position(); self.cdInitial=m.dodgeCool
        elseif self.slideAt and e.clip:find('sword_light_',1,true) then
            self.followAt=m.slideElapsed; self.followSampled=e.age-self.slideAt
            self.captureDistance=true -- next pre-physics sample includes the boundary frame
        end
    elseif kind=='hit' and e.enemy==self.o.dummy then
        self.hits[e.clip]=(self.hits[e.clip] or 0)+1
        self.damage[e.clip]=(self.damage[e.clip] or 0)+e.damage
        self:Log(string.format('%s hit clip=%s weapon=%s dmg=%.3f',self.step.id,e.clip or '?',e.weapon or '?',e.damage))
    elseif kind=='event' then
        if e.name=='hit_on' then
            local t=e.t*Clips[e.clip].dur
            self.hitTimes[e.clip]=t
            self:Log(string.format('%s hit_on clip=%s action_t=%.4f observed_t=%.4f',self.step.id,e.clip,t,e.age-m.clipStartedAt))
        elseif e.name=='iframe_on' then self.iframeOn=e.age
        elseif e.name=='iframe_off' then self.iframeDuration=m.slideElapsed end
    end
end
function T:Arrow(p)
    if not self.active or not self.step then return end
    self.shots[#self.shots+1]={tier=p.tier,speed=p.vel:Length(),damage=p.damage,crystal=p.crystalDamage,radius=p.crystalRadius,actual=p}
    self:Log(string.format('%s arrow tier=%s speed=%.3f damage=%.3f crystal=%.3f radius=%.2f',
        self.step.id,p.tier,p.vel:Length(),p.damage,p.crystalDamage,p.crystalRadius))
end
function T:Next()
    self.index=self.index+1
    self.step=self.steps[self.index]
    if not self.step then self:Stop('complete'); return false end
    self.t,self.maxDt,self.sent,self.released,self.phase=0,0,false,false,0
    self.starts,self.hits,self.damage,self.hitTimes,self.shots={},{},{},{},{}
    self.slideAt,self.slideOrigin,self.slideDistance,self.cdMeasured=nil,nil,nil,nil
    self.iframeOn,self.iframeDuration,self.followAt,self.captureDistance=nil,nil,nil,false
    self.o.moves:Cancel('selftest-step')
    if not self.o.prepare(self.step) then self:Result(self.step.id,false,'no safe staging point'); self:Stop('unsafe'); return false end
    self:Log('STEP '..self.step.id..' (neutral settle .35s)')
    return true
end
function T:Finish()
    local s,m=self.step,self.o.moves
    if s.id=='combo' then
        for i=1,3 do
            local id='sword_light_'..i
            self:Result(id,self.hits[id]==1 and self.hitTimes[id]~=nil,
                string.format('hit_on=%.4f damage=%.3f hits=%d',self.hitTimes[id] or -1,self.damage[id] or 0,self.hits[id] or 0))
        end
    elseif s.id:find('heavy_',1,true)==1 then
        local damage=self.damage.sword_heavy_release or 0
        local expected=m.rig:GetStats().attack*(s.id=='heavy_full' and 2.2 or 1.6)
        self:Result(s.id,(self.hits.sword_heavy_release or 0)==1 and math.abs(damage-expected)<.01,
            string.format('damage=%.3f expected=%.3f hit_on=%.4f',damage,expected,self.hitTimes.sword_heavy_release or -1))
    elseif s.axis then
        local d=self.slideDistance or (self.slideOrigin and distance(self.o.position(),self.slideOrigin)) or -1
        local target=s.cancel and 1.92 or 2.2
        local inv=self.iframeDuration or -1
        local cd=self.cdMeasured or -1
        self:Result(s.id,self.slideAt~=nil and math.abs(d-target)<=.08 and inv>=.19 and inv<=.20+self.maxDt*2
            and cd>=.49 and cd<=.50+self.maxDt*2,
            string.format('controller_distance=%.4f expected=%.2f iframe_observed=%.4f cd_observed=%.4f max_dt=%.4f',d,target,inv,cd,self.maxDt))
        if s.cancel then
            self:Result(s.id..'_follow',self.followAt~=nil and self.followAt>=.22-1e-6 and self.followAt<=.22+self.maxDt*2
                and (s.id~='attack_slide_attack' or (self.starts.sword_light_2 or 0)==1),
                string.format('attack_after_slide=%.4f next_clip2=%d',self.followAt or -1,self.starts.sword_light_2 or 0))
        end
    elseif s.id=='arrow_cancel' then
        self:Result(s.id,self.phase==2 and #self.shots==0 and m.charge==0 and not m.pendingFire,
            string.format('shots=%d charge=%.3f cancel_via_dodge=%s',#self.shots,m.charge,tostring(self.starts.dodge_slide~=nil)))
    else
        local shot=self.shots[1]; local tier=s.id:sub(7)
        local damage=self.damage.bow_release or 0
        local stats=m.rig:GetStats()
        local speed=({weak=18,mid=30,full=44})[tier]*(stats.projectileSpeed or 1)
        local expected=(stats.attack or 8)*({weak=.5,mid=1,full=1.8})[tier]
        self:Result(s.id,#self.shots==1 and shot.tier==tier and (self.hits.bow_release or 0)==1
            and math.abs(damage-expected)<.01 and math.abs(shot.speed-speed)<.01,
            string.format('shots=%d tier=%s speed=%.3f hit_damage=%.3f crystal_resolved=%.3f',#self.shots,shot and shot.tier or 'none',shot and shot.speed or -1,damage,shot and shot.actual.crystalDamage or 0))
        if shot and shot.radius>0 then self:Log(s.id..' crystal secondary-target damage UNVERIFIED (single dummy); resolved burst='..shot.actual.crystalDamage) end
    end
end
-- Called once before character movement. The previous frame's actual cc motion
-- has completed, so no commanded-distance sum is mislabelled as physical travel.
function T:Input(dt,allowed)
    local neutral={allowed=allowed,axis=Vector3.ZERO}
    if not self.active then return nil end
    if not allowed or self.o.moves.dead then self:Stop('blocked/focus/menu/death'); return nil end
    if not self.step and not self:Next() then return neutral end
    local m,s=self.o.moves,self.step
    self.t=self.t+dt; self.maxDt=math.max(self.maxDt,dt)
    if self.captureDistance then
        self.slideDistance=distance(self.o.position(),self.slideOrigin); self.captureDistance=false
    end
    if self.slideAt then
        if not self.cdMeasured and m.dodgeCool<=0 then self.cdMeasured=m.age-self.slideAt end
        if not self.slideDistance and m.clip~='dodge_slide' and not s.cancel then self.slideDistance=distance(self.o.position(),self.slideOrigin) end
    end
    if self.t<.35 then return neutral end
    local t=self.t-.35
    if t>4.5 then self:Result(s.id,false,'timeout'); self:Next(); return neutral end
    if s.id=='combo' then
        if not m.clip and self.phase<3 then neutral.attackTap=true; self.phase=self.phase+1 end
        if self.phase==3 and not neutral.attackTap and not m.clip and t>.2 then self:Finish(); self:Next() end
    elseif s.id:find('heavy_',1,true)==1 then
        if not self.released then
            neutral.attack=true
            if (s.id=='heavy_short' and m.hold>=.52) or (s.id=='heavy_full' and m.fullCharged) then
                neutral.attack=false; self.released=true
            end
        elseif not m.clip then self:Finish(); self:Next() end
    elseif s.axis then
        if s.id=='attack_slide_attack' and self.phase==0 then neutral.attackTap=true; self.phase=1
        elseif not self.sent and (s.id~='attack_slide_attack' or m.cancelOpen) then
            neutral.dodge=true; neutral.axis=self.o.direction(s.axis); self.sent=true
        elseif s.cancel and self.slideAt and self.phase<2 then neutral.attackTap=true; self.phase=2 end
        if self.sent and t>1.5 then self:Finish(); self:Next() end
    elseif s.id=='arrow_cancel' then
        if self.phase==0 then neutral.attack=true; if m.charge>=.5 then self.phase=1 end
        elseif self.phase==1 then neutral.dodge=true; self.phase=2
        elseif t>1.5 then self:Finish(); self:Next() end
    else
        if not self.released then
            neutral.attack=true
            if m.clip=='bow_hold' and m.charge>=s.charge then neutral.attack=false; self.released=true end
        elseif t>2 then self:Finish(); self:Next() end
    end
    -- Never carry a final frame's old hold/tap into the next case.
    if self.step~=s or not self.active then return {allowed=allowed,axis=Vector3.ZERO} end
    return neutral
end
return T
