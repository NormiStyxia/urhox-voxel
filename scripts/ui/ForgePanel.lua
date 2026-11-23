-- Weapon preparation overlay. UI owns the NanoVG frame and pointer dispatch.
local UI = require('urhox-libs/UI')
local Draw = require('ui.PixelDraw')
local View = require('ui.ForgeLayout')
local Preview = require('ui.ForgePreview')
local Catalog = require('combat.WeaponCatalog')
local Store = require('combat.WeaponStore')
local CombatState = require('combat.CombatState')
local TouchInput = require('ui.TouchInput')
local M = {}
local session
local FADE,REVEAL=.20,.30
local HELD_KEYS={KEY_W,KEY_A,KEY_S,KEY_D,KEY_SHIFT,KEY_SPACE,KEY_1,KEY_2,KEY_3,KEY_E,KEY_R,KEY_Q,KEY_F,KEY_T,KEY_TAB,KEY_C,KEY_B,KEY_G,KEY_L,KEY_ESCAPE}
local function Clamp(n,lo,hi) return math.min(hi,math.max(n,lo)) end
local function Round(n) return math.floor(n+.5) end
local function Safe(callbacks)
    if CombatState.Engaged() or (CombatState.HasAggro and CombatState.HasAggro()) then return false end
    if callbacks.canOpen then return callbacks.canOpen()==true end
    local controller=callbacks.rig and callbacks.rig.controller
    if not controller or not controller.cc or not controller.cc.onGround or not controller.Position then return false end
    local p=controller:Position()
    return require('ruins.RuinsTerrain').IsSafeGround(p.x,p.y,p.z)==true
end
local function PublishHud(hidden)
    rawset(_G,'FORGE_HUD_HIDDEN',hidden)
end
PublishHud(false)

local function Grid()
    local w,h,inset=Draw.Metrics()
    local pixel=Draw.PixelToHUD()
    local width,height=w-inset.left-inset.right,h-inset.top-inset.bottom
    local scale=math.min(width/View.width,height/View.height)
    -- Use whole display pixels whenever the full 380 x 214 grid fits.
    if scale>=pixel then scale=math.floor(scale/pixel)*pixel end
    scale=math.max(scale,0.01)
    local x=inset.left+(width-View.width*scale)*.5
    local y=inset.top+(height-View.height*scale)*.5
    return Round(x/pixel)*pixel,Round(y/pixel)*pixel,scale,w,h
end
local function Position(event)
    local x,y,scale=Grid()
    local ui=UI.GetScale()*Draw.PixelToHUD()
    return (event.x*ui-x)/scale,(event.y*ui-y)/scale
end
local function Hit(s,x,y)
    for i=#s.buttons,1,-1 do
        local b=s.buttons[i]
        if x>=b.x and y>=b.y and x<b.x+b.w and y<b.y+b.h then return b end
    end
end
local function Consume(event) event:StopPropagation(); event:PreventDefault() end
local function Down(event)
    Consume(event)
    local s=session
    if not s or s.phase~='open' or s.pointer then return end
    if event.pointerType=='mouse' and not event:IsPrimaryButton() then return end
    local x,y=Position(event)
    local b=Hit(s,x,y)
    s.pointer={id=event.pointerId,button=b and b.id,x=x,y=y,startX=x,startY=y,
        stage=x>=16 and x<212 and y>30 and y<196,
        drawer=s.mode=='weapon' and s.drawer and x>=222 and x<358 and y>=125 and y<194}
end
local function Move(event)
    Consume(event)
    local s=session
    local p=s and s.pointer
    if not p or p.id~=event.pointerId then return end
    local x,y=Position(event)
    if not p.moved then
        if math.abs(x-p.startX)+math.abs(y-p.startY)<4 then return end
        p.moved=true
    end
    if p.stage then
        s.preview.yaw=(s.preview.yaw+(x-p.x)*.028)%(math.pi*2)
        s.preview.pitch=Clamp(s.preview.pitch+(y-p.y)*.02,-.7,.7)
    elseif p.drawer and math.abs(y-p.y)>=12 then
        s.scroll=math.max(0,s.scroll+(y<p.y and 1 or -1))
    else
        return
    end
    p.x,p.y=x,y
