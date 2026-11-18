-- Time catalyst surroundings, two interchangeable looks (switch with TimeCatalystFx.SetMode):
--   'pixel'   : voxel-world pixel particles (dragon.VoxelFX.WorldMotes, additive pixel sprites): star-river sand
--               comets on three orbits, drifting star sparks, a pixel clock ring + burst on every cast, trail while flying.
--   'texture' : AI-painted textures (assets/Textures/fx/clock_dial.png, clock_sand.png) pasted through ClockTex.shader:
--               a camera-facing dial halo behind the orb and two tilted star-sand rings that slowly spin.
--   'off'     : neither (orb only).
-- Visual only. All positions follow the orb through `state`, so motion rules stay in TimeCatalystVisual.
local F={}
F.MODES={'pixel','texture','off'}
local TEX_SHADER='model/forge-blades/ClockTex.shader'
local DIAL_TEX='Textures/fx/clock_dial.png'
local SAND_TEX='Textures/fx/clock_sand.png'
local MASK=0xFFFFFFFF
local TAU=math.pi*2

local function C(r,g,b,a) return Color(r,g,b,a or 1) end
-- stepped colour ramps (sRGB inputs, VoxelSprite.shader linearises); alpha < 1 at the tail = pixel dissolve
local RAMP_SAND={C(1,1,1,1),C(.72,.90,1,1),C(.34,.62,1,.92),C(.12,.30,.85,.55)}
local RAMP_GOLD={C(1,.97,.80,1),C(1,.82,.38,1),C(.70,.84,1,.8),C(.22,.42,.95,.5)}
local RAMP_ICE={C(.86,.96,1,1),C(.50,.78,1,1),C(.24,.50,.98,.8),C(.10,.24,.80,.45)}

local function Rand(a,b) return a+(b-a)*math.random() end

-- same three orbits as the model's sand: inner pair counter-rotating, outer galactic ring
local STREAMS={
    {tilt=.55,rad=.135,dir=1,rate=24},
    {tilt=-.60,rad=.175,dir=-1,rate=22},
    {tilt=1.15,rad=.315,dir=1,rate=16},
}
local function Orbit(stream,angle,tighten,jitter)
    local s=STREAMS[stream]
    local a=angle*s.dir
    local rad=s.rad*(1-.28*tighten)+.012*math.sin(angle*3+stream*1.7)+(jitter or 0)
    local x,y=math.cos(a)*rad,math.sin(a)*rad*.62
    local z=math.sin(angle*2+stream)*rad*.35
    local ct,st=math.cos(s.tilt),math.sin(s.tilt)
    return Vector3(x,y*ct-z*st,y*st+z*ct)
end

local function MakeMaterial(texturePath)
    local texture=cache:GetResource('Texture2D',texturePath)
    if not texture then return nil end
    local material=Material:new()
    if material:SetSurfaceShader(TEX_SHADER)==false then return nil end
    material:SetSurfaceTexture('tex',texture)
    return material
end

local function Quad(node,half,material,mask)
    local g=assert(node:CreateComponent('CustomGeometry'),'CustomGeometry unavailable')
    g.viewMask=mask;g.lightMask=mask;g.zoneMask=mask;g.castShadows=false
    g:BeginGeometry(0,TRIANGLE_LIST)
    local function V(x,y,u,v)
        g:DefineVertex(Vector3(x*half,y*half,0));g:DefineNormal(Vector3(0,0,-1))
        g:DefineColor(Color(1,1,1,1));g:DefineTexCoord(Vector2(u,v))
    end
    V(-1,1,0,0);V(1,1,1,0);V(1,-1,1,1)
    V(-1,1,0,0);V(1,-1,1,1);V(-1,-1,0,1)
    g:Commit()
    assert(g:SetMaterial(0,material)~=false,'fx material binding failed')
    return g
end

