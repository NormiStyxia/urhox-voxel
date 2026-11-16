-- Fixed twelve-slot arrow pool. Swept contact is ordered against world geometry.
local Hit=require('combat.Hit')
---@class CombatProjectilePool
---@field opts table
---@field pool table[]
---@field serial number
local P={}; P.__index=P
P.STEP=1/120
P.DRAG=-20*math.log(.99)
local EMPTY={}
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
function P.Power(u) u=clamp(u or 0,0,1);return (u*u+2*u)/3 end
-- Shared by flight and the centre-trajectory predictor (no random draw here).
function P.Integrate(pos,vel,dt)
    local a=math.exp(-P.DRAG*dt)
    local k=(1-a)/P.DRAG
    return pos+vel*k+Vector3(0,-20*(dt-k)/P.DRAG,0),vel*a+Vector3(0,-20*k,0)
end
local function damage(p,speed)
    return p.attack*1.5*clamp(speed/p.fullSpeed,.1,1.05)*(p.critical and 1.2 or 1)
end
function P.New(opts)
    local self=setmetatable({opts=opts or {},pool={},serial=0},P)
    for i=1,12 do self.pool[i]={active=false,index=i,hit={},exploded={},hits={},hitPool={},bursts={},burstPool={},
        info={},burst={},sound={},history={Vector3(),Vector3(),Vector3(),Vector3()},
        wallImpact={kind='hit',material='stone'}}
        for j=1,64 do self.pool[i].hitPool[j]={};self.pool[i].burstPool[j]={} end
    end
    return self
end
function P:Fire(origin,dir,charge,stats,tip)
    stats=stats or EMPTY
    charge=clamp(charge or 0,0,1)
    local power=P.Power(charge)
    if power<.1 or dir:LengthSquared()<1e-10 then return false end
    local slot
    for _,p in ipairs(self.pool) do if not p.active then slot=p; break end end
    if not slot then return false end -- never evict a live arrow or allocate a 13th
    local p=slot
    local full=charge>=1
    local fullSpeed=60*(stats.projectileSpeed or 1)
    local speed=power*fullSpeed
    local random=self.opts.random or math.random
    local spread=(1-.7*charge)*(stats.spread or 1)
    local yaw,pitch=(random()-random())*spread,(random()-random())*spread
    local rotated=Quaternion(pitch,yaw,0)*dir:Normalized()
    local direction=Vector3(rotated.x,rotated.y,rotated.z):Normalized()
    self.serial=self.serial+1
    p.active,p.serial,p.pos,p.vel=true,self.serial,origin,direction*speed
    p.distance,p.range,p.embedded,p.age=0,stats.range or 64,false,0
    p.elapsed,p.accumulator,p.fullSpeed,p.attack,p.power=0,0,fullSpeed,stats.attack or 8,power
    p.critical,p.renderPos,p.previousPos=full,origin,origin
    p.drawU,p.impactSpeed=charge,nil
    p.historyCount,p.historyWrite=0,0
    p.historyTravel,p.historyHead=0,origin
    p.swingId='arrow:'..self.serial
    p.attached,p.part,p.bone,p.localPos,p.localDir=nil,nil,nil,nil,nil
    p.damage,p.poise=damage(p,speed),(stats.poise or 6)*(.4+.6*power)
    p.full=full
    p.tier=full and 'full' or (charge>=.5 and 'mid' or 'weak')
    p.pierce,p.kind=math.max(0,stats.pierce or 0),(stats.crystalRadius or 0)>0 and 'crystal' or 'arrow'
    for enemy in pairs(p.hit) do p.hit[enemy]=nil end
    p.crystalRadius=stats.crystalRadius or 0
    p.crystalDamageMultiplier=stats.crystalDamageMultiplier or 0
    p.crystalDamage=p.damage*p.crystalDamageMultiplier
    p.armorBreak=stats.armorBreak or 1
    p.initialSweep=tip
    if tip then
        self:Step(p,0);p.renderPos,p.previousPos,p.historyHead=p.pos,p.pos,p.pos
        p.distance=0 -- the initial, already-nocked arrow span is not flight travel
    end
    p.sound.pos,p.sound.tier,p.sound.material,p.sound.hitId=origin,p.tier,nil,nil
    if self.opts.audio then self.opts.audio.Play('bow_fire',p.sound) end
    if self.opts.log then self.opts.log('arrow-fire','Combat: arrow fire tier=%s speed=%.2f',p.tier,speed) end
    if self.opts.draw then self.opts.draw(p,p.active) end
    return true,p -- optional observer reads the actual initialized shot
end
function P:Retire(p)
    p.active=false
    if self.opts.draw then self.opts.draw(p,false) end