end
local function Up(event)
    Consume(event)
    local s=session
    local p=s and s.pointer
    if not p or p.id~=event.pointerId then return end
    s.pointer=nil
    if p.moved then return end
    local x,y=Position(event)
    local b=Hit(s,x,y)
    if b and p.button==b.id then b.action()
    elseif p.stage and not p.button then
        if s.lastTap and s.clock-s.lastTap<.35 then s.home();s.lastTap=nil
        else s.lastTap=s.clock end
    end
end
local function Cancel(event)
    Consume(event)
    if session and session.pointer and session.pointer.id==event.pointerId then session.pointer=nil end
end

local Layer=UI.Panel:Extend('PixelForgePanel')
function Layer:Render()
    local s=session
    if s then UI.QueueOverlay(s.render) end
end
local function Render(vg,s)
    local x,y,scale,w,h=Grid()
    Draw.Begin(vg,true)
    local phase=s.phase
    if phase~='opening' and phase~='closed_reveal' then
        Draw.Rect(vg,0,0,w,h,{20,26,36})
        Draw.Save(vg);nvgTranslate(vg,x,y);nvgScale(vg,scale,scale)
        View.Draw(vg,s)
        Draw.Restore(vg)
    end
    local alpha=0
    if phase=='opening' or phase=='closing' then alpha=Clamp(s.phaseTime/FADE,0,1)
    elseif phase=='reveal' or phase=='closed_reveal' then alpha=1-Clamp(s.phaseTime/REVEAL,0,1) end
    if alpha>0 then Draw.Rect(vg,0,0,w,h,{0,0,0},alpha) end
    Draw.Finish(vg)
end
local function Released()
    if input.numTouches>0 or input:GetMouseButtonDown(MOUSEB_LEFT) or input:GetMouseButtonDown(MOUSEB_RIGHT)
        or input:GetMouseButtonDown(MOUSEB_MIDDLE) then return false end
    for _,key in ipairs(HELD_KEYS) do if input:GetKeyDown(key) then return false end end
    return true
end
local function Finish(s)
    session=nil
    PublishHud(false)
    local layer=s.layer
    UI.PopOverlay(layer);s.root:RemoveChild(layer)
    layer.absoluteLayout={x=0,y=0,w=0,h=0}
    layer.props.onPointerDown=Consume;layer.props.onPointerMove=Consume
    layer.props.onPointerUp=Consume;layer.props.onPointerCancel=Consume
    layer:Destroy()
    s.receiver:UnsubscribeFromAllEvents();s.node:Remove()
    if input.mouseMode==MM_ABSOLUTE then input.mouseMode=s.mouseMode end
    TouchInput.Clear()
    if s.callbacks.onClose then s.callbacks.onClose(s.config,s.saved) end
end
local function Update(_,_,data)
    local s=session
    if not s then return end
    local dt=Clamp(data:GetFloat('TimeStep'),0,.10)
    s.phaseTime=s.phaseTime+dt
    if s.phase=='closing' then
        if s.phaseTime>=FADE and Released() then s.phase,s.phaseTime='closed_reveal',0 end
    elseif s.phase=='closed_reveal' then
        if s.phaseTime>=REVEAL then Finish(s);return end
    else
        if not Safe(s.callbacks) then Finish(s);return end
        s.clock=s.clock+dt
        if s.phase=='opening' and s.phaseTime>=FADE then s.phase,s.phaseTime='reveal',0
        elseif s.phase=='reveal' and s.phaseTime>=REVEAL then s.phase,s.phaseTime='open',0 end
        local delta=(s.targetAngle-s.preview.angle+math.pi)%(math.pi*2)-math.pi
        s.preview.angle=math.abs(delta)<.001 and s.targetAngle or s.preview.angle+delta*math.min(1,dt*8)
    end
    PublishHud(M.HudHidden())
