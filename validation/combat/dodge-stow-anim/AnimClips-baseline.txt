-- Keys/events: normalized time. Phases/motion: seconds. §18 owns dodge_slide;
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
---@field cancelAt number|nil Real seconds before this dodge can yield to attack.
---@field cancelBlend number|nil
---@field directional boolean|nil Snapshot params.moveX/moveZ in character-local space.
---@field bowKeys table<string, table[]>|nil Arm variant selected by params.bow=1.
---@field lean table[]|nil Directional blend envelope, normalized time.
---@field deprecated boolean|nil
---@field replacement string|nil
---@field handPath table<string, table>|nil Paths in body-aligned, feet-height authoring space.
---@field bladePath table|nil Desired +Y blade direction in body space.
---@field legacyKeys table<string, table[]>|nil Pre-path poses for params.legacyPose=1.
---@field aimFacing boolean|nil Bow aim is relative to W2 facing, not torso lean.

---@class CombatClipCatalog
---@field Layer table<string, number>
---@field Order string[]
---@field Clips table<string, CombatClip>
---@field DefaultDodge string
local C = {}
C.Layer = { STANCE=1, DRAW=2, ATTACK=3, DODGE=4, HIT=5, KNOCKDOWN=6, DEATH=7 }
C.DefaultDodge="dodge_slide"
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
attack({ -- 符号待 Web 校准
    id="sword_light_1",dur=.40,layer=L.ATTACK,weaponType="sword",speedStat="speed",
    phases=phases(.40,.10,.18),events=hits(.10/.40,.18/.40,.18/.40),
    root={{0,-.04},{.07/.4,-.08},{.10/.4,-.06},{.14/.4,-.04},{.22/.4,-.02},{1,0}},
    motion={{t0=.10,t1=.24,forward=.9}},
}, {0,.07,.10,.14,.22,.40},
    {{6,0,0},{-6,22,0},{0,15,0},{14,-25,0},{12,-41,0},{6,0,0}},
    {{-65,0,12},{-50,40,55},{-65,28,60},{-80,-35,20},{-75,-58,12},{-65,0,12}},
    {{0,0,-8},{10,-10,-20},{5,-8,-25},{-20,12,-30},{-10,18,-20},{0,0,-8}},
    {{0,0,0},{-8,0,-3},{-12,0,0},{-18,0,0},{-10,0,0},{0,0,0}},
    {{{0,0,0},{0,0,0}},{{0,0,-.03},{-20,10,18}},{{0,0,0},{-10,5,20}},
     {{0,0,.05},{25,-10,-20}},{{0,0,.03},{36,-18,-30}},{{0,0,0},{0,0,0}}})
attack({ -- 符号待 Web 校准
    id="sword_light_2",dur=.40,layer=L.ATTACK,weaponType="sword",speedStat="speed",
    phases=phases(.40,.10,.18),events=hits(.10/.40,.18/.40,.18/.40),
    root={{0,-.04},{.07/.4,-.07},{.10/.4,-.06},{.14/.4,-.03},{.22/.4,-.02},{1,0}},
    motion={{t0=.10,t1=.24,forward=.7}},
}, {0,.07,.10,.14,.22,.40},
    {{6,0,0},{8,-22,0},{8,-15,0},{6,25,0},{8,36,0},{6,0,0}},
    {{-65,0,12},{-40,-55,10},{-60,-40,15},{-95,25,50},{-98,42,65},{-65,0,12}},
    {{0,0,-8},{-15,10,-20},{-10,10,-25},{5,-15,-28},{8,-20,-22},{0,0,-8}},
    {{0,0,0},{8,0,0},{10,0,0},{15,0,0},{8,0,0},{0,0,0}},
    {{{0,0,0},{0,0,0}},{{0,-.02,0},{25,-20,-35}},{{0,0,0},{18,-10,-20}},
     {{0,.03,.04},{-15,12,25}},{{0,.02,.02},{-25,18,35}},{{0,0,0},{0,0,0}}})
