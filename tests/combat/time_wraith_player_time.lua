-- Player-side local time-field regression. Lua 5.4/Lupa only.
package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')
local Base=require('combat.enemies.EnemyBase')
local Wraith=require('combat.enemies.actors.TimeWraith')
local Field=require('combat.enemies.actors.TimeWraithField')

local terrain,combat=T.Fixture()
local w=Wraith.New(nil,nil,terrain,combat,Vector3.ZERO,'time_field')
local center=Vector3(0,0,0)
assert(w:GetPlayerTimeScale(center)==1,'pre-blink telegraph must not slow the player')
-- Use the actor's real attack selection, telegraph and BeginAttack path.
w:SetActive(true); w.aggro=true; w.attackIndex=1; w:Face(center)
assert(w:StartAttack(),'time-field attack did not enter telegraph')
assert(w.fieldStage=='warn' and w:GetPlayerTimeScale(center)==1,'warning stage must not slow the player')
T.Tick(w,w.attack.telegraph+.02,center)
assert(w.fieldStage=='active','time-field cast did not activate its domain')
assert(w:GetPlayerTimeScale(center)==.5,'player inside the active ring must be slowed')
assert(w:GetPlayerTimeScale(Vector3(0,0,Field.radius))==.5,'ring edge uses the authored visible radius')
assert(w:GetPlayerTimeScale(Vector3(0,0,Field.radius+.01))==1,'outside the ring must remain normal')
w:Stagger(1,false); assert(w:GetPlayerTimeScale(center)==1,'frozen field must restore normal speed')
w:SetActive(false); assert(w:GetPlayerTimeScale(center)==1,'inactive field must restore normal speed')
w:SetActive(true); w.dead=true; assert(w:GetPlayerTimeScale(center)==1,'dead field must restore normal speed')
w:Destroy()

-- CombatMoves consumes the same scale for the authored attack clock.
local Support=dofile('tests/combat/core_support.lua')
local State=require('combat.CombatState')
local Anim=require('combat.CombatAnim')
local Moves=require('combat.CombatMoves')
local rig={pose='hand',SetPose=function(self,p)self.pose=p end,SetActive=function()end,
    GetStats=function()return {attack=10,poise=6,speed=1,draw=.7,reach=1}end}
local function make(scale)
    State.ResetIsolation(); State.Configure{rig=rig,explicitSelection=true,log=function()end}
    assert(State.Enter('loadout')); State.FinishTransition(); assert(State.SetWeapon('sword')); State.FinishTransition(); State.Activity(true)
    local moves=Moves.New{anim=Anim.New(Support.anim.character(),nil),state=State,rig=rig,
        position=function()return Vector3.ZERO end,forward=function()return Vector3.FORWARD end,
        enemies=function()return {}end}
    assert(moves:Action('light'))
    local controls={allowed=true,onGround=true,attack=false,heavy=false,axis=Vector3.ZERO,playerTimeScale=scale}
    for _=1,10 do moves:Update(.02,controls) end
    return moves
end
local normal=make(1); local slow=make(.5)
assert(slow.anim.poseClock<normal.anim.poseClock*.7,'time field did not slow the real attack animation clock')
assert(slow.clip~=nil and normal.clip~=nil,'both attacks must remain live at the comparison point')

