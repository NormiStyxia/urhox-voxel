-- Palette-preserving, instance/part/bank/domain-local materials. Init-only cloning.
local HitMaterial={}
local values={}
local shader='Shaders/BLGL/EnemyVoxelHit.shader'
local serial=0
local logged,warned=false,false
function HitMaterial.Group(config,name)
    if config.boss then
        if name=='jaw' then return 'head' end
        if name=='body' or name=='tail' or name:find('rear') then return 'body' end
    elseif config.kind=='moss_beetle' then
        if name=='shell' or name=='head' then return 'shell' end
        if name=='body' or name=='belly' then return 'belly' end
        return 'legs'
    elseif config.kind=='stone_sentry' and name=='crown' then return 'body' end
    return name
end
-- 9 prebuilt values per peak. Light keeps its exact .85 peak instead of rounding to .875.
function HitMaterial.Init(visual)
    if not values.light then
        values.light,values.heavy={},{}
        for i=0,8 do values.light[i]=Variant(.85*i/8); values.heavy[i]=Variant(i/8) end
    end
    visual.hitGroups,visual.hitMaterialCount={},0
    serial=serial+1; visual.hitMaterialId=serial
    visual.hitTemplate=cache:GetResource('Material','Shaders/BLGL/EnemyVoxelHit.xml')
    visual.flashSupported=false
end
---@param visual EnemyVisual
---@param volume VoxelVolume
---@param name string
function HitMaterial.Attach(visual,volume,name)
    local original=volume:GetMaterial()
    local domain,bank=volume:GetPaletteDomain(),volume:GetPaletteBank()
    local group=HitMaterial.Group(visual.config,name)
    local key=group..':'..domain..':'..bank
    local entry=visual.hitGroups[key]
    if not entry then
        entry={name=group,material=false,level=0,heavy=false,age=1,duration=.06,peak=.85,rage=false}
        visual.hitGroups[key]=entry
        local template=visual.hitTemplate
        local texture=visual.world:GetPaletteTexture(domain)
        local surface=template and template:GetSurfaceShader()
        if surface and surface:GetName()==shader and texture then
            local mat=template:Clone('enemy_hit_'..visual.hitMaterialId..'_'..key)
            if mat and mat:SetSurfaceTexture('palette_tex',texture) then
                mat:SetShaderParameter('hit_flash',values.light[0])
                entry.material=mat; visual.hitMaterialCount=visual.hitMaterialCount+1
                visual.flashSupported=true
            end
        end
        if not entry.material and not warned then
            warned=true
            print('EnemyHitMaterial: 模板/调色板纹理绑定失败；保留原材质和白核/姿态反馈，请在 Web 检查 EnemyVoxelHit.shader 编译日志')
        end
        if not logged then
            logged=true
            print('EnemyHitMaterial: palette bank='..bank..' domain='..domain
                ..' original='..(original and original:GetName() or 'nil')
                ..' shader='..(original and original:GetSurfaceShader() and original:GetSurfaceShader():GetName() or 'nil')
                ..' hit_flash='..tostring(entry.material~=false)..' (GPU compile/visibility requires Web)')
        end
    end
    if entry.material then volume:SetMaterial(entry.material) end
    return entry,original
end
function HitMaterial.Value(age,duration,peak)
    if age>=duration then return 0 end
    local hold=math.min(1/60,duration/3)
    local u=math.max(0,(age-hold)/(duration-hold))
    return peak*(1-u)^2
end
function HitMaterial.Start(visual,part,heavy)
    local group=HitMaterial.Group(visual.config,part)
    for _,entry in pairs(visual.hitGroups) do
        if entry.name==group then
            entry.age,entry.duration,entry.peak,entry.heavy=0,heavy and .08 or .06,heavy and 1 or .85,heavy
            entry.level=8
            if entry.material then entry.material:SetShaderParameter('hit_flash',(heavy and values.heavy or values.light)[8]) end
        end
    end
end
function HitMaterial.Update(visual,realDt,clear)
    for _,entry in pairs(visual.hitGroups) do
        entry.age=clear and entry.duration or entry.age+realDt
        local f=HitMaterial.Value(entry.age,entry.duration,entry.peak)
        local level=math.min(8,math.floor(f/entry.peak*8+.5))
        if level~=entry.level then
            entry.level=level
            if entry.material then entry.material:SetShaderParameter('hit_flash',(entry.heavy and values.heavy or values.light)[level]) end
        end
    end
end
-- Separate rage layer: ordinary hit flashes cannot restart/clear the boss transition.
function HitMaterial.Rage(visual,active)
    for _,entry in pairs(visual.hitGroups) do
        local lit=active and (entry.name=='back_armor' or entry.name=='core') or false
        if lit~=entry.rage then
            entry.rage=lit
            if entry.material then entry.material:SetShaderParameter('rage_glow',values.heavy[lit and 8 or 0]) end
        end
    end
end
return HitMaterial