attack({ -- 符号待 Web 校准
    id="sword_light_3",dur=.52,layer=L.ATTACK,weaponType="sword",speedStat="speed",
    phases=phases(.52,.14,.22),events=hits(.14/.52,.22/.52,.30/.52),
    root={{0,-.04},{.11/.52,.05},{.14/.52,.02},{.18/.52,-.10},{.26/.52,-.12},{1,0}},
    motion={{t0=.14,t1=.26,forward=1}},
}, {0,.11,.14,.18,.26,.52},
    {{6,0,0},{-12,15,0},{-4,8,0},{22,0,0},{28,-6,0},{6,0,0}},
    {{-65,0,12},{-170,0,15},{-150,0,12},{-38,0,14},{-20,0,16},{-65,0,12}},
    {{0,0,-8},{-150,15,-10},{-130,12,-10},{-35,12,-12},{-20,10,-15},{0,0,-8}},
    {{0,0,0},{8,0,0},{-5,0,0},{-25,0,0},{-30,0,0},{0,0,0}},
    {{{0,0,0},{0,0,0}},{{0,.03,0},{-25,0,0}},{{0,.02,0},{-15,0,0}},
     {{0,-.05,.03},{35,0,0}},{{0,-.06,.02},{45,0,0}},{{0,0,0},{0,0,0}}})
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
add { -- 符号待 Web 校准
    id="dodge_slide",dur=.32,layer=L.DODGE,realTime=true,continuous=true,directional=true,
    fadeIn=.02,fadeOut=.02,cancelAt=.22,cancelBlend=.04,
    phases=phases(.32,.04,.20),
    -- Facing/yaw stays with W2. moveX/moveZ is the accepted direction expressed
    -- in that facing's local X/Z plane; no input defaults to (0,-1), a backstep.
    -- All tracks are six explicit poses; no nonexistent knee joints are needed.
    keys={
        body={{0,{6,0,0}},{.04/.32,{12,0,0},"outQuad"},{.10/.32,{18,0,0}},
            {.18/.32,{12,0,0}},{.26/.32,{4,0,0}},{1,{6,0,0}}},
        head={{0,{3,0,0}},{.04/.32,{-8,0,0},"outQuad"},{.10/.32,{-12,0,0}},
            {.18/.32,{-8,0,0}},{.26/.32,{-3,0,0}},{1,{3,0,0}}},
        arm_right={{0,{-65,0,12}},{.04/.32,{-50,0,8}},{.10/.32,{-45,0,8}},
            {.18/.32,{-70,0,12}},{.26/.32,{-75,0,10}},{1,{-65,0,12}}},
        arm_left={{0,{0,0,-8}},{.04/.32,{-15,0,-20}},{.10/.32,{-20,0,-25}},
            {.18/.32,{-10,0,-18}},{.26/.32,{-5,0,-10}},{1,{0,0,-8}}},
        leg_right={{0,{0,0,0}},{.04/.32,{20,0,0}},{.10/.32,{20,0,0}},
            {.18/.32,{12,0,0}},{.26/.32,{6,0,0}},{1,{0,0,0}}},
        leg_left={{0,{0,0,0}},{.04/.32,{-25,0,0}},{.10/.32,{-20,0,0}},
            {.18/.32,{-10,0,0}},{.26/.32,{-6,0,0}},{1,{0,0,0}}},
    },
    bowKeys={
        arm_left={{0,{-65,0,-8}},{.04/.32,{-68,0,-10}},{.10/.32,{-70,0,-12}},
            {.18/.32,{-68,0,-10}},{.26/.32,{-66,0,-8}},{1,{-65,0,-8}}},
        arm_right={{0,{-30,0,12}},{.04/.32,{-35,0,16}},{.10/.32,{-40,0,20}},
            {.18/.32,{-35,0,16}},{.26/.32,{-30,0,12}},{1,{-30,0,12}}},
    },
    lean={{0,0},{.04/.32,1},{.10/.32,1},{.18/.32,1},{.26/.32,1},{1,0}},
    root={{0,-.04},{.04/.32,-.14},{.10/.32,-.18},{.18/.32,-.15},{.26/.32,-.08},{1,-.04}},
    motion={{t0=0,t1=.06,forward=.72},{t0=.06,t1=.16,forward=.90},
        {t0=.16,t1=.26,forward=.50},{t0=.26,t1=.30,forward=.08}},
    events={{t=0,"iframe_on",clock="real"},{t=0,"dust_start",clock="real"},
        {t=.04/.32,"afterimage_on",clock="real"},{t=.16/.32,"afterimage_off",clock="real"},
        {t=.20/.32,"iframe_off",clock="real"},{t=.22/.32,"cancel_open",clock="real"},
        {t=.26/.32,"dust_stop",clock="real"},{t=.30/.32,"move_end",clock="real"},
        {t=1,"cancel_close",clock="real"}},
}
add { -- 符号待 Web 校准
    id="dodge_roll",dur=.45,layer=L.DODGE,phases=phases(.45,0,.25),deprecated=true,replacement="dodge_slide",
    keys={body={{0,{6,0,0}},{.08,{22,0,0},"inQuad"},{.18,{65,0,0},"inQuad"},{.38,{190,0,0}},{.25/.45,{330,0,0},"outQuad"},{1,{366,0,0},"outQuad"}},
        arm_right=k({0,0,8},{-60,0,20},{-45,0,15},{0,0,8},.18,.55),
        arm_left=k({0,0,-8},{-60,0,-20},{-45,0,-15},{0,0,-8},.18,.55),
        leg_right=k({0,0,0},{-70,0,0},{-55,0,0},{0,0,0},.18,.55),
        leg_left=k({0,0,0},{-60,0,0},{-40,0,0},{0,0,0},.18,.55)},
    root={{0,-.04},{.18,-.28},{.55,-.28},{1,0}},motion={{t0=0,t1=.315,forward=2.6*.85},{t0=.315,t1=.45,forward=2.6*.15}},
    events={{t=0,"iframe_on",clock="real"},{t=.25/.45,"iframe_off",clock="real"}},
}
add { -- 符号待 Web 校准
    id="bow_draw",dur=.30,layer=L.DRAW,weaponType="bow",
    keys={body=k({6,0,0},{6,15,0},{6,35,0},{6,35,0},.3,.8),
        head=k({3,0,0},{0,-15,0},{0,-35,0},{0,-35,0},.3,.8),
        arm_left=k({0,0,-8},{-45,-20,-12},{-85,-35,-8},{-85,-35,-8},.3,.8),
        arm_right=k({0,0,8},{-50,-10,25},{-80,-20,40},{-80,-20,40},.3,.8)},
    events={{t=0,"draw_start"},{t=.12/.30,"draw_min"}},
}
add { -- 符号待 Web 校准
    id="bow_hold",dur=1,layer=L.ATTACK,weaponType="bow",param="p",hold=true,
    keys={body=k({6,35,0},{6,35,0},{6,35,0},{6,35,0}),
        head=k({0,-35,0},{0,-35,0},{0,-35,0},{0,-35,0}),
        arm_left=k({-85,-35,-8},{-85,-35,-8},{-86,-35,-8},{-87,-35,-8}),
        arm_right=k({-80,-20,40},{-83,-8,43},{-86,8,49},{-90,28,58})},
    root={{0,-.04},{1,-.04}},events={{t=.8,"draw_full",param="p"}},
}
add { -- 符号待 Web 校准
    id="bow_release",dur=.20,layer=L.ATTACK,weaponType="bow",
    keys={body=k({6,35,0},{3,31,0},{7,20,0},{6,0,0},.12,.4),
        head=k({0,-35,0},{-2,-31,0},{0,-20,0},{3,0,0},.12,.4),
        arm_right=k({-90,28,58},{-72,-30,35},{-82,-5,35},{-45,0,12},.12,.4),
        arm_left=k({-87,-35,-8},{-94,-35,-8},{-85,-20,-8},{-65,0,-8},.12,.4)},
    events={{t=0,"fire"},{t=.18/.20,"recover_end"}},
    weapon={{0,offset={0,0,0},euler={0,0,0}},{.12,offset={0,0,-.025},euler={-4,0,0}},
        {.4,offset={0,0,.01},euler={2,0,0}},{1,offset={0,0,0},euler={0,0,0}}},
}
add { -- 符号待 Web 校准
    id="bow_cancel",dur=.18,layer=L.ATTACK,weaponType="bow",
    keys={body=k({6,35,0},{6,28,0},{6,12,0},{6,0,0}),
        head=k({0,-35,0},{0,-28,0},{2,-12,0},{3,0,0}),
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
local function pathAttack(id,a,b,degrees,plane,contact,ending,lunge)
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
        bez((ending+.04)/c.dur,1,overshoot,ready,{.15,1.30,.55},"outQuad")},
        amplitude=degrees,windup=.12,overshoot=.08,space="body_feet"}}
    c.bladePath={mode="radial",origin={0,1.05,0},side="arm_right"}
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
for _,id in ipairs({"sword_light_1","sword_light_2","sword_light_3","sword_heavy_release","sword_heavy_charge"}) do
    preservePose(C.Clips[id])
