-- Pixel HUD implemented as a UI.Panel subclass. UI owns the render event and
-- layout lifecycle; the whole display tree is pointerEvents="none".
local UI=require('urhox-libs/UI')
local Draw=require('ui.PixelDraw')
local Touch=require('ui.TouchInput')
local Controls=require('ui.TouchControls')
local CombatHUD=require('ui.CombatHUD')
local M={}
local ready=false
local title,sub,hint,message,target,clockText='','','','','',''
local displayMessage=''
local messageFrame,hideFrame=3,0
local cool,cd={},{}
local charge,crossVisible,targetGold=0,true,false
local help=false
local C=Draw.colors
-- 三个法术的按键色：左键碎时红、E 冻结蓝、Q 回溯黄
local SPELL_COLORS={shatter={255,92,76},freeze={96,160,255},rewind={255,206,96}}
local Layer=UI.Panel:Extend('RuinsPixelHUD')
local function MobileText(text)
    if not Touch.IsEnabled() then return text end
    local t=text:gsub('按左键施放','按住【碎时】蓄力，松手施放'):gsub('按 Q 施放','点【回溯】施放')
        :gsub('按 E','点【冻结】'):gsub('按 F 骑乘，Space 起飞','点【上龙】骑乘，再点【起飞】')
        :gsub('%[Q 回溯%]','【回溯】'):gsub('按 Q','点【回溯】')
        :gsub('%[左键 碎时%]','【碎时】'):gsub('左键碎时','【碎时】')
    return t
