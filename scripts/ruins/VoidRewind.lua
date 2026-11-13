-- Void rewind transition. UI owns NanoVGRender and the frame, as for RuinsHUD.
-- No independent context/frame, no pixel HUD scaling, no world/time mutations.
local UI = require('urhox-libs/UI')
local debugOK, DebugLog = pcall(require, 'ruins.DebugLog')
if not debugOK then DebugLog=nil end
local settingsOK, GameSettings = pcall(require, 'ruins.GameSettings')
if not settingsOK then GameSettings=nil end
local M = {}
M.CONFIG = {
    enabled = true,
    fallDepth = .85, -- metres below the island lip, while descending
    fade = .95, rewind = 1.15, hold = .18, reveal = .45,
    teleportAt = .20, -- seconds into rewind, after a fully black render
    minuteTurns = 3, hourTurns = .25, -- 12:1 speed, hour starts at III and stops at XII
    ringSizeRatio = .92, dialToRingRatio = .64,
    dustCount = 10, retrySeconds = .5, ringSpeed = math.rad(6),
}
-- Snapshot a profile per fall: automatic quality changes never jump an active phase.
local QUALITY = {
    high={name='high',durationScale=1,dust=true,ring=true,rotateRing=true,vignette=true},
    medium={name='medium',durationScale=.84,dust=false,ring=true,rotateRing=false,vignette=false},
    low={name='low',durationScale=.72,dust=false,ring=false,rotateRing=false,vignette=false},
}
local quality,activeQuality=QUALITY.high,QUALITY.high
local function ApplyQuality(profile)
    quality=QUALITY[profile.quality] or QUALITY.high
end
local function RegisterQuality()
    if GameSettings and GameSettings.RegisterQuality then GameSettings.RegisterQuality('voidRewind',ApplyQuality) end
end
local function Duration(seconds) return seconds*activeQuality.durationScale end
local STATE = { IDLE='idle', FADE='fade', BLACK='black', REWIND='rewind', HOLD='hold', REVEAL='reveal' }
local state, elapsed, clock = STATE.IDLE, 0, 0
local blackRendered, returned = false, false
---@type fun()|nil
local onBlack
---@type fun()|nil
local onFinish
---@type Widget|nil
local layer
---@type Widget|nil
local attachedRoot
---@class VoidRewindImage
---@field handle integer
---@field retry number
---@field ready boolean
---@class VoidRewindContext
---@field images VoidRewindImage[]
---@type table<NVGContextWrapper, VoidRewindContext>
local contexts = setmetatable({}, {__mode='k'})
-- Literal paths also keep the build asset reference chain visible.
local IMAGE_PATHS = {
    'ui/rewind/rewind_dial.png', 'ui/rewind/rewind_ring.png',
    'ui/rewind/rewind_hand_hour.png', 'ui/rewind/rewind_hand_minute.png',
    'ui/rewind/rewind_spark.png',
}
local IMAGE = { DIAL=1, RING=2, HOUR=3, MINUTE=4, SPARK=5 }
local ROMAN = {'XII','I','II','III','IV','V','VI','VII','VIII','IX','X','XI'}
local TAU = math.pi * 2
local Layer = UI.Panel:Extend('RuinsVoidRewind')
local function Clamp(v) return math.max(0, math.min(1, v)) end
local function Smooth(v) v=Clamp(v); return v*v*(3-2*v) end
local function Gold(alpha) return nvgRGBA(213,183,116,math.floor(255*Clamp(alpha)+.5)) end
local function Black(alpha) return nvgRGBA(0,0,0,math.floor(255*Clamp(alpha)+.5)) end

function M.IsActive() return state ~= STATE.IDLE end
function M.GetState() return state end
function M.GetQuality() return M.IsActive() and activeQuality.name or quality.name end
function M.BlackAlpha()
    if state==STATE.IDLE then return 0 end
    if state==STATE.FADE then return Smooth(elapsed/Duration(M.CONFIG.fade)) end
    if state==STATE.REVEAL then return 1-Smooth(elapsed/Duration(M.CONFIG.reveal)) end
    return 1
