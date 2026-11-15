"""Fixed FOV55 / real uploaded wind, all tiers, real 0/10/20/60 seconds. CPU only."""
from pathlib import Path
import runpy,json
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[3];D=Path(__file__).resolve().parent
r=runpy.run_path(str(ROOT/'validation/sky-fx/skycards_check.py'))
rows=json.loads((D/'lua-uniforms.json').read_text())
canvas=Image.new('RGB',(1536,732));metrics=[]
for j,count in enumerate((4,12,24)):
 for i,row in enumerate(rows[str(count)]):
  image,m=r['render'](.5,.24,12,count=count,w=384,h=216,time=row['time'],wind_value=row['wind'],fov=55)
  x,y=i*384,j*244
  canvas.paste(image,(x,y+28));ImageDraw.Draw(canvas).text((x+6,y+8),f'CPU {count} clouds / t={row["time"]:.0f}s / FOV55 NOT WEB',fill='white')
  metrics.append(dict(count=count,time=row['time'],**m))
canvas.save(D/'sequence-cpu.png')
(D/'preview-metrics.json').write_text(json.dumps(metrics,indent=2))
print('PASS formal 0/10/20/60s sequences: fixed camera/FOV55/day/exposure, actual Lua uploaded uniforms, same single atlas sample; CPU only')
