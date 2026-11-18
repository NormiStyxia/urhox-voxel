-- Time catalyst: the floating star-clock orb used while the caster is in time mode (CombatState selection
-- 'time'). Visual only. Rests behind the right shoulder, flies to the casting palm while aiming/charging,
-- dissolves when a real weapon is drawn. Model: art/weapon_gen/clock_catalyst_v6_blender.py (CLOCK_EXPORT=1).
-- Surroundings (sand / sparks / cast ring) live in TimeCatalystFx with two switchable looks.
-- Motion rules (all frame-rate independent):
--   * position = critically damped spring toward the current anchor (rest slot / palm), plus a small lift arc
--     while it travels, so it glides instead of teleporting;
--   * bands / blades turn about the horizontal X axis in opposite directions, gems orbit the view axis, the
--     sapphire turns slowly; all spin speeds ease toward `rest * (1 + aim + charge + pulse)`;
--   * a cast pops the scale and spikes the spin, then both settle within ~0.5 s.
-- Any failure returns nil so the scene keeps working without the catalyst.
local Fx=require('combat.TimeCatalystFx')
local V={}
V.ENABLED=true               -- kill switch
V.SCALE=.95                  -- model radius .27 m -> ~.26 m in the world (readable at the follow-camera distance)
V.STEP_VERTICES=2400         -- body upload per Step()
V.FX_MODE='pixel'            -- default surroundings: pixel | texture | off (NextFxMode cycles at runtime)
local MATERIAL='model/forge-blades/ClockCatalyst.xml'
local MASK=0xFFFFFFFF
local PARTS={'bands','blades','gems','shards','core'}
-- deg/s about the pivot axis at rest
local SPIN={bands=-26,blades=19,gems=34,core=11,shards=0}
local model
local function Model()
    model=model or require('combat.models.ClockCatalyst')
    return model
end

local function DefineBody(g,part,from,to)
    local m=Model()
    local v,idx=part.v,part.i
    local ps,ns=1/m.scale,1/m.nscale
    for k=from,to do
        local base=(idx[k]-1)*8
        g:DefineVertex(Vector3(v[base+1]*ps,v[base+2]*ps,v[base+3]*ps))
        g:DefineNormal(Vector3(v[base+4]*ns,v[base+5]*ns,v[base+6]*ns))
        g:DefineColor(Color(1,1,1,v[base+8]*.01))
        g:DefineTexCoord(Vector2(v[base+7]*.1,.5))
    end
end

local function SetShown(visual,flag)
    if visual.shown==flag then return end
    visual.shown=flag
    -- Node enable is NOT recursive: every child node must be toggled or it keeps rendering in place.
    visual.root.enabled=flag
    for _,pivot in pairs(visual.pivots) do pivot.enabled=flag end
    Fx.SetShown(visual.fx,flag)
end

---@param scene Node
---@param cameraNode Node? camera node (pixel quads face it)
---@return table? visual
---@return string? err
function V.New(scene,cameraNode)
    if not V.ENABLED then return nil,'disabled' end
    local visual={cursor=1,partIndex=1,ready=false,fade=0,aim=0,spinBoost=0,pulse=0,charge=0,
        glowKey=-1,fadeKey=-1,shown=false,speed=0,
        pos=Vector3(0,0,0),vel=Vector3(0,0,0),initialised=false,clock=0,castSeen=false,
        angles={bands=0,blades=0,gems=0,core=0}}
    local ok,err=pcall(function()
        local source=assert(cache:GetResource('Material',MATERIAL),'catalyst material unavailable')
        visual.material=assert(source:Clone('ClockCatalystMat'),'catalyst material clone failed')
        visual.root=scene:CreateChild('time_catalyst')
        visual.root.temporary=true
        visual.root.enabled=false
        visual.pivots={}
        visual.geometry={}
        for _,name in ipairs(PARTS) do
            local pivot=visual.root:CreateChild('catalyst_'..name)
            pivot.enabled=false
            visual.pivots[name]=pivot
            local g=assert(pivot:CreateComponent('CustomGeometry'),'CustomGeometry unavailable')
            g.viewMask=MASK;g.lightMask=MASK;g.zoneMask=MASK;g.castShadows=false
            g:BeginGeometry(0,TRIANGLE_LIST)
            visual.geometry[name]=g
        end
        visual.fx=Fx.New(scene,visual.root,cameraNode)
        Fx.SetMode(visual.fx,V.FX_MODE)
    end)
    if not ok then
        V.Dispose(visual)
        return nil,tostring(err)
    end
    return visual
