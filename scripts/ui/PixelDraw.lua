-- Pixel primitives for UI.Panel subclasses. Coordinates are system logical dp.
-- UI owns the NanoVG frame; Begin/Finish compensate UI.Scale.DEFAULT density.
local UI = require('urhox-libs/UI')
local M = {}
M.colors = { ink={22,34,48}, deep={14,18,30}, gold={224,178,83}, bright={255,229,150},
    paper={236,218,172}, muted={157,179,194}, brown={58,42,24}, white={242,235,214} }
local contexts = setmetatable({}, {__mode='k'})
local cells = {}
local WHITE,DISABLED={255,255,255},{110,110,120}
local safeMetrics={left=0,right=0,top=0,bottom=0}
local metricsFrame,metricsW,metricsH,metricsScale,metricsDPR,metricsZoom
local colorCache={}
local numbers={}
function M.Number(n)
    local text=numbers[n]
    if not text then text=tostring(n); if n>=0 and n<=9999 and n%1==0 then numbers[n]=text end end
    return text
end
function M.Snap(n) return math.floor(n / 2 + .5) * 2 end
-- 大屏整数放大：逻辑短边每满 540dp 放大一倍，像素字体保持整数倍不糊。
function M.Zoom()
    local dpr = graphics:GetDPR()
    local w, h = graphics:GetWidth()/dpr, graphics:GetHeight()/dpr
    return math.max(1, math.min(3, math.floor(math.min(w/960, h/540))))
end
-- 换算物理像素到 HUD 坐标（触控命中与绘制共用）
function M.PixelToHUD()
    return 1/(graphics:GetDPR()*M.Zoom())
end
-- Borrowed read-only result; refresh once per engine frame so callers do not
-- repeatedly allocate UI.GetSafeAreaInsets' table/Rect wrappers.
function M.Metrics()
    local dpr,z=graphics:GetDPR(),M.Zoom()
    local w,h,scale=graphics:GetWidth(),graphics:GetHeight(),UI.GetScale()
    local timer=GetTime()
    local frame=timer.GetFrameNumber and timer:GetFrameNumber() or nil
    if frame==nil or frame~=metricsFrame or w~=metricsW or h~=metricsH or scale~=metricsScale or dpr~=metricsDPR or z~=metricsZoom then
        local factor=scale/dpr/z
        local s=UI.GetSafeAreaInsets()
        safeMetrics.left,safeMetrics.right,safeMetrics.top,safeMetrics.bottom=s.left*factor,s.right*factor,s.top*factor,s.bottom*factor
        metricsFrame,metricsW,metricsH,metricsScale,metricsDPR,metricsZoom=frame,w,h,scale,dpr,z
    end
    return w/dpr/z,h/dpr/z,safeMetrics
end

-- Track only this renderer's saves; unwind them after a protected HUD failure
-- without touching the parent UI widget's NanoVG transform/scissor stack.
local saveDepth={}
function M.Depth(vg) return saveDepth[vg] or 0 end
function M.Save(vg) nvgSave(vg);saveDepth[vg]=(saveDepth[vg] or 0)+1 end
function M.Restore(vg) nvgRestore(vg);saveDepth[vg]=math.max(0,(saveDepth[vg] or 0)-1) end
function M.Unwind(vg,depth) while M.Depth(vg)>depth do M.Restore(vg) end end
function M.Begin(vg, screenSpace)
    M.Save(vg)
    if screenSpace then nvgResetTransform(vg) end
    local k = graphics:GetDPR()*M.Zoom()/UI.GetScale()
    nvgScale(vg,k,k)
    nvgShapeAntiAlias(vg,0)
    nvgTextScaleMode(vg,NVG_TEXT_SCALE_FULL)
    nvgFontSizeMethod(vg,NVG_SIZE_PIXEL)
end
function M.Finish(vg) M.Restore(vg) end
local function Context(vg)
    local c = contexts[vg]
    if not c then c = {images={}, retry={}, paints={}, font=nvgCreateFont(vg,'ruins-pixel','Fonts/ArkPixel-12px-zh_hans.ttf')}; contexts[vg]=c end
    return c
end
local function Image(vg,name)
    local c = Context(vg)
    local handle = c.images[name] or 0
    local w,h=0,0
    if handle>0 then w,h=nvgImageSize(vg,handle) end
    if w and h and w>0 and h>0 then return handle,w,h end
    if handle>0 then nvgDeleteImage(vg,handle); c.paints[handle]=nil; c.images[name]=0 end
    local now=GetTime():GetElapsedTime()
    if now<(c.retry[name] or 0) then return nil end
    c.retry[name]=now+.25
    handle=nvgCreateImage(vg,'ui/touch/'..name..'.png',NVG_IMAGE_NEAREST) or 0
    c.images[name]=handle
    if handle<=0 then return nil end
    w,h=nvgImageSize(vg,handle)
    if not w or not h or w<=0 or h<=0 then return nil end
    return handle,w,h