---@param scene Node world-space parent for pixel particles
---@param orb Node the orb root (texture quads live under it and inherit its scale/orientation)
---@param camera Node? camera node for billboarded pixel quads
---@return table fx
function F.New(scene,orb,camera)
    local fx={mode='off',shown=false,acc={0,0,0},heads={0,TAU*.37,TAU*.71},sparkAcc=0,trailAcc=0,
        cur={center=Vector3(0,0,0),rot=Quaternion(0,0,0),scale=1},ready={}}
    local ok,err=pcall(function()
        local VoxelFX=require('dragon.VoxelFX')
        fx.sand=VoxelFX.WorldMotes(scene,'CatalystPixelSand',300,'square',true,camera)
        fx.spark=VoxelFX.WorldMotes(scene,'CatalystPixelSpark',90,'star',true,camera)
        fx.burst=VoxelFX.WorldMotes(scene,'CatalystPixelBurst',130,'square',true,camera)
        fx.ready.pixel=true
    end)
    if not ok then print('TimeCatalystFx: pixel mode unavailable: '..tostring(err)) end
    ok,err=pcall(function()
        fx.dialMaterial=assert(MakeMaterial(DIAL_TEX),'dial texture/shader unavailable')
        fx.sandMaterialA=assert(MakeMaterial(SAND_TEX),'sand texture/shader unavailable')
        fx.sandMaterialB=assert(MakeMaterial(SAND_TEX),'sand texture/shader unavailable')
        fx.dialMaterial:SetShaderParameter('billboard',Variant(1))
        fx.dialMaterial:SetShaderParameter('half_size',Variant(.50))
        fx.dialMaterial:SetShaderParameter('spin',Variant(.16))
        fx.sandMaterialA:SetShaderParameter('spin',Variant(.38))
        fx.sandMaterialB:SetShaderParameter('spin',Variant(-.52))
        fx.texRoot=orb:CreateChild('catalyst_tex_fx')
        fx.dialNode=fx.texRoot:CreateChild('dial')
        fx.dialNode.position=Vector3(0,0,.06)
        Quad(fx.dialNode,.50,fx.dialMaterial,MASK)
        fx.ringA=fx.texRoot:CreateChild('sand_a')
        fx.ringA.rotation=Quaternion(58,0,18)
        Quad(fx.ringA,.56,fx.sandMaterialA,MASK)
        fx.ringB=fx.texRoot:CreateChild('sand_b')
        fx.ringB.rotation=Quaternion(-52,20,-32)
        Quad(fx.ringB,.50,fx.sandMaterialB,MASK)
        fx.texRoot.enabled=false
        for _,n in ipairs({fx.dialNode,fx.ringA,fx.ringB}) do n.enabled=false end
        fx.ready.texture=true
    end)
    if not ok then print('TimeCatalystFx: texture mode unavailable: '..tostring(err)) end
    return fx
end

local function SetTexEnabled(fx,on)
    if not fx.texRoot then return end
    fx.texRoot.enabled=on
    fx.dialNode.enabled=on;fx.ringA.enabled=on;fx.ringB.enabled=on
end

---@param fx table?
---@param mode string pixel | texture | off
---@return string applied
function F.SetMode(fx,mode)
    if not fx then return 'off' end
    if mode~='pixel' and mode~='texture' then mode='off' end
    if mode=='pixel' and not fx.ready.pixel then mode='texture' end
    if mode=='texture' and not fx.ready.texture then mode='off' end
    if fx.mode==mode then return mode end
    fx.mode=mode
    SetTexEnabled(fx,mode=='texture' and fx.shown)
    if mode~='pixel' then
        for _,m in ipairs({fx.sand,fx.spark,fx.burst}) do if m then m:Clear() end end
    end
    return mode
end

--- Orb became visible / hidden (Node enable is not recursive: texture quads need their own toggle).
---@param fx table?
---@param flag boolean
function F.SetShown(fx,flag)
    if not fx or fx.shown==flag then return end
    fx.shown=flag
    SetTexEnabled(fx,flag and fx.mode=='texture')
    if not flag then
        for _,m in ipairs({fx.sand,fx.spark,fx.burst}) do if m then m:Clear() end end
    end
end

