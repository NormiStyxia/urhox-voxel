-- Pure Lua mocks only. Never loads a native engine or starts a window.
local noop=function() end
local vmt={}; vmt.__index=vmt
Vector3=setmetatable({}, {__call=function(_,x,y,z) return setmetatable({x=x,y=y,z=z},vmt) end})
function vmt.__add(a,b) return Vector3(a.x+b.x,a.y+b.y,a.z+b.z) end
function vmt.__sub(a,b) return Vector3(a.x-b.x,a.y-b.y,a.z-b.z) end
function vmt.__mul(a,b) return Vector3(a.x*b,a.y*b,a.z*b) end
function vmt:Length() return math.sqrt(self.x^2+self.y^2+self.z^2) end
function vmt:Lerp(b,k) return self+(b-self)*k end
Vector3.ZERO=Vector3(0,0,0); Vector3.UP=Vector3(0,1,0)
Quaternion=function() return setmetatable({}, {__mul=function(_,v) return v end}) end
Ray=function(origin,direction) return {origin=origin,direction=direction} end
local teleports,now,created,painted=0,0,0,0
local root={AddChild=function(self,child) self.child=child end}
local panel={Extend=function() return setmetatable({}, {__call=function(_,props)
    props.SetVisible=function(self,v) self.visible=v end
    return props
end}) end}
local UI={Panel=panel,GetRoot=function() return root end,GetScale=function() return 1.5 end,
    GetSafeAreaInsets=function() return {left=20,right=10,top=0,bottom=4} end}
package.loaded['urhox-libs/UI']=UI
package.loaded['urhox-libs/UI/Core/ImageCache']={GetContext=function() return 'vg' end}
graphics={GetDPR=function() return 2 end,GetWidth=function() return 1688 end,GetHeight=function() return 780 end}
GetTime=function() return {GetElapsedTime=function() return now end} end
local resourcesReady=false
local handles={}
local paintedPaths,paintSizes,gradientCalls,currentAngle,ringAngleMax={},{},0,0,0
nvgCreateImage=function(_,path,flags)
    assert(flags==0,'rewind art must use linear filtering')
    created=created+1; handles[created]=path; return created
end
nvgImageSize=function() return resourcesReady and 1024 or 0,resourcesReady and 1024 or 0 end
nvgDeleteImage=function(_,id) handles[id]=nil end
nvgImagePattern=function(_,x,y,w,h,angle,id,alpha)
    assert(resourcesReady and handles[id], 'invalid/zero-size image reached paint')
    painted=painted+1
    paintedPaths[handles[id]]=(paintedPaths[handles[id]] or 0)+1
    paintSizes[handles[id]]=w
    if handles[id]=='ui/rewind/rewind_ring.png' then ringAngleMax=math.max(ringAngleMax,math.abs(currentAngle)) end
end
for _,name in ipairs({'nvgSave','nvgRestore','nvgTranslate','nvgRotate','nvgBeginPath','nvgRect',
    'nvgFillPaint','nvgFill','nvgMoveTo','nvgLineTo','nvgCircle','nvgStrokeColor','nvgStrokeWidth',
    'nvgStroke','nvgClosePath','nvgFillColor','nvgResetTransform','nvgResetScissor','nvgScale',
    'nvgGlobalAlpha','nvgShapeAntiAlias','nvgRadialGradient'}) do _G[name]=noop end
