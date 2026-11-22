-- Pixel sand and sparks around the time catalyst.
local F={}
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

local function BuildPixel(fx)
    local VoxelFX=require('dragon.VoxelFX')
    fx.sand=VoxelFX.WorldMotes(fx.scene,'CatalystPixelSand',300,'square',true,fx.camera)
    fx.spark=VoxelFX.WorldMotes(fx.scene,'CatalystPixelSpark',90,'star',true,fx.camera)
    fx.burst=VoxelFX.WorldMotes(fx.scene,'CatalystPixelBurst',130,'square',true,fx.camera)
    fx.acc={0,0,0};fx.sparkAcc=0;fx.trailAcc=0
    fx.ready=true
end

function F.New(scene,camera)
    local fx={mode='off',shown=false,heads={0,TAU*.37,TAU*.71},
        cur={center=Vector3.ZERO,rot=Quaternion(),scale=1},scene=scene,camera=camera}
    local ok,err=pcall(BuildPixel,fx)
    if ok then fx.mode='pixel'
    else
        print('TimeCatalystFx: pixel particles unavailable: '..tostring(err))
        F.Dispose(fx)
    end
    return fx
end

function F.SetMode(fx,mode)
    fx.mode=(mode=='pixel' and fx.ready) and 'pixel' or 'off'
    if fx.mode=='off' then F.Clear(fx) end
    return fx.mode
end

function F.SetShown(fx,flag)
    if not fx or fx.shown==flag then return end
    fx.shown=flag
    if not flag then F.Clear(fx) end
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
    local ok,err=pcall(F.UpdateImpl,fx,dt,s)
    if not ok and fx.lastError~=tostring(err) then
        fx.lastError=tostring(err)
        print('TimeCatalystFx: update failed in mode '..fx.mode..': '..fx.lastError)
    end
end
function F.UpdateImpl(fx,dt,s)
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
    end
end

--- Pixel quads are drawn after the camera has moved (needs the final right/up vectors).
---@param fx table?
function F.Draw(fx)
    if fx and fx.mode=='pixel' and fx.sand then
        local ok,err=pcall(function() fx.sand:Draw();fx.spark:Draw();fx.burst:Draw() end)
        if not ok and fx.lastDrawError~=tostring(err) then
            fx.lastDrawError=tostring(err)
            print('TimeCatalystFx: pixel draw failed: '..fx.lastDrawError)
        end
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
    fx.sand,fx.spark,fx.burst=nil,nil,nil
end
return F
