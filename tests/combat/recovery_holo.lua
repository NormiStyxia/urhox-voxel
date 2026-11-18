-- Long-press heavy, cancellable recovery (move/sprint/jump/next stage), low-guard
-- rest pose, and the wing sword's in-place hologram dissolve/reform on stow/draw.
local S=dofile('tests/combat/core_support.lua')
local A=require('combat.CombatAnim')
local State=require('combat.CombatState')
local C=require('combat.CombatMoves')
local D=require('combat.AnimClips')
local rig={SetActive=function()end,SetPose=function()end,GetStats=function()return {attack=10,speed=1,reach=1,poise=6}end}
local function New()
    State.Configure{rig=rig};State.Enter();State.FinishTransition();State.Activity(true)
    return C.New{anim=A.New(S.anim.character(),nil),state=State,rig=rig,
        forward=function()return Vector3.FORWARD end,position=function()return Vector3.ZERO end,enemies=function()return {}end}
end
local function run(m,seconds,controls)
    for _=1,math.ceil(seconds/.01) do m:Update(.01,controls or {allowed=true}) end
end
-- 1) Sword heavy is a long press of attack: no right button, no charge levels.
local m=New()
run(m,.6,{allowed=true,heavy=true});assert(m.clip==nil,'right button does nothing for the sword')
m=New();m:Update(.01,{allowed=true,attack=true});assert(m.clip=='sword_heavy_charge','press starts the windup')
run(m,.15,{allowed=true,attack=true});m:Update(.01,{allowed=true,attack=false})
assert(m.clip=='sword_light_1','short press is a light attack')
m=New();m:Update(.01,{allowed=true,attack=true});run(m,.42,{allowed=true,attack=true})
assert(m.clip=='sword_heavy_release','holding fires the cross slash without a release')
-- Mid-combo long press queues the cross slash after the current stage.
m=New();m:Update(.01,{allowed=true,attackTap=true});assert(m.clip=='sword_light_1')
m:Update(.01,{allowed=true,attack=true});run(m,.30,{allowed=true,attack=true})
assert(m.clip=='sword_light_1' and m.buffer~='heavy','not yet a long press')
run(m,.12,{allowed=true,attack=true});assert(m.clip=='sword_heavy_release','long press cuts into the cross slash at the cancel window')
-- Stamina: an unaffordable cross slash falls back to a light stage.
m=New();m.stamina.value=10;m:Update(.01,{allowed=true,attack=true});run(m,.42,{allowed=true,attack=true})
assert(m.clip=='sword_light_1' and m.stamina.value<25 and m.stamina.denyAt>0,'no stamina, no cross slash (bar flashes)')
-- 2) Recovery is inertia: idle plays it out, any intent ends it.
for stage,row in ipairs(D.Combo) do
    local clip=D.Clips[row.id];local open=clip.events[3].t*clip.dur
    assert(clip.dur-open>=.40,'stage '..stage..' keeps a visible recovery tail')
    for _,input in ipairs({{allowed=true,axis=Vector3.RIGHT},{allowed=true,runIntent=true},
        {allowed=true,jump=true,onGround=true}}) do
        m=New();m.combo=stage-1;assert(m:Action('light') and m.clip==row.id)
        run(m,open-.03);assert(m.clip==row.id and not m.cancelOpen,'locked before cancel_open')
        m:Update(.01,{allowed=true,axis=Vector3.RIGHT})
        if not input.jump then assert(m.clip==row.id,'movement cannot cut the strike itself') end
        run(m,.04)
        m:Update(.01,input);assert(m.clip==nil and m:MoveScale()==1,'intent ends recovery at once')
    end
    m=New();m.combo=stage-1;assert(m:Action('light'));run(m,open+.02)
    assert(m.clip==row.id,'idle keeps the follow-through')
    if stage<#D.Combo then
        m:Update(.01,{allowed=true,attackTap=true});assert(m.clip==D.Combo[stage+1].id,'next stage cuts recovery')
    end