end
function P:Embed(p,contact)
    p.embedded,p.age,p.pos=true,0,contact.pos
    p.attached,p.part=contact.enemy,contact.shape.id
    p.attachOffset=contact.pos-contact.shape.center
    local part=contact.enemy.parts and contact.enemy.parts[p.part]
    local bones=contact.enemy.visual and contact.enemy.visual.bones
    p.bone=bones and bones[part and part.spec.bone or p.part]
    if p.bone then
        p.localPos=p.bone:WorldToLocal(contact.pos)
        p.localDir=p.bone.worldRotation:Inverse()*p.vel:Normalized()
    end
end
function P:Step(p,dt)
    local nextPos,nextVel=P.Integrate(p.pos,p.vel,dt)
    if p.initialSweep then nextPos=p.initialSweep;p.initialSweep=nil end
    p.previousPos=p.pos
    local segment=nextPos-p.pos
    local length=segment:Length()
    local fraction=length>0 and math.min(1,(p.range-p.distance)/length) or 1
    nextPos=p.pos+segment*fraction
    local wall,worldHit
    if self.opts.cast then wall,worldHit=self.opts.cast(p.pos,nextPos) end
    local hits=Hit.Query(self.opts.enemies and self.opts.enemies() or EMPTY,p.pos,nextPos,0,p.hit,p.hits,p.hitPool)
    for _,contact in ipairs(hits) do
        local enemy=contact.enemy
        if wall and contact.t>=wall-1e-8 then break end -- solid terrain wins numerical ties
        if not p.hit[enemy] then
            local _,impactVel=P.Integrate(p.pos,p.vel,dt*fraction*contact.t)
            p.impactSpeed=impactVel:Length()
            p.damage=damage(p,impactVel:Length())
            local info=p.info
            info.dmg,info.poise,info.armorBreak=p.damage,p.poise,p.armorBreak
            info.part,info.kind,info.tier,info.clip=contact.shape.id,p.kind,p.tier,'bow_release'
            info.pos,info.dir,info.source,info.full=contact.pos,impactVel:Normalized(),'player',p.full
            info.critical,info.knockback=p.critical,p.critical and .16 or .08
            info.material,info.normal=contact.shape.material or 'soft',(contact.pos-contact.shape.center):Normalized()
            info.swingId=p.swingId
            local result=Hit.Apply(enemy,info)
            if result.hit then
                p.hit[enemy]=true
                -- Enemy owns weak/armor/down scaling. Use the resolved hit, but
                -- keep p.damage unchanged so a piercing arrow cannot compound it.
                p.crystalDamage=(result.damage or p.damage)*p.crystalDamageMultiplier
                if self.opts.hit then self.opts.hit(enemy,info,result,contact.shape.weak,true) end
                if p.crystalRadius>0 and p.crystalDamage>0 then
                    local exploded=p.exploded
                    for target in pairs(exploded) do exploded[target]=nil end
                    exploded[enemy]=true
                    for _,near in ipairs(Hit.Query(self.opts.enemies(),contact.pos,contact.pos,p.crystalRadius,nil,p.bursts,p.burstPool)) do
                        if not exploded[near.enemy] and Hit.Visible(contact.pos,near.shape.center,self.opts.cast) then
                            exploded[near.enemy]=true
                            local burst=p.burst
                            burst.dmg,burst.poise,burst.armorBreak=p.crystalDamage,p.poise,p.armorBreak
                            burst.part,burst.kind,burst.tier,burst.clip=near.shape.id,'crystal',p.tier,'crystal_burst'
                            burst.pos,burst.dir,burst.source,burst.full=near.pos,info.dir,'player',p.full
                            burst.material,burst.swingId,burst.critical=near.shape.material or 'soft',p.swingId,p.critical
                            local blast=Hit.Apply(near.enemy,burst)
                            if blast.hit and self.opts.hit then self.opts.hit(near.enemy,burst,blast,near.shape.weak,true) end
                        end
                    end
                end
                if p.pierce>0 and not enemy.boss then p.pierce=p.pierce-1
                else p.vel=impactVel;self:Embed(p,contact); return end
            end
        end
    end
    if wall then
        local _,impactVel=P.Integrate(p.pos,p.vel,dt*fraction*wall)
        p.vel=impactVel
        p.pos=p.pos+(nextPos-p.pos)*wall
        p.embedded,p.age=true,0
        local destroyed=false
        if self.opts.wallHit then
            local impact=p.wallImpact
            impact.pos,impact.dir,impact.tier=p.pos,p.vel:Normalized(),'arrow_'..p.tier
            impact.worldHit,impact.swingId=worldHit,p.swingId
            destroyed=self.opts.wallHit(impact)==true
        end
        p.sound.pos,p.sound.material,p.sound.hitId=p.pos,'stone',p.swingId
        if self.opts.audio then self.opts.audio.Play('arrow_hit',p.sound) end
        if destroyed then self:Retire(p) end -- no arrow hanging in the newly empty cell
    else
        p.distance=p.distance+length*fraction
        p.pos=nextPos
        p.vel=nextVel
        if fraction<1 or p.distance>=p.range then self:Retire(p); return end
    end
