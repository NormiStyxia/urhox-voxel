exec(open('validation/settings/check.py').read())
lua.execute(r'''
local keys={'W','A','S','D','SHIFT','SPACE','1','2','3','E','Q','F','T','TAB','C','B','G','L'}
for i,k in ipairs(keys) do _G['KEY_'..k]=i end
MOUSEB_LEFT,MOUSEB_RIGHT,MOUSEB_MIDDLE=1,2,3
NVG_ALIGN_LEFT,NVG_ALIGN_CENTER=1,2
local UI={Panel={}}
function UI.Panel:Extend()
 local class={}
 return setmetatable(class,{__call=function(c,props) return setmetatable({props=props},{__index=c}) end})
end
package.loaded['urhox-libs/UI']=UI
screenW,screenH=844,390
safe={left=0,right=0,top=0,bottom=0}
rects,texts={},{}
local D={colors={deep={},brown={},ink={},paper={},gold={}}}
function D.Metrics() return screenW,screenH,safe end
function D.Snap(x) return math.floor(x/2+.5)*2 end
function D.PixelToHUD() return 1 end
function D.Begin() end
function D.Finish() end
function D.Rect(_,x,y,w,h) rects[#rects+1]={x=x,y=y,w=w,h=h} end
function D.NineSlice(_,_,x,y,w,h) panel={x=x,y=y,w=w,h=h} end
function D.Text(_,text,x,y,size,_,align) texts[#texts+1]={text=text,x=x,y=y,size=size,align=align} end
package.loaded['ui.PixelDraw']=D
local root={children={}}
function root:AddChild(child) self.children[#self.children+1]=child end
function root:RemoveChild(child) for i,c in ipairs(self.children) do if c==child then table.remove(self.children,i); return end end end
local Menu=require('ui.SettingsMenu')
local Perf=require('ui.PerformanceHUD')
local changes={}
S.Load(); Menu.Attach(root,function(v) changes[#changes+1]=v end); Perf.Attach(root)
assert(#root.children==0 and nodes==0)
assert(Menu.Open()); assert(Menu.IsBlocked() and #root.children==1 and subscriptions('MouseButtonDown')==1)
local function render()
 rects,texts={},{}
 for _,layer in ipairs(root.children) do layer:Render(nil) end
 for _,t in ipairs(texts) do
  local width=0
  for _,code in utf8.codes(t.text) do width=width+(code<128 and t.size/2 or t.size) end
  local left=t.align==NVG_ALIGN_CENTER and t.x-width/2 or t.x
  assert(left>=0 and left+width<=screenW,t.text..' overflow')
 end
 assert(panel.x>=safe.left and panel.y>=safe.top and panel.x+panel.w<=screenW-safe.right and panel.y+panel.h<=screenH-safe.bottom)
end
local function clickText(label)
 for _,t in ipairs(texts) do if t.text==label then Menu.Click(t.x,t.y); return end end
 error('missing label '..label)
end
for _,size in ipairs({{844,390},{915,412},{320,568},{390,844},{568,320}}) do
 screenW,screenH=size[1],size[2]
 render(); clickText('调试'); render()
 clickText('调试日志：关闭'); render(); assert(S.Get('debugLog'))
 clickText('调试日志：开启'); render(); assert(not S.Get('debugLog'))
 clickText('画质'); render(); clickText('自动'); render(); clickText('低'); render(); assert(S.Get('quality')=='low')
 clickText('高级'); render(); clickText('下一页'); render(); clickText('上一页'); render(); clickText('画质'); render()
end
clickText('关闭 · 返回游戏'); assert(not Menu.IsOpen() and Menu.IsBlocked() and #root.children==0)
input.numTouches=1; step(.1,1); assert(Menu.IsBlocked())
input.numTouches=0; step(.1,6); assert(not Menu.IsBlocked() and nodes==0)
assert(changes[1] and changes[#changes]==false)
S.Set('perfHud',true); assert(#root.children==1 and subscriptions('Update')==2)
step(.1,6); assert(subscriptions('Update')==1); render()
S.Set('perfHud',false); assert(#root.children==0); step(.1,6); assert(nodes==0)
Menu.Stop(); Perf.Stop(); S.Stop(); assert(nodes==0 and #root.children==0)
''')
print('UI mock: five screen sizes, tabs, touch hit routes, release barrier, FPS lifetime PASS (not Web rendering)')
