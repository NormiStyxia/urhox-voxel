-- Shares the HUD's UI.Panel/PixelDraw pipeline (logical dp, 2x nearest assets).
local UI=require('urhox-libs/UI')
local Draw=require('ui.PixelDraw')
local Settings=require('ruins.GameSettings')
local DebugLog=require('ruins.DebugLog')
local TouchInput=require('ui.TouchInput')
local M={open=false}
---@type Widget?
local parent
---@type Widget?
local layer
---@type Node?
local eventNode
---@type LuaScriptObject?
local receiver
---@type fun(boolean)?
local changed
local page,advancedPage=1,1
local buttons={}
local information={}
local releaseLatch=false
local WIDTH,HEIGHT=0,0
local box={x=0,y=0,w=0,h=0}
local TAB_NAMES={'画质','高级','调试'}
local QUALITY={'high','medium','low','auto'}
local QUALITY_NAMES={high='高',medium='中',low='低',auto='自动'}
local DESCRIPTIONS={high='完整草地、远景阴影与天空特效',medium='半量草地、近景阴影，减少特效',low='稀疏草地，关闭阴影与天空特效',auto='持续低于28帧自动降档，只降不升'}
local ADVANCED={{'clouds','云层'},{'lowClouds','低空云'},{'cloudShadow','地面云影'},{'lightShafts','光柱'},{'floatingMotes','浮光'},{'volumetric','体积光'},{'grass','草地'},{'shadows','阴影'},{'postFx','后效'}}
local ENUMS={grass={'follow','full','half','off'},shadows={'follow','high','low','off'},postFx={'follow','full','lite','off'}}
local VALUE_NAMES={follow='跟随画质',full='完整',half='半量',off='关闭',high='高',low='低',lite='精简'}
local RELEASE_KEYS={KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT,KEY_SPACE,KEY_1,KEY_2,KEY_3,KEY_E,KEY_Q,KEY_F,KEY_T,KEY_TAB,KEY_C,KEY_B,KEY_G,KEY_L}
function M.IsOpen() return M.open end
function M.IsBlocked() return M.open or releaseLatch end
local function Add(label,x,y,w,h,action,active)
    buttons[#buttons+1]={label=label,x=x,y=y,w=w,h=h,action=action,active=active}
end
local function Cycle(key)
    local value=Settings.Get(key)
    local list=ENUMS[key]
    if list then
        local index=1
        for i,item in ipairs(list) do if item==value then index=i; break end end
        local nextValue=list[index%#list+1]
        Settings.Set(key,nextValue~='follow' and nextValue or nil)
    elseif value==nil then Settings.Set(key,true)
    elseif value then Settings.Set(key,false)
    else Settings.Set(key,nil) end
end
local function Layout()
    local w,h,safe=Draw.Metrics()
    WIDTH,HEIGHT=w,h
    box.w=math.floor(math.min(600,w-safe.left-safe.right-40)/2)*2
    box.h=math.floor(math.min(350,h-safe.top-safe.bottom-40)/2)*2
    box.x=Draw.Snap(safe.left+(w-safe.left-safe.right-box.w)/2)
    box.y=Draw.Snap(safe.top+(h-safe.top-safe.bottom-box.h)/2)
    buttons={}; information={}
    local function Info(line)
        local limit=math.max(1,math.floor((box.w-40)/12))
        local count=utf8.len(line) or 0
        for first=1,count,limit do
            local a=utf8.offset(line,first)
            local b=utf8.offset(line,math.min(count+1,first+limit)) or (#line+1)
            information[#information+1]=line:sub(a,b-1)
        end
    end
    if page==1 then
        Info(DESCRIPTIONS[Settings.Get('quality')])
        Info('高级选项单独覆盖，即时生效')
        Info('后效关闭保留基础色调映射')
    end
    local x,y,bw=box.x+16,box.y+48,box.w-32
    local tw=math.floor(bw/3/2)*2
    for i,name in ipairs(TAB_NAMES) do Add(name,x+(i-1)*tw,y,tw-4,44,function() page=i; Layout() end,page==i) end
    y=y+50
    if page==1 then
        local qw=math.floor(bw/4/2)*2
        for i,key in ipairs(QUALITY) do Add(QUALITY_NAMES[key],x+(i-1)*qw,y,qw-4,44,function() Settings.Set('quality',key); Layout() end,Settings.Get('quality')==key) end
    elseif page==2 then
        local rows=math.max(1,math.floor((box.h-196)/44))
        local pages=math.ceil(#ADVANCED/rows)
        advancedPage=math.min(advancedPage,pages)
        for i=(advancedPage-1)*rows+1,math.min(#ADVANCED,advancedPage*rows) do
            local entry=ADVANCED[i]
            local key=entry[1]
            local value=Settings.Get(key)
            local label=value==nil and '跟随画质' or (value==true and '开启' or (value==false and '关闭' or VALUE_NAMES[value]))
            Add(entry[2]..'：'..label,x,y,bw,44,function() Cycle(key); Layout() end,false)
            y=y+44
        end
        Add('上一页',x,box.y+box.h-96,bw/2-4,44,function() advancedPage=(advancedPage-2)%pages+1; Layout() end,false)
        Add('下一页',x+bw/2,box.y+box.h-96,bw/2-4,44,function() advancedPage=advancedPage%pages+1; Layout() end,false)
    else
        Add('调试日志：'..(Settings.Get('debugLog') and '开启' or '关闭'),x,y,bw,44,function() Settings.Set('debugLog',not Settings.Get('debugLog')); Layout() end,Settings.Get('debugLog'))
        Add('性能小字：'..(Settings.Get('perfHud') and '开启' or '关闭'),x,y+44,bw,44,function() Settings.Set('perfHud',not Settings.Get('perfHud')); Layout() end,Settings.Get('perfHud'))
        Add('打印最近日志',x,y+88,bw,44,function() for _,line in ipairs(DebugLog.GetRecent(40)) do print(line) end end,false)
    end
    Add('关闭 · 返回游戏',x,box.y+box.h-48,bw,44,function() M.Close() end,false)
end
local Layer=UI.Panel:Extend('RuinsSettingsMenu')
function Layer:Render(vg)
    local w,h=Draw.Metrics()
    if w~=WIDTH or h~=HEIGHT then Layout() end
    Draw.Begin(vg,true)
    Draw.Rect(vg,0,0,w,h,Draw.colors.deep,.72)
    Draw.NineSlice(vg,'panel_paper',box.x,box.y,box.w,box.h,8,1)
    Draw.Text(vg,'旅途设置',box.x+box.w/2,box.y+26,24,Draw.colors.brown,NVG_ALIGN_CENTER)
    for _,b in ipairs(buttons) do
        Draw.Rect(vg,b.x,b.y,b.w,b.h-4,b.active and Draw.colors.gold or Draw.colors.ink)
        Draw.Text(vg,b.label,b.x+b.w/2,b.y+20,12,b.active and Draw.colors.brown or Draw.colors.paper,NVG_ALIGN_CENTER)
    end
    if page==1 then
        Draw.Text(vg,'实际档位：'..QUALITY_NAMES[Settings.GetProfile().quality],box.x+20,box.y+160,12,Draw.colors.brown)
        local maxRows=math.max(0,math.floor((box.h-226)/20))
        for i=1,math.min(#information,maxRows) do
            Draw.Text(vg,information[i],box.x+20,box.y+180+(i-1)*20,12,Draw.colors.brown)
        end
    end
    Draw.Finish(vg)
end
function M.Click(x,y)
    if not M.open then return end
    for _,b in ipairs(buttons) do
        if x>=b.x and x<b.x+b.w and y>=b.y and y<b.y+b.h then b.action(); return end
    end
end
local function ReleaseEvents()
    if receiver then receiver:UnsubscribeFromAllEvents() end
    if eventNode then eventNode:Remove() end
    receiver,eventNode=nil,nil
end
---@param data VariantMap
local function WaitForRelease(_,_,data)
    if input.numTouches>0 or input:GetMouseButtonDown(MOUSEB_LEFT) or input:GetMouseButtonDown(MOUSEB_RIGHT) or input:GetMouseButtonDown(MOUSEB_MIDDLE) then return end
    for _,key in ipairs(RELEASE_KEYS) do if input:GetKeyDown(key) then return end end
    releaseLatch=false; ReleaseEvents()
    if changed then changed(false) end
end
function M.Open()
    if M.open then return true end
    if not parent then return false end
    ReleaseEvents(); releaseLatch=false; M.open=true; page=1
    if changed then changed(true) end
    Layout()
    layer=Layer{position='absolute',left=0,top=0,width='100%',height='100%',pointerEvents='none'}
    parent:AddChild(layer)
    eventNode=Node(); receiver=eventNode:CreateScriptObject('LuaScriptObject')
    receiver:SubscribeToEvent('MouseButtonDown',function(_,_,data)
        if TouchInput.IsEnabled() or data:GetInt('Button')~=MOUSEB_LEFT then return end
        local k=Draw.PixelToHUD()
        M.Click(data:GetInt('X')*k,data:GetInt('Y')*k)
    end)
    return true
end
function M.Close()
    if not M.open then return end
    M.open=false; releaseLatch=true
    if layer and parent then parent:RemoveChild(layer) end
    layer=nil; buttons={}; ReleaseEvents()
    -- Stay blocked through the closing click and held movement/skill keys.
    eventNode=Node(); receiver=eventNode:CreateScriptObject('LuaScriptObject')
    receiver:SubscribeToEvent('Update',WaitForRelease)
end
function M.Toggle() if M.open then M.Close() else M.Open() end end
function M.Attach(root,onChanged)
    if layer and parent then parent:RemoveChild(layer) end
    layer=nil; parent=root; changed=onChanged
    if M.open then M.open=false; M.Open() end
end
function M.Stop()
    ReleaseEvents()
    if layer and parent then parent:RemoveChild(layer) end
    layer,parent,changed=nil,nil,nil; buttons={}; M.open=false; releaseLatch=false
end
return M
