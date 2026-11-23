-- Run production HUD, input handlers and HomeIsland stage API with offline engine ports.
package.path='scripts/?.lua;'..package.path
local noop=function()end
local labels={};local draws=DrawPort or {};draws.Metrics=function()return 896,504,{left=0,right=0,top=0,bottom=0}end
draws.PixelToHUD=function()return 1 end;draws.Snap=function(v)return math.floor(v/2+.5)*2 end
draws.colors={deep={18,24,37},paper={238,227,200},gold={224,186,91},brown={67,47,32}}
local text=draws.Text or noop;draws.Text=function(vg,s,...)labels[#labels+1]=s;text(vg,s,...)end
package.loaded['ui.PixelDraw']=setmetatable(draws,{__index=function()return noop end})
package.loaded['urhox-libs/UI']={Panel={Extend=function()return setmetatable({},{__call=function(self,p)return setmetatable(p,{__index=self})end})end}}
NVG_ALIGN_RIGHT,NVG_ALIGN_CENTER=2,1
Vector3=function(x,y,z)return {x=x,y=y,z=z} end
local Touch=require('ui.TouchInput');local Controls=require('ui.TouchControls');local HUD=require('ruins.RuinsHUD')
local home=require('ruins.HomeIsland');local pointer=require('ruins.PointerCapture').New({web=false,focused=function()return true end,release=noop,changed=noop,now=function()return 0 end})
HUD.root={AddChild=noop};input={numTouches=0,focus=true};GetPlatform=function()return 'Web' end
Node=function()return {CreateScriptObject=function()return {SubscribeToEvent=noop}end} end
require('ruins.GameSettings').TouchDetected=noop
local W={IsOpen=function()return false end};local F={IsOpen=W.IsOpen};local S={IsBlocked=W.IsOpen};local wheel={IsBlocked=W.IsOpen}
local M={region='home',ride={mode='free'}};local env=setmetatable({HUD=HUD,HomeIsland=home,M=M,WorldMap=W,TouchControls=Controls,TouchInput=Touch,PixelDraw=draws,
    ForgePanel=F,WeaponWheel=wheel,SettingsMenu=S,animPreview_={index=0},combatMoves_={Cancel=noop},drag={buttons=0},pointer=pointer},{__index=_G})
local f=assert(io.open('scripts/ruins/RuinsScene.lua'));local src=f:read('*a');f:close()
local function exec(s)assert(load(s,'house scene routes','t',env))()end
exec(assert(src:match('(M.housePanel=HUD.AttachHouse.-TouchControls.housePanel=M.housePanel)')))
for _,name in ipairs({'KeyDown','MouseDown','MouseUp','MouseMove','InputFocus'}) do exec(assert(src:match('(function Ruins_Handle'..name..'.-\nend)')))end
local tick=assert(load('return function() '..assert(src:match("Safe%('Touch.Update',TouchControls.Update,dt%)%s*(if M.housePanel.-\n    end)"))..' end','house frame','t',env))()
local stop=assert(load('return function() '..assert(src:match('function M.Stop%(%)%s*(if M.housePanel.- end)'))..' end','house teardown','t',env))()
KEY_J,KEY_ESCAPE,KEY_0,KEY_1,KEY_2,KEY_3,KEY_M=106,27,48,49,50,51,109;MOUSEB_LEFT=1
local function event(t)return {GetInt=function(_,k)return t[k]end,GetBool=function(_,k)return t[k]==true end}end
local function key(k)env.Ruins_HandleKeyDown(nil,event{Key=k})end
local function mouse(type,x,y)env['Ruins_HandleMouse'..type](nil,event{Button=1,X=x,Y=y})end
local function touch(type,id,x,y)_G['RuinsTouch_'..type](nil,event{TouchID=id,X=x,Y=y})end
local p=M.housePanel;Controls.Attach({AddChild=noop},function()return {blocked=p.open==true}end)
local function frame(name)labels={};p:Render(1);if Screenshot then Screenshot(name)end;return table.concat(labels,'|')end
assert(frame('entry'):find('家园房屋'));mouse('Down',50,252);mouse('Up',50,252);assert(p.open and pointer.blocked)
assert(frame('open'):find('当前 · 废墟'));local realSet=p.port.set;local calls=0;p.port.set=function(n)calls=calls+1;return realSet(n)end
for _,n in ipairs({1,2,3,2,1,0,3})do key(KEY_0+n);assert(home.GetHouseStage()==n and p.open)end
local prior=calls;key(KEY_3);assert(calls==prior and frame('three'):find('已是三层'));key(KEY_M);assert(p.open)
key(KEY_ESCAPE);assert(not p.open and not pointer.blocked and pointer.active)
print('PASS mouse launcher, J/0-3/Esc, 7 consecutive up/down changes, repeat is idempotent and M is consumed')
-- Exercise the production overlap check with an occupied voxel volume.
local function up(fn,name,value)for i=1,100 do local k,old=debug.getupvalue(fn,i);if k==name then debug.setupvalue(fn,i,value);return i,old end end;error(name)end
local part={first=3,last=3,on=true,mask=1,brush={s=.125,Range=function()return 0,0 end,grid={IsSolid=function()return true end}}}
local ready,oldReady=up(realSet,'houseReady',true);local parts,oldParts=up(realSet,'houseParts',{part});home.GetHouseOccupants=function()return {x=home.x,y=home.base,z=home.z}end
key(KEY_J);key(KEY_1);assert(home.GetHouseStage()==3 and frame('blocked'):find('请先离开'));debug.setupvalue(realSet,ready,oldReady);debug.setupvalue(realSet,parts,oldParts);home.GetHouseOccupants=nil
-- Close with the selecting finger still down, then deliver the stale release.
touch('Begin',2,650,225);key(KEY_ESCAPE);touch('End',2,650,225);assert(not p.open and home.GetHouseStage()==3)
touch('Begin',5,50,255);touch('End',5,50,255);assert(p.open)
touch('Begin',7,805,224);touch('End',7,805,224);assert(home.GetHouseStage()==1)
touch('Begin',7,805,224);touch('Move',7,850,260);touch('End',7,805,224);assert(home.GetHouseStage()==1)
touch('Begin',8,850,162);touch('End',8,850,162);assert(not p.open)
print('PASS refusal from occupied house, native touch selection/return, no delayed stage change after closing during press')
key(KEY_J);M.region='ruins';tick();assert(not p.open);assert(not p:Down(1,50,252));M.region='home'
for _,gate in ipairs({{W,'IsOpen'},{F,'IsOpen'},{S,'IsBlocked'},{wheel,'IsBlocked'}}) do
    local obj,k=table.unpack(gate);local prior=obj[k];obj[k]=function()return true end;assert(not p:Down(1,50,255));obj[k]=prior
end
M.ride.mode='ground';assert(not p:Down(1,50,252));M.ride.mode='free';key(KEY_J)
env.Ruins_HandleInputFocus(nil,event{Focus=false});assert(not p.open and not pointer.active);key(KEY_J);stop();assert(not p.open and not M.housePanel and not Controls.housePanel)
print('PASS region exit, riding, map, forge, settings, wheel, focus loss and scene teardown')
