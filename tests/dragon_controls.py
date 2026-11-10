"""Offline regression: production Lua controls and tail FK. No Runtime window.
Requires Python numpy and lupa (Lua 5.4); engine nodes/input are test doubles.
"""
from pathlib import Path
import json, math
import numpy as np
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.globals().script_path=str(ROOT/'scripts')
lua.execute(r'''
package.path=script_path..'/?.lua;'..package.path
-- Rendering/physics are irrelevant to the numeric pose and input tests.
package.loaded['dragon.DragonRig']={}
package.loaded['dragon.DragonIK']={}
package.loaded['dragon.DragonGait']={}
local vmt={};vmt.__index=vmt
Vector3=setmetatable({}, {__call=function(_,x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0},vmt)end})
function vmt.__add(a,b)return Vector3(a.x+b.x,a.y+b.y,a.z+b.z)end
function vmt.__sub(a,b)return Vector3(a.x-b.x,a.y-b.y,a.z-b.z)end
function vmt.__mul(a,b)if type(a)=='number'then a,b=b,a end return Vector3(a.x*b,a.y*b,a.z*b)end
function vmt:LengthSquared()return self.x*self.x+self.y*self.y+self.z*self.z end
function vmt:Length()return math.sqrt(self:LengthSquared())end
function vmt:Normalized()local n=self:Length();return Vector3(self.x/n,self.y/n,self.z/n)end
Vector3.RIGHT=Vector3(1,0,0);Vector3.UP=Vector3(0,1,0);Vector3.FORWARD=Vector3(0,0,1)
Quaternion=function()return setmetatable({}, {__mul=function(_,v)return v end})end
for _,k in ipairs({'W','A','S','D','SPACE','C','F','L','G','SHIFT'})do _G['KEY_'..k]=k end
input={GetKeyDown=function()return false end,GetKeyPress=function()return false end}
Ride=require('dragon.DragonRide');C=require('dragon.DragonAnimationController')
Pose=require('dragon.DragonPose');Spec=require('dragon.DragonSpec');Sculpt=require('dragon.DragonSculpt')
checks=0
local function check(ok,label)checks=checks+1;assert(ok,label)end
local c=setmetatable({state='IDLE',layers={},params={walkSpeed=1.6,flySpeed=8,flapHz=.75,amp=1},
 input={move=0,turn=0,climb=0},loco={pos=Vector3(0,0,0),yaw=0,airborne=false,bank=0,
 speed=8,alt=6,altTarget=6,vy=0,pitch=0},flapPhase=0},C)
local node={worldPosition=Vector3(0,3,0),WorldToLocal=function(_,p)return p end}
local saddle={worldPosition=Vector3(0,3,0),worldRotation=Quaternion()}
local chest={worldPosition=Vector3(0,2,0),worldRotation=Quaternion()}
local n={bones={leg_right={worldPosition=Vector3(0,1,0)}},Update=function()end,SetBone=function()end}
local r=Ride.New({ctrl=c,nomi=n,nomiNode=node,rig={bones={chest=chest},sockets={saddle=saddle}}})
local function keys(down,press)Ride.fake=down or {};Ride.fakePress=press or {}end
r.mode='mounted';keys({SPACE=true},{SPACE=true});r:UpdateMounted(1/60)
check(r.mode=='mounted' and c.state=='TAKEOFF','Space takes off without dismounting')
check(c.input.climb==1,'Space routes to climb')
c.stateT=.4;keys({SPACE=true});r:UpdateMounted(1/60)
check(c.stateT==.4,'held Space does not restart takeoff')
c.state='FLY';c.loco.airborne=true;c.loco.altTarget=6;c:FlightLogic(.1,true)
check(c.loco.altTarget>6,'held Space raises target altitude')
keys();r:UpdateMounted(1/60);check(c.input.climb==0,'release Space clears climb')
keys({C=true});r:UpdateMounted(1/60);local alt=c.loco.altTarget;c:FlightLogic(.1,true)
check(c.loco.altTarget<alt,'C descends')
keys({C=true,SPACE=true});r:UpdateMounted(1/60);check(c.input.climb==0,'opposed vertical input cancels')
c.state='GLIDE';keys({SPACE=true},{SPACE=true});r:UpdateMounted(1/60)
check(c.state=='FLY' and r.mode=='mounted','Space leaves glide to climb')
keys({}, {L=true});r:UpdateMounted(1/60);check(c.state=='LAND','L lands without dismounting')
c.state='FLY';keys({SPACE=true},{SPACE=true,F=true});r:UpdateMounted(1/60)
check(r.mode=='free' and c.state=='LAND','F wins over Space and dismounts')
check(c.input.climb==0 and c.input.move==0 and c.input.turn==0,'dismount clears dragon input')
check(r.vy==4.5,'same-frame Space cannot trigger character jump')
local oldState=c.state;r:UpdateAI(1/60);check(c.state==oldState,'ground AI does not override airborne landing')
c.loco.airborne=false;c.state='IDLE';r.onGround=true;r.pos=Vector3(6,0,0)
keys({SPACE=true},{SPACE=true});r:UpdateFree(1/60,0)
check(not r.onGround and r.vy>4.5,'on-foot Space still jumps')
c.input.climb=1;r:Mount();check(c.input.climb==0,'mount clears previous flight input')
c.input.climb=1;r:Release();check(c.input.climb==0,'release clears flight input')
c.state='FLY';c.loco.airborne=true;r.mode='mounted'
keys({SHIFT=true,W=true});r:UpdateMounted(1/60)
check(c.input.sprint,'airborne Shift requests sprint')
keys({SHIFT=true,S=true});r:UpdateMounted(1/60)
check(not c.input.sprint and c.input.move<0,'S overrides Shift')
keys({SHIFT=true,SPACE=true});r:UpdateMounted(1/60)
check(c.input.sprint and c.input.climb==1 and r.mode=='mounted','sprint and climb coexist')
keys({SHIFT=true},{F=true});r:UpdateMounted(1/60)
check(r.mode=='free' and not c.input.sprint,'F clears sprint on dismount')
c.state='IDLE';c.loco.airborne=false;r.mode='mounted'
keys({SHIFT=true,W=true});r:UpdateMounted(1/60)
check(not c.input.sprint,'ground dragon does not sprint')
c.state='GLIDE';c.loco.airborne=true
keys({SHIFT=true});r:UpdateMounted(1/60)
check(c.state=='FLY' and c.input.sprint,'Shift resumes powered flight from glide')
-- Access state pose functions without adding testing API to production modules.
for i=1,20 do local name,value=debug.getupvalue(C.ApplyPose,i);if name=='STATES'then States=value;break end end
function flightPose(phi)
 local p=Pose.New();c.loco.bank=0;C.FlightBody(c,p,phi,1);return p
end
function takeoffPose(t)
 c.flapPhase=(t*.75)%1;c.wingDeploy=1;c.wingOpenPose=require('dragon.DragonPoses').WING_DISPLAY
 return States.TAKEOFF.pose(c,t)
end
function landingPose(alt)
 c.loco.alt=alt;c.touchT=nil;c.flapPhase=.3;return States.LAND.pose(c,0)
end
''')
g=lua.globals()
# Forward kinematics uses the actual skeleton and production Euler matrix order.
bones={b[1]:(b[2],np.array([b[3][i] for i in range(1,4)])) for b in g.Spec.BONES.values()}
def chain(pose,body_pitch=0):
    result={};points=[]
    for name in ['body','pelvis']+['tail'+str(i) for i in range(1,9)]:
        parent,pivot=bones[name]
        a=pose.j[name]
        e=[a[i] if a is not None else 0 for i in range(1,4)]
        if name=='body':e[0]+=body_pitch
        R=np.array(list(g.Sculpt.RotMatrix(*e).values())).reshape(3,3)
        if parent in result:
            pr,pp=result[parent];origin=pp+pr@(pivot-bones[parent][1]);R=pr@R
        else:origin=pivot.copy()
        result[name]=(R,origin)
        if name.startswith('tail'):points.append(origin)
    R,origin=result['tail8'];points.append(origin+R@np.array([0,0,-.23]))
    return np.array(points)
