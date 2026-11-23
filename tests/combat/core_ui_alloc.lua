package.path='scripts/?.lua;'..package.path
local base=rawget(_G,'UI_BASELINE')
local case=rawget(_G,'UI_CASE') or 'boss'
for _,name in ipairs({'ui.CombatHUD','ui.PixelDraw','ui.TouchControls','ruins.RuinsHUD','ui.TouchInput'}) do
 if base then package.preload[name]=function()return dofile(base..'/'..name:match('[^.]+$')..'.lua') end end
end
local noop=function()end
local classes={}
-- Opaque host-context adapter (.emmylua/NanoVG.manual.d.lua), not a numeric handle.
local vg={} --[[@as NVGContextWrapper]]
local Panel=setmetatable({Extend=function(_,name)
 local c={};c.__index=c;setmetatable(c,{__call=function(t,p)return setmetatable(p,t)end});classes[name]=c;return c
end},{__call=function(_,p)return p end})
local safe={left=0,right=0,top=0,bottom=0}
local UI={Panel=Panel,Scale={DEFAULT=1},Init=noop,SetRoot=noop,Shutdown=noop,
 GetScale=function()return 1 end,GetSafeAreaInsets=function()return {left=safe.left,right=safe.right,top=safe.top,bottom=safe.bottom} end}
package.loaded['urhox-libs/UI']=UI
package.loaded['urhox-libs/UI/Core/ImageCache']={GetContext=function()return vg end}
package.loaded['ui.SettingsMenu']={IsBlocked=function()return false end,IsOpen=function()return false end}
package.loaded['ruins.GameSettings']={TouchDetected=noop}
local events={SubscribeToEvent=noop,UnsubscribeFromAllEvents=noop}
Node=function()return {CreateScriptObject=function()return events end,Remove=noop}end
input={focus=true,numTouches=0,GetKeyPress=function()return false end}
graphics={GetWidth=function()return 1280 end,GetHeight=function()return 720 end,GetDPR=function()return 1 end}
GetPlatform=function()return case=='pc' and 'Mac' or 'Android' end
local now,frameNumber=1,1;local timer={GetElapsedTime=function()return now end,GetFrameNumber=function()return frameNumber end};GetTime=function()return timer end
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
local vec={};vec.__index=vec
Vector3=function(x,y,z)return setmetatable({x=x,y=y,z=z},vec)end
vec.__sub=function(a,b)return Vector3(a.x-b.x,a.y-b.y,a.z-b.z)end
vec.__add=function(a,b)return Vector3(a.x+b.x,a.y+b.y,a.z+b.z)end
function vec:DotProduct(v)return self.x*v.x+self.y*v.y+self.z*v.z end
local Draw=require('ui.PixelDraw')
local HUD=require('ruins.RuinsHUD');local Combat=require('ui.CombatHUD');local Touch=require('ui.TouchControls');local Input=require('ui.TouchInput')
local moves={hp=85,maxHP=100,age=1,invuln=0,charge=.5,clip='bow_hold',numbers={}}
local data={moves=moves,combat=true,weapon='bow',charge=.5,enemies={}}
if case=='boss' then
 local enemy={hp=50,maxHP=100,position=Vector3(0,0,5),active=true,parts={head={maxArmor=20,armor=10}},config={height=1.5}}
 local boss={boss=true,aggro=true,hp=150,maxHP=200,poise=20,maxPoise=100}
 data.enemies={enemy,boss};data.aimed=enemy
 local screen={x=.5,y=.4};data.camera={WorldToScreenPoint=function()return screen end}
 data.cameraNode={worldPosition=Vector3(0,0,0),worldDirection=Vector3(0,0,1)}
 moves.numbers={{value=25,pos=enemy.position,untilTime=100,duration=100}}
 moves.partNotice={part='head',untilTime=100};moves.lastHitAt=100
end
if case=='range' then
 local zone={origin=Vector3(0,0,0),source=Vector3(0,.9,0),forward=Vector3(0,0,1),radius=1.8,angle=120,low=-.3,high=2}
 local screen={x=.5,y=.5}
 moves.StrikeZones=function()return zone,nil,true end
 data.camera={WorldToScreenPoint=function()return screen end}
 data.rangeVisible=function()return true end
