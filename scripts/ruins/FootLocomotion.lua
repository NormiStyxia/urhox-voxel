-- R9: real-second input/locomotion coordination. CombatAnim alone owns dodge
-- metres and windows; this module owns only the following run displacement.
local F={};F.__index=F
F.State={LOCOMOTION='LOCOMOTION',HOLD_CHECK='HOLD_CHECK',DODGE='DODGE',
    SPRINT_ACCEL='SPRINT_ACCEL',SPRINT='SPRINT',RUN_EXIT='RUN_EXIT',WAIT_RELEASE='WAIT_RELEASE'}
F.HOLD=.24;F.HANDOFF=.30;F.ACCEL=.22;F.EXIT=.12;F.MAX_SPEED=7.2
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function smooth(u)return u*u*(3-2*u)end
-- Integral of smoothstep velocity, including the constant-speed tail.
---@param t number Real seconds, including time after the ramp.
---@param v0 number m/s
---@param v1 number m/s
---@param duration number Positive seconds
---@return number metres
function F.Distance(t,v0,v1,duration)
    t=math.max(0,t)
    local u=clamp(t/duration,0,1)
    return duration*(v0*u+(v1-v0)*(u^3-u^4*.5))+v1*math.max(0,t-duration)
end
function F.Speed(t,v0,v1,duration)return v0+(v1-v0)*smooth(clamp(t/duration,0,1))end
-- Select the closest rigid-leg pose, then the closest periodic branch. The
-- entry amplitude is 18 degrees; using the stable 34-degree phase would snap.
---@param right number Right hip pitch in degrees
---@param left number Left hip pitch in degrees
---@param previous number Previous cycle phase [0,1)
---@return number phase
function F.PhaseForLegs(right,left,previous)
    local k=28/34
    local positive=clamp((-right+k*left)/(18*(1+k*k)),0,1)
    local negative=clamp((-k*right+left)/(18*(1+k*k)),-1,0)
    local a=(-18*positive-right)^2+(18*k*positive-left)^2
    local b=(-18*k*negative-right)^2+(18*negative-left)^2
    local wave=a<b and positive or negative
    local first=math.acos(wave)/(2*math.pi)
    local second=1-first
    local da=math.abs((first-previous+.5)%1-.5)
    local db=math.abs((second-previous+.5)%1-.5)
    return (da<=db and first or second)%1
end
---@param ports table|nil Optional start/step callbacks allocated by the scene once.
---@return table locomotion
function F.New(ports)
    return setmetatable({ports=ports or {},state=F.State.LOCOMOTION,time=0,held=false,pending=false,
        speed=0,distance=0,weight=0,phase=math.acos(-18/34)/(2*math.pi),blockedAge=0,
        runAge=0,ownsFrame=false,stepSerial=0,previousStep=0,animOpts={params={}}},F)
end
function F:IsRunning()return self.state==F.State.SPRINT_ACCEL or self.state==F.State.SPRINT end
function F:Cancel(reason)
    self.state=F.State.WAIT_RELEASE;self.pending=false;self.pressAt=nil
    self.distance,self.speed,self.blockedAge=0,0,0;self.ownsFrame=false
    self.reason=reason;self.rejected=nil;self.weight=0
    if self.moves and self.moves.buffer=='dodge' then self.moves.buffer=nil end
end
function F:Accepted()
    self.state=F.State.DODGE;self.rejected=nil;self.reason=nil
    self.pressAt=self.pressAt or self.frameStart
    self.pending=self.held and self.moving and self.time-self.pressAt>=F.HOLD-1e-8
end
function F:Rejected(reason)
    self.rejected=reason
    if reason=='air' or reason=='unsafe' then self:Cancel(reason) end
end
function F:Start(speed,fromSlide)
    self.state=F.State.SPRINT_ACCEL;self.reason=nil;self.runAge=0;self.v0=clamp(speed or 0,0,F.MAX_SPEED)
    self.speed=self.v0;self.pending=false;self.blockedAge=0
    if fromSlide then
        self.weight=1 -- the old pose supplies the .04s crossfade
        local right,left=18,-18
        if self.ports.legAngles then right,left=self.ports.legAngles() end
        self.phase=F.PhaseForLegs(right,left,self.phase)
    end
    if self.ports.start then self.ports.start() end
end
function F:Exit(target)
    self.state=F.State.RUN_EXIT;self.runAge=0;self.v0=self.speed;self.exitSpeed=target or 0
    self.pending=false
