"""Execute actual vertex expressions with documented SurfaceShader spaces.
CPU regression, not GPU compilation. Old ideal matrices also pass: root unconfirmed.
"""
from pathlib import Path
import math, re, runpy, json
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
reference=runpy.run_path(str(ROOT/'validation/sky-fx/skycards_check.py'))

class Value:
    def __init__(self,value): self.a=np.asarray(value,float)
    def __add__(self,b): return Value(self.a+raw(b))
    __radd__=__add__
    def __sub__(self,b): return Value(self.a-raw(b))
    def __rsub__(self,b): return Value(raw(b)-self.a)
    def __mul__(self,b): return Value(self.a@raw(b) if self.a.ndim==2 else self.a*raw(b))
    def __rmul__(self,b): return Value(raw(b)*self.a)
    def __truediv__(self,b): return Value(self.a/raw(b))
    def __getattr__(self,key):
        ids=[{'x':0,'y':1,'z':2,'w':3,'r':0,'g':1,'b':2,'a':3}[c] for c in key]
        return float(self.a[ids[0]]) if len(ids)==1 else Value(self.a[ids])
def raw(v): return v.a if isinstance(v,Value) else v
def vec(*args): return Value(np.concatenate([np.atleast_1d(raw(v)) for v in args]))
def body(source):
    code=source.split('void vertex() {',1)[1].split('}',1)[0]
    code=re.sub(r'//[^\n]*','',code)
    return [re.sub(r'^(float|vec[234])\s+','',s.strip()) for s in code.split(';') if s.strip()]

def camera(yaw=0,pitch=0,roll=0,position=(0,0,0)):
    y,p,r=np.radians([yaw,pitch,roll]);sy,cy=np.sin(y),np.cos(y);sp,cp=np.sin(p),np.cos(p);sr,cr=np.sin(r),np.cos(r)
    # Left handed +Z forward, +Y up; camera basis columns right/up/forward.
    ry=np.array([[cy,0,sy],[0,1,0],[-sy,0,cy]])
    rx=np.array([[1,0,0],[0,cp,-sp],[0,sp,cp]])
    rz=np.array([[cr,-sr,0],[sr,cr,0],[0,0,1]])
    inverse=np.eye(4);inverse[:3,:3]=ry@rx@rz;inverse[:3,3]=position
    return np.linalg.inv(inverse),inverse

def evaluate(source,vertex,normal,color,model,view,inv_view,time=0,author_view=None):
    world_mode='world_vertex_coords' in source.split(';')[1]
    skip='skip_vertex_transform' in source.split(';')[1]
    input_vertex=(model@np.r_[vertex,1])[:3] if world_mode else vertex
    input_normal=np.linalg.inv(model[:3,:3]).T@normal if world_mode else normal
    env=dict(VERTEX=Value(input_vertex),NORMAL=Value(input_normal),COLOR=Value(color),
             MODEL_MATRIX=Value(model),VIEW_MATRIX=Value(view if author_view is None else author_view),
             INV_VIEW_MATRIX=Value(inv_view),CAMERA_POSITION_WORLD=Value(inv_view[:3,3]),
             drift_time=time,vec3=vec,vec4=vec,length=lambda v:float(np.linalg.norm(raw(v))),
             max=max,sin=math.sin,cos=math.cos)
    for line in body(source):
        lhs,rhs=line.split('=',1);env[lhs.strip()]=eval(rhs,{'__builtins__':{}},env)
    output=np.r_[raw(env['VERTEX']),1]
    # Cached SurfaceUnlit: skip recovers world via cViewInv; world mode skips model.
    world=inv_view@output if skip else output if world_mode else model@output
    return world,view@world,raw(env['cloud_direction']),raw(env['cloud_right'])

def project(v):
    near,far=.1,600.;f=1/math.tan(math.radians(55)/2);aspect=16/9
    p=np.array([[f/aspect,0,0,0],[0,f,0,0],[0,0,(far+near)/(far-near),-2*near*far/(far-near)],[0,0,1,0]])
    clip=p@v
    return clip[:3]/clip[3] if abs(clip[3])>1e-8 else np.full(3,np.nan)

