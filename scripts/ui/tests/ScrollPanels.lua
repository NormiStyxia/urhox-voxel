-- 独立卷轴面板渲染入口，不加载地形；网格背景用于检查遮罩和裁剪。
local UI=require('urhox-libs/UI')
local Draw=require('ui.PixelDraw')
local scene
local Background=UI.Panel:Extend('ScrollPanelTestBackground')
function Background:Render(vg)
    local w,h=Draw.Metrics()
    Draw.Begin(vg,true)
    Draw.Rect(vg,0,0,w,h,{65,96,105})
    for x=0,w,24 do Draw.Rect(vg,x,0,1,h,{80,114,120}) end
    for y=0,h,24 do Draw.Rect(vg,0,y,w,1,{80,114,120}) end
    Draw.Finish(vg)
end
function Start()
    scene=Scene()
    scene:CreateComponent('Octree')
    local camera=scene:CreateChild('Camera'):CreateComponent('Camera')
    renderer:SetViewport(0,Viewport:new(scene,camera))
    UI.Init({theme='default-dark',scale=UI.Scale.DEFAULT})
    UI.SetRoot(UI.Panel{width='100%',height='100%',children={
        Background{position='absolute',left=0,top=0,width='100%',height='100%',pointerEvents='none'},
    }})
end
function Stop()
    require('ui.WorldMap').Close()
    require('ui.ForgePanel').ForceClose()
    UI.Shutdown()
end