end
-- c is a borrowed, stable frame record. Keyboard/touch/gamepad edges have
-- already been sampled separately; releasing one device does not release another.
---@param dt number Real, unscaled seconds
---@param c table Borrowed input record: evadePressed/evadeHeld/runIntent/allowed/axis/onGround
---@param moves table Action port: state/o/clip plus Cancel/EndSlide
function F:Begin(dt,c,moves)
    self.moves=moves
    self.frameStart=self.time;self.time=self.time+math.max(0,dt)
    self.distance,self.ownsFrame=0,false
    self.held=c.evadeHeld==true
    local axis=c.axis
    local length=axis and math.sqrt(axis.x*axis.x+axis.z*axis.z) or 0
    self.moving=length>=(self:IsRunning() and .12 or .18)
    self.axis=axis;self.normalSpeed=c.normalSpeed or 4.2
    local cancel=c.cancelled or not c.allowed or c.mounted or moves.dead
    if self.inputRevision~=nil and self.inputRevision~=c.inputRevision then cancel=true end
    self.inputRevision=c.inputRevision
    if self.combat~=nil and self.combat~=moves.state.InCombat() then cancel=true end
    self.combat=moves.state.InCombat()
    if cancel then
        self:Cancel('input-gate')
        if moves.clip and not moves.dead and moves.clip~='getup' and moves.clip~='knockdown' then moves:Cancel('input-gate') end
    end
    if self.state==F.State.WAIT_RELEASE then
        if not cancel and not self.held then self.state=F.State.LOCOMOTION end
        c.dodge=false;return
    end
    if c.jump or (c.onGround==false and (self:IsRunning() or self.state==F.State.DODGE or self.state==F.State.HOLD_CHECK or c.evadePressed)) then
        self:Cancel(c.jump and 'jump' or 'air');c.dodge=false;return
    end
    if c.evadePressed then
        self.pressAt=self.frameStart;self.rejected=nil
        self.state=F.State.HOLD_CHECK;c.dodge=true
    else c.dodge=false end
    if self.state==F.State.DODGE then
        self.pending=self.held and self.moving and self.time-self.pressAt>=F.HOLD-1e-8
    end
    if self:IsRunning() then
        if c.attackTap or c.heavyTap or (c.attack and not moves.lastAttack) or (c.heavy and not moves.lastHeavy) then
            self:Cancel('attack')
        elseif c.onGround==false then self:Cancel('air')
        elseif not self.moving or (not self.held and not c.runIntent) then
            self:Exit(self.moving and self.normalSpeed*math.min(1,length) or 0)
        else
            local observed=c.actualForwardSpeed
            self.blockedAge=observed and self.speed>1 and observed<self.speed*.2 and self.blockedAge+(c.motionSampleDt or dt) or 0
            if self.blockedAge>=.08 then self:Cancel('wall') end
        end
    end
    -- Phase follows physical displacement, not the desired speed or hitstop.
    local travel=math.max(0,c.travel or 0)
    if self:IsRunning() or self.state==F.State.RUN_EXIT then
        local old=self.phase
        self.phase=(self.phase+travel/(F.MAX_SPEED*.38))%1
        if math.floor((old+travel/(F.MAX_SPEED*.38))*2)>math.floor(old*2) then
            self.stepSerial=self.stepSerial+1
            if self.ports.step then self.ports.step() end
        end
    end
end
function F:Integrate(dt)
    if dt<=0 then return end
    if self:IsRunning() then
        self.distance=self.distance+F.Distance(self.runAge+dt,self.v0,F.MAX_SPEED,F.ACCEL)-F.Distance(self.runAge,self.v0,F.MAX_SPEED,F.ACCEL)
        self.runAge=self.runAge+dt;self.speed=F.Speed(self.runAge,self.v0,F.MAX_SPEED,F.ACCEL)
        if self.runAge>=F.ACCEL then self.state=F.State.SPRINT end
        self.ownsFrame=true
    elseif self.state==F.State.RUN_EXIT then
        self.distance=self.distance+F.Distance(self.runAge+dt,self.v0,self.exitSpeed,F.EXIT)-F.Distance(self.runAge,self.v0,self.exitSpeed,F.EXIT)
        self.runAge=self.runAge+dt;self.speed=F.Speed(self.runAge,self.v0,self.exitSpeed,F.EXIT)
        self.ownsFrame=true
        if self.runAge>=F.EXIT then self.state=F.State.LOCOMOTION;self.pressAt=nil end
    end
