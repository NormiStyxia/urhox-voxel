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
local builds,clears,pin,enemy,gateChecks=0,0,{},false,0
local homePort=setmetatable({BeginBuild=function()builds=builds+1;return {Step=function()return true end} end},{__index=home})
local M={region='ruins',SPAWN=spawn,ride={mode='free',wander={}},dragonAwake=true,ctrl={loco={},input={},Teleport=function(_,pos)pin=pos end}}
local env=setmetatable({M=M,HomeIsland=homePort,Terrain=terrain,WorldMap=map,PixelDraw=draw,
   HUD={root=root},TouchControls={Cancel=noop},pointer={SetBlocked=noop,Resume=noop,Release=noop},drag={},
   nomi_=ctl,CombatHasAggro=function()gateChecks=gateChecks+1;return enemy end,CombatState={Engaged=function()return false end},
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
-- Sample transforms at emitted geometry and at the named avatar image. The
-- paper can add or reorder its own transforms without affecting the measurement.
local tx,ty,sc,spans
local function getDisplay()
    local m={x=0,y=0,sx=1,sy=1};local stack={};local mesh,arrow,avatar
    local save,restore,rect,image=draw.Save,draw.Restore,draw.Rect,draw.Image
    local translate,scale,meshRect=nvgTranslate,nvgScale,nvgRect
    spans={}
    draw.Save=function(vg) stack[#stack+1]=m;save(vg) end
    draw.Restore=function(vg) m=assert(table.remove(stack));restore(vg) end
    nvgTranslate=function(vg,x,y)
        m={x=m.x+x*m.sx,y=m.y+y*m.sy,sx=m.sx,sy=m.sy};translate(vg,x,y)
    end
    nvgScale=function(vg,x,y)
        m={x=m.x,y=m.y,sx=m.sx*x,sy=m.sy*y};scale(vg,x,y)
    end
    nvgRect=function(vg,x,y,w,h)
        if mesh then assert(mesh.x==m.x and mesh.y==m.y and mesh.sx==m.sx and mesh.sy==m.sy) else mesh=m end
        local left,top=m.x+x*m.sx,m.y+y*m.sy
        spans[#spans+1]={left,top,left+w*m.sx,top+h*m.sy}
        meshRect(vg,x,y,w,h)
    end
    draw.Rect=function(vg,x,y,w,h,col,...)
        if w==1 and h==1 and col[1]==82 and col[2]==49 then arrow={x=m.x+x*m.sx,y=m.y+y*m.sy,k=m.sx} end
        rect(vg,x,y,w,h,col,...)
    end
    draw.Image=function(vg,name,x,y,...)
        if name=='map_nomi' then avatar={cx=m.x+(x+48)*m.sx,bottom=m.y+(y+96)*m.sy,sx=m.sx,sy=m.sy} end
        image(vg,name,x,y,...)
    end
    root.layer:Render(1)
    nvgTranslate,nvgScale,nvgRect=translate,scale,meshRect
    draw.Save,draw.Restore,draw.Rect,draw.Image=save,restore,rect,image
    assert(#stack==0 and mesh and arrow and avatar and #spans>10)
    tx,ty,sc=mesh.x,mesh.y,mesh.sx;assert(sc>0 and sc==mesh.sy)
    local ax,ay=model.Anchor(view,M.region)
    assert(math.abs(arrow.x-tx-ax*sc)<=arrow.k*.51 and math.abs(arrow.y-ty-ay*sc)<=arrow.k*.51,'arrow misses displayed landing')
    assert(avatar.sx==avatar.sy and avatar.sy>0 and math.abs(avatar.cx-arrow.x)<.01 and math.abs(avatar.bottom-arrow.y+13*arrow.k)<.01,'portrait misses leader')
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
-- Find a contour in drawn screen-space spans, without consulting the ID buffer.
local function checkEdge()
    local x,y=location('home');local right=x;local extended=true
    while extended do
        extended=false
        for _,r in ipairs(spans) do
            if y>=r[2] and y<r[4] and r[1]<=right and r[3]>right then right=r[3];extended=true end
        end
    end
    local inside,outside=right-.25,right+.25
    local initial=gateChecks;enemy=true
    click(outside,y)
    mouse('Down',1,outside,y);mouse('Up',1,inside,y)
    mouse('Down',1,inside,y);mouse('Up',1,outside,y)
    assert(gateChecks==initial and builds==0,'blank or cross-edge clicks requested travel')
    click(inside,y);assert(gateChecks==initial+1 and builds==0,'visible island edge did not request travel')
    enemy=false;print('PASS displayed contour inside/outside/crossing',right,y)
end
checkEdge()
local old=view.yaw;mouse('Down',1,160,180);mouse('Move',1,510,180)
getDisplay();assert(view.cellSize==1);local dragGroups=view.groups;local dragX,dragY,dragScale=tx,ty,sc
mouse('Up',1,510,180);getDisplay()
assert(view.cellSize==1 and view.groups==dragGroups and tx==dragX and ty==dragY and sc==dragScale,'mouse release changed the camera transform')
assert(math.abs(view.yaw-old)>2.9 and builds==0);shot('02-back');assert(model.Anchor(view,'home')<model.Anchor(view,'ruins'))
print('PASS mouse orbit exposes back; island order reverses')
local oldX,oldY=view.panX,view.panY
mouse('Down',4,420,180);mouse('Move',4,484,204);mouse('Up',4,484,204);assert(view.panX>oldX and view.panY>oldY and builds==0);shot('03-pan')
print('PASS right-button pan without travel');checkEdge()
x,y=location('home');enemy=true;click(x,y);assert(map.IsOpen() and builds==0);shot('04-gate');enemy=false
mouse('Down',1,x,y);assert(builds==0);mouse('Up',1,x,y);assert(map.IsOpen() and builds==1);env.step()
assert(M.region=='home' and not map.IsOpen() and not held and pin.x==home.x+12);print('PASS rotated model click upon release, combat gate and asynchronous home arrival')
press(KEY_M);now=now+.3;assert(held);shot('05-home');assert(home.NearForge(Vector3(home.x+1,home.base,home.z+6)) and not home.NearForge(ctl.safePos))
-- Exercise the actual finger capture and release methods used by the raw Touch handlers.
GetPlatform=function()return 'Web' end
local touch=require('ui.TouchControls');package.loaded['ruins.GameSettings'].TouchDetected=noop
input={numTouches=0};Node=function()return {CreateScriptObject=function()return {SubscribeToEvent=noop} end}end
touch.Attach({AddChild=noop},function()return {cool={},cooldown={},blocked=map.IsOpen()}end)
local function touchEvent(name,id,x,y)
    _G['RuinsTouch_'..name](nil,{GetInt=function(_,key)return ({TouchID=id,X=x,Y=y})[key] end})
end
local before=view.yaw;touchEvent('Begin',7,410,200);touchEvent('Move',7,450,210)
getDisplay();assert(view.cellSize==1);local touchGroups=view.groups;local touchYaw=view.yaw
touchEvent('End',7,450,210);getDisplay()
assert(view.cellSize==1 and view.groups==touchGroups and view.yaw==touchYaw and view.yaw~=before and M.region=='home')
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
