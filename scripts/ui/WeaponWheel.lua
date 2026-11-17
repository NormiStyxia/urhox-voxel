-- Hand-anchored weapon selector. UI owns layout, dispatch and the NanoVG frame.
-- Public functions use dot calls. Anchors are normalized physical-screen points.
local UI = require('urhox-libs/UI')
local Glass = require('ui.Glass')
local TouchInput = require('ui.TouchInput')
local ImageCache = require('urhox-libs/UI/Core/ImageCache')
local M = {}
local DEFAULT_ITEMS = {
    {id='sword', name='长剑', tag='01 / BLADE'},
    {id='bow', name='长弓', tag='02 / RANGED'},
}
local INK, IVORY, MUTED, AMBER = {12,24,40}, {240,235,220}, {151,169,183}, {229,180,96}
local session
local releaseGuard = false
local guardFrames = 0
local fonts = setmetatable({}, {__mode='k'})
local START, SPAN = math.rad(-96), math.rad(122)
local function Clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function Consume(event)
    if event then event:StopPropagation(); event:PreventDefault() end
end
local function Released()
    return input.numTouches == 0 and not input:GetMouseButtonDown(MOUSEB_LEFT)
        and not input:GetMouseButtonDown(MOUSEB_RIGHT) and not input:GetKeyDown(KEY_Q)
end
local function EnsureFont()
    local vg=ImageCache.GetContext()
    if vg and not fonts[vg] then
        local id=nvgCreateFont(vg,'weapon-wheel-sans','Fonts/MiSans-Regular.ttf')
        if id and id>=0 then fonts[vg]=true end
    end
end

-- Pure geometry in CSS pixels; no graphics/input dependencies. Safe area is CSS.
-- Exposed for offline construction previews and future item counts.
function M.Layout(width,height,anchorX,anchorY,touch,count,safe)
    safe=safe or {left=0,right=0,top=0,bottom=0}
    local left,right=(safe.left or 0)+12,width-(safe.right or 0)-12
    local top,bottom=(safe.top or 0)+12,height-(safe.bottom or 0)-12
    local size=math.min(1,(right-left)/260,(bottom-top)/330)
    size=math.max(.2,size)
    local inner,outer=88*size,164*size
    local ax,ay=Clamp(anchorX or .52,0,1)*width,Clamp(anchorY or .5,0,1)*height
    -- Move the assembly only when necessary; a leader retains the true hand origin.
    local cx=Clamp(ax,left+34*size,right-outer-19*size)
    local cy=Clamp(ay,top+outer+25*size,bottom-outer*.55-41*size)
    local layout={width=width,height=height,ax=ax,ay=ay,cx=cx,cy=cy,
        inner=inner,outer=outer,size=size,start=START,span=SPAN,slots={}}
    count=count or #DEFAULT_ITEMS
    for i=1,count do
        local a=START+SPAN*(i-.5)/count
        local r=(inner+outer)*.5
        layout.slots[i]={angle=a,x=cx+math.cos(a)*r,y=cy+math.sin(a)*r,
            from=START+SPAN*(i-1)/count,to=START+SPAN*i/count}
    end
    return layout
end

