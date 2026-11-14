package.path='scripts/?.lua;'..package.path
local safe={left=10,right=12,top=4,bottom=6}
package.loaded['urhox-libs/UI']={GetScale=function()return 1 end,GetSafeAreaInsets=function()return safe end}
package.loaded['urhox-libs/UI/Core/ImageCache']={GetContext=function()return 1 end}
graphics={GetWidth=function()return 800 end,GetHeight=function()return 600 end,GetDPR=function()return 1 end}
NVG_IMAGE_NEAREST=1
local stamp={GetElapsedTime=function()return 1 end};GetTime=function()return stamp end
local iw,ih=64,64
local paints,colors,deleted=0,0,0
nvgCreateFont=function()return 1 end
nvgCreateImage=function(_,_,flags)assert(flags==NVG_IMAGE_NEAREST);return 1 end
nvgImageSize=function()return iw,ih end
nvgDeleteImage=function()deleted=deleted+1 end
nvgRGBA=function(r,g,b,a)colors=colors+1;return {r=r,g=g,b=b,a=a}end
nvgImagePatternTinted=function(_,x,y,w,h,_,image,color)
 paints=paints+1;return {x=x,y=y,w=w,h=h,image=image,color=color}
end
local tx,ty,stack,rect,paint,trace=0,0,{},nil,nil,{}
nvgSave=function()stack[#stack+1]={tx,ty}end
nvgRestore=function()local p=table.remove(stack);tx,ty=p[1],p[2]end
nvgTranslate=function(_,x,y)tx,ty=tx+x,ty+y end
nvgIntersectScissor=function()end
nvgBeginPath=function()end
nvgRect=function(_,x,y,w,h)rect={x+tx,y+ty,w,h}end
nvgFillPaint=function(_,p)paint=p end
nvgFill=function()trace[#trace+1]={rect[1],rect[2],rect[3],rect[4],paint.x+tx,paint.y+ty,paint.w,paint.h}end
local D=require('ui.PixelDraw')
D.NineSlice(1,'plaque_ink',10,20,130,110,8,.9)
-- Reference absolute-coordinate tiled 9-slice (pre-cache rendering contract).
local expected={}
local xs,ys,sw,sh={0,8,56},{0,8,56},{8,48,8},{8,48,8}
local dx,dy,dw,dh={10,26,124},{20,36,114},{16,98,16},{16,78,16}
for j=1,3 do for i=1,3 do
 for y=dy[j],dy[j]+dh[j]-1,sh[j]*2 do for x=dx[i],dx[i]+dw[i]-1,sw[i]*2 do
  expected[#expected+1]={x,y,math.min(sw[i]*2,dx[i]+dw[i]-x),math.min(sh[j]*2,dy[j]+dh[j]-y),x-xs[i]*2,y-ys[j]*2,128,128}
 end end
end end
assert(#trace==#expected)
for i,row in ipairs(trace) do for j,value in ipairs(row)do assert(value==expected[i][j],'tile geometry/UV changed')end end
local built=paints
for i=1,30 do D.NineSlice(1,'plaque_ink',10+i*2,20,130+i*2,110,8,.9)end
assert(paints==built,'moving/resizing uses same source patches')
D.Image(1,'plaque_ink',0,0,1,{100,110,120});built=paints;local colorBuilt=colors
for i=1,50 do D.Image(1,'plaque_ink',i*2,i*2,1,{100,110,120})end
assert(paints==built and colors==colorBuilt,'fresh caller RGB tables deduplicate by color value')
local _,_,a=D.Metrics();local _,_,b=D.Metrics();assert(a==b and a.left==10,'safe area workspace reused')
iw=32;D.Image(1,'plaque_ink',0,0,1,{100,110,120});assert(paints==built+1,'same handle resized invalidates paint')
D.Release();assert(deleted==1)
D.Image(1,'plaque_ink',0,0,1,{100,110,120});assert(paints==built+2,'context release drops paints')
assert(tx==0 and ty==0 and #stack==0,'transforms balanced')
print('PASS PixelDraw: identical tiled rect/UV contract, transform balance, moving/resize cache, fresh tint dedup, context lifetime')

-- Failed HUD draw unwinds only its own save levels, not the parent widget.
local State=require('combat.CombatState')
D.Save(1);local parentDepth=D.Depth(1)
local function brokenDraw()D.Save(1);nvgTranslate(1,8,12);D.Save(1);error('injected HUD failure')end
local ok=State.Isolated('HUD.test',brokenDraw)
assert(not ok)
D.Unwind(1,parentDepth)
assert(D.Depth(1)==parentDepth and #stack==1 and tx==0 and ty==0)
D.Restore(1);assert(D.Depth(1)==0 and #stack==0)
print('PASS isolated HUD draw restores parent NVG state after nested save failure')