end
-- Moving out of recovery keeps the chain; jumping resets it.
m=New();assert(m:Action('light'));run(m,.35);m:Update(.01,{allowed=true,axis=Vector3.RIGHT})
assert(m.clip==nil and m.combo==1);run(m,.10);assert(m:Action('light') and m.clip=='sword_light_2')
-- 3) 收招与持剑站姿必须用同一低位握点，攻击层淡出不能再把手抬平。
local function tipDown(id)
    return A.DebugSample(id,D.Clips[id].dur*.98)._ik.arm_right.authored
end
local stance=D.Clips.stance_combat_sword
local guard=A.DebugSample(stance.id,0)._ik.arm_right.authored
for _,row in ipairs(D.Combo) do
    local hand=tipDown(row.id)
    for i=1,3 do assert(math.abs(hand[i]-guard[i])<.02,'low guard matches stance: '..row.id) end
end
assert(stance and stance.additive and stance.weapon[1].euler[1]>30,'sword stance tilts the blade forward-down')
-- 连段继承实际呈现姿态，不是共享 ready，更不改变原命中弧和事件。
local function track(anim,handle)
    for _,s in ipairs(anim.tracks) do if s.handle==handle then return s end end
    error('missing track')
end
local function distance(a,b)
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)
end
local function rotationDistance(a,b)
    return math.deg(2*math.acos(math.min(1,math.abs(a.w*b.w+a.x*b.x+a.y*b.y+a.z*b.z))))
end
local function render(anim,character)
    S.anim.reset(character);anim:Apply();anim:Poll()
end
for _,fps in ipairs({30,60,120}) do
    for stage=1,#D.Combo-1 do
        local character=S.anim.character();local anim=A.New(character,nil,{quantize=false})
        m=New();m.anim=anim;m.combo=stage-1
        assert(m:Action('light'));run(m,D.Clips[m.clip].events[3].t*D.Clips[m.clip].dur+.01)
        render(anim,character)
        local old=m.handle;local source=track(anim,old)
        local hand=source.ik.arm_right.applied
        local body,arm=character.bones.body.rotation,character.bones.arm_right.rotation
        local e=anim.weaponEuler
        local blade=arm*anim.gripRotation*Quaternion(e.x,e.y,e.z)*Vector3(0,1,0)
        assert(m:Action('light') and m.clip==D.Combo[stage+1].id)
        local fresh=track(anim,m.handle)
        assert(fresh.entry.enabled,'entry inheritance enabled on actual combo route')
        assert(distance(fresh.entry.hand,hand)<1e-7,'entry stores rendered grip, not authored oversized target')
        assert(distance(fresh.entry.blade,blade)<1e-7,'entry stores displayed blade direction')
        assert(source.fadeOut==fresh.fadeIn and fresh.fadeIn==.08,'matched fade avoids base-pose leak')
        anim:Update(0);render(anim,character)
        assert(rotationDistance(character.bones.body.rotation,body)<1e-5,'no body reset at entry')
        assert(rotationDistance(character.bones.arm_right.rotation,arm)<1e-5,'no arm reset at entry')
        m:Update(1/fps,{allowed=true});render(anim,character)
        local total=0
        for _,s in ipairs(anim.ordered) do if s.live and s.clip.layer==D.Layer.ATTACK then total=total+s.weight end end
        assert(math.abs(total-1)<1e-7,'no fixed stance exposed mid-combo')
        -- 预备段最终接回原 windup，进入命中弧后与独立播放完全一致。
        local id=m.clip;local contact=D.Clips[id].phases.active[1]+.02
        local freshTime=fresh.t
        m:Update(contact-freshTime,{allowed=true});render(anim,character)
        local standalone=S.anim.character();local expected=A.New(standalone,nil,{quantize=false})
        expected:Play(id,{fadeIn=0});expected:Update(contact);render(expected,standalone)
        assert(rotationDistance(character.bones.arm_right.rotation,standalone.bones.arm_right.rotation)<1e-5,'authored strike unchanged')
        assert(rotationDistance(character.bones.body.rotation,standalone.bones.body.rotation)<1e-5,'authored torso contact unchanged')
    end
