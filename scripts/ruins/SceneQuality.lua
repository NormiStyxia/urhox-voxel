-- One-time registration only; no Update subscription or per-frame traversal.
local Settings=require('ruins.GameSettings')
local Terrain=require('ruins.RuinsTerrain')
local M={}
---@class SettingsGrass: Component
---@field density number
---@field viewDistance number
---@param host table
function M.Attach(host)
    local sun=host.sun --[[@as Light]]
    local zone=host.zone --[[@as Zone]]
    local originalBloom={mode=zone.bloomMode,weight=zone.bloomWeight,plus=zone.bloomPlusIntensity,ue=zone.bloomUEIntensity}
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
        if p.shadowCascades>=3 then sun.shadowCascade=CascadeParameters(10,38,p.shadowDistance,0,.85)
        elseif p.shadowCascades==2 then sun.shadowCascade=CascadeParameters(12,p.shadowDistance,0,0,.85) end
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
        local grass=Terrain.grass --[[@as SettingsGrass?]]
        local flowers=Terrain.flowers --[[@as SettingsGrass?]]
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
        if Terrain.tufts then
            local root=Terrain.tufts.root --[[@as Node]]
            root.enabled=p.grassDensity>0
            -- Stable spatial thinning of existing 6m batches, no rebuild on clicks.
            local nodes=root:GetChildren()
            local stride=p.grassDensity>=1 and 1 or (p.grassDensity>=.5 and 2 or 4)
            for i,node in ipairs(nodes) do node.enabled=(i-1)%stride==0 end
        end
    end)
end
return M
