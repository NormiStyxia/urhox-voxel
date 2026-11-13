-- Module-level ownership test; NOT a browser/native TouchCancel propagation test.
package.path='./scripts/?.lua;'..package.path
local callbacks={}
local panel={Extend=function() return setmetatable({}, {__call=function(_,p) return p end}) end}
package.loaded['urhox-libs/UI']={Panel=panel}
package.loaded['ui.PixelDraw']={Metrics=function() return 844,390,{left=0,right=0,top=0,bottom=0} end,
    Snap=function(x) return math.floor(x/2+.5)*2 end,colors={}}
local menu=false
package.loaded['ui.SettingsMenu']={IsBlocked=function() return menu end,IsOpen=function() return menu end,
    Open=function() menu=true; return true end,Click=function() end}
package.loaded['ruins.GameSettings']={TouchDetected=function() end}
GetPlatform=function() return 'Web' end
Node=function() return {CreateScriptObject=function() return {SubscribeToEvent=function(_,name,fn) callbacks[name]=fn end,
    UnsubscribeFromAllEvents=function() end} end,Remove=function() end} end
for i,name in ipairs({'SPACE','SHIFT','F','E','Q','C','G','L','B','TAB','T'}) do _G['KEY_'..name]=i end
local Input=require('ui.TouchInput')
local Controls=require('ui.TouchControls')
local state={combat=false}
local cancelled=0
Controls.Attach({AddChild=function() end},function() return state end,nil,function() cancelled=cancelled+1 end)
Controls.BeginTouch(1,100,290); Controls.MoveTouch(1,100,250)
Controls.BeginTouch(2,776,322); assert(Input.Down('shatter'))
Controls.BeginTouch(3,500,210); Controls.MoveTouch(3,510,220)
local f=Input.MoveAxis(); local x,y=Input.ConsumeLook()
assert(f>0 and x==10 and y==10,'three independent finger owners')
state.combat=true; Controls.Sync()
assert(not Input.Down('shatter') and not Input.Press('shatter'))
assert(Input.MoveAxis()>0,'mode change keeps stick owner')
Controls.CancelActions(); assert(Input.MoveAxis()>0,'State transition also preserves joystick')
Controls.EndTouch(2); Controls.BeginTouch(4,776,322); assert(Input.Down('attack'))
state.weapon='bow'
Controls.MoveTouch(4,710,280)
x,y=Input.ConsumeLook()
assert(x==-66 and y==-42 and Input.Down('attack'),'bow drag retains button ownership outside hit area')
Controls.MoveTouch(3,520,225)
x,y=Input.ConsumeLook(); assert(x==10 and y==5,'third finger remains independent while bow aims')
Controls.MoveTouch(1,100,250); assert(not Input.Down('sprint'))
callbacks.TouchCancel()
assert(not Input.Down('attack') and not Input.Press('attack') and Input.MoveAxis()==0)
Controls.BeginTouch(5,776,222) -- jump, not attack
assert(not Input.Down('attack'))
Controls.Cancel()
Controls.BeginTouch(6,776,322); assert(Input.Down('attack'))
Controls.BeginTouch(7,792,52) -- menu
assert(not Input.Down('attack') and menu)
assert(cancelled>=3)
Controls.Stop()
print('PASS module ownership: stick+attack+look, group retirement, no combat sprint, TouchCancel/menu clear held and edge')