end
-- 每个缓存槽只保留最新文本；测量与绘制共用 HUD 坐标和12px字体状态，
-- 同时记录 DPR 与整数 Zoom，防止转屏或设备密度变化后沿用旧字宽。
local headingCache,titleCache,objectiveCache,hintCache,messageCache,clockCache={},{},{},{},{},{}
---@param cached table
local function Lines(vg,cached,text,maxWidth,size,touch,mobile)
    local scale=graphics:GetDPR()*Draw.Zoom()
    if cached.valid and cached.vg==vg and cached.text==text and cached.width==maxWidth
        and cached.size==size and cached.touch==touch and cached.scale==scale then
        return cached.lines,cached.widths
    end
    cached.vg,cached.text,cached.width,cached.size,cached.touch,cached.scale=vg,text,maxWidth,size,touch,scale
    if mobile then text=MobileText(text) end
    -- 每个槽复用一个字形边界数组，避免每个前缀或每帧创建对象。
    local bounds=cached.bounds or {}; cached.bounds=bounds
    local fontReady=Draw.TextWidth(vg,'M',size,bounds)>0
    local result,widths,offsets={}, {}, {}
    local line=''
    local lineWidth,lineLeft,lineTop,lineBottom=0,0,-size/2,size/2
    local top,bottom=-size/2,size/2
    local function Append()
        result[#result+1]=line; widths[#widths+1]=lineWidth
        offsets[#offsets+1]=-lineLeft
        top,bottom=math.min(top,lineTop),math.max(bottom,lineBottom)
    end
    local function Measure(t)
        local advance=fontReady and Draw.TextWidth(vg,t,size,bounds) or 0
        local x0=fontReady and math.floor(math.min(0,bounds[1] or 0)) or 0
        local x1=fontReady and math.ceil(math.max(advance,bounds[3] or advance)) or 0
        return x1-x0,x0,fontReady and (bounds[2] or -size/2) or -size/2,
            fontReady and (bounds[4] or size/2) or size/2
    end
    -- CRLF 只算一次换行；末尾显式换行保留最后一个空行。
    text=text:gsub('\r\n','\n'):gsub('\r','\n')
    for _,code in utf8.codes(text) do
        local ch=utf8.char(code)
        if ch=='\n' then
            Append(); line,lineWidth,lineLeft,lineTop,lineBottom='',0,0,-size/2,size/2
        else
            local nextLine=line..ch
            local nextWidth,nextLeft,nextTop,nextBottom=Measure(nextLine)
            if line~='' and nextWidth>maxWidth then
                Append(); line=ch
                lineWidth,lineLeft,lineTop,lineBottom=Measure(ch)
            else
                line,lineWidth,lineLeft,lineTop,lineBottom=nextLine,nextWidth,nextLeft,nextTop,nextBottom
            end
        end
    end
    if text~='' then Append() end
    cached.lines,cached.widths,cached.offsets,cached.top,cached.bottom=result,widths,offsets,top,bottom
    cached.valid=fontReady -- 字体加载失败不缓存；PixelDraw.Font 会节流重试。
    return result,widths
end
-- NineSlice 的 border 单位是源图像素，固定以2倍铺贴。
-- 目标边框实际占24px，文字行盒与边框之间再留8px石板内底。
local OBJECTIVE_BORDER,OBJECTIVE_INSET,OBJECTIVE_LINE=12,32,16
local objectiveLayout={}
local function ObjectiveSize(vg,width,touch)
    local contentWidth=math.max(12,width-2*OBJECTIVE_INSET)
    Lines(vg,headingCache,'时之遗迹',contentWidth,12,touch,false)
    Lines(vg,titleCache,title,contentWidth,12,touch,true)
    Lines(vg,objectiveCache,sub,contentWidth,12,touch,true)
    local y0=math.min(headingCache.top,titleCache.top,objectiveCache.top)
    local y1=math.max(headingCache.bottom,titleCache.bottom,objectiveCache.bottom)
    local step=math.max(OBJECTIVE_LINE,math.ceil((y1-y0+4)/2)*2)
    local count=#headingCache.lines+#titleCache.lines+#objectiveCache.lines
    return 2*OBJECTIVE_INSET+count*step,step,(y0+y1)/2
end
local function ObjectiveRows(vg,cached,color,x,y,step,mid,row)
    for i,line in ipairs(cached.lines) do
        Draw.Text(vg,line,x+cached.offsets[i],y+(row+.5)*step-mid,12,color)
        row=row+1
    end
    return row
end
local function Objective(vg,w,h,s,touch)
    local left,top=Draw.Snap(s.left+16),Draw.Snap(s.top+16)
    -- 可用宽度向下对齐像素网格，不能向上取整越过右侧安全区。
    local available=math.max(0,math.floor((w-s.right-16-left)/2)*2)
    local baseWidth=math.min(w<620 and 360 or 260,available)
    local height=h-s.bottom-16-top
    local scale=graphics:GetDPR()*Draw.Zoom()
    local c=objectiveLayout
    if not c.valid or c.vg~=vg or c.width~=baseWidth or c.available~=available or c.height~=height
        or c.title~=title or c.sub~=sub or c.touch~=touch or c.scale~=scale then
        local oh,step,mid=ObjectiveSize(vg,baseWidth,touch)
        local ow=baseWidth
        -- 矮屏优先增加横向空间，再自适应高度。
        -- 不限制高度或行数，不允许静默丢弃任务末尾。
        if oh>height and ow<available then ow=available; oh,step,mid=ObjectiveSize(vg,ow,touch) end
        c.vg,c.width,c.available,c.height,c.title,c.sub,c.touch,c.scale=vg,baseWidth,available,height,title,sub,touch,scale
        c.ow,c.oh,c.step,c.mid=ow,oh,step,mid
        c.valid=headingCache.valid and titleCache.valid and objectiveCache.valid
    end
    local ow,oh,step,mid=c.ow,c.oh,c.step,c.mid
    Draw.NineSlice(vg,'plaque_ink',left,top,ow,oh,OBJECTIVE_BORDER,.9)
    local x,y=left+OBJECTIVE_INSET,top+OBJECTIVE_INSET
    nvgSave(vg)
    nvgIntersectScissor(vg,x,y,math.max(0,ow-2*OBJECTIVE_INSET),oh-2*OBJECTIVE_INSET)
    local row=ObjectiveRows(vg,headingCache,C.gold,x,y,step,mid,0)
    row=ObjectiveRows(vg,titleCache,C.paper,x,y,step,mid,row)
    ObjectiveRows(vg,objectiveCache,C.muted,x,y,step,mid,row)
    nvgRestore(vg)
    return left,top,ow,oh,available
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
    local left,top,ow,oh,available=Objective(vg,w,h,s,touch)
    local _,clockWidths=Lines(vg,clockCache,clockText,math.max(12,available-48),12,touch,false)
    local cw=120
    for _,width in ipairs(clockWidths) do cw=math.max(cw,math.ceil((width+48)/2)*2) end
    cw=math.min(available,cw)
    local ch=math.max(48,32+#clockCache.lines*16)
    local cx=Draw.Snap(math.max(left,math.min((w-cw)/2,w-s.right-16-cw)))
    local cy=top
    if CombatHUD.HasBoss() then cy=top+48 end
    -- 按真实矩形避让，而不是固定断点；宽任务卡和非对称安全区
    -- 同样不能与居中的时钟重叠。
    if cx<left+ow+8 then cy=top+oh+8 end
    Draw.NineSlice(vg,'plaque_ink',cx,cy,cw,ch,12,.9)
    for i,line in ipairs(clockCache.lines) do
        Draw.Text(vg,line,cx+cw/2,cy+ch/2+(i-(#clockCache.lines+1)/2)*16,12,C.gold,NVG_ALIGN_CENTER)
    end
    if crossVisible then
        local x,y=math.floor(w/2),math.floor(h/2)
        local c=CombatHUD.Active() and (CombatHUD.Aimed() and SPELL_COLORS.shatter or C.paper) or SPELL_COLORS.shatter
        Draw.Rect(vg,x-1,y-1,2,2,c)
        Draw.Rect(vg,x-1,y-13,2,6,c); Draw.Rect(vg,x-1,y+7,2,6,c)
        Draw.Rect(vg,x-13,y-1,6,2,c); Draw.Rect(vg,x+7,y-1,6,2,c)
        local text=MobileText(target)
        Draw.Text(vg,text,x+1,y+27,12,C.deep,NVG_ALIGN_CENTER)
        Draw.Text(vg,text,x,y+26,12,C.gold,NVG_ALIGN_CENTER)
    elseif target~='' then
        -- 平时不显示准星：目标说明放在技能栏上方
        local text=MobileText(target)
        local ty=Draw.Snap(h-s.bottom-(touch and 210 or 112))
        Draw.Text(vg,text,w/2+1,ty+1,12,C.deep,NVG_ALIGN_CENTER)
        Draw.Text(vg,text,w/2,ty,12,C.gold,NVG_ALIGN_CENTER)
    end
    if not touch and not CombatHUD.Active() then
        for i,b in ipairs({{name='shatter',key='左键'},{name='freeze',key='E'},{name='rewind',key='Q'}}) do
            local x,y=Draw.Snap(w/2+(i-2)*80),Draw.Snap(h-s.bottom-64)
            Draw.Button(vg,b,x,y,.78,false,false,false,cool[b.name] or 0,cd[b.name] or 1,b.name=='shatter' and charge or 0)
            Draw.Text(vg,b.key,x,y+44,12,SPELL_COLORS[b.name],NVG_ALIGN_CENTER)
        end
    end
    if not touch and CombatHUD.Active() then
        local list={{name='attack',icon=CombatHUD.Weapon(),key='左键'},{name='heavy',key='右键'},{name='dodge',key='Shift'},{name='swap',key='Q'}}
        for i,b in ipairs(list) do
            local x,y=Draw.Snap(w/2+(i-2.5)*80),Draw.Snap(h-s.bottom-64)
            Draw.Button(vg,b,x,y,.78,false,false,false,0,1,i==1 and CombatHUD.Charge() or 0)
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
    CombatHUD.Render(vg,w,h,s,{x=left,y=top,h=oh})
    Draw.Finish(vg)
end
function M.Build(spells)
    headingCache,titleCache,objectiveCache,hintCache,messageCache,clockCache={},{},{},{},{},{}
    objectiveLayout={}
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
function M.SetCrossVisible(v) crossVisible=v==true end
function M.IsCrossVisible() return crossVisible end
function M.UpdateSlots(c,q) cool,charge=c or {},q or 0 end
function M.IsPointerOverUI() return UI.IsPointerOverUI() end
function M.Stop()
    headingCache,titleCache,objectiveCache,hintCache,messageCache,clockCache={},{},{},{},{},{}
    objectiveLayout={}
    Draw.Release(); UI.Shutdown(); ready=false
end
return M
