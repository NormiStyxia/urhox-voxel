-- 与地图使用相同受控开卷进度，保留实际游戏背景。
local Draw=require('ui.PixelDraw')
local Forge=require('ui.ForgePanel')
local Store=require('combat.WeaponStore')
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
    V.assert(Forge.Open({config=Store.Default(),class='sword',canOpen=function() return true end}),'锻造卷轴已打开')
end)
V.atFrame(100,function() openness=1 end)
