-- Pure Lua 5.4 contract test for the dark-glass forge panel + showroom hand-off.
-- NOT covered here (needs real Web/Windows runs): NanoVG appearance, MiSans glyph
-- coverage, the real ForgeShowroom module, camera/viewport switching.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local Parts=require('combat.WeaponParts')
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
for _,name in ipairs({'W','A','S','D','SHIFT','SPACE','1','2','3','E','Q','F','T','TAB','C','B','G','L','ESCAPE'}) do rawset(_G,'KEY_'..name,name) end
for i,name in ipairs({'MOUSEB_LEFT','MOUSEB_RIGHT','MOUSEB_MIDDLE','MM_ABSOLUTE','MM_RELATIVE'}) do rawset(_G,name,i) end
NVG_ALIGN_LEFT,NVG_ALIGN_CENTER,NVG_ALIGN_RIGHT,NVG_ALIGN_MIDDLE=1,2,4,16
local fakeInput={numTouches=0,mouseMode=MM_RELATIVE,GetKeyDown=function(_,key) return held[key] end,GetMouseButtonDown=function(_,button) return buttons[button] end}
rawset(_G,'input',fakeInput)
local clock=0
rawset(_G,'time',{GetElapsedTime=function(self) assert(self,'colon dispatch');clock=clock+.0001;return clock end})
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
Draw.Finish=function() end
Draw.Image=function() imageCalls=imageCalls+1 end
Draw.Text=function() end
local combat='EXPLORE'
local currentWeapon='sword'
local equipOK=true
package.loaded['urhox-libs/UI']=UI
package.loaded['ui.PixelDraw']=Draw
package.loaded['ui.TouchInput']={Clear=function() cleared=cleared+1 end}
package.loaded['combat.CombatState']={EXPLORE='EXPLORE',Get=function() return combat end,GetPose=function() return combat=='EXPLORE' and 'hidden' or 'back' end,
    GetWeapon=function() return currentWeapon end,SetWeapon=function(weapon) if not equipOK then return false end;currentWeapon=weapon;return true end}
