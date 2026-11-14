"""Read the actual cached official Radiance assets, no Runtime or network."""
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
BASE=Path('/Users/xd/.taptap-maker/preview/afa0dcff485e9b3b31d610f753bbb7791551aab4723b4b2494f88cc3d9dceabb/storage/runtime-cache/tapcode-sce.spark.xd.com/src/engine-res/assets')
SOURCES={'ClearDay':'FxzWwe_yhfz9b8pFARQcSmzD-efaf0ab3','Dusk':'DwhWeQ46kS_beFuRg38uLsp3-fe560aaf','Night':'Fdb1QTqUZWZiVU3gxHFfHWT6-e9deafc2','Overcast':'Hj5BUaZ2UVC_Imbcv_bUM1Dd-1fa7a84a'}
canvas=Image.new('RGB',(1024,560))
for i,(name,asset) in enumerate(SOURCES.items()):
 with (BASE/(asset+'.hdr')).open('rb') as f:
  while f.readline().strip():pass
  dims=f.readline().split();h,w=int(dims[1]),int(dims[3]);a=np.zeros((h,w,4),dtype=np.uint8)
  for y in range(h):
   assert f.read(4)==bytes([2,2,w//256,w%256])
   for c in range(4):
    x=0
    while x<w:
     count=f.read(1)[0]
     if count>128:
      n=count-128;a[y,x:x+n,c]=f.read(1)[0]
     else:
      n=count;a[y,x:x+n,c]=np.frombuffer(f.read(n),dtype=np.uint8)
     x+=n
  rgb=a[:,:,:3].astype(float)*np.exp2(a[:,:,3].astype(float)-136)[:,:,None]
  # Fixed exposure, Reinhard only for contact-sheet display; original HDR untouched.
  rgb=rgb/(1+rgb);rgb=np.where(rgb<=.0031308,rgb*12.92,1.055*rgb**(1/2.4)-.055)
  tile=Image.fromarray(np.uint8(np.clip(rgb*255,0,255))).resize((512,256))
  x,y=(i%2)*512,(i//2)*280;canvas.paste(tile,(x,y+24));ImageDraw.Draw(canvas).text((x+8,y+6),'OFFICIAL Sky/'+name+'.hdr / fixed exposure',fill='white')
  print(name,'actual HDR',w,h)
canvas.save(Path(__file__).parent/'official-hdr-contact.png')
