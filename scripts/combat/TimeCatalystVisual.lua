-- Time catalyst: the floating star-clock orb used while the caster is in time mode (CombatState selection
-- 'time'). Visual only. Rests behind the right shoulder, flies to the casting palm while aiming/charging,
-- dissolves when a real weapon is drawn. Model: art/weapon_gen/clock_catalyst_v6_blender.py (CLOCK_EXPORT=1).
-- Motion rules (all frame-rate independent):
--   * position = critically damped spring toward the current anchor (rest slot / palm), plus a small lift arc
--     while it travels, so it glides instead of teleporting;
--   * bands / blades turn about the horizontal X axis in opposite directions, gems orbit the view axis, the
--     sapphire turns slowly; all spin speeds ease toward `rest * (1 + aim + charge + pulse)`;
--   * a cast pops the scale (+14%) and spikes the spin, then both settle within ~0.5 s;
--   * sand streams tighten toward the core and speed up with charge.
-- Any failure returns nil so the scene keeps working without the catalyst.
local V={}
V.ENABLED=true               -- kill switch
V.SCALE=.95                  -- model radius .27 m -> ~.26 m in the world (readable at the follow-camera distance)
V.STEP_VERTICES=2400         -- body upload per Step()
local MATERIAL='model/forge-blades/ClockCatalyst.xml'
local SAND='model/forge-blades/ClockSand.xml'
local MOTES='model/forge-blades/ClockMotes.xml'
local RING='model/forge-blades/ClockRing.xml'
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

-- Ribbon grains for the star-river sand; ClockSand.shader moves them on the GPU.
local function BuildSand(node,material)
    local g=assert(node:CreateComponent('CustomGeometry'),'CustomGeometry unavailable')
    g.viewMask=MASK;g.lightMask=MASK;g.zoneMask=MASK;g.castShadows=false
    g:BeginGeometry(0,TRIANGLE_LIST)
    local seed=29
    local function Rand()
        seed=(seed*1103515245+12345)%2147483648
        return seed/2147483648
    end
    local quad={{0,-1},{1,-1},{1,1},{0,-1},{1,1},{0,1}}
    local counts={[0]=64,[1]=64,[2]=48}
    for stream=0,2 do
        for i=0,counts[stream]-1 do
            local s0=(i+Rand()*.9)/counts[stream]
            local jitter,size=Rand(),Rand()
            for _,q in ipairs(quad) do
                g:DefineVertex(Vector3(0,0,0))
                g:DefineNormal(Vector3(0,0,-1))
                g:DefineColor(Color(q[1],(q[2]+1)*.5,jitter,size))
                g:DefineTexCoord(Vector2(s0,stream))
            end
        end
    end
    g:Commit()
    assert(g:SetMaterial(0,material)~=false,'sand material binding failed')
    return g
end

-- Star motes: camera-facing diamonds, placed by ClockMotes.shader (phase in UV.x, seed in UV.y, corner in COLOR.rg).
local function BuildMotes(node,material)
    local g=assert(node:CreateComponent('CustomGeometry'),'CustomGeometry unavailable')
    g.viewMask=MASK;g.lightMask=MASK;g.zoneMask=MASK;g.castShadows=false
    g:BeginGeometry(0,TRIANGLE_LIST)
    local seed=71
    local function Rand()
        seed=(seed*1103515245+12345)%2147483648
        return seed/2147483648
    end
    local corners={{0,0},{1,0},{1,1},{0,0},{1,1},{0,1}}
    for i=0,79 do
        local phase,s=(i+Rand()*.9)/80,Rand()
        for _,c in ipairs(corners) do
            g:DefineVertex(Vector3(0,0,0))
            g:DefineNormal(Vector3(0,0,-1))
            g:DefineColor(Color(c[1],c[2],0,1))
            g:DefineTexCoord(Vector2(phase,s))
        end
    end
    g:Commit()
    assert(g:SetMaterial(0,material)~=false,'motes material binding failed')
    return g
end

