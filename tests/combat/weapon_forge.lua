-- Pure Lua 5.4 contract test. Native render/GC/input timing still needs Web testing.
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
local scenes,textures={},{}
local nativeFailure,bridgeFailure,sizeFailure=false,false,false
local liveContext='vg'
local videoCreates,videoDeletes=0,0
local cleared=0
local messages={}
local realPrint=print
rawset(_G,'print',function(message) messages[#messages+1]=tostring(message);realPrint(message) end)
local function LogCount(message)
    local count=0
    for _,line in ipairs(messages) do if line==message then count=count+1 end end
    return count
end
local width,height,dpr,scale=844,390,3,2
local safe={left=47,right=47,top=0,bottom=21}
for _,name in ipairs({'W','A','S','D','SHIFT','SPACE','1','2','3','E','Q','F','T','TAB','C','B','G','L','ESCAPE'}) do rawset(_G,'KEY_'..name,name) end
for i,name in ipairs({'MOUSEB_LEFT','MOUSEB_RIGHT','MOUSEB_MIDDLE','MM_ABSOLUTE','MM_RELATIVE','LIGHT_DIRECTIONAL','FILTER_NEAREST','TEXTURE_RENDERTARGET','SURFACE_MANUALUPDATE','CMD_CLEAR','NVG_ALIGN_CENTER','NVG_ALIGN_RIGHT'}) do rawset(_G,name,i) end
local fakeInput={numTouches=0,mouseMode=MM_RELATIVE,GetKeyDown=function(_,key) return held[key] end,GetMouseButtonDown=function(_,button) return buttons[button] end}
rawset(_G,'input',fakeInput)
local timerMs=0
local fakeTime={}
function fakeTime:GetElapsedTime()
    assert(self==fakeTime,'Time singleton requires colon dispatch')
    timerMs=timerMs+.01;return timerMs/1000
end
rawset(_G,'time',fakeTime)
rawset(_G,'GetTime',function() error('legacy GetTime/GetSystemTime path must not be used') end)
local function MakeNode(name,parent)
    local node=Mock.Node(name,parent)
    node.CreateChild=function(self,childName)
        local child=MakeNode(childName,self);self.children[#self.children+1]=child;return child
    end
    node.LookAt=function() return true end
    node.Dispose=function(self) assert(not self.disposed);self.disposed=true end
    node.CreateComponent=function(self,kind)
        if kind=='VoxelPhysicsWorld' then self.world=Mock.World(self);return self.world end
        return {SetBoundingBox=function() end,SetAmbientColor=function() end,SetLightType=function() end,SetBrightness=function() end}
    end
    node.CreateScriptObject=function()
        local receiver={}
        receiver.SubscribeToEvent=function(_,name,fn) eventHandlers[name]=fn end
        receiver.UnsubscribeFromAllEvents=function() eventHandlers={} end
        return receiver
    end
    return node
end
rawset(_G,'Node',function() return MakeNode('events') end)
rawset(_G,'Scene',function()
    if nativeFailure then error('test: render target unavailable') end
    local scene=MakeNode('preview');scenes[#scenes+1]=scene;return scene
end)
rawset(_G,'BoundingBox',function() return {} end)
rawset(_G,'Texture2D',{new=function()
    local texture={surface={updates=0,viewports=0}}
    texture.SetNumLevels=function(_,n) assert(n==1) end
    texture.SetSize=function(_,w,h) assert(w==512 and h==512);return not sizeFailure end
    texture.SetFilterMode=function(_,mode) assert(mode==FILTER_NEAREST) end
    texture.GetRenderSurface=function(self) return self.surface end
    texture.Dispose=function(self) assert(self.surface.viewports==0);assert(not self.disposed);self.disposed=true end
    texture.surface.SetViewport=function(self) self.viewports=1 end
    texture.surface.SetUpdateMode=function(_,mode) assert(mode==SURFACE_MANUALUPDATE) end
    texture.surface.QueueUpdate=function(self) self.updates=self.updates+1 end
    texture.surface.SetNumViewports=function(self,n) self.viewports=n end
    textures[#textures+1]=texture
    return texture
end})
rawset(_G,'Graphics',{GetRGBAFormat=function() return 1 end})
rawset(_G,'cache',{GetResource=function() return {} end})
rawset(_G,'Viewport',{new=function()
    local command={type=CMD_CLEAR}
    return {SetRenderPath=function() end,GetRenderPath=function()
        return {GetNumCommands=function() return 1 end,GetCommand=function() return command end}
    end}
end})
rawset(_G,'nvgCreateVideo',function() videoCreates=videoCreates+1;return bridgeFailure and 0 or videoCreates end)
rawset(_G,'nvgDeleteVideo',function() videoDeletes=videoDeletes+1 end)
for _,name in ipairs({'nvgSave','nvgRestore','nvgIntersectScissor','nvgTranslate','nvgBeginPath','nvgRect','nvgFillPaint','nvgImagePattern','nvgFill'}) do rawset(_G,name,function() end) end
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
UI.QueueOverlay=function(fn) fn(liveContext) end
local drawCalls={}
local Draw={colors={brown={1,2,3},ink={2,3,4},deep={4,5,6},paper={6,7,8},gold={8,9,10},muted={10,11,12}}}
Draw.Snap=function(n) return math.floor(n/2+.5)*2 end
Draw.PixelToHUD=function() return 1/dpr end
Draw.Metrics=function() return width,height,safe end
Draw.Begin=function() end
Draw.Finish=function() end
Draw.Image=function() end
Draw.Rect=function() end
Draw.NineSlice=function() end
Draw.Text=function(_,text,x,y,size) assert(size==12 or size==24);drawCalls[#drawCalls+1]={text=text,x=x,y=y} end
local combat='EXPLORE'
local currentWeapon='sword'
local equipOK=true
package.loaded['urhox-libs/UI']=UI
package.loaded['urhox-libs/UI/Core/ImageCache']={GetContext=function() return liveContext end}
package.loaded['ui.PixelDraw']=Draw
package.loaded['ui.TouchInput']={Clear=function() cleared=cleared+1 end}
package.loaded['combat.CombatState']={EXPLORE='EXPLORE',Get=function() return combat end,GetPose=function() return combat=='EXPLORE' and 'hidden' or 'back' end,
    GetWeapon=function() return currentWeapon end,SetWeapon=function(weapon) if not equipOK then return false end;currentWeapon=weapon;return true end}
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
    if button.body then
        s.scroll=math.max(0,math.min(s.maxScroll,b.y-s.body.y))
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
    drawCalls={}
    if s and s.layer then s.layer:Render('vg') end
end
local function CheckLayout()
    local s=State()
    assert(s.box.x>=safe.left and s.box.y>=safe.top)
    assert(s.box.x+s.box.w<=width-safe.right and s.box.y+s.box.h<=height-safe.bottom)
    for _,b in ipairs(s.buttons) do
        assert(b.box.w>=56 and b.box.h>=56,b.id..' too small')
        assert(b.box.x>=s.box.x and b.box.x+b.box.w<=s.box.x+s.box.w,b.id..' horizontal overflow')
        if not b.body then assert(b.box.y>=s.box.y and b.box.y+b.box.h<=s.box.y+s.box.h,b.id..' vertical overflow') end
    end
    for i,a in ipairs(s.buttons) do for j,b in ipairs(s.buttons) do
        if i<j and a.body==b.body then
            local x=math.min(a.box.x+a.box.w,b.box.x+b.box.w)-math.max(a.box.x,b.box.x)
            local y=math.min(a.box.y+a.box.h,b.box.y+b.box.h)-math.max(a.box.y,b.box.y)
            assert(x<=0 or y<=0,'overlapping buttons '..a.id..' / '..b.id)
        end
    end end
end
local safeToOpen=true
local function Open(options)
    options=options or {}
    options.canOpen=options.canOpen or function() return safeToOpen end
    return Forge.Open(options)
end
local function Flush()
    for _=1,200 do
        local current=State()
        if not current or not current.preview or not current.preview.job then return end
        Tick()
    end
    error('preview build did not complete')
end
assert(not Forge.Open(),'missing safety provider must fail closed')
assert(Forge.PreviewMode()==nil and Forge.Close(true) and Forge.ForceClose())
combat='COMBAT_IDLE';assert(not Open());combat='EXPLORE'
assert(not Open({canOpen=function() return false end}))
local opened,closed,applyCalls=0,0,{}
local mockRig={config=original,active='sword',pose='hidden'} --[[@as any]]
mockRig.Apply=function(_,config) applyCalls[#applyCalls+1]=config;return true end
mockRig.SetActive=function(self,weapon) self.active=weapon end
mockRig.SetPose=function(self,pose) self.pose=pose end
assert(Open({rig=mockRig,onOpen=function() opened=opened+1 end,onClose=function(config,wasSaved,kept)
    closed=closed+1;assert(config.active=='bow' and wasSaved and not kept)
end}))
assert(opened==1 and Forge.IsOpen() and fakeInput.mouseMode==MM_ABSOLUTE and cleared==1)
assert(#root.children==1 and State().preview and not State().fallback)
assert(State().preview.job and State().preview.world.created==0,'preview must build over frames')
assert(Forge.PreviewMode()==nil and LogCount('Forge preview: 3d')==0,'Open is not preview readiness')
assert(Open() and opened==1)
CheckLayout();Flush();Render()
assert(videoCreates==1)
assert(Forge.PreviewMode()==nil,'wait for a later frame after render surface queueing')
Tick();State().preview.mesh.volume.vertexCount=0;Render()
assert(Forge.PreviewMode()==nil and LogCount('Forge preview: 3d')==0,'empty native geometry is not ready')
State().preview.mesh.volume.vertexCount=4;Render()
assert(Forge.PreviewMode()=='3d' and LogCount('Forge preview: 3d')==1)
Tick();Render();assert(LogCount('Forge preview: 3d')==1,'no per-frame readiness log spam')
local s=State() --[[@as any]]
local scene=s.preview.scene
local world=s.preview.world
local rebuilt=world.rebuilds
local ortho=s.preview.camera.orthoSize
Click('part_blade_broad')
assert(s.config.sword.parts.blade=='blade_broad' and s.blueprint.stats.attack==13.5)
assert(world.rebuilds==rebuilt,'selection must not perform synchronous native rebuild')
Flush();Render()
assert(original.sword.parts.blade=='blade_straight' and world.rebuilds==rebuilt+1)
assert(s.preview.camera.orthoSize==ortho and s.preview.pivot.position.y==0,'grip and preview scale must stay fixed')
local comparison,delta=false,false
for _,draw in ipairs(drawCalls) do comparison=comparison or draw.text=='10点 → 13.5点';delta=delta or draw.text=='+3.5点' end
assert(comparison and delta,'real values, units and difference are required')
rebuilt=world.rebuilds
Click('color_primary')
for i=1,6 do Click('swatch_'..i);Flush();assert(s.config.sword.colors.primary==i) end
assert(world.rebuilds==rebuilt,'palette edits must not rebuild')
Click('swatch_3');Click('color_primary')
Click('slot_grip');Click('part_sword_grip_long');Flush()
Click('slot_reset');assert(s.config.sword.parts.grip==original.sword.parts.grip)
Click('undo');assert(s.config.sword.parts.grip=='sword_grip_long' and not s.undo)
Click('preset_fast');assert(s.config.sword.parts.blade=='blade_rapier')
Click('preset_armor');assert(s.blueprint.stats.armorBreak>1 and s.blueprint.stats.speed<1)
Click('undo');assert(s.config.sword.parts.blade=='blade_rapier')
Click('reset');assert(s.config.sword.parts.blade=='blade_straight')
Click('part_sword_grip_long');Flush()
local props=s.layer.props
s.scroll=0
local x=s.previewBox.x+s.previewBox.w/2
local y=s.previewBox.y+30
props.onPointerDown(Event(x,y));local yaw=s.yaw
props.onPointerMove(Event(x+30,y));props.onPointerUp(Event(x+30,y))
assert(s.yaw~=yaw and not s.autoSpin)
Tick();local updates=s.preview.surface.updates;Tick(8)
assert(s.preview.surface.updates==updates,'stopped preview must not redraw every frame')
Click('home');assert(s.yaw==25 and s.autoSpin)
props.onPointerDown(Event(x,y));props.onPointerUp(Event(x,y));Tick()
props.onPointerDown(Event(x,y));props.onPointerUp(Event(x,y));assert(s.yaw==25)
Click('tab_bow');Click('part_limbs_long');Click('slot_tip');Click('part_tip_crystal');Flush();Render()
assert(s.config.bow.parts.tip=='tip_crystal' and s.blueprint.stats.crystalRadius==.8)
local labels={}
for _,draw in ipairs(drawCalls) do labels[draw.text]=true end
assert(labels['拉弓速度'] and labels['射程'] and labels['移动'] and labels['破甲'] and not labels['散布'])
held.G=true;Click('equip')
assert(s.closing and Forge.IsOpen() and #root.children==1 and overlay)
assert(Forge.PreviewMode()==nil,'closed visual must not report a live preview during release latch')
assert(#applyCalls==2 and saved.active=='bow' and currentWeapon=='bow' and mockRig.active=='bow' and mockRig.pose=='hidden')
assert(scene.disposed and textures[1].disposed and videoDeletes==1)
assert(world.removed==world.created)
Tick(4);assert(Forge.IsOpen() and closed==0)
held.G=false;Tick(2)
assert(not Forge.IsOpen() and closed==1 and fakeInput.mouseMode==MM_RELATIVE and not next(eventHandlers))

-- Responsive collapse and explicit palettes preserve 56dp targets at every width.
width,height,dpr,scale=320,568,2,1.5
safe={left=0,right=0,top=20,bottom=24};nativeFailure=true
assert(Open());s=State();CheckLayout();Render()
assert(s.fallback and not s.preview and not s.wide and s.statsBox==nil)
assert(Forge.PreviewMode()=='fallback' and LogCount('Forge preview: fallback (scene)')==1)
Click('stats_toggle');CheckLayout();Render()
assert(s.statsBox.y>=s.previewBox.y+s.previewBox.h+56)
Click('color_primary');CheckLayout();Click('swatch_5');assert(s.config.sword.colors.primary==5)
local b=Button('swatch_2');x,y=Point(b);props=s.layer.props
props.onPointerDown(Event(x,y,1));props.onPointerUp(Event(x,y,2));assert(s.pointer)
props.onPointerCancel(Event(x,y,1));assert(not s.pointer)
props.onPointerDown(Event(x,y));props.onPointerMove(Event(x,y-28));props.onPointerUp(Event(x,y-28))
assert(s.config.sword.colors.primary==5,'scroll must not select a swatch')
for _,w in ipairs({320,430,719,720,844,960}) do
    width,height=w,390;safe={left=0,right=0,top=0,bottom=0};Render();CheckLayout()
    assert(s.wide==(w>=720))
end
Forge.Close();Tick(2)

-- Native failures clean up once; a subsequent Open can retry the capability.
nativeFailure=false;bridgeFailure=true
width,height=844,390
assert(Open());s=State()
local nextPreview=State().preview --[[@as any]]
scene=nextPreview.scene;world=nextPreview.world
Render();assert(s.fallback and not s.preview and scene.disposed and world.removed==world.created)
assert(Forge.PreviewMode()=='fallback' and LogCount('Forge preview: fallback (bridge)')==1)
local count=videoCreates
Render();Tick(5);Render();assert(videoCreates==count)
assert(LogCount('Forge preview: fallback (bridge)')==1)
Click('tab_bow');Click('slot_grip');Click('part_bow_grip_stable')
assert(s.blueprint.stats.move==.6)
Forge.Close();Tick(2)

-- Danger closes immediately without applying or saving; next safe Open restores undo too.
bridgeFailure=false
local savedBefore=saved
local draftApplies,draftCloses=0,0
local function DraftOptions()
    return {config=Store.Default(),onApply=function() draftApplies=draftApplies+1;return true end,
        onClose=function(_,wasSaved,kept) if kept then assert(not wasSaved);draftCloses=draftCloses+1 end end}
end
assert(Open(DraftOptions()));s=State();Click('part_blade_rapier')
Tick(3) -- Abort a partially allocated, not yet published preview volume.
local interruptedWorld=State().preview.world
buttons[MOUSEB_LEFT]=true
assert(Forge.Close(true) and not Forge.IsOpen(),'danger must not wait for held buttons')
assert(draftApplies==0 and saved==savedBefore and draftCloses==1 and #root.children==0)
assert(interruptedWorld.created==interruptedWorld.removed)
assert(not next(eventHandlers) and s.eventNode.removed and s.finished,'forced close must clean receiver now, without another Update')
assert(Forge.PreviewMode()==nil and Forge.ForceClose() and Forge.Close(true) and draftCloses==1)
Tick();buttons[MOUSEB_LEFT]=false
combat='COMBAT_ACTIVE';assert(not Open(DraftOptions()));combat='EXPLORE'
assert(Open(DraftOptions()));s=State()
assert(s.config.sword.parts.blade=='blade_rapier' and s.undo and s.original.sword.parts.blade=='blade_straight')
Click('undo');assert(s.config.sword.parts.blade=='blade_straight')
Click('part_blade_broad');safeToOpen=false;Tick()
assert(not Forge.IsOpen() and draftApplies==0 and draftCloses==2)
Tick();safeToOpen=true
assert(Open(DraftOptions()));assert(State().config.sword.parts.blade=='blade_broad')
Forge.Close();Tick(2);assert(draftApplies==1)
assert(Open(DraftOptions()));assert(State().config.sword.parts.blade=='blade_straight','equipping clears retained draft')
Forge.Close();Tick(2)
-- Scene.Stop can arrive during the release latch, with no future Update events.
local forcedCallbacks=0
assert(Open({onClose=function() forcedCallbacks=forcedCallbacks+1 end}))
s=State();local retiredLayer=s.layer
held.G=true;buttons[MOUSEB_LEFT]=true;fakeInput.numTouches=1
Forge.Close();assert(Forge.IsOpen() and not retiredLayer.destroyed)
Forge.Close(true)
assert(not Forge.IsOpen() and not overlay and #root.children==0 and not next(eventHandlers))
assert(retiredLayer.destroyed and s.eventNode.removed and fakeInput.mouseMode==MM_RELATIVE and forcedCallbacks==1)
local clearCount=cleared
assert(Forge.Close(true) and Forge.ForceClose() and Forge.ForceClose())
assert(forcedCallbacks==1 and cleared==clearCount and not next(eventHandlers),'repeated teardown must have no side effects')
held.G=false;buttons[MOUSEB_LEFT]=false;fakeInput.numTouches=0
assert(Open({onClose=function(_,_,kept) assert(kept);forcedCallbacks=forcedCallbacks+1 end}))
s=State()
retiredLayer.props.onPointerDown(Event(100,100));retiredLayer.props.onPointerMove(Event(120,100));retiredLayer.props.onPointerUp(Event(120,100))
assert(not s.pointer and retiredLayer.absoluteLayout.w==0,'stale UI pointer events must not touch a reopened forge')
assert(Forge.ForceClose())
assert(s.eventNode.removed and not next(eventHandlers) and forcedCallbacks==2)

-- Failed application/equip retains edits; failed disk save still applies this session.
local allowApply=false
saveOK=false
assert(Open({onApply=function() return allowApply end,onClose=function(_,wasSaved,kept) assert(not wasSaved and not kept) end}))
s=State();Click('part_blade_rapier')
assert(not Forge.Close() and Forge.IsOpen() and not s.closing and s.message)
allowApply=true;equipOK=false;Click('tab_bow');currentWeapon='sword'
assert(not Forge.Close() and not s.closing)
equipOK=true;assert(Forge.Close());Tick(2);assert(not Forge.IsOpen())
assert(Open({config={sword={},bow={}}}));assert(State().config.active=='sword')
Forge.Close();Tick(2)
sizeFailure=true
assert(Open());assert(State().fallback and not State().preview)
assert(Forge.PreviewMode()=='fallback' and LogCount('Forge preview: fallback (rendertexture)')==1)
Forge.Close();Tick(2);sizeFailure=false
assert(Open());Flush();Render()
local createsBefore,deletesBefore=videoCreates,videoDeletes
liveContext='vg2';Render()
assert(videoCreates==createsBefore+1 and videoDeletes==deletesBefore)
eventHandlers.KeyDown(nil,nil,{GetInt=function() return KEY_ESCAPE end})
Tick(2);assert(not Forge.IsOpen() and videoDeletes==deletesBefore+1)
assert(#root.children==0 and not overlay)
-- Unavailable or throwing Time must still finish assembly and emit readiness.
local oldOs=rawget(_G,'os')
rawset(_G,'os',nil)
for _,brokenTime in ipairs({false,{GetElapsedTime=function() error('Web binding failure') end}}) do
    rawset(_G,'time',brokenTime or nil)
    local readyLogs=LogCount('Forge preview: 3d')
    assert(Open());Flush();Tick();Render()
    assert(Forge.PreviewMode()=='3d' and State().buildMetrics.clockUnavailable)
    assert(LogCount('Forge preview: 3d')==readyLogs+1,'clock failure must not suppress preview readiness')
    Forge.ForceClose()
end
rawset(_G,'time',fakeTime);rawset(_G,'os',oldOs)
for _,texture in ipairs(textures) do assert(texture.disposed) end
for _,createdScene in ipairs(scenes) do assert(createdScene.disposed) end
for key in pairs(Forge) do assert(key=='Open' or key=='Close' or key=='IsOpen' or key=='ForceClose' or key=='PreviewMode') end
print('PASS weapon_forge: staged preview, safe drafts, presets/undo/slot reset, real stats, 720dp collapse, explicit palettes, fixed grip, input and cleanup')
