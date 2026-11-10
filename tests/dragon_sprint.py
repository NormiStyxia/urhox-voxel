"""Numerical handling tests against production Lua, using the existing engine doubles."""
import contextlib, io, json
from pathlib import Path
with contextlib.redirect_stdout(io.StringIO()):
    import dragon_controls as base
lua=base.lua
lua.execute(r'''
Flight=require('dragon.DragonFlight')
function setupFlight(speed,yaw,x,z)
 local L={pos=Vector3(x or 0,0,z or 0),yaw=yaw or 0,speed=speed,bank=0,yawRate=0,airborne=true}
 Flight.Reset(L,L.yaw)
 return L,{move=1,turn=0,sprint=false,free=true}, {flySpeed=8}
end
function stepFlight(L,inp,prm,dt,stationary)
 Flight.Update(L,inp,prm,dt,true)
 Flight.Move(L,dt,true)
 if stationary then L.pos=Vector3(0,0,0) end
end
''')
g=lua.globals()
def new(speed=11.6,yaw=0,x=0,z=0):return g.setupFlight(speed,yaw,x,z)
def step(s,dt=1/60,stationary=False):g.stepFlight(*s,dt,stationary)
def reach(s,target,dt=1/60):
 for i in range(600):
  before=s[0].speed;step(s,dt,True)
  assert abs(s[0].speed-before)<=9*dt+1e-7,'instant speed jump'
  if abs(s[0].speed-target)<.001:return (i+1)*dt
 raise AssertionError('target speed not reached')
s=new();s[1].sprint=True
accel=reach(s,18)
assert .7<=accel<=1.2
assert s[0].tailStream[1]>s[0].tailStream[8],'tail tip must follow root with delay'
s[1].sprint=False
coast=reach(s,11.6)
assert 1.8<=coast<=2.8
s=new(18);s[1].sprint=True;s[1].move=-1
brake=reach(s,4.4)
assert 1.3<=brake<=1.8 and brake<coast
# Releasing all keys keeps forward momentum, then reaches cruise speed.
s=new(18);s[1].move=0
step(s,stationary=True);assert s[0].speed>17
release_all=reach(s,8)
# Heading leads travel direction through a turn; no instantaneous velocity rotation.
s=new(18);s[0].stream=1;s[1].sprint=True;s[1].turn=1
for _ in range(60):step(s,stationary=True)
lag=(s[0].yaw-s[0].travelYaw+180)%360-180
assert 3<lag<25
assert s[0].bank>30
# No unwanted autopilot turn in player flight outside the old 22m radius.
s=new(8,0,30,0)
for _ in range(60):step(s)
assert abs(s[0].yaw)<1e-6
# Hard boundary clamping would teleport / break velocity. Soft stopping stays inside.
for yaw,x,z in [(0,0,0),(45,30,30),(90,45,0),(-90,-45,0)]:
 s=new(18,yaw,x,z);s[1].sprint=True
 for _ in range(1200):
  ox,oz=s[0].pos.x,s[0].pos.z;step(s)
  dist=((s[0].pos.x-ox)**2+(s[0].pos.z-oz)**2)**.5
  assert dist<=18/60+.001
  assert max(abs(s[0].pos.x),abs(s[0].pos.z))<60
 assert s[0].speed<.1
 # Turning away lets the dragon leave the edge without a reset/teleport.
 s[1].turn=1
 for _ in range(240):step(s)
 assert s[0].speed>1
# Frame-rate stability over a combined boost and turn manoeuvre.
out=[]
for fps in (30,60,120):
 s=new();s[1].sprint=True;s[1].turn=.6
 for _ in range(fps*2):step(s,1/fps)
 out.append((s[0].pos.x,s[0].pos.z,s[0].speed,s[0].travelYaw))
assert max(v[2] for v in out)-min(v[2] for v in out)<.2
assert max(v[0] for v in out)-min(v[0] for v in out)<.4
assert max(v[1] for v in out)-min(v[1] for v in out)<.4
# Ground/teleport clears inertial travel direction rather than leaking drift into walking.
s=new(18);s[0].travelYaw=70;s[0].yaw=10
g.Flight.Move(s[0],0,False)
assert s[0].travelYaw==10 and s[0].boost==0 and s[0].stream==0
report={'acceleration_11_6_to_18_s':round(accel,3),'coast_18_to_11_6_s':round(coast,3),
        'brake_18_to_4_4_s':round(brake,3),'release_all_to_8_s':round(release_all,3),
        'turn_heading_lead_degrees':round(lag,2),'boundary_tests':4,'frame_rates':[30,60,120]}
print(json.dumps(report,indent=2))
out=Path(__file__).resolve().parents[1]/'.tmp/dragon/controls-tail'
out.mkdir(parents=True,exist_ok=True)
(out/'sprint-checks.json').write_text(json.dumps(report,indent=2))