end
-- 低位 stance 已有剑向时，极小的出招权重不能立刻抢走整个剑向。
for _,id in ipairs({'sword_light_1','sword_heavy_charge'}) do
    local character=S.anim.character();local anim=A.New(character,nil,{quantize=false})
    anim:Play(stance.id,{fadeIn=0});anim:Update(.1);render(anim,character)
    local before=anim.bladeDirection
    anim:Play(id,{fadeIn=.08});anim:Update(.000001);render(anim,character)
    assert(distance(anim.bladeDirection,before)<.001,'tiny entry weight must not snap blade from guard')
end
-- 首刀短按的抬剑识别姿态也平滑交给轻击；长按交叉斩保持原输入。
local character=S.anim.character();local anim=A.New(character,nil,{quantize=false})
m=New();m.anim=anim;m:Update(.01,{allowed=true,attack=true});run(m,.12,{allowed=true,attack=true})
render(anim,character);local charge=m.handle;m:Update(.01,{allowed=true,attack=false})
assert(m.clip=='sword_light_1' and track(anim,m.handle).entry.enabled and track(anim,charge).stopping,'short tap inherits windup')
-- 持械基础层即使每帧仍写前举角，收招后也必须留在低位，而不是图中的平举。
for _,row in ipairs(D.Combo) do
    local character=S.anim.character();local anim=A.New(character,nil,{quantize=false})
    anim:Play(stance.id,{fadeIn=0});anim:Play(row.id,{fadeIn=0})
    anim:Update(D.Clips[row.id].dur+.1);render(anim,character)
    local settled=character.bones.arm_right.rotation
    for _=1,3 do
        S.anim.reset(character);character.bones.arm_right.rotation=Quaternion(-80,0,8)
        anim:Update(.1);anim:Apply();anim:Poll()
        assert(rotationDistance(character.bones.arm_right.rotation,settled)<1e-5,'no raised base arm after recovery')
        local e=anim.weaponEuler
        local blade=character.bones.arm_right.rotation*anim.gripRotation*Quaternion(e.x,e.y,e.z)*Vector3(0,1,0)
        assert(blade.y<-.75,'resting blade stays down')
    end
end
-- 4) Hologram: dissolve/reform in place, never fly through the body.
local Mock=require('weapon_mock')
local Rig=require('combat.WeaponRig')
rawset(_G,'WING_MATERIAL_MISSING',nil)
local scene=Mock.Node('scene') --[[@as any]]
local r=Rig.New(scene,Mock.World(scene),Mock.Nomi(scene))
local wing=r.entries.sword.wing
assert(wing and wing.holoNode and wing.holoMaterial,'hologram twin built')
local function frames(n) for _=1,n do r:Update(1/60) end end
r:SetPose('back');frames(30);assert(r.visualState=='hang')
r:SetPose('hand');assert(r.transition.holo and r.visualState=='fly_to_hand')
local pivot=r.entries.sword.pivot
local back=r.sockets.back_sword
local sawHolo,sawSolidGone=false,false
for _=1,40 do
    r:Update(1/60)
    if r.transition then
        assert(pivot.parent==back or pivot.parent==r.sockets.hand_right,'pivot always rides a socket')
        if wing.holoNode.enabled then sawHolo=true end
        if not wing.node.enabled then sawSolidGone=true end
    end
end
assert(sawHolo and sawSolidGone,'blade turns to projection then breaks up')
assert(r.visualState=='hand' and pivot.parent==r.sockets.hand_right and wing.node.enabled and not wing.holoNode.enabled)
local events=r:PopEvents();local drew=false
for _,e in ipairs(events) do if e=='blade_draw' then drew=true end end
assert(drew,'arrival still emits blade_draw for sound/flash')
r:SetPose('back');local first=true
for _=1,40 do
    r:Update(1/60)
    if r.transition and first then assert(pivot.parent==r.sockets.hand_right,'dissolves at the hand first');first=false end
end
assert(r.visualState=='hang' and pivot.parent==back and wing.node.enabled and not wing.holoNode.enabled)
r:SetPose('hidden');frames(40);assert(r.visualState=='hidden' and not wing.node.enabled and not wing.holoNode.enabled)
r:Dispose();assert(r.entries.sword.wing==nil)
rawset(_G,'WING_MATERIAL_MISSING',true)
print('PASS long-press cross slash, cancellable recovery, low guard rest, hologram stow/draw in place')
