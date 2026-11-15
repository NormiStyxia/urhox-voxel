local DebugLog=require('ruins.DebugLog')
local M={}
-- Budgets centralized here. High preserves the current scene's shadow/grass/capture settings.
M.PROFILES={
 high={cloudCount=24,cloudsEnabled=true,lightShafts=8,motes=80,volumetric='full',grassDensity=1,grassDistance=55,shadowCascades=3,shadowDistance=140,shadowOn=true,shadowMapSize=2048,shadowPCFSamples=4,bloom=true,postFx='full',skyCaptureResolution=64,skyCaptureInterval=.5},
 medium={cloudCount=12,cloudsEnabled=true,lightShafts=3,motes=28,volumetric='lite',grassDensity=.5,grassDistance=38,shadowCascades=2,shadowDistance=65,shadowOn=true,shadowMapSize=1024,shadowPCFSamples=2,bloom=false,postFx='lite',skyCaptureResolution=32,skyCaptureInterval=2},
 low={cloudCount=4,cloudsEnabled=true,lightShafts=0,motes=0,volumetric='off',grassDensity=.25,grassDistance=24,shadowCascades=0,shadowDistance=0,shadowOn=false,shadowMapSize=512,shadowPCFSamples=1,bloom=false,postFx='off',skyCaptureResolution=32,skyCaptureInterval=5},
}
local allowed={quality={high=true,medium=true,low=true,auto=true},grass={full=true,half=true,off=true},shadows={high=true,low=true,off=true},postFx={full=true,lite=true,off=true}}
local booleanKeys={debugLog=true,perfHud=true,clouds=true,lowClouds=true,cloudShadow=true,lightShafts=true,floatingMotes=true,volumetric=true}
local optional={clouds=true,lowClouds=true,cloudShadow=true,lightShafts=true,floatingMotes=true,volumetric=true,grass=true,shadows=true,postFx=true}
local values,callbacks,listeners,order={},{},{},{}
local loaded,dirty,pending=false,false,0
local explicitQuality=false
local autoTier,autoElapsed,autoSum,autoFrames,slowWindows='high',0,0,0,0
---@type Node?
local node
---@type LuaScriptObject?
local receiver
---@type table?
local profile
local function DefaultTier()
    local platform=GetPlatform()
    if platform=='Android' or platform=='iOS' or (input and input.numTouches>0) then return 'medium' end
    return 'high'
end
local function Valid(key,value)
    if value==nil then return optional[key]==true end
    if booleanKeys[key] then return type(value)=='boolean' end
    return allowed[key]~=nil and allowed[key][value]==true
end
function M.Get(key) return values[key] end
function M.Resolve()
    local tier=values.quality=='auto' and autoTier or (values.quality or DefaultTier())
    local result={}
    for key,value in pairs(M.PROFILES[tier]) do result[key]=value end
    result.quality=tier
    if values.clouds~=nil then result.cloudsEnabled=values.clouds; result.cloudCount=values.clouds and math.max(tier=='low' and 4 or 12,result.cloudCount) or 0 end
    result.lowCloudsEnabled=result.cloudsEnabled and tier~='low' and values.lowClouds~=false
    result.cloudShadowEnabled=result.cloudsEnabled and tier~='low' and values.cloudShadow~=false
    if values.lightShafts~=nil then result.lightShafts=values.lightShafts and math.max(3,result.lightShafts) or 0 end
    if values.floatingMotes~=nil then result.motes=values.floatingMotes and math.max(28,result.motes) or 0 end
    if values.volumetric~=nil then result.volumetric=values.volumetric and 'full' or 'off' end
    if values.grass then result.grassDensity=({full=1,half=.5,off=0})[values.grass] end
    if values.shadows then
        local shadow=M.PROFILES[({high='high',low='medium',off='low'})[values.shadows]]
        for _,key in ipairs({'shadowCascades','shadowDistance','shadowOn','shadowMapSize','shadowPCFSamples'}) do result[key]=shadow[key] end
    end
    if values.postFx then result.postFx,result.bloom=values.postFx,values.postFx=='full' end
    return result
end
function M.Apply()
    profile=M.Resolve(); DebugLog.quality=profile.quality
    DebugLog.SetEnabled(values.debugLog==true)
    for _,name in ipairs(order) do
        local fn=callbacks[name]
        if fn then
            local ok,err=pcall(fn,profile)
            if not ok and DebugLog.enabled then DebugLog.Warn('Settings','%s: %s',name,tostring(err)) end
        end
    end
