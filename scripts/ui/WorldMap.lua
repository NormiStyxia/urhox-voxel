local UI=require('urhox-libs/UI')
local Draw=require('ui.PixelDraw')
local Model=require('ui.WorldMapModel')
local Map={}
local layer,root,onTravel,onClose,view
local current,selected,notice,touchMode,opened,closing,closeFrom,pointed
local pointers={}
local ink={64,63,52}; local muted={108,98,74};local edge={155,127,84}
local paper={232,213,167};local light={246,228,183};local line={207,184,139}
local green={46,82,75};local gold={215,177,102};local red={134,69,52}
local names={ruins='时之遗迹',home='家园小岛'}
local ids={'ruins','home'}
local function round(n) return math.floor(n+.5) end
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function metrics()
    local w,h,s=Draw.Metrics();local u=Draw.PixelToHUD()
    local aw,ah=w-s.left-s.right-8,h-s.top-s.bottom-8
    local k=math.max(u,math.floor(math.min(aw/344,ah/196)/u)*u)
    local W,H=math.floor(aw/k),math.floor(ah/k)
    return round((w+s.left-s.right-W*k)*.5/u)*u,round((h+s.top-s.bottom-H*k)*.5/u)*u,k,W,H,w,h
end
local function frame(W,H,k,cellSize)
    local top,bottom=34,H-54
    local u=Draw.PixelToHUD()
    local nominal=math.min((W-40)/346,(bottom-top-6)/112)
    local step=math.max(u/k,math.ceil(nominal*k/u)*u/k)
    Model.Update(view,(W-46)/step,(bottom-top-15)/step,cellSize)
    local ax,ay=Model.Anchor(view,current)
    local iconSize=32*math.max(1,round(k/u*.57))*u/k
    local ox=round(clamp(W*.5-view.centerX*step+view.panX,26+iconSize*.5-ax*step,W-23-ax*step))
    local oy=round(clamp((top+bottom)*.5-view.centerY*step+view.panY,top+20+iconSize-ay*step,bottom-5-ay*step))
    return ox,oy,step,top,bottom
end
local function screenPoint(x,y)
    local left,top,k,W,H=metrics()
    return (x-left)/k,(y-top)/k,W,H,k
end
local function clock() return GetTime():GetElapsedTime() end
local function progress()
    if closing then return closeFrom*(1-clamp((clock()-closing)/.16,0,1)) end
    local t=clamp((clock()-opened)/.26,0,1)
    return t*t*(3-2*t)
end
local function paperStrip(vg,H,x,width,sourceX,sourceWidth)
    local sx=width/sourceWidth
    for section=1,3 do
        local y,sh,sy=0,10,0
        local h=12
        if section==2 then y,sy,sh,h=12,10,106,H-24
        elseif section==3 then y,sy=H-12,116 end
        local repeatCount=section==2 and math.max(1,round(h/(sh*sx))) or 1
        for tile=0,repeatCount-1 do
            local dy=y+round(h*tile/repeatCount)
            local dh=y+round(h*(tile+1)/repeatCount)-dy
            Draw.Save(vg);nvgIntersectScissor(vg,x,dy,width,dh)
            nvgTranslate(vg,x-sourceX*sx,dy-sy*dh/sh);nvgScale(vg,sx*.5,dh/sh*.5)
            Draw.Image(vg,'map_scroll',0,0);Draw.Restore(vg)
        end
    end
end
local function chart(vg,W,H,left,right)
    local roller=12
    Draw.Save(vg);nvgIntersectScissor(vg,left+roller,0,math.max(0,right-left-roller*2),H)
    paperStrip(vg,H,roller,W-roller*2,12,200)
    Draw.Rect(vg,19,31,W-38,1,edge);Draw.Rect(vg,19,H-53,W-38,1,edge)
    for x=25,W-24,8 do
        local tick=(x-25)%32==0 and 3 or 1
        Draw.Rect(vg,x,32,1,tick,line);Draw.Rect(vg,x,H-53-tick,1,tick,line)
    end
    Draw.Restore(vg)
    paperStrip(vg,H,left,roller,0,12);paperStrip(vg,H,right-roller,roller,212,12)
end
local function compass(vg,x,y)
    -- Its dark needle follows geographical north in screen space.
    for i=-5,5 do
        local a=math.abs(i)
        if a>=2 then Draw.Rect(vg,x+i,y,1,1,edge);Draw.Rect(vg,x,y+i,1,1,edge) end
    end
    for i=0,7 do Draw.Rect(vg,x-round(view.sy*i),y-round(view.cy*i),2,2,i<2 and gold or green) end
