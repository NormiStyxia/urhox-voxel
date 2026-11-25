#!/usr/bin/env python3
"""龙娘头部白模专版：复用主生成器的头部结构，输出独立 Blockbench 工程和四视图。"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import sys
D=Path(__file__).resolve().parent
sys.path.insert(0,str(D))
import build_longnu as B


def keep_head(g, reached=False):
    # 保留 Root -> ... -> Head 路径，以及 Head 下全部头部部件
    name=g.name
    reached = reached or name == 'Head'
    kept=[]
    for c in g.children:
        if isinstance(c,B.Cube):
            if reached: kept.append(c)
        else:
            if reached or c.name in ('MAllBody','AllBody','UpBody','UpperBody','AllHead','MHead','Head'):
                keep_head(c,reached)
                if c.children: kept.append(c)
    g.children=kept


def collect_bounds(g):
    xs=[];ys=[];zs=[]
    for c in B.iter_cubes(g):
        xs += [c.frm[0],c.to[0]]; ys += [c.frm[1],c.to[1]]; zs += [c.frm[2],c.to[2]]
    return (min(xs),max(xs)),(min(ys),max(ys)),(min(zs),max(zs))


def head_preview(root,atlas):
    faces=B.collect_faces(root)
    views=[('正面',0,0),('左侧',90,0),('背面',180,0),('3/4',35,10)]
    tiles=[]
    for _,yaw,pitch in views:
        arr=B.render(faces,atlas,yaw,pitch,scale=18,size=(420,560),center=(0,30.5,0))
        tiles.append(Image.fromarray(arr))
    sheet=Image.new('RGB',(420*4,600),(225,227,233)); d=ImageDraw.Draw(sheet)
    try: font=ImageFont.truetype('/System/Library/Fonts/Hiragino Sans GB.ttc',22)
    except: font=None
    for i,(name,_,_) in enumerate(views):
        sheet.paste(tiles[i],(420*i,40)); d.text((12+420*i,8),name,fill=(55,55,65),font=font)
    sheet.save(D/'head_whitebox_views.png')
    # face close-up
    arr=B.render(faces,atlas,0,0,scale=46,size=(620,520),center=(0,29.8,0))
    Image.fromarray(arr).save(D/'head_whitebox_face.png')


def main():
    root=B.build(); keep_head(root)
    atlas=B.make_atlas(root)
    n,g=B.export_bbmodel(root,atlas,D/'longnu_head_whitebox.bbmodel')
    head_preview(root,atlas)
    print('head cubes',n,'groups',g,'bounds',collect_bounds(root),'atlas',atlas.shape)

if __name__=='__main__': main()
