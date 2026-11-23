local Base = require('combat.enemies.EnemyBase')
local Wraith = setmetatable({}, {__index = Base})
Wraith.__index = Wraith
local S = Base.State
local SWEEP, BLINK = 'needle_sweep', 'stopped_clock'
local SWEEP_START, SWEEP_END = .10, .22
local RING_TIME, RING_RADIUS, RING_HALF_WIDTH = .70, 1.85, .30
local function unit(x) return math.max(0, math.min(1, x)) end

Wraith.Config = {
    kind = 'time_wraith', enemy = 'sentry', name = '时蚀灵体', model = 'TimeWraith',
    hp = 52, poise = 100, radius = .54, height = 2.56, speed = 2.25,
    aggro = 11, leash = 26, attackDistance = 1.6, defaultPart = 'mantle', voxelSize = .08, sculpt = {},
    parts = {
        {id = 'mantle', material = 'soft', x = 0, y = 1.20, z = 0, radius = .61},
        {id = 'hood', material = 'soft', x = 0, y = 1.79, z = .04, radius = .50},
    },
    attacks = {
        {name = SWEEP, telegraph = .56, duration = .32, recover = .58,
            warning = 'fan', range = 1.65, cosine = .5, damage = 9, poise = 7},
        {name = BLINK, telegraph = .48, duration = .90, recover = .90,
            warning = 'ring', range = RING_RADIUS, damage = 14, poise = 10},
    },
}

function Wraith.New(scene, world, terrain, combat, position, id)
    local self = setmetatable(Base.Create(scene, world, terrain, combat, Wraith.Config, position, id), Wraith)
    self.blinkSide = 1
    self.phaseFx = {kind = 'phase', material = 'core', dir = Vector3.UP, normal = Vector3.UP}
    return self
end

function Wraith:Chase(dt, target, distance)
    self:Face(target)
    local reach = self.attackIndex == 1 and 3.65 or self.config.attackDistance
    if distance <= reach then self:StartAttack()
    else self:Move(self.fx * self.config.speed * dt, self.fz * self.config.speed * dt) end
end

local function sparks(self, position)
    if self.particles then
        self.phaseFx.pos = Vector3(position.x, position.y + .48, position.z)
        self.particles:Emit(self, self.phaseFx)
    end
end

-- Base.Move checks the whole swept footprint. Roll back partial travel before
-- trying the opposite side so a blocked corridor cannot become a chain of hops.
function Wraith:BeginAttack()
    if self.attack.name ~= BLINK then return end
    local origin, aim = self.position, self.aimPoint
    local ax, az = aim.x - origin.x, aim.z - origin.z
    local distance = math.sqrt(ax * ax + az * az)
    local fx, fz = self.fx, self.fz
    if distance > .001 then fx, fz = ax / distance, az / distance end
    -- Choose a flank on the marked circle with a chord no longer than 2.35 m.
    -- A stationary target stays on the rim throughout the possible cast ranges.
    if distance > 2.35 + RING_RADIUS then self:FinishAttack(); return end
    local along = math.max(0, (distance ^ 2 + RING_RADIUS ^ 2 - 2.35 ^ 2) / (2 * math.max(.001, distance)))
    local flank = math.sqrt(math.max(0, RING_RADIUS ^ 2 - along ^ 2))
    local side = self.blinkSide
    for _ = 1, 2 do
        local dx = ax - fx * along + side * fz * flank
        local dz = az - fz * along - side * fx * flank
        if self:Move(dx, dz) then
            self.blinkSide = -side
            self.arrived = true
            self.warning.visible, self.warning.kind = true, 'ring'
            self.warning.radius, self.warning.step, self.warning.progress = RING_RADIUS, 6, 0
            sparks(self, origin)
            sparks(self, self.position)
            return
        end
        self.position = origin
        side = -side
    end
    self:FinishAttack()
end

function Wraith:AttackStep(dt, target)
    if self.attack.name == SWEEP then
        if self.stateTime >= SWEEP_START and self.stateTime - dt < SWEEP_END then
            -- Base includes a .32 m player radius. The advertised outer edge
            -- is already measured to the player's centre.
            self:DamagePlayer(target, self.attack.range - .32, self.attack.cosine, false)
        end
        return
    end
    if not self.arrived or self.ringSpent then return end
    self.warning.progress = unit(self.stateTime / RING_TIME)
    if self.stateTime >= .48 and self.stateTime - dt < .48 then self:EmitAttackCue('danger') end
    if self.stateTime + 1e-8 < RING_TIME then return end
    self.ringSpent = true
    self:EmitAttackCue('whoosh')
    local dx, dz = target.x - self.position.x, target.z - self.position.z
    if dx * dx + dz * dz >= (RING_RADIUS - RING_HALF_WIDTH) ^ 2 then
        self:DamagePlayer(target, RING_RADIUS + RING_HALF_WIDTH - .32, nil, true)
    end
end

function Wraith:ClearExtras()
    self.arrived, self.ringSpent = false, false
    self.warning.visible = false
    if self.particles then self.particles:ClearOwner(self) end
end

function Wraith:UpdatePose()
    Base.UpdatePose(self)
    if self.state == S.TELEGRAPH and self.attack.name == BLINK then
        -- The small departure mark belongs to the caster. The full-sized ring
        -- first appears at the actual, terrain-checked destination.
        self.warning.radius = .52
    end
end

function Wraith:SetState(state)
    if self.state == S.ATTACK and self.attack.name == BLINK and state ~= S.ATTACK then
        self:ClearExtras()
    end
    return Base.SetState(self, state)
end

function Wraith:SetActive(active)
    -- A sleeping encounter may resume without Reset. Discard its pending strike.
    if not active and not self.dead and (self.state == S.ATTACK or self.state == S.TELEGRAPH) then
        self:SetState(S.CHASE)
    end
    Base.SetActive(self, active)
