-- Node-bone overlay for BlockCharacter, never an AnimatedModel/FSM provider.
-- Recommended frame order:
--   meters = anim:GetMotion(dt)  -- advances clock ONCE; clip events available now
--   events = anim:Poll()        -- consume before moving/attacking
--   nomi:Update(dt, state); anim:Apply(); rig:SetSwing(anim:GetWeaponPose())
-- Alternatively Update(dt), then GetMotion() (read-only). Never use both dt calls.
-- Apply() alone can follow BlockCharacter.time, but its Update clamps dt to .1;
-- explicit advancement is required for exact gameplay timing and hitstop.
-- No Lua tables are created in Update/Apply/Poll/GetMotion/GetWeaponPose.
-- Quaternion Slerp returns engine userdata; that allocation belongs to the binding.
-- Poll's reusable result is valid until the next Poll; copy if retaining history.
local Data = require("combat.AnimClips")
local MAX_TRACKS, MAX_EVENTS = 32, 512
local EPS = 1e-10
local EMPTY = {}
-- Forearms follow their arm: the elbow bend is solved together with the shoulder.
local BONE_NAMES = {"body","arm_left","arm_right","head","leg_right","leg_left","forearm_right","forearm_left"}
local FOREARM_ARM = {forearm_right="arm_right",forearm_left="arm_left"}

---@class CombatAnimTrack
---@field clip CombatClip
---@field handle number
---@field live boolean
---@field stopping boolean
---@field t number
---@field age number
---@field realAge number
---@field previousT number
---@field speed number
---@field fadeIn number
---@field fadeOut number
---@field stopAge number
---@field stopWeight number
---@field weight number
---@field params table<string, number>
---@field nextEvent number
---@field complete boolean
---@field hitOpen boolean
---@field cancelOpen boolean
---@field protectOpen boolean
---@field mixLayer number|nil Optional blend layer.
---@field sample number
---@field motion number
---@field ik table<string, CombatIKResult>
---@field handWeight number Smoothed weaponInHand value for running arms.
---@class CombatArm
---@field shoulder Vector3
---@field grip Vector3
---@field length number
---@field elbow Vector3|nil Forearm pivot in shoulder space (two-segment arms only).
---@field hand Vector3|nil Palm relative to the forearm pivot.
---@class CombatIKResult
---@field target Vector3 Requested body-local grip point, BEFORE reach projection.
---@field clamped Vector3 Closest reachable point on the rigid arm sphere.
---@field actual Vector3 Grip after solving (before layer blend).
---@field applied Vector3 Grip after all layer blends, populated by Apply.
---@field rotation Quaternion
---@field requestedDistance number
---@field reachError number
---@field degenerate boolean
---@field enabled boolean
---@class CombatAnimEvent
---@field name string
---@field clip string
---@field handle number
---@field t number normalized clip time
---@class CombatAfterimage
---@field clip string
---@field handle number
---@field time number Real-clock capture time, seconds.
---@field age number
---@field alpha number
---@field position Vector3 Weapon pivot world position (same grip rest as WeaponRig).
---@field rotation Quaternion Weapon pivot world rotation.
---@field handPosition Vector3
---@field handRotation Quaternion
---@field offset Vector3 Local weapon offset.
---@field euler Vector3 Local weapon Euler degrees.
---@class CombatAnim
---@field character BlockCharacter
---@field node Node|nil
---@field tracks CombatAnimTrack[]
---@field ordered CombatAnimTrack[]
---@field queue CombatAnimEvent[]
---@field output CombatAnimEvent[]
---@field eventPool CombatAnimEvent[]
---@field queueCount number
---@field serial number
---@field motion number
---@field stats table<string, number>
---@field timeScale number
---@field quantize boolean
---@field fps number
---@field quantizeHz number
---@field lastBaseTime number
---@field advanced boolean
---@field target Quaternion
---@field weaponOffset Vector3
---@field weaponEuler Vector3
---@field handSocket Node|nil
---@field gripRotation Quaternion
---@field realTime number
---@field afterimagePool CombatAfterimage[]
---@field afterimages CombatAfterimage[]
---@field afterimageWrite number
---@field lastImageTime number
---@field lastImageClipTime number
---@field trailHandle number
---@field nextImageTime number
---@field observedTime number
---@field observedPosition Vector3
---@field observedRotation Quaternion
---@field observedOffset Vector3
---@field observedEuler Vector3
---@field arms table<string, CombatArm>
---@field bodyHeight number
---@field pathIK boolean
---@field bladeDirection Vector3
---@field bladeWeight number
---@field bladeSide string
---@field bladeMode string
---@field aimPitch number
local A = {}
A.__index = A
A.Layer = Data.Layer

local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function ease(name,x)
    if name=="smoothStep" then return x*x*(3-2*x) end
    if name=="inQuad" then return x*x end
    if name=="outQuad" then return 1-(1-x)*(1-x) end
    if name=="inOutQuad" then return x<.5 and 2*x*x or 1-(-2*x+2)^2/2 end
    if name=="inCubic" then return x*x*x end
    if name=="inOutCubic" then return x<.5 and 4*x*x*x or 1-(-2*x+2)^3/2 end
    if name=="outCubic" then return 1-(1-x)^3 end
    if name=="outExpo" then return x>=1 and 1 or 1-2^(-10*x) end
    if name=="outBack" then return 1+2.70158*(x-1)^3+1.70158*(x-1)^2 end
    return x
end