-- Exercise the final NomiController methods with the same scale that RuinsScene
-- passes on each frame.  This is the real Move/SetPlayerTimeScale body loaded
-- from the shipped controller, with only the documented controller ports mocked
-- by the offline harness.  Integrating desiredVelocity gives a repeatable
-- player-distance measurement, while the gravity loop uses the native factor.
local S=dofile('tests/combat/core_support.lua')
local nomiFile=assert(io.open('scripts/ruins/NomiController.lua'))
local nomiSource=nomiFile:read('*a'); nomiFile:close()
local function method(name,nextName)
    local start=assert(nomiSource:find('function N:'..name,1,true))
    local finish=nextName and assert(nomiSource:find('function N:'..nextName,start+1,true))
    return nomiSource:sub(start,(finish and finish-1) or #nomiSource)
end
local Nomi={}
local nomiEnv=setmetatable({N=Nomi,WALK=4.2,RUN=7.2,SPRINT=10,JUMP=6.4,
    AIR_CONTROL=.35,COYOTE_TIME=.12,JUMP_BUFFER=.12,
    Clamp=function(v,a,b)return math.max(a,math.min(b,v))end,
    WrapDeg=function(a)return (a+180)%360-180 end,
    Quaternion=function(yaw)return {yaw=yaw}end,
    Terrain={HasGround=function()return true end}}, {__index=_G})
assert(load(method('SetPlayerTimeScale','HandPos'), 'actual Nomi SetPlayerTimeScale', 't', nomiEnv))()
assert(load(method('ResetJump','UpdateJump'), 'actual Nomi ResetJump', 't', nomiEnv))()
assert(load(method('UpdateJump','Move'), 'actual Nomi UpdateJump', 't', nomiEnv))()
assert(load(method('Move','SlideRay'), 'actual Nomi Move', 't', nomiEnv))()
local function newNomi()
    local cc={onGround=true,gravityFactor=1,linear=Vector3.ZERO,desiredVelocity=Vector3.ZERO}
    function cc:GetLinearVelocity()return self.linear end
    function cc:SetLinearVelocity(v)self.linear=v end
    function cc:Jump()error('jump not requested during this measurement')end
    local n=setmetatable({cc=cc,node={worldPosition=Vector3.ZERO},camYaw=0,yaw=0,vel=Vector3.ZERO,
        baseGravityFactor=1,playerTimeScale=1,timeSlowGravityDebt=0,
        UpdateSafety=function()return false end},{__index=Nomi})
    return n
end
local function walkDistance(scale)
    local n=newNomi(); n:SetPlayerTimeScale(scale,0)
    local distance=0
    for _=1,120 do
        n:Move(1/60,1,0,false,false,false,{playerTimeScale=scale,scale=1,baseSpeed=5,motion=Vector3.ZERO,motionChecked=true})
        distance=distance+n.cc.desiredVelocity.z/60
    end
    return distance,n
end
local normalDistance=walkDistance(1)
local slowDistance=walkDistance(.5)
assert(normalDistance>slowDistance*1.8,'real Nomi run distance did not slow inside field')
assert(slowDistance>normalDistance*.35,'real Nomi movement was over-slowed')

-- Apply the controller's native gravity factor while falling, then leave the
-- field.  The authored debt correction restores the equivalent full-gravity
-- vertical velocity without a second multiplier or stale field state.
local falling=newNomi(); falling.cc.onGround=false
local dt=.1
for _=1,10 do
    falling:SetPlayerTimeScale(.5,dt)
    local v=falling.cc:GetLinearVelocity()
    falling.cc:SetLinearVelocity(Vector3(v.x,v.y-9.81*falling.cc.gravityFactor*dt,v.z))
end
local slowedFall=falling.cc:GetLinearVelocity().y
falling:SetPlayerTimeScale(1,0)
local recoveredFall=falling.cc:GetLinearVelocity().y
assert(math.abs(slowedFall+4.905)<.02,'field gravity did not halve falling acceleration')
assert(math.abs(recoveredFall+9.81)<.03,'leaving field did not restore full-gravity vertical velocity')
assert(falling.cc.gravityFactor==1 and falling.timeSlowGravityDebt==0,'field exit left gravity debt')

print(string.format('PASS TimeWraith player field: center=.5 edge=authored, inactive/dead=1, Nomi distance normal=%.3fm slow=%.3fm, fall vy slow=%.3f restored=%.3f, attack clocks normal=%.3f slow=%.3f',
    normalDistance,slowDistance,slowedFall,recoveredFall,normal.anim.poseClock,slow.anim.poseClock))
