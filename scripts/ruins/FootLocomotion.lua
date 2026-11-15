-- Ordinary held-run pose coordination; the controller alone owns movement.
local F={};F.__index=F
F.MAX_SPEED=7.2
F.State={LOCOMOTION='LOCOMOTION',SPRINT='SPRINT'}
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
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
function F.New(ports)
    return setmetatable({ports=ports or {},state=F.State.LOCOMOTION,time=0,
        weight=0,phase=0,speed=0,animOpts={params={}}},F)
end
function F:IsRunning()return self.state==F.State.SPRINT end
function F:Cancel(reason)
    self.state=F.State.LOCOMOTION;self.reason=reason;self.weight=0;self.speed=0
end
-- Inputs are held intent, never a tap classifier. No distance or immunity here.
function F:Begin(dt,c,moves)
    self.time=self.time+math.max(0,dt)
    self.axis=c.axis
    self.moving=c.axis~=nil and c.axis:LengthSquared()>.01
    self.requested=c.runIntent==true and c.allowed==true and not c.cancelled and not c.mounted and not moves.dead
    if self.moving then self.direction=c.axis:Normalized() end
    self.speed=math.max(0,c.actualSpeed or 0)
    if self:IsRunning() and c.onGround~=false then
        local advance=math.max(0,c.travel or 0)/(F.MAX_SPEED*.38)
        if math.floor((self.phase+advance)*2)>math.floor(self.phase*2) and self.ports.step then self.ports.step() end
        self.phase=(self.phase+advance)%1
    end
end
function F:Finish(dt,c,moves)
    local running=self.requested and self.moving and c.onGround~=false and not moves.clip
    if running and not self:IsRunning() then
        if self.ports.legAngles then
            local right,left=self.ports.legAngles()
            self.phase=F.PhaseForLegs(right,left,self.phase)
        end
        if self.ports.start then self.ports.start() end
    end
    self.state=running and F.State.SPRINT or F.State.LOCOMOTION
    local wanted=running and clamp(self.speed/F.MAX_SPEED,0,1) or 0
    self.weight=self.weight+(wanted-self.weight)*(1-math.exp(-dt/.06))
    if moves.clip or self.weight<1e-4 then self.weight=0 end
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
