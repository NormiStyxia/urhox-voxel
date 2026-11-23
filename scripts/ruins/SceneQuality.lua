-- One-time registration only; no Update subscription or per-frame traversal.
local Settings=require('ruins.GameSettings')
local Terrain=require('ruins.RuinsTerrain')
local ContactAO=require('ruins.ContactAO')
local RenderBudget=require('ruins.RenderBudget')
local GroundContact=require('ruins.GroundContact')
local LightQuality=require('ruins.LightQuality')
local M={}
---@class SettingsGrass: Component
---@field density number
---@field viewDistance number
function M.ApplyGrass(field,p)
    local grass=field.grass --[[@as SettingsGrass?]]
    local flowers=field.flowers --[[@as SettingsGrass?]]
    -- 地面材质在草叶淡出的同一距离换成草冠色；没有原生草时整片都用草冠色。
    local ground=field.groundMaterial or field.meadowMaterial
    if ground then
        local far=(grass and p.grassDensity>0) and p.grassDistance or 0
        ground:SetShaderParameter('grass_far',Variant(Vector2(far*0.82,far)))
    end
    if grass then
        grass.enabled=p.grassDensity>0
        grass.density=110*p.grassDensity
        grass.viewDistance=p.grassDistance
    end
    if flowers then
        flowers.enabled=p.grassDensity>0
        flowers.density=2.5*p.grassDensity
        flowers.viewDistance=math.min(35,p.grassDistance)
    end
    if field.tufts then
        local root=field.tufts.root --[[@as Node]]
        root.enabled=p.grassDensity>0
        -- Stable spatial thinning of existing 6m batches, no rebuild on clicks.
        local stride=p.grassDensity>=1 and 1 or (p.grassDensity>=.5 and 2 or 4)
        for i,tile in ipairs(field.tufts.tiles) do
            tile.node.enabled=p.grassDensity>0 and (i-1)%stride==0
            tile.drawable.drawDistance=p.grassDistance
        end
    end
end
---@param host table
function M.Attach(host)
    local sun=host.sun --[[@as Light]]
    local zone=host.zone --[[@as Zone]]
    -- 静态场景已经建好：一次性按物体尺寸限制阴影与绘制距离（不随档位变化）。
    if host.scene then RenderBudget.Apply(host.scene) end
    local originalBloom={mode=zone.bloomMode,weight=zone.bloomWeight,plus=zone.bloomPlusIntensity,ue=zone.bloomUEIntensity}
    local dayNight=host.dayNight --[[@as DayNight]]
    if dayNight.contactAO then dayNight.contactAO:Dispose() end
    dayNight.contactAO=ContactAO.New(host.surfaceMaterials or {},Terrain.groundMaterial)
    Settings.RegisterQuality('scene-night-contact',function(p)
        dayNight.nightMoon=math.max(0.5,math.min(1,p.nightMoon or .82))
        dayNight.nightIBL=math.max(.68,math.min(1.3,p.nightIBL or 1.08))
        dayNight.contactAO:SetQuality(p,dayNight.day or 0)
        dayNight:Apply()
    end)
    Settings.RegisterQuality('scene-ground-contact',function(p)
        -- 落地遮蔽只压环境光，与昼夜无关；低档不做这次贴图查表。
        GroundContact.SetStrength(p.groundContact or 0)
    end)
    Settings.RegisterQuality('scene-skycapture',function(p)
        local dn=host.dayNight --[[@as DayNight]]
        if dn.capture.resolution~=p.skyCaptureResolution then
            dn.capture.resolution=p.skyCaptureResolution
            dn.capturePending=true
        end
        dn.capture.minCaptureInterval=p.skyCaptureInterval
    end)
    Settings.RegisterQuality('scene-shadows',function(p)
        sun.castShadows=p.shadowOn
        sun:SetAttribute('Auto Shadow Cascade',Variant(false))
        if p.shadowOn and p.shadowCascades>0 then LightQuality.ApplyShadowFocus(sun) end
        if p.shadowCascades>=3 then sun.shadowCascade=CascadeParameters(10,38,p.shadowDistance,0,.85)
        elseif p.shadowCascades==2 then sun.shadowCascade=CascadeParameters(12,p.shadowDistance,0,0,.85) end
        -- 远级联隔帧更新：太阳每帧只转约 0.004°，第 3 级每 4 帧重画一次看不出差别。
        -- 级联不足 2 级、关闭阴影等情况引擎自动退回普通阴影。
        sun.temporalShadows=p.shadowCascades>=2
        sun.temporalShadowIntervals=Vector4(1,2,4,8)
        renderer.shadowMapSize=p.shadowMapSize
        renderer.shadowPCFSamples=p.shadowPCFSamples
    end)
    Settings.RegisterQuality('scene-postfx',function(p)
        -- Bloom Enable also disables tone mapping/exposure; keep its compositor.
        zone.bloomMode=p.postFx=='full' and BLOOM_MODE_UE or BLOOM_MODE_LEGACY
        zone.bloomWeight=p.bloom and originalBloom.weight or 0
        zone.bloomPlusIntensity=p.bloom and originalBloom.plus or 0
        zone.bloomUEIntensity=p.bloom and originalBloom.ue or 0
    end)
    Settings.RegisterQuality('scene-grass',function(p)
        M.ApplyGrass(Terrain,p)
        if Terrain.home and Terrain.home.field then M.ApplyGrass(Terrain.home.field,p) end
    end)
end
return M
