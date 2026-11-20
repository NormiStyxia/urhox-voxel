#!/usr/bin/env python3
"""Extract a Blockbench animation from Nomi's .bbmodel into CombatAnim tracks."""
import argparse,json
from pathlib import Path
MAP={'Root':'root','UpBody':'body','DownBody':'body','Head':'head','LeftArm':'arm_left','RightArm':'arm_right','LeftForeArm':'forearm_left','RightForeArm':'forearm_right','LeftLeg':'leg_left','RightLeg':'leg_right','LeftLowerLeg':'leg_left','RightLowerLeg':'leg_right','LeftFoot':'leg_left','RightFoot':'leg_right','FLongHair':'hair','MLongHair':'hair','LongHair':'hair','NomiWaistFollow':'skirt'}
def main():
 ap=argparse.ArgumentParser(); ap.add_argument('bbmodel',type=Path); ap.add_argument('--animation',default='walk'); ap.add_argument('-o','--output',type=Path,required=True); a=ap.parse_args(); d=json.loads(a.bbmodel.read_text()); anim=next(x for x in d['animations'] if x['name']==a.animation); dur=float(anim.get('length',1)); tracks={}
 for rec in anim.get('animators',{}).values():
  dst=MAP.get(rec.get('name')); 
  if not dst: continue
  vals=[]
  for k in rec.get('keyframes',[]):
   if k.get('channel')!='rotation': continue
   pts=k.get('data_points',[])
   if not pts: continue
   v=pts[0]
   try: vals.append((float(k['time'])/dur,[float(v.get('x',0)),float(v.get('y',0)),float(v.get('z',0))]))
   except (TypeError,ValueError): pass
  if vals: tracks[dst]=sorted(vals)
 out=['-- Extracted from Blockbench: %s / %s'%(a.bbmodel.name,a.animation),'return { id="mc_%s", dur=%.4f, layer=L.LOCOMOTION, loop=true, locomotion=true, keys={'%(a.animation,dur)]
 for n,ks in tracks.items(): out.append('  %s={%s},'%(n,','.join('{%.6f,{%.4f,%.4f,%.4f}}'%(t,*v) for t,v in ks)))
 out.append('}}'); a.output.write_text('\n'.join(out)+'\n'); print('animation',a.animation,'duration',dur,'tracks',sorted(tracks),'keys',sum(map(len,tracks.values())))
if __name__=='__main__': main()