nvgRGBA=function(r,g,b,a) assert(a>=0 and a<=255); return {r,g,b,a} end
nvgRadialGradient=function() gradientCalls=gradientCalls+1 end
nvgRotate=function(_,angle) currentAngle=angle end
local debugEvents={}
local logger={enabled=false,Log=function(tag,fmt,...)
    assert(tag=='VoidRewind'); debugEvents[#debugEvents+1]=string.format(fmt,...)
end}
local settings={tier='high'}
function settings.RegisterQuality(name,fn)
    assert(name=='voidRewind'); settings.callback=fn; fn({quality=settings.tier})
end
package.loaded['ruins.DebugLog']=logger
package.loaded['ruins.GameSettings']=settings
local R=require('ruins.VoidRewind')
local T={RING_Y=6,ISLAND={fallY=-5,hardFallY=-24},
    HasGround=function(x,z) return z< -50 end, IsSafeGround=function(x,y,z) return z< -50 and y>5 end}
package.loaded['ruins.RuinsTerrain']=T
package.loaded['urhox-libs.Camera.ThirdPersonCamera']={}
package.loaded['game.BlockCharacter']={SLENDER={widen=Vector3(1,1,1)},
    CreateVoxel=function() return {bones={arm_right={CreateChild=function() return {} end}},Update=noop} end}
package.loaded['game.NomiVoxelData']={unit=.05}
package.loaded['ruins.TimeObject']={}
local cn={}
ThirdPersonCamera={Create=function() return {SetMode=noop,GetNode=function() return cn end,
    Update=function(_,dt,target) cn.position=target.position end} end}
local scene={CreateChild=function()
    local node={}
    function node:CreateComponent()
        local cc={onGround=false,actual=Vector3(0,-4,0)}
        function cc:SetLinearVelocity(v) self.actual=v end
        function cc:GetLinearVelocity() return self.actual end
        function cc:Teleport(v) node.worldPosition=v; teleports=teleports+1 end
        return cc
    end
    return node
end}
local actor=require('ruins.NomiController').New(scene,{RaycastSingle=function() return {hit=false} end},Vector3(0,6.1,-64),0)
local M={ride={mode='free',pos=Vector3.ZERO},stream={Stop=noop}}
local caster={charging=true,charge=1,Say=noop}
local drag={buttons=7}
local touch={Cancel=noop,Sync=noop}
local combat={Exit=noop}
local held={}
for _,key in ipairs({'W','A','S','D','SHIFT','SPACE','1','2','3','E','Q','F','T','TAB','F10'}) do _G['KEY_'..key]=key end
MOUSEB_LEFT='left'; MOUSEB_RIGHT='right'; MOUSEB_MIDDLE='middle'
input={GetMouseButtonDown=function(_,key) return held[key] or false end}
local factory=assert(load('return function(nomi_,VoidRewind,Terrain,TouchControls,caster_,drag,M,CombatState,Down) local SettingsMenu={IsOpen=function() return false end}; local voidInputBlocked=false '
    ..productionHooks..' return function() return voidInputBlocked end, function() '..productionGate..' end end'))()
local blocked,release=factory(actor,R,T,touch,caster,drag,M,combat,function(key) return held[key] or false end)
local function tick(dt,draw)
    now=now+dt; R.Update(dt); if draw~=false then R.Draw('vg') end; release()
end
local function finish()
    for i=1,300 do if not R.IsActive() then break end; tick(1/60) end
    assert(not R.IsActive() and not actor.voidReturning)
end
local function fall(y,vertical,onGround)
    actor.node.worldPosition=Vector3(0,y,-44)
    actor.cc.actual=Vector3(0,vertical or -4,0); actor.cc.onGround=onGround or false
    return actor:UpdateSafety(1/60)
end
assert(not fall(5.5)); assert(not fall(5,2)); assert(not fall(5,-2,true))
assert(not R.IsActive() and teleports==0)
print('PASS early detection: lip clearance, rising jump and supported bridge excluded')
assert(fall(5)); assert(R.IsActive() and blocked() and actor.voidReturning)
assert(not caster.charging and caster.charge==0 and drag.buttons==0 and teleports==0)
for i=1,24 do tick(1/60) end
assert(R.BlackAlpha()>.1 and R.BlackAlpha()<.9 and teleports==0)
assert(R.Start(function() error('reentrant callback replaced original') end,noop))
assert(actor:UpdateSafety(.5) and teleports==0)
for i=1,100 do tick(1/60,false) end
assert(R.GetState()=='black' and R.BlackAlpha()==1 and teleports==0)
print('PASS blackout gate: gradual fade, no teleport before opaque render, reentry ignored')
R.Draw('vg'); tick(1/60)
local previous=R.HandAngle(3)
for i=1,14 do
    tick(1/60)
    local angle=R.HandAngle(3); assert(angle<previous); previous=angle
    assert(math.abs(angle/R.HandAngle(.25)-12)<1e-8)
end
assert(teleports==1 and actor:Position().z==-64 and actor.cc.actual:Length()==0)
assert(actor.camTarget.position.z==-64 and cn.position.z==-64 and M.ride.pos.z==-64)
assert(created==5 and painted==0,'pending images must be throttled and never painted')
held.W=true; finish()
assert(blocked() and teleports==1 and root.child.visible==false)
held.W=false; release(); assert(not blocked())
assert(math.abs(R.HandAngle(3))<1e-8 and math.abs(R.HandAngle(.25))<1e-8)
print('PASS one teleport under black, safe point/camera/velocity cleanup, XII stop and release-to-resume')
local beforeCreated=created
R.Draw('vg'); R.Update(1)
assert(created==beforeCreated,'idle must perform no resource work')
resourcesReady=true
assert(fall(3,-4,true)); finish()
assert(teleports==2 and painted>0,'late textures must replace vector fallback')
assert(not blocked())
print('PASS consecutive falls, stranded low fragment, late bitmap switch and idle no resource work')
actor.safePos=Vector3(0,6,-54)
local started=now
assert(fall(-6)); finish(); assert(actor:Position().z==-54 and teleports==3)
assert(now-started>=2.2 and now-started<=3.0,'normal transition must fit timing budget')
print(string.format('PASS normal transition duration %.3fs',now-started))
actor.safePos=Vector3(0,6,-44)
assert(fall(-25)); finish(); assert(actor:Position().z==-64 and teleports==4)
print('PASS nearest safe point retained and invalid checkpoint falls back to spawn')
R.CONFIG.enabled=false
assert(not fall(5) and not R.IsActive())
assert(fall(-6) and teleports==5 and not R.IsActive())
release(); assert(not blocked())
R.CONFIG.enabled=true
local previousRoot=root; root=nil
assert(fall(-6) and teleports==6 and not R.IsActive())
root=previousRoot
print('PASS disabled/no-UI immediate return fallback')
-- Exercise the real scene movement guard without the rest of the scene.
local movementCalls=0
local guard=assert(load('return function(nomi_,M,TouchControls,pointer,TouchInput) local Down=function() return false end; local Clamp=function(v) return v end; local animPreview_={index=0}; '..productionSceneUpdate..' end'))()
guard({Move=function() movementCalls=movementCalls+1 end},M,{IsBlocked=function() return true end},{},{MoveAxis=function() return 0,0 end})
local event={TimeStep={GetFloat=function() return .016 end}}
M.mounted=true; Ruins_HandleSceneUpdate(nil,event)
M.mounted=false; M.ride.mode='mounting'; Ruins_HandleSceneUpdate(nil,event)
M.ride.mode='dismounting'; Ruins_HandleSceneUpdate(nil,event)
assert(movementCalls==0)
M.ride.mode='free'; Ruins_HandleSceneUpdate(nil,event); assert(movementCalls==1)
print('PASS mounted/mounting/dismounting bypass the foot safety path')
assert(#debugEvents==0,'disabled logger must never be called')
print('PASS disabled diagnostics: no calls, formatting or log buffers in VoidRewind')
local durations={}
for _,tier in ipairs({'high','medium','low'}) do
    settings.tier=tier; settings.callback({quality=tier})
    paintedPaths={}; paintSizes={}; gradientCalls=0; ringAngleMax=0
    local at=now
    assert(fall(5) and R.GetQuality()==tier)
    finish(); durations[tier]=now-at
    assert((paintedPaths['ui/rewind/rewind_dial.png'] or 0)>0)
    assert((paintedPaths['ui/rewind/rewind_hand_hour.png'] or 0)>0)
    assert((paintedPaths['ui/rewind/rewind_hand_minute.png'] or 0)>0)
    assert((gradientCalls>0)==(tier=='high'))
    assert(((paintedPaths['ui/rewind/rewind_spark.png'] or 0)>0)==(tier=='high'))
    assert(((paintedPaths['ui/rewind/rewind_ring.png'] or 0)>0)==(tier~='low'))
    assert((ringAngleMax>0)==(tier=='high'))
    local size=paintSizes['ui/rewind/rewind_dial.png']
    assert(size==paintSizes['ui/rewind/rewind_hand_hour.png'] and size==paintSizes['ui/rewind/rewind_hand_minute.png'])
    if tier~='low' then assert(math.abs(size/paintSizes['ui/rewind/rewind_ring.png']-.64)<1e-8) end
end
assert(durations.high>durations.medium and durations.medium>durations.low)
print(string.format('PASS quality budgets high=%.3fs medium=%.3fs low=%.3fs; dust/ring/vignette gates',durations.high,durations.medium,durations.low))
settings.tier='high'; settings.callback({quality='high'})
logger.enabled=true
assert(fall(5)); R.Start(noop,noop)
settings.tier='low'; settings.callback({quality='low'})
assert(R.GetQuality()=='high','quality change must not jump the active transition')
finish()
assert(#debugEvents==5,'expected start/reentry/black/teleport/complete logs exactly once')
assert(R.GetQuality()=='low')
logger.enabled=false
assert(fall(5)); finish(); assert(#debugEvents==5)
print('PASS enabled milestone logs only, disabled zero calls, active quality snapshot and next-fall update')
R.Stop(); assert(not R.IsActive())
settings.callback=nil
R.Attach(root); assert(settings.callback,'quality hook must reconnect after settings lifecycle reset')
R.Stop()
package.loaded['ruins.VoidRewind']=nil
package.loaded['ruins.DebugLog']=nil; package.loaded['ruins.GameSettings']=nil
package.preload['ruins.DebugLog']=function() error('optional logger absent') end
package.preload['ruins.GameSettings']=function() error('optional settings absent') end
local fallback=require('ruins.VoidRewind')
assert(fallback.Start(noop,noop) and fallback.GetQuality()=='high')
for i=1,240 do now=now+1/60; fallback.Update(1/60); fallback.Draw('vg') end
assert(not fallback.IsActive()); fallback.Stop()
print('PASS optional settings/logger absent defaults to high without error')
print('PASS lifecycle release; all offline assertions passed')
