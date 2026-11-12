"""Production touch ownership, edge triggering and dp layout; no engine mocks of gameplay."""
from pathlib import Path
from lupa.lua54 import LuaRuntime
root=Path(__file__).resolve().parents[2]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.globals().scripts=str(root/'scripts')
lua.execute(r'''
package.path=scripts..'/?.lua;'..package.path
for _,key in ipairs({'SPACE','SHIFT','F','E','Q','C','G','L','B','TAB','T','F9'}) do _G['KEY_'..key]=key end
local platform='Mac'
GetPlatform=function() return platform end
local W,H,DPR=844,390,1
local safe={left=0,right=0,top=0,bottom=0}
graphics={GetWidth=function()return W*DPR end,GetHeight=function()return H*DPR end,GetDPR=function()return DPR end}
local Panel={Extend=function() return setmetatable({}, {__call=function(_,p)return p end}) end}
local ui={Panel=Panel,GetScale=function()return DPR end,GetSafeAreaInsets=function()return safe end}
package.loaded['urhox-libs/UI']=ui
local event={SubscribeToEvent=function()end,UnsubscribeFromAllEvents=function()end}
Node=function() return {CreateScriptObject=function()return event end,Remove=function()end} end
local T=require('ui.TouchInput');local C=require('ui.TouchControls')
local state={cool={},cooldown={shatter=1,freeze=1,rewind=1},canMount=true}
local parent={AddChild=function()end}
local checks=0
local function check(v,label)checks=checks+1; assert(v,label)end
C.Attach(parent,function()return state end,function()end)
check(not T.IsEnabled(),'PC defaults to keyboard')
C.BeginTouch(1,100,300);check(not T.IsEnabled(),'native desktop touch does not auto enable')
platform='Web';C.BeginTouch(1,100,300);check(T.IsEnabled(),'web first touch permanently enables')
C.MoveTouch(1,100,260)
local f,r=T.MoveAxis();check(f==1 and r==0 and T.Down('sprint'),'joystick outer radius runs')
C.BeginTouch(2,776,322);check(T.Down('shatter'),'second finger holds shatter')
C.BeginTouch(3,460,150);C.MoveTouch(3,480,160)
local dx,dy=T.ConsumeLook();check(dx==20 and dy==10,'third finger independently looks')
check(T.Down('shatter') and T.MoveAxis()==1,'look does not steal joystick or charge')
C.EndTouch(3);check(T.Down('shatter'),'look release does not release button')
C.EndTouch(2);check(not T.Down('shatter') and T.Press('shatter'),'short tap remains edge triggered')
check(not T.Press('shatter'),'press only once')
C.EndTouch(1);check(T.MoveAxis()==0 and not T.Down('sprint'),'joystick release clears sprint and axis')
C.BeginTouch(4,100,300);C.MoveTouch(4,104,300);check(T.MoveAxis()==0,'dead zone')
C.EndTouch(4)
C.BeginTouch(5,776,222);check(T.KeyPress(KEY_SPACE),'jump mapped to Space')
C.EndTouch(5)
state.mounted=true;C.Sync();C.BeginTouch(6,776,322);check(T.Down('ascend') and T.KeyPress(KEY_SPACE),'ground takeoff')
state.airborne=true;C.Sync();check(not T.Down('ascend'),'switch retires old button finger')
C.EndTouch(6)
C.BeginTouch(7,776,222);check(T.KeyDown(KEY_SHIFT),'air dash maps Shift')
C.BeginTouch(8,694,258);check(T.KeyPress(KEY_B),'air breath maps B')
C.BeginTouch(9,594,220);check(T.KeyPress(KEY_L),'air land maps L')
C.EndTouch(7);C.EndTouch(8);C.EndTouch(9)
C.BeginTouch(10,614,306);check(T.KeyPress(KEY_G),'air glide toggle edge')
C.EndTouch(10)
C.BeginTouch(11,100,300);C.MoveTouch(11,100,260);check(not T.Down('sprint'),'ride joystick never sprints')
C.BeginTouch(12,776,322);C.BeginTouch(13,792,52)
check(C.menuOpen and not T.Down('ascend') and T.MoveAxis()==0,'menu cancels all owners')
C.BeginTouch(14,400,150);check(not C.menuOpen,'help dismiss')
C.Cancel();T.Toggle();C.Sync();check(not T.IsEnabled(),'F9 force off')
C.BeginTouch(15,100,300);check(not T.IsEnabled(),'override stays off despite touch')
T.Toggle();C.Sync()
for _,size in ipairs({{844,390},{915,412}}) do
 W,H=size[1],size[2];DPR=3;safe={left=24,right=24,top=0,bottom=12};C.Sync()
 local ox,oy=W-safe.right-20,H-safe.bottom-20
 C.BeginTouch(20,ox-48,oy-48);check(T.Down('ascend'),'safe area primary button at '..W)
 C.EndTouch(20)
 C.BeginTouch(21,ox-140,oy-24);check(T.Down('descend'),'safe area descending button at '..W)
 C.EndTouch(21)
end
C.Cancel();check(not T.Down('ascend') and T.MoveAxis()==0,'focus/stop cancellation')
C.Stop()
print('PASS: '..checks..' touch ownership/layout assertions')
''')
# Parse all touched Lua using the actual Lua 5.4 parser, without executing engine code.
for f in ['ui/TouchInput.lua','ui/TouchControls.lua','ui/PixelDraw.lua','ruins/RuinsHUD.lua','ruins/RuinsScene.lua','ruins/NomiController.lua','dragon/DragonRide.lua','dragon/DragonTest.lua']:
 lua.execute('assert(load(...))',(root/'scripts'/f).read_text())
print('PASS: 8 Lua 5.4 source files parsed')
