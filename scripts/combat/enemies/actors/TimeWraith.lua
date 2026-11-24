local Base = require('combat.enemies.EnemyBase')
local Field = require('combat.enemies.actors.TimeWraithField')
local Wraith = setmetatable({}, {__index = Base})
Wraith.__index = Wraith
local S = Base.State
local SWEEP, DOMAIN = 'needle_sweep', 'hourglass_field'
local SWEEP_START, SWEEP_END = .10, .22
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
        {name = DOMAIN, telegraph = Field.warning, duration = Field.duration, recover = .80,
            warning = 'ring', range = Field.radius, damage = 0, poise = 0},
    },
}

function Wraith.New(scene, world, terrain, combat, position, id)
    local self = setmetatable(Base.Create(scene, world, terrain, combat, Wraith.Config, position, id), Wraith)
    self.fieldAge = 0
    return self
end

function Wraith:Chase(dt, target, distance)
    self:Face(target)
    local reach = self.attackIndex == 1 and Field.radius or self.config.attackDistance
    if distance <= reach then self:StartAttack()
    else self:Move(self.fx * self.config.speed * dt, self.fz * self.config.speed * dt) end
end

-- The two caps and the outer rim are inclusive for the player's feet.
function Wraith:GetPlayerTimeScale(feet)
    if not feet or not self.active or self.dead or self.fieldStage ~= 'active' then return 1 end
    local c = self.fieldCenter
    local dx, dz = feet.x-c.x, feet.z-c.z
    if feet.y >= c.y+Field.bottom and feet.y <= c.y+Field.top and dx*dx+dz*dz <= Field.radius^2+1e-8 then return .5 end
    return 1
end

function Wraith:BeginAttack()
    if self.attack.name == DOMAIN and self.fieldStage == 'warn' then
        self.fieldStage, self.fieldAge = 'active', 0
        Field.Draw(self.fieldFx, self.fieldCenter, 'active', 0)
    end
end

function Wraith:AttackStep(dt, target)
    if self.attack.name == SWEEP and self.stateTime >= SWEEP_START and self.stateTime - dt < SWEEP_END then
        self:DamagePlayer(target, self.attack.range - .32, self.attack.cosine, false)
    end
end

function Wraith:ClearExtras()
    self.fieldStage, self.fieldCenter, self.fieldAge = nil, nil, 0
    Field.Draw(self.fieldFx, nil, nil, 0)
    self.warning.visible = false
end

function Wraith:UpdatePose()
    Base.UpdatePose(self)
    if self.attack.name == DOMAIN then self.warning.visible = false end
end

function Wraith:SetState(state)
    local changed = Base.SetState(self, state)
    if not changed or self.dead or self.state ~= state then return changed end
    if state == S.TELEGRAPH and self.attack.name == DOMAIN then
        local pos = self.position
        self.fieldCenter = Vector3(pos.x,pos.y,pos.z)
        self.fieldStage, self.fieldAge = 'warn', 0
        if self.scene and not self.fieldFx then self.fieldFx = Field.New(self.scene) end
        Field.Draw(self.fieldFx, self.fieldCenter, 'warn', 0)
    elseif state == S.RECOVER and self.fieldStage == 'active' then
        self.fieldStage, self.fieldAge = 'release', 0
        Field.Draw(self.fieldFx, self.fieldCenter, 'release', 0)
    elseif state ~= S.ATTACK and self.fieldStage then self:ClearExtras() end
    return true
end

function Wraith:Update(dt, target)
    -- The field expires in real seconds, even during hit-stop or a long frame.
    local stage = self.fieldStage
    if stage == 'active' or stage == 'release' then
        self.fieldAge = self.fieldAge + math.max(0, dt)
        if stage == 'active' and self.fieldAge+1e-8 >= Field.duration then
            local overflow = math.max(0, self.fieldAge-Field.duration)
            self:FinishAttack()
            self.fieldAge = overflow
        end
        if self.fieldStage == 'release' and self.fieldAge+1e-8 >= Field.release then self:ClearExtras() end
    end
    Base.Update(self, dt, target)
    if self.fieldStage == 'warn' then self.fieldAge = self.stateTime end
    if self.fieldStage then Field.Draw(self.fieldFx, self.fieldCenter, self.fieldStage, self.fieldAge) end
end

function Wraith:Destroy()
    Base.Destroy(self)
    if self.fieldFx then self.fieldFx.root:Remove(); self.fieldFx=nil end
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
    self.stoppedClock = nil
    return true
end

-- The winding and release share endpoints at each state boundary. Only the
-- single physical hand rotates; the bezel drifts independently around its hub.
local function handAngle(e)
    local t, name = e.stateTime, e.attack.name
    if e.state == S.TELEGRAPH then
        if name == DOMAIN then return -45 end
        return -75 * unit(t / .38)
    elseif e.state == S.ATTACK then
        if name == DOMAIN then return -45 + 30 * unit(t / Field.duration) end
        return -75 + 185 * unit((t - .045) / .18)
    elseif e.state == S.RECOVER then
        local endAngle = name == DOMAIN and -15 or 110
        return endAngle * (1 - unit(t / e.attack.recover))
    end
    return (math.floor(e.poseAge * 2) % 12) * 30
end

local function bezelAngle(e)
    if e.attack.name == DOMAIN then
        if e.state == S.TELEGRAPH then return -12 * unit(e.stateTime / .24) end
        if e.state == S.ATTACK then return -12 + 36 * unit(e.stateTime / Field.duration) end
        if e.state == S.RECOVER then return 24 * (1 - unit(e.stateTime / e.attack.recover)) end
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
        local beat = math.sin(t * 2.4)
        p.y = .045 + beat * .012
        if id == 'ribbon_r' or id == 'ribbon_l' then
            local side = id == 'ribbon_r' and 1 or -1
            p.x, p.roll = side * (.17 + beat * .04), side * (18 + beat * 4)
        elseif id == 'sleeve_r' or id == 'sleeve_l' then p.pitch = -36 + beat * 3
        elseif id == 'hourglass' then p.pitch = 70 + 110 * unit(t / Field.duration) end
    elseif id == 'hood' or id == 'face' then p.pitch = 14 * (1-unit(t/e.attack.recover))
    elseif id == 'hourglass' then p.pitch = 180 * (1-unit(t/e.attack.recover)) end
end

return Wraith
