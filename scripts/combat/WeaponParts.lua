-- Weapon catalogue. Pure Lua: no engine objects are created while requiring it.
-- voxels[y][z] is an ASCII row along +X, with voxels[1][1][1] at origin.
-- Sockets and origin are integer voxel coordinates; one voxel is 0.03 metres.
---@class WeaponPart
---@field id string
---@field weapon string
---@field slot string
---@field name string
---@field desc string
---@field voxels string[][]
---@field origin integer[]
---@field sockets table<string, integer[]>
---@field palette table<string, string>
---@field stats table<string, number>

---@class WeaponPartsCatalog
local Parts = {}
Parts.VOXEL_SIZE = 0.03
Parts.Slots = { sword = {"pommel", "grip", "guard", "blade"}, bow = {"grip", "limbs", "tip"} }
Parts.SlotNames = { blade="剑刃", guard="护手", grip="握柄", pommel="剑首", limbs="弓臂", tip="箭簇" }
Parts.Channels = {"primary", "secondary", "accent"}
Parts.ColorPresets = {
    {name="时砂金", rgb={224,178,83}}, {name="冰蓝", rgb={143,208,232}},
    {name="遗迹灰", rgb={157,179,194}}, {name="铜红", rgb={170,102,48}},
    {name="苔绿", rgb={112,144,82}}, {name="暮紫", rgb={153,121,177}},
}
Parts.BaseStats = {
    sword = {attack=10, speed=1, reach=1, poise=6, armorBreak=1, charge=0.45},
    bow = {attack=8, speed=1, reach=1, poise=4, armorBreak=1, draw=0.7, range=36, spread=1, move=0.5, projectileSpeed=1},
}
---@type table<string, WeaponPart>
Parts.ById = {}
---@type WeaponPart[]
Parts.All = {}
local CHANNEL_PALETTE = {P="primary", S="secondary", A="accent", D="dark"}