end
function M.GetProfile() return profile or M.Resolve() end
function M.RegisterQuality(name,fn)
    if not callbacks[name] and fn then
        local known=false
        for _,item in ipairs(order) do if item==name then known=true; break end end
        if not known then order[#order+1]=name end
    end
    callbacks[name]=fn
    if fn and loaded then fn(M.GetProfile()) end
end
function M.OnChange(fn)
    listeners[#listeners+1]=fn
    return function() for i,item in ipairs(listeners) do if item==fn then table.remove(listeners,i); break end end end
end
local function Notify(key) for _,fn in ipairs(listeners) do fn(key,values[key]) end end
local function StopTimer()
    if receiver then receiver:UnsubscribeFromAllEvents() end
    if node then node:Remove() end
    receiver,node=nil,nil
end
function M.Save()
    ---@type File?
    local file
    local ok,result=pcall(function()
        local encoded=cjson.encode({version=1,values=values,explicitQuality=explicitQuality})
        file=File('settings.json',FILE_WRITE)
        if not file or not file:IsOpen() then return false end
        return file:WriteString(encoded)==true
    end)
    if file then pcall(function() file:Close() end) end
    dirty=false -- No continuous retries on storage failure.
    if values.quality~='auto' then StopTimer() end
    if not ok or not result then
        if DebugLog.enabled then DebugLog.Warn('Settings','save unavailable; keeping session values') end
        return false
    end
    return true
end
---@param data VariantMap
local function Update(_,_,data)
    local dt=math.max(0,data:GetFloat('TimeStep'))
    if dirty then pending=pending+dt; if pending>=.5 then M.Save() end end
    if values.quality~='auto' then return end
    if dt<=0 or dt>1 or (input and (not input.focus or input.minimized)) then return end
    autoElapsed,autoSum,autoFrames=autoElapsed+dt,autoSum+dt,autoFrames+1
    if autoSum>=2 then
        local average=autoSum/autoFrames
        if average>1/28 then slowWindows=slowWindows+1 elseif average<1/34 then slowWindows=0 end
        autoSum,autoFrames=0,0
        if slowWindows>=3 and autoElapsed>=10 and autoTier~='low' then
            autoTier=autoTier=='high' and 'medium' or 'low'
            autoElapsed,slowWindows=0,0
            M.Apply(); Notify('quality')
        end
    end
end
local function StartTimer()
    if receiver then return end
    node=Node(); receiver=node:CreateScriptObject('LuaScriptObject')
    receiver:SubscribeToEvent('Update',Update)
end
function M.Set(key,value)
    if not Valid(key,value) then return false end
    local wasExplicit=explicitQuality
    if key=='quality' then explicitQuality=true end
    if values[key]==value and (key~='quality' or wasExplicit) then return true end
    values[key]=value
    if key=='quality' then autoTier=DefaultTier(); autoElapsed,autoSum,autoFrames,slowWindows=0,0,0,0 end
    dirty,pending=true,0
    if key=='quality' or optional[key] then M.Apply()
    elseif key=='debugLog' then DebugLog.SetEnabled(value) end
    Notify(key); StartTimer()
    return true
end
function M.TouchDetected()
    if loaded and not explicitQuality and values.quality=='high' then
        values.quality='medium'; M.Apply(); Notify('quality')
    end
end
function M.Load()
    StopTimer()
    values={quality=DefaultTier(),debugLog=false,perfHud=false}; explicitQuality=false
    ---@type File?
    local file
    local ok,data=pcall(function()
        -- 首次进入没有设置文件：先判断存在，避免引擎对不存在的文件打印 ERROR（Could not open file）。
        if fileSystem and not fileSystem:FileExists('settings.json') then return nil end
        file=File('settings.json',FILE_READ)
        if not file or not file:IsOpen() then return nil end
        return cjson.decode(file:ReadString())
    end)
    if file then pcall(function() file:Close() end) end
    if ok and type(data)=='table' and data.version==1 and type(data.values)=='table' then
        for key,value in pairs(data.values) do if Valid(key,value) then values[key]=value end end
        explicitQuality=data.explicitQuality~=false and data.values.quality~=nil
    end
    autoTier=DefaultTier(); autoElapsed,autoSum,autoFrames,slowWindows=0,0,0,0
    loaded,dirty,pending=true,false,0
    M.Apply()
    if values.quality=='auto' then StartTimer() end
    return values
end
function M.Stop()
    if dirty then M.Save() end
    StopTimer(); DebugLog.SetEnabled(false)
    callbacks,order,listeners={},{},{}; loaded=false
end
return M