end
local palette={}
local function islands(vg,ox,oy,step)
    Draw.Save(vg);nvgTranslate(vg,ox,oy);nvgScale(vg,step,step)
    for id,rects in pairs(view.groups) do
        local rgb=Model.colours[id]
        palette[id]=palette[id] or nvgRGBA(rgb[1],rgb[2],rgb[3],255)
        nvgBeginPath(vg)
        for _,r in ipairs(rects) do nvgRect(vg,r[1],r[2],r[3],r[4]) end
        nvgFillColor(vg,palette[id]);nvgFill(vg)
    end
    Draw.Restore(vg)
end
local function button(vg,x,y,w,h,text,active)
    Draw.Rect(vg,x,y,w,h,active and green or edge)
    Draw.Rect(vg,x+1,y+1,w-2,h-2,active and green or paper)
    Draw.Text(vg,text,x+w*.5,y+h*.5,12,active and light or ink,NVG_ALIGN_CENTER)
end
local Layer=UI.Panel:Extend('RuinsWorldMap')
function Layer:Render(vg)
    local x,y,k,W,H,w,h=metrics()
    local cellSize=1
    for _,p in pairs(pointers) do
        if p.target=='chart' and p.drag and not p.pair and p.mode~='pan' then cellSize=2;break end
    end
    local ox,oy,step,top,bottom=frame(W,H,k,cellSize)
    local openness=progress()
    local left=round((W-26)*(1-openness)*.5);local right=W-left
    Draw.Begin(vg,true);Draw.Rect(vg,0,0,w,h,Draw.colors.deep,.91*openness)
    Draw.Save(vg);nvgTranslate(vg,x,y);nvgScale(vg,k,k)
    chart(vg,W,H,left,right)
    Draw.Save(vg);nvgIntersectScissor(vg,left+12,0,math.max(0,right-left-24),H)
    compass(vg,23,21)
    Draw.Text(vg,'群岛航图',35,21,12,ink)
    Draw.Text(vg,'关闭 ×',W-19,21,12,ink,NVG_ALIGN_RIGHT)
    Draw.Save(vg);nvgIntersectScissor(vg,13,top,W-26,bottom-top)
    islands(vg,ox,oy,step)
    -- The destination reticle and upright portrait have independent anchors.
    local targetId=pointed or selected
    if targetId and targetId~=current then
        local a,b=Model.Anchor(view,targetId);local dx,dy=round(ox+a*step),round(oy+b*step)
        for _,side in ipairs({-1,1}) do
            local ex=dx+side*6
            Draw.Rect(vg,ex,dy-3,2,7,green);Draw.Rect(vg,ex+(side==-1 and 0 or -2),dy-4,4,2,gold)
            Draw.Rect(vg,ex+(side==-1 and 0 or -2),dy+3,4,2,gold)
        end
    end
    local a,b=Model.Anchor(view,current);local ax,ay=round(ox+a*step),round(oy+b*step)
    local density=k/Draw.PixelToHUD();local iconK=math.max(1,round(density*.57))/density
    local iconSize=32*iconK
    -- Offset the portrait from the ground feature with a stepped leader.
    local px,py=ax-12,ay-19
    for i=0,12 do Draw.Rect(vg,ax-i,ay-i,2,2,ink) end
    Draw.Rect(vg,ax-4,ay-1,6,2,ink);Draw.Rect(vg,ax,ay-4,2,5,ink)
    Draw.Rect(vg,px,py,2,9,ink)
    Draw.Save(vg);nvgTranslate(vg,px-iconSize*.5,py-iconSize);nvgScale(vg,iconK*.5,iconK*.5)
    Draw.Image(vg,'map_nomi',0,0);Draw.Restore(vg)
    Draw.Restore(vg)
    for i,id in ipairs(ids) do
        local bx=18+(i-1)*62
        button(vg,bx,H-48,58,20,names[id],selected==id)
        if current==id then Draw.Rect(vg,bx+26,H-29,6,2,gold) end
    end
    Draw.Text(vg,'当前位置 · '..names[current],W-18,H-38,12,muted,NVG_ALIGN_RIGHT)
    local help=touchMode and '单指转动 · 双指平移 · 点岛前往' or '左键滑动转向 · 右键平移 · 点岛前往'
    Draw.Text(vg,notice or help,18,H-20,12,notice and red or ink)
    Draw.Restore(vg);Draw.Restore(vg);Draw.Finish(vg)
