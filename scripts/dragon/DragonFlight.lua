-- Flight handling in metres/seconds. Heading and travel direction are separate:
-- steering banks the body first, while momentum follows over a short interval.
local M = {}
local function Clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function Approach(x,y,rate,dt)
    return x + Clamp(y-x,-rate*dt,rate*dt)
end
local function Damp(x,y,k,dt) return x+(y-x)*(1-math.exp(-k*dt)) end
local function Wrap(a) return (a+180)%360-180 end

M.SPRINT_SPEED = 18.0
M.AIR_EDGE = 60.0 -- same arena as riding; reserve space for a soft stop

function M.Reset(L,yaw)
    L.travelYaw=yaw or L.yaw
    L.boost,L.stream,L.brake,L.edgeBrake=0,0,0,0
    L.tailStream=nil
end

-- Limit speed according to stopping distance along the actual travel direction.
-- Never clamp position or force a player-controlled turn back towards the centre.
function M.EdgeSpeed(L)
    local a=math.rad(L.travelYaw or L.yaw)
    local dx,dz=math.sin(a),math.cos(a)
    local cap=1e6
    for _,axis in ipairs({{L.pos.x,dx},{L.pos.z,dz}}) do
        local pos,dir=axis[1],axis[2]
        if math.abs(dir)>0.001 then
            local distance=(M.AIR_EDGE-4-(dir>0 and pos or -pos))/math.abs(dir)
            cap=math.min(cap,math.sqrt(2*6*math.max(0,distance)))
        end
    end
    return cap
end

function M.Update(L,inp,prm,dt,flapping)
    local braking=inp.move<0
    local sprint=flapping and inp.sprint and not braking
    L.boost=Approach(L.boost or 0,sprint and 1 or 0,sprint and 5 or 3,dt)
    local normal=prm.flySpeed*Clamp(1+inp.move*.45,.45,1.6)
    local top=math.max(M.SPRINT_SPEED,prm.flySpeed*1.65)
    local target=normal+(top-normal)*L.boost
    if not flapping then target=5.5 end
    if braking then target=prm.flySpeed*.55 end -- S always wins over Shift
    local cap=inp.free and M.EdgeSpeed(L) or 1e6
    L.edgeBrake=target>cap and 1 or 0
    target=math.min(target,cap)
    local rate
    if L.speed>target then
        rate=(braking or L.edgeBrake>0) and 9 or (flapping and 3.2 or .8)
    else
        rate=sprint and 8 or 2
    end
    if L.edgeBrake>0 then
        -- A high-speed re-entry near an edge may need stronger braking than S.
        local remaining=math.max(cap*cap/12,1)
        rate=math.max(rate,math.min(30,L.speed*L.speed/(2*remaining)))
    end
    L.speed=Approach(L.speed,target,rate,dt)
    L.stream=Damp(L.stream or 0,Clamp((L.speed-prm.flySpeed)/(top-prm.flySpeed),0,1),3,dt)
    L.tailStream=L.tailStream or {}
    for i=8,1,-1 do
        local lead=(i==1) and L.stream or (L.tailStream[i-1] or 0)
        L.tailStream[i]=Damp(L.tailStream[i] or 0,lead,8,dt)
    end
    L.brake=Damp(L.brake or 0,(braking or L.edgeBrake>0) and 1 or 0,5,dt)
    local bankTarget=inp.turn*(34+14*L.stream)
    -- Automatic circling belongs only to the unattended demo.
    if inp.turn==0 and not inp.free and L.pos:Length()>22 then
        local center=math.deg(math.atan(-L.pos.x,-L.pos.z))
        bankTarget=Clamp(Wrap(center-L.yaw)/30,-1,1)*26
    end
    L.bank=Damp(L.bank,bankTarget,inp.turn==0 and 4.5 or 3.2,dt)
    L.yawRate=Clamp(math.deg(9.8*math.tan(math.rad(L.bank))/math.max(L.speed,2)),-65,65)
end

function M.Move(L,dt,inertial)
    L.yaw=Wrap(L.yaw+L.yawRate*dt)
    if inertial then
        local rate=2.8-1.0*(L.stream or 0)+1.5*(L.brake or 0)
        local from=L.travelYaw or L.yaw
        L.travelYaw=Wrap(from+Wrap(L.yaw-from)*(1-math.exp(-rate*dt)))
    else
        M.Reset(L,L.yaw)
    end
    local a=math.rad(L.travelYaw)
    L.vel=Vector3(math.sin(a)*L.speed,0,math.cos(a)*L.speed)
    L.pos=L.pos+L.vel*dt
end

return M