-- Interpolate Euler components before constructing a quaternion. Slerping
-- 0 -> 330 directly would turn -30 degrees, destroying the forward roll.
local function segment(track,t)
    if t<=track[1][1] then return track[1],track[1],0 end
    for i=2,#track do
        local b=track[i]
        if t<=b[1] then
            local a=track[i-1]
            return a,b,ease(b.ease or b[3],clamp((t-a[1])/(b[1]-a[1]),0,1))
        end
    end
    return track[#track],track[#track],0
end
local function vectorSample(track,t,field)
    local a,b,u=segment(track,t)
    local v,w=field and a[field] or a[2],field and b[field] or b[2]
    return v[1]+(w[1]-v[1])*u,v[2]+(w[2]-v[2])*u,v[3]+(w[3]-v[3])*u
end
local function scalarSample(track,t)
    local a,b,u=segment(track,t)
    return a[2]+(b[2]-a[2])*u
end
local function vec(t) return Vector3(t[1],t[2],t[3]) end
local function vectorLength(v) return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end
local function unit(v,fallback)
    local n=vectorLength(v)
    if n<1e-7 then return fallback end
    return Vector3(v.x/n,v.y/n,v.z/n)
end
-- Deterministic shortest rotation. Antiparallel rays choose a stable orthogonal
-- axis instead of dividing by zero. solveArm then aligns a secondary axis to
-- the path plane pole, avoiding swing-only twist flips across the back.
local function align(from,to)
    local a,b=unit(from,Vector3(0,-1,0)),unit(to,Vector3(0,-1,0))
    local dot=clamp(a.x*b.x+a.y*b.y+a.z*b.z,-1,1)
    if dot<-.999999 then
        local axis=math.abs(a.x)<.8 and Vector3(0,a.z,-a.y) or Vector3(-a.z,0,a.x)
        axis=unit(axis,Vector3(1,0,0))
        return Quaternion(0,axis.x,axis.y,axis.z)
    end
    local x,y,z=a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x
    local w=1+dot
    local n=math.sqrt(w*w+x*x+y*y+z*z)
    return Quaternion(w/n,x/n,y/n,z/n)
end
local function inverse(q) return Quaternion(q.w,-q.x,-q.y,-q.z) end
local function vectorCross(a,b) return Vector3(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x) end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function project(v,axis)
    local n=dot(v,axis)
    return Vector3(v.x-axis.x*n,v.y-axis.y*n,v.z-axis.z*n)
end
---@param elbow Vector3|nil Forearm pivot in the arm frame (two-segment rig).
---@param hand Vector3|nil Palm in the forearm frame.
local function makeArm(shoulder,grip,elbow,hand)
    return {shoulder=shoulder,grip=grip,length=vectorLength(grip),elbow=elbow,hand=hand}
end
-- Shoulder-frame grip after bending the forearm by `pitch` degrees about its
-- local X hinge (negative = flex, palm moves forward). Scalar math only.
local function bentGrip(arm,pitch)
    local e,h=arm.elbow,arm.hand
    local r=math.rad(pitch)
    local c,s=math.cos(r),math.sin(r)
    return e.x+h.x,e.y+h.y*c-h.z*s,e.z+h.y*s+h.z*c
end
local function ikBuffer()
    return {target=Vector3(0,0,0),clamped=Vector3(0,0,0),actual=Vector3(0,0,0),applied=Vector3(0,0,0),
        rotation=Quaternion(0,0,0),requestedDistance=0,reachError=0,degenerate=false,enabled=false,bend=0}
end
---@param arm CombatArm
---@param result CombatIKResult
---@param bend number|nil Authored minimum elbow flex (forearm pitch, degrees).
local function solveArm(arm,target,authored,result,pole,bend)
    local d=Vector3(target.x-arm.shoulder.x,target.y-arm.shoulder.y,target.z-arm.shoulder.z)
    local distance=vectorLength(d)
    local grip,length=arm.grip,arm.length
    bend=arm.elbow and (bend or 0) or 0
    if arm.elbow then
        local x,y,z=bentGrip(arm,bend)
        local reach=math.sqrt(x*x+y*y+z*z)
        if distance>1e-7 and distance<reach then
            -- Target inside the authored reach: flex further until the palm lands on it.
            local lo,hi=bend,-160
            for _=1,14 do
                local mid=(lo+hi)*.5
                x,y,z=bentGrip(arm,mid)
                if x*x+y*y+z*z>distance*distance then lo=mid else hi=mid end
            end
            bend=(lo+hi)*.5
            x,y,z=bentGrip(arm,bend)
        end
        grip=Vector3(x,y,z);length=vectorLength(grip)
    end
    local reference=authored*grip
    local degenerate=distance<1e-7 or length<1e-7
    local dir=unit(d,unit(reference,Vector3(0,-1,0)))
    local rotated=authored
    if not degenerate then
        -- A fixed plane pole removes the swing-only antipodal twist singularity.
        -- Horizontal cuts use +Y, vertical cuts / bow use +X. Project the pole
        -- onto the plane perpendicular to the aim ray. The elbow hinge rides
        -- with the shoulder, so the pole also decides which way the elbow points.
        local swing=align(grip,dir)
        local fromPole=unit(project(swing*Vector3(0,0,1),dir),unit(vectorCross(dir,Vector3(1,0,0)),Vector3(0,1,0)))
        local toPole=unit(project(pole or Vector3(0,1,0),dir),fromPole)
        local angle=math.atan(dot(dir,vectorCross(fromPole,toPole)),clamp(dot(fromPole,toPole),-1,1))*.5
        local sn=math.sin(angle)
        rotated=Quaternion(math.cos(angle),dir.x*sn,dir.y*sn,dir.z*sn)*swing
    end
    result.target=target
    result.clamped=Vector3(arm.shoulder.x+dir.x*length,arm.shoulder.y+dir.y*length,arm.shoulder.z+dir.z*length)
    result.actual=arm.shoulder+rotated*grip
    result.rotation=rotated
    result.requestedDistance,result.reachError,result.degenerate=distance,math.abs(distance-length),degenerate
    result.bend=bend
    result.enabled=true
    return rotated
end
---@param c table Clip; `elbow` holds forearm pitch tracks.
local function elbowBend(c,name,p)
    local track=c.elbow and c.elbow[name]
    return track and scalarSample(track,p) or 0
end
local function pathPoint(path,p)
    local list=path.segments
    local seg=list[#list]
    for _,candidate in ipairs(list) do if p<=candidate.t1 then seg=candidate;break end end
    local u=ease(seg.ease,clamp((p-seg.t0)/(seg.t1-seg.t0),0,1))
    if seg.kind=="arc" then
        local q=(seg.u0 or 0)+((seg.u1 or 1)-(seg.u0 or 0))*u
        local angle=seg.angle+seg.sweep*q
        local x,y=seg.cx+seg.radius*math.cos(angle),seg.cy+seg.radius*math.sin(angle)
        if seg.plane=="yz" then return Vector3(seg.a[1]+(seg.b[1]-seg.a[1])*q,x,y) end
        return Vector3(x,seg.a[2]+(seg.b[2]-seg.a[2])*q,y)
    end
    local a,b,c=seg.a,seg.b,seg.control
    local v=1-u
    return Vector3(v*v*a[1]+2*v*u*c[1]+u*u*b[1],v*v*a[2]+2*v*u*c[2]+u*u*b[2],v*v*a[3]+2*v*u*c[3]+u*u*b[3])
end
---@param arm CombatArm
local function handTarget(c,name,p,params,arm,bodyHeight,bodyRotation)
    local path=c.handPath[name]
    if path.mode=="plunge" then
        local u=math.max(clamp(((params.plungeSpeed or 1)-.5)*2,0,1),clamp(params.plungeTuck or 0,0,1))
        u=ease("smoothStep",u)
        return Vector3(.5-.02*u,1.6-.75*u-bodyHeight,.42+.20*u)
    end
    if path.mode=="bow_aim" or path.mode=="bow_string" then
        local aim=math.rad(clamp(params.aimPitch or 0,-35,35))
        local cp,sp=math.cos(aim),math.sin(aim)
        local charge=clamp(params.p or (c.param and p or 0),0,1)
        local x,y,z
        if path.mode=="bow_aim" then
            x,y,z=arm.shoulder.x,arm.shoulder.y,arm.length
        else
            -- At full draw, approach the right mouth corner in BODY coordinates.
            x=arm.shoulder.x+.06+charge*.02
            y=arm.shoulder.y+.02+charge*.10
            z=.32-charge*.17
            -- Release pulls back briefly, never punches the string forward.
            if c.id=="bow_release" then z=z-.03*math.sin(math.pi*clamp(p*c.dur/.08,0,1)) end
        end
        local dy=y-arm.shoulder.y
        local ray=Vector3(x-arm.shoulder.x,dy*cp-z*sp,dy*sp+z*cp)
        local localRay=bodyRotation and inverse(bodyRotation)*ray or ray
        -- The shoulder is body-local, but aim is in the controller facing frame.
        -- Remove actual torso lean (including full-charge tremor) exactly once.
        local relax=c.id=="bow_cancel" and ease("outQuad",p)
            or (c.id=="bow_release" and ease("outQuad",clamp((p*c.dur-.08)/(c.dur-.08),0,1)) or 0)
        return arm.shoulder+Vector3(localRay.x+(arm.grip.x-localRay.x)*relax,
            localRay.y+(arm.grip.y-localRay.y)*relax,localRay.z+(arm.grip.z-localRay.z)*relax)
    end
    local target=pathPoint(path,p)
    return Vector3(target.x,target.y-bodyHeight,target.z)
end
local function pathPole(path)
    if path.pole then return Vector3(path.pole[1],path.pole[2],path.pole[3]) end
    if path.mode or (path.segments and path.segments[2] and path.segments[2].plane=="yz") then return Vector3(1,0,0) end
    return Vector3(0,1,0)
end
---@param c CombatClip
local function boneSample(c,name,p,params,handWeight)
    if c.id=="plunge_loop" then
        local u=ease("smoothStep",math.max(clamp(((params.plungeSpeed or 1)-.5)*2,0,1),clamp(params.plungeTuck or 0,0,1)))
        local tuck=clamp(params.plungeTuck or 0,0,1)
        if name=="body" then return -4+34*u,0,0 end
        if name=="head" then return 3-13*u,0,0 end
        if name=="leg_right" then return 14+11*u*(1-tuck),0,0 end
        if name=="leg_left" then return -10-10*u*(1-tuck),0,0 end
    end
    if c.locomotion then
        local phase=(params.gaitPhase or 0)*math.pi*2
        local wave=math.cos(phase)
        local cross=math.sin(phase)^2
        local accel=clamp(params.sprintAccel or 1,0,1)
        local legs,arms=18+16*accel,18+6*accel
        local x,y,z=0,0,0
        if name=="body" then return 14+2*cross+4*(1-accel),-3*wave,0 end
        if name=="head" then return -10-2*cross-3*(1-accel),1.5*wave,0 end
        if name=="leg_right" then return -legs*wave*(wave<0 and 28/34 or 1),0,0 end
        if name=="leg_left" then return legs*wave*(wave>0 and 28/34 or 1),0,0 end
        local side=name=="arm_right" and 1 or -1
        x,z=side*arms*wave,side*(8+2*math.abs(wave))
        local held=handWeight or clamp(params.weaponInHand==nil and 1 or params.weaponInHand,0,1)
        local heldPitch=params.bow==1 and (side==1 and -20 or -58) or (side==1 and -40 or x*.7)
        return x+(heldPitch-x)*held,y,z
    end
    local tracks=(params.legacyPose==1 and c.legacyKeys) or c.keys
    return vectorSample(tracks[name],p)
end
---@param c CombatClip
local function normalized(c,t)
    if c.loop and t>c.dur then
        local start=(c.loopFrom or 0)*c.dur
        return (start+(t-c.dur)%(c.dur-start))/c.dur
    end
    return clamp(t/c.dur,0,1)
end
---@param s CombatAnimTrack
local function weight(s)
    if s.stopping then
        return s.fadeOut<=0 and 0 or s.stopWeight*clamp(1-s.stopAge/s.fadeOut,0,1)
    end
    local w=s.fadeIn<=0 and 1 or clamp(s.age/s.fadeIn,0,1)
    if s.clip.smoothBlend then w=ease("smoothStep",w) end
    if not s.clip.loop and not s.clip.hold and s.fadeOut>0 then
        -- fadeOut is wall/animation-clock seconds, not normalized time.
        local remaining=(s.clip.dur-s.t)/math.max(s.speed,EPS)
        local out=clamp(remaining/s.fadeOut,0,1)
        w=math.min(w,s.clip.smoothBlend and ease("smoothStep",out) or out)
    end
    if s.clip.locomotion then w=w*clamp(s.params.sprintWeight or 0,0,1) end
    return w
end
---@param s CombatAnimTrack
local function sampleTime(self,s)
    if s.clip.param then return clamp(s.params[s.clip.param] or 0,0,1) end
    local p=normalized(s.clip,s.t)
    if s.clip.continuous then return p end
    local seconds=p*s.clip.dur
    local active=s.clip.phases.active
    if self.quantize and not (active and seconds>=active[1] and seconds<=active[2] and active[2]>active[1]) then
        if p>=1 then return 1 end
        seconds=math.floor(seconds*self.quantizeHz+EPS)/self.quantizeHz
        -- Never step backwards when leaving the unquantized active interval.
        if active and seconds<active[2] and p*s.clip.dur>active[2] then seconds=active[2] end
    end
    return seconds/s.clip.dur
end

---@param character BlockCharacter
---@param node Node|nil
---@param opts table|nil {quantizeHz=20, stats={}, timeScale=1, handSocket=Node, leftHandSocket=Node, pathIK=true, bodyHeight=number}
---@return CombatAnim
function A.New(character,node,opts)
    local self=setmetatable({},A)
    self:init(character,node,opts or EMPTY)
    return self
end
---@param character BlockCharacter
---@param node Node|nil
---@param opts table
function A:init(character,node,opts)
    self.character,self.node=character,node
    self.bowRig=opts.bowRig
    self.tracks,self.ordered,self.queue,self.output,self.eventPool={},{},{},{},{}
    self.queueCount,self.serial,self.motion=0,0,0
    self.stats=opts.stats or EMPTY
    self.timeScale=opts.timeScale or 1
    local hz=opts.quantizeHz or opts.fps or 20
    assert(finite(hz) and hz>=0,"CombatAnim: quantizeHz must be finite and nonnegative")
    self.quantize=opts.quantize~=false and hz>0
    self.quantizeHz=math.max(1,hz)
    self.fps=self.quantizeHz -- legacy inspector alias
    self.lastBaseTime=character.time or 0
    self.advanced=false
    self.target=Quaternion(0,0,0)
    self.weaponOffset,self.weaponEuler=Vector3(0,0,0),Vector3(0,0,0)
    local arm=character.bones.arm_right
    local forearmR,forearmL=character.bones.forearm_right,character.bones.forearm_left
    -- Two-segment rigs own their palm on the forearm; ask the character, never guess.
    local function palm(side,bone,name)
        if character.HandSocket and character.bones["forearm_"..side] then return character:HandSocket(side) end
        return bone and bone:GetChild(name,false)
    end
    self.handSocket=opts.handSocket or palm("right",arm,"SpellPalm")
    self.gripRotation=opts.gripRotation or Quaternion(90,0,0)
    local reference=Data.RigReference
    local left=character.bones.arm_left
    local leftSocket=opts.leftHandSocket or palm("left",left,"hand_left")
    local body=character.bones.body
    local rootBase=character.basePos and character.basePos.root
    self.footBaseY=rootBase and rootBase.y or 0
    self.bodyHeight=opts.bodyHeight or (body and rootBase and body.position.y+rootBase.y) or reference.bodyHeight
    self.pathIK=opts.pathIK~=false
    local function build(shoulder,fallbackShoulder,socket,fallbackGrip,forearm)
        local s=shoulder and shoulder.position or vec(fallbackShoulder)
        if forearm and socket then
            -- Straight-elbow grip = forearm pivot + palm offset (forearm identity).
            local e,h=forearm.position,socket.position
            return makeArm(s,Vector3(e.x+h.x,e.y+h.y,e.z+h.z),Vector3(e.x,e.y,e.z),Vector3(h.x,h.y,h.z))
        end
        return makeArm(s,socket and socket.position or vec(fallbackGrip))
    end
    self.forearms={arm_right=forearmR,arm_left=forearmL}
    self.arms={
        arm_right=build(arm,reference.rightShoulder,self.handSocket,reference.rightGrip,forearmR),
        arm_left=build(left,reference.leftShoulder,leftSocket,reference.leftGrip,forearmL)}
    self.bladeDirection,self.bladeWeight,self.bladeSide,self.bladeMode,self.aimPitch=Vector3(0,1,0),0,"arm_right","radial",0
    self.realTime,self.afterimageWrite,self.trailHandle=0,0,0
    self.lastImageTime,self.lastImageClipTime=-math.huge,-math.huge
    self.nextImageTime,self.observedTime=0,0
    self.observedPosition=self.handSocket and self.handSocket.worldPosition or Vector3(0,0,0)
    self.observedRotation=self.handSocket and self.handSocket.worldRotation or Quaternion(0,0,0)
    self.observedOffset,self.observedEuler=Vector3(0,0,0),Vector3(0,0,0)
    self.afterimagePool,self.afterimages={},{}
    for i=1,2 do
        self.afterimagePool[i]={clip="",handle=0,time=-math.huge,age=0,alpha=0,
            position=Vector3(0,0,0),rotation=Quaternion(0,0,0),
            handPosition=Vector3(0,0,0),handRotation=Quaternion(0,0,0),
            offset=Vector3(0,0,0),euler=Vector3(0,0,0)}
    end
    for i=1,MAX_TRACKS do
        self.tracks[i]={clip=Data.Clips.stance_combat,handle=0,live=false,stopping=false,
            t=0,age=0,realAge=0,previousT=0,speed=1,fadeIn=.08,fadeOut=.08,stopAge=0,stopWeight=0,weight=0,
            params={},nextEvent=1,complete=false,hitOpen=false,cancelOpen=false,protectOpen=false,
            sample=0,motion=0,handWeight=1,
            ik={arm_right=ikBuffer(),arm_left=ikBuffer()}}
    end
    for i=1,MAX_EVENTS do
        self.queue[i]={name="",clip="",handle=0,t=0}
        self.eventPool[i]={name="",clip="",handle=0,t=0}
    end
end

---@param s CombatAnimTrack
---@param name string
---@param t number
function A:emit(s,name,t)
    assert(self.queueCount<MAX_EVENTS,"CombatAnim: Poll events before queue capacity is exhausted")
    self.queueCount=self.queueCount+1
    local e=self.queue[self.queueCount]
    e.name,e.clip,e.handle,e.t=name,s.clip.id,s.handle,t
    if name=="hit_on" then s.hitOpen=true elseif name=="hit_off" then s.hitOpen=false end
    if name=="cancel_open" then s.cancelOpen=true elseif name=="cancel_close" then s.cancelOpen=false end
    if name=="protect_on" then s.protectOpen=true elseif name=="protect_off" then s.protectOpen=false end
end

---@param clipId string
---@param opts table|nil {speed=1, stats=..., fadeIn=.08, fadeOut=.08, params={p=0}}
---weaponInHand is a [0,1] run-arm blend; default 1.
---@return number|nil handle Numeric generation id; stale handles never stop a replacement.
---@return string|nil reason
function A:Play(clipId,opts)
    local c=Data.Clips[clipId]
    if not c then return nil,"unknown_clip" end
    opts=opts or EMPTY
    local speed=c.realTime and 1 or (opts.speed or 1)
    local stats=opts.stats or self.stats
    if c.speedStat then speed=speed*(stats[c.speedStat] or 1) end
    if not finite(speed) or speed<0 then return nil,"invalid_speed" end
    local fadeIn,fadeOut=opts.fadeIn or c.fadeIn or .08,opts.fadeOut or c.fadeOut or .08
    if not finite(fadeIn) or not finite(fadeOut) or fadeIn<0 or fadeOut<0 then return nil,"invalid_fade" end
    for _,s in ipairs(self.ordered) do
        if s.live and not s.stopping and (not s.complete or s.clip.hold) and s.clip.layer>c.layer
            and c.layer~=Data.Layer.STANCE and not c.locomotion then
            return nil,"higher_priority"
        end
    end
    ---@type CombatAnimTrack|nil
    local slot=nil
    for _,s in ipairs(self.tracks) do if not s.live then slot=s;break end end
    if not slot then return nil,"track_capacity" end
    -- Remove dead references before reusing a slot; ordered retains blend order.
    for i=#self.ordered,1,-1 do if not self.ordered[i].live then table.remove(self.ordered,i) end end
    for _,s in ipairs(self.ordered) do
        if s.live and not s.stopping and s.clip.layer<=c.layer and s.clip.layer~=Data.Layer.STANCE then
            self:Stop(s.handle,fadeIn)
        elseif s.live and s.clip.layer==c.layer and not s.stopping then self:Stop(s.handle,fadeIn) end
    end
    self.serial=self.serial+1
    slot.handle,slot.clip,slot.live,slot.stopping=self.serial,c,true,false
    slot.t,slot.age,slot.realAge,slot.stopAge,slot.stopWeight,slot.sample,slot.motion=0,0,0,0,0,0,0
    slot.previousT=0
    slot.mixLayer=nil
    slot.ik.arm_right.enabled,slot.ik.arm_left.enabled=false,false
    slot.speed,slot.fadeIn,slot.fadeOut=speed,fadeIn,fadeOut
    slot.nextEvent,slot.complete=1,false
    slot.hitOpen,slot.cancelOpen,slot.protectOpen=false,false,false
    for name in pairs(slot.params) do slot.params[name]=nil end
    for name,value in pairs(opts.params or EMPTY) do if finite(value) then slot.params[name]=value end end
    slot.handWeight=clamp(slot.params.weaponInHand==nil and 1 or slot.params.weaponInHand,0,1)
    slot.weight=weight(slot)
    local at=#self.ordered+1
    for i,s in ipairs(self.ordered) do if s.clip.layer>c.layer then at=i;break end end
    table.insert(self.ordered,at,slot)
    if c.realTime then
        -- Real-time clips emit their zero-time events immediately, without waiting
        -- for Update; t=0 events are consumed by the same monotonic cursor.
        while slot.nextEvent<=#c.events and c.events[slot.nextEvent].t==0 do
            self:emit(slot,c.events[slot.nextEvent][1],0)
            slot.nextEvent=slot.nextEvent+1
        end
    end
    return slot.handle
end

---@param name string
---@param value number
function A:SetParam(name,value)
    if not finite(value) then return end
    for _,s in ipairs(self.ordered) do
        if s.live and not s.stopping then
            s.params[name]=value
            if s.clip.locomotion then s.weight=weight(s) end
        end
    end
end

---@param handle number|nil nil stops all tracks, including stance/death.
---@param fadeOut number|nil
function A:Stop(handle,fadeOut)
    for _,s in ipairs(self.ordered) do
        if s.live and (not handle or s.handle==handle) and not s.stopping then
            -- Suppress unconsumed offensive/opening events. Keep close events so
            -- an already consumed hit_on cannot remain stuck open.
            local n=0
            for i=1,self.queueCount do
                local e=self.queue[i]
                if e.handle~=s.handle or e.name=="hit_off" or e.name=="cancel_close"
                    or e.name=="protect_off" then
                    n=n+1
                    if n~=i then
                        local dst=self.queue[n]
                        dst.name,dst.clip,dst.handle,dst.t=e.name,e.clip,e.handle,e.t
                    end
                end
            end
            self.queueCount=n
            if s.hitOpen then self:emit(s,"hit_off",normalized(s.clip,s.t)) end
            if s.cancelOpen then self:emit(s,"cancel_close",normalized(s.clip,s.t)) end
            if s.protectOpen then self:emit(s,"protect_off",s.realAge/s.clip.dur) end
            for _,snapshot in ipairs(self.afterimagePool) do
                if snapshot.handle==s.handle then snapshot.time=-math.huge end
            end
            self:emit(s,"clip_cancelled",normalized(s.clip,s.t))
            s.stopWeight,s.stopAge,s.stopping=s.weight,0,true
            s.fadeOut=finite(fadeOut) and math.max(0,fadeOut) or .08
            s.motion=0
            if s.fadeOut==0 then s.weight,s.live=0,false end
        end
    end
    self.motion=0
end

---Pose dt may be frozen; realDt keeps protection/afterimage expiry on wall time.
---With timeScale=0, dt itself still advances the real clock. If passing dt=0
---for hitstop, explicitly supply realDt. Real-clock events ignore weapon speed.
---@param dt number
---@param realDt number|nil Defaults to unscaled dt.
function A:Update(dt,realDt)
    assert(finite(dt) and dt>=0,"CombatAnim: dt must be finite and nonnegative")
    realDt=realDt or dt
    assert(finite(realDt) and realDt>=0,"CombatAnim: realDt must be finite and nonnegative")
    assert(finite(self.timeScale) and self.timeScale>=0,"CombatAnim: invalid timeScale")
    self.realTime=self.realTime+realDt
    dt=dt*self.timeScale
    self.advanced=true
    self.motion=0
    for _,s in ipairs(self.ordered) do
        s.motion=0
        if s.live then
            s.realAge=s.realAge+realDt
            local step=s.clip.realTime and realDt or dt
            if s.stopping then
                s.stopAge=s.stopAge+step
                s.weight=weight(s)
                if s.weight<=0 then s.live=false end
            else
                if s.clip.locomotion then
                    local held=clamp(s.params.weaponInHand==nil and 1 or s.params.weaponInHand,0,1)
                    s.handWeight=s.handWeight+(held-s.handWeight)*(1-math.exp(-realDt/.05))
                end
                local previous=s.t
                s.previousT=previous
                s.t=s.t+step*s.speed
                s.age=s.age+step
                local c=s.clip
                while s.nextEvent<=#c.events do
                    local event=c.events[s.nextEvent]
                    local value=event.param and (s.params[event.param] or 0)
                        or (event.clock=="real" and s.realAge or s.t)/c.dur
                    if value+EPS<event.t then break end
                    if event.t>1 and s.t+EPS>=c.dur and not c.loop and not c.param and not s.complete then
                        self:emit(s,"clip_finished",1)
                        s.complete=true
                    end
                    self:emit(s,event[1],event.t)
                    s.nextEvent=s.nextEvent+1
                end
                -- Exact integrated displacement: independent of dt, quantization
                -- and visual fade weight. Never directly write the physics Node.
                -- Half outQuad: burst on the step, then glide to a stop (inertia).
                for _,m in ipairs(c.motion) do
                    local span=m.t1-m.t0
                    local u0=clamp((math.max(previous,m.t0)-m.t0)/span,0,1)
                    local u1=clamp((math.min(s.t,m.t1)-m.t0)/span,0,1)
                    if u1>u0 then s.motion=s.motion+m.forward*(u1*(1.5-.5*u1)-u0*(1.5-.5*u0)) end
                end
                self.motion=self.motion+s.motion
                s.sample=sampleTime(self,s)
                s.weight=weight(s)
                if s.t+EPS>=c.dur and not c.loop and not c.param then
                    if not s.complete then self:emit(s,"clip_finished",1);s.complete=true end
                    if not c.hold then
                        -- Keep a nonblocking, zero-weight event tail until protection
                        -- expires .15s after the nominal getup duration.
                        s.weight=0
                        if s.nextEvent>#c.events then s.live=false end
                    end
                end
            end
        end
    end
end

---Read event queue once. No callbacks/reentrant changes during evaluation.
---@return CombatAnimEvent[]
function A:Poll()
    for i=#self.output,1,-1 do self.output[i]=nil end
    for i=1,self.queueCount do
        local src,dst=self.queue[i],self.eventPool[i]
        dst.name,dst.clip,dst.handle,dst.t=src.name,src.clip,src.handle,src.t
        self.output[i]=dst
    end
    self.queueCount=0
    return self.output
end

---@param dt number|nil Supplying dt advances once; omitting it only reads.
---@param realDt number|nil
---@return number forwardMeters
---Distance is integrated over every overlapping motion interval, not velocity.
---Stop drops the pending/current cached motion and all future intervals; callers
---keep displacement already applied. Split a frame at .22s if an attack was
---buffered there and exact 1.92m cancellation is required; no retroactive rewind.
function A:GetMotion(dt,realDt)
    if dt~=nil then self:Update(dt,realDt) end
    return self.motion
end

---Apply AFTER the base pose has been freshly written by BlockCharacter.Update.
---Do not call twice without rewriting that base pose (especially additive stance).
function A:Apply()
    local baseTime=self.character.time or 0
    if not self.advanced then self:Update(math.max(0,baseTime-self.lastBaseTime)) end
    self.lastBaseTime,self.advanced=baseTime,false
    local root=self.character.bones.root
    local baseY=root and root.position.y or 0
    local rootDelta=0
    local ox,oy,oz,ex,ey,ez=0,0,0,0,0,0
    self.bladeWeight=0
    for _,s in ipairs(self.ordered) do
        if s.live and not s.stopping then s.sample=sampleTime(self,s) end
        if s.live and s.weight>0 and (s.clip.finalDirectional or s.clip.locomotion) then baseY=self.footBaseY end
    end
    -- Normalize competing tracks WITHIN each layer, then cover lower layers.
    -- Sequential old*.5 then new*.5 would leak 25% of the base at mid-crossfade.
    for layer=Data.Layer.STANCE,Data.Layer.DEATH do
        for _,name in ipairs(BONE_NAMES) do
            local bone=self.character.bones[name]
            -- Attack clips describe the upper-body strike. Keep the locomotion
            -- layer's leg phases underneath it so a swing does not freeze both
            -- feet into authored kick angles.
            local keepLocomotionLegs=layer==Data.Layer.ATTACK
                and (name=="leg_right" or name=="leg_left")
            if bone and not keepLocomotionLegs then
                local base=bone.rotation
                local mixed=base
                local total=0
                local armName=FOREARM_ARM[name]
                for _,s in ipairs(self.ordered) do
                    local c=s.clip
                    if armName then
                        -- Elbow flex: solved together with this layer's arm IK, else authored.
                        local solved=s.ik[armName]
                        local ik=solved and solved.enabled and c.handPath and c.handPath[armName]
                        local authored=c.elbow and c.elbow[armName]
                        if s.live and s.weight>0 and (s.mixLayer or c.layer)==layer and (ik or authored) then
                            local bend=ik and solved.bend or elbowBend(c,armName,s.sample)
                            self.target:FromEulerAngles(bend,0,0)
                            total=total+s.weight
                            mixed=mixed:Slerp(self.target,s.weight/total)
                        end
                    end
                    local track=not armName and ((s.params.legacyPose==1 and c.legacyKeys) or c.keys)[name]
                    if s.live and s.weight>0 and (s.mixLayer or c.layer)==layer and track then
                        local x,y,z=boneSample(c,name,s.sample,s.params,s.handWeight)
                        if c.param=="p" and s.sample>.8 and name=="body" then
                            x=x+math.sin(s.t*48)*.4
                        end
                        self.target:FromEulerAngles(x,y,z)
                        local target=c.additive and base*self.target or self.target
                        if c.layer==Data.Layer.ATTACK and c.weaponType=="sword"
                            and name=="body" and c.keys.body then
                            -- Attack body keys are authored from the combat
                            -- stance. Apply only their delta over the current
                            -- locomotion/base torso pose, preserving gait lean
                            -- while letting the torso lead the shoulder turn.
                            local first=c.keys.body[1]
                            local authoredStart=Quaternion(first[2][1],first[2][2],first[2][3])
                            target=base*(inverse(authoredStart)*self.target)
                        end
                        if c.aimFacing and name=="head" and s.params.legacyPose~=1 then
                            target=inverse(self.character.bones.body.rotation)*Quaternion(clamp(s.params.aimPitch or 0,-35,35)+4,0,0)
                        end
                        local path=c.handPath and c.handPath[name]
                        if path and self.pathIK and s.params.legacyPose~=1 then
                            local arm=self.arms[name]
                            local point=handTarget(c,name,s.sample,s.params,arm,self.bodyHeight,self.character.bones.body.rotation)
                            if self.bowRig and (path.mode=='bow_aim' or path.mode=='bow_string') then
                                local bodyRotation=self.character.bones.body.rotation
                                local bowRotation=inverse(bodyRotation)*Quaternion(clamp(s.params.aimPitch or 0,-35,35),0,0)
                                local u=clamp(s.params.p or 0,0,1)
                                if path.mode=='bow_aim' and c.id~='bow_cancel' and c.id~='bow_release' then
                                    -- Couple the two rigid arms: choose left grip on the
                                    -- intersection of shoulder reach spheres so the right
                                    -- hand can meet the real nock without scaling either arm.
                                    local right=self.arms.arm_right
                                    local offset=bowRotation*self.bowRig:GetBowNockLocal(u)
                                    local delta=right.shoulder-offset-arm.shoulder
                                    local d=vectorLength(delta)
                                    if d>EPS and d<arm.length+right.length and d>math.abs(arm.length-right.length) then
                                        local axis=delta*(1/d)
                                        local along=(arm.length^2-right.length^2+d*d)/(2*d)
                                        local center=arm.shoulder+axis*along
                                        local radial=point-center
                                        radial=radial-axis*dot(radial,axis)
                                        point=center+unit(radial,Vector3(0,0,1))*math.sqrt(math.max(0,arm.length^2-along^2))
                                    end
                                elseif path.mode=='bow_string' and c.id~='bow_cancel' then
                                    local left=self.arms.arm_left
                                    local grip=left.shoulder+self.character.bones.arm_left.rotation*left.grip
                                    point=self.bowRig:GetBowNock(u,grip,bowRotation)
                                    if c.id=='bow_release' then
                                        point=point+bowRotation*Vector3(0,0,-.03*math.sin(math.pi*clamp(s.sample*c.dur/.08,0,1)))
                                    end
                                end
                            end
                            target=solveArm(arm,point,target,s.ik[name],pathPole(path),elbowBend(c,name,s.sample))
                        elseif s.ik[name] then s.ik[name].enabled=false end
                        total=total+s.weight
                        mixed=mixed:Slerp(target,s.weight/total)
                    end
                end
                if total>0 then bone.rotation=base:Slerp(mixed,math.min(total,1)) end
            end
        end
        local total,ry,lx,ly,lz,lp,lyaw,lr=0,0,0,0,0,0,0,0
        local bladeTotal,bx,by,bz=0,0,0,0
        for _,s in ipairs(self.ordered) do
            local c,w=s.clip,s.weight
            if s.live and w>0 and (s.mixLayer or c.layer)==layer then
                total=total+w
                -- Root translation remains continuous even when local rotations step.
                local rootP=c.param and s.sample or normalized(c,s.t)
                ry=ry+scalarSample(c.root,rootP)*w
                local x,y,z=vectorSample(c.weapon,s.sample,"offset")
                lx,ly,lz=lx+x*w,ly+y*w,lz+z*w
                x,y,z=vectorSample(c.weapon,s.sample,"euler")
                lp,lyaw,lr=lp+x*w,lyaw+y*w,lr+z*w
                if c.bladePath and self.pathIK and s.params.legacyPose~=1 then
                    local side=c.bladePath.side
                    local solved=s.ik[side]
                    if solved.enabled then
                        local direction
                        if c.bladePath.mode=="bow_upright" then
                            local aim=math.rad(clamp(s.params.aimPitch or 0,-35,35))
                            direction=Vector3(0,math.cos(aim),math.sin(aim))
                            self.aimPitch=clamp(s.params.aimPitch or 0,-35,35)
                        elseif c.bladePath.mode=="fixed" then
                            local d=c.bladePath.direction
                            direction=unit(Vector3(d[1],d[2],d[3]),Vector3(0,-1,0))
                            if c.id=="plunge_loop" then
                                local u=ease("smoothStep",math.max(clamp(((s.params.plungeSpeed or 1)-.5)*2,0,1),clamp(s.params.plungeTuck or 0,0,1)))
                                direction=unit(Vector3(.4*(1-u),math.cos(math.pi*u),.25+.05*(1-u)+.6*math.sin(math.pi*u)),Vector3(0,-1,0))
                            end
                        else
                            local origin=c.bladePath.origin
                            direction=unit(Vector3(solved.target.x-origin[1],solved.target.y+self.bodyHeight-origin[2],
                                solved.target.z-origin[3]),Vector3(0,1,0))
                            -- Follow-through: after the cut the wrist rolls the blade
                            -- down along the swing instead of pointing it at the sky.
                            local settle=c.bladePath.settle
                            if settle and s.sample>settle[1] then
                                local u=ease("inOutCubic",clamp((s.sample-settle[1])/(settle[2]-settle[1]),0,1))
                                local d=settle[3]
                                -- Mid-blend the tip swings out front, so a cut that ends
                                -- on the left side never drags the blade through the body.
                                local out=math.sin(math.pi*u)*(settle[4] or 0)
                                direction=unit(Vector3(direction.x+(d[1]-direction.x)*u,direction.y+(d[2]-direction.y)*u,
                                    direction.z+(d[3]-direction.z)*u+out),direction)
                            end
                        end
                        bladeTotal=bladeTotal+w
                        bx,by,bz=bx+direction.x*w,by+direction.y*w,bz+direction.z*w
                        self.bladeSide,self.bladeMode=side,c.bladePath.mode
                    end
                end
            end
        end
        if total>0 then
            local w=math.min(total,1)
            rootDelta=rootDelta+(ry/total-rootDelta)*w
            ox,oy,oz=ox+(lx/total-ox)*w,oy+(ly/total-oy)*w,oz+(lz/total-oz)*w
            ex,ey,ez=ex+(lp/total-ex)*w,ey+(lyaw/total-ey)*w,ez+(lr/total-ez)*w
            self.bladeWeight=self.bladeWeight*(1-w)+math.min(bladeTotal,1)
            if bladeTotal>0 then self.bladeDirection=unit(Vector3(bx,by,bz),Vector3(0,1,0)) end
        end
    end
    if self.bladeWeight>0 then
        local arm=self.character.bones[self.bladeSide]
        local desired=self.bladeMode=="bow_upright" and inverse(self.character.bones.body.rotation)*Quaternion(self.aimPitch,0,0)
            or (self.bladeMode=="fixed" and inverse(self.character.bones.body.rotation)*align(Vector3(0,1,0),self.bladeDirection)
                or align(Vector3(0,1,0),self.bladeDirection))
        -- Rig composes arm * gripRest * swing. Cancel current arm orientation
        -- only inside swing, keeping the desired blade/bow direction in body space.
        local forearm=self.forearms[self.bladeSide]
        local limb=forearm and arm.rotation*forearm.rotation or arm.rotation
        local extra=inverse(self.gripRotation)*inverse(limb)*desired
        self.target:FromEulerAngles(ex,ey,ez)
        local result=self.target:Slerp(extra,math.min(1,self.bladeWeight)):EulerAngles()
        ex,ey,ez=result.x,result.y,result.z
    end
    if root then local pos=root.position;root.position=Vector3(pos.x,baseY+rootDelta,pos.z) end
    self.weaponOffset,self.weaponEuler=Vector3(ox,oy,oz),Vector3(ex,ey,ez)
    for _,s in ipairs(self.ordered) do
        if s.live then
            for name,solved in pairs(s.ik) do
                if solved.enabled then
                    local arm=self.arms[name]
                    local forearm=self.forearms[name]
                    local q=self.character.bones[name].rotation
                    solved.applied=forearm and arm.shoulder+q*(arm.elbow+forearm.rotation*arm.hand)
                        or arm.shoulder+q*arm.grip
                end
            end
        end
    end
    self:captureAfterimage()
end

local function blendVector(a,b,t)
    return Vector3(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t,a.z+(b.z-a.z)*t)
end

---Fixed .04s real-clock samples, interpolated between observed rendered poses.
---The bounded two-slot ring skips stale samples after a hitch; never allocates tables.
function A:captureAfterimage()
    local socket=self.handSocket
    if not socket then return end
    local now=self.realTime
    local frameDuration=now-self.observedTime
    for i=#self.ordered,1,-1 do
        ---@type CombatAnimTrack
        local s=self.ordered[i]
        local interval=s.clip.trail
        local progress=s.t-s.previousT
        if s.live and not s.stopping and interval and progress>EPS and frameDuration>EPS
            and s.t+EPS>=interval[1] and s.previousT<=interval[2]+EPS then
            local startTime=self.observedTime+clamp((interval[1]-s.previousT)/progress,0,1)*frameDuration
            local endTime=self.observedTime+clamp((interval[2]-s.previousT)/progress,0,1)*frameDuration
            if self.trailHandle~=s.handle then
                self.trailHandle=s.handle
                self.nextImageTime=math.max(startTime,self.lastImageTime+.04)
            end
            -- At most the newest two deadlines can still be returned; no long loop.
            local overdue=math.floor((endTime-self.nextImageTime+EPS)/.04)
            if overdue>1 then self.nextImageTime=self.nextImageTime+(overdue-1)*.04 end
            for _=1,2 do
                local at=self.nextImageTime
                if at>endTime+EPS then break end
                self.nextImageTime=at+.04
                if at>=startTime-EPS and now-at<.10-EPS then
                    local u=clamp((at-self.observedTime)/frameDuration,0,1)
                    self.afterimageWrite=self.afterimageWrite%2+1
                    local shot=self.afterimagePool[self.afterimageWrite]
                    shot.clip,shot.handle,shot.time=s.clip.id,s.handle,at
                    shot.age,shot.alpha=now-at,1-(now-at)/.10
                    shot.handPosition=blendVector(self.observedPosition,socket.worldPosition,u)
                    shot.handRotation=self.observedRotation:Slerp(socket.worldRotation,u)
                    shot.offset=blendVector(self.observedOffset,self.weaponOffset,u)
                    shot.euler=blendVector(self.observedEuler,self.weaponEuler,u)
                    shot.position=shot.handPosition+shot.handRotation*shot.offset
                    self.target:FromEulerAngles(shot.euler.x,shot.euler.y,shot.euler.z)
                    shot.rotation=shot.handRotation*self.gripRotation*self.target
                    self.lastImageTime,self.lastImageClipTime=at,s.t
                end
            end
            break
        end
    end
    self.observedTime=now
    self.observedPosition,self.observedRotation=socket.worldPosition,socket.worldRotation
    self.observedOffset,self.observedEuler=self.weaponOffset,self.weaponEuler
end

---Newest first. Reusable snapshots/array; valid until the next Apply/GetAfterimages.
---Call anim:GetAfterimages() or A.GetAfterimages(anim); no global character singleton.
---@return CombatAfterimage[]
function A:GetAfterimages()
    self.afterimages[1],self.afterimages[2]=nil,nil
    local n=0
    for i=0,1 do
        local index=(self.afterimageWrite-i-1)%2+1
        local shot=self.afterimagePool[index]
        local age=self.realTime-shot.time
        if age>=0 and age<.10-EPS then
            n=n+1
            shot.age,shot.alpha=age,1-age/.10
            self.afterimages[n]=shot
        end
    end
    return self.afterimages
end

---@return Vector3 offset
---@return Vector3 euler
function A:GetWeaponPose() return self.weaponOffset,self.weaponEuler end

---Reusable IK diagnostics in body-node local space. No allocation; read after Apply.
---@param clipId string|nil
---@return table<string, CombatIKResult>|nil
function A:GetIKDebug(clipId)
    for i=#self.ordered,1,-1 do
        ---@type CombatAnimTrack
        local s=self.ordered[i]
        if s.live and (not clipId or s.clip.id==clipId) and s.clip.handPath then return s.ik end
    end
    return nil
end

---@param clipId string|nil
---@return boolean
function A:IsPlaying(clipId)
    for _,s in ipairs(self.ordered) do
        if s.live and not s.stopping and (not s.complete or s.clip.hold) and (not clipId or s.clip.id==clipId) then return true end
    end
    return false
end
---@param clipId string|nil
---@return string|nil
function A:Phase(clipId)
    for i=#self.ordered,1,-1 do
        ---@type CombatAnimTrack
        local s=self.ordered[i]
        if s.live and not s.stopping and (not s.complete or s.clip.hold) and (not clipId or s.clip.id==clipId) then
            local t=normalized(s.clip,s.t)*s.clip.dur
            local ph=s.clip.phases
            if t<ph.anticipation[2] then return "anticipation" end
            if t<ph.active[2] then return "active" end
            return "recovery"
        end
    end
    return nil
end

---Debug functions allocate intentionally; do not use in the gameplay hot path.
---@return table[]
function A.DebugList()
    local result={}
    for _,id in ipairs(Data.Order) do
        local c=Data.Clips[id]
        result[#result+1]={id=id,dur=c.dur,layer=c.layer,weaponType=c.weaponType,sourceWeapon=c.sourceWeapon,
            deprecated=c.deprecated==true,replacement=c.replacement}
    end
    return result
end
---@param clipId string
---@param t number Seconds; bow_hold uses t as p in [0,1]. No quantization or tremor.
---@param params table|nil Directional preview: {moveX,moveZ,bow=1}; default rear/sword.
---@return table|nil Bone Euler arrays plus _ik per-arm requested/clamped/actual points.
function A.DebugSample(clipId,t,params)
    local c=Data.Clips[clipId]
    if not c then return nil end
    local result={}
    params=params or EMPTY
    local p=c.param and clamp(t,0,1) or normalized(c,math.max(0,t))
    for name in pairs((params.legacyPose==1 and c.legacyKeys) or c.keys) do
        local x,y,z=boneSample(c,name,p,params)
        result[name]={x,y,z}
    end
    local bodyRotation=Quaternion(table.unpack(result.body))
    if c.aimFacing and params.legacyPose~=1 then
        local head=(inverse(bodyRotation)*Quaternion(clamp(params.aimPitch or 0,-35,35)+4,0,0)):EulerAngles()
        result.head={head.x,head.y,head.z}
    end
    if c.handPath and params.legacyPose~=1 then
        result._ik={}
        result._bodyHeight=Data.RigReference.bodyHeight
        for name in pairs(c.handPath) do
            local ref=Data.RigReference
            local right=name=="arm_right"
            local arm=makeArm(vec(right and ref.rightShoulder or ref.leftShoulder),vec(right and ref.rightGrip or ref.leftGrip))
            local buffer=ikBuffer()
            local x,y,z=boneSample(c,name,p,params)
            local target=handTarget(c,name,p,params,arm,ref.bodyHeight,bodyRotation)
            local solved=solveArm(arm,target,Quaternion(x,y,z),buffer,pathPole(c.handPath[name]))
            local angle=solved:EulerAngles()
            result[name]={angle.x,angle.y,angle.z}
            result._ik[name]={target={target.x,target.y,target.z},clamped={buffer.clamped.x,buffer.clamped.y,buffer.clamped.z},
                actual={buffer.actual.x,buffer.actual.y,buffer.actual.z},shoulder={arm.shoulder.x,arm.shoulder.y,arm.shoulder.z},
                length=arm.length,reachError=buffer.reachError,degenerate=buffer.degenerate,
                authored={target.x,target.y+ref.bodyHeight,target.z}}
        end
    end
    return result
end
return A
