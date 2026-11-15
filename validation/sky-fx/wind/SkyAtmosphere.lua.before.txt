-- 灯光段唯一挂接入口；5Hz 联动，低云/高云/云影/光柱/浮光/真实体积雾分别开关。
local Clouds = require("ruins.SkyClouds")
local Shafts = require("ruins.LightShafts")
local Motes = require("ruins.FloatingMotes")
local Braziers = require("ruins.NightBraziers")
local Quality = require("ruins.LightQuality")
local settingsOK,GameSettings = pcall(require,"ruins.GameSettings")
if not settingsOK then GameSettings=nil end
local logOK,DebugLog = pcall(require,"ruins.DebugLog")
if not logOK then DebugLog=nil end
local M = {}
M.__index = M

---@param scene Scene
---@param dn DayNight
function M.New(scene,dn)
    local self = setmetatable({},M)
    self:Init(scene,dn)
    return self
end

---@param scene Scene
---@param dn DayNight
function M:Init(scene,dn)
    ---@type Scene|nil
    self.scene = scene
    self.dayNight = dn
    ---@type RuinsSkyClouds|nil
    self.clouds = nil
    ---@type RuinsLightShafts|nil
    self.shafts = nil
    ---@type RuinsFloatingMotes|nil
    self.motes = nil
    ---@type RuinsNightBraziers|nil
    self.braziers=nil
    ---@type Vector3[]
    self.pillarAnchors={}
    self.active,self.stopped,self.realFog,self.shadowActive = false,false,false,false
    self.settingsManaged = GameSettings~=nil
    self.features = {}
    for k,v in pairs(Quality.FEATURES) do self.features[k] = v end
    self.features.cloudMotion,self.features.atmosphereFog,self.features.nightBraziers=true,true,true
    self.elapsed,self.clock = 0.2,0
    self.cloudElapsed=0 -- preserve wind phase across quality rebuilds and off/on
    ---@type Material|nil
    self.ground = nil
    ---@type Material|nil 本次开启已绑定（或已尝试失败）的地表，避免每帧重试/查资源
    self.shadowGround = nil
    self.profile = Quality.PROFILES[Quality.Default()]
    Quality.ConfigureScene(dn.zone,dn.sun)
    if GameSettings then
        GameSettings.RegisterQuality("skyfx",function(profile) self:ApplyProfile(profile) end)
        -- RegisterQuality在Settings.Load前不立即调用，独立加载此模块也要有当前预算。
        if not self.applied then self:ApplyProfile(GameSettings.GetProfile()) end
    else
        self:ApplyProfile(self.profile)
    end
    if DebugLog then DebugLog.RegisterProbe("skyfx",function() return self:Probe() end) end
end

function M:SetQuality(quality)
    if self.stopped then return end
    if self.settingsManaged and GameSettings then
        assert(quality=="auto" or Quality.PROFILES[quality],"SkyAtmosphere quality must be auto/off/low/medium/high")
        return GameSettings.Set("quality",quality=="off" and "low" or quality)
    end
    local profile = Quality.PROFILES[quality]
    assert(profile,"SkyAtmosphere quality must be off/low/medium/high")
    self:ApplyProfile(profile)
end

function M:ApplyProfile(profile)
    if self.stopped then return end
    if self.settingsManaged then
        -- The resolved profile is authoritative; no hidden per-instance overrides.
        local f=self.features
        f.clouds,f.lowClouds,f.cloudShadow=profile.cloudsEnabled~=false,profile.lowCloudsEnabled~=false,profile.cloudShadowEnabled~=false
        f.cloudMotion,f.atmosphereFog,f.nightBraziers=profile.cloudMotionEnabled~=false,profile.atmosphereFogEnabled~=false,(profile.braziers or 0)>0
        f.shafts,f.motes,f.volumetric,f.bloom=true,true,true,profile.bloom==true
    end
    self.profile,self.quality,self.applied = profile,profile.quality or "custom",true
    self:ApplySwitches()
    if DebugLog and DebugLog.enabled then
        DebugLog.Log("SkyFx","quality=%s clouds=%d shafts=%d motes=%d volume=%s",self.quality,
            self.clouds and self.clouds.count or 0,self.shafts and self.shafts.count or 0,
            self.motes and self.motes.count or 0,self.realFog and profile.volumetric or "off")
    end
end

