-- Pure Lua 5.4 contract test for the dark-glass forge panel + showroom hand-off.
-- NOT covered here (needs real Web/Windows runs): NanoVG appearance, MiSans glyph
-- coverage, the real ForgeShowroom module, camera/viewport switching.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local Parts=require('combat.WeaponCatalog')
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
Draw.Finish=function() end
Draw.Image=function() imageCalls=imageCalls+1 end
Draw.Text=function() end
local combat='EXPLORE'
local currentWeapon='sword'
local equipOK=true
package.loaded['urhox-libs/UI']=UI
package.loaded['ui.PixelDraw']=Draw
package.loaded['ui.TouchInput']={Clear=function() cleared=cleared+1 end}
package.loaded['combat.CombatState']={EXPLORE='EXPLORE',Get=function() return combat end,Engaged=function() return combat~='EXPLORE' end,GetPose=function() return combat=='EXPLORE' and 'hidden' or 'back' end,
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
    local p,c=s.panel,s.content
    assert(p.x+p.w==width and p.y==0 and p.h==height,'the sheet is flush with the right edge and full height')
    assert(p.w>=360 and p.w<=math.max(360,width*.52+1) or p.w==width,'sheet takes about half the screen')
    assert(c.x>=p.x and c.x+c.w<=width-safe.right and c.y>=safe.top and c.y+c.h<=height-safe.bottom,'content outside safe area')
    assert(s.stage.x+s.stage.w<=p.x,'stage must stay left of the panel')
    for _,b in ipairs(s.buttons) do
        local min=(b.kind=='primary' or b.id=='recommend' or b.id=='undo') and 44 or ((b.id=='more' or b.kind=='swatch') and 34 or 34)
        assert(b.box.h>=min and b.box.w>=34,b.id..' hit target too small')
        if b.kind=='route' then
            assert(b.box.x>=0 and b.box.x+b.box.w<=p.x,'route chips stay on the stage')
        elseif b.id=='more' then
            assert(b.box.x>=0 and b.box.x+b.box.w<=p.x+4,'more must sit on the stage, left of the sheet')
        else
            assert(b.box.x>=p.x and b.box.x+b.box.w<=p.x+p.w,b.id..' horizontal overflow')
            assert(b.box.x+b.box.w<=width-safe.right+4,b.id..' reaches under the notch')
        end
        if not b.area then assert(b.box.y>=0 and b.box.y+b.box.h<=height-safe.bottom+2,b.id..' vertical overflow') end
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
    options.onCommit=options.onCommit or function(config)
        if not equipOK then return false,'equip refused' end
        currentWeapon=config.active
        return true,nil,Store.Save(config)
    end
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
assert(not Open({canOpen=function() return false end}))
local s=OpenReady()
CheckLayout();Render()
for _,b in ipairs(s.buttons) do
    assert(not b.id:find('part_',1,true) and not b.id:find('slot_',1,true)
        and not b.id:find('route_',1,true) and b.id~='recommend','removed editor exposed')
end
Click('color_primary');Click('swatch_6')
assert(s.config.sword.colors.primary==6 and s.config.sword.parts==nil)
Click('undo');assert(s.config.sword.colors.primary==3)
Click('color_primary');Click('color_primary');Click('swatch_4')
assert(s.config.sword.colors.primary==4)
Click('tab_bow');CheckLayout();Render()
for _,b in ipairs(s.buttons) do assert(not b.id:find('color_',1,true),'bow must retain original colors') end
held.G=true;Click('equip')
assert(s.closing and Forge.IsOpen() and saved.active=='bow')
Tick(40);assert(Forge.IsOpen(),'held keys retain release guard')
held.G=false;Tick(80)
assert(not Forge.IsOpen() and #root.children==0 and not overlay and not next(eventHandlers))
assert(room.entered==room.exited)

for _,case in ipairs({{844,390},{960,420},{720,360},{667,375},{568,320},{1280,720}}) do
    width,height=case[1],case[2];safe={left=0,right=0,top=0,bottom=0}
    s=OpenReady();CheckLayout();Render();CloseAll()
end
width,height=844,390;safe={left=47,right=47,top=0,bottom=21}
room.enterOK=false;s=OpenReady();assert(s.fallback and Forge.PreviewMode()=='fallback');Render();CloseAll();ResetRoom()
room.enterThrows=true;s=OpenReady();assert(s.fallback);CloseAll();ResetRoom()
room.ready=false;s=OpenReady();assert(not s.fallback);Tick(60*7)
assert(s.fallback and not s.room);CloseAll();ResetRoom()
s=OpenReady();room.state='failed';Tick(2);assert(s.fallback);CloseAll();ResetRoom()
local update=package.loaded['combat.ForgeShowroom'].Update
package.loaded['combat.ForgeShowroom'].Update=function() error('update failed') end
s=OpenReady();assert(s.fallback);CloseAll();package.loaded['combat.ForgeShowroom'].Update=update

local commits=0
local function DraftOptions()
    return {config=Store.Default(),onCommit=function(config) commits=commits+1;return true,nil,true end}
end
s=OpenReady(DraftOptions());Click('color_primary');Click('swatch_6')
local retired=s.layer
buttons[MOUSEB_LEFT]=true
assert(Forge.ForceClose() and not Forge.IsOpen() and commits==0)
assert(retired.destroyed and s.eventNode.removed and room.entered==room.exited)
buttons[MOUSEB_LEFT]=false
s=OpenReady(DraftOptions());assert(s.config.sword.colors.primary==6)
retired.props.onPointerDown(Event(100,100));assert(not s.pointer)
Click('undo');assert(s.config.sword.colors.primary==3)
Click('color_primary');Click('swatch_4');safeToOpen=false;Tick()
assert(not Forge.IsOpen() and commits==0);safeToOpen=true
s=OpenReady(DraftOptions());assert(s.config.sword.colors.primary==4);CloseAll();assert(commits==1)
local before=room.entered
assert(Open());Tick(3);Forge.ForceClose();Tick(30);assert(room.entered==before)

local accepted=false
s=OpenReady({onCommit=function() return accepted,accepted and nil or 'failed',false end})
assert(not Forge.Close() and Forge.IsOpen() and not s.closing)
accepted=true;assert(Forge.Close());Forge.ForceClose()
assert(not Forge.IsOpen() and #root.children==0 and not overlay)
assert(Forge.ForceClose())
for _,fallback in ipairs({false,true}) do
    room.enterOK=not fallback;s=OpenReady();Render()
    for _=1,20 do s.layer:Render(liveContext) end
    collectgarbage('collect');collectgarbage('stop')
    local mem=collectgarbage('count')
    for _=1,240 do s.layer:Render(liveContext) end
    local perFrame=(collectgarbage('count')-mem)/240
    collectgarbage('restart');assert(perFrame<1,'forge steady rendering allocates too much')
    CloseAll()
end
assert(room.entered==room.exited and not next(eventHandlers))
print('weapon_forge: cosmetics, original bow, safety/drafts, failure, layout, fallback, teardown PASS')

local rig={config=Store.Default()}
rig.config.progress.ore=0
s=OpenReady({rig=rig})
Click('select_wing');assert(s.stageTitle=='翼剑')
Click('select_warden');assert(s.stageTitle=='守门长剑')
Click('select_iron');Click('tab_bow');Click('select_thorn');Click('select_silver')
assert(s.stageTitle=='银枝弓' and rig.config.progress.ore==0)
Click('select_field');Click('tab_sword');Click('equip');Tick(80)
-- Keep testing the paid smelting path with an unowned target.
rig.config.progress.slots.sword.levels.warden=nil
rig.config.progress.ore,rig.config.progress.sand=9,2
s=OpenReady({rig=rig})
Click('level_sword');Click('imprint_edge');Click('guarantee_sword')
assert(rig.config.progress.slots.sword.ranks.edge==2 and rig.config.progress.sand==0)
Click('smelt_warden');assert(s.confirm=='warden' and rig.config.progress.ore==8)
Click('smelt_warden');assert(rig.config.progress.slots.sword.levels.warden==2 and rig.config.progress.ore==2)
Click('color_primary');Click('swatch_6');assert(Forge.ForceClose())
rig.config.progress.ore=5 -- enemy reward between openings
s=OpenReady({rig=rig});assert(s.config.progress.ore==5 and s.config.sword.colors.primary==6)
Click('undo');assert(s.config.progress.ore==5 and s.config.sword.colors.primary==3)
Click('tab_time');Click('imprint_rift');Click('level_time');Click('equip');Tick(80)
assert(not Forge.IsOpen() and saved.progress.ore==4 and saved.progress.slots.time.levels.clock==2)
print('weapon_forge: touch purchase, smelt confirmation, restored draft and catalyst PASS')
