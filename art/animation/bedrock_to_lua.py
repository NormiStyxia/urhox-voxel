#!/usr/bin/env python3
"""Convert Bedrock/GeckoLib-style rotation tracks into Nomi Lua tracks."""
import argparse, json
from pathlib import Path
BONES={'root':'root','waist':'body','body':'body','upperbody':'body','head':'head','arm_right':'arm_right','arm_left':'arm_left','rightarm':'arm_right','leftarm':'arm_left','armright':'arm_right','armleft':'arm_left','forearm_right':'forearm_right','forearm_left':'forearm_left','rightleg':'leg_right','leftleg':'leg_left','legright':'leg_right','legleft':'leg_left','cloak':'cloak','skirt':'skirt','hair':'hair'}
def vec(v):
    if isinstance(v,(int,float)): return [float(v)]*3
    if isinstance(v,list): return [float(v[i]) if i<len(v) else 0.0 for i in range(3)]
    return [0.0,0.0,0.0]
def keys(ch):
    if isinstance(ch,list): return [(0.0,vec(ch))]
    out=[]
    for t,v in (ch or {}).items():
        try: t=float(t)
        except ValueError: continue
        if isinstance(v,dict): v=v.get('post',v.get('pre',v.get('value',[0,0,0])))
        out.append((t,vec(v)))
    return sorted(out)
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('input',type=Path); ap.add_argument('-o','--output',type=Path); ap.add_argument('--name',default='mc_imported'); ap.add_argument('--duration',type=float)
    a=ap.parse_args(); raw=json.loads(a.input.read_text()); all_anim=raw.get('animations',raw); anim=all_anim.get(a.name,next(iter(all_anim.values()))) if isinstance(all_anim,dict) else all_anim
    dur=float(anim.get('animation_length',a.duration or 1.0)); tracks={}
    for src,p in anim.get('bones',{}).items():
        dst=BONES.get(src.lower()); rot=keys(p.get('rotation',{})) if isinstance(p,dict) else []
        if dst and rot: tracks[dst]=[(t/dur,v) for t,v in rot]
    s=['-- Generated from Bedrock/GeckoLib JSON; review axis and mapping.','return { id="%s", dur=%.4f, layer=L.LOCOMOTION, loop=true, locomotion=true, keys={'%(a.name,dur)]
    for bone,ks in tracks.items():
        s.append('  %s={%s},'%(bone,','.join('{%.6f,{%.3f,%.3f,%.3f}}'%(t,v[0],v[1],-v[2]) for t,v in ks)))
    s.append('}}'); out='\n'.join(s)+'\n'; a.output.write_text(out) if a.output else print(out)
if __name__=='__main__': main()