function M:SetFeature(name,enabled)
    if self.stopped then return end
    assert(self.features[name]~=nil,"Unknown SkyAtmosphere feature")
    if self.settingsManaged and GameSettings then
        local key=({cloudMotion="cloudMotion",atmosphereFog="atmosphereFog",nightBraziers="nightBraziers",clouds="clouds",lowClouds="lowClouds",cloudShadow="cloudShadow",shafts="lightShafts",motes="floatingMotes",volumetric="volumetric",bloom="postFx"})[name]
        return GameSettings.Set(key,name=="bloom" and (enabled==true and "full" or "off") or enabled==true)
    end
    self.features[name] = enabled==true
    self:ApplySwitches()
end

-- Called only after static pillars have been built.
function M:SetPillarLayout(build,baseY)
    if self.stopped then return end
    if self.braziers then self.braziers:Dispose();self.braziers=nil end
    self.pillarAnchors=Braziers.Anchors(build,baseY)
    self:ApplySwitches()
end

function M:ApplyFog()
    local zone=self.dayNight.zone
    zone.depthFogEnable=self.features.atmosphereFog
    local density=self.features.atmosphereFog and (self.profile.heightFogDensity or 0) or 0
    zone.heightFogEnable=density>0
    if density>0 then
        -- DayNight continues owning the approved horizon colour and depth range.
        zone.heightFogDensity=density*(1+0.18*(self.dayNight.dusk or 0))
    end
end

