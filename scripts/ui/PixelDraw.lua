-- Pixel primitives for UI.Panel subclasses. Coordinates are system logical dp.
-- UI owns the NanoVG frame; Begin/Finish compensate UI.Scale.DEFAULT density.
local UI = require('urhox-libs/UI')
local M = {}
M.colors = { ink={22,34,48}, deep={14,18,30}, gold={224,178,83}, bright={255,229,150},
    paper={236,218,172}, muted={157,179,194}, brown={58,42,24}, white={242,235,214} }
local contexts = setmetatable({}, {__mode='k'})
local cells = {}
function M.Snap(n) return math.floor(n / 2 + .5) * 2 end
function M.Metrics()
    local dpr = graphics:GetDPR()
    local factor = UI.GetScale() / dpr
    local s = UI.GetSafeAreaInsets()
    return graphics:GetWidth()/dpr, graphics:GetHeight()/dpr,
        {left=s.left*factor, right=s.right*factor, top=s.top*factor, bottom=s.bottom*factor}
end
function M.Begin(vg, screenSpace)
    nvgSave(vg)
    if screenSpace then nvgResetTransform(vg) end
    local k = graphics:GetDPR()/UI.GetScale()
    nvgScale(vg,k,k)
    nvgShapeAntiAlias(vg,0)
    nvgTextScaleMode(vg,NVG_TEXT_SCALE_FULL)
    nvgFontSizeMethod(vg,NVG_SIZE_PIXEL)
end
function M.Finish(vg) nvgRestore(vg) end
local function Context(vg)
    local c = contexts[vg]
    if not c then c = {images={}, retry={}, font=nvgCreateFont(vg,'ruins-pixel','Fonts/ArkPixel-12px-zh_hans.ttf')}; contexts[vg]=c end
    return c
end
local function Image(vg,name)
    local c = Context(vg)
    local handle = c.images[name] or 0
    local w,h=0,0
    if handle>0 then w,h=nvgImageSize(vg,handle) end
    if w and h and w>0 and h>0 then return handle,w,h end
    if handle>0 then nvgDeleteImage(vg,handle); c.images[name]=0 end
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
    return nvgRGBA(c[1],c[2],c[3],math.floor((alpha or 1)*(c[4] or 255)+.5))
end
function M.Rect(vg,x,y,w,h,c,alpha)
    nvgBeginPath(vg); nvgRect(vg,x,y,w,h); nvgFillColor(vg,Color(c,alpha)); nvgFill(vg)
end
function M.Image(vg,name,x,y,alpha,tint)
    local img,w,h=Image(vg,name)
    if not img then return end
    x,y=M.Snap(x),M.Snap(y)
    nvgBeginPath(vg); nvgRect(vg,x,y,w*2,h*2)
    nvgFillPaint(vg,nvgImagePatternTinted(vg,x,y,w*2,h*2,0,img,Color(tint or {255,255,255},alpha)))
    nvgFill(vg)
end
-- Tile source patches at exactly 2x; only the last tile is clipped.
local function Tile(vg,img,iw,ih,sx,sy,sw,sh,x,y,w,h,alpha)
    if w<=0 or h<=0 or sw<=0 or sh<=0 then return end
    nvgSave(vg); nvgIntersectScissor(vg,x,y,w,h)
    for yy=y,y+h-1,sh*2 do
        for xx=x,x+w-1,sw*2 do
            nvgBeginPath(vg); nvgRect(vg,xx,yy,math.min(sw*2,x+w-xx),math.min(sh*2,y+h-yy))
            nvgFillPaint(vg,nvgImagePattern(vg,xx-sx*2,yy-sy*2,iw*2,ih*2,0,img,alpha or 1)); nvgFill(vg)
        end
    end
    nvgRestore(vg)
end
function M.NineSlice(vg,name,x,y,w,h,border,alpha)
    local img,iw,ih=Image(vg,name)
    if not img then return end
    x,y,w,h=M.Snap(x),M.Snap(y),M.Snap(w),M.Snap(h)
    local b=border*2
    w,h=math.max(w,b*2),math.max(h,b*2)
    local xs,ys={0,border,iw-border},{0,border,ih-border}
    local sw,sh={border,iw-2*border,border},{border,ih-2*border,border}
    local dx,dy={x,x+b,x+w-b},{y,y+b,y+h-b}
    local dw,dh={b,w-2*b,b},{b,h-2*b,b}
    for j=1,3 do for i=1,3 do Tile(vg,img,iw,ih,xs[i],ys[j],sw[i],sh[j],dx[i],dy[j],dw[i],dh[j],alpha) end end
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
function M.TextWidth(vg,text,size)
    if not Font(vg,size) then return 0 end
    return nvgTextBounds(vg,0,0,text or '')
end
-- Clockwise pixel-grid sweep: 24 cooldown sectors, 32 charge sectors.
function M.Arc(vg,x,y,r,inner,fraction,segments,color,alpha)
    local key=r..':'..inner..':'..segments
    local list=cells[key]
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
        cells[key]=list
    end
    local steps=math.ceil(math.max(0,math.min(1,fraction))*segments)
    x,y=M.Snap(x),M.Snap(y)
    nvgBeginPath(vg)
    for _,p in ipairs(list) do if p[3]<steps then nvgRect(vg,x+p[1],y+p[2],2,2) end end
    nvgFillColor(vg,Color(color,alpha)); nvgFill(vg)
end
function M.Button(vg,b,x,y,alpha,down,active,disabled,cool,total,charge)
    local size=b.size or 64
    local frame=(size==80 and 'btn40' or 'btn32')..((b.main or active) and '_main' or '')..(down and '_down' or '')
    local shade=disabled and {110,110,120} or nil
    if disabled then alpha=alpha*.5 end
    M.Image(vg,frame,x-size/2,y-size/2,alpha,shade)
    local icon=b.icon or b.name
    M.Image(vg,icon..(size==80 and '' or '_s'),x-(size==80 and 32 or 20),y-(size==80 and 32 or 20)+(down and 2 or 0),alpha,shade)
    if (cool or 0)>0 then
        M.Arc(vg,x,y,size/2-6,0,cool/math.max(.001,total or 1),24,M.colors.deep,.62*alpha)
        if cool>=1 then M.Text(vg,tostring(math.ceil(cool)),x,y,12,M.colors.paper,NVG_ALIGN_CENTER,alpha) end
    end
    if (charge or 0)>0 then M.Arc(vg,x,y,size/2+6,size/2+2,charge,32,M.colors.bright,alpha) end
end
function M.Release()
    local live=require('urhox-libs/UI/Core/ImageCache').GetContext()
    for vg,c in pairs(contexts) do
        if vg==live then for _,h in pairs(c.images) do if h>0 then nvgDeleteImage(vg,h) end end end
    end
    contexts=setmetatable({},{__mode='k'})
end
return M
