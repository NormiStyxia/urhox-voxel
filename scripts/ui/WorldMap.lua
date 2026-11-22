-- Painted top-down scroll; all hit boxes and the avatar use the same native pixel grid.
local UI=require('urhox-libs/UI')
local Draw=require('ui.PixelDraw')
local Map={}
local layer,root,onTravel,onClose
local current,selected,opened,notice
local names={ruins='时之遗迹',home='家园小岛'}
local centers={ruins=59,home=166}
local function metrics()
    local w,h,s=Draw.Metrics()
    local unit=Draw.PixelToHUD()
    local scale=math.max(1,math.floor(math.min((w-s.left-s.right-8)/224,(h-s.top-s.bottom-8)/126,4)/unit))*unit
    local x=math.floor(((w+s.left-s.right-224*scale)*.5)/unit+.5)*unit
    local y=math.floor(((h+s.top-s.bottom-126*scale)*.5)/unit+.5)*unit
    return x,y,scale,w,h
end
local Layer=UI.Panel:Extend('RuinsWorldMap')
function Layer:Render(vg)
    local x,y,k,w,h=metrics()
    Draw.Begin(vg,true);Draw.Rect(vg,0,0,w,h,Draw.colors.deep,.88)
    Draw.Save(vg);nvgTranslate(vg,x,y);nvgScale(vg,k,k)
    local t=math.min(1,(GetTime():GetElapsedTime()-opened)/.25)
    local half=math.floor(4+108*(1-(1-t)^3))
    Draw.Save(vg);nvgIntersectScissor(vg,112-half,0,half*2,126)
    Draw.Save(vg);nvgScale(vg,.5,.5);Draw.Image(vg,'world_map',0,0);Draw.Restore(vg)
    if t<1 then
        -- The painted wooden rollers travel with their respective edges as the sheet opens.
        for _,side in ipairs({-1,1}) do
            local left=side<0 and 112-half or 112+half-7
            Draw.Save(vg);nvgIntersectScissor(vg,left,0,7,126)
            nvgTranslate(vg,left-(side<0 and 0 or 217),0);nvgScale(vg,.5,.5)
            Draw.Image(vg,'world_map',0,0);Draw.Restore(vg)
        end
    end
    if t>=1 then
        -- Marker sits just above the island; both the court and the roof stay readable.
        local cx=centers[current]
        local density=k/Draw.PixelToHUD()
        local markerScale=math.max(1,math.floor(density*.8+.5))/density
        local bottom=4+32*markerScale
        Draw.Save(vg);nvgTranslate(vg,cx-16*markerScale,4);nvgScale(vg,markerScale*.5,markerScale*.5)
        Draw.Image(vg,'map_nomi',0,0);Draw.Restore(vg)
        Draw.Rect(vg,cx-2,bottom,4,1,Draw.colors.brown);Draw.Rect(vg,cx-1,bottom+1,2,1,Draw.colors.brown)
        for _,id in ipairs({'ruins','home'}) do
            local at=centers[id]
            Draw.Text(vg,names[id],at,101,12,Draw.colors.brown,NVG_ALIGN_CENTER)
            if id==selected then Draw.Rect(vg,at-17,108,34,1,Draw.colors.brown) end
        end
        if notice then Draw.Text(vg,notice,112,115,12,Draw.colors.brown,NVG_ALIGN_CENTER) end
        Draw.Text(vg,'×',205,12,12,Draw.colors.brown,NVG_ALIGN_CENTER)
    end
    Draw.Restore(vg);Draw.Restore(vg);Draw.Finish(vg)
end
function Map.SetNotice(text) notice=text end
function Map.IsOpen() return layer~=nil end
function Map.Close()
    if not layer then return end
    root:RemoveChild(layer);layer=nil;root=nil
    local f=onClose;onClose,onTravel=nil,nil
    if f then f() end
end
function Map.Open(parent,area,travel,close)
    if layer then return end
    current,selected,opened,notice=area,area,GetTime():GetElapsedTime(),nil
    root,onTravel,onClose=parent,travel,close
    layer=Layer{position='absolute',left=0,top=0,width='100%',height='100%',pointerEvents='none'}
    root:AddChild(layer)
end
local function choose(id)
    selected=id
    if id==current then Map.Close();return end
    local ok,why=onTravel(id)
    if ok then Map.Close() else notice=why end
end
function Map.Key(key)
    if key==KEY_M or key==KEY_ESCAPE then Map.Close()
    elseif key==KEY_LEFT or key==KEY_A then selected='ruins'
    elseif key==KEY_RIGHT or key==KEY_D then selected='home'
    elseif key==KEY_RETURN or key==KEY_SPACE then choose(selected) end
end
function Map.Click(px,py)
    local x,y,k=metrics();local u,v=(px-x)/k,(py-y)/k
    if v<0 or v>126 or u<0 or u>224 or (u>=197 and u<=215 and v>=3 and v<=18) then Map.Close();return end
    if GetTime():GetElapsedTime()-opened<.25 then return end
    if v>=17 and v<=110 then
        if u>=17 and u<=100 then choose('ruins') elseif u>=126 and u<=205 then choose('home') end
    end
end
return Map