function M:ApplySwitches()
    if self.stopped then return end
    local p,f = self.profile,self.features
    local count = p.cloudsEnabled and math.max(0,math.min(24,math.floor(p.cloudCount or 0))) or 0
    local upper,lower = f.clouds==true,f.lowClouds==true
    if self.clouds and (count~=self.clouds.budget or upper~=self.clouds.upper or lower~=self.clouds.lower) then
        self.cloudElapsed=self.clouds.elapsed
        self.clouds:Dispose(); self.clouds=nil
    end
    if count>0 and (upper or lower) and not self.clouds then
        self.clouds=Clouds.New(self.scene,count,upper,lower)
        self.clouds.elapsed=self.cloudElapsed
    end
    if self.clouds then self.clouds:SetMotion(f.cloudMotion,p.cloudMotionDetail or 0) end
    local fires=f.nightBraziers and math.min(#self.pillarAnchors,p.braziers or 0) or 0
    local lamps=math.min(fires,p.brazierLights or 0)
    if self.braziers and (fires~=self.braziers.count or lamps~=self.braziers.lightCount) then
        self.braziers:Dispose();self.braziers=nil
    end
    if fires>0 and not self.braziers then self.braziers=Braziers.New(self.scene,self.pillarAnchors,fires,lamps) end
    self:ApplyFog()
    local shafts = f.shafts and math.max(0,math.min(8,math.floor(p.lightShafts or 0))) or 0
    if self.shafts and shafts~=self.shafts.count then self.shafts:Dispose(); self.shafts=nil end
    if shafts>0 and not self.shafts then self.shafts=Shafts.New(self.scene,shafts) end
    local motes = f.motes and math.max(0,math.min(120,math.floor(p.motes or 0))) or 0
    if self.motes and motes~=self.motes.count then self.motes:Dispose(); self.motes=nil end
    if motes>0 and not self.motes then self.motes=Motes.New(self.scene,motes) end
    self.realFog=Quality.ApplyVolume(self.dayNight.zone,self.dayNight.sun,p.volumetric or "off",f.volumetric and p.shadowOn~=false)
    if not self.settingsManaged then Quality.ApplyStandaloneScene(self.dayNight.zone,self.dayNight.sun,p,f.bloom) end
    self.shadowActive=count>0 and f.cloudShadow==true
    self.active=self.clouds~=nil or self.shafts~=nil or self.motes~=nil or self.shadowActive or self.braziers~=nil
    if self.clouds then self.clouds:Update(0,self.dayNight.day or 1,self.dayNight.dusk or 0,self.dayNight) end
    if self.shafts then self.shafts:Update(self.dayNight,true,self.realFog) end
    if self.braziers then self.braziers:Update(self.dayNight.nightK or 0,self.clock,self.realFog) end
    self:ApplyCloudShadow()
    self.elapsed = 0.2
end

function M:ApplyCloudShadow()
    local ground = self.ground
    if not ground then return end
    ground:SetShaderParameter("cloud_shadow_strength",Variant(self.shadowActive and 0.16 or 0))
    if not self.shadowActive then
        ground:SetShaderParameter("cloud_shadow_use_atlas",Variant(0))
        self.shadowGround=nil
        return
    end
    if self.shadowGround==ground then return end
    local texture = cache:GetResource("Texture2D","Textures/Sky/cloud_flat_atlas.png")
    local bound = texture~=nil and ground:SetSurfaceTexture("cloud_shadow_atlas",texture)
    ground:SetShaderParameter("cloud_shadow_use_atlas",Variant(bound and 1 or 0))
    self.shadowGround=ground
    if not bound and DebugLog and DebugLog.enabled then DebugLog.Log("SkyFx","cloud shadow atlas unavailable; analytic round mask") end
end

---@param position Vector3 玩家/骑乘位置，不跟随拉远的观察相机
---@param ground Material|nil
function M:Update(dt,position,ground)
    if not self.active or self.stopped then return end
    if self.clouds then self.clouds:Follow(position) end
    self.clock,self.elapsed = self.clock+math.max(0,dt),self.elapsed+math.max(0,dt)
    if ground~=self.ground then
        if self.ground then self.ground:SetShaderParameter("cloud_shadow_strength",Variant(0)) end
        self.ground=ground
        self.shadowGround=nil
        self:ApplyCloudShadow()
    end
    if self.elapsed<0.2 then return end
    local step = self.elapsed
    self.elapsed = 0
    local dn = self.dayNight
    self:ApplyFog()
    if self.braziers then self.braziers:Update(dn.nightK or 0,self.clock,self.realFog) end
    if self.clouds then self.clouds:Update(step,dn.day or 1,dn.dusk or 0,dn) end
    if self.shafts then self.shafts:Update(dn,true,self.realFog) end
    if self.motes then self.motes:Update(position,true,dn.day or 1) end
    if self.ground and self.shadowActive then
        -- 独立实时时钟：快进昼夜不会让云影狂奔，也不触碰原 daynight_tint 接口。
        self.ground:SetShaderParameter("cloud_shadow_time",Variant(self.clock))
        self.ground:SetShaderParameter("cloud_shadow_day",Variant(dn.day or 1))
    end
end

-- 只被DebugLog的开启态probe调用；关闭日志时不构造统计表，不遍历粒子。
function M:Probe()
    return {clouds=self.clouds and self.clouds.count or 0,shafts=self.shafts and self.shafts.count or 0,
        cloudShapes=self.clouds and self.clouds.shapeCount or 0,cloudTriangles=self.clouds and self.clouds.triangleCount or 0,
        cloudBaking=self.clouds and self.clouds.baking or false,cloudReady=self.clouds and self.clouds.readyCount or 0,
        cloudFallback=self.clouds and self.clouds.fallback or false,
        cloudMethod="celestial_patches",cloudUnavailable=self.clouds and self.clouds.unavailable or false,
        cloudTextureReads=self.clouds and self.clouds.textureReads or 0,
        braziers=self.braziers and self.braziers.count or 0,pointLights=self.braziers and self.braziers.lightCount or 0,
        fireReady=self.braziers and self.braziers.available or false,
        motesMax=self.motes and self.motes.count or 0,volume=self.realFog,
        active=self.active,quality=self.quality,cloudShadow=self.shadowActive,
        batches=(self.clouds and self.clouds.batchCount or 0)+(self.shafts and 1 or 0)+(self.motes and 1 or 0)+(self.braziers and self.braziers.batchCount or 0)}
end

function M:Stop()
    if self.stopped then return end
    if GameSettings then GameSettings.RegisterQuality("skyfx",nil) end
    if DebugLog then DebugLog.RegisterProbe("skyfx",nil) end
    if self.clouds then self.clouds:Dispose(); self.clouds=nil end
    if self.shafts then self.shafts:Dispose(); self.shafts=nil end
    if self.motes then self.motes:Dispose(); self.motes=nil end
    if self.braziers then self.braziers:Dispose();self.braziers=nil end
    self.pillarAnchors={}
    if self.ground then
        self.ground:SetShaderParameter("cloud_shadow_strength",Variant(0))
        self.ground:SetShaderParameter("cloud_shadow_use_atlas",Variant(0))
    end
    Quality.ApplyVolume(self.dayNight.zone,self.dayNight.sun,"off",false)
    self.scene,self.ground,self.shadowGround=nil,nil,nil -- 不让已停止的大气模块继续持有场景/地表资源。
    self.active,self.stopped,self.realFog,self.shadowActive=false,true,false,false
end

return M
