local M = {
    Items = {
        {id='ore', name='强化矿', description='用于打造和升级武器。', icon='ui/materials/ore_20.png'},
        {id='sand', name='淬炼砂', description='用于提高石印的品阶。', icon='ui/materials/sand_20.png'},
        {id='wood_resin', name='木灵凝脂', description='凝结在木灵胸前的暖金树脂。', icon='ui/materials/wood_resin_20.png'},
        {id='amber_silk', name='琥珀巢丝', description='织巢虫金色巢囊中取出的坚韧纤维。', icon='ui/materials/amber_silk_20.png'},
        {id='armor_crystal', name='岩甲晶片', description='岩甲巨兽的肩晶碎片，依然连着深色岩甲。', icon='ui/materials/armor_crystal_20.png'},
        {id='ruin_conduit', name='遗迹导能件', description='构装体的铜环中嵌着仍有余光的青晶。', icon='ui/materials/ruin_conduit_20.png'},
        {id='time_dust', name='时蚀砂', description='时蚀灵体消散后留下的冷光砂粒。', icon='ui/materials/time_dust_20.png'},
        {id='timber', name='木材', description='在遗迹树木旁取得的带皮枝材。', icon='ui/materials/timber_20.png'},
        {id='stone', name='石料', description='从墙根层岩采石点凿取的赤褐砂岩石料。', icon='ui/materials/stone_20.png'},
        {id='crystal_ore', name='晶矿', description='从遗迹的晶簇中采下的原矿。', icon='ui/materials/crystal_ore_20.png'},
    },
    EnemyDrops = {
        wood_spirit = {id='wood_resin',count=1},
        nest_weaver = {id='amber_silk',count=1},
        rock_colossus = {id='armor_crystal',count=1},
        ruin_construct = {id='ruin_conduit',count=1},
        time_wraith = {id='time_dust',count=1},
    },
    -- 采集点刷新间隔（秒）。以前是永久耗尽，改为按时间冷却刷新。
    SiteRespawnSeconds = 180,
    TreeYield = { id = 'timber', count = 2 },
    -- {key, item, count, x, z, mode?, faceX?, faceZ?}.
    -- 矿石与专门采石点贴在墙壁与地面交界处；树木取木点由 RuinsBuild 每棵树动态登记。
    Sites = {
        {'court_vein', 'crystal_ore', 1, 18.65, 6.18, 'wall', 0, 0},
        {'west_vein', 'crystal_ore', 1, -9.20, -52.60, 'wall', -9.20, -58.0},
        {'court_quarry', 'stone', 2, -17.40, -9.15, 'wall', 0, 0},
    },
    ById = {},
    SiteByKey = {},
}

for _,item in ipairs(M.Items) do M.ById[item.id]=item end
for _,site in ipairs(M.Sites) do M.SiteByKey['site:'..site[1]]=site end

function M.IsTreeSiteKey(key)
    if type(key)~='string' then return false end
    if key=='site:east_ancient' or key=='site:west_ancient' then return true end
    local idx=key:match('^site:tree_(%d+)$')
    local n=idx and tonumber(idx)
    return n~=nil and n>=1 and n<=128
end

function M.ValidSite(siteKey,id,count)
    local site=M.SiteByKey[siteKey]
    if site then return site[2]==id and site[3]==count end
    if M.IsTreeSiteKey(siteKey) then
        return id==M.TreeYield.id and count==M.TreeYield.count
    end
    return false
end

function M.IsSiteClaimed(siteClaims,key,now)
    if type(siteClaims)~='table' or not key then return false end
    local stamp=siteClaims[key]
    if type(stamp)~='number' or stamp<=0 then return false end
    if not now or now<=0 then return true end
    return (now-stamp)<(M.SiteRespawnSeconds or 180)
end

function M.IsGathered(id)
    return M.ById[id]~=nil and id~='ore' and id~='sand'
end

function M.Count(progress,id)
    if id=='ore' or id=='sand' then return progress[id] or 0 end
    return progress.materials and progress.materials[id] or 0
end

return M