-- Cast ripple: flat annulus in the orb's front plane (UV.x angle, UV.y radial).
local function BuildRing(node,material)
    local g=assert(node:CreateComponent('CustomGeometry'),'CustomGeometry unavailable')
    g.viewMask=MASK;g.lightMask=MASK;g.zoneMask=MASK;g.castShadows=false
    g:BeginGeometry(0,TRIANGLE_LIST)
    local n,r0,r1=96,.215,.30
    local function Vert(a,rr,u,v)
        g:DefineVertex(Vector3(math.cos(a)*rr,math.sin(a)*rr,-.03))
        g:DefineNormal(Vector3(0,0,-1))
        g:DefineColor(Color(1,1,1,1))
        g:DefineTexCoord(Vector2(u,v))
    end
    for i=0,n-1 do
        local a0,a1=i/n*math.pi*2,(i+1)/n*math.pi*2
        Vert(a0,r0,i/n,0);Vert(a1,r0,(i+1)/n,0);Vert(a1,r1,(i+1)/n,1)
        Vert(a0,r0,i/n,0);Vert(a1,r1,(i+1)/n,1);Vert(a0,r1,i/n,1)
    end
    g:Commit()
    assert(g:SetMaterial(0,material)~=false,'ring material binding failed')
    return g
end

local function SetShown(visual,flag)
    if visual.shown==flag then return end
    visual.shown=flag
    -- Node enable is NOT recursive: every child node must be toggled or it keeps rendering in place.
    visual.root.enabled=flag
    for _,pivot in pairs(visual.pivots) do pivot.enabled=flag end
    if visual.sandNode then visual.sandNode.enabled=flag end
    if visual.motesNode then visual.motesNode.enabled=flag end
    if visual.ringNode then visual.ringNode.enabled=flag and visual.ringAge<1 end
end