end
local function Color(c,alpha)
    local a=math.max(0,math.min(255,math.floor((alpha or 1)*(c[4] or 255)+.5)))
    -- Key by value: other panels may pass a fresh RGB table every draw.
    -- Identity keys would retain a new paint/color for every such call.
    local r,g,b=math.floor(c[1]),math.floor(c[2]),math.floor(c[3])
    local key=((r*256+g)*256+b)*256+a
    local value=colorCache[key]
    if not value then value=nvgRGBA(r,g,b,a); colorCache[key]=value end
    return value
end
function M.Rect(vg,x,y,w,h,c,alpha)
    nvgBeginPath(vg); nvgRect(vg,x,y,w,h); nvgFillColor(vg,Color(c,alpha)); nvgFill(vg)
end
-- Paints are source-local, so moving/resizing a panel never creates another
-- paint. Integer alpha is also the color path's existing 8-bit precision.
local function Paint(vg,img,iw,ih,sx,sy,tint,alpha)
    local c=Context(vg)
    local byImage=c.paints[img]
    if not byImage or byImage.width~=iw or byImage.height~=ih then
        byImage={width=iw,height=ih};c.paints[img]=byImage
    end
    local key=sx+sy*iw
    local patch=byImage[key]
    if not patch then patch={};byImage[key]=patch end
    local color=Color(tint or WHITE,alpha)
    local paint=patch[color]
    if not paint then
        paint=nvgImagePatternTinted(vg,-sx*2,-sy*2,iw*2,ih*2,0,img,color)
        patch[color]=paint
    end
    return paint
end
function M.Image(vg,name,x,y,alpha,tint)
    local img,w,h=Image(vg,name)
    if not img then return end
    x,y=M.Snap(x),M.Snap(y)
    M.Save(vg); nvgTranslate(vg,x,y)
    nvgBeginPath(vg); nvgRect(vg,0,0,w*2,h*2)
    nvgFillPaint(vg,Paint(vg,img,w,h,0,0,tint,alpha)); nvgFill(vg)
    M.Restore(vg)
end
-- Preserve exact 2x source tiling (stretching would blur/distort pixel borders).
local function Tile(vg,img,iw,ih,sx,sy,sw,sh,x,y,w,h,alpha)
    if w<=0 or h<=0 or sw<=0 or sh<=0 then return end
    local paint=Paint(vg,img,iw,ih,sx,sy,nil,alpha)
    M.Save(vg); nvgIntersectScissor(vg,x,y,w,h)
    for yy=y,y+h-1,sh*2 do
        for xx=x,x+w-1,sw*2 do
            M.Save(vg);nvgTranslate(vg,xx,yy)
            nvgBeginPath(vg); nvgRect(vg,0,0,math.min(sw*2,x+w-xx),math.min(sh*2,y+h-yy))
            nvgFillPaint(vg,paint); nvgFill(vg);M.Restore(vg)
        end
    end
    M.Restore(vg)
end
function M.NineSlice(vg,name,x,y,w,h,border,alpha)
    local img,iw,ih=Image(vg,name)
    if not img then return end
    x,y,w,h=M.Snap(x),M.Snap(y),M.Snap(w),M.Snap(h)
    local b=border*2
    w,h=math.max(w,b*2),math.max(h,b*2)
    for j=1,3 do
        local sy=j==1 and 0 or (j==2 and border or ih-border)
        local sh=j==2 and ih-2*border or border
        local dy=j==1 and y or (j==2 and y+b or y+h-b)
        local dh=j==2 and h-2*b or b
        for i=1,3 do
            local sx=i==1 and 0 or (i==2 and border or iw-border)
            local sw=i==2 and iw-2*border or border
            local dx=i==1 and x or (i==2 and x+b or x+w-b)
            local dw=i==2 and w-2*b or b
            Tile(vg,img,iw,ih,sx,sy,sw,sh,dx,dy,dw,dh,alpha)
        end
    end
end
function M.Scroll(vg,x,y,w,alpha)
    local img,iw,ih=Image(vg,'banner_scroll')
    if not img then return end
    x,y,w=M.Snap(x),M.Snap(y),math.max(88,M.Snap(w))
    Tile(vg,img,iw,ih,0,0,16,ih,x,y,32,96,alpha)
    Tile(vg,img,iw,ih,16,0,iw-32,ih,x+32,y,w-64,96,alpha)
    Tile(vg,img,iw,ih,iw-16,0,16,ih,x+w-32,y,32,96,alpha)
