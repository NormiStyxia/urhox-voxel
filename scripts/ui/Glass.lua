-- Clean "dark glass" drawing helpers for modern (non-pixel) panels.
-- Coordinates share ui.PixelDraw's logical space (Begin/Metrics/PixelToHUD), but
-- shapes are anti-aliased and text uses MiSans. Pixel icons still go through
-- PixelDraw.Image so the 2x NEAREST path is reused.
local Draw = require('ui.PixelDraw')
local M = {}
M.colors = {
    panel={14,22,36}, panelEdge={201,168,96}, ice={132,190,240},
    card={26,38,58}, cardHi={44,58,84}, cardSel={52,60,78},
    text={236,240,247}, sub={150,166,188}, dim={104,118,140},
    gold={232,196,110}, goldDeep={196,150,64}, ink={34,26,12},
    good={120,214,150}, bad={238,124,124}, black={0,0,0},
}
local SIZE_FALLBACK=function(size) return size>=20 and 24 or 12 end
local contexts=setmetatable({},{__mode='k'})
local colorCache={}
local function Color(c,alpha)
    local a=math.max(0,math.min(255,math.floor((alpha or 1)*(c[4] or 255)+.5)))
    local r,g,b=math.floor(c[1]),math.floor(c[2]),math.floor(c[3])
    local key=((r*256+g)*256+b)*256+a
    local value=colorCache[key]
    if not value then value=nvgRGBA(r,g,b,a);colorCache[key]=value end
    return value
end
M.Color=Color
function M.Begin(vg)
    Draw.Begin(vg,true)
    nvgShapeAntiAlias(vg,1)
end
function M.Finish(vg) Draw.Finish(vg) end
local function Font(vg)
    local c=contexts[vg]
    if not c then c={font=-1,retry=0};contexts[vg]=c end
    if c.font>=0 then return c.font end
    local now=time:GetElapsedTime()
    if now<c.retry then return -1 end
    c.retry=now+.5
    local font=nvgCreateFont(vg,'glass-sans','Fonts/MiSans-Regular.ttf')
    c.font=font or -1
    return c.font
end
function M.Round(vg,x,y,w,h,r,color,alpha)
    nvgBeginPath(vg);nvgRoundedRect(vg,x,y,w,h,r);nvgFillColor(vg,Color(color,alpha));nvgFill(vg)
end
function M.Stroke(vg,x,y,w,h,r,color,alpha,width)
    nvgBeginPath(vg);nvgRoundedRect(vg,x+.5,y+.5,w-1,h-1,math.max(0,r-.5))
    nvgStrokeColor(vg,Color(color,alpha));nvgStrokeWidth(vg,width or 1);nvgStroke(vg)
end
--- Vertical two-stop gradient fill. Paints are memoised per (rect, colours) so a
--- steady frame allocates nothing; falls back to the top colour on failure.
local paints=setmetatable({},{__mode='k'})
function M.Gradient(vg,x,y,w,h,r,top,bottom,alpha)
    local cTop,cBottom=Color(top,alpha),Color(bottom,alpha)
    local byVg=paints[vg]
    if not byVg then byVg={};paints[vg]=byVg end
    local key=(x*31+y)*31+h+top[1]*7+bottom[3]*13+(alpha or 1)
    local entry=byVg[key]
    if not entry or entry.x~=x or entry.y~=y or entry.h~=h or entry.top~=cTop or entry.bottom~=cBottom then
        local ok,paint=pcall(nvgLinearGradient,vg,x,y,x,y+h,cTop,cBottom)
        entry={x=x,y=y,h=h,top=cTop,bottom=cBottom,paint=ok and paint or false}
        byVg[key]=entry
    end
    nvgBeginPath(vg);nvgRoundedRect(vg,x,y,w,h,r)
    if entry.paint then nvgFillPaint(vg,entry.paint) else nvgFillColor(vg,cTop) end
    nvgFill(vg)
end
function M.Circle(vg,x,y,r,color,alpha)
    nvgBeginPath(vg);nvgCircle(vg,x,y,r);nvgFillColor(vg,Color(color,alpha));nvgFill(vg)
end
function M.Ring(vg,x,y,r,color,alpha,width)
    nvgBeginPath(vg);nvgCircle(vg,x,y,r);nvgStrokeColor(vg,Color(color,alpha));nvgStrokeWidth(vg,width or 1.5);nvgStroke(vg)
end
function M.Line(vg,x1,y1,x2,y2,color,alpha,width)
    nvgBeginPath(vg);nvgMoveTo(vg,x1,y1);nvgLineTo(vg,x2,y2)
    nvgStrokeColor(vg,Color(color,alpha));nvgStrokeWidth(vg,width or 1);nvgStroke(vg)
end
--- Text with middle baseline. align is an NVG horizontal flag (default left).
function M.Text(vg,text,x,y,size,color,align,alpha)
    if not text or text=='' then return end
    local font=Font(vg)
    if font<0 then
        Draw.Text(vg,text,x,y,SIZE_FALLBACK(size),color or M.colors.text,align,alpha)
        return
    end
    nvgFontFaceId(vg,font);nvgFontSize(vg,size);nvgFontBlur(vg,0);nvgTextLetterSpacing(vg,0)
    nvgTextAlign(vg,(align or NVG_ALIGN_LEFT)+NVG_ALIGN_MIDDLE)
    nvgFillColor(vg,Color(color or M.colors.text,alpha))
    nvgText(vg,x,y,text)
end
--- Cheap width estimate for layout time (no vg): CJK = 1em, everything else .56em.
function M.EstimateWidth(text,size)
    local width=0
    for _,cp in utf8.codes(text or '') do width=width+(cp>=0x2E80 and size or size*.56) end
    return width
end
--- Wrap by estimated width; returns lines.
function M.Wrap(text,size,maxWidth)
    local lines,line,width={},{},0
    for _,cp in utf8.codes(text or '') do
        local cw=cp>=0x2E80 and size or size*.56
        if width+cw>maxWidth and #line>0 then lines[#lines+1]=utf8.char(table.unpack(line));line,width={},0 end
        line[#line+1]=cp;width=width+cw
    end
    if #line>0 then lines[#lines+1]=utf8.char(table.unpack(line)) end
    return lines
end
function M.Fit(text,size,maxWidth)
    if M.EstimateWidth(text,size)<=maxWidth then return text end
    local out,width={},M.EstimateWidth('…',size)
    for _,cp in utf8.codes(text) do
        local cw=cp>=0x2E80 and size or size*.56
        if width+cw>maxWidth then break end
        out[#out+1]=cp;width=width+cw
    end
    return utf8.char(table.unpack(out))..'…'
end
return M
