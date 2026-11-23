-- Pixel mana that attaches to the complete nocked arrow during bow draw.
-- The nock/tip/rotation are supplied by WeaponRig, so this effect never owns
-- projectile direction or invents a second launch point.
local F={}
local TAU=math.pi*2
local PALETTES={
    field={
        edge={Color(1.00,.58,.12,1),Color(1.00,.84,.34,1),Color(.66,.20,.04,.72),Color(.22,.05,.01,.16)},
        full={Color(1,1,1,1),Color(1,1,1,1),Color(1.00,.76,.20,1),Color(.60,.14,.02,.20)},
    },
    silver={
        edge={Color(.52,.80,1.00,1),Color(.86,.96,1.00,1),Color(.22,.46,.82,.68),Color(.05,.14,.35,.16)},
        full={Color(1,1,1,1),Color(1,1,1,1),Color(.70,.90,1.00,1),Color(.22,.46,.82,.20)},
    },
    thorn={
        edge={Color(.70,.26,1.00,1),Color(1.00,.58,.88,1),Color(.34,.06,.68,.72),Color(.10,.01,.24,.16)},
        full={Color(1,1,1,1),Color(1,1,1,1),Color(.92,.42,.98,1),Color(.34,.05,.64,.20)},
    },
}
local function Clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function Basis(fx,v) return fx.rotation*v end
local function Palette(id,full)
    local p=PALETTES[id] or PALETTES.field
    return full and p.full or p.edge
end

-- Four visible source streams. The offsets are deliberately 0.20--0.30 m
-- from the arrow, roughly 1/4--1/2 of the HunterBow span, so the effect reads
-- as energy arriving from both limbs and the side-front space at game distance.
local STREAMS={
    {x=.20,y=.22,target=.22,bend=.042,size=.026},
    {x=-.24,y=.16,target=.43,bend=.055,size=.034},
    {x=.25,y=-.15,target=.67,bend=.050,size=.030},
    {x=-.19,y=-.24,target=.88,bend=.068,size=.037},
}

function F.New(parent)
    local fx={active=false,charge=0,acc=0,nock=Vector3.ZERO,rotation=Quaternion(),
        arrowLength=.705,modelId='field',phase=0,streamPhase=0}
    local ok,err=pcall(function()
        local VoxelFX=require('dragon.VoxelFX')
        fx.root=parent:CreateChild('bow_charge_grains')
        fx.root.temporary=true
        fx.root.enabled=false
        -- Same hard-edged VoxelSprite material path and pixel scale family as
        -- TimeCatalystFx, with a small fixed pool for mobile/Web stability.
        -- Keep both pools in the same root. star is the bright core, flake is
        -- the larger segmented stream material used by the time catalyst.
        fx.motes=VoxelFX.Motes(fx.root,'BowArrowManaMotes',72,'star',true)
        fx.flakes=VoxelFX.Motes(fx.root,'BowArrowManaFlakes',48,'flake',true)
    end)
    if not ok then
        if fx.root then pcall(fx.root.Remove,fx.root) end
        return nil,tostring(err)
    end
    return fx
end

