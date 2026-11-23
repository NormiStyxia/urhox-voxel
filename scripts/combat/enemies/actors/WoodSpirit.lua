local Base = require('combat.enemies.EnemyBase')
local WoodSpirit = setmetatable({}, {__index = Base})
WoodSpirit.__index = WoodSpirit
local S = Base.State
local min, max, sin, cos = math.min, math.max, math.sin, math.cos
local headbutt = {name='stump_headbutt', telegraph=.46, duration=.28, recover=.55,
    warning='fan', range=1.32, hitRange=.48, cosine=.5, travel=.52,
    start=.05, finish=.19, damage=9, poise=7}
local pounce = {name='root_pounce', telegraph=.90, duration=.54, recover=1.08,
    warning='line', range=4.22, hitRange=.40, cosine=.35, travel=3.50,
    start=.06, finish=.46, damage=16, poise=12}
WoodSpirit.Config = {kind='wood_spirit', enemy='beetle', name='木灵', model='WoodSpirit',
    hp=42, radius=.45, height=1.34, speed=2.15, aggro=9, leash=23,
    attackDistance=pounce.range, defaultPart='body', parts={{id='body', y=.73, radius=.58, material='soft'}},
    attacks={headbutt,pounce}}

function WoodSpirit.New(scene, world, terrain, combat, position, id)
    return setmetatable(Base.Create(scene, world, terrain, combat, WoodSpirit.Config, position, id), WoodSpirit)
end

function WoodSpirit:Chase(dt, target, distance)
    self:Face(target)
    local nextIndex = self.attackIndex % 2 + 1
    if self.attackIndex == 0 and distance > headbutt.range then nextIndex = 2 end
    if distance <= self.config.attacks[nextIndex].range then
        if self:CanTelegraph() then
            self.attackIndex = nextIndex - 1
            self:StartAttack()
        end
    else
        self:Move(self.fx*self.config.speed*dt, self.fz*self.config.speed*dt)
    end
end

-- Only the overlap of this update with the contact window can move or hurt.
-- Sample along the actual travelled path so a coarse frame cannot skip a player or a wall.
function WoodSpirit:AttackStep(dt, target, knocked)
    local a = self.attack
    local elapsed = min(self.stateTime, a.finish) - max(self.stateTime-dt, a.start)
    if elapsed <= 0 or knocked then return end
    local distance = a.travel * elapsed / (a.finish-a.start)
    local steps = math.ceil(distance/.10)
    local step = distance / steps
    self:DamagePlayer(target, a.hitRange, a.cosine)
    for _ = 1, steps do
        if not self.active or self.dead or self.state ~= S.ATTACK then return end
        if not self:Move(self.fx*step, self.fz*step) then
            self:FinishAttack()
            return
        end
        self.attackTravel = self.attackTravel + step
        self:DamagePlayer(target, a.hitRange, a.cosine)
    end
end

function WoodSpirit:FinishAttack()
    if self.attack == pounce and self.particles then
        self.particles:Emit(self, {pos=self.position, dir=Vector3.UP, material='soft', kind='dust'})
    end
    Base.FinishAttack(self)
end

function WoodSpirit:SetActive(active)
    if not active and not self.dead and (self.state == S.ATTACK or self.state == S.TELEGRAPH) then
        self:SetState(S.IDLE)
        self.aggro = false
    end
    Base.SetActive(self, active)
end

function WoodSpirit:UpdatePose()
    Base.UpdatePose(self)
    -- The four feet stay planted while posePart lowers the barrel between them.
    if self.state == S.TELEGRAPH then self.poseY = 0 end
end

local function ease(t, a, b)
    local u = min(1, max(0, (t-a)/(b-a)))
    return u*u*(3-2*u)
end

-- Each leaf and the resin are siblings of the trunk. Carry their sockets around
-- the trunk pivot (y=.32m) before adding leaf flex or local resin contraction.
local function tilt(p, y, z, pitch, lift)
    local angle = math.rad(pitch)
    p.pitch = pitch
    p.y = lift + y*(cos(angle)-1) - z*sin(angle)
    p.z = y*sin(angle) + z*(cos(angle)-1)
end

