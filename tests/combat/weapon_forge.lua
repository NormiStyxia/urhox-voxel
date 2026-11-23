-- Offline pointer, safe-area and transaction coverage for the pixel weapon panel.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Store=require('combat.WeaponStore')
local saved,saveOK=nil,true
Store.Save=function(config) saved=config;return saveOK end
local original=Store.Default()
Store.Load=function() return original end
local held,buttons={},{}
local eventHandlers={}
local cleared=0
local messages={}
local realPrint=print
rawset(_G,'print',function(message) messages[#messages+1]=tostring(message);realPrint(message) end)
local function LogCount(message)
    local count=0
    for _,line in ipairs(messages) do if line:find(message,1,true)==1 then count=count+1 end end
    return count
end
local width,height,dpr,scale=844,390,3,2
local safe={left=47,right=47,top=0,bottom=21}
for _,name in ipairs({'W','A','S','D','SHIFT','SPACE','1','2','3','E','R','Q','F','T','TAB','C','B','G','L','ESCAPE'}) do rawset(_G,'KEY_'..name,name) end
for i,name in ipairs({'MOUSEB_LEFT','MOUSEB_RIGHT','MOUSEB_MIDDLE','MM_ABSOLUTE','MM_RELATIVE'}) do rawset(_G,name,i) end
NVG_ALIGN_LEFT,NVG_ALIGN_CENTER,NVG_ALIGN_RIGHT,NVG_ALIGN_MIDDLE=1,2,4,16
for _,name in ipairs({'nvgArc','nvgRotate','nvgEllipse'}) do rawset(_G,name,function() end) end
local fakeInput={numTouches=0,mouseMode=MM_RELATIVE,GetKeyDown=function(_,key) return held[key] end,GetMouseButtonDown=function(_,button) return buttons[button] end}
rawset(_G,'input',fakeInput)
-- Every NanoVG call is counted; paints/colours are fresh tables like the real binding's userdata.
local nvgCalls,rects,fills=0,0,0
for _,name in ipairs({'nvgSave','nvgRestore','nvgTranslate','nvgScale','nvgIntersectScissor','nvgBeginPath','nvgRoundedRect','nvgFillColor','nvgFillPaint',
    'nvgStrokeColor','nvgStrokeWidth','nvgStroke','nvgCircle','nvgMoveTo','nvgLineTo','nvgClosePath','nvgFontFaceId','nvgFontSize','nvgFontBlur',
    'nvgTextLetterSpacing','nvgTextAlign','nvgText','nvgShapeAntiAlias','nvgGlobalAlpha'}) do rawset(_G,name,function() nvgCalls=nvgCalls+1 end) end
rawset(_G,'nvgRect',function() rects=rects+1 end)
rawset(_G,'nvgFill',function() fills=fills+1 end)
rawset(_G,'nvgRGBA',function() return {} end)
rawset(_G,'nvgLinearGradient',function() return {} end)
rawset(_G,'nvgCreateFont',function() return 1 end)
rawset(_G,'nvgCreateImage',function() return 7 end)
rawset(_G,'nvgImageSize',function() return 100,60 end)
rawset(_G,'nvgImagePattern',function() return {} end)
local function MakeNode()
    local node={}
    node.CreateScriptObject=function()
        local receiver={}
        receiver.SubscribeToEvent=function(_,name,fn) eventHandlers[name]=fn end
        receiver.UnsubscribeFromAllEvents=function() eventHandlers={} end
        return receiver
    end
    node.Remove=function(self) self.removed=true end
    return node
end
rawset(_G,'Node',MakeNode)
local root={children={}}
function root:AddChild(child) self.children[#self.children+1]=child;child.parent=self end
function root:RemoveChild(child)
    for i,value in ipairs(self.children) do if child==value then table.remove(self.children,i);child.parent=nil;return end end
    error('missing child')
end
local overlay
local UI={Panel={}}
function UI.Panel:Extend()
    local class={}
    class.Destroy=function(self) assert(not self.destroyed);self.destroyed=true end
    return setmetatable(class,{__call=function(_,props) return setmetatable({props=props},{__index=class}) end})
end
UI.GetRoot=function() return root end
UI.GetScale=function() return scale end
UI.PushOverlay=function(widget) assert(not overlay);overlay=widget end
UI.PopOverlay=function(widget) assert(overlay==widget);overlay=nil end
local liveContext='vg'
UI.QueueOverlay=function(fn) fn(liveContext) end
local imageCalls=0
local Draw={colors={}}
Draw.Snap=function(n) return math.floor(n/2+.5)*2 end
Draw.PixelToHUD=function() return 1/dpr end
Draw.Metrics=function() return width,height,safe end
Draw.Begin=function() end
Draw.Save=function() end
Draw.Restore=function() end
Draw.Rect=function() end
Draw.ImagePixels=function() return true end
Draw.ScrollPaper=function() end
Draw.Finish=function() end
Draw.Image=function() imageCalls=imageCalls+1 end
Draw.Text=function() end
local selectedClass,engaged,safeToOpen='sword',false,true
package.loaded['urhox-libs/UI']=UI
package.loaded['ui.PixelDraw']=Draw
package.loaded['ui.TouchInput']={Clear=function() cleared=cleared+1 end}
package.loaded['combat.CombatState']={Engaged=function() return engaged end,GetSelection=function() return selectedClass end}
local Forge=require('ui.ForgePanel')
local function State()
    local _,s=debug.getupvalue(Forge.IsOpen,1)
    return s
end
local function Tick(n)
    for _=1,n or 1 do
        if eventHandlers.Update then eventHandlers.Update(nil,nil,{GetFloat=function() return 1/60 end}) end
    end
end
local function Render()
    local s=assert(State())
    s.layer:Render('vg')
    return s
end
local function Grid()
    local unit=1/dpr
    local w,h=width-safe.left-safe.right,height-safe.top-safe.bottom
    local k=math.floor(math.min(w/380,h/214)/unit)*unit
    local x=math.floor((safe.left+(w-380*k)*.5)/unit+.5)*unit
    local y=math.floor((safe.top+(h-214*k)*.5)/unit+.5)*unit
    return x,y,k
end
local function Event(x,y)
    local ox,oy,k=Grid()
    return {x=(ox+x*k)*dpr/scale,y=(oy+y*k)*dpr/scale,pointerId=1,pointerType='touch',
        StopPropagation=function(self) self.stopped=true end,PreventDefault=function(self) self.prevented=true end}
end
local function Has(id)
    for _,button in ipairs(Render().buttons) do if button.id==id then return button end end
end
local function Click(id)
    local b=assert(Has(id),'missing button '..id)
    local props=State().layer.props
    local e=Event(b.x+b.w*.5,b.y+b.h*.5)
    props.onPointerDown(e);assert(e.stopped and e.prevented)
    props.onPointerUp(e)
end
local function Open(rig)
    assert(Forge.Open({rig=rig,canOpen=function() return safeToOpen end}))
    Tick(40)
    assert(Forge.PreviewMode()=='3d' and Forge.HudHidden())
    return Render()
end
local function CheckLayout()
    local x,y,k=Grid()
    local inset=1/dpr
    assert(x>=safe.left-inset and x+380*k<=width-safe.right+inset)
    assert(y>=safe.top-inset and y+214*k<=height-safe.bottom+inset)
    local byId={}
    for _,b in ipairs(Render().buttons) do
        assert(not byId[b.id] and b.x>=0 and b.y>=0 and b.x+b.w<=380 and b.y+b.h<=214,b.id)
        byId[b.id]=true
    end
end
local function Finish()
    Forge.ForceClose()
    assert(not Forge.IsOpen() and not Forge.HudHidden() and #root.children==0 and not overlay and not next(eventHandlers))
    assert(input.mouseMode==MM_RELATIVE)
end

local rig={config=Store.Default()}
assert(not Forge.Open())
assert(not Forge.Open({rig=rig,canOpen=function() return false end}))
engaged=true
assert(not Forge.Open({rig=rig,canOpen=function() return true end}))
engaged=false
local s=Open(rig)
assert(not Has('tab_bow') and not Has('color_primary') and s.tab=='detail')
CheckLayout()
local props=s.layer.props
local before=s.preview.yaw
props.onPointerDown(Event(105,80));props.onPointerMove(Event(132,90));props.onPointerUp(Event(132,90))
assert(s.preview.yaw~=before and s.tab=='detail')
Click('orbit_2');Tick(70);Render()
assert(s.focusIndex==2 and s.tab=='imprint' and s.preview.centers[2].x==114)
Click('role_1');Click('enhance');Click('show_drawer')
Click('forge')
eventHandlers.MouseWheel(nil,nil,{GetInt=function() return -1 end})
assert(s.scroll==0,'a hidden material list must not scroll')
eventHandlers.KeyDown(nil,nil,{GetInt=function() return KEY_ESCAPE end})
assert(s.mode=='weapon' and s.drawer,'Escape leaves the forge and restores the material list')
Click('material_edge')
assert(s.sub and not s.drawer and s.fodder=='edge')
local previous=rig.config
saveOK=false
Click('refine');assert(rig.config==previous and s.fodder=='edge')
saveOK=true
local random=math.random
math.random=function() return 1 end
Click('refine');math.random=random
assert(rig.config.progress.sand==0 and rig.config.progress.slots.sword.counts.edge==1 and rig.config.progress.slots.sword.ranks.edge==2)
Click('show_drawer');assert(not Has('material_edge'));Click('hide_drawer')
rig.config.progress.sand=1
rig.config.progress.slots.bow.counts.feather=2
Click('show_drawer');Click('filter_bow');Click('material_feather')
math.random=function() return 1 end
Click('refine');math.random=random
assert(rig.config.progress.sand==0 and rig.config.progress.slots.sword.ranks.edge==3)
assert(rig.config.progress.slots.bow.counts.feather==1 and rig.config.progress.slots.bow.imprints.edge=='feather')
Click('imprint_back')
Click('detail');Click('level');assert(rig.config.progress.slots.sword.levels.iron==2)
rig.config.progress.ore=20
Click('forge');assert(s.mode=='forge' and not Has('orbit_1') and not Has('detail'))
Click('pattern_warden');Click('forge_confirm')
assert(s.confirm and rig.config.progress.slots.sword.weapon=='iron')
Click('forge_confirm');Click('weapon')
local slot=rig.config.progress.slots.sword
assert(slot.weapon=='warden' and slot.levels.warden==2 and slot.levels.iron==nil and rig.config.progress.ore==14)
assert(s.mode=='weapon' and s.tab=='detail' and slot.imprints.edge=='edge')
local beforeClose=saved
held.G=true;Click('close');Tick(50)
assert(Forge.IsOpen() and saved==beforeClose and s.phase=='closing','close waits for release without writing equipment')
held.G=false;Tick(55)
assert(not Forge.IsOpen() and input.mouseMode==MM_RELATIVE)

local retired=s.layer
s=Open(rig)
retired.props.onPointerDown(Event(100,100));assert(not s.pointer)
safeToOpen=false;Tick();assert(not Forge.IsOpen())
safeToOpen=true
for _,size in ipairs({{844,390},{960,420},{720,360},{568,320},{1280,720}}) do
    width,height=size[1],size[2]
    Open(rig);CheckLayout();Finish()
end
for _,class in ipairs({'sword','bow','time'}) do
    selectedClass=class
    s=Open(rig);assert(s.class==class)
    for i=1,3 do Click('orbit_'..i);Tick(65);Render();assert(s.preview.centers[i].x==114) end
    Finish()
end
assert(rig.config.active=='sword' and cleared>0)
print('weapon_forge: safe area, drag, three slots, materials, upgrade, smelt, and teardown PASS')
