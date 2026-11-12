-- Runtime-only acceptance driver; loaded explicitly with maker_validate.test.
-- Exercises actual TouchBegin/Move/End handlers in the existing scene.
local V=_G['V']
local Input=require('ui.TouchInput')
local Controls=require('ui.TouchControls')
local Draw=require('ui.PixelDraw')
local HUD=require('ruins.RuinsHUD')
---@class TouchAcceptanceHost
---@field caster TimeCaster
---@field nomiCtl NomiController
---@type TouchAcceptanceHost
local host
local oldYaw
local function Event(name,id,x,y)
    local d=VariantMap()
    d['TouchID']=Variant(id)
    d['X']=Variant(math.floor(x*graphics:GetDPR()))
    d['Y']=Variant(math.floor(y*graphics:GetDPR()))
    SendEvent(name,d)
end
V.atFrame(5,function()
    host=_G['RUINS'] --[[@as TouchAcceptanceHost]]
    if not Input.IsEnabled() then Input.Toggle() end
    Controls.Sync()
    V.assert(Input.IsEnabled(),'F9 touch mode is enabled')
    V.assert(input.mouseMode~=MM_RELATIVE,'touch bypasses pointer lock')
    local w,h,s=Draw.Metrics()
    Event('TouchBegin',101,s.left+100,h-s.bottom-100)
    Event('TouchMove',101,s.left+100,h-s.bottom-140)
    Event('TouchBegin',102,w-s.right-68,h-s.bottom-68)
    Event('TouchBegin',103,w*.56,h*.4)
    oldYaw=host.nomiCtl.camYaw
    Event('TouchMove',103,w*.56+20,h*.4+10)
    V.assert(Input.Down('shatter') and Input.Down('sprint'),'three fingers preserve charge and movement')
end)
V.atFrame(12,function()
    V.assert(host.caster.charging,'real spell controller charges on hold')
    V.assert(host.nomiCtl.camYaw>oldYaw,'real camera receives look delta')
    local w,h,s=Draw.Metrics()
    Event('TouchEnd',102,w-s.right-68,h-s.bottom-68)
    Event('TouchEnd',101,100,h-140)
    Event('TouchEnd',103,w*.56+20,h*.4+10)
end)
V.atFrame(16,function()
    V.assert(not host.caster.charging,'release clears real charge')
    V.assert(host.caster.lastCast=='shatter','release casts shatter once')
    V.assert(Input.MoveAxis()==0,'release clears movement')
    Controls.Cancel()
    host.caster.message='';host.caster.messageT=0
    HUD.SetMessage('')

end)

V.atFrame(132,function() V.finish() end)