end
function Map.SetNotice(text) notice=text end
function Map.IsOpen() return layer~=nil end
function Map.CancelPointers() pointers={};pointed=nil end
function Map.Close()
    if not layer then return end
    root:RemoveChild(layer);root,layer,view=nil,nil,nil;Map.CancelPointers()
    local f=onClose;onClose,onTravel=nil,nil
    if f then f() end
end
function Map.Open(parent,area,travel,close,touch)
    if layer then return end
    current,selected,notice,touchMode=area,area,nil,touch==true
    opened,closing=clock(),nil
    root,onTravel,onClose=parent,travel,close
    view=Model.New()
    layer=Layer{position='absolute',left=0,top=0,width='100%',height='100%',pointerEvents='none'}
    root:AddChild(layer)
end
local function dismiss()
    if closing then return end
    closeFrom=progress();closing=clock();Map.CancelPointers()
end
function Map.StepClosing()
    if not closing or not layer then return false end
    if progress()<=0 then Map.Close() end
    return true
end
local function selectIsland(id)
    if id then selected,notice,pointed=id,nil,nil end
end
local function travel()
    if selected==current then return end
    local ok,why=onTravel(selected)
    if ok then Map.Close() else notice=why end
end
function Map.Key(key)
    if key==KEY_M or key==KEY_ESCAPE then dismiss()
    elseif progress()<1 or closing then return
    elseif key==KEY_LEFT or key==KEY_A then selectIsland('ruins')
    elseif key==KEY_RIGHT or key==KEY_D then selectIsland('home')
    elseif key==KEY_RETURN or key==KEY_SPACE then travel() end
end
local function target(x,y,W,H)
    if y>=0 and y<33 and x>W-66 then return 'close' end
    if y>=H-52 and y<=H-26 then
        if x>=16 and x<=77 then return 'ruins' end
        if x>=78 and x<=141 then return 'home' end
    end
    if x>=13 and x<W-13 and y>=34 and y<H-54 then return 'chart' end
end
local function pan(dx,dy,W,H)
    view.panX=clamp(view.panX+dx,-W*.32,W*.32)
    view.panY=clamp(view.panY+dy,-H*.28,H*.28)
end
function Map.Down(id,x,y,mode)
    if pointers[id] or closing or progress()<1 then return end
    local u,v,W,H,density=screenPoint(x,y)
    local t=target(u,v,W,H)
    if not t then return end
    local p={x=x,y=y,startX=x,startY=y,target=t,mode=mode}
    if t=='chart' then
        local ox,oy,k=frame(W,H,density)
        p.island=Model.Pick(view,(u-ox)/k,(v-oy)/k)
        pointed=p.island
    end
    if mode=='touch' then
        touchMode=true
        for _,other in pairs(pointers) do
            if other.mode=='touch' then
                p.drag,other.drag=true,true
                if p.target=='chart' and other.target=='chart' then p.pair,other.pair=true,true end
            end
        end
    end
    pointers[id]=p
end
function Map.Move(id,x,y)
    local p=pointers[id];if not p then return end
    local dx,dy=x-p.x,y-p.y
    if not p.drag then
        dx,dy=x-p.startX,y-p.startY
        if dx*dx+dy*dy<25 then return end
        p.drag=true
    end
    p.x,p.y=x,y
    pointed=nil
    if p.target~='chart' then return end
    local _,_,k,W,H=metrics()
    if p.pair then
        local count=0
        for _,other in pairs(pointers) do if other.pair then count=count+1 end end
        if count>=2 then pan(dx/k/count,dy/k/count,W,H) end
    elseif p.mode=='pan' then pan(dx/k,dy/k,W,H)
    else
        view.yaw=(view.yaw+dx/k*.018)%(math.pi*2)
        view.pitch=clamp(view.pitch+dy/k*.012,.24,.96)
    end
end
function Map.Up(id,x,y)
    local p=pointers[id];if not p then return end
    if x then Map.Move(id,x,y) else x,y=p.x,p.y end
    pointers[id]=nil
    if p.drag or p.mode=='pan' then return end
    local u,v,W,H,density=screenPoint(x,y)
    local t=target(u,v,W,H);if t~=p.target then return end
    if t=='close' then dismiss()
    elseif t=='chart' then
        local ox,oy,k=frame(W,H,density)
        local hit=Model.Pick(view,(u-ox)/k,(v-oy)/k)
        if hit and hit==p.island then selectIsland(hit);travel() end
    else selectIsland(t);travel() end
end
return Map
