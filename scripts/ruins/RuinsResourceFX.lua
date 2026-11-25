-- Lightweight crystal-ore break feedback: a few physical shards plus a short dust puff.
local LIFETIME = .56
local FLASH_TIME = .09
local FX = {}
FX.__index = FX

local function makeSoftTexture()
    local image = Image()
    image:SetSize(32, 32, 4)
    for y = 0, 31 do
        for x = 0, 31 do
            local dx = (x + .5) / 16 - 1
            local dy = (y + .5) / 16 - 1
            local radius = math.sqrt(dx * dx + dy * dy)
            local alpha = math.max(0, 1 - radius) ^ 2
            image:SetPixel(x, y, Color(1, 1, 1, alpha))
        end
    end
    local texture = Texture2D:new()
    texture:SetData(image, true)
    image:Dispose()
    return texture
end

local function softMaterial()
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource('Technique', 'Techniques/DiffUnlitParticleAlpha.xml'))
    material:SetTexture(TU_DIFFUSE, makeSoftTexture())
    return material
end

local function makeShardMaterial()
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource('Technique', 'Techniques/PBR/PBRNoTextureAlpha.xml'))
    material:SetShaderParameter('MatDiffColor', Variant(Color(.52, .88, 1.0, 1)))
    material:SetShaderParameter('MatEmissiveColor', Variant(Color(.12, .32, .48)))
    material:SetShaderParameter('Roughness', Variant(.08))
    material:SetShaderParameter('Metallic', Variant(.18))
    material:SetShaderParameter('MatSpecColor', Variant(Color(.9, .96, 1, 1)))
    return material
end

local function triangle(geometry, a, b, c)
    local normal = (b - a):CrossProduct(c - a):Normalized()
    geometry:DefineVertex(a); geometry:DefineNormal(normal)
    geometry:DefineVertex(b); geometry:DefineNormal(normal)
    geometry:DefineVertex(c); geometry:DefineNormal(normal)
end

local function makeShard(parent, name, material)
    local node = parent:CreateChild(name)
    local geometry = node:CreateComponent('CustomGeometry')
    geometry:BeginGeometry(0, TRIANGLE_LIST)
    local top = Vector3(0, .5, 0)
    local bottom = Vector3(0, -.5, 0)
    local ring = {
        Vector3(-.34, 0, -.22), Vector3(.28, 0, -.25),
        Vector3(.36, 0, .18), Vector3(-.25, 0, .24),
    }
    for i = 1, 4 do
        local nextIndex = i % 4 + 1
        triangle(geometry, top, ring[nextIndex], ring[i])
        triangle(geometry, bottom, ring[i], ring[nextIndex])
    end
    geometry:Commit()
    geometry:SetMaterial(material)
    geometry.castShadows = false
    return node
end

local function makeDustEffect(material)
    local effect = ParticleEffect:new()
    effect:SetMaterial(material)
    effect:SetRelative(true)
    effect:SetNumParticles(12)
    effect:SetEmitterType(EMITTER_SPHERE)
    effect:SetEmitterSize(Vector3(.22, .10, .22))
    effect:SetMinDirection(Vector3(-1, .20, -1))
    effect:SetMaxDirection(Vector3(1, .75, 1))
    effect:SetMinVelocity(2.0)
    effect:SetMaxVelocity(3.8)
    effect:SetConstantForce(Vector3(0, -.65, 0))
    effect:SetDampingForce(5.0)
    effect:SetMinTimeToLive(.28)
    effect:SetMaxTimeToLive(.48)
    effect:SetMinParticleSize(Vector2(.19, .19))
    effect:SetMaxParticleSize(Vector2(.35, .35))
    effect:SetMinRotation(-180)
    effect:SetMaxRotation(180)
    effect:SetMinRotationSpeed(-80)
    effect:SetMaxRotationSpeed(80)
    effect:SetMinEmissionRate(90)
    effect:SetMaxEmissionRate(120)
    effect:SetActiveTime(.08)
    effect:SetInactiveTime(1)
    effect:SetSizeAdd(.42)
    effect:SetNumColorFrames(0)
    effect:AddColorTime(Color(.78, .91, .95, .45), 0.0)
    effect:AddColorTime(Color(.64, .80, .84, .42), .10)
    effect:AddColorTime(Color(.42, .56, .60, .0), .48)
    effect:SetUpdateInvisible(true)
    return effect
