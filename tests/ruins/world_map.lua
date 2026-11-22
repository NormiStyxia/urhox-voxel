-- Run the real M-key handler, scroll widget, and travel checks against offline engine ports.
package.path='scripts/?.lua;'..package.path
local now,paint,avatarX=0,{},nil
local noop=function() end
Vector3=function(x,y,z)return {x=x,y=y,z=z} end
GetTime=function()return {GetElapsedTime=function()return now end} end
nvgTranslate=function(_,x,y) if y==4 then avatarX=x end end
nvgScale,nvgIntersectScissor=noop,noop
local draw=setmetatable({colors={},Metrics=function()return 896,504,{left=0,right=0,top=0,bottom=0} end,
    PixelToHUD=function()return 1 end,Image=function(_,name)paint[name]=true end},{__index=function()return noop end})
package.loaded['ui.PixelDraw']=draw
package.loaded['urhox-libs/UI']={Panel={Extend=function()return setmetatable({},{__call=function(t)return setmetatable({},{__index=t}) end})end}}
local root={AddChild=function(self,c)self.layer=c end,RemoveChild=function(self)self.layer=nil end}
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
KEY_M,KEY_RETURN,KEY_RIGHT,KEY_LEFT,KEY_ESCAPE=77,13,39,37,27;MOUSEB_LEFT=1
local fn=source:match('(local function TravelToRegion.-)local function AttachTouchControls')
local key=source:match('(function Ruins_HandleKeyDown.-)\nend');local mouse=source:match('(function Ruins_HandleMouseDown.-)\nend')
assert(load(fn..'step=AdvanceHomeTravel\n'..key..'\nend\n'..mouse..'\nend','map entry points','t',env))()
local function press(k) env.Ruins_HandleKeyDown(nil,{GetInt=function()return k end,GetBool=function()return false end}) end
local function frame()now=now+.4;root.layer:Render(1)end
press(KEY_M);assert(map.IsOpen());frame();assert(paint.world_map and paint.map_nomi and math.abs(avatarX+32/3-59)<.001)
enemy=true;press(KEY_RIGHT);press(KEY_RETURN);assert(map.IsOpen() and builds==0)
enemy=false;press(KEY_RETURN);assert(map.IsOpen());env.step();assert(M.region=='home' and not map.IsOpen() and builds==1 and pin.x==home.x+12)
assert(home.NearForge(Vector3(home.x+1,home.base,home.z+6)) and not home.NearForge(ctl.safePos))
press(KEY_M);frame();assert(math.abs(avatarX+32/3-166)<.001)
env.Ruins_HandleMouseDown(nil,{GetInt=function(_,key)return ({X=240,Y=225,Button=1})[key] end})
assert(M.region=='ruins' and not map.IsOpen() and ctl.safePos==spawn and clears==2)
press(KEY_M);press(KEY_RIGHT);press(KEY_RETURN);assert(builds==1);press(KEY_M);press(KEY_ESCAPE);assert(not map.IsOpen())
local flight=require('dragon.DragonFlight')
local f0=flight.EdgeSpeed({pos=Vector3(12,0,3),travelYaw=90})
local f1=flight.EdgeSpeed({pos=Vector3(home.x+12,0,3),arenaX=home.x,travelYaw=90})
assert(f0==f1 and f1>18,'home flight must have its own braking origin')
print('PASS M key, both painted regions, location avatar, mouse/keyboard round trip, combat gate, one-time build, dragon pad and forge radius')
