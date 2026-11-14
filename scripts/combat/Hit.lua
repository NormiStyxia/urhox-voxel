-- Analytic combat queries only. Never calls TimeObject or voxel destruction.
local H={}
local function Finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
---@param a Vector3
---@param b Vector3
---@param center Vector3
---@param radius number
---@return number? earliest segment fraction, including start-inside
function H.SegmentSphere(a,b,center,radius)
    local dx,dy,dz=b.x-a.x,b.y-a.y,b.z-a.z
    local ox,oy,oz=a.x-center.x,a.y-center.y,a.z-center.z
    local c=ox*ox+oy*oy+oz*oz-radius*radius
    if c<=0 then return 0 end
    local aa=dx*dx+dy*dy+dz*dz
    if aa<1e-12 then return nil end
    local bb=ox*dx+oy*dy+oz*dz
    local disc=bb*bb-aa*c
    if disc<0 then return nil end
    local t=(-bb-math.sqrt(disc))/aa
    if t>=0 and t<=1 then return t end
end
---@param target table
---@param info table
---@return table result independent of an enemy's reused scratch result
function H.Apply(target,info)
    if not target or not target.ApplyHit or not info or not Finite(info.dmg) or info.dmg<=0 then return {hit=false} end
    if info.poise~=nil and (not Finite(info.poise) or info.poise<0) then return {hit=false} end
    if info.armorBreak~=nil and (not Finite(info.armorBreak) or info.armorBreak<0) then return {hit=false} end
    -- Enemy owns weak/down/armor multipliers. Applying them here doubles damage.
    local before=target.hp
    local priorHitStop=target.hitStop or 0
    local result=target:ApplyHit(info) or {}
    return {hit=result.hit==true,killed=result.killed==true,partBroken=result.partBroken,
        damage=result.damage or (before and target.hp and math.max(0,before-target.hp) or nil),
        priorHitStop=priorHitStop,part=result.part or info.part,material=result.material or info.material or 'soft',
        broke=result.broke==true or result.partBroken~=nil,staggered=result.staggered==true,weak=result.weak==true}
end
---@param enemies table[]
---@param a Vector3
---@param b Vector3
---@param radius number
---@param skip table|nil
---@return table[] ordered by contact distance; disabled/hidden parts excluded
function H.Query(enemies,a,b,radius,skip)
    local hits={}
    for _,enemy in ipairs(enemies) do
        if not enemy.dead and enemy.active~=false and not (skip and skip[enemy]) then
            for _,shape in ipairs(enemy:GetHurtShapes()) do
                if shape.enabled~=false and (shape.radius or 0)>0 then
                    local t=H.SegmentSphere(a,b,shape.center,shape.radius+(radius or 0))
                    if t then hits[#hits+1]={enemy=enemy,shape=shape,t=t,pos=a+(b-a)*t} end
                end
            end
        end
    end
    table.sort(hits,function(a0,b0) return a0.t<b0.t end)
    return hits
end
-- Finite upright sector prism. Angles are FULL degrees; convex <=180 or
-- a 360-degree disc. This is gameplay geometry, independent of blade bones.
-- Return the nearest point in the zone to a point (in world metres).
local function ZonePoint(zone,p)
    local d=p-zone.origin
    local f=zone.forward
    local x,z=d.x*f.z-d.z*f.x,d.x*f.x+d.z*f.z
    local radius=zone.radius
    local half=math.rad(zone.angle*.5)
    local angle=math.atan(x,z)
    local qx,qz=x,z
    if zone.angle<360 and math.abs(angle)>half then
        local side=angle<0 and -1 or 1
        local sx,sz=math.sin(half)*side,math.cos(half)
        local along=math.max(0,math.min(radius,x*sx+z*sz))
        qx,qz=sx*along,sz*along
    else
        local length=math.sqrt(x*x+z*z)
        if length>radius then qx,qz=x*radius/length,z*radius/length end
    end
    return zone.origin+Vector3(qx*f.z+qz*f.x,
        math.max(zone.low,math.min(zone.high,d.y)),qz*f.z-qx*f.x)
end
-- shape: sphere {center,radius} or capsule {a,b,radius}; endpoints are world
-- positions. Existing enemies are spheres. Capsule minimization uses convex
-- distance, not discrete samples that could miss a thin crossing capsule.
local function ZoneShape(zone,shape)
    local r=shape.radius or 0
    if r<=0 or not Finite(r) then return nil end
    local center=shape.center
    if shape.a and shape.b then
        local a,b=shape.a,shape.b
        local delta=b-a
        local lo,hi=0,1
        local function Square(t)
            local c=a+delta*t
            return (ZonePoint(zone,c)-c):LengthSquared()
        end
        for _=1,36 do
            local l,h=lo+(hi-lo)/3,hi-(hi-lo)/3
            if Square(l)<Square(h) then hi=h else lo=l end
        end
        local t=(lo+hi)*.5
        if Square(0)<=Square(t) then t=0 end
        if Square(1)<Square(t) then t=1 end
        local source=zone.source or zone.origin+Vector3(0,.9,0)
        local length2=delta:LengthSquared()
        local near=length2>1e-12 and math.max(0,math.min(1,(source-a):DotProduct(delta)/length2)) or 0
        if Square(near)<=r*r+1e-9 then t=near end
        center=a+delta*t
    end
    if not center then return nil end
    local q=ZonePoint(zone,center)
    if (q-center):LengthSquared()>r*r+1e-9 then return nil end
    -- Prefer the near surface of the hurt shape, not its centre, for contact FX.
    -- At a grazing zone edge keep the actual overlap point instead of pulling
    -- a surface point outside the attack region.
    local source=zone.source or zone.origin+Vector3(0,.9,0)
    local toward=source-center
    local length=toward:Length()
    local contact=length>r and center+toward*(r/length) or source
    if (ZonePoint(zone,contact)-contact):LengthSquared()>1e-9 then contact=q end
    local normal=contact-center
    if normal:LengthSquared()<1e-10 then normal=-zone.forward else normal=normal:Normalized() end
    return contact,normal,(contact-source):LengthSquared()
end
-- Return all shape contacts sorted nearest first. Caller applies wall visibility
-- and per-swing target deduplication, so a hidden near part does not hide another
-- visible part, and multiple parts/overlapping zones cannot multiply damage.
function H.QueryZone(enemies,zone)
    local hits={}
    for _,enemy in ipairs(enemies) do
        if not enemy.dead and enemy.active~=false then
            for _,shape in ipairs(enemy:GetHurtShapes()) do
                if shape.enabled~=false then
                    local pos,normal,d2=ZoneShape(zone,shape)
                    if pos then hits[#hits+1]={enemy=enemy,shape=shape,pos=pos,normal=normal,distance2=d2} end
                end
            end
        end
    end
    table.sort(hits,function(a,b)
        if math.abs(a.distance2-b.distance2)>1e-9 then return a.distance2<b.distance2 end
        return tostring(a.shape.id)<tostring(b.shape.id)
    end)
    return hits
end
-- Cast adapter returns a segment fraction or nil, using actual voxel/terrain grid.
function H.Visible(a,b,cast)
    if not cast then return true end
    local t=cast(a,b)
    return t==nil or t>=1-1e-5
end
return H