---@param part WeaponPart
local function Add(part)
    Parts.ById[part.id] = part
    Parts.All[#Parts.All+1] = part
end

-- Profile is ordered bottom -> top. Three Z slices give dark backs and bright ridges.
---@param profile string[]
---@return string[][]
local function Relief(profile)
    local layers = {}
    for y, row in ipairs(profile) do
        layers[y] = { (row:gsub("[PSA]", "D")), row, (row:gsub("P", "S")) }
    end
    return layers
end

---@param id string
---@param name string
---@param desc string
---@param width integer
---@param height integer
---@param stats table<string, number>
local function Blade(id, name, desc, width, height, stats)
    local layers = {}
    local half = width // 2
    for y = 1, height do
        local edge = math.min(half, height-y)
        local row, ridge = {}, {}
        for x = -half, half do
            row[#row+1] = math.abs(x) <= edge and (math.abs(x)==edge and "S" or "P") or "."
            ridge[#ridge+1] = x==0 and "A" or "."
        end
        layers[y] = {table.concat(ridge), table.concat(row), table.concat(ridge)}
    end
    Add({id=id, weapon="sword", slot="blade", name=name, desc=desc, voxels=layers,
        origin={-half,0,-1}, sockets={root={0,0,0},top={0,height,0}}, stats=stats, palette=CHANNEL_PALETTE})
end
Blade("blade_straight", "直刃", "出手略快，攻击略低", 5, 22, {speed=.02,attack=-.5})
Blade("blade_broad", "阔刃", "重刃伤高，出手稍慢", 7, 21, {attack=3,speed=-0.12})
Blade("blade_rapier", "细剑", "轻快长刺，伤害稍低", 3, 26, {attack=-2,speed=0.16,reach=0.1})

local function SwordPart(id, slot, name, desc, profile, root, top, stats)
    Add({id=id, weapon="sword", slot=slot, name=name, desc=desc, voxels=Relief(profile),
        origin={-(#profile[1]//2),root[2],-1}, sockets={root=root,top=top}, stats=stats, palette=CHANNEL_PALETTE})
end
SwordPart("guard_cross","guard","十字","失衡更强，出手略慢",
    {"DDSPPAPPSDD","SSSPPAPPSSS"}, {0,0,0},{0,2,0},{poise=1,speed=-.02})
SwordPart("guard_wing","guard","翼形","失衡+3，速度−0.04",
    {"...DPAPD...",".DSPPAPPSD.","SSSPPAPPSSS"}, {0,0,0},{0,3,0},{poise=3,speed=-0.04})
SwordPart("guard_slim","guard","窄身","速度+0.08，失衡−1", {"DPAPD","SSASS"},{0,0,0},{0,2,0},{speed=0.08,poise=-1})
SwordPart("sword_grip_leather","grip","缠革","发力稳，触及略短",
    {"SAS","PDP","DPD","PDP","DPD","PDP","SAS"}, {0,-3,0},{0,4,0},{attack=.5,reach=-.02})
SwordPart("sword_grip_long","grip","长柄","增加触及，出手稍慢",
    {"SAS","PDP","DPD","PDP","DPD","PDP","DPD","PDP","SAS"}, {0,-4,0},{0,5,0},{reach=0.1,speed=-0.06})
SwordPart("pommel_round","pommel","圆首","触及略长，失衡略低", {".DSD.","DPAPD",".SAS."},{0,0,0},{0,3,0},{reach=.02,poise=-1})
SwordPart("pommel_crystal","pommel","晶首","蓄满时间−8%，攻击−0.5", {"..A..",".SAS.","DPAPD",".SSS."},{0,0,0},{0,4,0},{chargeMultiplier=.92,attack=-.5})
SwordPart("pommel_weight","pommel","配重","攻击+2，破甲+0.15，速度−0.08", {"DSSSD","DPAPD","DPAPD",".SAS."},{0,0,0},{0,4,0},{attack=2,armorBreak=.15,speed=-0.08})

-- The grip is at (0,0,0). Bow limbs curve towards the taut string at x=-6.
-- Central limb voxels are omitted so either grip can fill the same socket.
local function Limbs(id, name, desc, halfHeight, recurve, stats)
    local layers = {}
    for y = -halfHeight, halfHeight do
        local t = math.abs(y)/halfHeight
        local bend = math.floor(6*t*t+0.5)
        local center = -bend
        if recurve and math.abs(y)>halfHeight-3 then center = -6 end
        local front, back = {}, {}
        for x = -7, 1 do
            local limb = math.abs(y)>3 and math.abs(x-center)<=1
            local cap = math.abs(y)==halfHeight and x>=-6 and x<=center
            front[#front+1] = (limb or cap) and (x==center and "P" or "S") or (x==-6 and "A" or ".")
            back[#back+1] = limb and "D" or "."
        end
        layers[#layers+1] = {table.concat(back),table.concat(front)}
    end
    Add({id=id,weapon="bow",slot="limbs",name=name,desc=desc,voxels=layers,origin={-7,-halfHeight,-1},
        sockets={root={0,0,0},top={-6,halfHeight,0}},stats=stats,palette=CHANNEL_PALETTE})
end
Limbs("limbs_short","短弓","拉弓快，射程近",15,false,{draw=-0.15,range=-8,attack=-1})
Limbs("limbs_long","长弓","射程远，拉满稍慢",20,false,{draw=0.16,range=10,attack=2})
Limbs("limbs_recurve","反曲弓","失衡略强，出手略慢",18,true,{poise=.5,speed=-.02})

local function BowPart(id,slot,name,desc,profile,origin,sockets,stats)
    Add({id=id,weapon="bow",slot=slot,name=name,desc=desc,voxels=Relief(profile),origin=origin,sockets=sockets,stats=stats,palette=CHANNEL_PALETTE})
end
BowPart("bow_grip_leather","grip","皮握把","攻击略高，失衡略低",
    {"SAS","PDP","DPD","PDP","DPD","PDP","SAS"},{-1,-3,-1},{root={0,0,0},top={0,0,0},launch={0,2,3}}, {attack=.5,poise=-.5})
BowPart("bow_grip_stable","grip","稳定握把","移动×0.6，散布−25%，拉弓速度−8%",
    {".SAS.",".PDP.","DPAPD","DPAPD","DPAPD",".PDP.",".SAS."},{-2,-3,-1},{root={0,0,0},top={0,0,0},launch={0,2,3}}, {spreadMultiplier=.75,move=.1,drawMultiplier=1/.92})
BowPart("tip_iron","tip","铁簇","出手略快，攻击略低",{"DAD","SPS",".S."},{-1,0,-1},{root={0,0,0},top={0,3,0}}, {speed=.02,attack=-.5})
BowPart("tip_bone","tip","骨簇","轻骨箭簇，箭速更快",{"DAD",".S."},{-1,0,-1},{root={0,0,0},top={0,2,0}}, {attack=-1,projectileSpeed=0.12})
BowPart("tip_crystal","tip","晶簇","破甲+25%，晶爆0.8m/箭伤25%；箭速−10%，射程−8%",{"DAD","SAS",".A."},{-1,0,-1},{root={0,0,0},top={0,3,0}}, {armorBreak=.25,crystalRadius=.8,crystalDamageMultiplier=.25,projectileSpeedMultiplier=.9,rangeMultiplier=.92})

---@param id string
---@return WeaponPart?
function Parts.Get(id) return Parts.ById[id] end

---@param weapon string
---@param slot string
---@return WeaponPart[]
function Parts.GetOptions(weapon, slot)
    local result = {}
    for _, part in ipairs(Parts.All) do
        if part.weapon==weapon and part.slot==slot then result[#result+1]=part end
    end
    return result
end

---@param weapon string
---@return table
function Parts.DefaultWeapon(weapon)
    if weapon=="bow" then
        return {parts={limbs="limbs_recurve",grip="bow_grip_leather",tip="tip_iron"},colors={primary=4,secondary=1,accent=2}}
    end
    return {parts={blade="blade_straight",guard="guard_cross",grip="sword_grip_leather",pommel="pommel_round"},colors={primary=3,secondary=1,accent=2}}
end

---@class WeaponPreset
---@field id string
---@field name string
---@type WeaponPreset[]
Parts.Presets={{id='balanced',name='均衡'},{id='fast',name='快攻'},{id='armor',name='破甲'}}
--- A new independent loadout; preset identifiers are stable save/API keys.
---@param weapon string
---@param id string balanced | fast | armor
---@return table?
function Parts.Preset(weapon,id)
    if not Parts.Slots[weapon] or (id~='balanced' and id~='fast' and id~='armor') then return nil end
    local config=Parts.DefaultWeapon(weapon)
    if weapon=='sword' then
        if id=='fast' then config.parts.blade='blade_rapier';config.parts.guard='guard_slim';config.parts.pommel='pommel_crystal'
        elseif id=='armor' then config.parts.blade='blade_broad';config.parts.guard='guard_wing';config.parts.pommel='pommel_weight' end
    elseif id=='fast' then config.parts.limbs='limbs_short';config.parts.tip='tip_bone'
    elseif id=='armor' then config.parts.limbs='limbs_long';config.parts.grip='bow_grip_stable';config.parts.tip='tip_crystal' end
    return config
end

---@param weapon string
---@param config any
---@return boolean
function Parts.ValidateWeapon(weapon, config)
    if not Parts.Slots[weapon] or type(config)~="table" or type(config.parts)~="table" or type(config.colors)~="table" then return false end
    for _, slot in ipairs(Parts.Slots[weapon]) do
        local id = config.parts[slot]
        if type(id)~="string" then return false end
        local part = Parts.Get(id)
        if not part or part.weapon~=weapon or part.slot~=slot then return false end
    end
    for _, channel in ipairs(Parts.Channels) do
        local index = config.colors[channel]
        if type(index)~="number" or index%1~=0 or index<1 or index>#Parts.ColorPresets then return false end
    end
    return true
end
return Parts
