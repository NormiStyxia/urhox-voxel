-- Run from project root with Lua 5.4: lua tests/combat/anim_spec.lua
-- Or python3 + lupa.lua54 (no UrhoX runtime, assets, scene or network required).
package.path="scripts/?.lua;tests/combat/?.lua;"..package.path
assert(_VERSION=="Lua 5.4","requires Lua 5.4")
local Mock=require("anim_mock")
local A=require("combat.CombatAnim")
local D=require("combat.AnimClips")
local passed=0
local function test(name,fn) fn();passed=passed+1;print("PASS "..name) end
local function near(a,b,e) assert(math.abs(a-b)<(e or 1e-8),tostring(a).." != "..tostring(b)) end
local function sameRotation(a,b)
    near(math.abs(a.w*b.w+a.x*b.x+a.y*b.y+a.z*b.z),1,1e-7)
end
local function new(opts)
    local c=Mock.character()
    return A.New(c,nil,opts or {quantize=false}),c
end
local function names(events)
    local s=""
    for _,e in ipairs(events) do s=s..e.name.."," end
    return s
end
local function state(anim,handle)
    for _,s in ipairs(anim.tracks) do if s.handle==handle then return s end end
    error("missing handle")
end

test("bone axis derivation",function()
    local x,y,z=Mock.rotate(Quaternion(-90,0,0),0,-1,0);near(z,1);near(y,0)
    x,y,z=Mock.rotate(Quaternion(0,0,90),0,-1,0);near(x,1)
    x,y,z=Mock.rotate(Quaternion(0,90,0),0,0,1);near(x,1)
    x,y,z=Mock.rotate(Quaternion(90,0,0),0,1,0);near(z,1)
end)
test("all active clips have complete, ordered tracks and matching event windows",function()
    assert(#A.DebugList()==29)
    for _,item in ipairs(A.DebugList()) do
        local c=D.Clips[item.id]
        assert(c.id==item.id and c.dur>0 and c.root and c.weapon and c.events and c.motion)
        for _,track in pairs(c.keys) do
            assert(#track==6 and track[1][1]==0 and track[#track][1]==1)
            for i=2,#track do assert(track[i][1]>track[i-1][1]) end
        end
        -- Active phase spans the first hit_on to the last hit_off (cross slash has two windows).
        local previous,firstOn,lastOff=-1,nil,nil
        for _,event in ipairs(c.events) do
            assert(event.t>=previous and event.t<=(c.eventDur or c.dur)/c.dur);previous=event.t
            if event[1]=="hit_on" then firstOn=firstOn or event.t*c.dur end
            if event[1]=="hit_off" then lastOff=event.t*c.dur end
        end
        if firstOn then near(c.phases.active[1],firstOn) end
        if lastOff then near(c.phases.active[2],lastOff) end
        for _,m in ipairs(c.motion) do assert(m.t1>m.t0 and m.t0>=0 and m.t1<=c.dur) end
    end
end)
test("events survive a large timestep in order and fire once",function()
    local a=new();a:Play("sword_light_1")
    a:Update(1)
    assert(names(a:Poll())=="hit_on,hit_off,cancel_open,cancel_close,clip_finished,")
    assert(#a:Poll()==0)
    a:Update(1);assert(#a:Poll()==0)
end)
test("events at zero and exact boundary",function()
    local a=new();a:Play("bow_draw")
    a:Update(0);assert(names(a:Poll())=="draw_start,")
    a:Update(.12);assert(names(a:Poll())=="draw_min,")
    a:Update(0);assert(#a:Poll()==0)
end)
test("slow playback and accelerated playback retain exactly one hit",function()
    for _,speed in ipairs({.1,.7,1,1.4,8}) do
        local a=new();a:Play("sword_light_2",{speed=speed})
        local on,off=0,0
        for _=1,math.ceil(.5/speed/.007) do
            a:Update(.007)
            for _,e in ipairs(a:Poll()) do
                if e.name=="hit_on" then on=on+1 elseif e.name=="hit_off" then off=off+1 end
            end
        end
        assert(on==1 and off==1)
    end
end)
test("stats speed is multiplied, timeScale and zero dt pause",function()
    local a=new({stats={speed=1.4},timeScale=.5,quantize=false})
    local h=a:Play("sword_light_1",{speed=2,fadeIn=0})
    a:Update(.05);near(state(a,h).t,.07)
    a:Update(0);near(state(a,h).t,.07)
    a.timeScale=0;a:Update(1);near(state(a,h).t,.07)
    assert(#a:Poll()==0)
end)
test("fade weights and slerp match base-to-pose interpolation",function()
    local a,c=new()
    local h=a:Play("stance_combat",{fadeIn=.1})
    a:Update(.05);near(state(a,h).weight,.5);a:Apply()
    sameRotation(c.bones.body.rotation,Quaternion(3,0,0));near(c.bones.root.position.y,.98)
    a:Stop(h,.1);a:Update(.05);near(state(a,h).weight,.25)
    Mock.reset(c);a:Apply();sameRotation(c.bones.body.rotation,Quaternion(1.5,0,0))
    a:Update(.06);assert(not state(a,h).live)
end)
test("automatic recovery fade reaches zero",function()
    local a=new();local h=a:Play("sword_light_1",{fadeIn=0,fadeOut=.1})
    a:Update(.75);near(state(a,h).weight,.5)
    a:Update(.05);assert(not a:IsPlaying("sword_light_1"));near(state(a,h).weight,0)
end)
test("priority covers stance and cancels offensive tracks",function()
    local a,c=new();a:Play("stance_combat",{fadeIn=0})
    local attack=a:Play("sword_light_1",{fadeIn=0});a:Update(.12);a:Poll()
    local death=a:Play("death",{fadeIn=0});assert(death)
    assert(not a:IsPlaying("sword_light_1"));assert(not a:Play("hit_light"))
    a:Update(.6);a:Apply();sameRotation(c.bones.body.rotation,Quaternion(70,0,0))
    assert(state(a,attack).stopping and a:IsPlaying("stance_combat"))
    a:Stop(death,0);assert(a:Play("getup"))
end)
test("same-layer replacement fades old pose, cancels old events",function()
    local a=new();local old=a:Play("sword_light_1",{fadeIn=0});a:Update(.05)
    local fresh=a:Play("sword_light_2",{fadeIn=.1})
    assert(state(a,old).stopping and state(a,old).live and fresh~=old)
    a:Update(.04);near(state(a,old).weight,.6);near(state(a,fresh).weight,.4)
    for _,e in ipairs(a:Poll()) do assert(e.handle~=old or e.name=="clip_cancelled") end
end)
test("same-layer crossfade does not leak the base pose",function()
    local a,c=new();a:Play("stance_combat",{fadeIn=0});a:Update(.1)
    a:Play("stance_combat",{fadeIn=.1});a:Update(.05);a:Apply()
    sameRotation(c.bones.body.rotation,Quaternion(6,0,0));near(c.bones.root.position.y,.96)
end)
test("stop closes active windows and never emits future fire",function()
    local a=new();local h=a:Play("sword_light_1");a:Update(.18);a:Poll();a:Stop(h,.1)
    assert(names(a:Poll())=="hit_off,clip_cancelled,")
    a:Update(1);assert(#a:Poll()==0)
    h=a:Play("bow_release");a:Stop(h,0);a:Update(.5)
    assert(names(a:Poll())=="clip_cancelled,")
end)
test("stop removes unconsumed hit_on without losing pending hit_off",function()
    local a=new();local h=a:Play("sword_light_1");a:Update(.18);a:Poll()
    a:Update(.15);a:Stop(h,0)
    assert(names(a:Poll())=="hit_off,cancel_close,clip_cancelled,")
    h=a:Play("sword_light_1");a:Update(.18);a:Stop(h,0)
    assert(names(a:Poll())=="hit_off,clip_cancelled,")
end)
test("replay and stale handles",function()
    local a=new();local h=a:Play("bow_release");a:Update(.3);a:Poll()
    local nextHandle=a:Play("bow_release");assert(nextHandle~=h);a:Stop(h,0)
    a:Update(0);assert(names(a:Poll())=="fire,")
end)
test("long-press windup has no charge levels and holds its pose",function()
    local a=new();a:Play("sword_heavy_charge")
    a:Update(9);assert(#a:Poll()==0,"no charge_full event");a:Update(9);assert(#a:Poll()==0)
    local pose=A.DebugSample("sword_heavy_charge",9)
    near(pose.body[2],38)
end)
test("bow parameter drives arm, clamps, and full fires once per play",function()
    local a,c=new();a:Play("bow_hold",{fadeIn=0,params={p=0}});a:Update(0);a:Apply()
    sameRotation(c.bones.arm_right.rotation,Quaternion(table.unpack(A.DebugSample("bow_hold",0).arm_right)))
    a:SetParam("p",.7);Mock.reset(c);a:Update(0);a:Apply()
    local pose=A.DebugSample("bow_hold",.7)
    sameRotation(c.bones.arm_right.rotation,Quaternion(table.unpack(pose.arm_right)))
    a:SetParam("p",2);a:Update(0);assert(names(a:Poll())=="draw_full,")
    a:SetParam("p",0);a:Update(0);a:SetParam("p",1);a:Update(0);assert(#a:Poll()==0)
    assert(a:IsPlaying("bow_hold"))
end)
test("quantized anticipation but continuous active and monotonic recovery",function()
    local a=new({quantize=true});local h=a:Play("sword_light_1",{fadeIn=0})
    a:Update(.10);near(state(a,h).sample*.80,.10)
    a:Update(.07);near(state(a,h).sample*.80,.17);assert(a:Phase()=="active")
    a:Update(.12);assert(state(a,h).sample*.80>=.26);assert(a:Phase()=="recovery")
end)
test("motion totals independent of speed, fades and timestep",function()
    for _,speed in ipairs({.5,1,3}) do
        for _,dt in ipairs({1/144,1/30,.6}) do
            local a=new();a:Play("sword_light_1",{speed=speed})
            local total=0
            for _=1,math.ceil(.6/speed/dt) do total=total+a:GetMotion(dt);a:Poll() end
            near(total,.55)
        end
    end
    local a=new();a:Play("hit_heavy");near(a:GetMotion(1),-.8)
    a=new();a:Play("sword_light_1");near(a:GetMotion(1),.55)
end)
test("cancel stops subsequent motion",function()
    local a=new();local h=a:Play("sword_light_1");assert(a:GetMotion(.20)>0)
    a:Stop(h,.1);near(a:GetMotion(.225),0)
end)
test("Apply fallback, explicit dt avoids double advancement",function()
    local a,c=new();local h=a:Play("sword_light_1")
    c.time=.05;a:Apply();near(state(a,h).t,.05)
    a:GetMotion(.06);c.time=.11;Mock.reset(c);a:Apply();near(state(a,h).t,.11)
end)
test("uncontrolled bones untouched and root offset does not accumulate",function()
    local a,c=new();a:Play("stance_combat",{fadeIn=0})
    for _=1,10 do
        Mock.reset(c);c.bones.cloak.rotation=Quaternion(17,2,3)
        a:Update(.01);a:Apply();near(c.bones.root.position.y,.96)
        sameRotation(c.bones.cloak.rotation,Quaternion(17,2,3))
    end
end)
test("cross slash torso swings left then right, never a full turn",function()
    local id="sword_heavy_release";local dur=D.Clips[id].dur
    assert(A.DebugSample(id,.17).body[2]<-20,"first cut carries the torso left")
    assert(A.DebugSample(id,.44).body[2]>20,"second cut carries it back right")
    for i=0,100 do assert(math.abs(A.DebugSample(id,dur*i/100).body[2])<=45) end
    near(A.DebugSample(id,dur).body[2],0)
end)
test("weapon pose and state buffers reuse tables",function()
    local a,c=new();local ordered,queue,output,pool=a.ordered,a.queue,a.output,a.eventPool
    local track=a.tracks[1];local params=track.params
    a:Play("bow_hold",{fadeIn=0})
    for _=1,100 do
        a:SetParam("p",.5);a:Update(.01);Mock.reset(c);a:Apply()
        assert(a:Poll()==output and a.ordered==ordered and a.queue==queue and a.eventPool==pool)
        assert(a.tracks[1]==track and track.params==params)
        local o,e=a:GetWeaponPose();near(o.x,0);assert(e.y==e.y)
    end
end)
test("death/knockdown hold until explicit replacement; stop all clears",function()
    local a=new();a:Play("death");a:Update(3);assert(a:IsPlaying("death"))
    a:Poll();a:Update(3);assert(#a:Poll()==0)
    a:Stop(nil,0);assert(not a:IsPlaying());assert(a:Play("getup"))
end)
test("invalid inputs do not mutate live animation",function()
    local a=new();a:Play("stance_combat")
    assert(not a:Play("missing"));assert(not a:Play("sword_light_1",{speed=-1}))
    assert(not a:Play("sword_light_1",{fadeIn=0/0}));assert(a:IsPlaying("stance_combat"))
    assert(not pcall(function() a:Update(-.1) end))
end)
test("R1 move timings and cancel windows are authored once",function()
    -- Long recovery tails (inertia + low guard) after an unchanged cancel point.
    local expected={sword_light_1={.80,.19,.29,.35},sword_light_2={.82,.20,.30,.36},
        sword_light_3={.88,.21,.33,.41},sword_light_4={.96,.22,.40,.46},sword_light_5={1.10,.34,.46,.62}}
    for id,v in pairs(expected) do
        local c=D.Clips[id];near(c.dur,v[1]);near(c.phases.active[1],v[2]);near(c.phases.active[2],v[3])
        near(c.events[1].t*c.dur,v[2]);near(c.events[2].t*c.dur,v[3]);near(c.events[3].t*c.dur,v[4])
        near(c.trail[2],v[3]+.06)
    end
    -- Cross slash: two hit windows inside one clip, then a cancellable recovery.
    local cross=D.Clips.sword_heavy_release;near(cross.dur,.96)
    local want={{"hit_on",.10},{"hit_off",.19},{"hit_on",.36},{"hit_off",.46},{"cancel_open",.60},{"cancel_close",.96}}
    for i,e in ipairs(want) do assert(cross.events[i][1]==e[1]);near(cross.events[i].t*cross.dur,e[2],1e-9) end
    near(cross.phases.active[1],.10);near(cross.phases.active[2],.46)
    near(D.Clips.hit_light.dur,.24);near(D.Clips.hit_heavy.dur,.42)
    near(D.Clips.knockdown.dur,.55);near(D.Clips.getup.dur,.45)
end)
test("six attack landmarks, torso .02s ahead and head compensates",function()
    for _,id in ipairs({"sword_light_1","sword_light_2","sword_light_3","sword_light_4","sword_heavy_release"}) do
        local c=D.Clips[id]
        for i=2,5 do
            near((c.keys.arm_right[i][1]-c.keys.body[i][1])*c.dur,.02)
            near(c.keys.head[i][1],c.keys.body[i][1])
        end
        assert(c.keys.head[2][2][2]*c.keys.body[2][2][2]<0)
    end
    local c=D.Clips.sword_light_1
    for i,t in ipairs({0,.114,.19,.25,.29,.80}) do near(c.keys.arm_right[i][1]*c.dur,t) end
end)
test("finisher commits the torso and hips to the downward strike",function()
    local c=D.Clips.sword_light_5
    assert(c.keys.body[4][2][1]>=42,'finisher torso folds forward at contact')
    assert(c.keys.body[5][2][1]>=36,'finisher stays folded through follow-through')
    assert(c.root[4][2]<-.15 and c.root[5][2]<-.12,'finisher hips drop on impact')
    assert(c.keys.leg_left[4][2][1]<=-28 and c.keys.leg_right[4][2][1]>=18,'both legs brace the landing')
    local contact=A.DebugSample('sword_light_5',c.phases.active[1]+.01)
    local settle=A.DebugSample('sword_light_5',.70)
    assert(contact.body[1]>35 and settle.body[1]>20,'downward weight persists after contact')
end)

test("20Hz option and continuous root position",function()
    local a,c=new({quantize=true});local b,d=new({quantize=false})
    near(a.quantizeHz,20)
    a:Play("sword_light_1",{fadeIn=0});b:Play("sword_light_1",{fadeIn=0})
    a:Update(.075);b:Update(.075);a:Apply();b:Apply()
    near(c.bones.root.position.y,d.bones.root.position.y)
    local custom=new({quantizeHz=24});near(custom.quantizeHz,24)
    local disabled=new({quantizeHz=0});assert(not disabled.quantize)
end)
test("getup protection outlives pose and does not block new attacks",function()
    local a=new();a:Play("getup");a:Update(0);assert(names(a:Poll())=="protect_on,")
    a:Update(.45);assert(names(a:Poll())=="clip_finished,")
    assert(not a:IsPlaying("getup"));assert(a:Phase("getup")==nil)
    assert(a:Play("sword_draw"));a:Update(.149)
    local events=names(a:Poll());assert(not events:find("protect_off",1,true))
    a:Update(.001);assert(names(a:Poll())=="protect_off,")
    a:Update(1);assert(not names(a:Poll()):find("protect_off",1,true))
end)
test("getup event tail on large delta and explicit stop closes it",function()
    local a=new();local h=a:Play("getup");a:Update(1)
    assert(names(a:Poll())=="protect_on,clip_finished,protect_off,")
    h=a:Play("getup");a:Update(.45);a:Poll();a:Stop(h,0)
    assert(names(a:Poll())=="protect_off,clip_cancelled,")
    a:Update(1);assert(#a:Poll()==0)
end)
test("protection clocks keep advancing through pose hitstop",function()
    local a=new();a:Play("getup");a:Update(.1);a:Poll()
    a:Update(0,.51)
    assert(names(a:Poll()):find("protect_off",1,true))
end)
test("bow minimum draw, full threshold, and shot recovery boundary",function()
    local a=new();a:Play("bow_draw");a:Update(.119)
    assert(names(a:Poll())=="draw_start,")
    a:Update(.001);assert(names(a:Poll())=="draw_min,")
    a:Play("bow_hold",{params={p=.999}});a:Poll();a:Update(0);assert(#a:Poll()==0)
    a:SetParam("p",1);a:Update(0);assert(names(a:Poll())=="draw_full,")
    a:Play("bow_release");a:Poll();a:Update(.179);assert(names(a:Poll())=="fire,")
    a:Update(.001);assert(names(a:Poll())=="recover_end,")
end)
test("afterimages maintain .04s deadlines at 30 and 60fps",function()
    for _,fps in ipairs({30,60}) do
        local a,c=new();a:Play("sword_light_1",{fadeIn=0})
        local output=a:GetAfterimages();local first,second=a.afterimagePool[1],a.afterimagePool[2]
        local last=-math.huge;local count=0
        for _=1,math.ceil(.54*fps) do
            a:Update(1/fps);Mock.reset(c);a:Apply();a:Poll()
            local shots=A.GetAfterimages(a);assert(shots==output and #shots<=2)
            for _,shot in ipairs(shots) do
                assert(shot==first or shot==second)
                assert(shot.age>=0 and shot.age<.1 and shot.alpha>0 and shot.alpha<=1)
            end
            if shots[1] and shots[1].time>last+1e-8 then
                if last>0 then near(shots[1].time-last,.04) end
                last=shots[1].time;count=count+1
            end
        end
        assert(count==5);assert(#a:GetAfterimages()==0)
    end
end)
test("afterimages are sword-only, expire during hitstop, cancel clears",function()
    local a,c=new();a:Play("sword_light_1",{fadeIn=0});a:Update(.17);a:Apply()
    assert(#a:GetAfterimages()==1)
    a.timeScale=0;a:Update(.11);Mock.reset(c);a:Apply();assert(#a:GetAfterimages()==0)
    a:Stop(nil,0);a:Poll();a.timeScale=1
    local h=a:Play("sword_light_1",{fadeIn=0});a:Update(.17);Mock.reset(c);a:Apply()
    assert(#a:GetAfterimages()==1);a:Stop(h,0);assert(#a:GetAfterimages()==0)
    a:Play("bow_release");a:Update(.1);Mock.reset(c);a:Apply();assert(#a:GetAfterimages()==0)
end)
test("equipment clips appear in DebugList with source and target equipment",function()
    local found={}
    for _,item in ipairs(A.DebugList()) do found[item.id]=item end
    near(found.bow_equip.dur,.30);near(found.bow_sheath.dur,.30)
    local toBow,toSword=found.weapon_swap_sword_to_bow,found.weapon_swap_bow_to_sword
    near(toBow.dur,.40);near(toSword.dur,.40)
    assert(toBow.sourceWeapon=="sword" and toBow.weaponType=="bow")
    assert(toSword.sourceWeapon=="bow" and toSword.weaponType=="sword")
end)
test("bow equip and sheath traverse the shoulder and deliver attachment once",function()
    local pose=A.DebugSample("bow_equip",.12)
    near(pose.arm_left[1],-170);assert(pose.arm_left[3]<0)
    near(A.DebugSample("bow_equip",.30).arm_left[1],-65)
    near(A.DebugSample("bow_sheath",.20).arm_left[1],-170)
    near(A.DebugSample("bow_sheath",.30).arm_left[1],0)
    local a=new();a:Play("bow_equip");a:Update(.249);assert(#a:Poll()==0)
    a:Update(.001);assert(names(a:Poll())=="weapon_ready,")
    a:Update(.05);assert(names(a:Poll())=="clip_finished,")
    a:Play("bow_sheath");a:Update(.20);assert(names(a:Poll())=="weapon_stowed,")
    a:Update(.10);assert(names(a:Poll())=="clip_finished,")
    a:Update(1);assert(#a:Poll()==0)
end)
test("swap stows at .18, opens cancellation at .20, readies at .40",function()
    for _,id in ipairs({"weapon_swap_sword_to_bow","weapon_swap_bow_to_sword"}) do
        local a=new();a:Play(id)
        a:Update(.179);assert(#a:Poll()==0)
        a:Update(.001);assert(names(a:Poll())=="weapon_stowed,")
        a:Update(.019);assert(#a:Poll()==0)
        a:Update(.001);assert(names(a:Poll())=="cancel_open,")
        a:Update(.199);assert(#a:Poll()==0)
        a:Update(.001);assert(names(a:Poll())=="weapon_ready,cancel_close,clip_finished,")
        a:Update(1);assert(#a:Poll()==0)
    end
end)
test("swap can be cancelled after gate without late attachment or damage",function()
    for _,id in ipairs({"weapon_swap_sword_to_bow","weapon_swap_bow_to_sword"}) do
        local a=new();local h=a:Play(id);a:Update(.20);a:Poll()
        a:Stop(h,0);assert(names(a:Poll())=="cancel_close,clip_cancelled,")
        assert(a:Play("hit_light"));a:Update(.25)
        assert(names(a:Poll())=="cancel_open,cancel_close,clip_finished,")
        local c=D.Clips[id]
        assert(#c.motion==0 and not c.trail and c.layer==D.Layer.DRAW)
        for _,event in ipairs(c.events) do assert(event[1]~="hit_on" and event[1]~="fire") end
    end
end)
test("swap large-frame event order and head/torso lead",function()
    for _,id in ipairs({"weapon_swap_sword_to_bow","weapon_swap_bow_to_sword"}) do
        local a=new();a:Play(id);a:Update(1)
        assert(names(a:Poll())=="weapon_stowed,cancel_open,weapon_ready,cancel_close,clip_finished,")
        local c=D.Clips[id]
        for i=2,5 do
            near((c.keys.arm_left[i][1]-c.keys.body[i][1])*c.dur,.02)
            near(c.keys.head[i][1],c.keys.body[i][1])
            assert(c.keys.body[i][2][2]*c.keys.head[i][2][2]<=0)
        end
    end
end)
local function distance(a,b)
    return math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2+(a[3]-b[3])^2)
end
test("path endpoints, explicit arc sweep, windup and overshoot",function()
    local cases={
        {"sword_light_1",.19,.29,{.62,1.55,.05},{-.40,.85,.70},150,.55},
        {"sword_light_2",.20,.30,{-.40,.80,.65},{.62,1.60,.30},-140,.45},
        {"sword_light_3",.21,.33,{.70,1.20,-.20},{-.70,1.10,.35},200,1.6}}
    for _,v in ipairs(cases) do
        local c=D.Clips[v[1]];local path=c.handPath.arm_right
        near(path.amplitude,v[6]);near(path.windup,.12);near(path.overshoot,.08)
        near(distance(A.DebugSample(v[1],v[2])._ik.arm_right.authored,v[4]),0)
        near(distance(A.DebugSample(v[1],v[3])._ik.arm_right.authored,v[5]),0)
        local a=new();a:Play(v[1]);near(a:GetMotion(1),v[7])
    end
    local a=new();a:Play("sword_heavy_release");near(a:GetMotion(1),1.05)
    near(D.Clips.sword_heavy_release.handPath.arm_right.amplitude,160)
    -- X: cut 1 runs right->left and high->low, cut 2 left->right and high->low.
    local function hand(t) return A.DebugSample("sword_heavy_release",t)._ik.arm_right.authored end
    local a1,b1,a2,b2=hand(.10),hand(.19),hand(.36),hand(.46)
    assert(a1[1]>.3 and b1[1]<-.3 and a1[2]>b1[2]+.6,"first diagonal")
    assert(a2[1]<-.3 and b2[1]>.3 and a2[2]>b2[2]+.3,"second diagonal")
end)
test("all IK samples remain finite and hit the rigid arm sphere",function()
    for _,id in ipairs({"sword_light_1","sword_light_2","sword_light_3","sword_heavy_release","sword_heavy_charge","bow_draw","bow_hold","bow_release"}) do
        local dur=D.Clips[id].dur
        for i=0,120 do
            local pose=A.DebugSample(id,dur*i/120,{p=i/120,aimPitch=35})
            for _,ik in pairs(pose._ik) do
                near(distance(ik.actual,ik.shoulder),ik.length,1e-7)
                near(distance(ik.actual,ik.clamped),0,1e-7)
                assert(ik.reachError==ik.reachError and ik.reachError<10)
            end
        end
    end
end)
test("IK uses actual character socket bind vector and allocates no result tables per Apply",function()
    local a,c=new();a:Play("sword_light_1",{fadeIn=0,fadeOut=0});a:Update(.14);a:Apply()
    local debug=a:GetIKDebug();local arm=debug.arm_right
    local radius=a.arms.arm_right.length
    local solved=c.bones.arm_right.rotation*a.arms.arm_right.grip+a.arms.arm_right.shoulder
    near(solved.x,arm.actual.x);near(solved.y,arm.actual.y);near(solved.z,arm.actual.z)
    near(radius,math.sqrt(.187^2+.286^2+.01518^2))
    for _=1,10 do
        a:Update(0);Mock.reset(c);a:Apply()
        assert(a:GetIKDebug()==debug and debug.arm_right==arm)
    end
end)
test("hitstop holds IK contact pose and weapon direction without drift",function()
    local a,c=new();a:Play("sword_light_1",{fadeIn=0,fadeOut=0});a:Update(.14);a:Apply()
    local q=c.bones.arm_right.rotation
    local actual=a:GetIKDebug().arm_right.actual
    local _,e=a:GetWeaponPose();local blade=Quaternion(e.x,e.y,e.z)
    a.timeScale=0
    for _=1,8 do
        a:Update(1/60);Mock.reset(c);a:Apply()
        sameRotation(c.bones.arm_right.rotation,q)
        near(a:GetIKDebug().arm_right.actual.x,actual.x)
        local _,nextEuler=a:GetWeaponPose();sameRotation(Quaternion(nextEuler.x,nextEuler.y,nextEuler.z),blade)
    end
end)
test("blade compensation follows desired direction through real Rig composition",function()
    for _,id in ipairs({"sword_light_1","sword_light_2","sword_light_3","sword_heavy_release"}) do
        local a,c=new();a:Play(id,{fadeIn=0,fadeOut=0});a:Update(D.Clips[id].phases.active[1]+.04);a:Apply()
        local _,e=a:GetWeaponPose()
        local direction=c.bones.arm_right.rotation*Quaternion(90,0,0)*Quaternion(e.x,e.y,e.z)*Vector3(0,1,0)
        near(direction.x,a.bladeDirection.x,1e-6);near(direction.y,a.bladeDirection.y,1e-6);near(direction.z,a.bladeDirection.z,1e-6)
    end
end)
test("bow faces target, aims within 35 degrees, and draws toward chin",function()
    local low=A.DebugSample("bow_hold",0,{p=0,aimPitch=0})
    local full=A.DebugSample("bow_hold",1,{p=1,aimPitch=0})
    near(full.body[2],0);near(full.body[1]+full.head[1],4)
    assert(full._ik.arm_right.target[3]<low._ik.arm_right.target[3])
    assert(full._ik.arm_right.target[2]>low._ik.arm_right.target[2])
    for _,pitch in ipairs({-100,-35,0,35,100}) do
        local a,c=new();a:Play("bow_hold",{fadeIn=0,params={p=.7,aimPitch=pitch}})
        a:Update(0);a:Apply();local _,e=a:GetWeaponPose()
        local final=c.bones.body.rotation*c.bones.arm_left.rotation*Quaternion(90,0,0)*Quaternion(e.x,e.y,e.z)
        sameRotation(final,Quaternion(math.max(-35,math.min(35,pitch)),0,0))
    end
end)
test("path fallback and exact shoulder-target degeneracy stay valid",function()
    local pose=A.DebugSample("sword_light_1",.14,{legacyPose=1})
    assert(not pose._ik)
    local c=Mock.character();local a=A.New(c,nil,{pathIK=false})
    a:Play("sword_light_1",{fadeIn=0});a:Update(.14);a:Apply()
    assert(not a:GetIKDebug().arm_right.enabled)
    -- A zero-length bind is an invalid rig; keep authored rotation without NaN.
    a=new();a.arms.arm_right.length=0;a.arms.arm_right.grip=Vector3(0,0,0)
    a:Play("sword_light_1",{fadeIn=0});a:Update(.14);a:Apply()
    assert(a:GetIKDebug().arm_right.degenerate)
    local target=A.DebugSample("sword_light_1",.14)._ik.arm_right.target
    a=new();a.arms.arm_right.shoulder=Vector3(table.unpack(target))
    a:Play("sword_light_1",{fadeIn=0});a:Update(.14);a:Apply()
    assert(a:GetIKDebug().arm_right.degenerate)
end)
test("path rotations stay continuous across shoulder and behind-back crossings",function()
    for _,id in ipairs({"sword_light_1","sword_light_2","sword_light_3","sword_heavy_release"}) do
        local previous
        for i=0,600 do
            local pose=A.DebugSample(id,D.Clips[id].dur*i/600)
            local q=Quaternion(table.unpack(pose.arm_right))
            if previous then
                local d=math.min(1,math.abs(q.w*previous.w+q.x*previous.x+q.y*previous.y+q.z*previous.z))
                assert(math.deg(2*math.acos(d))<20,id.." shoulder twist discontinuity")
            end
            previous=q
        end
    end
end)
test("half-moon finisher plants the landed grip for .06 seconds",function()
    local landed=A.DebugSample("sword_light_5",.46)._ik.arm_right.actual
    for _,t in ipairs({.48,.50,.52}) do
        near(distance(A.DebugSample("sword_light_5",t)._ik.arm_right.actual,landed),0)
    end
end)
test("legacy fallback supports clips without separate legacy keys",function()
    for _,item in ipairs(A.DebugList()) do
        assert(A.DebugSample(item.id,0,{legacyPose=1}).body)
    end
end)
test("free-facing attacks leave controller heading and horizontal position untouched",function()
    for _,id in ipairs({"sword_light_1","sword_light_2","sword_light_3","sword_heavy_release"}) do
        for _,yaw in ipairs({-179,-90,0,90,179}) do
            local a,c=new();local node={rotation=Quaternion(0,yaw,0),position=Vector3(8,2,-4)}
            a.node=node;c.bones.root.rotation=Quaternion(0,17,0)
            a:Play(id,{fadeIn=0,fadeOut=0});a:Update(D.Clips[id].phases.active[1]+.04)
            c.bones.root.position=Vector3(3,1,7);a:Apply()
            sameRotation(node.rotation,Quaternion(0,yaw,0));sameRotation(c.bones.root.rotation,Quaternion(0,17,0))
            near(node.position.x,8);near(node.position.z,-4);near(c.bones.root.position.x,3);near(c.bones.root.position.z,7)
            assert(math.abs(A.DebugSample(id,D.Clips[id].phases.active[1]+.04).body[2])<=55)
        end
    end
end)
test("attack leg keys stay available for authoring while runtime preserves gait legs",function()
    for _,id in ipairs({"sword_light_1","sword_light_2","sword_light_3","sword_heavy_release"}) do
        local c=D.Clips[id]
        for i=1,6 do
            near(c.keys.leg_right[i][2][1],-c.keys.leg_left[i][2][1]*.65)
            near(c.keys.head[i][2][2],-math.max(-30,math.min(30,c.keys.body[i][2][2]*.65)))
        end
        local a,character=new();a:Play("sprint_loop",{fadeIn=0,params={sprintWeight=1,gaitPhase=.35}})
        a:Update(0);a:Apply()
        local foot=character.bones.leg_right.rotation
        a:Play(id,{fadeIn=0,fadeOut=0});a:Update(c.phases.active[1]+.04);a:Apply()
        sameRotation(character.bones.leg_right.rotation,foot)
    end
end)
test("bow hand blade and gaze share aim under torso tremor and arbitrary facing",function()
    for _,yaw in ipairs({-179,0,179}) do
        for _,pitch in ipairs({-90,-35,0,35,90}) do
            for _,charge in ipairs({0,.5,1}) do
                local a,c=new();a:Play("bow_hold",{fadeIn=0,params={p=charge,aimPitch=pitch}})
                a:Update(.13);a:Apply()
                local facing=Quaternion(0,yaw,0)
                local body=c.bones.body.rotation
                local aim=math.max(-35,math.min(35,pitch))
                local hand=body*c.bones.arm_left.rotation*a.arms.arm_left.grip
                local wanted=Quaternion(aim,0,0)*Vector3(0,0,a.arms.arm_left.length)
                near(hand.x,wanted.x);near(hand.y,wanted.y);near(hand.z,wanted.z)
                local _,e=a:GetWeaponPose()
                sameRotation(facing*body*c.bones.arm_left.rotation*Quaternion(90,0,0)*Quaternion(e.x,e.y,e.z),facing*Quaternion(aim,0,0))
                sameRotation(facing*body*c.bones.head.rotation,facing*Quaternion(aim+4,0,0))
                local right=a:GetIKDebug().arm_right.actual
                assert(right.x>.20,"string hand must stay outside centre face silhouette")
                assert(a.arms.arm_right.length<.35,"must not stretch arm")
            end
        end
    end
end)
test("bow release holds left aim for .08s then relaxes; cancel does not twist torso",function()
    local first=A.DebugSample("bow_release",0,{p=1,aimPitch=-20})
    for _,t in ipairs({.02,.04,.08}) do
        local pose=A.DebugSample("bow_release",t,{p=1,aimPitch=-20})
        near(distance(first._ik.arm_left.actual,pose._ik.arm_left.actual),0)
    end
    local rest=A.DebugSample("bow_release",.20,{p=1,aimPitch=-20})
    assert(rest._ik.arm_left.actual[2]<first._ik.arm_left.actual[2])
    for i=0,18 do near(A.DebugSample("bow_cancel",i*.01,{p=1}).body[2],0) end
end)

test("new spin/finisher IK and motion remain independent of frame rate",function()
 for _,entry in ipairs({{"sword_light_4",.75,340},{"sword_light_5",1.3,230}}) do
  local clip=D.Clips[entry[1]]
  near(clip.handPath.arm_right.amplitude,entry[3])
  for _,fps in ipairs({30,60}) do
   local a,c=new();a:Play(entry[1]);local total=0
   for i=1,math.ceil(clip.dur*fps)+1 do
    total=total+a:GetMotion(1/fps);Mock.reset(c);a:Apply();a:Poll()
    local sample=A.DebugSample(entry[1],math.min(clip.dur,i/fps))
    for _,angles in pairs(sample) do
     if type(angles)=="table" and type(angles[1])=="number" then assert(angles[1]==angles[1]) end
    end
   end
   near(total,entry[2])
  end
 end
end)
test("plunge anticipation raises blade and descent points down without root displacement",function()
 for _,id in ipairs({"plunge_start","plunge_loop","plunge_land"}) do
  local a,c=new();a:Play(id,{fadeIn=0,fadeOut=0})
  for i=1,10 do
   near(a:GetMotion(.01),0);Mock.reset(c);a:Apply();a:Poll()
   local body=c.bones.body.rotation
   local arm=c.bones.arm_right.rotation
   local _,e=a:GetWeaponPose()
   local blade=body*arm*a.gripRotation*Quaternion(e.x,e.y,e.z)*Vector3(0,1,0)
   assert(id=='plunge_start' and blade.y>.85 or id~='plunge_start' and blade.y<-.96,'overhead anticipation / downward descent')
  end
 end
end)

test("attack preserves locomotion legs and adds body turn over base pose",function()
    local a,c=new({quantize=false})
    c.bones.leg_right.rotation=Quaternion(-17,0,0)
    c.bones.leg_left.rotation=Quaternion(21,0,0)
    c.bones.body.rotation=Quaternion(14,8,0)
    a:Play("sprint_loop",{fadeIn=0,params={sprintWeight=1,gaitPhase=.35}})
    a:Update(0);a:Apply()
    local legRightBefore,legLeftBefore=c.bones.leg_right.rotation,c.bones.leg_left.rotation
    a:Play("sword_light_1",{fadeIn=0})
    a:Update(.18);a:Apply()
    sameRotation(c.bones.leg_right.rotation,legRightBefore)
    sameRotation(c.bones.leg_left.rotation,legLeftBefore)
    local authored=Quaternion(table.unpack(A.DebugSample("sword_light_1",.18).body))
    assert(math.abs(c.bones.body.rotation.w*authored.w+c.bones.body.rotation.x*authored.x
        +c.bones.body.rotation.y*authored.y+c.bones.body.rotation.z*authored.z)<.999,
        "attack must not replace body with the authored combat pose")
    assert(math.abs(c.bones.body.rotation.w*Quaternion(14,8,0).w
        +c.bones.body.rotation.x*Quaternion(14,8,0).x
        +c.bones.body.rotation.y*Quaternion(14,8,0).y
        +c.bones.body.rotation.z*Quaternion(14,8,0).z)<.999,
        "body must add a turn during the attack")
end)
