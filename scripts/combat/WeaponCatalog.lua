-- Shared weapon handling and appearance, plus fixed equipment and engraving profiles.
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
        stats={attack=10,reach=1,poise=6,armorBreak=1},
        hit={origin={0,0,0},dir={0,1,0},length=.825,radius=.12},
        colors={primary=3,secondary=1,accent=2},visualTip=.825*1.25},
    bow={name='荆棘花弓',appearance='thorn',tintable=false,
        stats={attack=8,reach=1,poise=4,armorBreak=1,draw=1,range=64,move=.5},
        hit={origin={.06,.06,.09},dir={0,0,1}},
        colors={primary=4,secondary=1,accent=2},halfHeight=.54},
}
M.Classes={'sword','bow','time'}
M.Tiers={'普通','珍贵','传说'}
M.Weapons={
    sword={{id='iron',name='遗迹铁剑',attack=10},{id='warden',name='守门长剑',attack=13},{id='wing',name='翼剑',attack=16}},
    bow={{id='field',name='猎弓',attack=8},{id='silver',name='银枝弓',attack=11},{id='thorn',name='荆棘花弓',attack=14}},
    time={{id='clock',name='星砂时钟',attack=6}},
}
-- Per-rank multipliers. All attributes apply to every weapon of that class.
M.Imprints={
    sword={{id='edge',name='锋芒剑印',stat='attack',label='攻击',bonus=.08},
        {id='breaker',name='破军剑印',stat='armorBreak',label='破甲',bonus=.20},
        {id='impact',name='震刃剑印',stat='poise',label='削韧',bonus=.15}},
    bow={{id='feather',name='白羽矢印',stat='attack',label='攻击',bonus=.08},
        {id='awl',name='凿甲矢印',stat='armorBreak',label='破甲',bonus=.20},
        {id='anchor',name='镇石矢印',stat='poise',label='削韧',bonus=.15}},
    time={{id='rift',name='裂地法印',stat='terrainRadius',label='破坏范围',bonus=.12},
        {id='erosion',name='蚀岩法印',stat='terrainPower',label='破坏强度',bonus=.15},
        {id='echo',name='余震法印',stat='poise',label='碎时削韧',bonus=.25}},
}
M.CraftCost={3,6,12}
M.LevelCap=5
M.RefineChance={{80,100},{50,75,100}}
function M.Find(list,id)
    for index,item in ipairs(list) do if item.id==id then return item,index end end
end
function M.Stats(class,progress)
    local slot=progress.slots[class]
    local item=M.Find(M.Weapons[class],slot.weapon)
    local imprint=M.Find(M.Imprints[class],slot.imprint)
    local stats={}
    local base=class=='time' and {poise=3,terrainRadius=1,terrainPower=3} or M.Definitions[class].stats
    for k,v in pairs(base) do stats[k]=v end
    local level=slot.levels[item.id]
    stats.attack=item.attack*(1+(level-1)*.10)
    if class=='time' then stats.terrainRadius=1+(level-1)*.08 end
    if imprint then stats[imprint.stat]=stats[imprint.stat]*(1+imprint.bonus*slot.ranks[imprint.id]) end
    return stats
end
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
