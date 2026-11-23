local M = {
    Items = {
        {id='ore', name='强化矿', description='用于打造和升级武器。', icon='ui/materials/ore_20.png'},
        {id='sand', name='淬炼砂', description='用于提高石印的品阶。', icon='ui/materials/sand_20.png'},
        {id='wood_resin', name='木灵凝脂', description='凝结在木灵胸前的暖金树脂。', icon='ui/materials/wood_resin_20.png'},
        {id='amber_silk', name='琥珀巢丝', description='织巢虫金色巢囊中取出的坚韧纤维。', icon='ui/materials/amber_silk_20.png'},
        {id='armor_crystal', name='岩甲晶片', description='岩甲巨兽的肩晶碎片，依然连着深色岩甲。', icon='ui/materials/armor_crystal_20.png'},
        {id='ruin_conduit', name='遗迹导能件', description='构装体的铜环中嵌着仍有余光的青晶。', icon='ui/materials/ruin_conduit_20.png'},
        {id='time_dust', name='时蚀砂', description='时蚀灵体消散后留下的冷光砂粒。', icon='ui/materials/time_dust_20.png'},
        {id='timber', name='木材', description='从遗迹采集树折取的带皮枝材。', icon='ui/materials/timber_20.png'},
        {id='stone', name='石料', description='在遗迹采石点拾取的硬质石块。', icon='ui/materials/stone_20.png'},
        {id='crystal_ore', name='晶矿', description='从遗迹的晶簇中采下的原矿。', icon='ui/materials/crystal_ore_20.png'},
    },
    EnemyDrops = {
        wood_spirit = {id='wood_resin',count=1},
        nest_weaver = {id='amber_silk',count=1},
        rock_colossus = {id='armor_crystal',count=1},
        ruin_construct = {id='ruin_conduit',count=1},
        time_wraith = {id='time_dust',count=1},
    },
    Sites = {
        {'court_log','timber',2,-6.0,7.8}, {'court_vein','crystal_ore',1,8.6,5.2},
        {'court_quarry','stone',2,-11,-7.4},
        {'south_log','timber',2,-4.6,-58.4}, {'south_vein','crystal_ore',1,4.8,-56.8},
        {'east_log','timber',2,32.4,4.5}, {'west_vein','crystal_ore',1,-14.2,-28.2},
        {'east_quarry','stone',2,31.2,10.8},
    },
    ById = {},
    SiteByKey = {},
}

for _,item in ipairs(M.Items) do M.ById[item.id]=item end
for _,site in ipairs(M.Sites) do M.SiteByKey['site:'..site[1]]=site end

function M.IsGathered(id)
    return M.ById[id]~=nil and id~='ore' and id~='sand'
end

function M.Count(progress,id)
    if id=='ore' or id=='sand' then return progress[id] or 0 end
    return progress.materials and progress.materials[id] or 0
end

return M
