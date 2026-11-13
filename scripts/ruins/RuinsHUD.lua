-- Pixel HUD implemented as a UI.Panel subclass. UI owns the render event and
-- layout lifecycle; the whole display tree is pointerEvents="none".
local UI=require('urhox-libs/UI')
local Draw=require('ui.PixelDraw')
local Touch=require('ui.TouchInput')
local Controls=require('ui.TouchControls')
local M={}
local ready=false
local title,sub,hint,message,target,clockText='','','','','',''
local displayMessage=''
local messageFrame,hideFrame=3,0
local cool,cd={},{}
local charge,crossVisible,targetGold=0,true,false
local help=false
local C=Draw.colors
local Layer=UI.Panel:Extend('RuinsPixelHUD')
local function MobileText(text)
    if not Touch.IsEnabled() then return text end
    local t=text:gsub('按左键施放','按住【碎时】蓄力，松手施放'):gsub('按 Q 施放','点【回溯】施放')
        :gsub('按 E','点【冻结】'):gsub('按 F 骑乘，Space 起飞','点【上龙】骑乘，再点【起飞】')
        :gsub('%[Q 回溯%]','【回溯】'):gsub('按 Q','点【回溯】')
        :gsub('%[左键 碎时%]','【碎时】'):gsub('左键碎时','【碎时】')
    return t
