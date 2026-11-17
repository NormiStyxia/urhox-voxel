-- Pure Lua contract checks. Does not run the engine or assert rendered pixels.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local width,height,dpr,scale=1280,720,1,1
local safe={left=0,right=0,top=0,bottom=0}
local mouse={x=640,y=360}
local relative={x=0,y=0} -- IntVector2 fields from Input:GetMouseMove(), not Vector3
local frame,platform,locked=0,'Mac',true
GetTime=function()return {GetFrameNumber=function()return frame end}end
GetPlatform=function()return platform end
local keys,buttons,presses={},{},{}
KEY_Q,KEY_ESCAPE='Q','ESCAPE'
MOUSEB_LEFT,MOUSEB_MIDDLE,MOUSEB_RIGHT=0,1,2
MM_RELATIVE,MM_ABSOLUTE=1,2
NVG_CW,NVG_CCW=2,1
local cleared,fonts,draws=0,0,0
input={numTouches=0,focus=true,mouseMode=MM_RELATIVE,
    GetKeyDown=function(_,key) return keys[key]==true end,
    GetMouseButtonDown=function(_,key) return buttons[key]==true end,
    GetKeyPress=function(_,key) local v=presses[key];presses[key]=nil;return v end,
    GetMouseButtonPress=function(_,key) local v=presses[key];presses[key]=nil;return v end,
    GetMousePosition=function() return mouse end,GetMouseMove=function()return relative end,
    IsMouseLocked=function()return locked end}
