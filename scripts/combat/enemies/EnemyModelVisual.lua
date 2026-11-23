-- Runtime visual driver for the data-only enemy models. It owns no combat
-- decisions. Model cells are built once through EnemyModelAdapter, then each
-- frame only updates pivot transforms and the existing hit/death presentation.
local Adapter = require('combat.enemies.EnemyModelAdapter')
local HitMaterial = require('combat.enemies.EnemyHitMaterial')

local Visual = {}
Visual.__index = Visual
local dataCache = {}
local metricsCache = {}

local function modelData(config)
    local key = config.model
    local data = dataCache[key]
    if data then return data end
    local module = require('combat.enemies.models.' .. key)
    data = assert(module.Build(), 'enemy model Build() returned nil: ' .. key)
    dataCache[key] = data
    return data
end

local function CellKey(x, y, z) return x .. ',' .. y .. ',' .. z end

function Visual.Measure(config)
    local cached = metricsCache[config.model]
    if cached then return cached end
    local data = modelData(config)
    local count, faces = 0, 0
    for _, part in ipairs(data.parts) do
        local occupied = {}
        for _, cell in ipairs(part.cells) do
            occupied[CellKey(cell[1], cell[2], cell[3])] = true
            count = count + 1
        end
        for _, cell in ipairs(part.cells) do
            local x, y, z = cell[1], cell[2], cell[3]
            if not occupied[CellKey(x - 1, y, z)] then faces = faces + 1 end
            if not occupied[CellKey(x + 1, y, z)] then faces = faces + 1 end
            if not occupied[CellKey(x, y - 1, z)] then faces = faces + 1 end
            if not occupied[CellKey(x, y + 1, z)] then faces = faces + 1 end
            if not occupied[CellKey(x, y, z - 1)] then faces = faces + 1 end
            if not occupied[CellKey(x, y, z + 1)] then faces = faces + 1 end
        end
    end
    assert(count <= 3000, 'enemy model voxel budget exceeded: ' .. config.model .. ' ' .. count)
    local result = {voxelCount = count, surfaceFacesEstimate = faces, drawSubmissionsEstimate = #data.parts}
    metricsCache[config.model] = result
    return result
end

local function MakeWarning(self, kind, decorative)
    local node = self.root:CreateChild('warning_' .. kind)
    local geom = node:CreateComponent('CustomGeometry')
    geom:BeginGeometry(0, TRIANGLE_LIST)
    local function pixel(x, z, size)
        x, z = math.floor(x / size + .5) * size, math.floor(z / size + .5) * size
        local h = size * .48
        local vertices = {Vector3(x-h, 0, z-h), Vector3(x-h, 0, z+h), Vector3(x+h, 0, z+h),
            Vector3(x-h, 0, z-h), Vector3(x+h, 0, z+h), Vector3(x+h, 0, z-h)}
        for _, vertex in ipairs(vertices) do geom:DefineVertex(vertex); geom:DefineNormal(Vector3.UP) end
    end
    if kind == 'line' then
        for i = 0, 28 do pixel(-.075, i / 28, .045); pixel(.075, i / 28, .045) end
    else
        local span = kind == 'fan' and math.pi * 2 / 3 or math.pi * 2
        for i = 0, 47 do
            local angle = -span / 2 + span * i / 47
            pixel(math.sin(angle), math.cos(angle), .065)
        end
        if kind == 'fan' then
            for i = 1, 14 do
                pixel(math.sin(span / 2) * i / 14, math.cos(span / 2) * i / 14, .065)
                pixel(-math.sin(span / 2) * i / 14, math.cos(span / 2) * i / 14, .065)
            end
        end
    end
    geom:Commit()
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource('Technique', 'Techniques/NoTextureUnlit.xml'))
    material:SetShaderParameter('MatDiffColor', Variant(decorative and Color(.38, .35, .25, 1)
        or Color(200 / 255, 80 / 255, 60 / 255, 1)))
    material:SetCullMode(CULL_NONE)
    geom:SetMaterial(material)
    node.position = Vector3(0, .06, 0)
    node.enabled = false
    return node
end

