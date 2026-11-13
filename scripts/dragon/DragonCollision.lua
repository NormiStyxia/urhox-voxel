-- Kinematic dragon hull. Root motion owns collision; animated tails/wings do not.
-- SphereCast handles travel. Grid occupancy is checked separately for recovery,
-- because the query API does not specify initial-overlap behaviour.
local M = {}
---@alias DragonHullBall {offset:Vector3,radius:number}
M.MASK = 0xffffffff & ~2
local SKIN = .04
local function Clamp(v,a,b) return math.max(a,math.min(b,v)) end
function M.Angle(a) return (a+180)%360-180 end

---@param rig DragonRig
---@return DragonHullBall[]
function M.Hull(rig)
    local hull = {}
    for _,zone in ipairs(rig.spec.HIT_ZONES) do
        if zone.name=='chest' or zone.name=='torso' or zone.name=='pelvis' then
            local p,off=rig.pivots[zone.bone],zone.offset
            -- HIT_ZONES and pivots already contain the variant's scale/deformation.
            hull[#hull+1]={offset=Vector3(p[1]+off[1],p[2]+off[2],p[3]+off[3]),
                radius=zone.radius+.10*rig.size}
        end
    end
    assert(#hull==3,'Dragon collision needs the three authored torso hit zones')
    return hull
end

-- Earliest blocking contact; exiting an existing contact must remain possible.
---@param world VoxelPhysicsWorld
---@param hull DragonHullBall[]
---@param pos Vector3
---@param yaw number
---@param move Vector3
---@return number, Vector3
function M.Sweep(world,hull,pos,yaw,move)
    local distance=move:Length()
    if distance<1e-6 then return 1,Vector3.ZERO end
    local direction=move/distance
    local q=Quaternion(yaw,Vector3.UP)
    local fraction,normal=1,Vector3.ZERO
    for _,ball in ipairs(hull) do
        local hit=world:SphereCast(Sphere(pos+q*ball.offset,ball.radius),direction,distance+SKIN,M.MASK)
        if hit.hit and hit.normal:DotProduct(direction)<-1e-5 then
            local f=Clamp((hit.distance-SKIN)/distance,0,1)
            if f<fraction then fraction,normal=f,hit.normal end
        end
    end
    return fraction,normal
end

---@param world VoxelPhysicsWorld
---@param hull DragonHullBall[]
---@param pos Vector3
---@param yaw number
---@param move Vector3
---@return Vector3, Vector3
function M.Slide(world,hull,pos,yaw,move)
    local current,remaining=pos,move
    ---@type Vector3[]
    local planes={}
    for _=1,4 do
        if remaining:LengthSquared()<1e-10 then break end
        local fraction,normal=M.Sweep(world,hull,current,yaw,remaining)
        local advanced=current+remaining*fraction
        current=advanced
        if fraction>=1 then break end
        local rest=remaining*(1-fraction)
        remaining=rest
        planes[#planes+1]=normal
        -- Keep every contact plane: a second wall must not push us into the first.
        for _pass=1,3 do
            for _,n in ipairs(planes) do
                local into=remaining:DotProduct(n)
                if into<0 then local projected=remaining-n*into; remaining=projected end
            end
        end
        for _,n in ipairs(planes) do
            if remaining:DotProduct(n)<-1e-5 then remaining=Vector3.ZERO; break end
        end
    end
    local free=move
    for _=1,3 do for _,n in ipairs(planes) do
        local into=free:DotProduct(n)
        if into<0 then local projected=free-n*into; free=projected end
    end end
    for _,n in ipairs(planes) do
        if free:DotProduct(n)<-1e-5 then free=Vector3.ZERO; break end
    end
    return current,free
end

-- Separate rotation from translation and cover each arc with an inflated chord.
---@param world VoxelPhysicsWorld
---@param hull DragonHullBall[]
---@param pos Vector3
---@param yaw number
---@param target number
---@return number
function M.Turn(world,hull,pos,yaw,target)
    local angle=M.Angle(target-yaw)
    local count=math.max(1,math.ceil(math.abs(angle)/3))
    local step=angle/count
    local current=yaw
    for _=1,count do
        local a,b=Quaternion(current,Vector3.UP),Quaternion(current+step,Vector3.UP)
        local fraction=1
        for _,ball in ipairs(hull) do
            local from,to=a*ball.offset,b*ball.offset
            local move=to-from
            local distance=move:Length()
            if distance>1e-6 then
                local radial=math.sqrt(ball.offset.x^2+ball.offset.z^2)
                local sagitta=radial*(1-math.cos(math.rad(step)*.5))
                local hit=world:SphereCast(Sphere(pos+from,ball.radius+sagitta),move/distance,distance+SKIN,M.MASK)
                if hit.hit and hit.normal:DotProduct(move/distance)<-1e-5 then
                    fraction=math.min(fraction,Clamp((hit.distance-SKIN)/distance,0,1))
                end
            end
        end
        current=current+step*fraction
        if fraction<1 then break end
    end
    return M.Angle(current)
end

-- Exact sphere/occupied-voxel intersection, including rotated/scaled volumes.
-- A budget overrun is UNKNOWN (nil), never a certified clear/safe position.
---@param world VoxelPhysicsWorld
---@param hull DragonHullBall[]
---@param pos Vector3
---@param yaw number
---@param budget {left:number}
---@return boolean|nil, Vector3|nil, number|nil
function M.Clear(world,hull,pos,yaw,budget)
    local q=Quaternion(yaw,Vector3.UP)
    for i=0,world:GetVolumeCount()-1 do -- Native indexed accessor is zero-based.
        local volume=world:GetVolume(i)
        if volume and (volume.collisionLayer & M.MASK)~=0 and volume.collisionMask~=0 and volume:IsCollidable() then
            local node,grid=volume:GetNode(),volume:GetGrid()
            if node and grid then
                local size,scale=volume.voxelSize,node.worldScale
                local sx,sy,sz=math.abs(scale.x),math.abs(scale.y),math.abs(scale.z)
                if size>0 and math.min(sx,sy,sz)>1e-6 then
                    local dims=grid:GetDimensions()
                    for _,ball in ipairs(hull) do
                        local center=pos+q*ball.offset
                        local p=node:WorldToLocal(center)
                        local r=math.max(.001,ball.radius-.005)
                        local near=Vector3(Clamp(p.x,0,dims.x*size),Clamp(p.y,0,dims.y*size),Clamp(p.z,0,dims.z*size))
                        if (center-node:LocalToWorld(near)):LengthSquared()<r*r then
                            local x0,x1=math.max(0,math.floor((p.x-r/sx)/size)),math.min(dims.x-1,math.floor((p.x+r/sx)/size))
                            local y0,y1=math.max(0,math.floor((p.y-r/sy)/size)),math.min(dims.y-1,math.floor((p.y+r/sy)/size))
                            local z0,z1=math.max(0,math.floor((p.z-r/sz)/size)),math.min(dims.z-1,math.floor((p.z+r/sz)/size))
                            for z=z0,z1 do for y=y0,y1 do for x=x0,x1 do
                                budget.left=budget.left-1
                                if budget.left<0 then return nil end
                                if grid:IsSolid(x,y,z) then
                                    local closest=Vector3(Clamp(p.x,x*size,(x+1)*size),Clamp(p.y,y*size,(y+1)*size),Clamp(p.z,z*size,(z+1)*size))
                                    local delta=center-node:LocalToWorld(closest)
                                    local distance=delta:Length()
                                    if distance<r then
                                        -- Deep containment has no reliable surface normal; use a
                                        -- revalidated safe position instead of inventing an exit.
                                        return false,distance>1e-6 and delta/distance or Vector3.ZERO,r-distance
                                    end
                                end
                            end end end
                        end
                    end
                end
            end
        end
    end
    return true
end

return M
