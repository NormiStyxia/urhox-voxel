-- 灯光段唯一挂接入口；5Hz 联动，低云/高云/云影/光柱/浮光/真实体积雾分别开关。
local Clouds = require("ruins.SkyClouds")
local Shafts = require("ruins.LightShafts")
local Motes = require("ruins.FloatingMotes")
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
    self.active,self.stopped,self.realFog,self.shadowActive = false,false,false,false
    self.settingsManaged = GameSettings~=nil
    self.features = {}
    for k,v in pairs(Quality.FEATURES) do self.features[k] = v end
    self.elapsed,self.clock = 0.2,0
    ---@type Material|nil
    self.ground = nil
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
        local key=({clouds="clouds",lowClouds="lowClouds",cloudShadow="cloudShadow",shafts="lightShafts",motes="floatingMotes",volumetric="volumetric",bloom="postFx"})[name]
        return GameSettings.Set(key,name=="bloom" and (enabled==true and "full" or "off") or enabled==true)
    end
    self.features[name] = enabled==true
    self:ApplySwitches()
end

function M:ApplySwitches()
    if self.stopped then return end
    local p,f = self.profile,self.features
    local count = p.cloudsEnabled and math.max(0,math.min(24,math.floor(p.cloudCount or 0))) or 0
    local upper,lower = f.clouds==true,f.lowClouds==true
    if self.clouds and (count~=self.clouds.budget or upper~=self.clouds.upper or lower~=self.clouds.lower) then
        self.clouds:Dispose(); self.clouds=nil
    end
    if count>0 and (upper or lower) and not self.clouds then self.clouds=Clouds.New(self.scene,count,upper,lower) end
    local shafts = f.shafts and math.max(0,math.min(8,math.floor(p.lightShafts or 0))) or 0
    if self.shafts and shafts~=self.shafts.count then self.shafts:Dispose(); self.shafts=nil end
    if shafts>0 and not self.shafts then self.shafts=Shafts.New(self.scene,shafts) end
    local motes = f.motes and math.max(0,math.min(120,math.floor(p.motes or 0))) or 0
    if self.motes and motes~=self.motes.count then self.motes:Dispose(); self.motes=nil end
    if motes>0 and not self.motes then self.motes=Motes.New(self.scene,motes) end
    self.realFog=Quality.ApplyVolume(self.dayNight.zone,self.dayNight.sun,p.volumetric or "off",f.volumetric and p.shadowOn~=false)
    if not self.settingsManaged then Quality.ApplyStandaloneScene(self.dayNight.zone,self.dayNight.sun,p,f.bloom) end
    self.shadowActive=count>0 and f.cloudShadow==true
    self.active=self.clouds~=nil or self.shafts~=nil or self.motes~=nil or self.shadowActive
    if self.shafts then self.shafts:Update(self.dayNight,true,self.realFog) end
    if self.ground then
        self.ground:SetShaderParameter("cloud_shadow_strength",Variant(self.shadowActive and 0.16 or 0))
    end
    self.elapsed = 0.2
end

---@param position Vector3 玩家/骑乘位置，不跟随拉远的观察相机
---@param ground Material|nil
function M:Update(dt,position,ground)
    if not self.active or self.stopped then return end
    self.clock,self.elapsed = self.clock+math.max(0,dt),self.elapsed+math.max(0,dt)
    if ground~=self.ground then
        self.ground=ground
        if ground then ground:SetShaderParameter("cloud_shadow_strength",Variant(self.shadowActive and 0.16 or 0)) end
    end
    if self.elapsed<0.2 then return end
    local step = self.elapsed
    self.elapsed = 0
    local dn = self.dayNight
    if self.clouds then self.clouds:Update(step,dn.day or 1,dn.dusk or 0) end
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
        motesMax=self.motes and self.motes.count or 0,volume=self.realFog,
        active=self.active,quality=self.quality,cloudShadow=self.shadowActive,
        batches=(self.clouds and self.clouds.batchCount or 0)+(self.shafts and 1 or 0)+(self.motes and 1 or 0)}
end

function M:Stop()
    if self.stopped then return end
    if GameSettings then GameSettings.RegisterQuality("skyfx",nil) end
    if DebugLog then DebugLog.RegisterProbe("skyfx",nil) end
    if self.clouds then self.clouds:Dispose(); self.clouds=nil end
    if self.shafts then self.shafts:Dispose(); self.shafts=nil end
    if self.motes then self.motes:Dispose(); self.motes=nil end
    if self.ground then self.ground:SetShaderParameter("cloud_shadow_strength",Variant(0)) end
    Quality.ApplyVolume(self.dayNight.zone,self.dayNight.sun,"off",false)
    self.scene,self.ground=nil,nil -- 不让已停止的大气模块继续持有场景/地表资源。
    self.active,self.stopped,self.realFog,self.shadowActive=false,true,false,false
end

return M