end

--- Spread the ~8k-vertex upload over frames; true when every part is committed.
---@param visual table?
---@return boolean
function V.Step(visual)
    if not visual then return false end
    if visual.ready then return true end
    if visual.failed then return false end
    local ok,err=pcall(function()
        local m=Model()
        local budget=V.STEP_VERTICES
        while budget>0 and visual.partIndex<=#PARTS do
            local name=PARTS[visual.partIndex]
            local part=m[name]
            local total=part.triangles*3
            local last=math.min(total,visual.cursor+budget-1)
            DefineBody(visual.geometry[name],part,visual.cursor,last)
            budget=budget-(last-visual.cursor+1)
            visual.cursor=last+1
            if last>=total then
                visual.geometry[name]:Commit()
                assert(visual.geometry[name]:SetMaterial(0,visual.material)~=false,'catalyst material binding failed')
                visual.partIndex=visual.partIndex+1
                visual.cursor=1
            end
        end
        if visual.partIndex>#PARTS then visual.ready=true end
    end)
    if not ok then
        visual.failed=true
        print('TimeCatalystVisual: build failed, catalyst hidden: '..tostring(err))
        return false
    end
    return visual.ready
end

local function Smooth(current,target,rate,dt)
    return current+(target-current)*(1-math.exp(-rate*dt))
end
-- Critically damped spring on a Vector3 (returns new position and velocity).
local function Spring(pos,vel,target,dt,omega)
    local e=math.exp(-omega*dt)
    local function Axis(d,v)
        local t=v+omega*d
        return (d+t*dt)*e, (v-omega*t*dt)*e
    end
    local nx,vx=Axis(pos.x-target.x,vel.x)
    local ny,vy=Axis(pos.y-target.y,vel.y)
    local nz,vz=Axis(pos.z-target.z,vel.z)
    return Vector3(target.x+nx,target.y+ny,target.z+nz),Vector3(vx,vy,vz)
end

--- Cached-Variant shader parameter write (`value` quantised to 1/steps).
local function SetQuant(visual,material,key,value,steps)
    local q=math.floor(value*steps+.5)
    local slot='k_'..key
    if visual[slot]==q then return end
    visual[slot]=q
    visual.variants=visual.variants or {}
    local id=key..q
    local v=visual.variants[id]
    if not v then v=Variant(q/steps);visual.variants[id]=v end
    material:SetShaderParameter(key,v)
end

