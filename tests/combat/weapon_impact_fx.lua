-- Contract at the boundary between resolved gameplay and pooled Cascade layers.
local S = dofile('tests/combat/core_support.lua')
local fx = require('combat.WeaponImpactFX')
local scene, played, loads = {}, {}, {}
local p = Vector3(2, 1, 3)
local dir = Vector3.RIGHT
assert(not fx.Play(scene, 'swordBreak', p, dir), 'optional API')
local oldQuaternion = Quaternion
Quaternion = function(_, axis) return axis end
CASCADE_POOL_AUTO_RELEASE = 1
cache = { GetResource = function(_, kind, path)
    assert(kind == 'CascadeParticleSystem' and not loads[path], 'resource loaded once')
    loads[path] = true
    return path
end }
CascadeParticle = { SpawnEmitterAttached = function(path, parent, pos, axis, _, autoDestroy, pool, active)
    assert(parent == scene and autoDestroy and pool == CASCADE_POOL_AUTO_RELEASE and not active)
    local instance = {path=path, pos=pos, axis=axis}
    function instance:SetFloatParameter(k, v) self[k] = v end
    instance.SetVectorParameter = instance.SetFloatParameter
    function instance:Activate()
        assert(self.Life > 0 and self.Count >= 1 and self.Size.x > 0 and self.Tint)
        played[#played+1] = self
    end
    return instance
end }
local function sword(weak, critical, broke, tier)
    fx.Sword(scene, {weak=weak, critical=critical, broke=broke, tier=tier, pos=p, impactDir=dir})
end
sword(false, false, false, 'light')
assert(#played == 0)
sword(true, true, true, 'heavy')
assert(#played == 3 and played[2].Count == fx.profiles.swordBreak[2].count)
assert(played[2].pos == p and played[2].axis.x == 1)
sword(true, true, false, 'light')
sword(false, false, false, 'heavy')
assert(#played == 8)
local info = {pos=p, dir=Vector3.RIGHT, normal=Vector3.UP, material='armor'}
fx.ArrowTarget(scene, info, {}, true)
assert(#played == 10 and played[9].path:find('Focus.effect', 1, true))
fx.ArrowTarget(scene, info, {}, false)
S.near(played[11].axis:DotProduct(info.normal), 0)
assert(fx.Play(scene, 'shatter', p, Vector3.UP, 4.16))
S.near(played[12].Size.x, 8.32)
S.near(played[12].Size.z, 8.32)
assert(not fx.Play(scene, 'shatter', p, Vector3.UP))
fx.enabled = false
assert(not fx.Play(scene, 'arrowStone', p, dir) and #played == 13)
fx.enabled = true
Quaternion = oldQuaternion

-- Run an actual projectile sweep and prediction with identical solid contact.
-- Only the embedded projectile presents, and only once across later ticks.
local shots = {}
fx.Play = function(_, name) shots[#shots+1] = name end
local Projectile = require('combat.Projectile')
local function cast() return .5, {hit=true,volume={},normal=Vector3.UP} end
local predictor = Projectile.NewPrediction()
Projectile.Predict(predictor, p, dir, 1, {}, 0, false, 4, cast, {})
assert(#shots == 0)
local arrows = Projectile.New{scene=scene, cast=cast, random=function() return .5 end}
for _, bow in ipairs({'thorn','field','silver'}) do
    assert(arrows:Fire(p, dir, .5, {}, nil, bow))
    arrows:Update(.05)
    arrows:Update(.1)
    arrows:Clear()
end
assert(#shots == 2 and shots[1] == 'arrowStone' and shots[2] == 'arrowStone')
print('PASS weapon impact routing, direction, radius, cache, pooled playback, toggle and solid sweep')

-- Exercise the real full-charge spell with an upgraded terrain radius.
package.loaded['dragon.VoxelFX'] = {}
local terrainR
package.loaded['ruins.VoxelDamage'] = { AtWorldPoint=function(_, _, radius) terrainR=radius; return 1 end }
Color = function(...) return {...} end
local spells = require('ruins.TimeSpells')
local ringR, rings = nil, 0
fx.Play = function(parent, name, pos, axis, radius)
    assert(parent == scene and name == 'shatter' and pos == p and axis == Vector3.UP)
    rings, ringR = rings+1, radius
end
local ctx = {scene=scene, world={ApplyRadialImpulse=function() end}, spellDamaged={},
    catalystStats=function() return {terrainRadius=1.30} end,
    fx={Burst=function() end}}
local aim = {hit=true,pos=p,normal=Vector3.UP,volume={destructible=true},dir=dir}
local cast = spells.BY_ID.shatter.cast
assert(cast(ctx, aim, .999) and rings == 0)
assert(cast(ctx, aim, 1) and rings == 1)
S.near(ringR, terrainR)
S.near(ringR, spells.ShatterRadius(1)*1.30)
assert(not cast(ctx, {hit=false}, 1) and rings == 1)
print('PASS full-charge terrain footprint uses the actual modified destruction radius')
