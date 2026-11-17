package.path='scripts/?.lua;'..package.path
local Catalog=require('combat.WeaponCatalog')
local Builder=require('combat.WeaponBuilder')
assert(Catalog.Slots==nil and Catalog.Presets==nil and Catalog.All==nil)
for _,weapon in ipairs({'sword','bow'}) do
    local definition=Catalog.Definitions[weapon]
    for _,channel in ipairs(Catalog.Channels) do
        for i=1,#Catalog.ColorPresets do
            local config=Catalog.DefaultWeapon(weapon);config.weapon=weapon;config.colors[channel]=i
            local mesh=assert(Builder.Compile(config))
            assert(mesh.stats==definition.stats and mesh.hit==definition.hit)
            assert(mesh.config.parts==nil)
            if weapon=='bow' then assert(mesh.config.colors[channel]==definition.colors[channel]) end
        end
    end
    local bad=Catalog.DefaultWeapon(weapon);bad.colors.primary=1.5
    assert(not Catalog.ValidateWeapon(weapon,bad))
    bad.colors.primary=0/0;assert(not Catalog.ValidateWeapon(weapon,bad))
    bad=Catalog.DefaultWeapon(weapon);bad.appearance='unknown'
    assert(not Catalog.ValidateWeapon(weapon,bad))
end
print('weapon_data: fixed class stats/hit, appearance isolation, original bow palette PASS')