end
-- Called after action events: a .22 attack has priority over the .30 run handoff.
---@param dt number Real frame seconds
---@param slideDt number Frame time consumed before run handoff (including delayed acceptance)
---@param c table Same borrowed input record as Begin
---@param moves table Same action port as Begin
function F:Finish(dt,slideDt,c,moves)
    if moves.slidePathClipped and self.state==F.State.DODGE then self:Cancel('path-clipped') end
    local integrate=dt
    if self.state==F.State.DODGE then
        if moves.clip=='dodge_slide' and moves.slideElapsed>=F.HANDOFF-1e-8 and self.pending and self.held and self.moving then
            moves:EndSlide(true);self:Start(2,true)
            if self.ports.step then self.ports.step() end
            integrate=math.max(0,dt-slideDt)
        elseif moves.clip~='dodge_slide' then
            if moves.clip then self:Cancel('action') else
                self.pending=false;self.state=F.State.LOCOMOTION;self.pressAt=nil
            end
        else integrate=0 end
    elseif self.state==F.State.HOLD_CHECK then
        local after=self.pressAt and self.time-self.pressAt-F.HOLD or -1
        if self.held and self.moving and after>=-1e-8 and self.rejected=='cooldown' and not moves.clip and c.onGround~=false then
            local safe=not moves.o.slideStart or moves.o.slideStart()
            if safe then self:Start(c.actualSpeed or 0);integrate=math.min(dt,math.max(0,after)) else self:Cancel('unsafe') end
        elseif not self.held then self.state=F.State.LOCOMOTION;self.pressAt=nil end
    elseif self.state==F.State.LOCOMOTION and c.runIntent and self.moving and c.onGround~=false and not moves.clip then
        self:Start(c.actualSpeed or 0) -- touch outer-ring convenience, no dodge
    end
    self:Integrate(integrate)
    local wanted=self:IsRunning() and 1 or 0
    self.weight=self.weight+(wanted-self.weight)*(1-math.exp(-dt/(wanted==1 and .04 or .06)))
    if self.weight<1e-4 then self.weight=0 end
    moves.sprintWeight=self.weight
end
-- Four real sole corners per leg, extracted once from downward shoe quads.
-- The low heel and raised toe keep their actual heights; no invented knee IK.
function F:Soles(character,data,variant)
    self.character=character;self.soles={};self.groundDelta=nil
    local unit=data.unit;local origin=data.origin
    local wx=variant.widen and variant.widen.x or 1
    local wz=variant.widen and variant.widen.z or 1
    for _,name in ipairs({'leg_right','leg_left'}) do
        local pivot
        for _,bone in ipairs(data.bones) do if bone.name==name then pivot=bone.pivot;break end end
        local quads=data.quads[name]
        local low=math.huge
        for _,q in ipairs(quads) do if q[1]==4 then low=math.min(low,q[2]) end end
        for corner=1,4 do
            local sx=corner%2==1 and -1 or 1
            local sz=corner<=2 and -1 or 1
            local best,x,y,z=-math.huge,0,0,0
            for _,q in ipairs(quads) do
                if q[1]==4 and q[2]<=low+1 then
                    for ix=0,1 do for iz=0,1 do
                        local px,pz=q[3]+ix*q[5]+origin[1],q[4]+iz*q[6]+origin[3]
                        local score=sx*px+sz*pz
                        if score>best then best,x,y,z=score,px,q[2]+origin[2],pz end
                    end end
                end
            end
            self.soles[#self.soles+1]={bone=name,point=Vector3((x-pivot[1])*wx*unit,(y-pivot[2])*unit,(z-pivot[3])*wz*unit),world=Vector3.ZERO,ground=0}
        end
    end
end
function F:Ground(dt,ground,active,grounded)
    if not self.soles or not grounded then self.groundDelta=nil;return end
    self.groundTail=active and .06 or math.max(0,(self.groundTail or 0)-dt)
    if self.groundTail<=0 then self.groundDelta=nil;return end
    local root=self.character.bones.root
    local base=self.character.basePos.root.y -- already contains SLENDER lift
    local p=root.position
    local authored=p.y-base
    local scale=root.worldScale.y
    if math.abs(scale)<1e-6 then return end
    local required=authored
    for _,sole in ipairs(self.soles) do
        local world=self.character.bones[sole.bone]:LocalToWorld(sole.point)
        sole.world=world
        local y=ground(world)
        sole.ground=y
        if y then required=math.max(required,(y+.006-world.y)/scale+authored) end
    end
    -- Raising is immediate; only the lowering side is damped. Rebase every frame.
    local previous=self.groundDelta or authored
    local corrected=required>=previous and required or previous+(required-previous)*(1-math.exp(-dt/.04))
    self.groundDelta=corrected
    root.position=Vector3(p.x,base+corrected,p.z)
end
function F:Debug()
    return self.soles,self.groundDelta,self.phase,self.phase<.5 and 'right' or 'left'
end
return F
