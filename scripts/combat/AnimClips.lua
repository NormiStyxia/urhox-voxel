-- Keys/events: normalized time. Phases/motion: seconds;
-- §14 overrides earlier timing drafts for the remaining combat moves.
-- weaponType identifies equipment; weapon stores its pose track. The design
-- example used "weapon" twice; Lua would discard the first value.
-- Axes: Rx(p)*(0,-1,0)=(0,-cos(p),-sin(p)): negative arm/leg pitch = forward.
-- Rz(r)*(0,-1,0)=(sin(r),-cos(r),0): positive right-arm roll = outward.
-- Ry(y)*(0,0,1)=(sin(y),0,cos(y)): positive yaw turns toward character right.
-- Body/head extend UP, so positive pitch bends them forward; coat hangs DOWN.
-- Absolute local Euler degrees; continuous angles preserve roll/spin direction.
---@class CombatClip
---@field id string
---@field dur number
---@field layer number
---@field weaponType string|nil
---@field sourceWeapon string|nil Equipment being stowed by a swap clip.
---@field keys table<string, table[]>
---@field root table[]
---@field weapon table[]
---@field motion table[]
---@field events table[]
---@field phases table<string, number[]>
---@field speedStat string|nil
---@field loop boolean|nil
---@field loopFrom number|nil
---@field hold boolean|nil
---@field param string|nil
---@field additive boolean|nil
---@field eventDur number|nil Real-clock tail duration, may exceed dur.
---@field trail number[]|nil Sword afterimage interval in clip seconds.
---@field realTime boolean|nil Fixed real-second pose/motion clock; ignores playback speed.
---@field continuous boolean|nil Bypass local pose quantization.
---@field fadeIn number|nil
---@field fadeOut number|nil
---@field lean table[]|nil Directional blend envelope, normalized time.
---@field deprecated boolean|nil
---@field replacement string|nil
---@field elbow table<string, table[]>|nil Forearm pitch tracks (degrees) for two-segment arms.
---@field handPath table<string, table>|nil Paths in body-aligned, feet-height authoring space.
---@field bladePath table|nil Desired +Y blade direction in body space.
---@field legacyKeys table<string, table[]>|nil Pre-path poses for params.legacyPose=1.
---@field aimFacing boolean|nil Bow aim is relative to W2 facing, not torso lean.
---@field locomotion boolean|nil Pure pose, driven by real displacement gaitPhase.
---@field smoothBlend boolean|nil Smooth natural entry/exit, never retime events.

---@class CombatClipCatalog
---@field Layer table<string, number>
---@field Order string[]
---@field Clips table<string, CombatClip>
local C = {}
C.Layer = { STANCE=1, LOCOMOTION=2, DRAW=3, ATTACK=4, HIT=6, KNOCKDOWN=7, DEATH=8 }
C.Order = {}
---@type table<string, CombatClip>
C.Clips = {}
local function k(a,b,c,d,peak,strike)
    local p,q=peak or .22,strike or .48
    local ab={(a[1]+b[1])*.5,(a[2]+b[2])*.5,(a[3]+b[3])*.5}
    local cd={(c[1]+d[1])*.5,(c[2]+d[2])*.5,(c[3]+d[3])*.5}
    return {{0,a},{p*.5,ab,"inQuad"},{p,b,"inQuad"},{q,c,"outExpo"},{q+(1-q)*.35,cd,"outQuad"},{1,d,"outBack"}}
end
local function phases(d,a,b)
    return {anticipation={0,a},active={a,b},recovery={b,d}}
end
local function hits(a,b,c)
    return {{t=a,"hit_on"},{t=b,"hit_off"},{t=c,"cancel_open"},{t=1,"cancel_close"}}
