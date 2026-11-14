"""Same actual meshes/camera/DayNight/exposure/budget; CPU, not Web."""
from pathlib import Path
import runpy,json
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2]
DIR=ROOT/'validation/sky-fx'
current=runpy.run_path(str(DIR/'skycards_check.py'))
before={'__file__':str(DIR/'skycards_check.py'),'__name__':'before'}
source=(DIR/'detail-before/skycards_check.py.txt').read_text()
source=source.replace('assets/Textures/Sky/cloud_sculpted_atlas','validation/sky-fx/detail-before/cloud_sculpted_atlas')
source=source.replace('im=im.resize((max(1,im.width//2),max(1,im.height//2)),Image.Resampling.BOX)',
    "im=Image.merge('RGBA',[channel.resize((max(1,im.width//2),max(1,im.height//2)),Image.Resampling.BOX) for channel in im.split()])")
exec(compile(source,str(DIR/'detail-before/skycards_check.py.txt'),'exec'),before)

def main():
    cases=[(.08,.5,12,'DAY / upper large'),(1.51,.29,12,'DAY / middle'),
           (.26,.11,12,'DAY / horizon'),(2,.18,18,'DUSK'),(0,.18,23,'NIGHT')]
    canvas=Image.new('RGB',(960,len(cases)*298));stats=[]
    for i,(yaw,pitch,hour,label) in enumerate(cases):
        for col,renderer in enumerate((before,current)):
            im,m=renderer['render'](yaw,pitch,hour,w=480,h=270)
            canvas.paste(im,(col*480,i*298+28))
            ImageDraw.Draw(canvas).text((col*480+8,i*298+8),('BEFORE / ' if col==0 else 'AFTER / ')+label+' / CPU',fill='white')
            stats.append(dict(case=label,variant=col,**m))
    canvas.save(DIR/'detail-scene-comparison.png')
    # One physical tile under formal shader, shown at 320/160/64 px to expose mip loss.
    atlas=Image.new('RGB',(1280,800));draw=ImageDraw.Draw(atlas)
    for col,renderer in enumerate((before,current)):
        mips=renderer['mipmaps']();_,palette=renderer['geometry'](24,12)
        for row,size in enumerate((320,160,64)):
            yy,xx=np.mgrid[:size,:size];uv=np.stack([(2+(xx+.5)/size)/4,((yy+.5)/size)/2],axis=-1).reshape(-1,2)
            data=renderer['sample'](mips,uv,np.full(size*size,max(0,np.log2(512/size))))
            directions=np.tile([0,.45,.89302855],(size*size,1))
            out,a=renderer['shade'](data,directions,np.array([1,0,0]),palette,.25)
            bg=renderer['background'](directions,palette)
            pixels=renderer['srgb'](out*a[:,None]+bg*(1-a[:,None]))
            im=Image.fromarray(np.rint(pixels.reshape(size,size,3)*255).astype(np.uint8))
            y=(30,390,600)[row];x=col*640+40
            atlas.paste(im,(x,y));draw.text((x,y-20),('BEFORE' if col==0 else 'AFTER')+f' / tile 2 / {size}px / CPU',fill='white')
    atlas.save(DIR/'detail-scale-comparison.png')
    (DIR/'detail-counts.json').write_text(json.dumps(stats,indent=2))
    print('PASS same geometry/time/exposure/quality and actual independent PNGs; 5 views plus 3 angular pixel scales, CPU only')
    print(json.dumps(stats))
if __name__=='__main__':main()