---@param scene Scene
---@param world VoxelPhysicsWorld
---@param config table
function Visual.New(scene, world, config)
    local started = os.clock()
    local self = setmetatable({}, Visual)
    self.scene, self.world, self.config = scene, world, config
    self.data = modelData(config)
    local built = Adapter.Build(world, scene, self.data)
    self.adapter, self.root = built, built.root
    self.root.name = 'Enemy_' .. config.kind
    self.body = self.root:CreateChild('body_pose')
    self.parts, self.bones, self.warnings = {}, {}, {}
    for index, handle in ipairs(built.parts) do
        local pivot = handle.pivot
        local rest = handle.pivotPosition or {0, 0, 0}
        pivot:SetParent(self.body)
        pivot.position = Vector3(rest[1], rest[2], rest[3])
        pivot.rotation = Quaternion()
        pivot.scale = Vector3(1, 1, 1)
        local entry = {id = handle.id, volume = handle.volume, node = handle.node, pivot = pivot,
            restPivot = rest, pose = {x=0, y=0, z=0, pitch=0, yaw=0, roll=0, sx=1, sy=1, sz=1},
            hitGroup = nil, originalMaterial = nil, material = nil, lit = false}
        self.parts[index] = entry
        self.bones[handle.id] = pivot
    end
    self.flashSupported = false
    HitMaterial.Init(self)
    -- Attach after Init so each model visual owns instance/domain/bank clones.
    for _, entry in ipairs(self.parts) do
        entry.hitGroup, entry.originalMaterial = HitMaterial.Attach(self, entry.volume, entry.id)
        entry.material = entry.hitGroup.material
        self.flashSupported = self.flashSupported or entry.material ~= false
    end
    for _, attack in ipairs(config.attacks) do
        if not self.warnings[attack.warning] then
            self.warnings[attack.warning] = MakeWarning(self, attack.warning, false)
        end
    end
    if config.boss then self.phaseRing = MakeWarning(self, 'ring', true) end
    self.metrics = Visual.Measure(config)
    self.voxelCount = self.metrics.voxelCount
    self.surfaceFacesEstimate = self.metrics.surfaceFacesEstimate
    self.drawSubmissionsEstimate = self.metrics.drawSubmissionsEstimate
    self.rebuildCpuMs = (os.clock() - started) * 1000
    self.removed = false
    return self
end

function Visual:StartHit(part, heavy) HitMaterial.Start(self, part, heavy) end
function Visual:TickFlash(realDt) HitMaterial.Update(self, realDt, false) end
function Visual:ClearFlash() HitMaterial.Update(self, 0, true); HitMaterial.Rage(self, false) end

local function ResetPose(pose)
    pose.x, pose.y, pose.z = 0, 0, 0
    pose.pitch, pose.yaw, pose.roll = 0, 0, 0
    pose.sx, pose.sy, pose.sz = 1, 1, 1
end

function Visual:Update(enemy)
    if self.removed then return end
    self.root.position = enemy.position
    self.root.rotation = Quaternion(enemy.yaw, Vector3.UP)
    local reaction = enemy.reaction
    local recoil = math.max(0, 1 - reaction.recoilAge / .12)
    local roll = math.rad(enemy.poseRoll or 0)
    local pivot = enemy.posePivot or 0
    self.body.position = Vector3(pivot * math.sin(roll), (enemy.config.hover or 0) + enemy.poseY
        + pivot * (1 - math.cos(roll)), 0)
    self.body.rotation = Quaternion((enemy.posePitch or 0) + (reaction.bodyPitch or 0) * recoil,
        (reaction.bodyYaw or 0) * recoil, enemy.poseRoll or 0)
    self.body.scale = Vector3(1, 1, 1)

    for kind, node in pairs(self.warnings) do
        node.enabled = enemy.warning.visible and kind == enemy.warning.kind
        if node.enabled then
            local radius = enemy.warning.radius * (.25 + .75 * enemy.warning.step / 6)
            node.scale = Vector3(radius, 1, radius)
        end
    end
    if self.phaseRing then
        local time = enemy.rageTime or 0
        self.phaseRing.enabled = enemy.rageActive and not enemy.down and time >= .45 and time < .70 and not enemy.dead
        self.phaseRing:SetScale(.5 + 3.5 * math.floor(math.max(0, time - .45) / .25 * 6) / 6)
    end
    HitMaterial.Rage(self, enemy.rageActive and not enemy.dead and not enemy.down)

    for _, entry in ipairs(self.parts) do
        local pose = entry.pose
        ResetPose(pose)
        if self.config.posePart then self.config.posePart(enemy, entry.id, pose) end
        local rest = entry.restPivot
        entry.pivot.position = Vector3(rest[1] + pose.x, rest[2] + pose.y, rest[3] + pose.z)
        entry.pivot.rotation = Quaternion(pose.pitch, pose.yaw, pose.roll)
        entry.pivot.scale = Vector3(pose.sx, pose.sy, pose.sz)
        entry.lit = entry.hitGroup.level > 0
    end

    if enemy.dead and enemy.deathTime + 1e-8 >= 1.1 then
        self.root.enabled = false
        self:Destroy()
    end
end

function Visual:Destroy()
    if self.removed then return end
    self:ClearFlash()
    self.removed = true
    Adapter.Destroy(self.adapter)
    self.hitGroups, self.hitTemplate = {}, nil
end

return Visual
