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
-- Cast adapter returns a segment fraction or nil, using actual voxel/terrain grid.
function H.Visible(a,b,cast)
    if not cast then return true end
    local t=cast(a,b)
    return t==nil or t>=1-1e-5
end
return H
