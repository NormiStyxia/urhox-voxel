-- The only owner of an equipment transaction: validate, apply, select, save once.
local Catalog=require('combat.WeaponCatalog')
local Store=require('combat.WeaponStore')
local M={}
local function Single(config,weapon)
    local appearance=Catalog.CopyAppearance(weapon,config[weapon])
    appearance.weapon=weapon
    return appearance
end
function M.Commit(rig,draft,state)
    local config=Store.Normalize(draft)
    local previous=rig and Store.Normalize(rig.config)
    if not config or not previous then return false,'装备配置无效' end
    if not state.CanSetWeapon(config.active) then return false,'暂时无法切换武器' end
    config.progress=previous.progress -- live purchases and loot survive older cosmetic drafts
    local applied={}
    local function Rollback(reason)
        for i=#applied,1,-1 do
            local ok,err=pcall(applied[i].Rollback)
            if not ok then reason=reason..'; rollback: '..tostring(err) end
        end
        return false,reason
    end
    for _,weapon in ipairs({'sword','bow'}) do
        local called,ok,err,transaction=pcall(rig.ApplyAppearance,rig,Single(config,weapon),true)
        if not called then return Rollback(tostring(ok)) end
        if not ok then return Rollback(err or '外观未能应用') end
        if transaction then applied[#applied+1]=transaction end
    end
    if not state.SetWeapon(config.active) then return Rollback('暂时无法切换武器') end
    rig:SetActive(config.active)
    rig:SetPose(state.GetPose())
    rig.config=config
    for _,transaction in ipairs(applied) do transaction.Commit() end
    local saved=Store.Save(config)
    if not saved then return true,'配置已应用，本次未能保存',false end
    return true,nil,true
end
return M