end
local function Blueprints()
    local list={}
    for _,class in ipairs(Catalog.Classes) do
        for i=2,#Catalog.Weapons[class] do
            local item=Catalog.Weapons[class][i]
            list[#list+1]={class=class,id=item.id,name=item.name}
        end
    end
    return list
end

function M.Open(rigOrCallbacks)
    if session then return session.phase~='closing' and session.phase~='closed_reveal' end
    local callbacks=rigOrCallbacks or {}
    if callbacks.ApplyAppearance then callbacks={rig=callbacks} end
    local root=UI.GetRoot()
    if not root or not Safe(callbacks) then return false end
    local rig=callbacks.rig
    local config=Store.Normalize((rig and rig.config) or callbacks.config or Store.Load(),true) or Store.Default()
    local class=callbacks.class or CombatState.GetSelection() or config.active
    if not Catalog.Weapons[class] then class=config.active end
    local s={callbacks=callbacks,config=config,class=class,root=root,preview=Preview.New(),mode='weapon',tab='detail',
        focusIndex=1,targetAngle=math.pi/6,clock=0,phase='opening',phaseTime=0,buttons={},mouseMode=input.mouseMode,
        method='smelt',blueprints=Blueprints(),pattern=1,scroll=0}
    s.home=function()
        local id=s.mode=='forge' and s.blueprints[s.pattern].id or s.config.progress.slots[s.class].weapon
        Preview.Home(s.preview,id)
    end
    s.focus=function(i)
        s.tab,s.focusIndex,s.targetAngle='imprint',i,-(i-1)*math.pi*2/3
        s.sub,s.drawer,s.notice=false,false,nil
    end
    s.showDetail=function()
        s.tab,s.targetAngle,s.sub,s.drawer,s.notice='detail',math.pi/6,false,false,nil
    end
    s.back=function()
        if s.drawer then s.drawer=false
        elseif s.sub then s.sub=false;s.notice=nil end
    end
    s.showForge=function()
        s.mode,s.confirm,s.notice='forge',nil,nil
        s.home()
    end
    s.showWeapon=function()
        s.mode,s.notice='weapon',nil
        s.home()
    end
    s.choosePattern=function(i)
        s.pattern,s.confirm,s.notice=i,nil,nil
        s.home()
    end
    s.close=function() if s.mode=='forge' then s.showWeapon() else M.Close() end end
    s.edit=function(editClass,action,id,option)
        if not Safe(callbacks) then Finish(s);return end
        local ok,message
        if rig then
            ok,message=Store.Forge(rig,editClass,action,id,option)
            if ok then s.config=rig.config;s.saved=true end
        end
        s.notice=message or (ok and '已保存' or '整备入口未就绪')
        if ok and action=='refine' then s.fodder=nil end
    end
    s.home()
    if callbacks.mode=='forge' then s.showForge() end
    session=s
    s.render=function(vg) if session==s then Render(vg,s) end end
    s.layer=Layer{position='absolute',left=0,top=0,width='100%',height='100%',
        onPointerDown=Down,onPointerMove=Move,onPointerUp=Up,onPointerCancel=Cancel,
        onClick=function(_,event) if event then Consume(event) end end}
    s.layer.focusable=false
    root:AddChild(s.layer);UI.PushOverlay(s.layer)
    s.node=Node()
    s.receiver=s.node:CreateScriptObject('LuaScriptObject')
    s.receiver:SubscribeToEvent('Update',Update)
    s.receiver:SubscribeToEvent('KeyDown',function(_,_,data)
        if s.phase~='open' then return end
        local key=data:GetInt('Key')
        if key==KEY_ESCAPE then
            if s.mode=='weapon' and (s.drawer or s.sub) then s.back()
            else s.close() end
        elseif s.mode=='weapon' and not s.sub then
            if key==KEY_A or key==KEY_LEFT then s.focus((s.focusIndex+1)%3+1)
            elseif key==KEY_D or key==KEY_RIGHT then s.focus(s.focusIndex%3+1) end
        end
    end)
    s.receiver:SubscribeToEvent('MouseWheel',function(_,_,data)
        if s.phase=='open' and s.mode=='weapon' and s.drawer then
            s.scroll=math.max(0,s.scroll-data:GetInt('Wheel'))
        end
    end)
    input.mouseMode=MM_ABSOLUTE
    TouchInput.Clear()
    if callbacks.onOpen then callbacks.onOpen() end
    return true
end

function M.Close(immediate)
    local s=session
    if not s then return true end
    if immediate or not Safe(s.callbacks) then Finish(s)
    elseif s.phase~='closing' and s.phase~='closed_reveal' then
        s.phase,s.phaseTime,s.pointer='closing',0,nil
        TouchInput.Clear()
    end
    return true
end
function M.IsOpen() return session~=nil end
function M.HudHidden()
    local s=session
    return s~=nil and (s.phase~='opening' or s.phaseTime>=FADE*.6) and s.phase~='closed_reveal'
end
function M.ForceClose() return M.Close(true) end
function M.PreviewMode()
    local s=session
    if s and (s.phase=='open' or s.phase=='reveal') then return '3d' end
end
return M
