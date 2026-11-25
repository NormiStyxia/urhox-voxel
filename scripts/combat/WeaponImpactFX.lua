-- Shared one-shot Cascade presentation. Each layer uses the scene's native
-- auto-release pool. No borrowed hit event or pooled instance is retained.
local M = { enabled = true }
local paths = {
    flash = 'Effects/WeaponImpact/Flash.effect',
    sparks = 'Effects/WeaponImpact/Sparks.effect',
    chips = 'Effects/WeaponImpact/Chips.effect',
    dust = 'Effects/WeaponImpact/Dust.effect',
    focus = 'Effects/WeaponImpact/Focus.effect',
    wave = 'Effects/WeaponImpact/Wave.effect',
    sand = 'Effects/WeaponImpact/Sand.effect',
}

-- Count per contact, lifetime in seconds, particle dimensions in metres,
-- RGB multipliers (may exceed 1 for emissive layers). Wave size is the
-- footprint diameter and is derived exclusively from the gameplay radius.
M.profiles = {
    swordBreak = {
        {shape='flash', count=1, life=.13, size={.78,.78,.78}, tint={3.5,2.7,1.3}},
        {shape='sparks', count=16, life=.28, size={.052,.36,.05}, tint={3.6,2.0,.55}},
        {shape='chips', count=9, life=.49, size={.07,.035,.13}, tint={.93,.62,.28}},
    },
    swordWeak = {
        {shape='flash', count=1, life=.12, size={.72,.72,.72}, tint={2.1,3.1,3.8}},
        {shape='sparks', count=12, life=.22, size={.042,.34,.04}, tint={1.0,2.5,3.4}},
        {shape='chips', count=6, life=.34, size={.05,.028,.10}, tint={.65,.87,1}},
    },
    swordHeavy = {
        {shape='sparks', count=7, life=.20, size={.04,.24,.04}, tint={2.3,1.65,.80}},
        {shape='chips', count=4, life=.32, size={.045,.025,.07}, tint={.80,.62,.43}},
    },
    arrowStone = {
        {shape='chips', count=7, life=.43, size={.065,.045,.08}, tint={.62,.55,.43}},
        {shape='dust', count=9, life=.58, size={.23,.23,.23}, tint={.56,.50,.42}},
    },
    arrowArmor = {
        {shape='sparks', count=7, life=.15, size={.035,.25,.035}, tint={3.5,2.1,.62}},
    },
    arrowWeak = {
        {shape='focus', count=12, life=.17, size={.038,.13,.038}, tint={1.3,2.5,3.6}},
        {shape='flash', count=1, life=.20, size={.47,.47,.47}, tint={2.7,3.1,3.5}},
    },
    shatter = {
        {shape='wave', count=1, life=.54, lift=.035, tint={.75,.64,.48}},
        {shape='sand', count=38, life=.62, size={.060,.10,.060}, radiusFraction=.83, tint={2.6,1.8,.67}},
    },
}

local resources, warned = {}, {}
local function warnOnce(key, message)
    if warned[key] then return end
    warned[key] = true
    print('WeaponImpactFX: ' .. key .. ' ' .. tostring(message))
end

local function configure(instance, layer, radius)
    local size = layer.size
    local extent = size and Vector3(table.unpack(size)) or Vector3(radius * 2, 1, radius * 2)
    instance:SetFloatParameter('Count', layer.count)
    instance:SetFloatParameter('Life', layer.life)
    instance:SetVectorParameter('Size', extent)
    instance:SetVectorParameter('Tint', Vector3(table.unpack(layer.tint)))
    if layer.radiusFraction then instance:SetFloatParameter('Radius', radius * layer.radiusFraction) end
    if layer.shape == 'focus' then instance:SetFloatParameter('Converge', -1 / layer.life) end
    instance:Activate(true)
end

local function spawnLayer(CascadeParticle, pool, scene, layer, pos, rotation, normal, radius)
    local path = paths[layer.shape]
    local resource = resources[path]
    if resource == nil then
        resource = cache:GetResource('CascadeParticleSystem', path) or false
        resources[path] = resource
        if not resource then warnOnce(path, 'unavailable') end
    end
    if not resource then return false end
    local origin = layer.lift and pos + normal * layer.lift or pos
    local instance = CascadeParticle.SpawnEmitterAttached(resource, scene, origin, rotation, Vector3.ONE, true, pool, false)
    if not instance then return false end
    local ok, err = pcall(configure, instance, layer, radius)
    if not ok then
        -- An inactive, partially initialized auto-release instance cannot finish.
        warnOnce(path, err)
        instance.node:Remove()
    end
    return ok
end

-- Also the visual review entry point. Returns true if all layers were started.
function M.Play(scene, name, pos, axis, radius)
    local CascadeParticle = rawget(_G, 'CascadeParticle')
    local pool = rawget(_G, 'CASCADE_POOL_AUTO_RELEASE')
    local layers = M.profiles[name]
    if not M.enabled or not scene or not pos or not layers or not cache or not CascadeParticle
        or not CascadeParticle.SpawnEmitterAttached or pool == nil then return false end
    if name == 'shatter' and not (radius and radius > 0 and radius < math.huge) then return false end
    local normal = axis and axis:LengthSquared() > 1e-8 and axis:Normalized() or Vector3.UP
    local rotation = Quaternion(Vector3.UP, normal)
    local complete = true
    for _, layer in ipairs(layers) do
        local ok, played = pcall(spawnLayer, CascadeParticle, pool, scene, layer, pos, rotation, normal, radius)
        if not ok then warnOnce(layer.shape, played) end
        if not ok or not played then complete = false end
    end
    return complete
end

function M.Sword(scene, e)
    local name
    if e.broke then name = 'swordBreak'
    elseif e.weak and e.critical then name = 'swordWeak'
    elseif e.tier == 'heavy' then name = 'swordHeavy' end
    if name then M.Play(scene, name, e.pos, e.impactDir) end
end

function M.ArrowTarget(scene, info, result, weak)
    if not M.enabled or not scene then return end
    if weak or result.weak then
        M.Play(scene, 'arrowWeak', info.pos, info.normal)
    elseif (result.material or info.material) == 'armor' then
        local normal = info.normal
        if not normal or normal:LengthSquared() < 1e-8 then normal = -info.dir end
        local tangent = info.dir - normal * info.dir:DotProduct(normal)
        if tangent:LengthSquared() < 1e-8 then
            local reference = math.abs(normal.y) < .9 and Vector3.UP or Vector3.RIGHT
            tangent = normal:CrossProduct(reference)
        end
        M.Play(scene, 'arrowArmor', info.pos, tangent)
    end
end

return M