end
-- Only the latest objective/hint/message layouts are retained (three bounded
-- slots, never a map keyed by arbitrary strings). Widths share their lifetime.
local objectiveCache,hintCache,messageCache={},{},{}
-- Wrap on UTF-8 codepoints at the actual 12/24px font advance, never shrink.
-- Exact prefix measurements are needed only on layout changes, not per frame.
---@param cached table
local function Lines(vg,cached,text,maxWidth,size,touch,mobile)
    if cached.valid and cached.vg==vg and cached.text==text and cached.width==maxWidth
        and cached.size==size and cached.touch==touch then
        return cached.lines,cached.widths
    end
    cached.vg,cached.text,cached.width,cached.size,cached.touch=vg,text,maxWidth,size,touch
    if mobile then text=MobileText(text) end
    -- PixelDraw returns 0 until its font is ready. Do not freeze zero-width
    -- wrapping into a valid cache; retry on the next render (Font throttles IO).
    local fontReady=text=='' or Draw.TextWidth(vg,'M',size)>0
    local result,widths,line={}, {},''
    ---@type number
    local lineWidth=0
    for _,code in utf8.codes(text) do
        local ch=utf8.char(code)
        if ch=='\n' then
            result[#result+1]=line; widths[#widths+1]=lineWidth
            line,lineWidth='',0
        else
            local nextLine=line..ch
            local nextWidth=fontReady and Draw.TextWidth(vg,nextLine,size) or 0
            if line~='' and nextWidth>maxWidth then
                result[#result+1]=line; widths[#widths+1]=lineWidth
                line,lineWidth=ch,Draw.TextWidth(vg,ch,size)
            else line,lineWidth=nextLine,nextWidth end
        end
    end
    if line~='' then result[#result+1]=line; widths[#widths+1]=lineWidth end
    cached.lines,cached.widths,cached.valid=result,widths,fontReady
    return result,widths
end
function Layer:Update(dt)
    messageFrame=math.min(3,messageFrame+1)
    if message=='' and hideFrame>0 then hideFrame=hideFrame-1 end
    if input:GetKeyPress(KEY_H) and not Touch.IsEnabled() then help=not help end
end
function Layer:Render(vg)
    Draw.Begin(vg,true) -- 全屏准星不继承父 UI 动画的局部变换。
    local w,h,s=Draw.Metrics()
    local touch=Touch.IsEnabled()
    local left,top=Draw.Snap(s.left+16),Draw.Snap(s.top+16)
    local ow=math.min(260,Draw.Snap(w-s.left-s.right-32))
    local lines=Lines(vg,objectiveCache,sub,ow-32,12,touch,true)
    local oh=math.max(72,48+#lines*16)
    Draw.NineSlice(vg,'plaque_ink',left,top,ow,oh,12,.9)
    Draw.Text(vg,'时之遗迹',left+16,top+18,12,C.gold)
    Draw.Text(vg,title,left+16,top+34,12,C.paper)
    for i,line in ipairs(lines) do Draw.Text(vg,line,left+16,top+50+(i-1)*16,12,C.muted) end
    local cw=math.max(120,Draw.Snap(Draw.TextWidth(vg,clockText,12)+48))
    local cy=top
    if w<620 then cy=top+oh+8 end
    Draw.NineSlice(vg,'plaque_ink',(w-cw)/2,cy,cw,48,12,.9)
    Draw.Text(vg,clockText,w/2,cy+24,12,C.gold,NVG_ALIGN_CENTER)
    if crossVisible then
        local x,y=math.floor(w/2),math.floor(h/2)
        local c=targetGold and C.bright or C.white
        Draw.Rect(vg,x-1,y-1,2,2,c)
        Draw.Rect(vg,x-1,y-13,2,6,c); Draw.Rect(vg,x-1,y+7,2,6,c)
        Draw.Rect(vg,x-13,y-1,6,2,c); Draw.Rect(vg,x+7,y-1,6,2,c)
        local text=MobileText(target)
        Draw.Text(vg,text,x+1,y+27,12,C.deep,NVG_ALIGN_CENTER)
        Draw.Text(vg,text,x,y+26,12,C.gold,NVG_ALIGN_CENTER)
    end
    if not touch then
        for i,b in ipairs({{name='shatter',key='左键'},{name='freeze',key='E'},{name='rewind',key='Q'}}) do
            local x,y=Draw.Snap(w/2+(i-2)*80),Draw.Snap(h-s.bottom-64)
            Draw.Button(vg,b,x,y,.78,false,false,false,cool[b.name] or 0,cd[b.name] or 1,b.name=='shatter' and charge or 0)
            Draw.Text(vg,b.key,x,y+44,12,C.gold,NVG_ALIGN_CENTER)
        end
    end
    local shownHint=touch and Controls.Hint() or hint
    if not touch and charge>0 then shownHint='碎时蓄力 · 松开左键释放' end
    if shownHint~='' then
        -- Keep the bottom-center strip in the gap left of the right action cluster.
        -- Longer air instructions wrap instead of covering glide/land buttons.
        local maxW=touch and math.max(96,math.min(340,w-s.left-s.right-470)) or math.min(640,w-40)
        local hs,widths=Lines(vg,hintCache,shownHint,maxW-32,12,touch,false)
        local hw=96
        for _,width in ipairs(widths) do hw=math.max(hw,Draw.Snap(width+32)) end
        local hh=math.max(48,24+#hs*16)
        local hx=Draw.Snap((w-hw)/2)
        if touch then hx=math.min(hx,w-s.right-290-hw) end
        hx=math.max(s.left+20,hx)
        local hy=Draw.Snap(math.max(h-s.bottom-150-hh/2,h/2+40))
        Draw.NineSlice(vg,'plaque_ink',hx,hy,hw,hh,12,.9)
        for i,line in ipairs(hs) do Draw.Text(vg,line,hx+hw/2,hy+hh/2+(i-(#hs+1)/2)*16,12,C.paper,NVG_ALIGN_CENTER) end
    end
    if message~='' or hideFrame>0 then
        local maxW=math.max(96,w-s.left-s.right-40)
        local ml,widths=Lines(vg,messageCache,displayMessage,maxW-88,24,touch,true)
        local mw=88
        for _,width in ipairs(widths) do mw=math.max(mw,Draw.Snap(width+88)) end
        local step=({-4,0,4,0})[messageFrame+1]
        mw=math.min(maxW,mw+step)
        local my=Draw.Snap(h*.22)
        local alpha=message=='' and hideFrame/2 or ({.34,.67,1,1})[messageFrame+1]
        Draw.Scroll(vg,(w-mw)/2,my,mw,alpha)
        for i,line in ipairs(ml) do Draw.Text(vg,line,w/2,my+48+(i-(#ml+1)/2)*26,24,C.brown,NVG_ALIGN_CENTER,alpha) end
    end
    if help and not touch then
        local hx=w-s.right-320
        Draw.NineSlice(vg,'panel_paper',hx,top,304,144,8,.95)
        for i,line in ipairs({'WASD 移动 · Shift 奔跑 · Space 跳跃','左键蓄力碎时 · E 冻结 · Q 回溯','F 上龙/下龙 · Space 起飞/上升','C 下降 · G 滑翔 · L 降落 · B 大招','Tab 远景 · 按住 T 快进时间','Esc 释放鼠标 · H 隐藏说明'}) do
            Draw.Text(vg,line,hx+16,top+22+(i-1)*20,12,C.brown)
        end
    end
    Draw.Finish(vg)
end
function M.Build(spells)
    objectiveCache,hintCache,messageCache={},{},{}
    if not ready then UI.Init({theme='default-dark',scale=UI.Scale.DEFAULT,
        fonts={{family='sans',weights={normal='Fonts/ArkPixel-12px-zh_hans.ttf',bold='Fonts/ArkPixel-12px-zh_hans.ttf'}}}}); ready=true end
    cd={}
    for _,sp in ipairs(spells) do cd[sp.id]=sp.cooldown end
    M.root=UI.Panel{width='100%',height='100%',pointerEvents='none',children={Layer{width='100%',height='100%',pointerEvents='none'}}}
    UI.SetRoot(M.root,true)
end
function M.SetObjective(t,s) title,sub=t or '',s or '' end
function M.SetClock(t) clockText=t or '' end
function M.SetHint(t) hint=t or '' end
function M.SetMessage(t)
    t=t or ''
    if t==message then return end
    message=t
    if t=='' then hideFrame=2 else displayMessage=t; messageFrame=0; hideFrame=0 end
end
function M.SetTarget(t,obj) target,targetGold=t or '',obj~=nil end
function M.SetCrossVisible(v) crossVisible=v end
function M.UpdateSlots(c,q) cool,charge=c or {},q or 0 end
function M.IsPointerOverUI() return UI.IsPointerOverUI() end
function M.Stop()
    objectiveCache,hintCache,messageCache={},{},{}
    Draw.Release(); UI.Shutdown(); ready=false
end
return M
