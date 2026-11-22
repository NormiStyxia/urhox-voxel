-- Production modal, rasterizer and region handlers with offline engine ports.
package.path='scripts/?.lua;'..package.path
local noop=function()end
local now=0
GetTime=function()return {GetElapsedTime=function()return now end} end
Vector3=function(x,y,z)return {x=x,y=y,z=z} end
NVG_ALIGN_CENTER,NVG_ALIGN_RIGHT=1,2
nvgTranslate,nvgScale,nvgIntersectScissor=nvgTranslate or noop,nvgScale or noop,nvgIntersectScissor or noop
nvgRGBA,nvgBeginPath,nvgRect,nvgFillColor,nvgFill=nvgRGBA or noop,nvgBeginPath or noop,nvgRect or noop,nvgFillColor or noop,nvgFill or noop
local draw=setmetatable(DrawPort or {},{__index=function()return noop end})
draw.colors={deep={18,23,31}}
draw.Metrics=function()return 896,504,{left=0,right=0,top=0,bottom=0} end
draw.PixelToHUD=function()return 1 end
package.loaded['ui.PixelDraw']=draw
package.loaded['urhox-libs/UI']={Panel={Extend=function()return setmetatable({},{__call=function(t)return setmetatable({},{__index=t}) end})end}}
local root={AddChild=function(self,c)self.layer=c end,RemoveChild=function(self)self.layer=nil end}
local model=require('ui.WorldMapModel');local new=model.New;local view
model.New=function()view=new();return view end
local map=require('ui.WorldMap')
local home=require('ruins.HomeIsland');local terrain=require('ruins.RuinsTerrain')
local f=assert(io.open('scripts/ruins/RuinsScene.lua'));local source=f:read('*a');f:close()
local spawn=Vector3(0,6.10,-64)
local ctl={cc={onGround=true},safePos=spawn,TeleportToSafeGround=function(self,p)assert(terrain.IsSafeGround(p.x,p.y,p.z));self.safePos=p;return true end}
local builds,clears,pin,enemy=0,0,{},false
local homePort=setmetatable({BeginBuild=function()builds=builds+1;return {Step=function()return true end} end},{__index=home})
local M={region='ruins',SPAWN=spawn,ride={mode='free',wander={}},dragonAwake=true,ctrl={loco={},input={},Teleport=function(_,pos)pin=pos end}}
local env=setmetatable({M=M,HomeIsland=homePort,Terrain=terrain,WorldMap=map,PixelDraw=draw,
   HUD={root=root},TouchControls={Cancel=noop},pointer={SetBlocked=noop,Resume=noop,Release=noop},drag={},
   nomi_=ctl,CombatHasAggro=function()return enemy end,CombatState={Engaged=function()return false end},
   RefreshObjective=noop, combatArrows_={Clear=function()clears=clears+1 end},animPreview_={index=0},combatMoves_={},
   ForgePanel={IsOpen=function()return false end},SettingsMenu={IsBlocked=function()return false end},WeaponWheel={IsBlocked=function()return false end},TouchInput={IsEnabled=function()return false end}},{__index=_G})