-- strict=true: actual hollow band only; false: directional PC selection beyond it.
function M.HitTest(layout,x,y,strict)
    local dx,dy=x-layout.cx,y-layout.cy
    local radius=math.sqrt(dx*dx+dy*dy)
    if radius<layout.inner-(strict and 0 or 30*layout.size) then return nil end
    if strict and radius>layout.outer then return nil end
    local a=math.atan(dy,dx)
    if a<layout.start or a>layout.start+layout.span then return nil end
    local index=math.min(#layout.slots,math.floor((a-layout.start)/layout.span*#layout.slots)+1)
    return index>0 and index or nil
end
local function Metrics(s)
    local scale=UI.GetScale()
    local dpr=graphics:GetDPR()
    s.factor=dpr/scale -- CSS -> UI base pixels (UI applies base -> physical once).
    local safe=UI.GetSafeAreaInsets()
    s.layout=M.Layout(graphics:GetWidth()/dpr,graphics:GetHeight()/dpr,s.anchorX,s.anchorY,s.touch,#s.items,
        {left=safe.left/s.factor,right=safe.right/s.factor,top=safe.top/s.factor,bottom=safe.bottom/s.factor})
    -- A restrained outward unfold. Draw, labels and hit testing share these
    -- animated radii; the true hand registration point never drifts.
    local l=s.layout
    local t=Clamp(s.age/.12,0,1)
    local inset=6*l.size*(1-t)^3
    l.inner,l.outer=l.inner-inset,l.outer-inset
    local radius=(l.inner+l.outer)*.5
    for _,slot in ipairs(l.slots) do
        slot.x,slot.y=l.cx+math.cos(slot.angle)*radius,l.cy+math.sin(slot.angle)*radius
    end
end
local function Stroke(vg,color,alpha,width)
    nvgStrokeColor(vg,Glass.Color(color,alpha));nvgStrokeWidth(vg,width or 1);nvgStroke(vg)
end
local function Arc(vg,l,r,a,b,color,alpha,width)
    nvgBeginPath(vg);nvgArc(vg,l.cx,l.cy,r,a,b,NVG_CW);Stroke(vg,color,alpha,width)
end
-- Four rounded corners, two concentric arcs, and no vertex at the hand origin.
local function Band(vg,l,inner,outer,a,b,corner,color,alpha)
    local c=math.min(corner,(outer-inner)*.25,(b-a)*inner*.2)
    local function X(r,t) return l.cx+math.cos(t)*r end
    local function Y(r,t) return l.cy+math.sin(t)*r end
    nvgBeginPath(vg)
    nvgMoveTo(vg,X(inner+c,a),Y(inner+c,a))
    nvgLineTo(vg,X(outer-c,a),Y(outer-c,a))
    nvgQuadTo(vg,X(outer,a),Y(outer,a),X(outer,a+c/outer),Y(outer,a+c/outer))
    nvgArc(vg,l.cx,l.cy,outer,a+c/outer,b-c/outer,NVG_CW)
    nvgQuadTo(vg,X(outer,b),Y(outer,b),X(outer-c,b),Y(outer-c,b))
    nvgLineTo(vg,X(inner+c,b),Y(inner+c,b))
    nvgQuadTo(vg,X(inner,b),Y(inner,b),X(inner,b-c/inner),Y(inner,b-c/inner))
    nvgArc(vg,l.cx,l.cy,inner,b-c/inner,a+c/inner,NVG_CCW)
    nvgQuadTo(vg,X(inner,a),Y(inner,a),X(inner+c,a),Y(inner+c,a))
    nvgClosePath(vg);nvgFillColor(vg,Glass.Color(color,alpha));nvgFill(vg)
end
local function Glyph(vg,id,x,y,size,color)
    nvgSave(vg);nvgTranslate(vg,x,y);nvgScale(vg,size,size)
    nvgBeginPath(vg)
    if id=='sword' then
        nvgMoveTo(vg,-3,13);nvgLineTo(vg,-3,-15);nvgLineTo(vg,0,-23);nvgLineTo(vg,3,-15);nvgLineTo(vg,3,13)
        nvgMoveTo(vg,0,-17);nvgLineTo(vg,0,12)
        nvgMoveTo(vg,-10,12);nvgLineTo(vg,10,12)
        nvgMoveTo(vg,0,13);nvgLineTo(vg,0,23)
        nvgMoveTo(vg,-3,24);nvgLineTo(vg,3,24)
    elseif id=='bow' then
        nvgMoveTo(vg,-5,-23);nvgBezierTo(vg,22,-15,22,15,-5,23)
        nvgLineTo(vg,1,0);nvgLineTo(vg,-5,-23)
        nvgMoveTo(vg,-16,0);nvgLineTo(vg,23,0)
        nvgMoveTo(vg,18,-4);nvgLineTo(vg,23,0);nvgLineTo(vg,18,4)
    else
        nvgMoveTo(vg,0,-16);nvgLineTo(vg,13,0);nvgLineTo(vg,0,16);nvgLineTo(vg,-13,0);nvgClosePath(vg)
    end
    Stroke(vg,color,.98,1.65)
    nvgRestore(vg)
end

-- Rendering entry for NanoVG recording; geometry is CSS pixels, no BeginFrame.
function M.Draw(vg,layout,selected,items,alpha)
    local l,k=layout,layout.size
    items=items or DEFAULT_ITEMS
    nvgSave(vg);nvgShapeAntiAlias(vg,1);nvgGlobalAlpha(vg,alpha or 1)
    -- No filled plastic band: two fine arcs, a tick scale, and one ruins medallion per weapon.
    Arc(vg,l,l.inner,START+.035,START+SPAN-.035,IVORY,.5,.8)
    Arc(vg,l,l.outer,START+.02,START+SPAN-.02,IVORY,.5,.8)
    Arc(vg,l,l.outer+9*k,START-.02,START+SPAN+.02,IVORY,.22,.7)
    for i=0,24 do
        local a=START+SPAN*i/24
        local r=l.outer+9*k
        local length=(i%6==0 and 7 or 3)*k
        Glass.Line(vg,l.cx+math.cos(a)*r,l.cy+math.sin(a)*r,
            l.cx+math.cos(a)*(r+length),l.cy+math.sin(a)*(r+length),IVORY,i%6==0 and .55 or .24,.8)
    end
    for i,slot in ipairs(l.slots) do
        local sel=selected==i
        local d=(sel and 70 or 64)*k
        if i>1 then
            local a=slot.from
            Glass.Line(vg,l.cx+math.cos(a)*(l.inner+13*k),l.cy+math.sin(a)*(l.inner+13*k),
                l.cx+math.cos(a)*(l.outer-13*k),l.cy+math.sin(a)*(l.outer-13*k),IVORY,.18,.8)
        end
        -- soft backing so the medallion reads on any scene colour
        Glass.Circle(vg,slot.x,slot.y,d*.5+2*k,INK,sel and .0 or .28)
        local drawn=Glass.Picture(vg,'ui/forge/medal_idle.png',slot.x-d/2,slot.y-d/2,d,d,sel and .5 or .95)
        if drawn and sel then
            local w=d*1.16
            Glass.Picture(vg,'ui/forge/medal_active.png',slot.x-w/2,slot.y-w*.53,w,w*1.064,1)
        end
        local iconPath=items[i].id=='sword' and 'ui/forge/icon_sword.png' or (items[i].id=='bow' and 'ui/forge/icon_bow.png' or nil)
        local iconDrawn=false
        if drawn and iconPath then
            nvgSave(vg);nvgTranslate(vg,slot.x,slot.y);nvgRotate(vg,math.pi/4)
            local ih=(sel and 46 or 42)*k
            local iw=ih*(items[i].id=='sword' and .328 or .258)
            iconDrawn=Glass.Picture(vg,iconPath,-iw/2,-ih/2,iw,ih,sel and 1 or .9)
            nvgRestore(vg)
        end
        if not iconDrawn then Glyph(vg,items[i].id,slot.x,slot.y-2*k,k,sel and AMBER or IVORY) end
        if sel then
            Band(vg,l,l.outer-6*k,l.outer-3*k,slot.angle-.14,slot.angle+.14,1*k,AMBER,.95)
            Band(vg,l,l.inner+3*k,l.inner+6*k,slot.angle-.14,slot.angle+.14,1*k,AMBER,.95)
        end
        local px,py=l.cx+math.cos(slot.angle)*(l.inner-9*k),l.cy+math.sin(slot.angle)*(l.inner-9*k)
        Glass.Circle(vg,px,py,1.8*k,sel and AMBER or IVORY,.9)
        Glass.Line(vg,px,py,l.cx+math.cos(slot.angle)*(l.inner+5*k),l.cy+math.sin(slot.angle)*(l.inner+5*k),IVORY,.3,.8)
    end
    -- Hand registration mark + short broken leader, never a central filled disc.
    Glass.Cross(vg,l.ax,l.ay,4*k,IVORY,.62,.8)
    local tx,ty=l.cx+math.cos(-.6)*(l.inner-17*k),l.cy+math.sin(-.6)*(l.inner-17*k)
    Glass.Line(vg,l.ax+8*k,l.ay,tx-12*k,l.ay,IVORY,.25,.8)
    Glass.Line(vg,tx-12*k,l.ay,tx,ty,IVORY,.25,.8)
    Glass.Circle(vg,tx,ty,2*k,AMBER,.7)
    nvgRestore(vg)
end
local function PlaceLabel(label,x,y,w,h,size,factor,color,alpha)
    label:SetStyle({left=x*factor,top=y*factor,width=w*factor,height=h*factor,
        fontSize=size*factor,fontColor=color,opacity=alpha})
end
local function Labels(s)
    local l,k=s.layout,s.layout.size
    local alpha=s.closing and math.max(0,1-s.closeTime/.1) or math.min(1,s.age/.12)
    for i,slot in ipairs(l.slots) do
        PlaceLabel(s.names[i],slot.x-34*k,slot.y+38*k,68*k,20*k,14*k,s.factor,
            s.selected==i and AMBER or IVORY,alpha)
    end
    local choice=s.items[s.selected or 0]
    s.caption:SetText(choice and choice.tag or 'ARMAMENT / SELECT')
    PlaceLabel(s.caption,l.cx-22*k,l.cy+l.outer*.53,204*k,18*k,10*k,s.factor,MUTED,alpha)
    PlaceLabel(s.hint,l.cx-22*k,l.cy+l.outer*.53+19*k,196*k,24*k,12*k,s.factor,IVORY,alpha)
end
local Layer=UI.Panel:Extend('WeaponWheelLayer')
function Layer:Render(vg)
    local s=session
    if not s or s.layer~=self then return end
    nvgSave(vg);nvgScale(vg,s.factor,s.factor)
    M.Draw(vg,s.layout,s.selected,s.items,s.closing and math.max(0,1-s.closeTime/.1) or math.min(1,s.age/.12))
    if not s.touch and not s.closing then
        -- Visible virtual cursor retains browser pointer lock; no re-capture click.
        local x,y=s.layout.cx+s.virtualX,s.layout.cy+s.virtualY
        local k=s.layout.size
        nvgBeginPath(vg);nvgMoveTo(vg,x,y)
        nvgLineTo(vg,x+4*k,y+19*k);nvgLineTo(vg,x+8*k,y+13*k)
        nvgLineTo(vg,x+15*k,y+11*k);nvgClosePath(vg)
        nvgFillColor(vg,Glass.Color(IVORY,1));nvgFill(vg);Stroke(vg,INK,1,2*k)
    end
    nvgRestore(vg)
end
local function Pick(s,event,strict)
    return M.HitTest(s.layout,event.x/s.factor,event.y/s.factor,strict)
end
local function Down(event)
    Consume(event)
    local s=session
    if not s or s.closing then return end
    if event:IsMouse() and event:IsSecondaryButton() then M.Cancel();return end
    if not s.touch then return end -- desktop selection is relative direction + Q release
    if not event:IsPrimaryAction() then return end
    if s.pointer~=nil and s.pointer~=event.pointerId then return end
    s.pointer=event.pointerId
    s.down=Pick(s,event,true) or false
    if s.down then s.selected=s.down end
end
local function Move(event)
    Consume(event)
    local s=session
    if not s or s.closing then return end
    if s.touch then
        if s.pointer==event.pointerId then s.selected=Pick(s,event,true) end
    end -- absolute UI pointer coordinates must not override desktop gestures
end
local function Up(event)
    Consume(event)
    if not event:IsPrimaryAction() then return end
    local s=session
    if not s or s.closing or not s.touch or s.pointer~=event.pointerId then return end
    local choice=Pick(s,event,true)
    local down=s.down
    s.pointer,s.down=nil,nil
    if choice and choice==down then s.selected=choice;M.Confirm()
    elseif not choice and not down then M.Cancel() end
end
local function Retire(s)
    if session~=s then return end
    local layer=s.layer
    UI.PopOverlay(layer);s.root:RemoveChild(layer)
    -- UI dispatch may still own this pointer target until the physical release.
    layer.absoluteLayout={x=0,y=0,w=0,h=0}
    layer.props.onPointerDown=Consume;layer.props.onPointerUp=Consume
    layer.props.onPointerMove=Consume;layer.props.onPointerCancel=Consume
    layer:Destroy()
    if s.touch and input.mouseMode==MM_ABSOLUTE then input.mouseMode=s.mouseMode end
    session=nil
    TouchInput.Clear()
    if s.onClose then s.onClose(s.reason or 'closed') end
end
function M.Open(opts)
    if session or releaseGuard then return false end
    opts=opts or {}
    local root=UI.GetRoot()
    if not root or UI.GetTopOverlay() then return false end
    EnsureFont()
    local items={}
    for _,item in ipairs(opts.items or DEFAULT_ITEMS) do
        if type(item.id)=='string' then items[#items+1]={id=item.id,name=item.name or item.id,tag=item.tag or item.id} end
    end
    if #items==0 then return false end
    local s={root=root,items=items,anchorX=opts.anchorX or .52,anchorY=opts.anchorY or .5,
        touch=opts.touch==true,selected=1,names={},age=0,closeTime=0,virtualX=0,virtualY=0,
        onSelect=opts.onSelect,onClose=opts.onClose,mouseMode=input.mouseMode}
    for i,item in ipairs(items) do if item.id==opts.weapon then s.selected=i end end
    s.initialSelected=s.selected
    s.wasLocked=input.mouseMode==MM_RELATIVE
    if GetPlatform()=='Web' then s.wasLocked=input:IsMouseLocked() end
    session=s
    Metrics(s)
    -- Start on the current item, not the invisible origin where tiny movement
    -- produces huge angular changes. Discard the camera delta on the opening frame.
    local slot=s.layout.slots[s.selected]
    s.virtualX,s.virtualY=slot.x-s.layout.cx,slot.y-s.layout.cy
    s.mouseFrame=GetTime():GetFrameNumber()
    s.layer=Layer{position='absolute',left=0,top=0,width='100%',height='100%',pointerEvents='auto',
        onPointerDown=Down,onPointerMove=Move,onPointerUp=Up,
        onPointerCancel=function(event)
            Consume(event)
            if session==s and not s.closing and s.pointer==event.pointerId then M.Cancel() end
        end,
        onClick=function(_,event) Consume(event) end}
    s.layer.focusable=false
    local function Label(text)
        local label=UI.Label{position='absolute',text=text,fontFamily='weapon-wheel-sans',
            textAlign='center',pointerEvents='none'}
        s.layer:AddChild(label);return label
    end
    for i,item in ipairs(items) do s.names[i]=Label(item.name) end
    s.caption=Label('');s.caption:SetStyle({textAlign='left'})
    s.hint=Label(s.touch and '点击选择 · 空白处取消' or '松开 Q 确认 · 右键取消')
    s.hint:SetStyle({textAlign='left'})
    Labels(s)
    root:AddChild(s.layer);UI.PushOverlay(s.layer)
    if s.touch then input.mouseMode=MM_ABSOLUTE end
    TouchInput.Clear()
    return true
end
function M.Close(reason)
    local s=session
    if not s then return false end
    if not s.closing then
        s.closing,s.closeTime,s.reason=true,0,reason or 'closed'
        s.pointer,s.down=nil,nil
        releaseGuard,guardFrames=true,0
        TouchInput.Clear()
    end
    return true
end
function M.ForceClose(reason)
    local s=session
    if s then s.reason=reason or 'forced';Retire(s) end
    releaseGuard,guardFrames=false,0
end
-- GetMouseMove is this frame's relative IntVector2 (physical pixels), not an
-- absolute cursor and not a consuming read. Confirm can run before Update.
local function RelativeSelection(s)
    if s.touch or s.closing then return end
    local frame=GetTime():GetFrameNumber()
    if s.mouseFrame==frame then return end
    s.mouseFrame=frame
    local delta=input:GetMouseMove()
    local dpr=math.max(1,graphics:GetDPR())
    local gain=.65*s.layout.size
    local x,y=s.virtualX+delta.x/dpr*gain,s.virtualY+delta.y/dpr*gain
    local radius=math.sqrt(x*x+y*y)
    local limit=s.layout.outer
    if radius>limit then x,y=x*limit/radius,y*limit/radius;radius=limit end
    s.virtualX,s.virtualY=x,y
    if radius<42*s.layout.size then s.selected=s.initialSelected;return end
    local r=(s.layout.inner+s.layout.outer)*.5
    local nextSelection=M.HitTest(s.layout,s.layout.cx+x/radius*r,s.layout.cy+y/radius*r,false)
    local previous=s.layout.slots[s.selected or 0]
    local angle=math.atan(y,x)
    -- Four degrees of hysteresis at shared boundaries prevent hand jitter.
    -- Moving outside the arc still cancels rather than forcing a choice.
    if nextSelection and previous and angle>=previous.from-math.rad(4)
        and angle<=previous.to+math.rad(4) then return end
    s.selected=nextSelection
end
local function PointerLost(s)
    if s.touch or not s.wasLocked then return false end
    local locked=input.mouseMode==MM_RELATIVE
    if GetPlatform()=='Web' then locked=input:IsMouseLocked() end
    if locked then return false end
    if not s.lockLossLogged then
        print('WeaponWheel: pointer lock lost during Q selection; cancel, no automatic relock')
        s.lockLossLogged=true
    end
    M.Close('pointer-unlocked')
    return true
end
function M.Confirm()
    local s=session
    if not s or s.closing then return false end
    if PointerLost(s) then return false end
    if input:GetKeyPress(KEY_ESCAPE) or input:GetMouseButtonPress(MOUSEB_RIGHT) then M.Cancel();return false end
    RelativeSelection(s)
    local item=s.items[s.selected or 0]
    if not item then M.Cancel();return false end
    if s.onSelect and s.onSelect(item.id)==false then return false end
    -- Selection may itself trigger a scene change / ForceClose.
    if session==s then M.Close('selected') end
    return true
end
function M.Cancel() return M.Close('cancelled') end
function M.IsOpen() return session~=nil end -- Includes visible fade, excludes guard.
function M.IsBlocked() return session~=nil or releaseGuard end
function M.SetAnchor(x,y)
    if session then session.anchorX,session.anchorY=x or session.anchorX,y or session.anchorY end
end
function M.Update(dt,anchor)
    local s=session
    if not s then
        if releaseGuard then
            guardFrames=guardFrames+1
            if guardFrames>=2 and Released() then releaseGuard=false end
        end
        return
    end
    if UI.GetRoot()~=s.root then M.ForceClose('root-changed');return end
    PointerLost(s) -- observe browser Escape loss even during the closing fade
    if input.focus==false then M.Close('focus-lost') end
    local step=math.max(0,math.min(.1,dt or 0))
    if s.closing then
        s.closeTime=s.closeTime+step
        Labels(s)
        if s.closeTime>=.1 then Retire(s) end
        return
    end
    if UI.GetTopOverlay()~=s.layer then M.ForceClose('covered');return end
    s.age=s.age+step
    if anchor then M.SetAnchor(anchor.anchorX,anchor.anchorY) end
    Metrics(s)
    if input:GetKeyPress(KEY_ESCAPE) or input:GetMouseButtonPress(MOUSEB_RIGHT) then M.Cancel();return end
    RelativeSelection(s)
    Labels(s)
end
-- Read-only snapshots; callers must not mutate the returned layout.
function M.DebugLayout() return session and session.layout or nil end
function M.DebugState()
    local s=session
    return {open=s~=nil,closing=s and s.closing==true or false,blocked=M.IsBlocked(),
        selected=s and s.items[s.selected or 0] and s.items[s.selected].id or nil,
        touch=s and s.touch or false,reason=s and s.reason or nil,
        virtualX=s and s.virtualX or 0,virtualY=s and s.virtualY or 0}
end
return M