end
pathAttack("sword_light_1",{.55,1.35,-.25},{-.55,1.15,.55},170,"xz",.14,.18,.50)
pathAttack("sword_light_2",{-.55,1,-.25},{.55,1.40,.55},-150,"xz",.14,.18,.45)
pathAttack("sword_light_3",{.15,1.9,-.15},{.15,.45,.7},190,"yz",.18,.22,.70)
C.Clips.sword_light_1.keys.body[4][2][2]=-45
C.Clips.sword_light_1.keys.body[5][2][2]=-49
C.Clips.sword_light_2.keys.body[4][2][2]=40
C.Clips.sword_light_2.keys.body[5][2][2]=43
C.Clips.sword_light_3.keys.body[5][2][1]=22
C.Clips.sword_light_3.root={{0,-.04},{.11/.52,.05},{.14/.52,.02},
    {.22/.52,-.12},{.27/.52,-.12},{1,0}}
-- Downward contact lands at hit_off; hold the grip/root for .05s, then overshoot.
local slamPath=C.Clips.sword_light_3.handPath.arm_right.segments
slamPath[5].t0,slamPath[5].t1=.27/.52,.31/.52
slamPath[6].t0=.31/.52
table.insert(slamPath,5,bez(.22/.52,.27/.52,{.15,.45,.7},{.15,.45,.7},{.15,.45,.7}))

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
    bez(.43/.72,1,{.10,.28,.70},{.35,1.05,.30},{.25,1.25,.55},"outQuad")}}}