KEY_M,KEY_RETURN,KEY_RIGHT,KEY_LEFT,KEY_ESCAPE=77,13,39,37,27
MOUSEB_LEFT,MOUSEB_RIGHT=1,4
local held,restored=false,0
env.pointer.SetBlocked=function(_,b) held=b end
env.pointer.Resume=function() restored=restored+1 end
local fn=assert(source:match('(local function TravelToRegion.-)local function AttachTouchControls'))
local handlers={fn,'step=AdvanceHomeTravel'}
for _,name in ipairs({'KeyDown','MouseDown','MouseMove','MouseUp'}) do
    handlers[#handlers+1]=assert(source:match('(function Ruins_Handle'..name..'.-\nend)'))
end
assert(load(table.concat(handlers,'\n'),'map entry points','t',env))()
local function press(k) env.Ruins_HandleKeyDown(nil,{GetInt=function()return k end,GetBool=function()return false end}) end
local function mouse(name,button,x,y)
    env['Ruins_HandleMouse'..name](nil,{GetInt=function(_,key)return ({X=x,Y=y,Button=button})[key] end})
end
local function shot(s)
    root.layer:Render(1)
    if Screenshot then Screenshot(s) end
end
-- Observe the same display transform used to draw the model. No duplicate camera math.
local tx,ty,sc
local tr,scl=nvgTranslate,nvgScale
local function getDisplay()
    local calls={};nvgTranslate=function(vg,x,y) calls[#calls+1]={x,y};tr(vg,x,y) end
    nvgScale=function(vg,x,y)
        local c=calls[#calls];if c then c[3]=x end;scl(vg,x,y)
    end
    root.layer:Render(1);nvgTranslate,nvgScale=tr,scl
    local chart=calls[1];local mesh=calls[#calls-1]
    tx,ty,sc=chart[1]+mesh[1]*chart[3],chart[2]+mesh[2]*chart[3],mesh[3]*chart[3]
end
local function location(id)
    getDisplay();local x,y=model.Anchor(view,id)
    local px,py=math.floor(x),math.floor(y)
    assert(model.Pick(view,px,py)==id,'landing target must be selectable: '..id)
    return tx+(px+.5)*sc,ty+(py+.5)*sc
end
local function click(x,y)
    mouse('Down',1,x,y);mouse('Up',1,x,y)
end
press(KEY_M);assert(map.IsOpen() and held);now=now+.13;shot('00-unrolling');click(629,207)
assert(builds==0);now=now+.16;shot('01-open')
local x,y=location('home');mouse('Down',1,x,y);assert(builds==0);mouse('Move',1,x+20,y);mouse('Move',1,x,y);mouse('Up',1,x,y);assert(builds==0 and map.IsOpen())
click(42,72);assert(builds==0 and map.IsOpen());print('PASS blank tap and dragged release never initiate travel')
local old=view.yaw;mouse('Down',1,160,180);mouse('Move',1,510,180);mouse('Up',1,510,180)
assert(math.abs(view.yaw-old)>2.9 and builds==0);shot('02-back');assert(model.Anchor(view,'home')<model.Anchor(view,'ruins'))
print('PASS mouse orbit exposes back; island order reverses')
local oldX,oldY=view.panX,view.panY
mouse('Down',4,420,180);mouse('Move',4,484,204);mouse('Up',4,484,204);assert(view.panX>oldX and view.panY>oldY and builds==0);shot('03-pan')
print('PASS right-button pan without travel')
x,y=location('home');enemy=true;click(x,y);assert(map.IsOpen() and builds==0);shot('04-gate');enemy=false
mouse('Down',1,x,y);assert(builds==0);mouse('Up',1,x,y);assert(map.IsOpen() and builds==1);env.step()
assert(M.region=='home' and not map.IsOpen() and not held and pin.x==home.x+12);print('PASS rotated model click upon release, combat gate and asynchronous home arrival')
press(KEY_M);now=now+.3;assert(held);shot('05-home');assert(home.NearForge(Vector3(home.x+1,home.base,home.z+6)) and not home.NearForge(ctl.safePos))
-- Exercise the actual finger capture and release methods used by the raw Touch handlers.
GetPlatform=function()return 'Web' end
local touch=require('ui.TouchControls');package.loaded['ruins.GameSettings'].TouchDetected=noop
local function touchEvent(name,id,x,y)
    if name=='Begin' then touch.BeginTouch(id,x,y) elseif name=='Move' then touch.MoveTouch(id,x,y) else touch.EndTouch(id,x,y) end
end
local before=view.yaw;touchEvent('Begin',7,410,200);touchEvent('Move',7,450,210);touchEvent('End',7,450,210);assert(view.yaw~=before and M.region=='home')
local yaw=view.yaw;oldX,oldY=view.panX,view.panY
touchEvent('Begin',1,250,170);touchEvent('Begin',2,350,170);touchEvent('Move',1,280,182);touchEvent('Move',2,380,182);touchEvent('End',2,380,182);touchEvent('End',1,280,182)
assert(view.yaw==yaw and view.panX>oldX and view.panY>oldY and M.region=='home');shot('06-touch')
x,y=location('ruins');touchEvent('Begin',2,x,y);assert(M.region=='home');touchEvent('End',2,x,y)
assert(M.region=='ruins' and not map.IsOpen() and ctl.safePos==spawn and clears==2 and not held)
print('PASS one-finger orbit, two-finger pan, release-on-model return and correct anchor')
press(KEY_M);now=now+.3;press(KEY_RIGHT);press(KEY_RETURN);assert(builds==1 and M.region=='home' and not map.IsOpen());press(KEY_M);now=now+.3;press(KEY_ESCAPE)
now=now+.08;assert(map.StepClosing() and map.IsOpen());shot('07-rolling-up');now=now+.09;assert(map.StepClosing());assert(not map.IsOpen() and not held and restored==4)
local flight=require('dragon.DragonFlight')
local f0=flight.EdgeSpeed({pos=Vector3(12,0,3),travelYaw=90})
local f1=flight.EdgeSpeed({pos=Vector3(home.x+12,0,3),arenaX=home.x,travelYaw=90})
assert(f0==f1 and f1>18);print('PASS keyboard travel, Escape, reopen, pointer restoration, build reuse, dragon pad and forge radius')
