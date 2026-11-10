"""Sprint silhouette and airflow regression, using production poses and skeleton FK."""
import contextlib, io, json, math
from pathlib import Path
import numpy as np
with contextlib.redirect_stdout(io.StringIO()):
    import dragon_sprint as base
lua,g=base.lua,base.g
lua.execute('''
function chargePose(L,phi)
 L.vy=L.vy or 0; L.pitch=L.pitch or 0
 local c=setmetatable({loco=L,input={climb=0},params={amp=1},flapPhase=phi},C)
 return C.STATES.FLY.pose(c,0)
end
''')
bones={b[1]:(b[2],np.array([b[3][i] for i in range(1,4)])) for b in g.Spec.BONES.values()}
def fk(pose,L):
    out={}
    for name,(parent,pivot) in bones.items():
        e=pose.body if name=='body' else pose.j[name]
        angles=np.array([e[i] if e is not None else 0 for i in range(1,4)])
        if name=='body':angles+=np.array([L.pitch or 0,0,-L.bank])
        R=np.array(list(g.Sculpt.RotMatrix(*(float(a) for a in angles)).values())).reshape(3,3)
        if parent in out:
            pr,pp=out[parent];origin=pp+pr@(pivot-bones[parent][1]);R=pr@R
        else:origin=pivot+np.array([pose.body[i] for i in range(4,7)])
        out[name]=(R,origin)
    return out

def scenario(fps):
    s=base.new()
    for _ in range(3*fps):base.step(s,1/fps,True)
    normal=g.chargePose(s[0],.15);normalFK=fk(normal,s[0])
    snaps=[('Cruise',normalFK)]
    s[1].sprint=True
    prev=None;maxstep=0;onsetPitch=0
    for i in range(1,3*fps+1):
        base.step(s,1/fps,True)
        p=g.chargePose(s[0],.15);k=fk(p,s[0])
        if prev is not None:
            maxstep=max(maxstep,np.linalg.norm(k['head'][1]-prev))
        prev=k['head'][1]
        onsetPitch=max(onsetPitch,p.body[1])
        if i in [round(fps*.2),round(fps*.5),round(fps*.8),fps*3]:snaps.append((f'{i/fps:.1f}s',k))
        assert all(np.isfinite(v).all() for R,v in k.values())
    assert maxstep<.18, 'head must not jump into sprint pose'
    assert onsetPitch>p.body[1]+1.5, 'onset compression must be stronger than sustained sprint'
    head=k['head'][1];rest=normalFK['head'][1]
    assert head[1]<rest[1]-.65, 'head must visibly lower into the airflow'
    assert head[2]>rest[2]+.3, 'neck must reach forward, not just point the head down'
    forward=k['head'][0]@np.array([0,0,1])
    assert abs(math.degrees(math.atan2(forward[1],forward[2])))<8, 'snout must aim along flight, not down'
    # Check every flap phase with actual body pitch included (unlike tail-only tests).
    for phi in np.linspace(0,1,32,endpoint=False):
        pp=g.chargePose(s[0],float(phi));kk=fk(pp,s[0])
        tip=kk['tail8'][1]+kk['tail8'][0]@np.array([0,0,-.23])
        assert tip[1]<kk['tail1'][1][1]-.3, 'sprint body pitch must not lift tail above its root'
        neutral=g.chargePose(base.new()[0],float(phi))
        assert pp.j.wing_R[2]>neutral.j.wing_R[2]+20, 'wings must sweep back visibly'
    s[1].move=-1
    for _ in range(fps):base.step(s,1/fps,True)
    assert s[0].drill<.03, 'S braking releases compressed sprint pose'
    return snaps,head.tolist(),maxstep
snaps,head,step=scenario(60)
heads=[scenario(f)[1] for f in (30,120)]
assert np.max(np.abs(np.array(heads)-np.array(head)))<.03
# Exercise the full altitude integrator, not only constant-height pose inputs.
lua.execute('''
function flightAltitude(sprint,climb,fps)
 local L,inp,prm=setupFlight(11.6,0,0,0)
 L.alt,L.altTarget,L.vy,L.pitch=6,6,0,0
 inp.sprint,inp.climb=sprint,climb
 prm.amp,prm.flapHz=1,.75
 local c=setmetatable({loco=L,input=inp,params=prm,flapPhase=0},C)
 local low,high=100,-100
 for i=1,fps*6 do
  c:FlightLogic(1/fps,true);Flight.Move(L,1/fps,true);L.pos=Vector3(0,0,0)
  if i>fps*3 then low=math.min(low,L.alt);high=math.max(high,L.alt) end
 end
 return L.alt,high-low
end
''')
for fps in (30,60,120):
    alt,bob=g.flightAltitude(True,0,fps)
    _,cruise_bob=g.flightAltitude(False,0,fps)
    assert abs(alt-6)<.5 and bob<cruise_bob*.7, 'sprint must skim steadily without diving'
    assert g.flightAltitude(True,1,fps)[0]>15, 'Space must still climb in sprint'
    assert 2.3<g.flightAltitude(True,-1,fps)[0]<3.4, 'C must still descend safely'
# Yaw wrap and both turns: trailing parts must bend toward -velocity, not -heading.
for yaw,turn in [(0,1),(0,-1),(179,1),(-179,-1)]:
    s=base.new(18,yaw);s[1].sprint=True;s[1].turn=turn
    for _ in range(120):base.step(s,1/60,True)
    L=s[0];slip=(L.travelYaw-L.yaw+180)%360-180
    assert abs(L.flowYaw-slip)<3 and L.flowYaw*turn<0
    p=g.chargePose(L,.2)
    assert sum(p.j['tail'+str(i)][2] for i in range(1,9))*turn<0
    g.Flight.Reset(L,yaw)
    assert L.drill==0 and L.flowYaw==0
out=Path('.tmp/dragon/charge');out.mkdir(parents=True,exist_ok=True)
report={'head_position_sprint':head,'max_head_step_60fps_m':step,'frame_rates':[30,60,120],
        'phases_checked':32,'flow_turn_cases':4}
(out/'checks.json').write_text(json.dumps(report,indent=2))
# Same projection/scale in every panel: offline skeleton evidence, not runtime pixels.
from PIL import Image,ImageDraw
im=Image.new('RGB',(1000,580),'white');d=ImageDraw.Draw(im)
chains=[['pelvis','waist','chest','neck1','neck2','neck3','neck4','head'],
        ['chest','armU_R','armL_R','hand_R'],['pelvis','legU_R','legL_R','legM_R','foot_R'],
        ['pelvis']+['tail'+str(i) for i in range(1,9)]]
for i,(label,k) in enumerate(snaps):
    x0=(i%3)*333;y0=(i//3)*290
    d.text((x0+12,y0+10),label,fill='black')
    def pt(v):return (x0+175+v[2]*31,y0+225-v[1]*40)
    for chain in chains:
        pts=[pt(k[n][1]) for n in chain]
        d.line(pts,fill='steelblue',width=4)
        for x,y in pts:d.ellipse((x-3,y-3,x+3,y+3),fill='navy')
    pos=k['head'][1];end=pos+k['head'][0]@np.array([0,0,.6])
    d.line([pt(pos),pt(end)],fill='black',width=7)
    d.line([(x0+280,y0+60),(x0+220,y0+60)],fill='gray',width=2)
    d.text((x0+200,y0+40),'airflow',fill='gray')
d.text((680,330),'Production skeleton FK\nFixed flap phase / side view\nRight = travel direction\nNo model/texture edits',fill='black')
im.save(out/'pose-sequence.png')
print(json.dumps(report,indent=2))
