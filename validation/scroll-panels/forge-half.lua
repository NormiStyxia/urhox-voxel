local Draw=require('ui.PixelDraw')
local Forge=require('ui.ForgePanel')
local Store=require('combat.WeaponStore')
local V=_G['V']
Draw.ScrollProgress=function() return .5 end
V.atFrame(8,function()
    V.assert(Forge.Open({config=Store.Default(),class='bow',canOpen=function() return true end}),'锻造半展开卷轴已打开')
end)
