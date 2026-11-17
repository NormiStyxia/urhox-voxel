package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local Rig=require('combat.WeaponRig')
local Store=require('combat.WeaponStore')
local State=require('combat.CombatState')
local Loadout=require('combat.WeaponLoadout')
WING_MATERIAL_MISSING=nil
local scene=Mock.Node('scene')
local world=Mock.World(scene)
local rig=Rig.New(scene,world,Mock.Nomi(scene))
State.Configure{rig=rig}
local saves=0
Store.Save=function(config) saves=saves+1;assert(config.version==2 and not config.sword.parts);return true end
local draft=Store.Normalize(rig.config)
draft.sword.colors.accent=6;draft.active='bow'
local wing=rig.entries.sword.wing
assert(wing,'exercise real material transactions')
local oldMaterial,oldCrystal=wing.material,wing.crystal
local oldBlueprint=rig.entries.sword.mesh.blueprint
local oldTrail=rig.trailColors.sword
local beforeCreated,beforeBuilds=world.created,world.rebuilds
State.SetBusy(true)
assert(not Loadout.Commit(rig,draft,State))
assert(saves==0 and wing.material==oldMaterial and rig.active=='sword')
State.SetBusy(false)
-- Second appearance fails after sword recolour. Also make any subsequent Clone
-- fail, proving rollback rebinds retained handles instead of allocating resources.
local apply=rig.ApplyAppearance
local clone=oldMaterial.Clone
rig.ApplyAppearance=function(self,config,deferred)
    if config.weapon=='bow' then
        wing.material.Clone=function() error('persistent resource failure') end
        oldMaterial.Clone=function() error('persistent resource failure') end
        return false,'injected second item failure'
    end
    return apply(self,config,deferred)
end
assert(not Loadout.Commit(rig,draft,State))
assert(saves==0 and wing.material==oldMaterial and wing.crystal==oldCrystal)
assert(rig.entries.sword.mesh.blueprint==oldBlueprint and rig.trailColors.sword==oldTrail)
assert(rig.config.sword.colors.accent==2 and rig.active=='sword')
oldMaterial.Clone=clone;rig.ApplyAppearance=apply
-- A late selection refusal restores the same resources and does not save.
local setWeapon=State.SetWeapon
State.SetWeapon=function()return false end
assert(not Loadout.Commit(rig,draft,State))
assert(saves==0 and wing.material==oldMaterial and rig.entries.sword.mesh.blueprint==oldBlueprint)
State.SetWeapon=setWeapon
-- Recolour preparation failure leaves old visual and config intact.
oldMaterial.Clone=function()error('clone failed')end
assert(not Loadout.Commit(rig,draft,State))
assert(saves==0 and wing.material==oldMaterial and rig.config.sword.colors.accent==2)
oldMaterial.Clone=clone
local committed,message,persisted=Loadout.Commit(rig,draft,State)
assert(committed and message==nil and persisted==true)
assert(saves==1 and rig.active=='bow' and State.GetWeapon()=='bow')
assert(rig.config.sword.colors.accent==6 and wing.material~=oldMaterial)
assert(world.created==beforeCreated and world.rebuilds==beforeBuilds,'cosmetics must not rebuild volumes')
State.FinishTransition()
Store.Save=function()saves=saves+1;return false end
local nextDraft=Store.Normalize(rig.config);nextDraft.sword.colors.accent=5
local ok,notice,saved=Loadout.Commit(rig,nextDraft,State)
assert(ok and notice and saved==false and saves==2 and rig.config.sword.colors.accent==5)
State.Stop();rig:Dispose()
assert(world.created==world.removed)
print('PASS equipment transaction: real Rig/State, preflight, second-item failure, retained-material rollback, late rejection, single save, save failure, geometry reuse')