curves=[]
for phi in np.linspace(0,1,32,endpoint=False):
    pose=g.flightPose(float(phi))
    for body_pitch in (-14,0,14):
        pts=chain(pose,body_pitch)
        assert pts[-1,1]<pts[0,1]-.5,'flight tail tip must hang below base even when pitching down'
        assert pts[-1,1]<pts[-2,1],'flight tail tip must not curl upward'
    pts=chain(pose)
    delta=np.diff(pts,axis=0)
    slopes=np.degrees(np.arctan2(delta[:,1],-delta[:,2]))
    assert slopes[-1]<slopes[0]-20,'flight arc must bend downward, not just lower the whole tail'
    curves.append(pts)
for t in (0,.5,.74,1.0,1.3,1.9,2.6):
    assert np.isfinite(chain(g.takeoffPose(t))).all()
for alt in (6,3.4,2,1.6,.6):
    assert np.isfinite(chain(g.landingPose(alt))).all()
report={'input_assertions':g.checks,'flight_phases':32,'body_pitch_cases_per_phase':3,
        'tail_tip_drop_m':[round(float((p[0]-p[-1])[1]),3) for p in curves]}
print(json.dumps(report,indent=2))
if __name__=='__main__':
    dest=ROOT/'.tmp/dragon/controls-tail';dest.mkdir(parents=True,exist_ok=True)
    (dest/'checks.json').write_text(json.dumps(report,indent=2))
    from PIL import Image,ImageDraw
    im=Image.new('RGB',(800,480),'white');draw=ImageDraw.Draw(im)
    for i in range(8):
        pts=curves[i*4];ox=(i%4)*200+174;oy=(i//4)*240+50
        xy=[(ox+float(p[2]+1.3)*40,oy-float(p[1]-1.82)*40) for p in pts]
        draw.text(((i%4)*200+10,(i//4)*240+10),'Flight phase %.3f'%(i/8),fill='black')
        draw.line(xy,fill='steelblue',width=3)
        for x,y in xy:draw.ellipse((x-2,y-2,x+2,y+2),fill='navy')
    im.save(dest/'tail-phases.png')