-- Fake showroom: records the whole contract the panel relies on.
local room={enterOK=true,ready=true,state='ready',entered=0,exited=0,weapons={},drag={begin=0,by={},finish={}},homes=0,focus=nil,sceneSeen=nil,updates=0,enterThrows=false}
local active=false
package.loaded['combat.ForgeShowroom']={
    Enter=function(scene,opts)
        if room.enterThrows then error('showroom exploded') end
        room.sceneSeen=scene;room.focus=opts.focusX
        if not room.enterOK then return false end
        room.entered=room.entered+1;active=true;return true
    end,
    Exit=function() if active then room.exited=room.exited+1;active=false end end,
    SetWeapon=function(single) room.weapons[#room.weapons+1]=single end,
    Update=function() room.updates=room.updates+1 end,
    DragBegin=function() room.drag.begin=room.drag.begin+1 end,
    DragBy=function(dx) room.drag.by[#room.drag.by+1]=dx end,
    DragEnd=function(v) room.drag.finish[#room.drag.finish+1]=v end,
    Home=function() room.homes=room.homes+1 end,
    IsReady=function() return room.ready end,
    State=function() return room.state end,
    SetFocus=function(fx) room.focus=fx end,
}
local Forge=require('ui.ForgePanel')
---@return any
local function State()
    for i=1,10 do local name,value=debug.getupvalue(Forge.IsOpen,i);if name=='session' then return value end end
    error('missing session')
end
local function Tick(n)
    for _=1,n or 1 do
        if eventHandlers.Update then eventHandlers.Update(nil,nil,{GetFloat=function() return 1/60 end}) end
    end
end
local function Button(id)
    for _,b in ipairs(State().buttons) do if b.id==id then return b end end
    error('missing button '..id)
end
local function Event(x,y,id,button)
    return {x=x*dpr/scale,y=y*dpr/scale,pointerId=id or 1,pointerType='touch',button=button or MOUSEB_LEFT,
        StopPropagation=function(self) self.stopped=true end,PreventDefault=function(self) self.prevented=true end,
        IsPrimaryButton=function(self) return self.button==MOUSEB_LEFT end}
end
local function Point(button)
    local s=State()
    local b=button.box
    if button.area=='scroll' then
        s.scroll=math.max(0,math.min(s.maxScroll,b.y-s.view.y-8))
        return b.x+b.w/2,b.y-s.scroll+b.h/2
    end
    return b.x+b.w/2,b.y+b.h/2
end
local function Click(id)
    local button=Button(id)
    local x,y=Point(button)
    local props=State().layer.props
    local e=Event(x,y)
    props.onPointerDown(e);assert(e.stopped and e.prevented)
    props.onPointerUp(e)
end
local function Render()
    local s=State()
    if s and s.layer then s.layer:Render('vg') end
end
local function CheckLayout()
    local s=State()
    local p=s.panel
    assert(p.x>=safe.left and p.y>=safe.top and p.x+p.w<=width-safe.right and p.y+p.h<=height-safe.bottom,'panel outside safe area')
    assert(s.stage.x+s.stage.w<=p.x,'stage must stay left of the panel')
    for _,b in ipairs(s.buttons) do
        local min=(b.kind=='plain' or b.kind=='primary') and 44 or 34
        assert(b.box.h>=min and b.box.w>=34,b.id..' hit target too small')
        assert(b.box.x>=p.x and b.box.x+b.box.w<=p.x+p.w,b.id..' horizontal overflow')
        if not b.area then assert(b.box.y>=p.y and b.box.y+b.box.h<=p.y+p.h,b.id..' vertical overflow') end
    end
    for i,a in ipairs(s.buttons) do for j,b in ipairs(s.buttons) do
        if i<j and a.area==b.area then
            local x=math.min(a.box.x+a.box.w,b.box.x+b.box.w)-math.max(a.box.x,b.box.x)
            local y=math.min(a.box.y+a.box.h,b.box.y+b.box.h)-math.max(a.box.y,b.box.y)
            assert(x<=0 or y<=0,'overlapping buttons '..a.id..' / '..b.id)
        end
    end end
    -- Scrolling content must never reach under the fixed footer.
    assert(s.view.y+s.view.h<=s.footerY)
end
local safeToOpen=true
local function Open(options)
    options=options or {}
    options.canOpen=options.canOpen or function() return safeToOpen end
    if options.scene==nil then options.scene={name='main-scene'} end
    return Forge.Open(options)
end
local function OpenReady(options)
    local ok=Open(options)
    assert(ok);Tick(40)
    return State()
end
local function CloseAll() Forge.Close();Tick(60) end
local function ResetRoom()
    room.enterOK,room.ready,room.state,room.enterThrows=true,true,'ready',false
end

assert(not Forge.Open(),'missing safety provider must fail closed')
assert(Forge.PreviewMode()==nil and Forge.Close(true) and Forge.ForceClose())
combat='COMBAT_IDLE';assert(not Open());combat='EXPLORE'
assert(not Open({canOpen=function() return false end}))

-- ---------------------------------------------------------------- normal flow
local opened,closed,applyCalls=0,0,{}
local mockRig={config=original,active='sword',pose='hidden',scene={name='rig-scene'}} --[[@as any]]
mockRig.Apply=function(_,config) applyCalls[#applyCalls+1]=config;return true end
mockRig.SetActive=function(self,weapon) self.active=weapon end
mockRig.SetPose=function(self,pose) self.pose=pose end
assert(Open({rig=mockRig,scene=false,onOpen=function() opened=opened+1 end,onClose=function(config,wasSaved,kept)
    closed=closed+1;assert(config.active=='bow' and wasSaved and not kept)
end}))
assert(opened==1 and Forge.IsOpen() and fakeInput.mouseMode==MM_ABSOLUTE and cleared==1 and #root.children==1)
local s=State()
assert(s.phase=='opening' and room.entered==0,'the showroom is entered only after the fade to black')
assert(Forge.PreviewMode()==nil and LogCount('Forge preview: 3d')==0)
CheckLayout();Render()
assert(Open() and opened==1,'second Open joins the live session')
Tick(10);assert(room.entered==0)
Tick(4);assert(room.entered==1 and s.phase=='revealing' and room.sceneSeen==mockRig.scene,'scene falls back to rig.scene')
assert(room.focus and room.focus>0 and room.focus<.5,'weapon focus sits in the left half')
assert(#room.weapons==1 and room.weapons[1].weapon=='sword' and room.weapons[1].parts.blade=='blade_straight')
Tick(1);assert(Forge.PreviewMode()=='3d' and LogCount('Forge preview: 3d')==1)
Tick(30);assert(s.phase=='open' and LogCount('Forge preview: 3d')==1,'no per-frame readiness log spam')
assert(room.updates>20,'the showroom is stepped every frame')
rects=0;Render();local readyRects=rects
CheckLayout()

-- Part selection: real values, units, and the weapon is re-sent to the showroom.
Click('part_blade_broad')
assert(s.config.sword.parts.blade=='blade_broad' and s.blueprint.stats.attack==13.5)
assert(#room.weapons==2 and room.weapons[2].parts.blade=='blade_broad')
local attack=s.statRows[1]
assert(attack.label=='攻击' and attack.text=='10 → 13.5' and attack.delta=='+3.5' and attack.up)
assert(s.statRows[2].label=='速度 ×' and s.statRows[3].label:find('范围',1,true))
for _,row in ipairs(s.statRows) do assert(row.fraction>=0 and row.fraction<=1) end
assert(#s.statRows==3,'three headline stats; the rest sit behind 更多数值')
Click('more');assert(s.moreOpen and #s.moreRows==2 and s.moreRows[1].label=='失衡');CheckLayout();Render()
Click('more');assert(not s.moreOpen and not s.moreBox)
-- Colours: palette opens inside the scroll area and edits rebuild without touching parts.
Click('color_primary');CheckLayout();Render()
assert(s.colorChannel=='primary' and s.paletteBox)
local sends=#room.weapons
for i=1,6 do Click('swatch_'..i);assert(s.config.sword.colors.primary==i) end
assert(#room.weapons==sends+6)
Click('swatch_3');Click('color_primary');assert(not s.colorChannel and not s.paletteBox)
-- Slots, recommended menu, undo, reset.
Click('slot_grip');assert(s.slot=='grip');Click('part_sword_grip_long');assert(s.config.sword.parts.grip=='sword_grip_long')
Click('recommend');assert(s.menuOpen and s.menuBox);CheckLayout();Render()
Click('slot_reset');assert(not s.menuOpen and s.config.sword.parts.grip==original.sword.parts.grip)
Click('undo');assert(s.config.sword.parts.grip=='sword_grip_long' and not s.undo)
Click('recommend');Click('preset_fast');assert(s.config.sword.parts.blade=='blade_rapier' and not s.menuOpen)
Click('recommend');Click('preset_armor');assert(s.blueprint.stats.armorBreak>1 and s.blueprint.stats.speed<1)
Click('undo');assert(s.config.sword.parts.blade=='blade_rapier')
Click('recommend');Click('reset');assert(s.config.sword.parts.blade=='blade_straight')
-- Tapping outside an open menu only closes it (no click-through).
Click('recommend');assert(s.menuOpen)
do
    local props=s.layer.props
    local tab=Button('tab_bow');local x,y=Point(tab)
    props.onPointerDown(Event(x,y));props.onPointerUp(Event(x,y))
    assert(not s.menuOpen and s.weapon=='sword','outside tap closes the menu without activating what is under it')
end
Click('part_sword_grip_long')
-- Stage gestures: drag rotates, a quick second tap resets, panel drags scroll instead of selecting.
do
    local props=s.layer.props
    local x,y=s.stage.x+s.stage.w/2,s.stage.y+s.stage.h/2
    props.onPointerDown(Event(x,y));Tick()
    props.onPointerMove(Event(x+30,y));Tick();props.onPointerMove(Event(x+60,y));props.onPointerUp(Event(x+60,y))
    assert(room.drag.begin==1 and #room.drag.by>=1 and #room.drag.finish==1 and room.drag.finish[1]~=0)
    props.onPointerDown(Event(x,y));props.onPointerUp(Event(x,y));Tick()
    props.onPointerDown(Event(x,y));props.onPointerUp(Event(x,y));assert(room.homes==1)
end
do
    local props=s.layer.props
    s.scroll=0
    local card=Button('slot_grip');local x,y=card.box.x+card.box.w/2,card.box.y+card.box.h/2
    local before=s.slot
    props.onPointerDown(Event(x,y));props.onPointerMove(Event(x,y-30));props.onPointerUp(Event(x,y-30))
    assert(s.slot==before and s.scroll>0 or s.maxScroll==0,'dragging a button scrolls and does not select it')
    props.onPointerDown(Event(x,y,1));props.onPointerUp(Event(x,y,2));assert(s.pointer)
    props.onPointerCancel(Event(x,y,1));assert(not s.pointer)
end
-- Bow tab and its stats.
Click('tab_bow');assert(s.weapon=='bow' and s.slot=='limbs' and #room.weapons>0 and room.weapons[#room.weapons].weapon=='bow')
Click('part_limbs_long');Click('slot_tip');Click('part_tip_crystal')
assert(s.config.bow.parts.tip=='tip_crystal' and s.blueprint.stats.crystalRadius==.8)
assert(s.statRows[1].label:find('拉弓速度',1,true) and s.statRows[2].label:find('射程',1,true) and s.statRows[3].label:find('移动',1,true))
Click('more');assert(s.moreRows[1].label:find('破甲',1,true));Click('more')
CheckLayout();Render()
-- Equip: edits apply immediately, the visual closes through the fade + release latch.
held.G=true;Click('equip')
assert(s.closing and Forge.IsOpen() and #root.children==1 and overlay and Forge.PreviewMode()==nil)
assert(#applyCalls==2 and saved.active=='bow' and currentWeapon=='bow' and mockRig.active=='bow' and mockRig.pose=='hidden')
Tick(30);assert(Forge.IsOpen() and closed==0 and room.exited==0,'held key blocks the release latch and the showroom stays up')
held.G=false;Tick(14)
assert(room.exited==1 and Forge.IsOpen(),'showroom exits at full black, then the overlay fades out')
Tick(30)
assert(not Forge.IsOpen() and closed==1 and fakeInput.mouseMode==MM_RELATIVE and not next(eventHandlers) and #root.children==0 and not overlay)
assert(room.entered==room.exited)

-- ---------------------------------------------------------------- layouts
for _,case in ipairs({{844,390},{960,420},{720,360},{667,375},{568,320},{1280,720}}) do
    width,height=case[1],case[2];safe={left=0,right=0,top=0,bottom=0}
    s=OpenReady();CheckLayout();Render()
    width,height=case[1]+1,case[2];Render();CheckLayout()
    assert(room.focus<.6,'re-layout updates the showroom focus')
    CloseAll()
end
width,height=844,390;safe={left=47,right=47,top=0,bottom=21}
-- Notched / unsafe areas shrink the panel but never leave the screen.
safe={left=64,right=64,top=24,bottom=34};s=OpenReady();CheckLayout();CloseAll()
safe={left=47,right=47,top=0,bottom=21}

-- ---------------------------------------------------------------- fallbacks
room.enterOK=false
s=OpenReady();assert(s.fallback and not s.room and room.exited==room.entered)
assert(Forge.PreviewMode()=='fallback' and LogCount('Forge preview: fallback (enter)')==1)
rects=0;Render()
local fallbackRects=rects
assert(fallbackRects>readyRects+10,'fallback draws the 2D voxel side view on top of the normal UI')
Click('part_blade_broad');assert(s.config.sword.parts.blade=='blade_broad')
Tick(10);assert(LogCount('Forge preview: fallback (enter)')==1)
CloseAll();ResetRoom()
room.enterThrows=true
s=OpenReady();assert(s.fallback and Forge.PreviewMode()=='fallback');CloseAll();ResetRoom()
-- Room that never becomes ready: fall back after the timeout and release it.
local entered=room.entered
room.ready=false
s=OpenReady();assert(not s.fallback and Forge.PreviewMode()==nil and s.room)
rects=0;Render();local preparingRects=rects
Tick(60*7)
assert(preparingRects<fallbackRects,'while the room is preparing, no 2D side view flash')
assert(s.fallback and not s.room and LogCount('Forge preview: fallback (timeout)')==1 and room.exited==room.entered)
CloseAll();ResetRoom()
-- Room that reports failure.
s=OpenReady();room.state='failed';Tick(2)
assert(s.fallback and LogCount('Forge preview: fallback (failed)')==1)
CloseAll();ResetRoom()
-- Missing showroom module at runtime: updates that throw also fall back.
package.loaded['combat.ForgeShowroom'].Update=function() error('update failed') end
s=OpenReady();assert(s.fallback and LogCount('Forge preview: fallback (update)')==1);CloseAll()
package.loaded['combat.ForgeShowroom'].Update=function() room.updates=room.updates+1 end
-- SetWeapon failures also degrade without breaking edits.
local oldSet=package.loaded['combat.ForgeShowroom'].SetWeapon
package.loaded['combat.ForgeShowroom'].SetWeapon=function() error('mesh failed') end
s=OpenReady();assert(s.fallback and LogCount('Forge preview: fallback (mesh)')==1)
Click('part_blade_broad');assert(s.config.sword.parts.blade=='blade_broad');CloseAll()
package.loaded['combat.ForgeShowroom'].SetWeapon=oldSet

-- ---------------------------------------------------------------- danger close / drafts
local savedBefore=saved
local draftApplies,draftCloses=0,0
local function DraftOptions()
    return {config=Store.Default(),onApply=function() draftApplies=draftApplies+1;return true end,
        onClose=function(_,wasSaved,kept) if kept then assert(not wasSaved);draftCloses=draftCloses+1 end end}
end
local exitedBefore=room.exited
s=OpenReady(DraftOptions());Click('part_blade_rapier')
buttons[MOUSEB_LEFT]=true
assert(Forge.Close(true) and not Forge.IsOpen(),'danger must not wait for held buttons or fades')
assert(draftApplies==0 and saved==savedBefore and draftCloses==1 and #root.children==0)
assert(room.exited==exitedBefore+1 and room.entered==room.exited,'danger close releases the showroom immediately')
assert(not next(eventHandlers) and s.eventNode.removed and s.finished)
assert(Forge.PreviewMode()==nil and Forge.ForceClose() and Forge.Close(true) and draftCloses==1)
buttons[MOUSEB_LEFT]=false
combat='COMBAT_ACTIVE';assert(not Open(DraftOptions()));combat='EXPLORE'
s=OpenReady(DraftOptions())
assert(s.config.sword.parts.blade=='blade_rapier' and s.undo and s.original.sword.parts.blade=='blade_straight')
Click('undo');assert(s.config.sword.parts.blade=='blade_straight')
Click('part_blade_broad');safeToOpen=false;Tick()
assert(not Forge.IsOpen() and draftApplies==0 and draftCloses==2,'losing safe ground closes the forge and keeps the draft')
safeToOpen=true
s=OpenReady(DraftOptions());assert(s.config.sword.parts.blade=='blade_broad')
CloseAll();assert(draftApplies==1)
s=OpenReady(DraftOptions());assert(s.config.sword.parts.blade=='blade_straight','equipping clears the retained draft')
CloseAll()
-- Scene.Stop during the release latch: the latch finishes without another Update.
local forcedCallbacks=0
assert(Open({onClose=function() forcedCallbacks=forcedCallbacks+1 end}));Tick(40)
s=State();local retiredLayer=s.layer
held.G=true;buttons[MOUSEB_LEFT]=true;fakeInput.numTouches=1
Forge.Close();assert(Forge.IsOpen() and not retiredLayer.destroyed)
Forge.Close(true)
assert(not Forge.IsOpen() and not overlay and #root.children==0 and not next(eventHandlers))
assert(retiredLayer.destroyed and s.eventNode.removed and fakeInput.mouseMode==MM_RELATIVE and forcedCallbacks==1)
assert(room.entered==room.exited)
local clearCount=cleared
assert(Forge.Close(true) and Forge.ForceClose() and Forge.ForceClose())
assert(forcedCallbacks==1 and cleared==clearCount,'repeated teardown has no side effects')
held.G=false;buttons[MOUSEB_LEFT]=false;fakeInput.numTouches=0
assert(Open({onClose=function(_,_,kept) assert(kept);forcedCallbacks=forcedCallbacks+1 end}));s=State()
retiredLayer.props.onPointerDown(Event(100,100));retiredLayer.props.onPointerMove(Event(120,100));retiredLayer.props.onPointerUp(Event(120,100))
assert(not s.pointer and retiredLayer.absoluteLayout.w==0,'stale UI pointer events must not touch a reopened forge')
assert(Forge.ForceClose() and s.eventNode.removed and forcedCallbacks==2)
-- Closing during the opening fade never enters (or leaks) the showroom.
local before=room.entered
assert(Open());Tick(3);Forge.ForceClose();Tick(30);assert(room.entered==before and not Forge.IsOpen())

-- ---------------------------------------------------------------- failed apply / equip / save
local allowApply=false
saveOK=false
assert(Open({onApply=function() return allowApply end,onClose=function(_,wasSaved,kept) assert(not wasSaved and not kept) end}));Tick(40)
s=State();Click('part_blade_rapier')
assert(not Forge.Close() and Forge.IsOpen() and not s.closing and s.message)
rects=0;Render()
allowApply=true;equipOK=false;Click('tab_bow');currentWeapon='sword'
assert(not Forge.Close() and not s.closing)
equipOK=true;assert(Forge.Close());Tick(80);assert(not Forge.IsOpen())
saveOK=true
assert(Open({config={sword={},bow={}}}));assert(State().config.active=='sword')
eventHandlers.KeyDown(nil,nil,{GetInt=function() return KEY_ESCAPE end})
Tick(80);assert(not Forge.IsOpen() and #root.children==0 and not overlay)
-- Escape closes an open menu first.
s=OpenReady();Click('recommend')
eventHandlers.KeyDown(nil,nil,{GetInt=function() return KEY_ESCAPE end});assert(Forge.IsOpen() and not s.menuOpen)
eventHandlers.MouseWheel(nil,nil,{GetInt=function() return -1 end});assert(s.scroll>=0)
CloseAll()

-- ---------------------------------------------------------------- allocation probe
-- Steady-state Lua allocation per drawn frame. Native NanoVG allocations are not measured.
for _,fallback in ipairs({false,true}) do
    room.enterOK=not fallback
    s=OpenReady();Render()
    for _=1,20 do s.layer:Render(liveContext) end
    collectgarbage('collect');collectgarbage('stop')
    local mem=collectgarbage('count')
    for _=1,240 do s.layer:Render(liveContext) end
    local perFrame=(collectgarbage('count')-mem)/240
    collectgarbage('restart')
    print(string.format('BENCH %s %.6f KiB/frame (240 frames, GC stopped)',fallback and '2d' or '3d',perFrame))
    assert(perFrame<1,'steady forge render regressed above 1 KiB/frame')
    CloseAll()
end
ResetRoom()
assert(room.entered==room.exited,'every entered showroom was exited exactly once')
for key in pairs(Forge) do assert(key=='Open' or key=='Close' or key=='IsOpen' or key=='ForceClose' or key=='PreviewMode') end
print('PASS weapon_forge: glass panel, sky-showroom hand-off, fades, drafts/undo/presets, real stats, layouts, fallbacks, input and cleanup')