end
local state={combat=true,weapon='bow',combatCharge=.5,cool={},cooldown={}}
HUD.Build({});HUD.SetObjective('测试任务','站在岸边瞄准桥片，修复断桥。');HUD.SetClock('12:00');HUD.SetHint('战斗测试')
Touch.Attach({AddChild=noop},function()return state end)
local layer=classes.RuinsPixelHUD;local touchLayer=classes.RuinsTouchControls
local function frame()
 moves.age=now;Combat.Set(data);Touch.Update(1/60);Touch.Sync();layer:Update(1/60);layer:Render(vg);touchLayer:Render(vg);Input.EndFrame();now=now+1/60;frameNumber=frameNumber+1
end
for _=1,20 do frame()end
collectgarbage('collect');collectgarbage('stop');count=0
local start=collectgarbage('count')
for _=1,600 do frame()end
local growth=collectgarbage('count')-start
collectgarbage('restart')
print(string.format(case..' HUD+Touch 600 frames: %.3f KB total / %.3f KB per frame / %.1f fills per frame',growth,growth/600,count/600))
if not base then assert(growth/600<=2,'HUD/Touch steady allocation exceeds 2KB per frame') end
-- Real HUD Render: the PC-only preview hides low overlays without mutating
-- their state. Exiting restores them; a touch HUD ignores this PC debug flag.
if not base then
 local buttons,hints,scrolls=0,0,0
 local button,text,scroll=Draw.Button,Draw.Text,Draw.Scroll
 Draw.Button=function(...)buttons=buttons+1;return button(...)end
 Draw.Text=function(vg,s,...)if s=='战斗测试'then hints=hints+1 end;return text(vg,s,...)end
 Draw.Scroll=function(...)scrolls=scrolls+1;return scroll(...)end
 moves.clip=nil;moves.charge=0;data.charge=0;HUD.UpdateSlots({},0);HUD.SetMessage('preview existing message')
 local function sample(preview)
  buttons,hints,scrolls=0,0,0;data.preview=preview;Combat.Set(data);layer:Render(vg)
  return buttons,hints,scrolls
 end
 local b,h,s=sample(false);assert(s>0);if not Input.IsEnabled()then assert(b>0 and h>0)end
 local pb,ph,ps=sample(true)
 if Input.IsEnabled()then assert(pb==b and ph==h and ps==s,'touch unchanged')
 else assert(pb==0 and ph==0 and ps==0,'F7 lower overlays hidden')end
 local rb,rh,rs=sample(false);assert(rb==b and rh==h and rs==s,'F7 exit restores overlays')
 Draw.Button,Draw.Text,Draw.Scroll=button,text,scroll
 print('PASS real Render preview overlay enter/exit, retained message/hint/buttons; touch unchanged')