end
---@param c table Draft clip; optional tracks receive defaults below.
local function add(c)
    c.root=c.root or {{0,0},{1,0}}
    c.weapon=c.weapon or {{0,offset={0,0,0},euler={0,0,0}},{1,offset={0,0,0},euler={0,0,0}}}
    c.motion,c.events=c.motion or {},c.events or {}
    c.phases=c.phases or phases(c.dur,0,0)
    C.Clips[c.id]=c
    C.Order[#C.Order+1]=c.id
end
local L=C.Layer
add { -- 符号待 Web 校准
    id="stance_combat",dur=1,layer=L.STANCE,loop=true,additive=true,
    keys={body=k({6,0,0},{6,0,0},{6,0,0},{6,0,0}),head=k({3,0,0},{3,0,0},{3,0,0},{3,0,0}),
        arm_right=k({0,0,4},{0,0,4},{0,0,4},{0,0,4}),arm_left=k({0,0,-4},{0,0,-4},{0,0,-4},{0,0,-4})},
    root={{0,-.04},{1,-.04}},
}
add { -- Sword in hand: same additive stance, blade held low, tip down-forward-out.
    id="stance_combat_sword",dur=1,layer=L.STANCE,loop=true,additive=true,
    keys={body=k({6,0,0},{6,0,0},{6,0,0},{6,0,0}),head=k({3,0,0},{3,0,0},{3,0,0},{3,0,0}),
        arm_right=k({0,0,4},{0,0,4},{0,0,4},{0,0,4}),arm_left=k({0,0,-4},{0,0,-4},{0,0,-4},{0,0,-4})},
    root={{0,-.04},{1,-.04}},
    weapon={{0,offset={0,0,0},euler={45,0,-25}},{1,offset={0,0,0},euler={45,0,-25}}},
}
assert(C.Clips.stance_combat_sword)
add { -- 符号待 Web 校准
    id="sword_draw",dur=.30,layer=L.DRAW,weaponType="sword",
    keys={body=k({6,0,0},{4,-10,0},{6,-4,0},{6,0,0},.42,.65),
        arm_right=k({20,0,8},{-170,0,25},{-100,8,20},{-65,0,12},.42,.65)},
    events={{t=.42,"weapon_ready"}},
}
add { -- 符号待 Web 校准
    id="sword_sheath",dur=.30,layer=L.DRAW,weaponType="sword",
    keys={body=k({6,0,0},{4,-8,0},{4,-10,0},{6,0,0},.35,.62),
        arm_right=k({-65,0,12},{-100,8,20},{-170,0,25},{0,0,8},.35,.62)},
    events={{t=.62,"weapon_stowed"}},
}
-- Six core poses: ready -> opposite windup -> side -> contact -> overshoot -> settle.
-- Hand/weapon landmarks use the authored times; torso/head landmarks lead by .02s.
local function six(dur,times,poses,lead)
    local track={}
    local curves={"linear","inQuad","inQuad","outExpo","outQuad","outBack"}
    for i=1,6 do
        local t=times[i]
        if lead and i>1 and i<6 then t=t-.02 end
        track[i]={t/dur,poses[i],curves[i]}
    end
    return track
end
-- Equipment transitions keep legs/gait untouched. The weapon track stays at
-- identity: WeaponRig owns back/hand attachment interpolation at the events.
local function equipment(c,times,body,right,left)
    local head={}
    for i,v in ipairs(body) do head[i]={3-v[1]*.35,-v[2]*.65,0} end
    c.keys={body=six(c.dur,times,body,true),head=six(c.dur,times,head,true),
        arm_right=six(c.dur,times,right),arm_left=six(c.dur,times,left)}
    add(c)
end
equipment({ -- 符号待 Web 校准
    id="bow_equip",dur=.30,layer=L.DRAW,weaponType="bow",
    phases=phases(.30,.12,.25),events={{t=.25/.30,"weapon_ready"}},
}, {0,.06,.12,.18,.25,.30},
    {{6,0,0},{4,8,0},{2,12,0},{4,8,0},{6,2,0},{6,0,0}},
    {{0,0,8},{5,0,12},{8,-5,15},{0,0,12},{-5,0,10},{0,0,8}},
    -- Left hand reaches behind its shoulder, extracts, then presents the bow.
    {{20,0,-8},{-95,-10,-25},{-170,0,-25},{-130,-15,-15},{-75,-5,-10},{-65,0,-8}})
equipment({ -- 符号待 Web 校准
    id="bow_sheath",dur=.30,layer=L.DRAW,weaponType="bow",
    phases=phases(.30,.10,.20),events={{t=.20/.30,"weapon_stowed"}},
}, {0,.05,.10,.20,.25,.30},
    {{6,0,0},{6,2,0},{4,8,0},{2,12,0},{4,8,0},{6,0,0}},
    {{0,0,8},{-5,0,10},{0,0,12},{8,-5,15},{5,0,12},{0,0,8}},
    {{-65,0,-8},{-75,-5,-10},{-130,-15,-15},{-170,0,-25},{-90,-10,-20},{0,0,-8}})
equipment({ -- 符号待 Web 校准
    id="weapon_swap_sword_to_bow",dur=.40,layer=L.DRAW,weaponType="bow",sourceWeapon="sword",
    phases=phases(.40,.18,.20),
    events={{t=.18/.40,"weapon_stowed"},{t=.20/.40,"cancel_open"},
        {t=1,"weapon_ready"},{t=1,"cancel_close"}},
}, {0,.08,.18,.24,.34,.40},
    {{6,0,0},{4,-8,0},{2,-12,0},{2,12,0},{6,4,0},{6,0,0}},
    {{-65,0,12},{-110,8,20},{-170,0,25},{-105,0,20},{-20,0,10},{0,0,8}},
    {{0,0,-8},{10,0,-12},{-70,0,-20},{-170,0,-25},{-95,-10,-15},{-65,0,-8}})
equipment({ -- 符号待 Web 校准
    id="weapon_swap_bow_to_sword",dur=.40,layer=L.DRAW,weaponType="sword",sourceWeapon="bow",
    phases=phases(.40,.18,.20),
    events={{t=.18/.40,"weapon_stowed"},{t=.20/.40,"cancel_open"},
        {t=1,"weapon_ready"},{t=1,"cancel_close"}},
}, {0,.08,.18,.24,.34,.40},
    {{6,0,0},{4,8,0},{2,12,0},{2,-12,0},{6,-4,0},{6,0,0}},
    {{0,0,8},{10,0,12},{-70,0,20},{-170,0,25},{-95,10,15},{-65,0,12}},
    {{-65,0,-8},{-110,-8,-20},{-170,0,-25},{-105,0,-20},{-20,0,-10},{0,0,-8}})
local function attack(c,times,body,right,left,legs,weapon)
    c.keys={body=six(c.dur,times,body,true),arm_right=six(c.dur,times,right),arm_left=six(c.dur,times,left)}
    local head={}
    for i,v in ipairs(body) do
        -- Head compensates torso yaw locally, without undoing a whole-body spin.
        local yaw=(v[2]+180)%360-180
        head[i]={3-v[1]*.35,-math.max(-30,math.min(30,yaw*.65)),0}
    end
    c.keys.head=six(c.dur,times,head,true)
    c.keys.leg_left=six(c.dur,times,legs)
    c.weapon={}
    for i,v in ipairs(weapon) do
        c.weapon[i]={times[i]/c.dur,offset=v[1],euler=v[2],ease=i==4 and "outExpo" or "outQuad"}
    end
    c.trail={c.phases.active[1],c.phases.active[2]+.06}
    add(c)
end
-- Five-stage light chain: 斜劈 → 上挑 → 突进横斩 → 腾空回旋 → 跃起半月斩.
-- Each row: dur, hit_on, contact, hit_off, cancel_open (seconds); body yaw per
-- landmark; free-hand pose; lead-leg pitch; root height (metres, optional ease).
-- Landmarks: ready, windup, release(hit_on), contact, follow-through, settle.
-- Recovery: follow-through keeps its inertia, then the blade sinks to the low
-- guard (tip toward the ground along the forearm) and blends into the stance.
local RECOVERY_FADE=.22
local LOW_GUARD={.30,.78,.38}
-- Blade direction in the low guard (radial from the chest to LOW_GUARD): tip
-- down, forward and out to the right. Recovery blends the blade into it.
local SETTLE_DIR={.54,-.49,.68}
local STANCE_EULER={45,0,-25} -- stance_combat_sword grip euler (same low guard)
local LIGHT={
    {id="sword_light_1",dur=.80,on=.16,contact=.22,off=.26,cancel=.32,
        yaw={0,35,22,-30,-45,0},
        left={{0,0,-8},{-35,-10,-25},{-20,-5,-28},{-10,15,-35},{-5,18,-25},{0,0,-8}},
        legs={0,-10,-16,-22,-14,0},
        root={{0,-.04},{.10,-.08},{.16,-.06},{.22,-.11},{.32,-.10},{.48,-.12},{.80,0}}},
    {id="sword_light_2",dur=.82,on=.17,contact=.23,off=.27,cancel=.33,
        yaw={0,-35,-25,22,40,0},
        left={{0,0,-8},{-10,15,-30},{-15,10,-25},{-40,-10,-20},{-30,-12,-18},{0,0,-8}},
        legs={0,-18,-22,-10,-6,0},
        -- Crouch into the low guard, then rise up onto the toes with the blade.
        root={{0,-.04},{.10,-.15},{.17,-.11},{.23,.05,"outQuad"},{.33,.03},{.48,-.10},{.82,0}}},
    {id="sword_light_3",dur=.88,on=.18,contact=.24,off=.30,cancel=.38,
        yaw={0,45,30,-35,-55,0},
        left={{0,0,-8},{-60,-20,-35},{-45,-15,-40},{-15,20,-55},{-10,25,-45},{0,0,-8}},
        legs={0,-24,-34,-30,-22,0},
        root={{0,-.04},{.08,-.13},{.18,-.09},{.24,-.13},{.36,-.12},{.52,-.13},{.88,0}}},
    {id="sword_light_4",dur=.96,on=.22,contact=.32,off=.40,cancel=.46,
        yaw={0,45,20,-30,-50,0},
        left={{0,0,-8},{-20,0,-30},{-30,0,-55},{-25,0,-70},{-15,0,-50},{0,0,-8}},
        legs={0,-12,-30,-36,-20,0},
        -- Visible hop: knees load, body leaves the ground through the whole turn.
        root={{0,-.04},{.13,-.15},{.22,.20,"outQuad"},{.32,.36,"outQuad"},{.46,.08,"inQuad"},{.56,-.12},{.96,0}}},
    {id="sword_light_5",dur=1.10,on=.34,contact=.40,off=.46,cancel=.62,
        yaw={0,15,8,0,-8,0},
        left={{0,0,-8},{-60,0,-30},{-150,10,-20},{-60,15,-25},{-30,10,-30},{0,0,-8}},
        legs={0,-20,-45,-30,-26,0},
        -- Leap: crouch, rise to ~.7m while the blade circles overhead, slam down.
        root={{0,-.04},{.13,-.17},{.30,.70,"outQuad"},{.40,.30,"inQuad"},{.46,-.15,"inQuad"},{.70,-.14},{1.10,0}}},
}
for _,row in ipairs(LIGHT) do
    local d=row.dur
    local times={0,row.on*.6,row.on,row.contact,row.off+.06,d}
    local body,right,legs,weapon={},{},{},{}
    for i=1,6 do
        body[i]={6,row.yaw[i],0}
        right[i]={-65,0,12} -- replaced by the hand-path IK
        legs[i]={row.legs[i],0,0}
        -- Settle keys match the sword stance, so the fade into it never tips the blade up.
        weapon[i]={{0,0,0},i>=5 and STANCE_EULER or {0,0,0}}
    end
    local root={}
    for i,key in ipairs(row.root) do root[i]={key[1]/d,key[2],key[3]} end
    attack({id=row.id,dur=d,layer=L.ATTACK,weaponType="sword",speedStat="speed",
        phases=phases(d,row.on,row.off),events=hits(row.on/d,row.off/d,row.cancel/d),root=root},
        times,body,right,row.left,legs,weapon)
    -- Elbow (forearm pitch, negative = flex). Cocked in the windup, whips
    -- straight at contact, relaxes through follow-through: never a rigid stick.
    C.Clips[row.id].elbow={
        arm_right={{0,-35},{times[2]/d,-95,"outQuad"},{times[3]/d,-70,"inQuad"},
            {times[4]/d,-4,"outCubic"},{times[5]/d,-14,"outQuad"},{1,-22,"smoothStep"}},
        arm_left={{0,-25},{times[2]/d,-70,"outQuad"},{times[4]/d,-45},{1,-25,"smoothStep"}}}
    -- Long recovery melts into the combat stance instead of snapping at the end.
    C.Clips[row.id].fadeOut=RECOVERY_FADE
end
add { -- 符号待 Web 校准
    id="sword_heavy_charge",dur=1,layer=L.ATTACK,weaponType="sword",loop=true,loopFrom=.8,
    keys={body=k({6,0,0},{-6,30,0},{-10,40,0},{-10,40,0},.45,.8),
        arm_right=k({-65,0,12},{-130,30,50},{-160,35,60},{-160,35,60},.45,.8),
        arm_left=k({0,0,-8},{-50,10,-20},{-90,15,-15},{-90,15,-15},.45,.8),
        leg_right=k({0,0,0},{-28,0,5},{-38,0,5},{-38,0,5},.45,.8),
        leg_left=k({0,0,0},{-20,0,-5},{-28,0,-5},{-28,0,-5},.45,.8)},
    root={{0,-.04},{.45,-.12},{.8,-.17},{1,-.17}},events={{t=1,"charge_full"}},
}
attack({ -- 符号待 Web 校准
    id="sword_heavy_release",dur=.72,layer=L.ATTACK,weaponType="sword",speedStat="speed",
    phases=phases(.72,.22,.32),events=hits(.22/.72,.32/.72,.48/.72),
    root={{0,-.17},{.19/.72,-.10},{.22/.72,-.08},{.27/.72,-.14},{.38/.72,-.18},{1,0}},
    motion={{t0=.22,t1=.40,forward=1.1}},
}, {0,.19,.22,.27,.38,.72},
    -- Unwrapped yaw: side 0 -> overshoot -365 -> settle -360. One full turn.
    {{-10,40,0},{-8,55,0},{6,0,0},{18,-180,0},{12,-365,0},{6,-360,0}},
    {{-160,35,60},{-145,45,65},{-100,20,70},{-70,-20,70},{-75,-35,75},{-65,0,12}},
    {{-90,15,-15},{-60,0,-20},{-45,0,-40},{-30,0,-50},{-20,0,-55},{0,0,-8}},
    {{-28,0,-5},{-25,0,-5},{-15,0,0},{-20,-15,0},{-12,0,0},{0,0,0}},
    {{{0,0,0},{-25,0,10}},{{0,0,-.04},{-30,0,25}},{{0,0,0},{-15,0,30}},
     {{0,0,.08},{25,0,-15}},{{0,0,.05},{38,0,-25}},{{0,0,0},{0,0,0}}})
-- Five-stage catalogue: gameplay and presentation read these same rows.
C.Combo={
    {id="sword_light_1",damage=1,poise=1,radius=1.8,angle=120,offset=0,profile="light_1",tier="light",knockback=.1,pitch=1},
    {id="sword_light_2",damage=1,poise=1,radius=1.8,angle=120,offset=0,profile="light_2",tier="light",knockback=.1,pitch=1.04},
    {id="sword_light_3",damage=1,poise=1,radius=1.8,angle=100,offset=.4,profile="third",tier="third",knockback=.55,pitch=.96},
    {id="sword_light_4",damage=.85,poise=1.6,radius=2.1,angle=340,offset=0,profile="spin",tier="third",knockback=.3,pitch=1.12},
    {id="sword_light_5",damage=1.9,poise=2.3,radius=2.2,angle=150,offset=.4,profile="finisher",tier="heavy",knockback=.7,pitch=.82,cooldown=.35,impactRing=true},
}
C.ComboLength=#C.Combo
-- 符号待 Web 校准；air clips supply pose only, physical descent belongs to CC.
add {id="plunge_start",dur=.12,layer=L.ATTACK,weaponType="sword",continuous=true,
    keys={body=k({6,0,0},{18,0,0},{30,0,0},{30,0,0}),head=k({3,0,0},{-3,0,0},{-10,0,0},{-10,0,0}),
        arm_right=k({-65,0,12},{-50,0,20},{-20,0,8},{-20,0,8}),arm_left=k({0,0,-8},{-30,0,-20},{-50,0,-25},{-50,0,-25}),
        leg_right=k({0,0,0},{15,0,0},{25,0,0},{25,0,0}),leg_left=k({0,0,0},{-10,0,0},{-20,0,0},{-20,0,0})}}
add { -- 符号待 Web 校准
    id="plunge_loop",dur=.5,layer=L.ATTACK,weaponType="sword",continuous=true,loop=true,
    keys={body=k({30,0,0},{30,0,0},{30,0,0},{30,0,0}),head=k({-10,0,0},{-10,0,0},{-10,0,0},{-10,0,0}),
        arm_right=k({-20,0,8},{-20,0,8},{-20,0,8},{-20,0,8}),arm_left=k({-50,0,-25},{-50,0,-25},{-50,0,-25},{-50,0,-25}),
        leg_right=k({25,0,0},{25,0,0},{25,0,0},{25,0,0}),leg_left=k({-20,0,0},{-20,0,0},{-20,0,0},{-20,0,0})}}
add { -- 符号待 Web 校准
    id="plunge_land",dur=.25,layer=L.ATTACK,weaponType="sword",continuous=true,
    phases=phases(.25,0,.04),events=hits(0,.04/.25,1),
    keys={body=k({30,0,0},{38,0,0},{20,0,0},{6,0,0}),head=k({-10,0,0},{-14,0,0},{-8,0,0},{3,0,0}),
        arm_right=k({-20,0,8},{-10,0,12},{-35,0,12},{-65,0,12}),arm_left=k({-50,0,-25},{-35,0,-30},{-20,0,-15},{0,0,-8}),
        leg_right=k({25,0,0},{16,0,0},{6,0,0},{0,0,0}),leg_left=k({-20,0,0},{-16,0,0},{-6,0,0},{0,0,0})},
    root={{0,-.04},{.2,-.08},{.6,-.04},{1,0}}}
add { -- 符号待 Web 校准；phase follows actual metres, no horizontal root motion.
    id="sprint_loop",dur=.38,layer=L.LOCOMOTION,loop=true,realTime=true,continuous=true,locomotion=true,
    fadeIn=.04,fadeOut=.06,keys={body=k({14,0,0},{14,0,0},{14,0,0},{14,0,0}),
        head=k({-10,0,0},{-10,0,0},{-10,0,0},{-10,0,0}),
        arm_right=k({0,0,8},{0,0,8},{0,0,8},{0,0,8}),arm_left=k({0,0,-8},{0,0,-8},{0,0,-8},{0,0,-8}),
        leg_right=k({0,0,0},{0,0,0},{0,0,0},{0,0,0}),leg_left=k({0,0,0},{0,0,0},{0,0,0},{0,0,0})}}
add { -- 符号待 Web 校准
    id="bow_draw",dur=.30,layer=L.DRAW,weaponType="bow",
    keys={body=k({6,0,0},{6,25,0},{6,55,0},{6,55,0},.3,.8),
        head=k({3,0,0},{0,-25,0},{0,-55,0},{0,-55,0},.3,.8),
        arm_left=k({0,0,-8},{-45,-20,-12},{-85,-35,-8},{-85,-35,-8},.3,.8),
        arm_right=k({0,0,8},{-50,-10,25},{-80,-20,40},{-80,-20,40},.3,.8)},
    events={{t=0,"draw_start"},{t=.12/.30,"draw_min"}},
}
add { -- 符号待 Web 校准
    id="bow_hold",dur=1,layer=L.ATTACK,weaponType="bow",param="p",hold=true,
    keys={body=k({6,55,0},{6,55,0},{6,55,0},{6,55,0}),
        head=k({0,-55,0},{0,-55,0},{0,-55,0},{0,-55,0}),
        arm_left=k({-85,-35,-8},{-85,-35,-8},{-86,-35,-8},{-87,-35,-8}),
        arm_right=k({-80,-20,40},{-83,-8,43},{-86,8,49},{-90,28,58})},
    root={{0,-.04},{1,-.04}},events={{t=1,"draw_full",param="p"}},
}
add { -- 符号待 Web 校准
    id="bow_release",dur=.20,layer=L.ATTACK,weaponType="bow",
    keys={body=k({6,55,0},{3,31,0},{7,20,0},{6,0,0},.12,.4),
        head=k({0,-55,0},{-2,-31,0},{0,-20,0},{3,0,0},.12,.4),
        arm_right=k({-90,28,58},{-72,-30,35},{-82,-5,35},{-45,0,12},.12,.4),
        arm_left=k({-87,-35,-8},{-94,-35,-8},{-85,-20,-8},{-65,0,-8},.12,.4)},
    events={{t=0,"fire"},{t=.18/.20,"recover_end"}},
    weapon={{0,offset={0,0,0},euler={0,0,0}},{.12,offset={0,0,-.015},euler={-2,0,0}},
        {.4,offset={0,0,0},euler={0,0,0}},{1,offset={0,0,0},euler={0,0,0}}},
}
add { -- 符号待 Web 校准
    id="bow_cancel",dur=.18,layer=L.ATTACK,weaponType="bow",
    keys={body=k({6,55,0},{6,28,0},{6,12,0},{6,0,0}),
        head=k({0,-55,0},{0,-28,0},{2,-12,0},{3,0,0}),
        arm_right=k({-90,28,58},{-70,15,40},{-30,0,20},{0,0,8}),
        arm_left=k({-87,-35,-8},{-70,-25,-8},{-30,-10,-8},{0,0,-8})},
}
add { -- 符号待 Web 校准
    id="hit_light",dur=.24,layer=L.HIT,
    keys={body=k({6,0,0},{-14,0,0},{-14,0,0},{6,0,0},.06/.24,.12/.24),
        head=k({3,0,0},{-10,0,0},{-8,0,0},{3,0,0},.06/.24,.12/.24),
        arm_right=k({-25,0,8},{-15,0,28},{-10,0,25},{0,0,8}),
        arm_left=k({0,0,-8},{-15,0,-28},{-10,0,-25},{0,0,-8})},
    motion={{t0=0,t1=.04,forward=-.04},{t0=.04,t1=.08,forward=.04}},
    events={{t=.18/.24,"cancel_open"},{t=1,"cancel_close"}},
}
add { -- 符号待 Web 校准
    id="hit_heavy",dur=.42,layer=L.HIT,
    keys={body=k({6,0,0},{-28,0,12},{-15,0,8},{6,0,0},.2,.6),
        head=k({3,0,0},{-15,0,-8},{-5,0,-5},{3,0,0},.2,.6),
        arm_right=k({0,0,8},{-30,0,55},{-20,0,35},{0,0,8},.2,.6),
        arm_left=k({0,0,-8},{-30,0,-55},{-20,0,-35},{0,0,-8},.2,.6),
        leg_right=k({0,0,0},{-35,0,0},{20,0,0},{0,0,0},.2,.6),
        leg_left=k({0,0,0},{-25,0,0},{-20,0,0},{0,0,0},.2,.6)},
    root={{0,-.04},{.2,-.15},{.6,-.10},{1,0}},motion={{t0=0,t1=.30,forward=-.8}},
    events={{t=.35/.42,"cancel_open"},{t=1,"cancel_close"}},
}
add { -- 符号待 Web 校准
    id="knockdown",dur=.55,layer=L.KNOCKDOWN,hold=true,
    keys={body=k({-15,0,0},{-45,0,0},{-80,0,0},{-80,0,0},.25,.55),
        head=k({-10,0,0},{-15,0,0},{8,0,0},{8,0,0},.25,.55),
        leg_right=k({0,0,0},{-65,0,8},{-20,0,8},{-10,0,8},.25,.55),
        leg_left=k({0,0,0},{-50,0,-8},{-15,0,-8},{-5,0,-8},.25,.55),
        arm_right=k({0,0,8},{-50,0,50},{-10,0,65},{0,0,60},.25,.55),
        arm_left=k({0,0,-8},{-50,0,-50},{-10,0,-65},{0,0,-60},.25,.55)},
    root={{0,0},{.25,.30},{.55,-.35},{1,-.35}},events={{t=1,"knockdown_end"}},
}
add { -- 符号待 Web 校准
    id="getup",dur=.45,eventDur=.60,layer=L.KNOCKDOWN,
    keys={body=k({-80,0,0},{-35,0,0},{28,0,0},{6,0,0},.28,.65),
        head=k({8,0,0},{12,0,0},{20,0,0},{3,0,0},.28,.82),
        arm_right=k({0,0,60},{25,0,40},{-35,0,15},{0,0,8},.28,.65),
        arm_left=k({0,0,-60},{25,0,-40},{-35,0,-15},{0,0,-8},.28,.65),
        leg_right=k({-10,0,8},{-55,0,6},{-35,0,0},{0,0,0},.28,.65),
        leg_left=k({-5,0,-8},{-40,0,-6},{-25,0,0},{0,0,0},.28,.65)},
    root={{0,-.35},{.28,-.28},{.65,-.12},{1,0}},events={{t=0,"protect_on",clock="real"},{t=.60/.45,"protect_off",clock="real"}},
}
add { -- 符号待 Web 校准
    id="death",dur=1.20,layer=L.DEATH,hold=true,
    keys={body=k({6,0,0},{25,0,8},{70,0,0},{70,0,0},.22,.5),
        head=k({3,0,0},{20,0,0},{30,0,0},{30,0,0},.22,.5),
        arm_right=k({-40,0,12},{-15,0,25},{5,0,35},{5,0,35},.22,.5),
        arm_left=k({0,0,-8},{-20,0,-18},{-10,0,-25},{-10,0,-25},.22,.5),
        leg_right=k({0,0,0},{-65,0,0},{-75,0,0},{-75,0,0},.22,.5),
        leg_left=k({0,0,0},{20,0,0},{30,0,0},{30,0,0},.22,.5)},
    root={{0,-.04},{.22,-.25},{.5,-.45},{1,-.45}},events={{t=.22,"weapon_drop"},{t=1,"respawn_ready"}},
}
add { -- 符号待 Web 校准
    id="stagger_recoil",dur=.25,layer=L.HIT,
    keys={body=k({6,0,0},{-8,0,0},{-5,0,0},{6,0,0},.16,.48),
        arm_right=k({-65,0,12},{-120,10,30},{-105,5,25},{-65,0,12},.16,.48),
        arm_left=k({0,0,-8},{-70,0,-30},{-50,0,-20},{0,0,-8},.16,.48)},
}
-- §20 path layer. All authoring positions are metres: body-aligned axes with
-- y=0 at the reference feet plane. CombatAnim subtracts the body pivot height
-- ONCE to express these points in the shoulder parent's local frame.
-- 符号待 Web 校准: paths amplify silhouette; reachable hands are projected to the
-- actual shoulder/socket radius, never stretch the mesh to these design points.
C.RigReference={bodyHeight=18*.022*1.35,
    rightShoulder={9*.85*.022,28*.022,-.5*.92*.022},
    leftShoulder={-9*.85*.022,28*.022,-.5*.92*.022},
    rightGrip={10*.85*.022,-13*.022,.75*.92*.022},
    leftGrip={-10*.85*.022,-13*.022,.75*.92*.022}}

local function bez(t0,t1,a,b,control,easing)
    return {kind="bezier",t0=t0,t1=t1,a=a,b=b,control=control,ease=easing or "linear"}
end
local function arc(a,b,degrees,plane)
    local i,j=plane=="yz" and 2 or 1,3
    local dx,dy=b[i]-a[i],b[j]-a[j]
    local half=math.rad(degrees)*.5
    local cx=(a[i]+b[i])*.5-dy/(2*math.tan(half))
    local cy=(a[j]+b[j])*.5+dx/(2*math.tan(half))
    return {kind="arc",plane=plane,cx=cx,cy=cy,radius=math.sqrt((a[i]-cx)^2+(a[j]-cy)^2),
        angle=math.atan(a[j]-cy,a[i]-cx),sweep=math.rad(degrees),a=a,b=b}
end
local function arcPoint(spec,u)
    local angle=spec.angle+spec.sweep*u
    local x,y=spec.cx+spec.radius*math.cos(angle),spec.cy+spec.radius*math.sin(angle)
    if spec.plane=="yz" then return {spec.a[1]+(spec.b[1]-spec.a[1])*u,x,y} end
    return {x,spec.a[2]+(spec.b[2]-spec.a[2])*u,y}
end
local function arcPart(spec,t0,t1,u0,u1,easing)
    return {kind="arc",plane=spec.plane,cx=spec.cx,cy=spec.cy,radius=spec.radius,
        angle=spec.angle,sweep=spec.sweep,a=spec.a,b=spec.b,t0=t0,t1=t1,u0=u0,u1=u1,ease=easing}
end
local function pathAttack(id,a,b,degrees,plane,contact,ending,lunge,pole)
    local c=C.Clips[id]
    local on=c.phases.active[1]/c.dur
    local spec=arc(a,b,degrees,plane)
    local ready={.35,1.05,.30}
    local windup=arcPoint(spec,-.12)
    local overshoot=arcPoint(spec,1.08)
    c.handPath={arm_right={segments={
        bez(0,on*.65,ready,windup,{a[1],a[2]+.10,a[3]-.12},"inQuad"),
        arcPart(spec,on*.65,on,-.12,0,"inQuad"),
        arcPart(spec,on,contact/c.dur,0,.70,"inCubic"),
        arcPart(spec,contact/c.dur,ending/c.dur,.70,1,"outCubic"),
        arcPart(spec,ending/c.dur,(ending+.04)/c.dur,1,1.08,"outQuad"),
        -- Inertia: the hand keeps falling with the swing (no bump back up) and
        -- sinks into the low guard at the right side, then rests there.
        bez((ending+.04)/c.dur,math.min(.92,(ending+.30)/c.dur),overshoot,LOW_GUARD,
            {(overshoot[1]+LOW_GUARD[1])*.5+.10,math.min(overshoot[2],LOW_GUARD[2])-.05,(overshoot[3]+LOW_GUARD[3])*.5+.05},"outCubic"),
        bez(math.min(.92,(ending+.30)/c.dur),1,LOW_GUARD,LOW_GUARD,LOW_GUARD)},
        amplitude=degrees,windup=.12,overshoot=.08,space="body_feet",pole=pole}}
    c.bladePath={mode="radial",origin={0,1.05,0},side="arm_right",
        settle={ending/c.dur,math.min(.95,(ending+.16)/c.dur),SETTLE_DIR}}
    c.motion={{t0=c.phases.active[1],t1=ending,forward=lunge}}
    -- IK and blade direction update at render cadence; hitstop freezes s.t.
    c.continuous=true
end
local function preservePose(c)
    c.legacyKeys=c.keys
    c.keys={}
    for name,track in pairs(c.legacyKeys) do
        local copy={}
        for i,key in ipairs(track) do copy[i]={key[1],{key[2][1],key[2][2],key[2][3]},key[3]} end
        c.keys[name]=copy
    end
end
for _,id in ipairs({"sword_light_1","sword_light_2","sword_light_3","sword_light_4","sword_light_5","sword_heavy_release","sword_heavy_charge"}) do
    preservePose(C.Clips[id])
end
-- Arc paths (body-aligned metres, feet at y=0). Contact/ending are seconds.
-- pole: elbow hinge direction (+X = elbow out to the side, -Y = elbow down).
pathAttack("sword_light_1",{.62,1.55,.05},{-.40,.85,.70},150,"xz",.22,.26,.55,{1,.2,-.4})
pathAttack("sword_light_2",{-.40,.80,.65},{.62,1.60,.30},-140,"xz",.23,.27,.45,{1,-.5,-.3})
pathAttack("sword_light_3",{.70,1.20,-.20},{-.70,1.10,.35},200,"xz",.24,.30,1.6,{.2,1,-.3})
pathAttack("sword_light_4",{.65,1.25,.05},{.62,1.20,-.12},340,"xz",.32,.40,.75,{0,1,0})
pathAttack("sword_light_5",{.45,1.10,-.55},{.40,.30,.80},230,"yz",.40,.46,1.3,{1,0,0})
-- Stage 3 dashes: most of the step happens before the blade arrives.
C.Clips.sword_light_3.motion={{t0=.06,t1=.30,forward=1.6}}
-- Stage 4 hops forward through the spin; stage 5 travels with the leap.
C.Clips.sword_light_4.motion={{t0=.18,t1=.46,forward=.75}}
C.Clips.sword_light_5.motion={{t0=.14,t1=.46,forward=1.3}}
-- Half-moon finisher: blade lands at the end of the arc and stays planted .06s.
local moonPath=C.Clips.sword_light_5.handPath.arm_right.segments
local moonEnd=moonPath[4].t1
table.insert(moonPath,5,bez(moonEnd,moonEnd+.06/.90,{.40,.30,.80},{.40,.30,.80},{.40,.30,.80}))
local moonDur=C.Clips.sword_light_5.dur
moonPath[6].t0,moonPath[6].t1=moonEnd+.06/moonDur,moonEnd+.10/moonDur
moonPath[7].t0=moonEnd+.10/moonDur

local heavy=C.Clips.sword_heavy_release
local circle={kind="arc",plane="xz",cx=0,cy=0,radius=.75,angle=0,sweep=math.pi*2,
    a={.75,1.1,0},b={.75,1.1,0}}
heavy.handPath={arm_right={space="body_feet",amplitude=360,windup=.12,overshoot=.08,segments={
    bez(0,.14/.72,{.30,1.55,-.20},arcPoint(circle,-.12),{.75,1.45,-.5},"inQuad"),
    arcPart(circle,.14/.72,.22/.72,-.12,0,"inQuad"),
    arcPart(circle,.22/.72,.27/.72,0,.7,"inCubic"),
    arcPart(circle,.27/.72,.32/.72,.7,1,"outCubic"),
    bez(.32/.72,.38/.72,{.75,1.1,0},{.12,.35,.65},{.35,1.9,.65},"inQuad"),
    bez(.38/.72,.43/.72,{.12,.35,.65},{.10,.28,.70},{.10,.28,.70},"outQuad"),
    bez(.43/.72,.62/.72,{.10,.28,.70},LOW_GUARD,{.25,.45,.70},"inOutCubic"),
    bez(.62/.72,1,LOW_GUARD,LOW_GUARD,LOW_GUARD)}}}
heavy.fadeOut=RECOVERY_FADE
heavy.bladePath={mode="radial",origin={0,1.05,0},side="arm_right",settle={.32/.72,.48/.72,SETTLE_DIR}}
heavy.motion={{t0=.22,t1=.38,forward=.65}}
heavy.continuous=true
-- Free-facing cleanup: the hand already describes a full circle. A second
-- torso revolution doubles the visible turn while the planted feet face W2
-- heading. Keep a bounded hip/shoulder windup and follow-through instead.
-- 符号待 Web 校准
local heavyYaw={40,55,8,-35,-45,0}
for i,yaw in ipairs(heavyYaw) do heavy.keys.body[i][2][2]=yaw end
for _,id in ipairs({"sword_light_1","sword_light_2","sword_light_3","sword_light_4","sword_light_5","sword_heavy_release"}) do
    local c=C.Clips[id]
    -- Torso arrives before the blade, with finite acceleration at contact.
    -- Remove recovery Euler overshoot; follow-through remains the fifth pose.
    c.keys.body[4][3]="smoothStep"
    c.keys.head[4][3]="smoothStep"
    for _,track in pairs(c.keys) do track[#track][3]="smoothStep" end
    c.keys.leg_right={}
    for i,key in ipairs(c.keys.leg_left) do
        -- A rear support foot opposes the lead step; do not inherit run gait
        -- on one leg while the other is planted. Translation stays in motion.
        c.keys.leg_right[i]={key[1],{-key[2][1]*.65,0,0},key[3]}
        local torso=c.keys.body[i][2]
        c.keys.head[i][2]={3-torso[1]*.35,-math.max(-30,math.min(30,torso[2]*.65)),0}
    end
end
-- Forward-leaning strikes with weight: lean back slightly in anticipation,
-- drive the chest over the lead foot at contact, carry it through, then settle.
-- Only torso pitch / root dip change; yaw, hand paths, events and hits are untouched.
-- Light rows author their own crouch/hop root; lean pitch is shared here.
local LEAN={sword_light_1={6,-6,4,26,22,6},sword_light_2={6,14,10,-6,-8,6},
    sword_light_3={6,-4,18,30,26,6},sword_light_4={6,10,4,12,10,6},
    sword_light_5={6,18,-10,8,34,6},sword_heavy_release={-10,-10,8,26,22,6}}
local DIP={sword_heavy_release=-.18}
for id,lean in pairs(LEAN) do
    local c=C.Clips[id]
    for i,pitch in ipairs(lean) do
        c.keys.body[i][2][1]=pitch
        local torso=c.keys.body[i][2]
        c.keys.head[i][2]={3-torso[1]*.35,-math.max(-30,math.min(30,torso[2]*.65)),0}
    end
    -- Contact/follow-through sink lower: the hips drop into the strike.
    local n=#c.root
    if DIP[id] then
        c.root[n-2][2]=math.min(c.root[n-2][2],DIP[id])
        c.root[n-1][2]=math.min(c.root[n-1][2],DIP[id]*.8)
    end
    -- Torso drives into contact quickly (outCubic) instead of a symmetric ease.
    c.keys.body[4][3]="outCubic"
end
C.Clips.sword_heavy_charge.handPath={arm_right={space="body_feet",segments={
    bez(0,1,{.35,1.05,.30},{.65,1.55,-.20},{.70,1.45,-.35},"inQuad")}}}

C.Clips.sword_heavy_charge.bladePath={mode="radial",origin={0,1.05,0},side="arm_right"}

-- 多关键帧悬停→俯冲→落地随动；符号待 Web 校准。
local ps,pl,pd=C.Clips.plunge_start,C.Clips.plunge_loop,C.Clips.plunge_land
ps.hold,ps.fadeOut=true,0
pl.root={{0,-.04},{1,-.04}}
ps.keys.body=k({6,0,0},{-12,8,0},{-10,5,0},{-4,0,0},.5,.83)
ps.keys.head=k({3,0,0},{8,-5,0},{6,-3,0},{3,0,0},.5,.83)
ps.keys.leg_right=k({0,0,0},{12,0,0},{18,0,0},{14,0,0},.5,.83)
ps.keys.leg_left=k({0,0,0},{-8,0,0},{-14,0,0},{-10,0,0},.5,.83)
ps.handPath={arm_right={space="body_feet",segments={
    bez(0,.55,{.35,1.05,.30},{.5,1.7,.35},{.6,1.35,.45},"outQuad"),
    bez(.55,1,{.5,1.7,.35},{.5,1.6,.42},{.55,1.72,.4},"smoothStep")}}}
ps.bladePath={mode="fixed",direction={.4,1,.3},side="arm_right"}
pl.handPath={arm_right={space="body_feet",mode="plunge"}}
pl.bladePath={mode="fixed",direction={0,-1,.25},side="arm_right"}
pd.keys.body=k({30,0,0},{40,0,0},{18,0,0},{6,0,0},.18,.52)
pd.keys.head=k({-10,0,0},{-16,0,0},{-7,0,0},{3,0,0},.18,.52)
pd.keys.leg_right=k({14,0,0},{20,0,0},{8,0,0},{0,0,0},.18,.52)
pd.keys.leg_left=k({-10,0,0},{-14,0,0},{-6,0,0},{0,0,0},.18,.52)
pd.root={{0,-.04},{.18,-.14},{.40,-.10},{.60,.015},{.80,.006},{1,0}}
pd.handPath={arm_right={space="body_feet",segments={
    bez(0,.18,{.48,.85,.62},{.5,.72,.66},{.5,.75,.64},"outQuad"),
    bez(.18,.52,{.5,.72,.66},{.55,1.05,.55},{.58,.90,.70},"outQuad"),
    bez(.52,1,{.55,1.05,.55},{.35,1.05,.30},{.50,1.12,.5},"smoothStep")}}}
pd.bladePath={mode="fixed",direction={0,-1,.25},side="arm_right"}

-- Keep authored legacy poses available, while the bow faces forward rather
-- than sideways. Single rigid right arm aims toward chin; no elbow is invented.
for _,id in ipairs({"bow_draw","bow_hold","bow_release","bow_cancel"}) do
    local c=C.Clips[id]
    c.legacyKeys=c.keys
    c.keys={}
    for name,track in pairs(c.legacyKeys) do c.keys[name]=track end
    c.keys.body=k({6,0,0},{6,0,0},{6,0,0},{6,0,0})
    c.keys.head=k({4,0,0},{4,0,0},{4,0,0},{4,0,0})
    c.handPath={arm_left={mode="bow_aim"},arm_right={mode="bow_string"}}
    c.bladePath={mode="bow_upright",side="arm_left"}
    c.aimFacing=true
    c.continuous=true
end
return C