local feet = {root_front_r={1,1}, root_front_l={-1,1}, root_back_r={1,-1}, root_back_l={-1,-1}}
local function die(enemy, id, p, side, foot)
    local t = enemy.deathTime
    if foot then
        local loosen = ease(t,.07,.38)
        p.x,p.roll,p.sy = foot[1]*.09*loosen, foot[1]*20*loosen, 1-.26*loosen
        p.y = -.069*loosen
    elseif side ~= 0 then
        local release = side > 0 and .18 or .27
        local drift = ease(t,release,release+.77)
        local flutter = sin(drift*math.pi*3.5)
        p.x = side*(.42*drift+.085*flutter)
        p.y = .16*sin(drift*math.pi)-1.045*drift
        p.z = -.21*drift+side*.08*flutter
        p.roll,p.pitch,p.yaw = side*(72*drift+14*flutter), -62*drift+20*flutter, side*52*drift
    else
        local fall = ease(t,.12,.69)
        local pitch = 82*fall-6*sin(math.pi*ease(t,.68,.88))
        local lift = .13*fall
        if id == 'core' then
            local dim = ease(t,0,.32)
            tilt(p,.20,.36-.18*dim,pitch,lift)
            p.z = p.z-.18*dim
            p.sx,p.sy,p.sz = 1-.97*dim,1-.97*dim,1-.97*dim
        else
            tilt(p,0,0,pitch,lift)
        end
    end
end

function WoodSpirit.Config.posePart(enemy, id, p)
    local side = id == 'leaf_r' and 1 or (id == 'leaf_l' and -1 or 0)
    local foot = feet[id]
    if enemy.dead then die(enemy,id,p,side,foot); return end
    local t, state, a = enemy.stateTime, enemy.state, enemy.attack
    local pitch, lift, fold, plant = 0, 0, 0, 0
    if state == S.TELEGRAPH or state == S.ATTACK or state == S.RECOVER then
        local load, strike = 1, 0
        if state == S.TELEGRAPH then load = ease(t,0,a.telegraph*.76)
        elseif state == S.ATTACK then
            local release = ease(t,0,a.start+.07)
            load,strike = 1-release,release
        else
            load = 0
            local hold = a == pounce and (enemy.attackHit and .28 or .55) or .12
            strike = 1-ease(t,hold,a.recover)
        end
        if a == pounce then
            local arc = state == S.ATTACK and sin(math.pi*ease(t,a.start,a.finish)) or 0
            pitch,lift,fold,plant = -14*load+32*strike, -.16*load+.23*arc-.08*strike,
                48*load+23*strike, load
        else
            pitch,lift,fold,plant = -22*load+34*strike, -.05*load+.03*strike, 20*load-12*strike, load*.4
        end
    elseif state == S.CHASE or state == S.PATROL then
        local stride = sin(enemy.poseAge*(state == S.CHASE and 13 or 5))
        lift,pitch,fold = .048*math.abs(stride), 4+3*stride, 7*stride
        if foot then
            local step = stride*foot[1]*foot[2]
            p.z,p.y,p.pitch = .105*step,.07*max(0,step),14*step
            return
        end
    else
        local breath = sin(enemy.poseAge*2.7)
        lift,fold = .013*breath, 4*breath
    end
    if foot then
        p.x,p.z = foot[1]*.09*plant,foot[2]*.07*plant
        p.sy,p.pitch = 1-.19*plant, -foot[2]*10*plant
        p.y = -.06*plant
        if state == S.ATTACK and a == pounce then p.y=lift+.08 end
        return
    end
    local socketY = side ~= 0 and .8 or (id == 'core' and .20 or 0)
    local socketZ = side ~= 0 and -.08 or (id == 'core' and .36 or 0)
    tilt(p,socketY,socketZ,pitch,lift)
    local age = enemy.reaction.recoilAge
    local twist = enemy.reaction.dx >= 0 and -1 or 1
    local recoil = 1-ease(age,0,.22)
    p.yaw = twist*16*recoil
    -- Follow the trunk's yaw before the flexible blade catches up a beat later.
    local yaw = math.rad(p.yaw)
    local x = side*.40
    local z = socketZ+p.z
    p.x,p.z = x*(cos(yaw)-1)+z*sin(yaw), p.z-x*sin(yaw)+z*(cos(yaw)-1)
    if side ~= 0 then
        local lag = ease(age,.035,.10)*(1-ease(age,.10,.32))
        p.roll = -side*(fold+17*lag)
        p.yaw = p.yaw+twist*12*lag
    end
end

return WoodSpirit