end
function P:Update(dt)
    for _,p in ipairs(self.pool) do if p.active then
        if p.embedded then
            p.age=p.age+dt
            if p.age>=.8 then self:Retire(p)
            elseif p.attached then
                local enemy,shape=p.attached,nil
                if not enemy.dead and enemy.active~=false then
                    for _,h in ipairs(enemy:GetHurtShapes()) do if h.id==p.part and h.enabled~=false then shape=h; break end end
                end
                local part=enemy.parts and enemy.parts[p.part]
                if not shape or (part and part.broken) then self:Retire(p)
                else
                    if p.bone then
                        p.pos=p.bone:LocalToWorld(p.localPos)
                        p.vel=p.bone.worldRotation*p.localDir
                    else p.pos=shape.center+p.attachOffset end
                end
            end
            if p.active and self.opts.draw then self.opts.draw(p,true) end
        else
            p.accumulator=p.accumulator+math.max(dt,0)
            while p.accumulator>=P.STEP-1e-10 and p.active and not p.embedded do
                self:Step(p,P.STEP)
                p.elapsed=p.elapsed+P.STEP
                p.accumulator=math.max(0,p.accumulator-P.STEP)
                if p.elapsed>=8 then self:Retire(p) end
            end
            p.renderPos=p.embedded and p.pos or p.previousPos+(p.pos-p.previousPos)*(p.accumulator/P.STEP)
            -- Distance samples of the rendered trajectory, not four rigid bars
            -- spaced one simulation frame apart (which leaves gaps at 60m/s).
            local segment=p.renderPos-p.historyHead
            local length=segment:Length()
            if not p.embedded and length>1e-8 then
                local at=.12-p.historyTravel
                while at<=length do
                    p.historyWrite=p.historyWrite%4+1
                    p.history[p.historyWrite]=p.historyHead+segment*(at/length)
                    p.historyCount=math.min(4,p.historyCount+1)
                    at=at+.12
                end
                p.historyTravel=(p.historyTravel+length)%.12
                p.historyHead=p.renderPos
            end
            if p.active and self.opts.draw then self.opts.draw(p,true) end
        end
    end end
end
function P:Clear() for _,p in ipairs(self.pool) do if p.active then self:Retire(p) end end end

-- Bounded, incremental centre-trajectory prediction. Budget is supplied by the
-- scene's shared decorative-ray allowance; never steals gameplay collision work.
function P.NewPrediction()
    local p={valid=false,working=false,hits={},pool={},points={},count=0,nextAt=0}
    for i=1,24 do p.points[i]=Vector3() end
    for i=1,64 do p.pool[i]={} end
    return p
end
function P.Predict(p,origin,dir,u,stats,now,low,budget,cast,enemies)
    local changed=p.origin and ((origin-p.origin):LengthSquared()>.0009 or dir:DotProduct(p.direction)<.9999 or math.abs(u-p.u)>.025)
    if changed then p.valid,p.working,p.nextAt=false,false,0 end
    if not p.working and now>=p.nextAt then
        p.valid,p.working=false,P.Power(u)>=.1
        p.origin,p.direction,p.u,p.pos=origin,dir,u,origin
        p.vel=dir*(60*(stats.projectileSpeed or 1)*P.Power(u))
        p.elapsed,p.distance,p.count=0,0,0
        p.range,p.limit=stats.range or 64,low and 12 or 24
        p.nextAt=now+(low and .2 or 1/15)
    end
    local used=0
    while p.working and used<budget do
        -- At most .25m per collision chord, same analytic equations as flight.
        local h=math.min(P.STEP,.25/math.max(.1,p.vel:Length()+20*P.STEP))
        local nextPos,nextVel=P.Integrate(p.pos,p.vel,h)
        local delta=nextPos-p.pos
        local distance=delta:Length()
        if p.distance+distance>p.range then nextPos=p.pos+delta*((p.range-p.distance)/distance) end
        local wall,available
        if cast then wall,available=cast(p.pos,nextPos) end
        if available==false then p.valid,p.working=false,false;return used+1 end
        local hits=Hit.Query(enemies or EMPTY,p.pos,nextPos,0,nil,p.hits,p.pool)
        local t=wall
        if hits[1] and (not t or hits[1].t<t) then t=hits[1].t end
        used=used+1
        if t then p.contact=p.pos+(nextPos-p.pos)*t;p.valid=true;p.working=false
        else
            p.pos,p.vel=nextPos,nextVel
            p.distance,p.elapsed=p.distance+distance,p.elapsed+h
            local index=math.min(p.limit,math.floor(p.distance/p.range*(p.limit-1))+1)
            p.points[index]=nextPos;p.count=math.max(p.count,index)
            if p.distance>=p.range or p.elapsed>=8 then p.working=false end
        end
    end
    return used
end
return P