def main():
    shader=(ROOT/'assets/Shaders/BLGL/RuinsCloud.shader').read_text()
    previous=(ROOT/'validation/sky-fx/RuinsCloud-before-rotation.shader.txt').read_text()
    assert 'world_vertex_coords' in shader.split(';')[1] and 'skip_vertex_transform' not in shader.split(';')[1]
    assert not any('VIEW_MATRIX' in c for c in body(shader))
    records=[];max_error=0.;checks=0
    poses=[(0,0,0),(90,0,0),(180,0,0),(360,0,0),(0,40,0),(0,-40,0),(0,0,45),(90,-35,27)]
    for count in (24,12,4):
        triangles,palette=reference['geometry'](count,12)
        for time in (0.,137.):
            for position in ((0,0,0),(100,80,-50),(-900,30000,750)):
                origin=np.asarray(position)+np.array([13.,-3.2,-7.]) # player != camera
                model=np.eye(4);model[:3,3]=origin
                for vertex in triangles[:-2].reshape(-1,12)[::3]:
                    v0,iv0=camera(position=position)
                    expected=evaluate(shader,vertex[:3],vertex[9:12],vertex[5:9],model,v0,iv0,time)
                    offset=expected[0][:3]-position
                    for yaw,pitch,roll in poses:
                        view,inv=camera(yaw,pitch,roll,position)
                        result=evaluate(shader,vertex[:3],vertex[9:12],vertex[5:9],model,view,inv,time)
                        ideal=view@np.r_[np.asarray(position)+offset,1]
                        error=np.max(np.abs(result[1]-ideal));max_error=max(max_error,float(error));assert error<1e-8
                        assert np.allclose(result[2],expected[2],atol=1e-10)
                        assert np.allclose(result[3],expected[3],atol=1e-10)
                        assert abs(result[2]@palette['sun']-expected[2]@palette['sun'])<1e-10
                        assert abs(result[3]@palette['sun']-expected[3]@palette['sun'])<1e-10
                        old=evaluate(previous,vertex[:3],vertex[9:12],vertex[5:9],model,view,inv,time)
                        assert np.allclose(old[1],result[1],atol=1e-8), 'prior ideal matrix path also correct'
                        assert np.all(np.abs(result[0][:3]-origin)<2048), 'followed CPU bounds'
                        if yaw==360: assert np.allclose(result[1],expected[1],atol=1e-8)
                        checks+=1
    vertex=reference['geometry']()[0][0,0];model=np.eye(4);baseline=None
    for pose in poses:
        view,inv=camera(*pose);r=evaluate(shader,vertex[:3],vertex[9:12],vertex[5:9],model,view,inv)
        ndc=project(r[1]);records.append(dict(yaw=pose[0],pitch=pose[1],roll=pose[2],ndc=ndc.tolist(),in_front=bool(r[1][2]>0)))
        if baseline is None: baseline=ndc
        elif pose==(360,0,0): assert np.allclose(ndc,baseline)
        else: assert np.linalg.norm(ndc-baseline)>.1
    assert not records[2]['in_front'], '180-degree turn puts same cloud behind camera'
    view,inv=camera();base=evaluate(shader,vertex[:3],vertex[9:12],vertex[5:9],model,view,inv)
    for pos in ((100,80,-50),(-900,30000,750)):
        view,inv=camera(position=pos);model[:3,3]=np.asarray(pos)+[13,-3.2,-7]
        shifted=evaluate(shader,vertex[:3],vertex[9:12],vertex[5:9],model,view,inv)
        assert np.allclose(shifted[1],base[1],atol=1e-8), 'pure camera translation'
    view,inv=camera();model=np.eye(4)
    moved=evaluate(shader,vertex[:3],vertex[9:12],vertex[5:9],model,view,inv,137)
    assert np.linalg.norm(moved[2]-base[2])>1e-4, 'time drift preserved'
    # Diagnostic ONLY: absent author VIEW rotation reproduces lock in old path.
    fault=[]
    for yaw in (0,90,180):
        view,inv=camera(yaw)
        old=evaluate(previous,vertex[:3],vertex[9:12],vertex[5:9],model,view,inv,author_view=np.eye(4))
        new=evaluate(shader,vertex[:3],vertex[9:12],vertex[5:9],model,view,inv,author_view=np.eye(4))
        fault.append((old[1],new[1]))
    assert np.allclose(fault[0][0],fault[1][0]) and not np.allclose(fault[0][1],fault[1][1])
    out=dict(checks=checks,max_view_error=max_error,projection=records,old_ideal_path_also_passes=True,
        root_cause_confirmed=False,simulated_mismatched_VIEW_is_hypothesis_only=True,web_gpu_validated=False)
    (ROOT/'validation/sky-fx/rotation-counts.json').write_text(json.dumps(out,indent=2))
    print(json.dumps(out,indent=2))
    print('PASS actual vertex expressions: all tiers, yaw/pitch/roll/360, pure translation, distinct camera/model positions, light invariance, drift, bounds')
    print('UNCONFIRMED root cause: prior ideal matrices also pass; fault injection is not Web evidence')
if __name__=='__main__':main()
