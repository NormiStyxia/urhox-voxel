-- Fixed twelve-slot arrow pool. Swept contact is ordered against world geometry.
local Hit=require('combat.Hit')
---@class CombatProjectilePool
---@field opts table
---@field pool table[]
---@field serial number
local P={}; P.__index=P
function P.New(opts)
    local self=setmetatable({opts=opts or {},pool={},serial=0},P)
    for i=1,12 do self.pool[i]={active=false,index=i,hit={}} end
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
    p.damage,p.poise=(stats.attack or 8)*(full and 1.8 or (charge>=.3 and 1 or .5)),stats.poise or 6
    p.full=full
    p.pierce,p.hit,p.kind=full and 1 or 0,{},(stats.crystalRadius or 0)>0 and 'crystal' or 'arrow'
    p.crystalRadius=stats.crystalRadius or 0
    p.crystalDamage=stats.crystalDamageMultiplier and p.damage*stats.crystalDamageMultiplier or (stats.crystalDamage or 0)
    p.armorBreak=stats.armorBreak or 1
    if self.opts.draw then self.opts.draw(p,true) end
    return true
end
function P:Retire(p)
    p.active=false
    if self.opts.draw then self.opts.draw(p,false) end
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
            local info={dmg=p.damage,poise=p.poise,armorBreak=p.armorBreak,part=contact.shape.id,kind=p.kind,
                pos=contact.pos,dir=p.vel:Normalized(),source='player',full=p.full}
            local result=Hit.Apply(enemy,info)
            if result.hit then
                p.hit[enemy]=true
                if self.opts.hit then self.opts.hit(enemy,info,result,contact.shape.weak,true) end
                if p.crystalRadius>0 and p.crystalDamage>0 then
                    local exploded={[enemy]=true}
                    for _,near in ipairs(Hit.Query(self.opts.enemies(),contact.pos,contact.pos,p.crystalRadius)) do
                        if not exploded[near.enemy] and Hit.Visible(contact.pos,near.shape.center,self.opts.cast) then
                            exploded[near.enemy]=true
                            local burst={dmg=p.crystalDamage,poise=p.poise,armorBreak=p.armorBreak,part=near.shape.id,kind='crystal',
                                pos=near.shape.center,dir=p.vel:Normalized(),source='player'}
                            local blast=Hit.Apply(near.enemy,burst)
                            if blast.hit and self.opts.hit then self.opts.hit(near.enemy,burst,blast,near.shape.weak,true) end
                        end
                    end
                end
                if p.pierce>0 and not enemy.boss then p.pierce=p.pierce-1
                else p.pos=contact.pos; self:Retire(p); return end
            end
        end
    end
    if wall then
        p.pos=p.pos+(nextPos-p.pos)*wall
        p.embedded,p.age=true,0
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
            if p.age>=.8 then self:Retire(p) end
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