end

function Wraith:Reset()
    if not Base.Reset(self) then return false end
    self.blinkSide = 1
    self.stoppedClock = nil
    return true
end

-- The winding and release share endpoints at each state boundary. Only the
-- single physical hand rotates; the bezel drifts independently around its hub.
local function handAngle(e)
    local t, name = e.stateTime, e.attack.name
    if e.state == S.TELEGRAPH then
        if name == BLINK then return -45 end
        return -75 * unit(t / .38)
    elseif e.state == S.ATTACK then
        if name == BLINK then return -45 + 180 * unit((t - RING_TIME) / .16) end
        return -75 + 185 * unit((t - .045) / .18)
    elseif e.state == S.RECOVER then
        local endAngle = name == BLINK and 135 or 110
        return endAngle * (1 - unit(t / e.attack.recover))
    end
    return (math.floor(e.poseAge * 2) % 12) * 30
end

local function bezelAngle(e)
    if e.attack.name == BLINK then
        if e.state == S.TELEGRAPH then return -12 * unit(e.stateTime / .24) end
        if e.state == S.ATTACK then return -12 + 72 * unit((e.stateTime - .56) / .28) end
        if e.state == S.RECOVER then return 60 * (1 - unit(e.stateTime / e.attack.recover)) end
    end
    return 5 * math.sin(e.poseAge * 1.4)
end

local function recoil(e)
    local t = unit(e.reaction.recoilAge / .24)
    return (1 - t) ^ 2 * math.cos(t * 2 * math.pi) * 42
end

function Wraith:OnDamaged()
    if self.hp <= 0 then
        -- The hand can be extended in front of the hood. Freeze its complete
        -- transform on the killing frame, including extension and pitch.
        self.stoppedClock = {}
        for _, id in ipairs({'clock_hand', 'clock_ring'}) do
            local p = {x=0,y=0,z=0,pitch=0,yaw=0,roll=0,sx=1,sy=1,sz=1}
            Wraith.Config.posePart(self, id, p)
            self.stoppedClock[id] = p
        end
    elseif self.arrived and self.knock.active then
        -- A melee shove breaks the locked ground seal before it could drift.
        self:FinishAttack()
    end
end

local deathOrder = {
    tail = .06, ribbon_back = .12, ribbon_r = .18, ribbon_l = .22,
    hourglass = .16, mantle = .32, sleeve_l = .40, sleeve_r = .44,
    face = .52, hood = .58, escapement = .66, clock_ring = .72, clock_hand = .78,
}

function Wraith.Config.posePart(e, id, p)
    if e.dead then
        local start = deathOrder[id] or .55
        local u = unit((e.deathTime - start) / .32)
        local size = math.max(.001, 1 - u * u * (3 - 2 * u))
        p.sx, p.sy, p.sz = size, size, size
        local held = e.stoppedClock and e.stoppedClock[id]
        if held then
            p.pitch, p.roll, p.yaw = held.pitch, held.roll, held.yaw
            p.x, p.y, p.z = held.x, held.y, held.z
            p.sx, p.sy, p.sz = held.sx * size, held.sy * size, held.sz * size
        elseif id == 'tail' then p.y = .23 * u
        elseif id == 'hourglass' then p.y = .13 * u end
        return
    end
    local t, state = e.stateTime, e.state
    local chase = state == S.CHASE or state == S.PATROL
    local wave = math.sin(e.poseAge * (chase and 5 or 2.6))
    p.y = wave * (chase and .055 or .025)
    if id == 'clock_hand' then p.roll = handAngle(e) - recoil(e)
    elseif id == 'clock_ring' then p.roll = bezelAngle(e)
    elseif id == 'tail' then p.pitch = (chase and -18 or 0) + 7 * wave
    elseif id == 'hourglass' then p.roll = 5 * wave
    elseif id == 'sleeve_r' or id == 'sleeve_l' then
        local side = id == 'sleeve_r' and 1 or -1
        p.pitch = (chase and -14 or 0) + side * wave * 9
    end
    if state ~= S.ATTACK and state ~= S.TELEGRAPH and state ~= S.RECOVER then return end
    if e.attack.name == SWEEP then
        local lean
        if state == S.TELEGRAPH then lean = -unit(t / .42)
        elseif state == S.ATTACK then lean = -1 + 2 * unit((t - .035) / .17)
        else lean = 1 - unit(t / e.attack.recover) end
        if id == 'clock_hand' then
            p.pitch, p.z = 38 * math.abs(lean), .37 * math.max(0, lean)
            p.sx, p.sy = 1 + .65 * math.max(0, lean), 1 + .65 * math.max(0, lean)
        elseif id == 'sleeve_r' or id == 'mantle' then p.yaw = 22 * lean end
    elseif state == S.TELEGRAPH then
        p.y = -.12 * unit(t / .35)
        if id == 'hourglass' then p.pitch = 70 * unit(t / .38) end
    elseif state == S.ATTACK then
        local reveal = unit(t / .16)
        p.sx, p.sz = .28 + .72 * reveal, .28 + .72 * reveal
        p.y = p.y + .16 * (1 - reveal)
        if id == 'ribbon_r' or id == 'ribbon_l' then
            local swell = unit((t - .28) / .42) * (1 - unit((t - RING_TIME) / .20))
            p.x = (id == 'ribbon_r' and 1 or -1) * swell * .43
            p.roll = swell * (id == 'ribbon_r' and 28 or -28)
        elseif id == 'hourglass' then p.pitch = 70 * (1 - unit(t / RING_TIME)) end
    elseif id == 'hood' or id == 'face' then p.pitch = 14 * (1 - unit(t / .90)) end
end

return Wraith
