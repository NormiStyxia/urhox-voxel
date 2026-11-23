local Draw=require('ui.PixelDraw')
local Forge=require('ui.ForgePanel')
local Store=require('combat.WeaponStore')
local V=_G['V']
local openness=1
Draw.ScrollProgress=function() return openness end
V.atFrame(8,function()
    V.assert(Forge.Open({config=Store.Default(),class='sword',canOpen=function() return true end}),'锻造卷轴已打开')
end)
V.atFrame(100,function() openness=1 end)
