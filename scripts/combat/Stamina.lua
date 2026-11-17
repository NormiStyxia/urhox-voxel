-- Combat stamina. Only drains while in combat: sprint drains per second,
-- heavy (cross slash) and plunge pay a fixed cost up front.
-- Numbers follow mature open-world action games (Genshin-like wheel scaled to
-- 100): ~8 s of combat sprint, 4 heavies or 5 plunges from full, a short pause
-- before regen, and an exhausted lock that stops sprinting until 30% is back.
---@class CombatStamina
---@field value number
---@field max number
---@field exhausted boolean
---@field idle number Seconds since the last spend.
---@field denyAt number Clock of the last failed spend (HUD flashes red).
---@field shownAt number Clock of the last change (HUD fades a full bar out).
---@field clock number
local S={};S.__index=S
S.MAX=100.0
S.COST={heavy=25.0,plunge=20.0}
S.SPRINT_RATE=12.0     -- per second while sprinting in combat
S.REGEN_RATE=30.0      -- per second once REGEN_DELAY has passed
S.REGEN_DELAY=.9
S.EXPLORE_RATE=60.0    -- out of combat: refills quickly, never drains
S.RECOVER=.30          -- exhausted lock lifts at this fraction
---@return CombatStamina
function S.New()
    return setmetatable({value=S.MAX,max=S.MAX,exhausted=false,idle=99.0,denyAt=-99.0,shownAt=-99.0,clock=0.0},S)
end
function S:Fraction() return self.value/self.max end
---@param kind string heavy | plunge
---@return boolean
function S:Spend(kind)
    local cost=S.COST[kind] or 0
    if self.exhausted or self.value+1e-6<cost then self.denyAt=self.clock;return false end
    self.value=math.max(0,self.value-cost);self.idle=0;self.shownAt=self.clock
    if self.value<=0 then self.exhausted=true end
    return true
end
function S:CanSprint() return not self.exhausted end
---@param dt number
---@param combat boolean
---@param sprinting boolean
function S:Update(dt,combat,sprinting)
    self.clock=self.clock+dt
    if combat and sprinting and not self.exhausted then
        self.value=math.max(0,self.value-S.SPRINT_RATE*dt);self.idle=0;self.shownAt=self.clock
        if self.value<=0 then self.exhausted=true;self.denyAt=self.clock end
        return
    end
    self.idle=self.idle+dt
    if self.value<self.max and (not combat or self.idle>=S.REGEN_DELAY) then
        self.value=math.min(self.max,self.value+(combat and S.REGEN_RATE or S.EXPLORE_RATE)*dt)
        self.shownAt=self.clock
    end
    if self.exhausted and self.value>=self.max*S.RECOVER then self.exhausted=false end
end
return S