end
if not base then
 -- Exercise every public draw entry, not a replacement renderer. Forge state is
 -- deliberately loaded late: HUD modules must neither require nor cache it.
 local Performance=require('ui.PerformanceHUD')
 local forgeBefore=package.loaded['ui.ForgePanel']
 local globalBefore=rawget(_G,'FORGE_HUD_HIDDEN')
 rawset(_G,'FORGE_HUD_HIDDEN',false)
 local hidden=false
 package.loaded['ui.ForgePanel']={HudHidden=function()return hidden end}
 data.preview=false;moves.lastHitAt=moves.age;Combat.Set(data)
 local saved,calls={},0
 for name,fn in pairs(Draw)do if type(fn)=='function'then
  saved[name]=fn;Draw[name]=function(...)calls=calls+1;return fn(...)end
 end end
 local renders={
  {name='RuinsHUD',run=function()layer:Render(vg)end},
  {name='CombatHUD',run=function()Combat.Render(vg,1280,720,safe,{x=20,y=20,h=80})end},
  {name='HitCross',run=function()Combat.RenderHit(vg,640,360)end},
  {name='TouchControls',run=function()touchLayer:Render(vg)end},
  {name='PerformanceHUD',run=function()classes.RuinsPerformanceHUD:Render(vg)end},
 }
 for _,entry in ipairs(renders)do
  hidden=false;calls=0;entry.run();local visible=calls;assert(visible>0,entry.name..' visible baseline')
  hidden=true;calls=0;entry.run();assert(calls==0,entry.name..' must not issue any draw call')
  hidden=false;calls=0;entry.run();assert(calls==visible,entry.name..' restores without reinitialization')
  -- Missing/canonicalized package.loaded entry must not leak any HUD pixels.
  package.loaded['ui.ForgePanel']=nil;rawset(_G,'FORGE_HUD_HIDDEN',true)
  calls=0;entry.run();entry.run();assert(calls==0,entry.name..' global-only fallback')
  package.loaded['ui.ForgePanel']={HudHidden=function()return false end}
  calls=0;entry.run();assert(calls==0,entry.name..' global true wins over module false')
  rawset(_G,'FORGE_HUD_HIDDEN',false)
  package.loaded['ui.ForgePanel']={HudHidden=function()return hidden end}
  hidden=true;calls=0;entry.run();assert(calls==0,entry.name..' module true wins over global false')
  hidden=false;calls=0;entry.run();assert(calls==visible,entry.name..' both cleared restores')
 end
 -- Exact Scene module binding works even without either cache or global flag.
 local sourceHidden=true
 local function readSource()return sourceHidden end
 for _,mod in ipairs({HUD,Combat,Touch,Performance})do mod.SetForgeVisibility(readSource)end
 package.loaded['ui.ForgePanel']=nil;rawset(_G,'FORGE_HUD_HIDDEN',nil)
 calls=0;for _,entry in ipairs(renders)do entry.run()end;assert(calls==0,'direct authoritative getter is cache-independent')
 sourceHidden=false;calls=0;for _,entry in ipairs(renders)do entry.run()end;assert(calls>0)
 for _,mod in ipairs({HUD,Combat,Touch,Performance})do mod.SetForgeVisibility(nil)end
 package.loaded['ui.ForgePanel']={HudHidden=function()return hidden end}
 -- Use ForgePanel's actual getter and session phases,
 -- with the registered getter route and a deliberately absent module cache.
 package.loaded['ui.ForgePanel']=nil
 local actual=require('ui.ForgePanel').HudHidden
 local sessionIndex
 for i=1,10 do if debug.getupvalue(actual,i)=='session' then sessionIndex=i;break end end
 assert(sessionIndex)
 for _,mod in ipairs({HUD,Combat,Touch,Performance})do mod.SetForgeVisibility(actual)end
 package.loaded['ui.ForgePanel']=nil
 for _,v in ipairs({{phase='opening',phaseTime=0,want=false},{phase='opening',phaseTime=.13,want=true},
  {phase='reveal',phaseTime=.15,want=true},{phase='open',phaseTime=0,want=true},
  {phase='closing',phaseTime=.1,want=true},{phase='closed_reveal',phaseTime=.05,want=false}})do
  debug.setupvalue(actual,sessionIndex,v);assert(actual()==v.want);calls=0
  for _,entry in ipairs(renders)do entry.run()end
  assert((calls==0)==v.want,'actual opening/revealing/open/closing/finish visibility contract')
 end
 debug.setupvalue(actual,sessionIndex,nil)
 for _,mod in ipairs({HUD,Combat,Touch,Performance})do mod.SetForgeVisibility(nil)end
 package.loaded['ui.ForgePanel']={HudHidden=function()return hidden end}
 -- A long open session emits only one hide log per layer, not one per frame.
 local oldPrint=print;local hiddenLogs=0
 print=function(line)if tostring(line):find('HUD: hidden by forge',1,true)then hiddenLogs=hiddenLogs+1 else oldPrint(line)end end
 hidden=true
 for _=1,120 do for _,entry in ipairs(renders)do entry.run()end end
 assert(hiddenLogs==4,'exactly one log per HUD layer (CombatHUD owns both entry points)')
 hidden=false;for _,entry in ipairs(renders)do entry.run()end
 hidden=true;for _,entry in ipairs(renders)do entry.run()end
 assert(hiddenLogs==8,'new opening logs once again');print=oldPrint
 -- Scene has no raw NanoVG HUD path; its banners/targets only update RuinsHUD.
 local sf=assert(io.open('scripts/ruins/RuinsScene.lua'));local scene=sf:read('*a');sf:close()
 assert(not scene:find('nvg%u[%w_]*%s*%('),'new direct Scene drawing path requires explicit forge guard review')
 for _,setter in ipairs({'HUD.SetMessage','HUD.SetTarget','HUD.SetHint','HUD.SetCrossVisible'})do
  assert(scene:find(setter,1,true),'HUD source routed via '..setter)
 end
 -- Timers and data updates continue while covered; rendering alone is gated.
 hidden=true;local age=moves.age;frame();assert(moves.age>age)
 HUD.SetMessage('updated while forge covered');HUD.SetClock('13:00');HUD.UpdateSlots({freeze=2},.2)
 hidden=false;calls=0;layer:Render(vg);assert(calls>0)
 for name,fn in pairs(saved)do Draw[name]=fn end
 package.loaded['ui.ForgePanel']=forgeBefore
 rawset(_G,'FORGE_HUD_HIDDEN',globalBefore)
 print('PASS forge HudHidden: all five HUD draw entries zero calls; close restores; covered updates continue')
end
return growth/600