end
local function Font(vg,size)
    local c=Context(vg)
    if c.font<0 then
        local now=GetTime():GetElapsedTime()
        if now<(c.fontRetry or 0) then return false end
        c.fontRetry=now+.25
        c.font=nvgCreateFont(vg,'ruins-pixel','Fonts/ArkPixel-12px-zh_hans.ttf')
        if c.font<0 then return false end
    end
    nvgFontFaceId(vg,c.font); nvgFontSize(vg,size==24 and 24 or 12)
    nvgFontBlur(vg,0); nvgTextLetterSpacing(vg,0)
    return true
end
function M.Text(vg,text,x,y,size,color,align,alpha)
    if not text or text=='' or not Font(vg,size) then return end
    nvgTextAlign(vg,(align or NVG_ALIGN_LEFT)+NVG_ALIGN_MIDDLE)
    nvgFillColor(vg,Color(color or M.colors.paper,alpha))
    nvgText(vg,math.floor(x+.5),math.floor(y+.5),text)
end
-- 可选的调用方边界数组由 NanoVG 复用，原有只取字宽的调用保持兼容。
-- 按 Text 的左对齐/垂直居中坐标测量，不继承前一段居中文本的对齐状态。
function M.TextWidth(vg,text,size,bounds)
    if not Font(vg,size) then return 0 end
    nvgTextAlign(vg,NVG_ALIGN_LEFT+NVG_ALIGN_MIDDLE)
    return nvgTextBounds(vg,0,0,text or '',bounds)
end
-- Clockwise pixel-grid sweep: 24 cooldown sectors, 32 charge sectors.
function M.Arc(vg,x,y,r,inner,fraction,segments,color,alpha)
    local byRadius=cells[r]
    if not byRadius then byRadius={}; cells[r]=byRadius end
    local byInner=byRadius[inner]
    if not byInner then byInner={};byRadius[inner]=byInner end
    local list=byInner[segments]
    if not list then
        list={}
        for yy=-r,r-2,2 do for xx=-r,r-2,2 do
            local dx,dy=xx+1,yy+1
            local d=dx*dx+dy*dy
            if d<=r*r and d>=inner*inner then
                local angle=(math.atan(dx,-dy)+math.pi*2)%(math.pi*2)
                list[#list+1]={xx,yy,math.floor(angle/(math.pi*2)*segments)}
            end
        end end
        byInner[segments]=list
    end
    local steps=math.ceil(math.max(0,math.min(1,fraction))*segments)
    x,y=M.Snap(x),M.Snap(y)
    nvgBeginPath(vg)
    for _,p in ipairs(list) do if p[3]<steps then nvgRect(vg,x+p[1],y+p[2],2,2) end end
    nvgFillColor(vg,Color(color,alpha)); nvgFill(vg)
end
function M.Button(vg,b,x,y,alpha,down,active,disabled,cool,total,charge)
    local size=b.size or 64
    local main=b.main or active
    local frame
    if size==80 then frame=main and (down and 'btn40_main_down' or 'btn40_main') or (down and 'btn40_down' or 'btn40')
    else frame=main and (down and 'btn32_main_down' or 'btn32_main') or (down and 'btn32_down' or 'btn32') end
    local shade=disabled and DISABLED or nil
    if disabled then alpha=alpha*.5 end
    M.Image(vg,frame,x-size/2,y-size/2,alpha,shade)
    local icon=b.icon or b.name
    if b.cachedIcon~=icon or b.cachedSize~=size then
        b.cachedIcon,b.cachedSize,b.imageName=icon,size,icon..(size==80 and '' or '_s')
    end
    M.Image(vg,b.imageName,x-(size==80 and 32 or 20),y-(size==80 and 32 or 20)+(down and 2 or 0),alpha,shade)
    if (cool or 0)>0 then
        M.Arc(vg,x,y,size/2-6,0,cool/math.max(.001,total or 1),24,M.colors.deep,.62*alpha)
        if cool>=1 then M.Text(vg,M.Number(math.ceil(cool)),x,y,12,M.colors.paper,NVG_ALIGN_CENTER,alpha) end
    end
    if (charge or 0)>0 then M.Arc(vg,x,y,size/2+6,size/2+2,charge,32,M.colors.bright,alpha) end
end
function M.Release()
    local live=require('urhox-libs/UI/Core/ImageCache').GetContext()
    for vg,c in pairs(contexts) do
        if vg==live then for _,h in pairs(c.images) do if h>0 then nvgDeleteImage(vg,h) end end end
    end
    contexts=setmetatable({},{__mode='k'})
    metricsFrame=nil
end
return M
