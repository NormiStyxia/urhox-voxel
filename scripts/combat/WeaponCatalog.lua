-- Weapon class rules and cosmetic choices. No interchangeable parts or stat modifiers.
local M={}
M.VOXEL_SIZE=.03 -- fixed effect / fallback silhouettes only
M.Channels={'primary','secondary','accent'}
M.ColorPresets={
    {name='时砂金',rgb={224,178,83}},{name='冰蓝',rgb={143,208,232}},
    {name='遗迹灰',rgb={157,179,194}},{name='铜红',rgb={170,102,48}},
    {name='苔绿',rgb={112,144,82}},{name='暮紫',rgb={153,121,177}},
}
M.Definitions={
    sword={name='翼剑',appearance='wing',tintable=true,
        stats={attack=10,speed=1,reach=1,poise=6,armorBreak=1,charge=.45},
        hit={origin={0,0,0},dir={0,1,0},length=.825,radius=.12},
        colors={primary=3,secondary=1,accent=2},visualTip=.825*1.25},
    bow={name='荆棘花弓',appearance='thorn',tintable=false,
        stats={attack=8,speed=1,reach=1,poise=4,armorBreak=1,draw=1,range=64,spread=1,move=.5,projectileSpeed=1},
        hit={origin={.06,.06,.09},dir={0,0,1}},
        colors={primary=4,secondary=1,accent=2},halfHeight=.54},
}
function M.DefaultWeapon(weapon)
    local definition=assert(M.Definitions[weapon],'unknown weapon')
    local colors={}
    for _,channel in ipairs(M.Channels) do colors[channel]=definition.colors[channel] end
    return {appearance=definition.appearance,colors=colors}
end
function M.ValidateWeapon(weapon,config)
    local definition=M.Definitions[weapon]
    if not definition or type(config)~='table' or config.appearance~=definition.appearance
        or type(config.colors)~='table' then return false end
    for _,channel in ipairs(M.Channels) do
        local index=config.colors[channel]
        if type(index)~='number' or index%1~=0 or index<1 or index>#M.ColorPresets then return false end
    end
    return true
end
function M.CopyAppearance(weapon,config)
    if not M.ValidateWeapon(weapon,config) then return nil end
    local result=M.DefaultWeapon(weapon)
    if M.Definitions[weapon].tintable then
        for _,channel in ipairs(M.Channels) do result.colors[channel]=config.colors[channel] end
    end
    return result
end
return M
