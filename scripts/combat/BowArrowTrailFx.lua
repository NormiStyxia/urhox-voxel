-- Small pixel-sand tail for arrows already flying through Projectile's real path.
-- This is visual-only. Projectile collision, direction, range and embedding stay
-- owned by combat.Projectile.
local VoxelFX=require('dragon.VoxelFX')
local F={}

local PALETTES={
    field={Color(1.00,.72,.18,1),Color(1.00,.92,.48,1),Color(.78,.30,.04,.72),Color(.28,.06,.01,.18)},
    silver={Color(.55,.84,1.00,1),Color(.90,.98,1.00,1),Color(.30,.58,.92,.68),Color(.06,.16,.38,.18)},
    thorn={Color(.72,.30,1.00,1),Color(1.00,.64,.92,1),Color(.42,.10,.74,.68),Color(.12,.02,.28,.18)},
}

local function Palette(modelId)
    return PALETTES[modelId] or PALETTES.field
end

function F.New(scene)
    local fx={root=nil,stars=nil,flakes=nil,ready=false}
    local ok,err=pcall(function()
        fx.root=scene:CreateChild('bow_arrow_flight_grains')
        fx.root.temporary=true
        fx.root.enabled=false
        -- The two built-in VoxelFX sprites mirror the time catalyst's star and
        -- segmented flake language. No external texture or image asset is used.
        fx.stars=VoxelFX.Motes(fx.root,'BowArrowFlightStars',128,'star',true)
        fx.flakes=VoxelFX.Motes(fx.root,'BowArrowFlightFlakes',48,'flake',true)
        fx.ready=true
    end)
    if not ok then
        if fx.root then pcall(fx.root.Remove,fx.root) end
        return nil,tostring(err)
    end
    return fx
end

local function Spawn(fx,p,pos,dir,ordinal)
    local colors=Palette(p.modelId)
    local phase=(ordinal*2.399963)%6.283185307
    local side=Vector3(math.cos(phase)*.010,math.sin(phase)*.010,0)
    local star={pos=pos+side,vel=dir*(-.20)+side*1.5,
        life=.14+.04*(ordinal%3),size=.008+.002*(ordinal%2),colors=colors,drag=2.0}
    fx.stars:Spawn(star)
    -- A larger flake every third sample supplies the segmented sand rhythm
    -- without turning a fast arrow into a solid ribbon.
    if ordinal%3==0 then
        fx.flakes:Spawn{pos=pos-side,vel=dir*(-.12)-side,
            life=.18+.03*(ordinal%2),size=.012+.002*(ordinal%2),colors=colors,drag=2.4}
    end
end

--- Draw samples the actual Projectile render path. It is called after each
--- fixed-step update and never writes p.pos, p.vel or collision state.
function F.Draw(fx,p,visible)
    if not fx or not fx.ready or not p then return end
    local pos=p.renderPos or p.pos
    local state=p.bowTrail
    if state==nil or state.serial~=p.serial then
        p.bowTrail={serial=p.serial,lastPos=pos,carry=0,ordinal=0}
        return
    end
    if not visible or p.embedded then
        state.lastPos=pos
        state.carry=0
        return
    end
    local delta=pos-state.lastPos
    local distance=delta:Length()
    if distance<1e-7 then return end
    local dir=delta*(1/distance)
    local spacing=.24
    local at=spacing-state.carry
    local emitted=0
    while at<=distance and emitted<5 do
        state.ordinal=state.ordinal+1
        Spawn(fx,p,state.lastPos+dir*at,dir,state.ordinal)
        emitted=emitted+1
        at=at+spacing
    end
    state.carry=(state.carry+distance)%spacing
    state.lastPos=pos
end

function F.Update(fx,dt)
    if not fx or not fx.ready then return end
    dt=math.min(math.max(dt or 0,0),.1)
    fx.stars:Update(dt)
    fx.flakes:Update(dt)
    fx.root.enabled=fx.stars:Count()>0 or fx.flakes:Count()>0
end

function F.Clear(fx)
    if not fx then return end
    if fx.stars then fx.stars:Clear() end
    if fx.flakes then fx.flakes:Clear() end
    if fx.root then fx.root.enabled=false end
end

function F.Dispose(fx)
    if not fx then return end
    F.Clear(fx)
    if fx.root then pcall(fx.root.Remove,fx.root) end
    fx.root,fx.stars,fx.flakes,fx.ready=nil,nil,nil,false
end

return F
