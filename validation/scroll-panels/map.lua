-- 真实遗迹背景上的卷轴验收；以受控进度检查半展开和完整展开。
local UI=require('urhox-libs/UI')
local Draw=require('ui.PixelDraw')
local Map=require('ui.WorldMap')
local V=_G['V']
local openness=.5
Draw.ScrollProgress=function() return openness end
V.atFrame(8,function()
    local game=_G['RUINS']
    V.assert(game~=nil,'遗迹场景已加载')
    if not game then return end
    UnsubscribeFromEvent('Update')
    UnsubscribeFromEvent('SceneUpdate')
    UnsubscribeFromEvent('PostUpdate')
    game.world.updateEnabled=false
    Map.Open(UI.GetRoot(),'ruins',function() return false end)
    V.assert(Map.IsOpen(),'地图卷轴已打开')
    local x,y,k,w,h=Draw.ScrollMetrics()
    V.assert(w==380 and h==214 and x>=0 and y>=0 and k>0,'地图与锻造共用尺寸')
end)
V.atFrame(100,function() openness=1 end)