---@param scene Node
---@return table? visual
---@return string? err
function V.New(scene)
    if not V.ENABLED then return nil,'disabled' end
    local visual={cursor=1,partIndex=1,ready=false,fade=0,aim=0,spinBoost=0,pulse=0,charge=0,
        sandStrength=-1,sandTighten=-1,sandSpeed=-1,glowKey=-1,fadeKey=-1,
        pos=Vector3(0,0,0),vel=Vector3(0,0,0),initialised=false,clock=0,castSeen=false,
        angles={bands=0,blades=0,gems=0,core=0},spin={bands=SPIN.bands,blades=SPIN.blades,gems=SPIN.gems,core=SPIN.core}}
    local ok,err=pcall(function()
        local source=assert(cache:GetResource('Material',MATERIAL),'catalyst material unavailable')
        visual.material=assert(source:Clone('ClockCatalystMat'),'catalyst material clone failed')
        local sand=cache:GetResource('Material',SAND)
        visual.sandMaterial=sand and sand:Clone('ClockSandMat') or nil
        visual.root=scene:CreateChild('time_catalyst')
        visual.root.temporary=true
        visual.root.enabled=false
        visual.shown=false
        visual.ringAge=1
        visual.pivots={}
        visual.geometry={}
        for _,name in ipairs(PARTS) do
            local pivot=visual.root:CreateChild('catalyst_'..name)
            visual.pivots[name]=pivot
            local g=assert(pivot:CreateComponent('CustomGeometry'),'CustomGeometry unavailable')
            g.viewMask=MASK;g.lightMask=MASK;g.zoneMask=MASK;g.castShadows=false
            g:BeginGeometry(0,TRIANGLE_LIST)
            visual.geometry[name]=g
        end
        if visual.sandMaterial then
            visual.sandNode=visual.root:CreateChild('catalyst_sand')
            BuildSand(visual.sandNode,visual.sandMaterial)
            visual.sandNode.enabled=false
        end
        local motes=cache:GetResource('Material',MOTES)
        visual.motesMaterial=motes and motes:Clone('ClockMotesMat') or nil
        if visual.motesMaterial then
            visual.motesMaterial:SetShaderParameter('spread',Variant(V.SCALE))
            visual.motesNode=visual.root:CreateChild('catalyst_motes')
            BuildMotes(visual.motesNode,visual.motesMaterial)
            visual.motesNode.enabled=false
        end
        local ring=cache:GetResource('Material',RING)
        visual.ringMaterial=ring and ring:Clone('ClockRingMat') or nil
        if visual.ringMaterial then
            visual.ringNode=visual.root:CreateChild('catalyst_ring')
            BuildRing(visual.ringNode,visual.ringMaterial)
            visual.ringNode.enabled=false
        end
        for _,pivot in pairs(visual.pivots) do pivot.enabled=false end
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
-- Critically damped spring on a Vector3 table (components updated in place).
local function Spring(pos,vel,target,dt,omega)
    local dx,dy,dz=pos.x-target.x,pos.y-target.y,pos.z-target.z
    local e=math.exp(-omega*dt)
    local function Axis(d,v)
        local t=v+omega*d
        return (d+t*dt)*e, (v-omega*t*dt)*e
    end
    local nx,vx=Axis(dx,vel.x)
    local ny,vy=Axis(dy,vel.y)
    local nz,vz=Axis(dz,vel.z)
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
    local show=Vector3(newPos.x,newPos.y+.08*travel,newPos.z)
    -- cast pop: edge of ctx.casting
    if ctx.casting and not visual.castSeen then visual.pulse=1;visual.ringAge=0 end
    visual.castSeen=ctx.casting==true
    visual.pulse=Smooth(visual.pulse,0,5,dt)
    local boost=math.min(5,1+2.0*visual.aim+2.4*visual.charge+3.5*visual.pulse)
    visual.spinBoost=Smooth(visual.spinBoost,boost,6,dt)
    local scale=V.SCALE*(1+.04*visual.aim+.06*visual.charge+.12*visual.pulse)*(.25+.75*visual.fade)
    visual.root.position=show
    -- front face toward the camera behind the caster; gentle idle sway so it never looks pasted on
    local sway=Quaternion(0,7*math.sin(visual.clock*.7),0)
    visual.root.rotation=yaw*sway
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
    if visual.ringMaterial then
        visual.ringAge=math.min(1,visual.ringAge+dt/.8)
        local on=visual.ringAge<1
        if visual.ringNode.enabled~=on then visual.ringNode.enabled=on end
        if on then SetQuant(visual,visual.ringMaterial,'age',visual.ringAge,40) end
    end
    if visual.motesMaterial then
        SetQuant(visual,visual.motesMaterial,'strength',(.55+.45*visual.aim+.3*visual.charge)*visual.fade,20)
    end
    if visual.sandMaterial then
        SetQuant(visual,visual.sandMaterial,'strength',(.40+.55*visual.aim+.35*visual.charge)*visual.fade,20)
        SetQuant(visual,visual.sandMaterial,'tighten',math.min(1,.55*visual.aim+.45*visual.charge),20)
        SetQuant(visual,visual.sandMaterial,'flow_speed',.11*(1+.9*visual.aim+1.6*visual.charge+1.2*visual.pulse),50)
    end
end

---@param visual table?
---@return boolean
function V.Visible(visual)
    return visual~=nil and visual.root~=nil and visual.root.enabled
end

---@param visual table?
function V.Dispose(visual)
    if not visual then return end
    if visual.root then pcall(visual.root.Remove,visual.root);visual.root=nil end
    if visual.material then pcall(visual.material.Dispose,visual.material);visual.material=nil end
    if visual.sandMaterial then pcall(visual.sandMaterial.Dispose,visual.sandMaterial);visual.sandMaterial=nil end
    if visual.motesMaterial then pcall(visual.motesMaterial.Dispose,visual.motesMaterial);visual.motesMaterial=nil end
    if visual.ringMaterial then pcall(visual.ringMaterial.Dispose,visual.ringMaterial);visual.ringMaterial=nil end
    visual.pivots,visual.geometry=nil,nil
end
return V
