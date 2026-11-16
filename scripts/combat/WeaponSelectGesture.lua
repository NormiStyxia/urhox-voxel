-- Selection owns input, not the simulation clock. The upper-arm overlay is
-- applied AFTER CombatAnim; shared palms and bone translations stay read-only.
local G={}; G.__index=G
local function inverse(q) return Quaternion(q.w,-q.x,-q.y,-q.z) end
local function unit(v)
    local n=math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z)
    if n<1e-7 then return Vector3(0,-1,0) end
    return Vector3(v.x/n,v.y/n,v.z/n)
end
local function align(from,to)
    local a,b=unit(from),unit(to)
    local dot=math.max(-1,math.min(1,a.x*b.x+a.y*b.y+a.z*b.z))
    if dot<-.999999 then
        local axis=(math.abs(a.x)<.8 and Vector3(0,a.z,-a.y) or Vector3(-a.z,0,a.x)):Normalized()
        return Quaternion(0,axis.x,axis.y,axis.z)
    end
    local x,y,z=a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x
    local w=1+dot
    local n=math.sqrt(w*w+x*x+y*y+z*z)
    return Quaternion(w/n,x/n,y/n,z/n)
end
function G.New(opts)
    local self=setmetatable({},G)
    self:init(opts)
    return self
end
function G:init(opts)
    self.o=opts
    self.active,self.committing,self.accepted,self.weight=false,false,false,0
    self.anchor={anchorX=.6,anchorY=.5}
    self.palm=assert(opts.character:HandSocket('right'),'weapon selection requires right palm')
    self.arm=assert(opts.character.bones.arm_right,'weapon selection requires right arm')
    self.elbow=opts.character.bones.forearm_right
    self.elbowPose=Quaternion(-18,0,0)
    -- Both supported skeletons use their real shoulder/elbow/palm geometry.
    self.grip=self.elbow and self.elbow.position+self.elbowPose*self.palm.position or self.palm.position
end
function G:IsOpen() return self.active end
function G:Open(touch)
    if self.active or self.o.wheel.IsBlocked() or not self.o.canOpen() or not self.o.moves:CanCancel() then return false end
    self.active,self.committing,self.accepted,self.weight=true,false,false,0
    self.touch=touch==true
    self.savedPose=self.o.rig.pose or self.o.state.GetPose()
    self.openWeapon=self.o.selection and self.o.selection() or self.o.state.GetWeapon()
    self.o.moves:Cancel('weapon-select')
    self.o.moves.suspended=true -- blocker takeover must not cancel the new pose/swap
    self.o.state.SetBusy(true)
    self.o.takeInput()
    self.o.rig:SetPose(self.openWeapon=='time' and 'hidden' or 'back')
    local opened=self.o.wheel.Open({weapon=self.openWeapon,items=self.o.items,touch=self.touch,
        anchorX=self.anchor.anchorX,anchorY=self.anchor.anchorY,
        onSelect=function(id)
            if not self.active or not self.o.canOpen() then return false end
            self.committing=true
            local ok,accepted
            if self.o.select then ok,accepted=pcall(self.o.select,id)
            else ok,accepted=pcall(self.o.moves.Swap,self.o.moves,id) end
            self.committing=false
            if not ok then error(accepted,0) end
            self.accepted=accepted==true and id~=self.openWeapon
            return accepted==true
        end,
        onClose=function(reason) self:Closed(reason) end})
    if not opened then self:Closed('open-rejected'); return false end
    return true
end
function G:Closed(reason)
    if not self.active then return end
    self.closing=true
    self.active=false
    if not self.accepted then self.o.rig:SetPose(self.forceClosing and self.o.state.GetPose() or self.savedPose or self.o.state.GetPose()) end
    self.o.state.SetBusy(self.o.moves.clip~=nil)
    self.o.releaseInput(reason)
    self.closing=false
end
function G:ForceClose(reason)
    self.weight=0 -- hard interruptions never cover hit/death/mount poses
    self.forceClosing=true
    self.o.wheel.ForceClose(reason or 'interrupted')
    self:Closed(reason) -- safe with either synchronous or deferred UI callbacks
    self.forceClosing=false
end
function G:Interrupt(reason)
    if self.committing then return end
    -- The wheel's own blocker emits touch-clear; those are not interruptions.
    if reason=='weapon-select' or reason=='blocked' or reason=='touch-clear' then return end
    self:ForceClose(reason)
end
function G:Confirm()
    if self.active then self.o.wheel.Confirm() end
end
function G:Apply(dt)
    if self.active then self.weight=math.min(1,self.weight+math.max(0,dt)/.18)
    else self.weight=math.max(0,self.weight-math.max(0,dt)/.12) end
    if self.weight<=0 then return end
    local w=self.weight*self.weight*(3-2*self.weight)
    local body=self.o.character.bones.body
    -- A slight forward reach leaves the palm beside the torso in rear view.
    local worldDir=self.o.root.worldRotation*Vector3(.80,.02,.60)
    local direction=inverse(body.worldRotation)*worldDir
    local pose=align(self.grip,direction)
    self.arm.rotation=self.arm.rotation:Slerp(pose,w)
    if self.elbow then self.elbow.rotation=self.elbow.rotation:Slerp(self.elbowPose,w) end
end
function G:Update(dt,camera)
    if self.active then
        local delta=self.palm.worldPosition-camera.node.worldPosition
        if delta:DotProduct(camera.node.worldDirection)<=0 then self:ForceClose('off-camera')
        else
            local point=camera:WorldToScreenPoint(self.palm.worldPosition)
            self.anchor.anchorX,self.anchor.anchorY=point.x,point.y
        end
    end
    -- Also advance the closing fade/release latch. UI owns edge clamping.
    self.o.wheel.Update(dt,self.anchor)
end
return G