--- Per-frame update.
---@param visual table?
---@param dt number
---@param ctx table active:boolean, position:Vector3 (feet), yaw:number (deg, character facing),
---       hand:Vector3 (palm), aiming:boolean, charge:number 0..1, casting:boolean
function V.Update(visual,dt,ctx)
    if not visual or not visual.ready then return end
    dt=math.min(math.max(dt or 0,0),.1)
    visual.clock=visual.clock+dt
    -- materialise / dissolve
    local wantFade=ctx.active and 1 or 0
    local rate=wantFade>visual.fade and 5 or 9
    visual.fade=Smooth(visual.fade,wantFade,rate,dt)
    if visual.fade<.01 and wantFade==0 then
        visual.fade=0
        SetShown(visual,false)
        visual.initialised=false
        return
    end
    local yaw=Quaternion(0,ctx.yaw,0)
    local rest=ctx.position+yaw*Vector3(.62,1.45,-.46)
    rest.y=rest.y+.035*math.sin(visual.clock*2.1)+.012*math.sin(visual.clock*5.3+1.3)
    local aimTarget=ctx.aiming and 1 or 0
    visual.aim=Smooth(visual.aim,aimTarget,ctx.aiming and 11 or 6,dt)
    visual.charge=Smooth(visual.charge,ctx.aiming and (ctx.charge or 0) or 0,10,dt)
    local forward=yaw*Vector3(0,0,1)
    local hand=ctx.hand+forward*.27+Vector3(0,.04,0)
    local target=Vector3(rest.x+(hand.x-rest.x)*visual.aim,rest.y+(hand.y-rest.y)*visual.aim,rest.z+(hand.z-rest.z)*visual.aim)
    if not visual.initialised then
        visual.pos=Vector3(rest.x,rest.y-.15,rest.z);visual.vel=Vector3(0,.4,0);visual.initialised=true
        SetShown(visual,true)
    end
    local omega=8+8*visual.aim
    local newPos,newVel=Spring(visual.pos,visual.vel,target,dt,omega)
    -- lift arc while travelling between the rest slot and the palm
    local travel=visual.aim*(1-visual.aim)*4
    visual.pos,visual.vel=newPos,newVel
    visual.speed=newVel:Length()
    local show=Vector3(newPos.x,newPos.y+.08*travel,newPos.z)
    -- cast pop: edge of ctx.casting
    local castEdge=false
    if ctx.casting and not visual.castSeen then visual.pulse=1;castEdge=true end
    visual.castSeen=ctx.casting==true
    visual.pulse=Smooth(visual.pulse,0,5,dt)
    local boost=math.min(5,1+2.0*visual.aim+2.4*visual.charge+3.5*visual.pulse)
    visual.spinBoost=Smooth(visual.spinBoost,boost,6,dt)
    local scale=V.SCALE*(1+.04*visual.aim+.06*visual.charge+.12*visual.pulse)*(.25+.75*visual.fade)
    visual.root.position=show
    -- front face toward the camera behind the caster; gentle idle sway so it never looks pasted on
    local sway=Quaternion(0,7*math.sin(visual.clock*.7),0)
    local orient=yaw*sway
    visual.root.rotation=orient
    visual.root.scale=Vector3(scale,scale,scale)
    -- part spin
    for _,name in ipairs({'bands','blades','core'}) do
        visual.angles[name]=(visual.angles[name]+SPIN[name]*visual.spinBoost*dt)%360
        local angle=visual.angles[name]
        visual.pivots[name].rotation=name=='core' and Quaternion(0,angle,0) or Quaternion(angle,0,0)
    end
    visual.angles.gems=(visual.angles.gems+SPIN.gems*visual.spinBoost*dt)%360
    visual.pivots.gems.rotation=Quaternion(0,0,visual.angles.gems)
    visual.pivots.shards.position=Vector3(0,.006*math.sin(visual.clock*1.9),0)
    -- shader parameters (quantised, cached Variants: no per-frame allocation)
    local glow=math.min(1,.15+.55*visual.aim+.5*visual.charge+.5*visual.pulse)
    SetQuant(visual,visual.material,'glow',glow,20)
    SetQuant(visual,visual.material,'fade',visual.fade,20)
    Fx.Update(visual.fx,dt,{center=show,rot=orient,scale=scale,aim=visual.aim,charge=visual.charge,
        pulse=visual.pulse,speed=visual.speed,fade=visual.fade,burst=castEdge})
end

--- Pixel particle quads face the camera: draw after the camera has moved this frame.
---@param visual table?
function V.Draw(visual)
    if visual and visual.shown then Fx.Draw(visual.fx) end
end

---@param visual table?
---@param mode string? pixel | texture | off; nil cycles
---@return string? applied
function V.SetFxMode(visual,mode)
    if not visual then return nil end
    if mode then return Fx.SetMode(visual.fx,mode) end
    return Fx.NextMode(visual.fx)
end

---@param visual table?
---@return boolean
function V.Visible(visual)
    return visual~=nil and visual.root~=nil and visual.root.enabled
end

---@param visual table?
function V.Dispose(visual)
    if not visual then return end
    Fx.Dispose(visual.fx);visual.fx=nil
    if visual.root then pcall(visual.root.Remove,visual.root);visual.root=nil end
    if visual.material then pcall(visual.material.Dispose,visual.material);visual.material=nil end
    visual.pivots,visual.geometry=nil,nil
end
return V