end

local function makeDustEmitter(parent, effect)
    local node = parent:CreateChild('MineralDust')
    local emitter = node:CreateComponent('ParticleEmitter')
    emitter:SetEffect(effect)
    emitter.castShadows = false
    emitter:SetEmitting(true)
end

local function impactFlash(root, material)
    local flash = root:CreateComponent('BillboardSet')
    flash.material = material
    flash.numBillboards = 1
    flash.faceCameraMode = FC_ROTATE_XYZ
    local sprite = flash:GetBillboard(0)
    sprite.size = Vector2(.29, .29)
    sprite.color = Color(.83, .96, 1, .68)
    sprite.enabled = true
    flash:Commit()
    return flash
end

function FX.New(scene)
    local glow = softMaterial()
    return setmetatable({
        root = scene:CreateChild('RuinsResourceFX'),
        shardMaterial = makeShardMaterial(),
        dustEffect = makeDustEffect(glow),
        flashMaterial = glow,
        bursts = {},
    }, FX)
end

function FX:Break(position)
    local root = self.root:CreateChild('CrystalBreak')
    root.position = position
    local burst = {root = root, age = 0, shards = {}, material = self.shardMaterial:Clone()}
    burst.flash = impactFlash(root, self.flashMaterial)
    for i = 1, 8 do
        local angle = (i - 1) * math.pi / 4 + (i % 2) * .17
        local dx, dz = math.cos(angle), math.sin(angle)
        local speed = 1.45 + (i % 3) * .36
        local shard = makeShard(root, 'Shard_' .. i, burst.material)
        local size = .12 + (i % 4) * .032
        shard.scale = Vector3(size, size * 1.25, size)
        local start = Vector3(dx * .22, (i % 3 - 1) * .16, dz * .22)
        shard.position = start
        burst.shards[i] = {
            node = shard, start = start, velocity = Vector3(dx * speed, 1.35 + (i % 4) * .33, dz * speed),
            spin = (i % 2 == 0 and 1 or -1) * (210 + i * 19), tilt = i * 37, yaw = i * 45
        }
        shard.rotation = Quaternion(i * 37, i * 45, 0)
    end
    makeDustEmitter(root, self.dustEffect)
    self.bursts[#self.bursts + 1] = burst
end

function FX:Update(dt)
    for index = #self.bursts, 1, -1 do
        local burst = self.bursts[index]
        local age = burst.age + dt
        burst.age = age
        if age >= LIFETIME then
            burst.root:Remove()
            table.remove(self.bursts, index)
        else
            if burst.flash then
                if age >= FLASH_TIME then
                    burst.flash:Remove()
                    burst.flash = nil
                else
                    local t = age / FLASH_TIME
                    local radius = .29 + .23 * t
                    local sprite = burst.flash:GetBillboard(0)
                    sprite.size = Vector2(radius, radius)
                    sprite.color = Color(.83, .96, 1, .68 * (1-t)^2)
                    burst.flash:Commit()
                end
            end
            local fall = Vector3(0, -4.9 * age * age, 0)
            local alpha = math.min(1, (LIFETIME - age) / .24)
            burst.material:SetShaderParameter('MatDiffColor', Variant(Color(.52, .88, 1, alpha)))
            for _, shard in ipairs(burst.shards) do
                shard.node.position = shard.start + shard.velocity * age + fall
                shard.node.rotation = Quaternion(shard.tilt + shard.spin * age, shard.yaw + age * 130, 0)
            end
        end
    end
end

function FX:Destroy()
    self.bursts = {}
    if self.root then self.root:Remove() end
    self.root = nil
end

return FX