end
function M.HandAngle(turns)
    local p = state==STATE.REWIND and Clamp(elapsed/Duration(M.CONFIG.rewind)) or 1
    return TAU*turns*(1-p)^3 -- decreasing angle = counter-clockwise; every hand stops at XII
end

---@param root Widget
function M.Attach(root)
    RegisterQuality() -- GameSettings.Stop clears callbacks; HUD rebuild/restart reattaches them.
    if root==attachedRoot and layer then return end
    attachedRoot=root
    layer=Layer{position='fixed',left=0,top=0,width='100%',height='100%',
        pointerEvents='auto',visible=M.IsActive()}
    root:AddChild(layer) -- fixed pass covers HUD, touch controls and later settings/performance panels
end

---@param blackout fun()
---@param finished fun()
---@return boolean accepted
function M.Start(blackout, finished)
    if not M.CONFIG.enabled then return false end
    if M.IsActive() then
        if DebugLog and DebugLog.enabled then DebugLog.Log('VoidRewind','reentry ignored phase=%s',state) end
        return true -- preserve original callbacks on re-entry
    end
    local root=UI.GetRoot()
    if not root then return false end -- no visible UI: let the original immediate safety path run
    M.Attach(root)
    activeQuality=quality
    onBlack,onFinish=blackout,finished
    elapsed,clock,blackRendered,returned=0,0,false,false
    state=STATE.FADE
    layer:SetVisible(true)
    if DebugLog and DebugLog.enabled then DebugLog.Log('VoidRewind','start quality=%s',activeQuality.name) end
    return true
end

function M.Update(dt)
    if state==STATE.IDLE then return end
    -- Tab suspension must not skip the black render gate or reveal an unsettled camera.
    local step=math.max(0,math.min(dt,.1))
    clock=clock+step
    elapsed=elapsed+step
    if state==STATE.FADE then
        if elapsed>=Duration(M.CONFIG.fade) then state,elapsed=STATE.BLACK,0 end
    elseif state==STATE.BLACK then
        if blackRendered then state,elapsed=STATE.REWIND,0 end
    elseif state==STATE.REWIND then
        if not returned and elapsed>=Duration(M.CONFIG.teleportAt) then
            returned=true -- before invoking external code: at most once
            if onBlack then onBlack() end
            if DebugLog and DebugLog.enabled then DebugLog.Log('VoidRewind','teleport executed at %.3fs',clock) end
        end
        if returned and elapsed>=Duration(M.CONFIG.rewind) then state,elapsed=STATE.HOLD,0 end
    elseif state==STATE.HOLD then
        if elapsed>=Duration(M.CONFIG.hold) then state,elapsed=STATE.REVEAL,0 end
    elseif state==STATE.REVEAL and elapsed>=Duration(M.CONFIG.reveal) then
        state,elapsed=STATE.IDLE,0
        if layer then layer:SetVisible(false) end
        local finished=onFinish
        onBlack,onFinish=nil,nil
        if finished then finished() end
        if DebugLog and DebugLog.enabled then DebugLog.Log('VoidRewind','complete at %.3fs',clock) end
    end
end

---@param vg NVGContextWrapper
---@param index integer
local function Image(vg,index)
    local c=contexts[vg]
    if not c then
        c={images={}}
        for i=1,#IMAGE_PATHS do c.images[i]={handle=0,retry=0,ready=false} end
        contexts[vg]=c
    end
    local img=c.images[index]
    if img.ready then return img.handle end
    local now=GetTime():GetElapsedTime()
    if now<img.retry then return nil end
    img.retry=now+M.CONFIG.retrySeconds
    if img.handle>0 then
        local w,h=nvgImageSize(vg,img.handle)
        if w and h and w>0 and h>0 then img.ready=true; return img.handle end
        nvgDeleteImage(vg,img.handle); img.handle=0
    end
    img.handle=nvgCreateImage(vg,IMAGE_PATHS[index],0) or 0 -- default linear filtering
    if img.handle>0 then
        local w,h=nvgImageSize(vg,img.handle)
        if w and h and w>0 and h>0 then img.ready=true; return img.handle end
    end
    return nil -- pending/zero-sized handles NEVER become a white quad
