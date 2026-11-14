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
local CHANNEL_PALETTE = {P="primary", S="secondary", A="accent", D="dark", W="accent"}

---@param part WeaponPart
local function Add(part)
    Parts.ById[part.id] = part
    Parts.All[#Parts.All+1] = part
end

-- Profile is ordered bottom -> top. Bevel the front/back instead of extruding
-- every silhouette cell into a three-voxel slab. Edge pixels stay one voxel.
---@param profile string[]
---@return string[][]
local function Relief(profile)
    local layers = {}
    for y, row in ipairs(profile) do
        local back,front={},{}
        for x=1,#row do
            local c=row:sub(x,x)
            local interior=c~='.' and x>1 and x<#row and row:sub(x-1,x-1)~='.' and row:sub(x+1,x+1)~='.'
            back[x]=interior and (c=='A' and 'S' or 'D') or '.'
            front[x]=interior and c or '.'
        end
        layers[y] = {table.concat(back),row,table.concat(front)}
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
        -- Straight: short ricasso and long converging point. Broad: waisted
        -- leaf, two shoulders. Rapier: narrow forte then a diamond needle.
        local edge
        if id=='blade_straight' then edge=y<=3 and 1 or (y<=13 and 2 or (y<=19 and 1 or 0))
        elseif id=='blade_broad' then
            edge=y==1 and 1 or (y==2 and 2 or (y<=6 and 3 or (y<=11 and 2 or (y<=15 and 3 or (y<=18 and 2 or (y<=20 and 1 or 0))))))
        else edge=y<=6 and 1 or 0 end
        local row, ridge = {}, {}
        for x = -half, half do
            row[#row+1] = math.abs(x) <= edge and (math.abs(x)==edge and "S" or "P") or "."
            -- Ridge is metal highlight, not a continuous emissive light bar.
            ridge[#ridge+1] = x==0 and y<height-1 and (y==2 and 'A' or 'S') or '.'
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
    {"SS..PAP..SS","DSSSPPPSSSD"}, {0,0,0},{0,2,0},{poise=1,speed=-.02})
SwordPart("guard_wing","guard","翼形","失衡+3，速度−0.04",
    {"...SPAPS...",".SSSPPPSSS.","SSD..S..DSS"}, {0,0,0},{0,3,0},{poise=3,speed=-0.04})
SwordPart("guard_slim","guard","窄身","速度+0.08，失衡−1", {".SAS.","SSPSS"},{0,0,0},{0,2,0},{speed=0.08,poise=-1})
SwordPart("sword_grip_leather","grip","缠革","发力稳，触及略短",
    {"SSS","DPP","PDP","PPD","DPP","PDP","SAS"}, {0,-3,0},{0,4,0},{attack=.5,reach=-.02})
SwordPart("sword_grip_long","grip","长柄","增加触及，出手稍慢",
    {"SSS","DPP","PDP","PPD","SSS","DPP","PDP","PPD","SAS"}, {0,-4,0},{0,5,0},{reach=0.1,speed=-0.06})
SwordPart("pommel_round","pommel","圆首","触及略长，失衡略低", {".SSS.","SPAPS",".SPS."},{0,0,0},{0,3,0},{reach=.02,poise=-1})
SwordPart("pommel_crystal","pommel","晶首","蓄满时间−8%，攻击−0.5", {"..A..",".SAS.","SDADS",".SPS."},{0,0,0},{0,4,0},{chargeMultiplier=.92,attack=-.5})
SwordPart("pommel_weight","pommel","配重","攻击+2，破甲+0.15，速度−0.08", {"SSSSS","SPDPS","SPAPS",".SPS."},{0,0,0},{0,4,0},{attack=2,armorBreak=.15,speed=-0.08})

-- Bow is in the Y/Z plane: +Y up, +Z target, string on the shooter's -Z side.
-- W explicitly identifies string voxels for the three cached draw shapes.
-- Central limb voxels are omitted so either grip can fill the same socket.
local function Limbs(id, name, desc, halfHeight, recurve, stats)
    local layers = {}
    -- Sampled centreline from |Y|=4 to the tip; same extents and sockets.
    -- Recurve has an actual reverse bend (0 -> 1 -> -1), not just a colour.
    local profiles={
        limbs_short={1,2,2,2,1,1,0,0,-1,-1,-1,-1},
        limbs_long={1,1,2,2,2,2,2,2,2,1,1,1,0,0,-1,-1,-1},
        limbs_recurve={1,2,2,2,1,1,0,0,0,1,1,1,0,-1,-1},
    }
    for y = -halfHeight, halfHeight do
        local ay=math.abs(y)
        local center=profiles[id][math.max(1,ay-3)]
        local wide=ay<halfHeight*(recurve and .65 or .5)
        local layer={}
        for z=-2,3 do
            local limb=ay>3 and (z==center or z==center-1 or (wide and z==center+1))
            local row='...'
            if limb then
                if z==center then row=wide and (ay==4 and 'SAS' or 'DPD') or '.P.'
                else row=z>center and '.S.' or '.D.' end
                if ay==halfHeight or ay==halfHeight-1 then row=z==center and '.S.' or '.D.' end
            elseif z==-2 then row='.W.' end
            layer[#layer+1]=row
        end
        layers[#layers+1] = layer
    end
    Add({id=id,weapon="bow",slot="limbs",name=name,desc=desc,voxels=layers,origin={-1,-halfHeight,-2},
        sockets={root={0,0,0},top={0,halfHeight,-1}},stats=stats,palette=CHANNEL_PALETTE})
end
Limbs("limbs_short","短弓","拉弓快，射程近",15,false,{draw=-0.15,range=-8,attack=-1})
Limbs("limbs_long","长弓","射程远，拉满稍慢",20,false,{draw=0.16,range=10,attack=2})
Limbs("limbs_recurve","反曲弓","失衡略强，出手略慢",18,true,{poise=.5,speed=-.02})

local function BowPart(id,slot,name,desc,profile,origin,sockets,stats)
    local layers=Relief(profile)
    if slot=='grip' then
        -- One right-side arrow shelf, one voxel BELOW the unchanged launch
        -- socket (2,2,3). Never fill the shaft corridor at launch Y=2.
        local width=5
        for iy,layer in ipairs(layers) do
            for iz=1,5 do
                local row=layer[iz] or string.rep('.',#profile[1])
                if #row==3 then row='.'..row..'.' end
                if iy==5 and iz>=3 then row=row:sub(1,width-2)..'SS' end
                layer[iz]=row
            end
        end
        origin={-2,origin[2],origin[3]}
    end
    Add({id=id,weapon="bow",slot=slot,name=name,desc=desc,voxels=layers,origin=origin,sockets=sockets,stats=stats,palette=CHANNEL_PALETTE})
end
BowPart("bow_grip_leather","grip","皮握把","攻击略高，失衡略低",
    {"SSS","DPP","PDP","PPD","DPP","PDP","SAS"},{-1,-3,-1},{root={0,0,0},top={0,0,0},launch={2,2,3}}, {attack=.5,poise=-.5})
BowPart("bow_grip_stable","grip","稳定握把","移动×0.6，散布−25%，拉弓速度−8%",
    {".SSS.",".DPP.","SPPPS","SPAPS","SPPPS",".PPD.",".SSS."},{-2,-3,-1},{root={0,0,0},top={0,0,0},launch={2,2,3}}, {spreadMultiplier=.75,move=.1,drawMultiplier=1/.92})
BowPart("tip_iron","tip","铁簇","出手略快，攻击略低",{"SPS",".P.",".S."},{-1,0,-1},{root={0,0,0},top={0,3,0}}, {speed=.02,attack=-.5})
BowPart("tip_bone","tip","骨簇","轻骨箭簇，箭速更快",{"SPD",".S."},{-1,0,-1},{root={0,0,0},top={0,2,0}}, {attack=-1,projectileSpeed=0.12})
BowPart("tip_crystal","tip","晶簇","破甲+25%，晶爆0.8m/箭伤25%；箭速−10%，射程−8%",{".S.","SAS",".A."},{-1,0,-1},{root={0,0,0},top={0,3,0}}, {armorBreak=.25,crystalRadius=.8,crystalDamageMultiplier=.25,projectileSpeedMultiplier=.9,rangeMultiplier=.92})

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