heavy.bladePath={mode="radial",origin={0,1.05,0},side="arm_right"}
heavy.motion={{t0=.22,t1=.38,forward=.65}}
heavy.continuous=true
-- Free-facing cleanup: the hand already describes a full circle. A second
-- torso revolution doubles the visible turn while the planted feet face W2
-- heading. Keep a bounded hip/shoulder windup and follow-through instead.
-- 符号待 Web 校准
local heavyYaw={40,55,8,-35,-45,0}
for i,yaw in ipairs(heavyYaw) do heavy.keys.body[i][2][2]=yaw end
for _,id in ipairs({"sword_light_1","sword_light_2","sword_light_3","sword_heavy_release"}) do
    local c=C.Clips[id]
    c.keys.leg_right={}
    for i,key in ipairs(c.keys.leg_left) do
        -- A rear support foot opposes the lead step; do not inherit run gait
        -- on one leg while the other is planted. Translation stays in motion.
        c.keys.leg_right[i]={key[1],{-key[2][1]*.65,0,0},key[3]}
        local torso=c.keys.body[i][2]
        c.keys.head[i][2]={3-torso[1]*.35,-math.max(-30,math.min(30,torso[2]*.65)),0}
    end
end
C.Clips.sword_heavy_charge.handPath={arm_right={space="body_feet",segments={
    bez(0,1,{.35,1.05,.30},{.30,1.55,-.20},{.65,1.45,-.35},"inQuad")}}}

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
-- §20.5 stronger silhouette; timings/motion/cancel/iframe contracts unchanged.
local slide=C.Clips.dodge_slide
slide.root={{0,-.04},{.04/.32,-.19},{.10/.32,-.24},{.18/.32,-.20},{.26/.32,-.10},{1,-.04}}
slide.keys.body={{0,{6,0,0}},{.04/.32,{20,0,0}},{.10/.32,{30,0,0}},
    {.18/.32,{20,0,0}},{.26/.32,{7,0,0}},{1,{6,0,0}}}
slide.keys.head={{0,{3,0,0}},{.04/.32,{-13,0,0}},{.10/.32,{-20,0,0}},
    {.18/.32,{-13,0,0}},{.26/.32,{-5,0,0}},{1,{3,0,0}}}
slide.keys.arm_right={{0,{-65,0,12}},{.04/.32,{30,0,12}},{.10/.32,{55,0,15}},
    {.18/.32,{25,0,12}},{.26/.32,{-55,0,10}},{1,{-65,0,12}}}
slide.keys.arm_left={{0,{0,0,-8}},{.04/.32,{-45,0,-20}},{.10/.32,{-65,0,-25}},
    {.18/.32,{-40,0,-18}},{.26/.32,{-15,0,-10}},{1,{0,0,-8}}}
slide.keys.leg_right[3][2][1]=25
slide.keys.leg_left[3][2][1]=-30
table.insert(slide.events,3,{t=0,"dust_streak",clock="real"})
return C
