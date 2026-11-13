-- Fixed twelve-slot arrow pool. Swept contact is ordered against world geometry.
local Hit=require('combat.Hit')
---@class CombatProjectilePool
---@field opts table
---@field pool table[]
---@field serial number
local P={}; P.__index=P
function P.New(opts)
    local self=setmetatable({opts=opts or {},pool={},serial=0},P)
    for i=1,12 do self.pool[i]={active=false,index=i,hit={},wallImpact={kind='hit',material='stone'}} end
    return self
end
function P:Fire(origin,dir,charge,stats)
    local slot
    for _,p in ipairs(self.pool) do if not p.active then slot=p; break end end
    if not slot then return false end -- never evict a live arrow or allocate a 13th
    local p=slot
    local full=charge>=.8
    local speed=(full and 44 or (charge>=.3 and 30 or 18))*(stats.projectileSpeed or 1)
    self.serial=self.serial+1
    p.active,p.serial,p.pos,p.vel=true,self.serial,origin,dir:Normalized()*speed
    p.distance,p.range,p.embedded,p.age=0,stats.range or 36,false,0
    p.attached,p.part,p.bone,p.localPos,p.localDir=nil,nil,nil,nil,nil
    p.damage,p.poise=(stats.attack or 8)*(full and 1.8 or (charge>=.3 and 1 or .5)),stats.poise or 6
    p.full=full
    p.tier=full and 'full' or (charge>=.3 and 'mid' or 'weak')
    p.pierce,p.hit,p.kind=full and 1 or 0,{},(stats.crystalRadius or 0)>0 and 'crystal' or 'arrow'
    p.crystalRadius=stats.crystalRadius or 0
    p.crystalDamageMultiplier=stats.crystalDamageMultiplier or 0
    p.crystalDamage=p.damage*p.crystalDamageMultiplier
    p.armorBreak=stats.armorBreak or 1
    if self.opts.audio then self.opts.audio.Play('bow_fire',{pos=origin,tier=p.tier}) end
    if self.opts.log then self.opts.log('arrow-fire','Combat: arrow fire tier=%s speed=%.2f',p.tier,speed) end
    if self.opts.draw then self.opts.draw(p,true) end
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
    if self.opts.draw then self.opts.draw(p,true) end
end
function P:Step(p,dt)
    local nextPos=p.pos+p.vel*dt+Vector3(0,-3*dt*dt,0)
    local segment=nextPos-p.pos
    local length=segment:Length()
    local fraction=length>0 and math.min(1,(p.range-p.distance)/length) or 1
    nextPos=p.pos+segment*fraction
    local wall=self.opts.cast and self.opts.cast(p.pos,nextPos) or nil
    local hits=Hit.Query(self.opts.enemies and self.opts.enemies() or {},p.pos,nextPos,0,p.hit)
    for _,contact in ipairs(hits) do
        local enemy=contact.enemy
        if wall and contact.t>=wall then break end -- solid terrain wins ties
        if not p.hit[enemy] then
            local info={dmg=p.damage,poise=p.poise,armorBreak=p.armorBreak,part=contact.shape.id,kind=p.kind,tier=p.tier,clip='bow_release',
                pos=contact.pos,dir=p.vel:Normalized(),source='player',full=p.full,
                material=contact.shape.material or 'soft',normal=(contact.pos-contact.shape.center):Normalized(),
                swingId='arrow:'..p.serial}
            local result=Hit.Apply(enemy,info)
            if result.hit then
                p.hit[enemy]=true
                -- Enemy owns weak/armor/down scaling. Use the resolved hit, but
                -- keep p.damage unchanged so a piercing arrow cannot compound it.
                p.crystalDamage=(result.damage or p.damage)*p.crystalDamageMultiplier
                if self.opts.hit then self.opts.hit(enemy,info,result,contact.shape.weak,true) end
                if p.crystalRadius>0 and p.crystalDamage>0 then
                    local exploded={[enemy]=true}
                    for _,near in ipairs(Hit.Query(self.opts.enemies(),contact.pos,contact.pos,p.crystalRadius)) do
                        if not exploded[near.enemy] and Hit.Visible(contact.pos,near.shape.center,self.opts.cast) then
                            exploded[near.enemy]=true
                            local burst={dmg=p.crystalDamage,poise=p.poise,armorBreak=p.armorBreak,part=near.shape.id,kind='crystal',tier=p.tier,clip='crystal_burst',
                                pos=near.pos,dir=p.vel:Normalized(),source='player',full=p.full,
                                material=near.shape.material or 'soft',swingId='arrow:'..p.serial}
                            local blast=Hit.Apply(near.enemy,burst)
                            if blast.hit and self.opts.hit then self.opts.hit(near.enemy,burst,blast,near.shape.weak,true) end
                        end
                    end
                end
                if p.pierce>0 and not enemy.boss then p.pierce=p.pierce-1
                else self:Embed(p,contact); return end
            end
        end
    end
    if wall then
        p.pos=p.pos+(nextPos-p.pos)*wall
        p.embedded,p.age=true,0
        if self.opts.wallHit then
            local impact=p.wallImpact
            impact.pos,impact.dir,impact.tier=p.pos,p.vel:Normalized(),'arrow_'..p.tier
            self.opts.wallHit(impact)
        end
        if self.opts.audio then self.opts.audio.Play('arrow_hit',{pos=p.pos,material='stone',hitId='arrow:'..p.serial}) end
    else
        p.distance=p.distance+length*fraction
        p.pos=nextPos
        p.vel=p.vel+Vector3(0,-6*dt,0)
        if fraction<1 or p.distance>=p.range then self:Retire(p); return end
    end
    if self.opts.draw then self.opts.draw(p,true) end
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
                    if self.opts.draw then self.opts.draw(p,true) end
                end
            end
        else
            -- Bound chord error to <2mm without skipping elapsed simulation time.
            local left=math.min(math.max(dt,0),.5)
            while left>0 and p.active and not p.embedded do
                local step=math.min(left,1/30); self:Step(p,step); left=left-step
            end
        end
    end end
end
function P:Clear() for _,p in ipairs(self.pool) do if p.active then self:Retire(p) end end end
return P