end
local function Picture(vg,index,x,y,size,angle,alpha)
    local img=Image(vg,index)
    if not img then return false end
    nvgSave(vg); nvgTranslate(vg,x,y); nvgRotate(vg,angle)
    nvgBeginPath(vg); nvgRect(vg,-size/2,-size/2,size,size)
    nvgFillPaint(vg,nvgImagePattern(vg,-size/2,-size/2,size,size,0,img,alpha)); nvgFill(vg)
    nvgRestore(vg)
    return true
end
local function Line(vg,x1,y1,x2,y2) nvgMoveTo(vg,x1,y1); nvgLineTo(vg,x2,y2) end
local function Ring(vg,r,alpha)
    nvgBeginPath(vg); nvgCircle(vg,0,0,r); nvgStrokeColor(vg,Gold(alpha)); nvgStrokeWidth(vg,.85); nvgStroke(vg)
end
-- Small upright serif Roman numerals built from strokes: no per-frame font creation
-- and no dependency on the pixel HUD font, including while images are downloading.
local function Numeral(vg,text,x,y,height)
    local w=height*.48
    local advance=w*1.35
    local left=x-(#text-1)*advance/2-w/2
    local top=y-height/2
    for i=1,#text do
        local ch=text:sub(i,i)
        local a=left+(i-1)*advance
        if ch=='I' then
            Line(vg,a+w/2,top,a+w/2,top+height)
            Line(vg,a,top,a+w,top); Line(vg,a,top+height,a+w,top+height)
        elseif ch=='V' then
            Line(vg,a,top,a+w/2,top+height); Line(vg,a+w/2,top+height,a+w,top)
        else
            Line(vg,a,top,a+w,top+height); Line(vg,a+w,top,a,top+height)
        end
    end
end
local function Dial(vg,r,alpha)
    Ring(vg,r*.86,alpha*.7); Ring(vg,r*.67,alpha*.45)
    nvgBeginPath(vg)
    for i=1,60 do
        local angle=(i-1)*TAU/60
        local s,c=math.sin(angle),-math.cos(angle)
        local inner=i%5==1 and .9 or .93
        Line(vg,s*r*inner,c*r*inner,s*r*.96,c*r*.96)
    end
    nvgStrokeColor(vg,Gold(alpha*.65)); nvgStrokeWidth(vg,.8); nvgStroke(vg)
    nvgBeginPath(vg)
    for i=1,12 do
        local angle=(i-1)*TAU/12
        Numeral(vg,ROMAN[i],math.sin(angle)*r*.765,-math.cos(angle)*r*.765,r*.105)
    end
    nvgStrokeColor(vg,Gold(alpha)); nvgStrokeWidth(vg,math.max(.8,r*.006)); nvgStroke(vg)
end
local function Hand(vg,r,length,angle,alpha)
    nvgSave(vg); nvgRotate(vg,angle)
    nvgBeginPath(vg); nvgMoveTo(vg,0,-r*length)
    nvgLineTo(vg,r*.018,-r*.16); nvgLineTo(vg,0,r*.10); nvgLineTo(vg,-r*.018,-r*.16); nvgClosePath(vg)
    nvgFillColor(vg,Gold(alpha)); nvgFill(vg)
    nvgRestore(vg)
end

function M.Draw(vg)
    if state==STATE.IDLE then return end
    local dpr=graphics:GetDPR()
    local w,h=graphics:GetWidth()/dpr,graphics:GetHeight()/dpr
    local scale=UI.GetScale()/dpr
    local safe=UI.GetSafeAreaInsets()
    local left,right,top,bottom=safe.left*scale,safe.right*scale,safe.top*scale,safe.bottom*scale
    local cx,cy=(left+w-right)/2,(top+h-bottom)/2
    local short=math.max(1,math.min(w-left-right,h-top-bottom))
    local ringSize=short*M.CONFIG.ringSizeRatio
    local r=ringSize*M.CONFIG.dialToRingRatio/2
    local black=M.BlackAlpha()
    nvgSave(vg); nvgResetTransform(vg); nvgResetScissor(vg)
    nvgScale(vg,1/scale,1/scale); nvgGlobalAlpha(vg,1); nvgShapeAntiAlias(vg,1)
    nvgBeginPath(vg); nvgRect(vg,0,0,w,h); nvgFillColor(vg,Black(black)); nvgFill(vg)
    if state==STATE.BLACK and not blackRendered then
        blackRendered=true
        if DebugLog and DebugLog.enabled then DebugLog.Log('VoidRewind','blackout drawn at %.3fs',clock) end
    end
    if state==STATE.FADE then
        -- The edges darken ahead of the centre, converging to opaque black.
        if activeQuality.vignette then
            nvgBeginPath(vg); nvgRect(vg,0,0,w,h)
            nvgFillPaint(vg,nvgRadialGradient(vg,cx,cy,short*.12,short*.7,Black(0),Black(math.sin(Clamp(elapsed/Duration(M.CONFIG.fade))*math.pi)*.7)))
            nvgFill(vg)
        end
    elseif state~=STATE.BLACK then
        local alpha=state==STATE.REWIND and Smooth(elapsed/Duration(.16)) or 1
        if state==STATE.REVEAL then alpha=1-Smooth(elapsed/Duration(M.CONFIG.reveal*.65)) end
        nvgSave(vg); nvgTranslate(vg,cx,cy)
        local ringAngle=activeQuality.rotateRing and clock*M.CONFIG.ringSpeed or 0
        if activeQuality.ring and not Picture(vg,IMAGE.RING,0,0,ringSize,ringAngle,alpha*.65) then
            local outer=ringSize/2
            Ring(vg,outer*.94,alpha*.55); Ring(vg,outer*.98,alpha*.25)
            nvgSave(vg); nvgRotate(vg,ringAngle); nvgBeginPath(vg)
            for i=1,8 do
                local a=(i-1)*TAU/8
                Line(vg,math.sin(a)*outer*.9,-math.cos(a)*outer*.9,math.sin(a)*outer,-math.cos(a)*outer)
            end
            nvgStrokeColor(vg,Gold(alpha*.65)); nvgStrokeWidth(vg,1); nvgStroke(vg); nvgRestore(vg)
        end
        if not Picture(vg,IMAGE.DIAL,0,0,r*2,0,alpha) then Dial(vg,r,alpha) end
        local hour,minute=M.HandAngle(M.CONFIG.hourTurns),M.HandAngle(M.CONFIG.minuteTurns)
        if not Picture(vg,IMAGE.HOUR,0,0,r*2,hour,alpha) then Hand(vg,r,.48,hour,alpha) end
        if not Picture(vg,IMAGE.MINUTE,0,0,r*2,minute,alpha) then Hand(vg,r,.65,minute,alpha) end
        nvgBeginPath(vg); nvgCircle(vg,0,0,r*.025); nvgFillColor(vg,Gold(alpha)); nvgFill(vg)
        for i=1,(activeQuality.dust and M.CONFIG.dustCount or 0) do
            local life=(i*.61803398875+clock*.07)%1
            local x=math.sin(i*2.39996)*r*1.55
            local y=(.5-life)*r*3.1
            local a=alpha*math.sin(life*math.pi)*.45
            if not Picture(vg,IMAGE.SPARK,x,y,r*.035,0,a) then
                nvgBeginPath(vg); nvgCircle(vg,x,y,math.max(.65,r*.005)); nvgFillColor(vg,Gold(a)); nvgFill(vg)
            end
        end
        nvgRestore(vg)
    end
    nvgRestore(vg)
end
function Layer:Render(vg) M.Draw(vg) end

function M.Stop()
    state,elapsed=STATE.IDLE,0
    onBlack,onFinish=nil,nil
    if layer then layer:SetVisible(false) end
    layer,attachedRoot=nil,nil
    local live=require('urhox-libs/UI/Core/ImageCache').GetContext()
    for vg,c in pairs(contexts) do
        if vg==live then
            for _,img in ipairs(c.images) do if img.handle>0 then nvgDeleteImage(vg,img.handle) end end
        end
    end
    contexts=setmetatable({}, {__mode='k'})
end
return M
