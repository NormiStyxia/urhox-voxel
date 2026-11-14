local S=dofile('tests/combat/locomotion_support.lua')
local F=S.F
for _,held in ipairs({0,.05,.1,.239}) do
    local m,f=S.New(false)
    local total=S.Tick(m,.001,{evadePressed=true,evadeHeld=held>0})
    assert(m.clip=='dodge_slide' and m.iframe and not S.State.InCombat())
    for i=1,100 do
        total=total+S.Tick(m,.01,{evadeHeld=f.time<held})
        assert(not f:IsRunning())
    end
    S.near(total,2.12)
end
for _,fps in ipairs({30,60,120}) do
    local m,f=S.New(true);local distance=0
    for i=1,math.floor(.52*fps) do distance=distance+S.Tick(m,1/fps,{evadePressed=i==1,evadeHeld=true}) end
    local tail=.52-f.time;if tail>1e-8 then distance=distance+S.Tick(m,tail,{evadeHeld=true}) end
    S.near(distance,3.212);S.near(f.speed,7.2);assert(f:IsRunning() and not m.iframe and not m.clip)
    assert(m.dodgeCount==1,'held does not replay dodge')
end
local m,f=S.New(false)
local total=S.Tick(m,.52,{evadePressed=true,evadeHeld=true})
S.near(total,3.212);S.near(f.speed,7.2);S.near(m.dodgeCool,0)
assert(not S.State.InCombat(),'exploration remains exploration')
m,f=S.New(true)
S.Tick(m,.239,{evadePressed=true,evadeHeld=true});assert(not f.pending)
S.Tick(m,.001,{evadeHeld=true});assert(f.pending and not f:IsRunning())
S.Tick(m,.06,{evadeHeld=true});assert(f:IsRunning());S.near(f.speed,2)
S.Tick(m,.22,{evadeHeld=true});S.near(f.speed,7.2)
S.Tick(m,.12,{evadeHeld=false});S.near(f.speed,4.2);assert(not f:IsRunning())
-- New attack at the .22 boundary wins over .30 continuation even in a hitch.
m,f=S.New(true);S.Tick(m,.04,{evadePressed=true,evadeHeld=true})
local d=S.Tick(m,.01,{evadeHeld=true,attackTap=true})+.48
d=d+S.Tick(m,.40,{evadeHeld=true});S.near(d,1.92)
assert(m.clip=='sword_light_1' and not f:IsRunning() and not f.pending)
-- Unsafe start and air may not become running by holding later.
for _,reason in ipairs({'unsafe','air'}) do
 m,f=S.New(false)
 if reason=='unsafe' then m.o.slideStart=function()return false end end
 S.Tick(m,.1,{evadePressed=true,evadeHeld=true,onGround=reason~='air'})
 for i=1,10 do S.Tick(m,.1,{evadeHeld=true}) end
 assert(m.dodgeCool==0 and not m.iframe and not f:IsRunning())
end
m,f=S.New(false);m.dodgeCool=.5
S.Tick(m,.1,{evadePressed=true,evadeHeld=true});S.Tick(m,.14,{evadeHeld=true})
assert(f:IsRunning() and not m.iframe);S.near(m.dodgeCool,.26)
-- Clipping retains original iframe/CD, drops pending; never adds run metres.
m,f=S.New(false);m.o.slideMotion=function()return Vector3.ZERO,true end
S.Tick(m,.25,{evadePressed=true,evadeHeld=true});assert(not f.pending and not f:IsRunning())
S.near(f.distance,0);assert(m.dodgeCool>0 and not m.iframe)
for _,reason in ipairs({'menu','focus','death','mount','void','touchcancel','device'}) do
 m,f=S.New(false);S.Tick(m,.31,{evadePressed=true,evadeHeld=true});m:Cancel(reason)
 for i=1,5 do S.Tick(m,.1,{evadeHeld=true}) end
 assert(f.state==F.State.WAIT_RELEASE and f.distance==0)
 S.Tick(m,.01,{evadeHeld=false});assert(f.state==F.State.LOCOMOTION)
 S.Tick(m,.01,{evadePressed=true,evadeHeld=true});assert(m.clip=='dodge_slide')
end
m,f=S.New(false);S.Tick(m,.52,{evadePressed=true,evadeHeld=true})
S.Tick(m,.04,{evadeHeld=true,actualForwardSpeed=0});assert(f:IsRunning())
S.Tick(m,.04,{evadeHeld=true,actualForwardSpeed=0});assert(f.state==F.State.WAIT_RELEASE)
m,f=S.New(false);S.Tick(m,.52,{evadePressed=true,evadeHeld=true})
S.Tick(m,.01,{evadeHeld=true,jump=true});assert(not f:IsRunning() and not f.pending)
m,f=S.New(false);S.Tick(m,.1,{runIntent=true});assert(f:IsRunning() and not m.clip and not m.iframe and m.dodgeCool==0)
print('PASS R9 tap/hold/explore/CD/air/unsafe/cancel/wall/jump/joystick; FPS and .52 hitch = 3.212m')
-- A hitch cannot make a press occur retroactively before the CD expired.
m,f=S.New(false);m.dodgeCool=.10
local metres=S.Tick(m,.20,{evadePressed=true,evadeHeld=false})
S.near(metres,1.08);S.near(m.slideElapsed,.10);S.near(m.dodgeAt,.10);S.near(m.dodgeCool,.40)
m,f=S.New(false);m.dodgeCool=.30
S.Tick(m,.40,{evadePressed=true,evadeHeld=false})
assert(m.dodgeCount==0 and not m.iframe and not m.buffer,'.16 buffer expires before late cooldown')
m,f=S.New(false);m.dodgeCool=.10
metres=S.Tick(m,.50,{evadePressed=true,evadeHeld=true})
S.near(metres,2.2+F.Distance(.10,2,7.2,.22));S.near(f.runAge,.10)
-- Real-time state machine performs no table creation after warmup.
local f0=F.New();local opts=f0.animOpts;local params=opts.params
local emptyMoves={state={InCombat=function()return false end},o={},dead=false}
local controls={allowed=true,evadeHeld=true,onGround=true,axis=Vector3.FORWARD,actualForwardSpeed=7.2,travel=.12}
f0:Start(2)
for _=1,100 do f0:Begin(1/60,controls,emptyMoves);f0:Finish(1/60,0,controls,emptyMoves) end
collectgarbage('collect');collectgarbage('stop');local before=collectgarbage('count')
for _=1,10000 do f0:Begin(1/60,controls,emptyMoves);f0:Finish(1/60,0,controls,emptyMoves) end
local bytes=(collectgarbage('count')-before)*1024/10000;collectgarbage('restart')
assert(bytes<1 and opts==f0.animOpts and params==f0.animOpts.params,'coordinator borrows stable tables')
print(string.format('PASS R9 cooldown crossing/buffer expiry/handoff exact; coordinator gross Lua allocation %.3f B/frame (excludes animation/native userdata)',bytes))
m,f=S.New(false);S.Tick(m,.52,{evadePressed=true,evadeHeld=true})
S.Tick(m,.3,{evadeHeld=true,actualForwardSpeed=0,motionSampleDt=1/60})
assert(f:IsRunning(),'one short observed collision sample is not .3 seconds of blocked physics')
print('PASS wall timer follows observed physics interval, not the next long render interval')
