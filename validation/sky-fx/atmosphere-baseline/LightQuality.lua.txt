-- 大气预算与基础光照。统一设置存在时，阴影/Bloom只由SceneQuality热更新。
local Platform = require("urhox-libs.Platform.PlatformUtils")
local M = {}
M.DEFAULT = "high" -- 无GameSettings时的默认；Web仍禁止真实体积雾。
M.FEATURES = {clouds=true,lowClouds=true,cloudShadow=true,shafts=true,motes=true,volumetric=true,bloom=true}
M.PROFILES = {
    high={quality="high",cloudsEnabled=true,cloudCount=24,lightShafts=8,motes=80,volumetric="full",shadowOn=true,shadowCascades=3,shadowDistance=110,shadowMapSize=2048,shadowPCFSamples=4,bloom=true,postFx="full"},
    medium={quality="medium",cloudsEnabled=true,cloudCount=12,lightShafts=3,motes=28,volumetric="lite",shadowOn=true,shadowCascades=2,shadowDistance=65,shadowMapSize=1024,shadowPCFSamples=2,bloom=false,postFx="lite"},
    low={quality="low",cloudsEnabled=false,cloudCount=0,lightShafts=0,motes=0,volumetric="off",shadowOn=false,shadowCascades=0,shadowDistance=0,shadowMapSize=512,shadowPCFSamples=1,bloom=false,postFx="off"},
}
M.PROFILES.off = M.PROFILES.low

function M.Default()
    return M.PROFILES[M.DEFAULT] and M.DEFAULT or "high"
end

---@param zone Zone
---@param sun Light
function M.ApplyVolume(zone,sun,mode,enabled)
    local constrained = Platform.IsWebPlatform() or Platform.IsMobilePlatform()
    local realFog = enabled and mode~="off" and not constrained and graphics:GetComputeShaderSupport()
    zone.volumetricFogEnabled = realFog
    renderer:SetVolumetricFogFroxelEnabled(realFog)
    if realFog then
        -- 只用 LOW froxel：16px × 64，high 是场景档名，不等于引擎 HIGH 体积档。
        renderer:SetVolumetricFogQuality(VOLUMETRIC_FOG_QUALITY_LOW)
        zone.volumetricFogDensity = mode=="lite" and 0.0015 or 0.0025
        zone.volumetricFogHeight = 3
        zone.volumetricFogHeightFalloff = 0.025
        zone.volumetricFogViewDistance = mode=="lite" and 60 or 90
        zone.volumetricFogPhaseG = 0.45
        zone.volumetricFogStartDistance = 3
        zone.volumetricFogMaxOpacity = 0.35
        zone.skyLightVolumetricScatteringIntensity = 0.25
        sun.volumetricFogShadows = true
    end
    sun.affectVolumetricFog = realFog
    return realFog
end

---@param zone Zone
---@param sun Light
function M.ConfigureScene(zone,sun)
    sun.useTemperature = false -- DayNight 自己给 RGB 色温，避免预设叠加温度。
    -- 降低全画面泛白；保留 Bloom 合成 pass 中的 tonemap 与固定曝光。
    zone.tonemapMode = TONEMAP_MODE_ACES
    zone.bloomMode = BLOOM_MODE_UE
    zone.bloomUEThreshold,zone.bloomThreshold = 1.2,1.2
    zone.bloomUEIntensity = 0.35
    zone.bloomWeight = 0.12
    zone.autoExposureEnabled,zone.autoExposurePlusEnabled = true,true
    zone.autoExposureMinBrightness,zone.autoExposureMaxBrightness = 1,1
    zone.autoExposureBias,zone.autoExposureForceTarget = 1,true
    zone.ssrEnabled,zone.ssgiEnabled,zone.motionBlurEnabled = false,false,false
    zone.depthFogEnable,zone.heightFogEnable = true,true
    zone.heightFogHeight,zone.heightFogFalloff,zone.heightFogDensity = -12,0.12,0.009
end

-- 仅无统一设置时使用；不会在SkyFx的RegisterQuality回调中改动共享阴影/后处理。
---@param zone Zone
---@param sun Light
function M.ApplyStandaloneScene(zone,sun,profile,bloom)
    sun.castShadows = profile.shadowOn
    if profile.shadowCascades>=3 then sun.shadowCascade=CascadeParameters(10,38,profile.shadowDistance,0,0.82)
    elseif profile.shadowCascades==2 then sun.shadowCascade=CascadeParameters(12,profile.shadowDistance,0,0,0.82) end
    renderer.shadowMapSize,renderer.shadowPCFSamples = profile.shadowMapSize,profile.shadowPCFSamples
    sun.shadowResolution = 1
    zone.bloomMode = profile.postFx=="full" and BLOOM_MODE_UE or BLOOM_MODE_LEGACY
    zone.bloomUEIntensity = bloom and profile.bloom and 0.35 or 0
    zone.bloomWeight = bloom and profile.bloom and 0.12 or 0
end

return M
