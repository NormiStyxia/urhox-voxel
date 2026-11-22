-- Exercise actual Scene input and sigil presentation without a renderer.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
require('weapon_mock')
local function Read(path)
    local f=assert(io.open(path));local source=f:read('*a');f:close();return source
end
local scene=Read('scripts/ruins/RuinsScene.lua')
local State=require('combat.CombatState')
State.Configure{explicitSelection=true,log=function()end}
local mouse,shatter,casts,charges=false,false,{},0
local pressed={}
local caster={charging=false,charge=0,castAnim=0}
function caster:Ready()return true end
function caster:Cast(id)casts[#casts+1]=id;self.lastCast=id;self.castAnim=.35 end
function caster:HandleCharge(held)charges=charges+1;self.charging=held end
local env=setmetatable({M={mounted=false},caster_=caster,CombatState=State,
    animPreview_={index=0},time_=10,KEY_E='e',KEY_R='r',KEY_Q='q',MOUSEB_LEFT=1,
    Press=function(key)local p=pressed[key];pressed[key]=nil;return p end,
    input={focus=true,GetMouseButtonDown=function()return mouse end},
    pointer={CanAttack=function()return true end,IsEnabled=function()return true end},
    WeaponWheel={IsBlocked=function()return false end},ForgePanel={IsOpen=function()return false end},
    SettingsMenu={IsBlocked=function()return false end},TouchControls={IsBlocked=function()return false end},
    TouchInput={IsEnabled=function()return false end,Down=function()return shatter end,Press=function()return false end}},
    {__index=_G})
local nl=string.char(10)
local inputBody=assert(scene:match('(local function HandleSpells.-)'..nl..'function Ruins_HandleSceneUpdate'))
local input=assert(load(inputBody..nl..'return HandleSpells','Scene spell input','t',env))()
local function Shape()return {node={enabled=false}}end
local sigils={age=0,target=Shape(),hand=Shape(),range=Shape(),impacts={}}
local S={}
local sigilEnv=setmetatable({S=S,Show=function(shape)shape.node.enabled=true end,
    -- Rotation values are irrelevant to the visibility assertions.
    Quaternion=function()return _G.Quaternion()end},{__index=_G})
local update=assert(Read('scripts/ruins/TimeSigil.lua'):match('(function S:Update.-)'..nl..'return M'))
assert(load(update,'TimeSigil actual update','t',sigilEnv))()
local aim={hit=true,breakable=true,pos=Vector3(0,0,4),normal=Vector3.UP,dir=Vector3.FORWARD}
local camera={worldPosition=Vector3(0,1,0),worldRotation=Quaternion()}
env.M.sigils=sigils;env.dt=.016;env.aim=aim
env.nomi_={HandPos=function()return Vector3.ZERO end,CameraNode=function()return camera end}
env.Spells={ShatterRadius=function()return 2 end}
env.Safe=function(_,fn,...)return fn(...)end
sigils.Update=S.Update
local sigilLine
for line in scene:gmatch('[^'..nl..']+')do
    if line:find("Safe('FX.Sigils'",1,true)then sigilLine=line;break end
end
local present=assert(load(assert(sigilLine),'Scene sigil presentation','t',env))
for _,weapon in ipairs({'sword','bow'})do
    State.SetBusy(false);State.FinishTransition();assert(State.SetWeapon(weapon))
    assert(State.Enter('loadout'));State.FinishTransition()
    mouse,shatter=true,true;caster.charging,caster.charge=true,.7
    input(.016,aim)
    assert(not caster.charging and caster.charge==0 and charges==0 and #casts==0,weapon..' cannot charge shatter')
    mouse,shatter=false,false;caster.castAnim=0
    present()
    assert(not sigils.target.node.enabled,weapon..' must not display passive time targeting')
    assert(not sigils.hand.node.enabled and not sigils.range.node.enabled,weapon..' has no casting circles at rest')
    -- Guard against stale shatter presentation after switching equipment.
    caster.charging,caster.charge,caster.castAnim,caster.lastCast=true,1,.3,'shatter'
    present()
    assert(not sigils.hand.node.enabled and not sigils.range.node.enabled,weapon..' must not display stale shatter charge')
    caster.charging,caster.charge,caster.castAnim=false,0,0
    for _,spell in ipairs({'freeze','rewind'})do
        pressed[spell=='freeze' and 'e' or 'r']=true;input(.016,aim)
        assert(casts[#casts]==spell,weapon..' keeps portable '..spell)
        present()
        assert(sigils.hand.node.enabled and not sigils.target.node.enabled,spell..' retains its explicit cast feedback')
        caster.castAnim=0
    end
    casts={}
end
State.Exit('loadout');mouse=true;input(.016,aim);present()
assert(caster.charging and charges==1 and sigils.target.node.enabled and sigils.hand.node.enabled and sigils.range.node.enabled,
    'time selection retains targeting, hand circle and charge range')
print('PASS time sigil routing: sword/bow reject shatter and passive/stale circles; E/R feedback and time charge preserved')
