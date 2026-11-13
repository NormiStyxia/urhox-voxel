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
Controls.BeginTouch(8,676,338)
assert(Input.Press('dodge') and Input.Down('dodge'),'independent dodge executes on down before release')
assert(not Input.Press('dodge'),'held dodge cannot autorepeat')
Controls.EndTouch(8);assert(not Input.Press('dodge'),'release cannot dodge a second time')
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
KEY_F9=109
local shift=false
input={GetKeyDown=function(_,key) return key==KEY_SHIFT and shift end}
local keyEvent={GetInt=function() return KEY_F9 end,GetBool=function() return false end}
---@cast keyEvent KeyDownEventData Offline adapter implements only fields consumed by handler.
local before=Input.IsEnabled()
RuinsTouch_Key(nil,keyEvent);assert(Input.IsEnabled()==before,'plain F9 is reserved for training')
shift=true;RuinsTouch_Key(nil,keyEvent);assert(Input.IsEnabled()~=before,'Shift+F9 retains touch emulation')
Controls.Stop()
local file=assert(io.open('scripts/ruins/RuinsHUD.lua'));local hudSource=file:read('*a');file:close()
local hud={}
for _,name in ipairs({'SelectHint','HelpLines'}) do
 local body=assert(hudSource:match('(function M:'..name..'.-)\nend') or hudSource:match('(function M%.'..name..'.-)\nend'))..'\nend'
 assert(load(body,'HUD hint priority','t',setmetatable({M=hud},{__index=_G})))()
end
assert(hud.SelectHint('满蓄','目标','Pointer')=='满蓄')
assert(hud.SelectHint(nil,'目标','Pointer')=='目标')
assert(hud.SelectHint('','','Pointer')=='Pointer')
local helpCombat=table.concat(hud.HelpLines('combat'),' ')
assert(helpCombat:find('Shift 闪避',1,true) and not helpCombat:find('碎时',1,true) and not helpCombat:find('滑翔',1,true))
assert(table.concat(hud.HelpLines('mounted'),' '):find('持续吐息',1,true))
assert(table.concat(hud.HelpLines('explore'),' '):find('E 冻结',1,true))
print('PASS one hint slot priority, mode-specific help, F9/Shift+F9 separation')
print('PASS module ownership: stick+attack+look, group retirement, no combat sprint, TouchCancel/menu clear held and edge')
