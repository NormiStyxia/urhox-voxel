-- 独立 HUDLayout 入口的渲染断言。
-- 配合 -validate-test=ui/tests/HUDLayoutAcceptance.lua 使用离屏渲染，不能用无图形模式。
-- 使用真实 NanoVG 字形边界检查完整文字，而不只是文字锚点。
local V=_G['V']
local UI=require('urhox-libs/UI')
local Draw=require('ui.PixelDraw')
local Touch=require('ui.TouchInput')
local oldBegin,oldFinish,oldNineSlice,oldText,oldWidth=Draw.Begin,Draw.Finish,Draw.NineSlice,Draw.Text,Draw.TextWidth
local oldGraphics,oldSafeArea=graphics,UI.GetSafeAreaInsets
local oldTouch=Touch.IsEnabled()
local bounds={}
local capture={}
local measureCount=0
local dpr=oldGraphics:GetDPR()
local safe=false
local caseIndex=0
local verified=0
local stable=0
local function Width(vg,text,size,scratch)
    measureCount=measureCount+1
    return oldWidth(vg,text,size,scratch)
end
Draw.TextWidth=Width
function Draw.Begin(vg,screen)
    oldBegin(vg,screen)
    capture={panels=0,title='',sub='',inside=true,rows=0}
    measureCount=0
end
function Draw.NineSlice(vg,name,x,y,w,h,border,alpha)
    oldNineSlice(vg,name,x,y,w,h,border,alpha)
    capture.panels=capture.panels+1
    if capture.panels==1 then
        capture.x,capture.y,capture.w,capture.h=x,y,w,h
    elseif capture.panels==2 then
        capture.clock={x=x,y=y,w=w,h=h}
    end
end
function Draw.Text(vg,text,x,y,size,color,align,alpha)
    if capture.panels==1 then
        capture.rows=capture.rows+1
        -- 生产绘制函数把锚点对齐到整数 HUD 坐标，断言必须使用同样的坐标。
        oldWidth(vg,text,size,bounds)
        local xx,yy=math.floor(x+.5),math.floor(y+.5)
        if text~='' then
            local fits=xx+bounds[1]>=capture.x+32-.01 and xx+bounds[3]<=capture.x+capture.w-32+.01
                and yy+bounds[2]>=capture.y+32-.01 and yy+bounds[4]<=capture.y+capture.h-32+.01
            capture.inside=capture.inside and fits
        end
        if color==Draw.colors.paper then capture.title=capture.title..text end
        if color==Draw.colors.muted then capture.sub=capture.sub..text end
    end
    oldText(vg,text,x,y,size,color,align,alpha)
end
local function MobileText(text)
    if not Touch.IsEnabled() then return text end
    return text:gsub('按左键施放','按住【碎时】蓄力，松手施放'):gsub('按 Q 施放','点【回溯】施放')
        :gsub('按 E','点【冻结】'):gsub('按 F 骑乘，Space 起飞','点【上龙】骑乘，再点【起飞】')
end
local function Flat(text) return MobileText(text):gsub('[\r\n]','') end
function Draw.Finish(vg)
    oldFinish(vg)
    if capture.panels<2 or caseIndex==0 then return end
    local fixture=_G['HUD_LAYOUT']
    if not fixture then return end
    local expected=fixture.cases[caseIndex]
    local key='用例'..caseIndex..' DPR='..dpr..' 安全区='..tostring(safe)..' 触控='..tostring(Touch.IsEnabled())
    -- 字体未就绪允许下帧重试；最终 verified 断言能检测所有未完成的用例。
    if capture.title~=Flat(expected[1]) or capture.sub~=Flat(expected[2]) then return end
    stable=stable+1
    if stable==2 then
        V.assert(capture.inside,key..' 每个完整字形都处于24px边框加8px内距之内')
        V.assert(capture.title==Flat(expected[1]) and capture.sub==Flat(expected[2]),key..' 标题与正文全文保留')
        local w,h,s=Draw.Metrics()
        V.assert(capture.x>=s.left and capture.x+capture.w<=w-s.right+.01,key..' 面板宽度位于安全区内')
        V.assert(capture.y+capture.h<=h-s.bottom+.01,key..' 完整面板高度位于安全区内')
        local clock=capture.clock
        V.assert(clock.x>=capture.x+capture.w+8 or clock.y>=capture.y+capture.h+8,key..' 时钟避开任务卡')
        V.assert(clock.x>=s.left and clock.x+clock.w<=w-s.right+.01,key..' 时钟宽度位于安全区内')
        V.assert(measureCount==0,key..' 稳定帧直接复用文本布局，不重新测量')
        verified=verified+1
    end
end
-- 仅测试使用的 DPR 代理：保留原始物理分辨率与真实 NanoVG 渲染器。
-- 此处覆盖生产缩放和缓存路径，但并非高DPI设备实测，仍需设备验收。
local function Mode(ratio,insets,touch)
    dpr=ratio; safe=insets
    graphics=setmetatable({GetDPR=function()return dpr end}, {__index=function(_,key)
        local value=oldGraphics[key]
        if type(value)=='function' then return function(_,...)return value(oldGraphics,...)end end
        return value
    end})
    UI.SetScale(UI.Scale.DEFAULT)
    UI.GetSafeAreaInsets=function()
        if not safe then return oldSafeArea() end
        local factor=dpr*Draw.Zoom()/UI.GetScale()
        return {left=12*factor,right=22*factor,top=10*factor,bottom=12*factor}
    end
    if Touch.IsEnabled()~=touch then Touch.Toggle() end
end
local frame=6
for _,mode in ipairs({{1,false,false},{2,true,false},{2,true,true}}) do
    local ratio,insets,touch=mode[1],mode[2],mode[3]
    V.atFrame(frame,function()Mode(ratio,insets,touch)end)
    for i=1,7 do
        local index=i
        V.atFrame(frame+1,function()
            caseIndex=index; stable=0
            _G['HUD_LAYOUT'].Show(index)
        end)
        frame=frame+5
    end
end
V.atFrame(frame+2,function()
    V.assert(verified==21,'七组全文用例均通过DPR1、DPR2与触控安全区验证')
    Draw.Begin,Draw.Finish,Draw.NineSlice,Draw.Text,Draw.TextWidth=oldBegin,oldFinish,oldNineSlice,oldText,oldWidth
    graphics=oldGraphics; UI.GetSafeAreaInsets=oldSafeArea; UI.SetScale(UI.Scale.DEFAULT)
    if Touch.IsEnabled()~=oldTouch then Touch.Toggle() end
    V.finish()
end)
