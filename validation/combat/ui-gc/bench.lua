package.path='scripts/?.lua;'..package.path
local base=UI_BASELINE
for _,name in ipairs({'ui.CombatHUD','ui.PixelDraw','ui.TouchControls','ruins.RuinsHUD','ui.TouchInput'}) do
 if base then package.preload[name]=function()return dofile(base..'/'..name:match('[^.]+$')..'.lua') end end
end
local noop=function()end
local classes={}
local Panel=setmetatable({Extend=function(_,name)
 local c={};c.__index=c;setmetatable(c,{__call=function(t,p)return setmetatable(p,t)end});classes[name]=c;return c
end},{__call=function(_,p)return p end})
local safe={left=0,right=0,top=0,bottom=0}
local UI={Panel=Panel,Scale={DEFAULT=1},Init=noop,SetRoot=noop,Shutdown=noop,
 GetScale=function()return 1 end,GetSafeAreaInsets=function()return safe end}
package.loaded['urhox-libs/UI']=UI
package.loaded['urhox-libs/UI/Core/ImageCache']={GetContext=function()return 1 end}
package.loaded['ui.SettingsMenu']={IsBlocked=function()return false end,IsOpen=function()return false end}
package.loaded['ruins.GameSettings']={TouchDetected=noop}
local events={SubscribeToEvent=noop,UnsubscribeFromAllEvents=noop}
Node=function()return {CreateScriptObject=function()return events end,Remove=noop}end
input={focus=true,numTouches=0,GetKeyPress=function()return false end}
graphics={GetWidth=function()return 1280 end,GetHeight=function()return 720 end,GetDPR=function()return 1 end}
GetPlatform=function()return 'Android' end
local now=1;local timer={GetElapsedTime=function()return now end};GetTime=function()return timer end
for _,n in ipairs({'NVG_ALIGN_LEFT','NVG_ALIGN_CENTER','NVG_ALIGN_MIDDLE','NVG_IMAGE_NEAREST','NVG_TEXT_SCALE_FULL','NVG_SIZE_PIXEL','KEY_H'})do _G[n]=1 end
local count=0
nvgFill=function()count=count+1 end
for _,n in ipairs({'Translate','Save','Restore','ResetTransform','Scale','ShapeAntiAlias','TextScaleMode','FontSizeMethod','BeginPath','Rect','FillColor','FillPaint','IntersectScissor','FontFaceId','FontSize','FontBlur','TextLetterSpacing','TextAlign','Text','DeleteImage'})do _G['nvg'..n]=noop end
nvgTextBounds=function(_,x,y,s,b) local w=utf8.len(s)*12;if b then b[1],b[2],b[3],b[4]=0,-6,w,6 end;return w end
nvgCreateFont=function()return 1 end
local images={};local sizes={};local id=0
nvgCreateImage=function(_,path)
 if images[path]then return images[path]end
 id=id+1;images[path]=id
 local file=assert(io.open('assets/'..path,'rb'));local header=file:read(24);file:close()
 local w,h=string.unpack('>I4I4',header,17);sizes[id]={w,h};return id
end
nvgImageSize=function(_,h)return sizes[h][1],sizes[h][2]end
-- Native result objects modeled explicitly; this is NOT native heap timing.
nvgRGBA=function(r,g,b,a)return {r=r/255,g=g/255,b=b/255,a=a/255}end
nvgImagePattern=function(_,x,y,w,h,angle,img,a)return {xform={1,0,0,1,x,y},extent={w,h},image=img,alpha=a}end
nvgImagePatternTinted=nvgImagePattern
Vector3=function(x,y,z)return {x=x,y=y,z=z}end
local Draw=require('ui.PixelDraw')
local HUD=require('ruins.RuinsHUD');local Combat=require('ui.CombatHUD');local Touch=require('ui.TouchControls');local Input=require('ui.TouchInput')
local moves={hp=85,maxHP=100,age=1,invuln=0,charge=.5,clip='bow_hold',numbers={}}
local data={moves=moves,combat=true,weapon='bow',charge=.5,enemies={}}
local state={combat=true,weapon='bow',combatCharge=.5,cool={},cooldown={}}
HUD.Build({});HUD.SetObjective('测试任务','站在岸边瞄准桥片，修复断桥。');HUD.SetClock('12:00');HUD.SetHint('战斗测试')
Touch.Attach({AddChild=noop},function()return state end)
local layer=classes.RuinsPixelHUD;local touchLayer=classes.RuinsTouchControls
local function frame()
 moves.age=now;Combat.Set(data);Touch.Update(1/60);layer:Update(1/60);layer:Render(1);touchLayer:Render(1);Input.EndFrame();now=now+1/60
end
for _=1,20 do frame()end
collectgarbage('collect');collectgarbage('stop');count=0
local start=collectgarbage('count')
for _=1,600 do frame()end
local growth=collectgarbage('count')-start
collectgarbage('restart')
print(string.format('HUD+Touch 600 frames: %.3f KB total / %.3f KB per frame / %.1f fills per frame',growth,growth/600,count/600))
return growth/600
