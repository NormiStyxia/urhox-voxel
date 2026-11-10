"""Temporal headwind/acceleration regression; production Lua with engine doubles."""
import contextlib, io, math
from pathlib import Path
with contextlib.redirect_stdout(io.StringIO()):
    import dragon_sprint as base
lua, g = base.lua, base.g
lua.execute('''
function riderPose(L)
 local angles={}
 local rider=Ride.New({ctrl={loco=L,params={walkSpeed=2}},
 nomiNode={WorldToLocal=function(_,v)return v end},
 nomi={bones={leg_right={worldPosition=Vector3(0,1,0)}},
 SetBone=function(_,name,x,y,z) angles[name]=x end}})
 rider:SeatPose()
 return angles
end
''')
rows=[]
for fps in (30,60,120):
    s=base.new()
    for _ in range(fps*3):base.step(s,1/fps,True)
    normal=g.riderPose(s[0]).body
    s[1].sprint=True
    frames=[]
    for i in range(fps*3):
        base.step(s,1/fps,True)
        L=s[0];p=g.riderPose(L)
        frames.append((L.pull,L.hairWind,L.hemWind,p.body,L.cameraPull))
        assert all(math.isfinite(v) for v in frames[-1])
        assert -1<=L.pull<=1 and 0<=L.hemWind<=1.25
        assert abs(L.cameraPull)<=1.1
        assert p.leg_right==-58 and p.leg_left==-58, 'hips/legs must stay seated'
    onset=frames[int(fps*.2)-1]
    assert onset[3]<normal-3, 'torso must yield backwards before bracing'
    assert onset[1]>onset[2]+.03, 'hair must lead the heavier coat hem'
    assert frames[-1][3]>normal+7, 'sustained wind must brace torso forward'
    assert abs(frames[-1][0])<.001, 'acceleration transient must settle at constant speed'
    assert g.riderPose(s[0]).hair_back>30, 'hair must remain swept back at speed'
    rows.append(frames[-1])
    s[1].move=-1
    for _ in range(fps//2):base.step(s,1/fps,True)
    assert s[0].pull<-.8, 'braking must reverse inertial pull'
    for _ in range(fps*5):base.step(s,1/fps,True)
    assert s[0].hemWind<.001 and abs(s[0].cameraPull)<.001, 'wind must release smoothly at low speed'
    g.Flight.Reset(s[0],0)
    assert all(s[0][k]==0 for k in ('wind','pull','hairWind','coatWind','hemWind','cameraPull'))
for i in range(5):
    assert max(r[i] for r in rows)-min(r[i] for r in rows)<.01
check=lua.eval('function(s) local f,e=load(s); assert(f,e) end')
for p in Path('scripts/dragon').glob('*.lua'):check(p.read_text())
print('PASS: backward onset, delayed cloth, sustained wind, brake reversal, reset, 30/60/120 FPS; Lua syntax.')