local function Spawn(fx,tipPulse,streamIndex,flake)
    local pool=flake and fx.flakes or fx.motes
    if not pool or pool:Count()>=(flake and 44 or 68) then return end
    fx.phase=fx.phase+1
    local i=fx.phase
    local stream=STREAMS[streamIndex or ((fx.streamPhase%#STREAMS)+1)]
    fx.streamPhase=(fx.streamPhase%#STREAMS)+1
    local a=(i*2.399963)%TAU
    local charge=fx.charge
    local full=charge>=.97
    local tip=tipPulse or (full and i%5==0)
    local target=tip and 1.0 or Clamp(stream.target+.06*charge,0.08,.98)
    local sourceZ=fx.arrowLength*(target*.52+.05*math.sin(a))
    local source=Vector3(stream.x,stream.y,sourceZ)
    -- Charge tightens the source stream while preserving an outer silhouette.
    local sourceScale=1-.18*charge
    local colors=Palette(fx.modelId,tip)
    local mote={pos=fx.nock+Basis(fx,source),life=.48+.16*charge,
        size=(tip and .030 or stream.size)*(flake and 1.22 or 1),colors=colors,
        source=source*sourceScale,target=target,bend=stream.bend,
        spin=(i%2==0 and 1 or -1)*(.75+charge),tip=tip,phase=a}
    mote.fn=function(m,_,u)
        -- Gather through a bent, segmented arc. The first 44% visibly spans
        -- the empty space around the bow, then the energy wraps the shaft and
        -- continues forward along it instead of vanishing at contact.
        local attach=Clamp(u/.44,0,1)
        local flow=Clamp((u-.34)/.66,0,1)
        local inward=1-attach
        local sourceAlong=Clamp(m.source.z/fx.arrowLength,0,.98)
        local gathered=sourceAlong+(m.target-sourceAlong)*attach
        local along=gathered+flow*(.10+.14*charge)
        along=Clamp(along,.02,.995)
        local curve=math.sin((u+.08)*math.pi)*m.bend*(1-.35*charge)
        local wobble=math.sin(u*TAU*(1.15+m.spin)+i*.31)*.009*(1-u)
        local radial=Vector3(m.source.x*inward+curve,
            m.source.y*inward+wobble,0)
        if attach>.70 then
            -- Short wrap around the arrow before longitudinal flow.
            local wrap=(1-attach)*.018
            radial=radial+Vector3(math.cos(m.phase+u*TAU*1.7)*wrap,
                math.sin(m.phase+u*TAU*1.7)*wrap,0)
        end
        if m.tip then radial=radial*.62 end
        m.pos=fx.nock+Basis(fx,Vector3(radial.x,radial.y,fx.arrowLength*along))
    end
    pool:Spawn(mote)
end

--- ctx includes nock/tip points from the actual bow pivot and modelId.
---@param ctx table {active:boolean,charge:number,nock:Vector3,tip:Vector3,rotation:Quaternion,modelId:string}
function F.Update(fx,dt,ctx)
    if not fx or not fx.motes then return end
    dt=math.min(math.max(dt or 0,0),.1)
    local active=ctx and ctx.active==true and (ctx.nock or ctx.center)~=nil
    fx.active=active
    if active then
        fx.nock=ctx.nock or ctx.center
        fx.rotation=ctx.rotation or fx.rotation
        fx.arrowLength=ctx.arrowLength or fx.arrowLength
        fx.modelId=ctx.modelId or fx.modelId
        fx.charge=Clamp(ctx.charge or 0,0,1)
        fx.acc=fx.acc+dt*(16+36*fx.charge)
        local emitted=0
        while fx.acc>=1 and emitted<5 do
            fx.acc=fx.acc-1;emitted=emitted+1
            local stream=((fx.streamPhase-1)%#STREAMS)+1
            Spawn(fx,false,stream,(fx.phase%3)==0)
        end
    else
        fx.acc=0
    end
    fx.motes:Update(dt)
    if fx.flakes then fx.flakes:Update(dt) end
    fx.root.enabled=active or fx.motes:Count()>0 or fx.flakes:Count()>0
end

--- Full-charge event hook used by WeaponRig:FlashBowFull. It replaces the
--- legacy 3x3 voxel flash with a short white-core arrowhead pulse.
function F.Full(fx)
    if not fx or not fx.motes then return end
    fx.charge=1
    for i=1,4 do Spawn(fx,true,i,(i%2)==0) end
    fx.root.enabled=true
end

function F.Stop(fx)
    if not fx then return end
    fx.active=false;fx.acc=0
end

function F.Clear(fx)
    if not fx then return end
    fx.active=false;fx.acc=0
    if fx.motes then fx.motes:Clear() end
    if fx.flakes then fx.flakes:Clear() end
    if fx.root then fx.root.enabled=false end
end

function F.Dispose(fx)
    if not fx then return end
    F.Clear(fx)
    if fx.root then pcall(fx.root.Remove,fx.root);fx.root=nil end
    fx.motes=nil;fx.flakes=nil
end
return F
