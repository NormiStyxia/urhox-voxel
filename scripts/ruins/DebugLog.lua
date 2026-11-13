-- Opt-in diagnostics: no event owner, buffers or formatting while disabled.
local M = {enabled=false, interval=5, quality='high'}
local probes = {}
---@type Node?
local node
---@type LuaScriptObject?
local receiver
---@type string[]?
local recent
---@type number[]?
local histogram
local head,count,elapsed,frames,peak = 0,0,0,0,0
local CAPACITY,BINS = 200,1000
local function Write(level,tag,fmt,...)
    if not M.enabled then return end
    local ok,message = pcall(string.format,tostring(fmt),...)
    if not ok then message=tostring(fmt) end
    local line='['..level..':'..tostring(tag)..'] '..message
    head=head%CAPACITY+1; recent[head]=line; count=math.min(CAPACITY,count+1)
    print(line)
end
function M.Log(tag,fmt,...) if M.enabled then Write('debug',tag,fmt,...) end end
function M.Warn(tag,fmt,...) if M.enabled then Write('warn',tag,fmt,...) end end
function M.RegisterProbe(name,fn) probes[name]=fn end
function M.GetRecent(n)
    local result={}
    if not recent then return result end
    local take=math.min(count,math.max(0,math.floor(n or count)))
    for i=take-1,0,-1 do result[#result+1]=recent[(head-i-1)%CAPACITY+1] end
    return result
end
local function Summary()
    local total,threshold,p95=0,math.ceil(frames*.95),0
    for i=1,BINS do total=total+histogram[i]; if total>=threshold then p95=i; break end end
    M.Log('Perf','fps avg=%.1f min=%.1f frameP95=%dms quality=%s',frames/math.max(.001,elapsed),1/math.max(.001,peak),p95,M.quality)
    for name,fn in pairs(probes) do
        local ok,value=pcall(fn)
        if ok then
            if type(value)=='table' then
                local parts={}
                for key,item in pairs(value) do parts[#parts+1]=tostring(key)..'='..tostring(item) end
                table.sort(parts); value=table.concat(parts,' ')
            end
            M.Log(name,'%s',tostring(value))
        else M.Warn(name,'probe failed: %s',tostring(value)) end
    end
    elapsed,frames,peak=0,0,0
    for i=1,BINS do histogram[i]=0 end
end
---@param data VariantMap
local function Update(_,_,data)
    if not M.enabled then return end
    local dt=data:GetFloat('TimeStep')
    if dt<=0 then return end
    elapsed,frames,peak=elapsed+dt,frames+1,math.max(peak,dt)
    local bin=math.min(BINS,math.max(1,math.ceil(dt*1000)))
    histogram[bin]=histogram[bin]+1
    if elapsed>=M.interval then Summary() end
end
function M.SetEnabled(on)
    on=on==true
    if on==M.enabled then return end
    M.enabled=on
    if on then
        recent,histogram={},{}
        for i=1,BINS do histogram[i]=0 end
        head,count,elapsed,frames,peak=0,0,0,0,0
        node=Node(); receiver=node:CreateScriptObject('LuaScriptObject')
        receiver:SubscribeToEvent('Update',Update)
        M.Log('DebugLog','enabled; summary every %ds',M.interval)
    else
        if receiver then receiver:UnsubscribeFromAllEvents() end
        if node then node:Remove() end
        receiver,node,recent,histogram=nil,nil,nil,nil
        head,count,elapsed,frames,peak=0,0,0,0,0
    end
end
return M