graphics={GetWidth=function() return width*dpr end,GetHeight=function() return height*dpr end,GetDPR=function() return dpr end}
local Widget={};Widget.__index=Widget
function Widget:AddChild(child) self.children[#self.children+1]=child;child.parent=self end
function Widget:RemoveChild(child)
    for i,c in ipairs(self.children) do if c==child then table.remove(self.children,i);child.parent=nil;return end end
    error('missing widget')
end
function Widget:Destroy()
    assert(not self.destroyed,'double destroy');self.destroyed=true
    for _,child in ipairs(self.children) do child:Destroy() end
end
function Widget:SetStyle(props) for key,value in pairs(props) do self.props[key]=value end end
function Widget:SetText(text) self.props.text=text end
local function New(props,class) return setmetatable({props=props or {},children={}},class or Widget) end
local Panel={}
function Panel:Extend()
    local class=setmetatable({}, {__index=Widget});class.__index=class
    return setmetatable(class,{__index=Widget,__call=function(_,props) return New(props,class) end})
end
local root=New({})
local overlay
local UI={Panel=Panel,Label=function(props) return New(props) end,GetRoot=function() return root end,
    GetScale=function() return scale end,GetSafeAreaInsets=function() return safe end,
    GetTopOverlay=function() return overlay end,
    PushOverlay=function(widget) assert(not overlay);overlay=widget end,
    PopOverlay=function(widget) if overlay==widget then overlay=nil end end}
local vg={}
package.loaded['urhox-libs/UI']=UI
package.loaded['urhox-libs/UI/Core/ImageCache']={GetContext=function() return vg end}
package.loaded['ui.TouchInput']={Clear=function() cleared=cleared+1 end}
package.loaded['ui.Glass']={Color=function(color,alpha) return {color,alpha} end}
for _,name in ipairs({'Line','Cross','Circle'}) do package.loaded['ui.Glass'][name]=function() draws=draws+1 end end
-- medallion/icon art: pretend the PNGs load so the art path (not the vector fallback) is exercised
package.loaded['ui.Glass'].Picture=function() draws=draws+1;return true end
local arcs,quads,pathPoints={},{},{}
for _,name in ipairs({'Save','Restore','Scale','Translate','ShapeAntiAlias','GlobalAlpha','BeginPath',
    'FillColor','Fill','StrokeColor','StrokeWidth','Stroke','ClosePath','BezierTo','Rotate'}) do
    rawset(_G,'nvg'..name,function() draws=draws+1 end)
end
nvgArc=function(_,x,y,r,a,b,dir) arcs[#arcs+1]={x=x,y=y,r=r,a=a,b=b,dir=dir} end
nvgMoveTo=function(_,x,y) pathPoints[#pathPoints+1]={x=x,y=y} end
nvgLineTo=nvgMoveTo
nvgQuadTo=function(_,x,y,tx,ty) quads[#quads+1]={x=x,y=y,tx=tx,ty=ty} end
nvgCreateFont=function(_,name,path)
    assert(name=='weapon-wheel-sans' and path=='Fonts/MiSans-Regular.ttf');fonts=fonts+1;return fonts
end
local PointerEvent=require('urhox-libs/UI/Core/PointerEvent')
local Wheel=require('ui.WeaponWheel')
local function Eq(a,b,msg) assert(a==b,(msg or 'equality')..': '..tostring(a)..' ~= '..tostring(b)) end
local function Flush()
    for _=1,6 do Wheel.Update(.1) end
end
local function Reset()
    Wheel.ForceClose('test-reset');overlay=nil
    keys,buttons,presses={},{},{}
    width,height,dpr,scale=1280,720,1,1
    safe={left=0,right=0,top=0,bottom=0}
    input.numTouches,input.focus,input.mouseMode=0,true,MM_RELATIVE
    mouse.x,mouse.y=640,360
    relative.x,relative.y=0,0;frame=frame+1;platform,locked='Mac',true
end
local function Event(x,y,id,button,touch)
    return PointerEvent.new('PointerDown',{x=x*dpr/scale,y=y*dpr/scale,
        pointerId=id or 0,button=button or MOUSEB_LEFT,pointerType=touch and 'touch' or 'mouse'})
end
local function SlotEvent(index,id,touch)
    local slot=Wheel.DebugLayout().slots[index]
    return Event(slot.x,slot.y,id,MOUSEB_LEFT,touch)
end
local selected,closed={},{}
local function Options(touch)
    return {weapon='sword',anchorX=.5,anchorY=.5,touch=touch,
        onSelect=function(id) selected[#selected+1]=id;return true end,
        onClose=function(reason) closed[#closed+1]=reason end}
end

-- Move the visible cursor to a screen point with physical mouse deltas.
local function PointAt(x,y)
 local l=Wheel.DebugLayout();local c=Wheel.DebugState()
 relative.x=(x-l.cx-c.virtualX)*dpr/(.65*l.size)
 relative.y=(y-l.cy-c.virtualY)*dpr/(.65*l.size)
 frame=frame+1
end

-- Hollow ring geometry and reusable count-driven selection.
for _,screen in ipairs({{1280,720},{320,430},{844,390},{390,844}}) do
    for _,anchor in ipairs({{0,0},{.5,.5},{1,1}}) do
        local l=Wheel.Layout(screen[1],screen[2],anchor[1],anchor[2],false,4)
        Eq(#l.slots,4);Eq(Wheel.HitTest(l,l.cx,l.cy,true),nil,'hollow center')
        for i,slot in ipairs(l.slots) do
            Eq(Wheel.HitTest(l,slot.x,slot.y,true),i)
            assert(slot.x>0 and slot.x<screen[1] and slot.y>0 and slot.y<screen[2],'slot on screen')
        end
        Eq(Wheel.HitTest(l,l.cx-l.outer,l.cy,true),nil,'outside arc')
        Eq(Wheel.HitTest(l,l.cx+l.outer*2,l.cy,true),nil,'beyond band')
        assert(Wheel.HitTest(l,l.cx+l.outer*2,l.cy,false),'directional selection')
    end
end

-- Preserve root and pre-existing HUD children; reject unrelated overlays.
Reset()
local hud=New({id='existing-hud'});root:AddChild(hud)
overlay=New({});assert(not Wheel.Open(Options()));overlay=nil
assert(Wheel.Open(Options()));Eq(#root.children,2);Eq(root.children[1],hud)
assert(not Wheel.Open(Options()));Eq(input.mouseMode,MM_RELATIVE,'PC opening preserves relative mode')
local unfoldOuter=Wheel.DebugLayout().outer
Wheel.Update(.06)
assert(Wheel.DebugLayout().outer>unfoldOuter,'outward unfold advances')
Wheel.Update(.06)
Eq(Wheel.DebugLayout().outer,164,'outward unfold settles in .12s')
local layer=overlay
assert(Wheel.Confirm());Eq(selected[#selected],'sword')
assert(Wheel.IsOpen() and Wheel.IsBlocked(),'fade remains visible')
keys.Q=true;Wheel.Update(.1)
assert(not Wheel.IsOpen() and Wheel.IsBlocked(),'guard is invisible')
Eq(#root.children,1);assert(layer.destroyed);Eq(input.mouseMode,MM_RELATIVE)
Flush();assert(Wheel.IsBlocked(),'held Q must not leak')
keys.Q=nil;Flush();assert(not Wheel.IsBlocked());Eq(closed[#closed],'selected')

-- Genuine PointerEvent semantics and physical/base coordinate conversion.
for _,metrics in ipairs({{1,1},{3,1.875},{2,2}}) do
    Reset();width,height=390,844;dpr,scale=metrics[1],metrics[2]
    assert(Wheel.Open(Options(true)));Wheel.Update(.2)
    local names=overlay.children
    Eq(names[1].props.fontFamily,'weapon-wheel-sans')
    local e=SlotEvent(2,7,true)
    overlay.props.onPointerDown(e)
    assert(e:IsPropagationStopped() and e:IsDefaultPrevented())
    local savedOverlay=overlay
    savedOverlay.props.onPointerUp(e)
    Eq(selected[#selected],'bow');assert(Wheel.DebugState().closing)
    Flush();assert(not Wheel.IsBlocked())
end
Eq(fonts,1,'one font allocation per UI context')

-- Opening finger release has no matching down, so cannot confirm or cancel.
Reset();assert(Wheel.Open(Options(true)))
layer=overlay;local before=#selected
layer.props.onPointerUp(SlotEvent(2,9,true));Eq(#selected,before);assert(Wheel.IsOpen())
local e=Event(2,2,9,MOUSEB_LEFT,true)
layer.props.onPointerDown(e);layer.props.onPointerUp(e)
Flush();Eq(closed[#closed],'cancelled')

-- Drag to a different item is not an accidental tap; second finger cannot steal.
Reset();assert(Wheel.Open(Options(true)));layer=overlay
layer.props.onPointerDown(SlotEvent(1,4,true))
layer.props.onPointerDown(SlotEvent(2,5,true))
layer.props.onPointerUp(SlotEvent(2,5,true));assert(not Wheel.DebugState().closing)
layer.props.onPointerUp(SlotEvent(2,4,true));assert(not Wheel.DebugState().closing)

-- A rejected equip keeps the UI and callbacks alive for an explicit retry.
Reset();local accept=false;local calls=0
local opts=Options();opts.onSelect=function() calls=calls+1;return accept end
assert(Wheel.Open(opts));assert(not Wheel.Confirm());Eq(calls,1);assert(not Wheel.DebugState().closing)
accept=true;assert(Wheel.Confirm());assert(not Wheel.Confirm());Eq(calls,2);Flush()

-- PC movement selects direction; Escape and secondary click only cancel.
Reset();assert(Wheel.Open(Options()));local l=Wheel.DebugLayout();local slot=l.slots[2]
PointAt(slot.x,slot.y);Wheel.Update(.02)
Eq(Wheel.DebugState().selected,'bow');assert(Wheel.Confirm());Flush()
Eq(input.mouseMode,MM_RELATIVE,'PC retirement preserves relative mode')
-- Dead zone, DPR, frame sampling, final release delta, and anchor motion.
for _,density in ipairs({1,2,3})do
 Reset();dpr=density;assert(Wheel.Open(Options()))
 relative.x,relative.y=3*dpr,0;Wheel.Update(.02);Eq(Wheel.DebugState().selected,'sword','deadzone retains current')
 l=Wheel.DebugLayout();slot=l.slots[2]
 PointAt(slot.x,slot.y)
 -- Q-up may Confirm before late-frame Update, so consume its final delta here.
 assert(Wheel.Confirm());Eq(selected[#selected],'bow');Flush();Eq(input.mouseMode,MM_RELATIVE)
 Reset();assert(Wheel.Open(Options()));l=Wheel.DebugLayout();slot=l.slots[2]
 PointAt(slot.x,slot.y);Wheel.Update(.02)
 local once=Wheel.DebugState().virtualX;Wheel.Update(.02,{anchorX=.8,anchorY=.3})
 Eq(Wheel.DebugState().virtualX,once,'frame delta accumulated once, anchor is independent')
 layer=overlay;layer.props.onPointerMove(SlotEvent(1));Eq(Wheel.DebugState().selected,'bow','absolute pointer events ignored')
 layer.props.onPointerDown(SlotEvent(1));layer.props.onPointerUp(SlotEvent(1));assert(not Wheel.DebugState().closing,'left click cannot confirm PC selection')
end
Reset();assert(Wheel.Open(Options()));PointAt(Wheel.DebugLayout().cx-120,Wheel.DebugLayout().cy);Wheel.Update(.02)
assert(not Wheel.Confirm(),'outside arc cancels, no forced closest sector');Flush()
-- Web loss is reported once and never requests pointer lock or changes mode.
Reset();platform='Web';assert(Wheel.Open(Options()));locked=false;input.mouseMode=0
local oldPrint=print;local losses=0
print=function(line)if tostring(line):find('pointer lock lost',1,true)then losses=losses+1 else oldPrint(line)end end
Wheel.Update(.02);Wheel.Update(.02);assert(not Wheel.Confirm());Flush()
print=oldPrint;Eq(losses,1);Eq(closed[#closed],'pointer-unlocked');Eq(input.mouseMode,0,'no relock after browser Escape')
Reset();assert(Wheel.Open(Options()));presses.ESCAPE=true;Wheel.Update(.02)
assert(Wheel.DebugState().closing);Flush();Eq(closed[#closed],'cancelled')
Reset();assert(Wheel.Open(Options()));before=#selected;layer=overlay
layer.props.onPointerDown(Event(0,0,0,MOUSEB_MIDDLE));assert(not Wheel.DebugState().closing)
layer.props.onPointerDown(Event(0,0,0,MOUSEB_RIGHT));Flush()
Eq(#selected,before);Eq(closed[#closed],'cancelled')

-- Window loss, root replacement, stale callbacks, and teardown during onSelect.
Reset();assert(Wheel.Open(Options()));input.focus=false;Wheel.Update(.02);Flush()
Eq(closed[#closed],'focus-lost')
Reset();assert(Wheel.Open(Options()));local oldRoot=root;layer=overlay;root=New({})
Wheel.Update(.01);assert(not Wheel.IsBlocked());assert(layer.destroyed);Eq(#oldRoot.children,1)
Eq(closed[#closed],'root-changed')
assert(Wheel.Open(Options()));before=#selected
layer.props.onPointerUp(SlotEvent(1));Eq(#selected,before,'retired event cannot select new session')
Wheel.ForceClose();assert(not Wheel.IsBlocked())
opts=Options();opts.onSelect=function() Wheel.ForceClose('scene-stop');return true end
assert(Wheel.Open(opts));assert(Wheel.Confirm());assert(not Wheel.IsOpen());Eq(closed[#closed],'scene-stop')

-- Actual draw code keeps the fine inner/outer arcs; the old filled rounded band is gone (art medallions instead).
local layout=Wheel.Layout(1280,720,.5,.5,false,2)
Wheel.Draw(vg,layout,1)
assert(draws>50 and #arcs>=6 and #quads>=4,'real geometry path recorded')
local inner,outer=false,false
for _,arc in ipairs(arcs) do
    inner=inner or arc.r==layout.inner;outer=outer or arc.r==layout.outer
    assert(math.abs(arc.b-arc.a)<math.pi,'no full circle disc')
end
assert(inner and outer,'concentric hollow boundaries')
assert(cleared>=12,'mode transitions clear touch actions')
print('weapon_wheel: geometry, DPI, pointer, selection, guard, teardown, drawing PASS')

-- Three-item visible cursor: no hidden-origin jump, opening delta ignored,
-- small movement stays selected, boundary noise cannot oscillate selection.
Reset();local opts3=Options();opts3.items={{id='sword'},{id='bow'},{id='time'}}
relative.x,relative.y=900,900
assert(Wheel.Open(opts3));Wheel.Update(.02)
Eq(Wheel.DebugState().selected,'sword','opening camera delta ignored')
l=Wheel.DebugLayout();local initial=Wheel.DebugState()
assert(initial.virtualX~=0 and initial.virtualY~=0,'cursor begins at selected medallion')
relative.x,relative.y=12,0;frame=frame+1;Wheel.Update(.02)
Eq(Wheel.DebugState().selected,'sword','small hand motion stays on current item')
for _,angleOffset in ipairs({1,3,-1,2}) do
 local angle=l.slots[1].to+math.rad(angleOffset);local r=(l.inner+l.outer)/2
 PointAt(l.cx+math.cos(angle)*r,l.cy+math.sin(angle)*r);Wheel.Update(.02)
 Eq(Wheel.DebugState().selected,'sword','shared-edge hysteresis')
end
PointAt(l.slots[2].x,l.slots[2].y);Wheel.Update(.02)
Eq(Wheel.DebugState().selected,'bow')
PointAt(l.slots[3].x,l.slots[3].y);assert(Wheel.Confirm());Eq(selected[#selected],'time');Flush()
-- Exercise the actual cursor render path, not just selection geometry.
Reset();assert(Wheel.Open(opts3));local n=#pathPoints;overlay:Render(vg)
local st=Wheel.DebugState();l=Wheel.DebugLayout()
Eq(pathPoints[#pathPoints-3].x,l.cx+st.virtualX,'cursor tip matches hit-test position')
assert(#pathPoints>n)
print('PASS visible PC cursor, 3-slot targeting, reduced gain, boundary hysteresis, opening-frame delta')