---@param fx table?
---@return string next mode name
function F.NextMode(fx)
    if not fx then return 'off' end
    for i,m in ipairs(F.MODES) do
        if m==fx.mode then return F.SetMode(fx,F.MODES[i%#F.MODES+1]) end
    end
    return F.SetMode(fx,'pixel')
end

local function SpawnBurst(fx,s)
    local rot,k=s.rot,s.scale
    local burst,spark=fx.burst,fx.spark
    -- radial pixel splash in the orb's front plane
    for _=1,38 do
        local a=Rand(0,TAU)
        local dir=rot*Vector3(math.cos(a),math.sin(a),Rand(-.25,.25))
        burst:Spawn{pos=s.center+dir*(.08*k),vel=dir*Rand(.9,2.3),life=Rand(.45,.8),size=Rand(.022,.040),
            colors=(math.random()<.35) and RAMP_GOLD or RAMP_SAND,drag=2.2}
    end
    -- pixel clock ring: 60 ticks, every fifth heavier and gold, widening around the orb
    for i=0,59 do
        local a=i/60*TAU
        local dir=Vector3(math.cos(a),math.sin(a),0)
        local hour=i%5==0
        burst:Spawn{pos=s.center,vel=Vector3(0,0,0),life=hour and .85 or .70,size=hour and .042 or .020,
            colors=hour and RAMP_GOLD or RAMP_ICE,
            fn=function(m,_,u)
                local ease=1-(1-u)^2.2
                local cur=fx.cur
                m.pos=cur.center+cur.rot*(dir*(.30+.52*ease))*cur.scale
            end}
    end
    for _=1,7 do
        local a=Rand(0,TAU)
        local dir=rot*Vector3(math.cos(a),math.sin(a),Rand(-.2,.2))
        spark:Spawn{pos=s.center+dir*(.25*k),vel=dir*Rand(.2,.6),life=Rand(.7,1.1),size=Rand(.06,.09),colors=RAMP_GOLD}
    end
end

--- Per-frame update. state: center Vector3, rot Quaternion (orb orientation), scale, aim 0..1, charge 0..1,
--- pulse 0..1, speed m/s, fade 0..1, burst boolean (true on the cast frame).
---@param fx table?
---@param dt number
---@param s table
function F.Update(fx,dt,s)
    if not fx then return end
    local cur=fx.cur
    cur.center,cur.rot,cur.scale=s.center,s.rot,s.scale
    if fx.mode=='pixel' then
        local fade=s.fade
        local tighten=math.min(1,.55*s.aim+.45*s.charge)
        local boost=1+.9*s.aim+1.6*s.charge+1.2*s.pulse
        local k=s.scale
        for i,stream in ipairs(STREAMS) do
            fx.heads[i]=(fx.heads[i]+TAU*.11*boost*dt*(i==3 and .55 or 1))%TAU
            fx.acc[i]=fx.acc[i]+stream.rate*(.55+.65*s.aim+.5*s.charge)*fade*dt
            while fx.acc[i]>=1 do
                fx.acc[i]=fx.acc[i]-1
                local back=Rand(0,.55)
                local localPos=Orbit(i,fx.heads[i]-back*boost,tighten,Rand(-.012,.012))
                fx.sand:Spawn{pos=s.center+s.rot*localPos*k,life=Rand(.45,.85)+.25*s.aim,size=Rand(.020,.034)*(1+.3*s.aim),
                    colors=RAMP_SAND,localPos=localPos,
                    fn=function(m,_,u)
                        local c=fx.cur
                        m.pos=c.center+c.rot*(m.localPos*(1+.35*u))*c.scale
                    end}
            end
        end
        fx.sparkAcc=fx.sparkAcc+(7+10*s.aim)*fade*dt
        while fx.sparkAcc>=1 do
            fx.sparkAcc=fx.sparkAcc-1
            local a,e=Rand(0,TAU),Rand(-.9,.9)
            local r=Rand(.32,.62)
            local dir=Vector3(math.cos(a)*math.sqrt(1-e*e),e,math.sin(a)*math.sqrt(1-e*e))
            fx.spark:Spawn{pos=s.center+s.rot*(dir*r)*k,vel=Vector3(0,Rand(.08,.22),0),life=Rand(.7,1.2),size=Rand(.050,.080),
                colors=(math.random()<.3) and RAMP_GOLD or RAMP_SAND}
        end
        -- comet trail while it flies between the back slot and the palm
        fx.trailAcc=fx.trailAcc+math.min(48,(s.speed or 0)*16)*fade*dt
        while fx.trailAcc>=1 do
            fx.trailAcc=fx.trailAcc-1
            local jitter=Vector3(Rand(-.05,.05),Rand(-.05,.05),Rand(-.05,.05))
            fx.burst:Spawn{pos=s.center+jitter,vel=Vector3(0,Rand(-.1,.1),0),life=Rand(.35,.6),size=Rand(.020,.034),
                colors=RAMP_ICE,drag=1.5}
        end
        if s.burst then SpawnBurst(fx,s) end
        fx.sand:Update(dt);fx.spark:Update(dt);fx.burst:Update(dt)
    elseif fx.mode=='texture' then
        local fade=s.fade
        local aim,charge,pulse=s.aim,s.charge,s.pulse
        local breathe=math.min(1,.5*aim+.5*charge+pulse)
        fx.dialMaterial:SetShaderParameter('strength',Variant((.34+.42*aim+.30*charge+.35*pulse)*fade))
        fx.dialMaterial:SetShaderParameter('breathe',Variant(breathe))
        local sandStrength=Variant((.55+.35*aim+.25*charge)*fade)
        fx.sandMaterialA:SetShaderParameter('strength',sandStrength)
        fx.sandMaterialB:SetShaderParameter('strength',sandStrength)
        fx.sandMaterialA:SetShaderParameter('breathe',Variant(breathe))
        fx.sandMaterialB:SetShaderParameter('breathe',Variant(breathe))
        -- rings contract toward the core while casting; dial swells slightly on the cast pulse
        local ringScale=1-.22*math.min(1,.55*aim+.45*charge)
        fx.ringA.scale=Vector3(ringScale,ringScale,ringScale)
        fx.ringB.scale=Vector3(ringScale*.9,ringScale*.9,ringScale*.9)
        local dial=1+.18*pulse
        fx.dialNode.scale=Vector3(dial,dial,dial)
    end
end

--- Pixel quads are drawn after the camera has moved (needs the final right/up vectors).
---@param fx table?
function F.Draw(fx)
    if fx and fx.mode=='pixel' then
        fx.sand:Draw();fx.spark:Draw();fx.burst:Draw()
    end
end

---@param fx table?
function F.Clear(fx)
    if not fx then return end
    for _,m in ipairs({fx.sand,fx.spark,fx.burst}) do if m then m:Clear() end end
end

---@param fx table?
function F.Dispose(fx)
    if not fx then return end
    F.Clear(fx)
    for _,m in ipairs({fx.sand,fx.spark,fx.burst}) do
        if m and m.node then pcall(m.node.Remove,m.node) end
    end
    for _,mat in ipairs({fx.dialMaterial,fx.sandMaterialA,fx.sandMaterialB}) do
        if mat then pcall(mat.Dispose,mat) end
    end
    fx.sand,fx.spark,fx.burst=nil,nil,nil
end
return F
