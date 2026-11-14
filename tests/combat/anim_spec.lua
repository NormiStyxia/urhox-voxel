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
test("all 24 clips have complete, ordered tracks and matching event windows",function()
    assert(#A.DebugList()==24)
    for _,item in ipairs(A.DebugList()) do
        local c=D.Clips[item.id]
        assert(c.id==item.id and c.dur>0 and c.root and c.weapon and c.events and c.motion)
        for _,track in pairs(c.keys) do
            assert(#track==6 and track[1][1]==0 and track[#track][1]==1)
            for i=2,#track do assert(track[i][1]>track[i-1][1]) end
        end
        local previous=-1
        for _,event in ipairs(c.events) do
            assert(event.t>=previous and event.t<=(c.eventDur or c.dur)/c.dur);previous=event.t
            if event[1]=="hit_on" then near(c.phases.active[1],event.t*c.dur) end
            if event[1]=="hit_off" then near(c.phases.active[2],event.t*c.dur) end
        end
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
    local a=new();a:Play("dodge_roll")
    a:Update(0);assert(names(a:Poll())=="iframe_on,")
    a:Update(.25);assert(names(a:Poll())=="iframe_off,")
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
    a:Update(.35);near(state(a,h).weight,.5)
    a:Update(.05);assert(not a:IsPlaying("sword_light_1"));near(state(a,h).weight,0)
end)
test("priority covers stance and cancels offensive tracks",function()
    local a,c=new();a:Play("stance_combat",{fadeIn=0})
    local attack=a:Play("sword_light_1",{fadeIn=0});a:Update(.12);a:Poll()
    local death=a:Play("death",{fadeIn=0});assert(death)
    assert(not a:IsPlaying("sword_light_1"));assert(not a:Play("dodge_roll"))
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
    local a=new();local h=a:Play("dodge_roll");a:Update(.05);a:Poll();a:Stop(h,.1)
    assert(names(a:Poll())=="iframe_off,clip_cancelled,")
    a:Update(1);assert(#a:Poll()==0)
    h=a:Play("bow_release");a:Stop(h,0);a:Update(.5)
    assert(names(a:Poll())=="clip_cancelled,")
end)
test("stop removes unconsumed hit_on without losing pending hit_off",function()
    local a=new();local h=a:Play("sword_light_1");a:Update(.12);a:Poll()
    a:Update(.065);a:Stop(h,0)
    assert(names(a:Poll())=="hit_off,cancel_close,clip_cancelled,")
    h=a:Play("sword_light_1");a:Update(.12);a:Stop(h,0)
    assert(names(a:Poll())=="hit_off,clip_cancelled,")
end)
test("replay and stale handles",function()
    local a=new();local h=a:Play("bow_release");a:Update(.3);a:Poll()
    local nextHandle=a:Play("bow_release");assert(nextHandle~=h);a:Stop(h,0)
    a:Update(0);assert(names(a:Poll())=="fire,")
end)
test("loop full event only once and no repeated anticipation",function()
    local a=new();a:Play("sword_heavy_charge")
    a:Update(9);assert(names(a:Poll())=="charge_full,");a:Update(9);assert(#a:Poll()==0)
    local pose=A.DebugSample("sword_heavy_charge",9)
    near(pose.body[2],40)
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
    a:Update(.06);near(state(a,h).sample*.40,.06)
    a:Update(.05);near(state(a,h).sample*.40,.11);assert(a:Phase()=="active")
    a:Update(.12);assert(state(a,h).sample*.40>=.18);assert(a:Phase()=="recovery")
end)
test("motion totals independent of speed, fades and timestep",function()
    for _,speed in ipairs({.5,1,3}) do
        for _,dt in ipairs({1/144,1/30,.6}) do
            local a=new();a:Play("dodge_roll",{speed=speed})
            local total=0
            for _=1,math.ceil(.5/speed/dt) do total=total+a:GetMotion(dt);a:Poll() end
            near(total,2.6)
        end
    end
    local a=new();a:Play("hit_heavy");near(a:GetMotion(1),-.8)
    a=new();a:Play("sword_light_1");near(a:GetMotion(1),.50)
end)
test("cancel stops subsequent motion",function()
    local a=new();local h=a:Play("dodge_roll");near(a:GetMotion(.315),2.6*.85)
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
test("roll and spin preserve authored multi-turn angle path",function()
    near(A.DebugSample("dodge_roll",.25).body[1],330)
    near(A.DebugSample("sword_heavy_release",.25).body[2],-180)
    near(A.DebugSample("sword_heavy_release",.72).body[2],-360)
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
    local expected={sword_light_1={.40,.10,.18,.18},sword_light_2={.40,.10,.18,.18},
        sword_light_3={.52,.14,.22,.30},sword_heavy_release={.72,.22,.32,.48}}
    for id,v in pairs(expected) do
        local c=D.Clips[id];near(c.dur,v[1]);near(c.phases.active[1],v[2]);near(c.phases.active[2],v[3])
        near(c.events[1].t*c.dur,v[2]);near(c.events[2].t*c.dur,v[3]);near(c.events[3].t*c.dur,v[4])
        near(c.trail[2],v[3]+.06)
    end
    near(D.Clips.hit_light.dur,.24);near(D.Clips.hit_heavy.dur,.42)
    near(D.Clips.knockdown.dur,.55);near(D.Clips.getup.dur,.45)
end)
test("six attack landmarks, torso .02s ahead and head compensates",function()
    for _,id in ipairs({"sword_light_1","sword_light_2","sword_light_3","sword_heavy_release"}) do
        local c=D.Clips[id]
        for i=2,5 do
            near((c.keys.arm_right[i][1]-c.keys.body[i][1])*c.dur,.02)
            near(c.keys.head[i][1],c.keys.body[i][1])
        end
        assert(c.keys.head[2][2][2]*c.keys.body[2][2][2]<0)
    end
    local c=D.Clips.sword_light_1
    for i,t in ipairs({0,.07,.10,.14,.22,.40}) do near(c.keys.arm_right[i][1]*c.dur,t) end
end)
test("dodge is front-loaded 85 percent in 70 percent time",function()
    local a=new();a:Play("dodge_roll")
    near(a:GetMotion(.315),2.21);near(a:GetMotion(.135),.39)
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
    local a=new();local h=a:Play("dodge_roll");a:Update(.1);a:Poll()
    a.timeScale=0;a:Update(.15);near(state(a,h).t,.1)
    assert(names(a:Poll())=="iframe_off,")
    a:Stop(nil,0);a:Poll();h=a:Play("getup");a:Update(0,.6)
    near(state(a,h).t,0);assert(names(a:Poll())=="protect_on,protect_off,")
end)
test("bow minimum draw, full threshold, and shot recovery boundary",function()
    local a=new();a:Play("bow_draw");a:Update(.119)
    assert(names(a:Poll())=="draw_start,")
    a:Update(.001);assert(names(a:Poll())=="draw_min,")
    a:Play("bow_hold",{params={p=.799}});a:Poll();a:Update(0);assert(#a:Poll()==0)
    a:SetParam("p",.8);a:Update(0);assert(names(a:Poll())=="draw_full,")
    a:Play("bow_release");a:Poll();a:Update(.179);assert(names(a:Poll())=="fire,")
    a:Update(.001);assert(names(a:Poll())=="recover_end,")
end)
test("afterimages maintain .04s deadlines at 30 and 60fps",function()
    for _,fps in ipairs({30,60}) do
        local a,c=new();a:Play("sword_light_1",{fadeIn=0})
        local output=a:GetAfterimages();local first,second=a.afterimagePool[1],a.afterimagePool[2]
        local last=-math.huge;local count=0
        for _=1,math.ceil(.4*fps) do
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
        assert(count==4);assert(#a:GetAfterimages()==0)
    end
end)
test("afterimages are sword-only, expire during hitstop, cancel clears",function()
    local a,c=new();a:Play("sword_light_1",{fadeIn=0});a:Update(.1);a:Apply()
    assert(#a:GetAfterimages()==1)
    a.timeScale=0;a:Update(.11);Mock.reset(c);a:Apply();assert(#a:GetAfterimages()==0)
    a:Stop(nil,0);a:Poll();a.timeScale=1
    local h=a:Play("sword_light_1",{fadeIn=0});a:Update(.1);Mock.reset(c);a:Apply()
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
test("swap stows at .18, opens dodge at .20, readies at .40",function()
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
        assert(a:Play("dodge_roll"));a:Update(.25)
        assert(names(a:Poll())=="iframe_on,iframe_off,")
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
test("slide is default and roll is marked deprecated without deleting it",function()
    assert(A.DefaultDodge=="dodge_slide" and D.DefaultDodge=="dodge_slide")
    local found={}
    for _,item in ipairs(A.DebugList()) do found[item.id]=item end
    assert(found.dodge_roll.deprecated and found.dodge_roll.replacement=="dodge_slide")
    assert(not found.dodge_slide.deprecated);near(found.dodge_slide.dur,.32)
end)
test("slide has six exact root landmarks and no knee bones",function()
    local clip=D.Clips.dodge_slide
    for i,t in ipairs({0,.04,.10,.18,.26,.32}) do
        near(clip.root[i][1]*clip.dur,t)
        near(clip.keys.body[i][1]*clip.dur,t)
    end
    for i,y in ipairs({-.04,-.19,-.24,-.20,-.10,-.04}) do near(clip.root[i][2],y) end
    local a,c=new();a:Play("dodge_slide",{fadeIn=0,params={moveZ=1}})
    a:Update(.1);a:Apply();near(c.bones.root.position.y,.76)
    local pose=A.DebugSample("dodge_slide",.1,{moveZ=1})
    near(pose.body[1],30);near(pose.leg_right[1]-pose.leg_left[1],55)
    assert(not pose.knee_right and not pose.knee_left)
end)
test("slide directional snapshot keeps attack yaw and supports bow",function()
    local forward=A.DebugSample("dodge_slide",.1,{moveX=0,moveZ=1})
    local rear=A.DebugSample("dodge_slide",.1)
    local right=A.DebugSample("dodge_slide",.1,{moveX=1,moveZ=0})
    local left=A.DebugSample("dodge_slide",.1,{moveX=-1,moveZ=0})
    near(forward.body[1],30);near(rear.body[1],-30)
    near(right.body[2],0);near(right.body[3],-12);near(left.body[3],12)
    assert(right.head[3]>0 and right.leg_right[3]*right.leg_left[3]<0)
    local bow=A.DebugSample("dodge_slide",.1,{moveX=1,moveZ=0,bow=1})
    near(bow.arm_left[1],-70)
    local a=new();local h=a:Play("dodge_slide",{params={moveX=3,moveZ=4}})
    a:SetParam("moveX",-1);a:SetParam("moveZ",0)
    near(state(a,h).params.moveX,.6);near(state(a,h).params.moveZ,.8)
end)
test("slide bypasses 20Hz, stats speed, playback speed and pose hitstop",function()
    local a=new({quantizeHz=20,timeScale=0,stats={speed=4}})
    local h=a:Play("dodge_slide",{speed=3,stats={speed=8}})
    a:Poll();near(a:GetMotion(0,.01),.12)
    near(state(a,h).t,.01);near(state(a,h).sample,.01/.32);near(state(a,h).speed,1)
    a:Update(0,.19)
    assert(names(a:Poll())=="afterimage_on,afterimage_off,iframe_off,")
    a:Update(0,.02);assert(names(a:Poll())=="cancel_open,")
end)
test("slide integrates every overlapped segment and stops at .30",function()
    local a=new();a:Play("dodge_slide")
    near(a:GetMotion(.20),1.82);near(a:GetMotion(.10),.38)
    near(a:GetMotion(.02),0);near(a:GetMotion(2),0)
    a=new();a:Play("dodge_slide");near(a:GetMotion(.32),2.20)
    a=new();a:Play("dodge_slide");near(a:GetMotion(.01),.12);near(a:GetMotion(.16),1.55)
end)
test("slide cancellation at .22 keeps 1.92m and discards the remainder",function()
    local a=new();local h=a:Play("dodge_slide")
    near(a:GetMotion(.22),1.92);a:Poll();a:Stop(h,.04)
    near(a:GetMotion(),0);near(a:GetMotion(.02),0);near(a:GetMotion(.30),0)
    assert(not a:IsPlaying("dodge_slide"))
end)
test("slide 30 and 60fps full and event-boundary cancellation distances agree",function()
    local totals={}
    for _,fps in ipairs({30,60}) do
        local a=new();a:Play("dodge_slide");local total=0
        for _=1,math.ceil(.32*fps) do total=total+a:GetMotion(1/fps);a:Poll() end
        totals[#totals+1]=total;near(total,2.2)
        a=new();local h=a:Play("dodge_slide");local elapsed=0;total=0
        -- The input owner splits a tick at the buffered attack's .22s boundary.
        while elapsed<.22-1e-10 do
            local dt=math.min(1/fps,.22-elapsed)
            total=total+a:GetMotion(dt);elapsed=elapsed+dt;a:Poll()
        end
        near(total,1.92);a:Stop(h,.04);near(a:GetMotion(1/fps),0)
    end
    assert(math.abs(totals[1]-totals[2])<=.03)
end)
test("slide emits acceptance events immediately and each milestone only once",function()
    local a=new();a:Play("dodge_slide")
    assert(names(a:Poll())=="iframe_on,dust_start,dust_streak,")
    a:Update(0);assert(#a:Poll()==0)
    a:Update(1)
    assert(names(a:Poll())=="afterimage_on,afterimage_off,iframe_off,cancel_open,dust_stop,move_end,cancel_close,clip_finished,")
    a:Update(1);assert(#a:Poll()==0)
end)
test("slide interruption closes dust and ghost windows with no late move_end",function()
    local a=new();local h=a:Play("dodge_slide");a:Poll();a:Update(.08);a:Poll()
    a:Stop(h,.04)
    assert(names(a:Poll())=="iframe_off,dust_stop,afterimage_off,clip_cancelled,")
    a:Update(1);near(a:GetMotion(),0);assert(#a:Poll()==0)
end)
test("slide to attack uses .04s crossfade without idle leakage or inherited impulse",function()
    local a,c=new();local h=a:Play("dodge_slide",{params={moveZ=1}})
    a:Update(.219);assert(not a:Play("sword_light_1"))
    a:Update(.001);a:Poll()
    local oldPose=A.DebugSample("dodge_slide",.22,{moveZ=1}).body
    local attack=a:Play("sword_light_1")
    assert(attack and state(a,h).stopping);near(state(a,h).fadeOut,.04);near(state(a,attack).fadeIn,.04)
    near(a:GetMotion(),0);near(a:GetMotion(.02),0);a:Apply()
    near(state(a,h).weight,.5);near(state(a,attack).weight,.5)
    local nextPose=A.DebugSample("sword_light_1",.02).body
    sameRotation(c.bones.body.rotation,Quaternion(table.unpack(oldPose)):Slerp(Quaternion(table.unpack(nextPose)),.5))
    a:Update(.02);assert(not state(a,h).live)
end)
test("explicit slide stop then bow draw still uses .04s blend",function()
    local a=new();local h=a:Play("dodge_slide",{params={bow=1}})
    a:Update(.22);a:Poll();a:Stop(h,.04)
    local draw=a:Play("bow_draw");assert(draw);near(state(a,draw).fadeIn,.04)
    near(a:GetMotion(.02),0)
end)
local function distance(a,b)
    return math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2+(a[3]-b[3])^2)
end
test("path endpoints, explicit arc sweep, windup and overshoot",function()
    local cases={
        {"sword_light_1",.10,.18,{.55,1.35,-.25},{-.55,1.15,.55},170,.5},
        {"sword_light_2",.10,.18,{-.55,1,-.25},{.55,1.40,.55},-150,.45},
        {"sword_light_3",.14,.22,{.15,1.9,-.15},{.15,.45,.7},190,.7}}
    for _,v in ipairs(cases) do
        local c=D.Clips[v[1]];local path=c.handPath.arm_right
        near(path.amplitude,v[6]);near(path.windup,.12);near(path.overshoot,.08)
        near(distance(A.DebugSample(v[1],v[2])._ik.arm_right.authored,v[4]),0)
        near(distance(A.DebugSample(v[1],v[3])._ik.arm_right.authored,v[5]),0)
        local a=new();a:Play(v[1]);near(a:GetMotion(1),v[7])
    end
    local a=new();a:Play("sword_heavy_release");near(a:GetMotion(1),.65)
    near(D.Clips.sword_heavy_release.handPath.arm_right.amplitude,360)
    assert(A.DebugSample("sword_heavy_release",.38)._ik.arm_right.authored[2]<.4)
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
    near(full.body[2],0);assert(full.head[1]>0)
    assert(full._ik.arm_right.target[3]<low._ik.arm_right.target[3])
    assert(full._ik.arm_right.target[2]>low._ik.arm_right.target[2])
    for _,pitch in ipairs({-100,-35,0,35,100}) do
        local a,c=new();a:Play("bow_hold",{fadeIn=0,params={p=.7,aimPitch=pitch}})
        a:Update(0);a:Apply();local _,e=a:GetWeaponPose()
        local final=c.bones.arm_left.rotation*Quaternion(90,0,0)*Quaternion(e.x,e.y,e.z)
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
test("strong slide adds dust_streak once without moving the old gates",function()
    local a=new();a:Play("dodge_slide");assert(names(a:Poll())=="iframe_on,dust_start,dust_streak,")
    a:Update(.10);a:Poll()
    local pose=A.DebugSample("dodge_slide",.10,{moveZ=1})
    near(pose.arm_right[1],55);near(pose.body[1],30)
    a:Update(.10);assert(names(a:Poll())=="afterimage_off,iframe_off,")
    a:Update(.02);assert(names(a:Poll())=="cancel_open,")
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
test("downward slash holds landed grip and root for .05 seconds",function()
    local landed=A.DebugSample("sword_light_3",.22)._ik.arm_right.actual
    for _,t in ipairs({.23,.25,.27}) do
        near(distance(A.DebugSample("sword_light_3",t)._ik.arm_right.actual,landed),0)
        local a,c=new();a:Play("sword_light_3",{fadeIn=0,fadeOut=0});a:Update(t);a:Apply()
        near(c.bones.root.position.y,.88)
    end
end)
test("legacy fallback supports clips without separate legacy keys",function()
    for _,item in ipairs(A.DebugList()) do
        assert(A.DebugSample(item.id,0,{legacyPose=1}).body)
    end
end)
print(string.format("CombatAnim: %d tests passed (Lua 5.4 offline; visual UNVERIFIED)",passed))
