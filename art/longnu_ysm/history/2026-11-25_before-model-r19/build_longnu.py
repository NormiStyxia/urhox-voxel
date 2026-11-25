#!/usr/bin/env python3
"""龙娘 YSM 体素模型 —— Blockbench 工程生成器

按诺米（~/Downloads/诺米/诺米.bbmodel）的 YSM 骨骼命名与层级搭建：
Root > MAllBody > AllBody > UpBody > UpperBody > AllHead > MHead > Head > Face > Eyes ...
DownBody > Leg > LeftLeg > LeftLowerLeg > LeftFoot ...
新增部件（龙角、尖耳、尾巴、腰侧蝴蝶结与飘带）挂在对应父骨骼下，不改动原有骨骼名。

坐标约定与诺米一致：单位 1/16 方块，脚底 y=0，角色面朝 -Z（north），角色右侧 = +X。
贴图密度 4 px / 单位；每个方块面单独分配 UV 区域并逐面绘制。

输出：longnu.bbmodel、longnu.png、preview.png（离线正交渲染，含参考图对照）
用法：python3 art/longnu_ysm/build_longnu.py
"""
from copy import deepcopy
import base64
import io
import json
from functools import lru_cache
import math
import uuid as uuidlib
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent
PPU = 4  # 贴图像素 / 单位

# ------------------------------------------------------------------ palette
C = {
    "hair": (42,36,48), "hair_soft": (47,41,53), "hair_d": (29,24,34), "hair_l": (58,51,64), "hair_hl": (92, 81, 88),
    "skin": (252, 234, 224), "skin_s": (240, 214, 204), "skin_d": (226, 190, 182),
    "blush": (251, 220, 214), "mouth": (233, 192, 187),
    "white": (250, 250, 251), "white_s": (230, 230, 236), "white_d": (206, 206, 216),
    "pleat": (240, 239, 244), "black": (40, 34, 38), "black_l": (60, 52, 58),
    "red": (230, 44, 49), "red_s": (168, 20, 28), "red_d": (124, 12, 20), "red_l": (232, 70, 66),
    "flower": (177, 23, 33), "flower_s": (120, 10, 22), "flower_c": (84, 6, 14),
    "tail": (122, 58, 70), "tail_d": (98, 42, 56), "tail_l": (142, 74, 86),
    "horn": (240, 202, 202), "horn_s": (222, 170, 176), "horn_d": (200, 146, 154),
    "cord": (20,16,26), "gold": (176,138,60), "gold_d": (138,106,42),
    "hood_gold": (156,122,48), "hood_gold_d": (122,92,34),
    "lock":(48,41,52), "lock_d":(37,31,42), "lock_l":(58,50,62),
    "bow_red": (207,42,47), "bow_edge": (140,26,36),
    "gem": (200, 24, 36), "gem_l": (250, 120, 120), "silver": (200, 200, 210),
    # 眼睛
    "lash": (42, 20, 24), "lash_m": (78, 40, 46),
    "scl": (255, 251, 250), "scl_s": (226, 214, 220),
    "iris_d": (112, 10, 22), "iris": (196, 24, 34), "iris_l": (239, 59, 60), "iris_o": (246, 128, 98),
    "pupil": (64, 4, 14), "hl": (255, 255, 255),
}



# ------------------------------------------------------------------ painters
# painter(face, w, h, cube) -> HxWx4 uint8，face 方向看过去的左上为 (0,0)

def rgba(c, a=255):
    return np.array([c[0], c[1], c[2], a], np.uint8)


def flat(key, edge=None):
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C[key])
        if edge and face not in ("up", "down") and h >= 3:
            a[-1, :] = rgba(C[edge])
        return a
    return p


def hair(tone="hair"):
    """让几何转折决定明暗，整块着色。"""
    side_tones = {"hair_soft": (51, 44, 48), "hair_d": (33, 28, 31), "hair": (48, 41, 46), "hair_l": (66, 57, 63)}
    def paint(face, w, h, cube):
        color = C[tone]
        if face in ("east", "west"):
            color = side_tones[tone]
        elif face == "up":
            color = C["hair_hl" if tone == "hair_l" else "hair_l"]
        elif face == "down":
            color = C["hair_d"]
        return np.full((h, w, 4), rgba(color), np.uint8)
    return paint

def horn(tier=2):
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        base = C["horn_s"] if face in ("east", "west", "south") else C["horn"]
        a[:] = rgba(tuple(channel + (tier-2)*3 for channel in base))
        return a
    return p


def tail(t):
    """t 0→1 从尾根到尾尖：颜色渐深，背脊一列提亮。"""
    base = np.array(C["tail"]) * (1 - t) + np.array(C["tail_d"]) * t

    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(tuple(int(v) for v in base))
        if face == "up":
            a[:] = rgba(tuple(int(min(255, v * 1.12)) for v in base))
        return a
    return p


def flower():
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C["flower_c"] if cube.role == "core" else C["flower"])
        if cube.role != "core" and face not in ("up", "down") and h >= 2:
            a[-1, :] = rgba((160, 20, 32))
        return a
    return p


def bow_paint(key="red"):
    def paint(face, w, h, cube):
        shade = ({"red": "red_s", "red_s": "red_d"}[key]
                 if face in ("down", "west") else key)
        return np.full((h, w, 4), rgba(C[shade]), np.uint8)
    return paint

def bodice(face,w,h,cube):
    tone = "white_s" if face in ("east","west","down") else "white"
    pixels = np.full((h,w,4),rgba(C[tone]),np.uint8)
    if face == "north" and cube.name == "胸身":
        row,col = np.indices((h,w))
        x = np.abs((col+.5)/w-.5)*6.8
        drop = (row+.5)/h*4.3
        pixels[x < 1.19*(1-drop/1.45)] = rgba(C["skin"])
    return pixels


def skin_part(shade_bottom=False):
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C["skin"])
        if shade_bottom and face not in ("up", "down"):
            a[-1:, :] = rgba(C["skin_s"])
        return a
    return p


@lru_cache(maxsize=1)
def nomi_model():
    return json.loads((Path.home()/"Downloads/诺米/诺米.bbmodel").read_text())


@lru_cache(maxsize=1)
def nomi_source():
    model = nomi_model()
    texture = Image.open(io.BytesIO(base64.b64decode(model["textures"][0]["source"].split(",",1)[1]))).convert("RGBA")
    groups = {g["uuid"]:g for g in model["groups"]}
    elements = {e["uuid"]:e for e in model["elements"]}
    nodes = {}
    def visit(node):
        nodes[groups[node["uuid"]]["name"]] = node
        for child in node["children"]:
            if isinstance(child,dict):
                visit(child)
    for node in model["outliner"]:
        visit(node)
    return texture,groups,elements,nodes


def template_parts(name):
    _,_,elements,nodes = nomi_source()
    return [elements[k] for k in nodes[name]["children"] if isinstance(k,str)]


@lru_cache(maxsize=1)
def iris_palette():
    tex = nomi_source()[0]
    colors = set()
    for side in ("RightPupil","LeftPupil"):
        uv = template_parts(side)[0]["faces"]["north"]["uv"]
        colors.update(tex.crop(tuple(uv)).convert("RGB").getdata())
    shades = sorted((c for c in colors if min(c)<210),key=lambda c:np.dot(c,(.2126,.7152,.0722)))
    reds = [(62,10,18),(90,14,24),(140,26,36),(179,35,44),(207,58,63)]
    assert len(shades)==len(reds)
    return {**dict(zip(shades,reds)),**{c:(241,232,230) for c in colors if c not in shades}}


def copy_nomi_group(name,red=False):
    texture,groups,elements,nodes = nomi_source()
    def copy(node):
        src = groups[node["uuid"]]
        g = Group(src["name"],src["origin"],src["rotation"])
        g.uuid = src["uuid"]
        for key in node["children"]:
            if isinstance(key,dict):
                g.children.append(copy(key))
                continue
            e = elements[key]
            c = g.c(e["name"],e["from"],e["to"],None,origin=e["origin"],rot=e.get("rotation",(0,0,0)),inflate=e.get("inflate",0))
            c.uuid = key
            c.tiles = {}
            c.uv_insets = {}
            for face,info in e["faces"].items():
                x,y,u,v = info["uv"]
                left,top=math.floor(min(x,u)),math.floor(min(y,v))
                right,bottom=math.ceil(max(x,u)),math.ceil(max(y,v))
                tile = np.array(texture.crop((left,top,right,bottom)))
                c.uv_insets[face] = (x-left if x<=u else right-x, y-top if y<=v else bottom-y,
                                      right-u if x<=u else u-left, bottom-v if y<=v else v-top)
                if x>u: tile = tile[:,::-1]
                if y>v: tile = tile[::-1]
                if info.get("rotation"): tile = np.rot90(tile,-info["rotation"]//90)
                if red and g.name.endswith("Pupil"):
                    original = tile.copy()
                    for old,new in iris_palette().items():
                        tile[np.all(original[:,:,:3]==old,axis=2),:3] = new
                if red and g.name=='Face' and c.name!='乳白浅眼窝底':
                    key_color={'轻颊色':'blush','下唇一笔':'mouth'}.get(c.name,
                              'skin' if face in ('north','south','up') else 'skin_s')
                    tile[:]=rgba(C[key_color])
                c.tiles[face] = tile
        return g
    return copy(nodes[name])


# ------------------------------------------------------------------ model types
class Cube:
    def __init__(self, name, frm, to, paint, origin=None, rot=(0, 0, 0), inflate=0.0, **kw):
        self.name = name
        self.frm = [float(v) for v in frm]
        self.to = [float(v) for v in to]
        if not all(math.isfinite(a) and math.isfinite(b) and a < b for a, b in zip(self.frm, self.to)):
            raise ValueError(f"无效方块 {name}: {frm} -> {to}")
        self.paint = paint
        self.origin = list(origin) if origin is not None else [(a + b) / 2 for a, b in zip(self.frm, self.to)]
        self.rot = list(rot)
        self.inflate = inflate
        self.role = kw.pop("role", "")
        self.uuid = str(uuidlib.uuid5(uuidlib.NAMESPACE_URL, "longnu/" + name + str(frm) + str(to)))
        self.faces = {}


class Group:
    def __init__(self, name, origin, rot=(0, 0, 0)):
        self.name = name
        self.origin = [float(v) for v in origin]
        self.rot = list(rot)
        self.children = []
        self.uuid = str(uuidlib.uuid5(uuidlib.NAMESPACE_URL, "longnu-group/" + name))

    def g(self, name, origin, rot=(0, 0, 0)):
        for child in self.children:
            if isinstance(child, Group) and child.name == name:
                return child
        c = Group(name, origin, rot)
        self.children.append(c)
        return c

    def c(self, *a, **kw):
        cube = Cube(*a, **kw)
        self.children.append(cube)
        return cube


def mirror_x(v):
    return [-v[0], v[1], v[2]]


def box(cx0, cx1, y0, y1, z0, z1):
    return [min(cx0, cx1), y0, min(z0, z1)], [max(cx0, cx1), y1, max(z0, z1)]


# ------------------------------------------------------------------ build
def nomi_skeleton():
    """保留诺米 BB 工程的轴系、原始 UUID 和全部定位器，Bedrock 的 X 轴与其相反。"""
    nodes = {}
    for row in json.loads((OUT / "ref/nomi_rig.json").read_text()):
        bone = Group(row["name"], row["origin"], row["rotation"])
        bone.uuid = row["uuid"]
        nodes[bone.name] = bone
        if row["parent"] is not None:
            nodes[row["parent"]].children.append(bone)
    return nodes


def skirt_section(bone, name, upper_edge, lower_edge, tone):
    # 每片都是向外倾斜的折面，以接缝两端的中点确定布料走向。
    high, low = np.mean(upper_edge,axis=0), np.mean(lower_edge,axis=0)
    up = high - low
    height = np.linalg.norm(up)
    up /= height
    edge = upper_edge[1] - upper_edge[0] + lower_edge[1] - lower_edge[0]
    normal = np.cross(edge,up)
    normal /= np.linalg.norm(normal)
    right = np.cross(up,normal)
    inverse = rot_matrix(bone.rot).T
    rotation = inverse @ np.column_stack((right,up,normal))
    angles = np.degrees([math.atan2(rotation[2,1],rotation[2,2]),
                         math.asin(-rotation[2,0]),math.atan2(rotation[1,0],rotation[0,0])])
    pivot = np.asarray(bone.origin)
    center = pivot + inverse @ ((high+low)/2 - pivot)
    width = max(np.linalg.norm(e[1]-e[0]) for e in (upper_edge,lower_edge))
    half = np.array([width+.10,height+.10,.20])/2
    bone.c(name,center-half,center+half,flat(tone),rot=angles)


def back_folds(tile, face, cube):
    # 按模型坐标给现有 UV 上色，让两块布在同一高度的折影接续。
    corners = np.asarray(face_quads(cube)[face]); h,w = tile.shape[:2]
    u = (np.arange(w)[None,:,None]+.5)/w
    v = (np.arange(h)[:,None,None]+.5)/h
    points = corners[0] + u*(corners[1]-corners[0]) + v*(corners[3]-corners[0])
    x,y = points[:,:,0],points[:,:,1]
    flare = 1+.13*np.clip((23-y)/11,0,1)
    for ridge in (-4.55,-2.75,-.95,.95,2.75):
        dist=np.abs(x-ridge*flare)
        region=(y>=11.65)&(y<=23.35)
        tile[region & (dist<.59)] = rgba(C['hair'])
        tile[region & (dist<.31)] = rgba(C['cord'])


def coat_cloth(kind="plain", decorated_face=None, burn_range=None):
    def paint(face,w,h,cube):
        base = 'hair_l' if face=='up' else 'cord' if face in ('down','west') else 'hair' if face=='south' or kind in ('back','rear_flower','center_flower') else 'hair_d'
        if face not in ('up','down'):
            base='hair_d' if kind in ('sleeve','rear_flower','center_flower','back') else 'cord'
        tile = np.full((h,w,4),rgba(C[base]),np.uint8)
        if kind in ('back','upper_back','rear_flower','center_flower') and face in ('north','south'):
            tile[:]=rgba(C['hair_d']);back_folds(tile,face,cube)
        if burn_range:
            stops = [(0,(29,24,34)),(.40,(57,20,30)),(.68,(90,14,24)),(1,(42,20,16))]
            levels = np.linspace(*burn_range,h) if face not in ('up','down') else [burn_range[face=='down']]*h
            for row,t in enumerate(levels):
                tile[row,:,:3] = [np.interp(t,[v for v,_ in stops],[col[k] for _,col in stops]) for k in range(3)]
        if face != decorated_face:
            return tile
        # 绣花单独留出花蕊和描底的像素空间。袖口提高 UV 密度以维持小花的可见尺寸。
        n=14 if kind=='center_flower' else 12
        if kind=='sleeve':
            tile=np.repeat(np.repeat(tile,2,axis=0),2,axis=1)
        image=Image.fromarray(tile); w,h=image.size
        if w<n+2 or h<n+6:
            image=image.resize((max(w,n+2),max(h,n+6)),Image.Resampling.NEAREST)
            w,h=image.size
        left=(w-n)//2
        if kind=='rear_flower':left=w-n-1 if decorated_face=='north' else 1
        top=max(4,min(h-n-2,(h-n)//2))
        thread=Image.new('RGBA',(w,h));pen=ImageDraw.Draw(thread)
        def point(px,py):return (left+round(px*(n-1)/11),top+round(py*(n-1)/11))
        petals=[((2,4),(0,2),(1,1)),((3,2),(3,0),(4,0)),((6,2),(8,0),(9,0)),
                ((8,4),(10,2),(11,3)),((8,6),(10,7),(11,6)),((7,8),(9,10),(10,10)),
                ((4,8),(3,10),(2,10)),((2,6),(0,7),(0,6))]
        for knee,tip,hook in petals:
            pen.line([point(5,5),point(*knee)],fill=(140,20,32),width=2)
            pen.line([point(*knee),point(*tip),point(*hook)],fill=(208,42,48),width=2)
        # 两条花蕊各在上方留出三个像素，沿不同的弧线穿过花瓣间的深色空隙。
        for line,end_x in [([(4,4),(2,3),(1,1)],0), ([(6,4),(7,3),(9,1)],10)]:
            pen.line([point(*v) for v in line]+[(point(end_x,0)[0],top-3)],fill=C['gold_d'],width=2)
        pen.line([point(5,5),point(6,8),point(8,11),point(10,11)],fill=C['gold_d'],width=1)
        cx,cy=point(5,5);pen.rectangle((cx-1,cy-1,cx+2,cy+2),fill=(122,15,24))
        pen.point((cx,cy),fill=C['gold_d'])
        outline=thread.getchannel('A').filter(ImageFilter.MaxFilter(3))
        image.paste((*C['cord'],255),(0,0,w,h),outline);image.alpha_composite(thread)
        return np.asarray(image)
    return paint


def coat_outline(side,y):
    u=np.clip((20.12-y)/9.12,0,1)
    waist=np.array([(2.65,-3.15),(4.93,-3.24),(5.04,-.38),(3.27,2.70),(0,3.38)])
    base=np.array([(3.18,-4.15),(6.26,-4.05),(7.03,-.48),(5.64,5.60),(0,6.10)])
    # 上胯快速放量，在白裙最宽处进入较缓的下摆斜度。
    path=waist+(base-waist)*(u+.52*u*(1-u))
    if side<0:
        path[:2,1]-=.04*u
        path[1,0]+=.94*u
    else:
        path[3,1]+=1.98*u;path[4,1]+=.94*u
    path[2:4,0]+=.55*u
    # 后摆中央为尾干留出开衩，开衩上方仍是整幅后背。
    path[4,0]=np.interp(y,[10.0,13.9,15.5,16.66],[2.48,2.22,1.52,0])+(1.65 if side>0 else 0)*np.clip((16.66-y)/2.7,0,1)
    return np.array([(side*x,y,z) for x,z in path])


def add_coat(rig):
    shell = rig["CoatShell"]
    cloth = coat_cloth()
    def plate(parent,name,center,size,paint,rotation=(0,0,0)):
        c=np.array(center);half=np.array(size)/2
        return parent.c(name,c-half,c+half,paint,rot=rotation)
    for e in template_parts("CoatShell"):
        name=e['name'];lo,hi=np.array(e['from']),np.array(e['to']);c=(lo+hi)/2;size=hi-lo
        if '挂绳' in name or '压头' in name:continue
        if '背幅' in name:
            c[0]=0;size[0]=7.45;c[2]=2.40;size[2]=.40
            if "下" in name:c[2]=3.17
        elif '披肩' in name:
            size[2]-=.82;c[2]-=.48;size[0]-=.30
        elif '腰侧' in name:
            c[0]=np.sign(c[0])*3.67;size[0]=.42
        elif '敞襟' in name:
            c[0]=np.sign(c[0])*3.13;size[0]=1.85;c[2]=-2.46;size[2]=.24
            if c[0]<0:
                size[1]-=2.04;c[1]+=1.02
        elif '领襟' in name:
            c[0]=np.sign(c[0])*1.88;c[2]=-2.69
        plate(shell,name,c,size,coat_cloth("upper_back") if "背幅" in name else cloth,e.get('rotation',(0,0,0)))
    plate(shell,'上背折肩',(0,23.75,2.48),(8.80,3.82,.26),coat_cloth('upper_back'))
    for side in (-1,1):
        # A folded return closes the slit between the side panel and the layered back shell.
        plate(shell,f'肩胛内折{side}',(side*2.95,23.39,2.27),(.55,3.30,1.00),cloth)
        plate(shell,f'下背内折{side}',(side*3.70,21.04,2.52),(1.16,2.16,1.66),cloth)
        for i,(a,b) in enumerate(zip(((.85,24.81,-2.88),(1.14,24.45,-2.83),(1.77,22.40,-3.17)),
                                    ((1.14,24.45,-2.83),(1.77,22.40,-3.17),(2.94,20.07,-3.38)))):
            strand(shell,f'领襟金线{side}_{i}',(side*a[0],*a[1:]),(side*b[0],*b[1:]),.60,.20,flat('gold'))
        for i,(a,b) in enumerate(zip(((.85,25.65,2.82),(3.14,25.30,2.20),(3.63,25.42,-1.30)),
                                    ((3.14,25.30,2.20),(3.63,25.42,-1.30),(1.35,24.65,-2.60)))):
            strand(shell,f'肩线{side}_{i}',(side*a[0],*a[1:]),(side*b[0],*b[1:]),.42,.22,flat('gold_d'))
    plate(shell,'金饰扣',(0,24.92,-3.04),(.78,.78,.25),flat('gold'),(0,0,45))
    plate(shell,'扣心',(0,24.92,-3.22),(.45,.45,.16),flat('gold_d'),(0,0,45))
    strand(shell,'红绳坠',(0,24.62,-2.83),(.11,23.65,-2.73),.15,.14,flat('red_s'))
    def facet(bone,name,a,b,c,d,tone,overlap=.22,offset=0,thickness=.18):
        mid1=(a+b)/2;mid2=(c+d)/2
        x=b-a+d-c;x/=np.linalg.norm(x)
        up=mid1-mid2;up-=x*np.dot(x,up);h=np.linalg.norm(up);up/=h
        norm=np.cross(x,up)
        M=np.column_stack((x,up,norm));rot=np.degrees([math.atan2(M[2,1],M[2,2]),math.asin(-M[2,0]),math.atan2(M[1,0],M[0,0])]);center=(mid1+mid2)/2
        out=norm if np.dot(norm[[0,2]],center[[0,2]])>0 else -norm
        extent=np.array([a,b,c,d])@x
        center+=x*((extent.min()+extent.max())/2-np.dot(center,x))
        w=np.ptp(extent)+overlap
        plate(bone,name,center+out*offset,(w,h+.12,thickness),tone,rot)
        return out
    hood=rig['NomiHood']
    # 横向的折面从后颈绕至肩外，再转到领前。背中帽口低于两侧，露出深色凹口。
    rim=[(0,25.74,6.02),(1.72,26.03,5.96),(2.94,26.65,5.45),
         (3.65,27.28,4.01),(4.12,27.84,2.14),(4.52,28.19,1.26)]
    hem=[(0,23.02,5.77),(1.41,23.28,5.70),(2.47,23.84,5.23),
         (3.16,24.51,4.00),(3.68,25.10,2.22),(4.48,25.62,1.23)]
    for sign,tag in ((-1,'Left'),(1,'Right')):
        def pt(v):return np.array([sign*v[0],v[1],v[2]])
        for i in range(len(rim)-1):
            a,b=map(pt,rim[i:i+2]);c,d=map(pt,hem[i:i+2])
            if i==len(rim)-2:
                plate(hood,tag+'帽口侧折',pt((4.37,26.97,1.67)),(.35,3.06,1.16),flat('hair'))
            else:
                facet(hood,tag+f'兜帽围面{i}',a,b,c,d,flat('hair'),.10,0,.46)
            rim_offset=np.array([sign*(.04 if i<3 else -.26),-.55,.42 if i<4 else -.14])
            strand(hood,tag+f'兜帽金口{i}',a+rim_offset,b+rim_offset,.50,.20,flat('hood_gold',edge='hood_gold_d'))
            facet(hood,tag+f'兜帽里折{i}',a-[0,.09,.20],b-[0,.09,.20],c-[0,0,1.88],d-[0,0,1.88],flat('cord'),.04,-.12,.19)
        cape=hood.g(tag+'ShoulderCape',pt((3.65,26.08,1.04)))
        end=cape.g(tag+'ShoulderCapeTip',pt((3.63,25.35,-.73)))
        back,mid,front=map(pt,((3.65,26.08,1.04),(3.63,25.35,-.73),(2.45,24.54,-2.60)))
        for idx,(g,high,low,w) in enumerate(((cape,back,mid,1.36),(end,mid,front,1.12))):
            strand(g,tag+f'肩披{idx}',high,low,w,.33,flat('hair'))
            stripe=np.array([sign*.43,.08,0]);strand(g,tag+f'肩披滚边{idx}',high+stripe,low+stripe,.19,.16,flat('gold_d'))
    strand(hood,'兜帽中折',(0,25.38,6.28),(0,23.12,6.05),.20,.16,flat('cord'))
    pendant=hood.g('HoodPendant',(0,23.18,5.79));tip=pendant.g('HoodPendantTip',(0,20.67,5.59))
    widths=(3.60,2.94,2.02,1.20)
    heights=(23.18,22.01,20.67,19.32,18.58)
    def pendant_trim(width,next_width,first):
        def paint(face,w,h,cube):
            tile=flat('hair')(face,w,h,cube)
            if face not in ('north','south'):return tile
            # 10 像素/单位使跨台阶的 0.4 宽沿线在每个转角都相接。
            pw=round(width*10);ph=round((cube.to[1]-cube.frm[1])*10)
            tile=np.full((ph,pw,4),rgba(C['hair']),np.uint8)
            ledge=round((width-next_width)*5)+4 if next_width else pw
            tile[-4:,:ledge]=tile[-4:,-ledge:]=rgba(C['hood_gold_d'])
            if first:tile[:4]=rgba(C['hood_gold_d'])
            return tile
        return paint
    for i,width in enumerate(widths):
        bone=pendant if i<2 else tip
        high,low=heights[i:i+2];z=(5.80,5.70,5.59,5.49)[i]
        plate(bone,f'坠帽垂尖{i}',(0,(high+low)/2,z),(width,high-low,.62),
              pendant_trim(width,widths[i+1] if i<3 else 0,i==0))
        for sign in (-1,1):
            plate(bone,f'坠帽金绲{sign}_{i}',(sign*(width/2-.20),(high+low)/2,z+.32),
                  (.40,high-low,.06),flat('hood_gold_d'))
    # 肘部套腔与腕口分开，用局部四壁保留空腔和手背活动间隙。
    for nm in ('Left','Right'):
        for limb,next_name in [('Arm','ForeArm'),('ForeArm','Hand')]:
            bone=rig[nm+limb+'Coat'];a=np.array(bone.origin);b=np.array(rig[nm+next_name].origin)
            if limb=='ForeArm': b=a+(b-a)*(16.84-a[1])/(b[1]-a[1])
            v=b-a;length=np.linalg.norm(v);rot=(-math.degrees(math.asin(v[2]/length)),0,math.degrees(math.atan2(v[0],-v[1])))
            frame=rot_matrix(rot);c=(a+b)/2
            for dim in (0,2):
                for sign in (-1,1):
                    for k,(start,stop,outer) in enumerate(((0,length*.48,1.50),(length*.48,length,1.78)) if limb=='Arm' else ((0,length-3.4,2.07),(length-3.4,length,2.40))):
                        size=np.array([2*outer,stop-start+.10,2*outer]);size[dim]=.20
                        off=np.zeros(3);off[dim]=sign*(outer-.10);off[1]=length/2-(start+stop)/2
                        tone=coat_cloth('sleeve','north') if limb=='ForeArm' and dim==2 and sign<0 and k==1 else cloth
                        plate(bone,nm+limb+f'袖壁{dim}_{sign}_{k}',c+frame@off,size,tone,rot)
                        if dim==2 and sign==1:
                            crease=off.copy();crease[2]+=.13;crease[0]+=.62
                            plate(bone,nm+limb+f'袖背折痕{k}',c+frame@crease,(.30,size[1],.075),flat('cord'),rot)
                    if limb=='ForeArm':
                        size[1]=.60;size[dim]=.20;off[dim]=sign*2.51;off[1]=-length/2+.36
                        plate(bone,nm+f'袖口金{dim}_{sign}',c+frame@off,size,flat('gold'),rot)
    pivots=json.loads((OUT/'ref/longnu_coat_pivots.json').read_text())
    for name,xyz in pivots.items():rig[name].origin=xyz
    # 共用五个接点构成四片，左右两半在背中相接。横截面由腰到摆连续插值。
    def gold_strip(bone,name,start,end):
        along=end-start; length=np.linalg.norm(along);along=along/length
        normal=np.cross(along,[0,1,0]);normal/=np.linalg.norm(normal)
        axes=np.column_stack((along,np.cross(normal,along),normal))
        rot=np.degrees([math.atan2(axes[2,1],axes[2,2]),math.asin(-axes[2,0]),math.atan2(axes[1,0],axes[0,0])])
        plate(bone,name,(start+end)/2,(length+.10,.50,.18),flat('gold'),rot)

    for sign,tag in ((-1,'L'),(1,'R')):
        waist=rig['NomiCoatLeft' if sign<0 else 'NomiCoatRight']
        # 各段裾线共用端点，同一圈前、侧、后片逐级转向。
        heights=(12.24,12.23,12.56,12.50,12.13)
        border=[]
        nudges=((.30,-.24),(.18,-.26),(.34,0),(.22,.30),(0,.31))
        for index,(height,(dx,dz)) in enumerate(zip(heights,nudges)):
            pt=coat_outline(sign,height)[index]+[sign*dx,0,dz]
            border.append(pt)
        tip_index=0 if sign<0 else 23
        for j in range(4):
            pref=f'NomiCoat{tag}{j}';hip=rig[pref+'Hip'];hem=rig[pref+'Hem']
            hem_y=11.54-.32*j + (1.14 if sign>0 and j==2 else .68 if sign>0 and j==3 else 0)
            cuts=(20.12,18.43,17.13,14.90 if j in (2,3) else 16.66,hem_y)
            for k,(hi,lo,bone) in enumerate(zip(cuts,cuts[1:],(waist,hip,hip,hem))):
                a,b=coat_outline(sign,hi)[j:j+2];c,d=coat_outline(sign,lo)[j:j+2]
                tone=coat_cloth('back' if j>=2 else 'plain')
                if k==3 and j in (0,3):tone=coat_cloth('rear_flower' if j==3 else 'front_flower','north' if sign>0 else 'south')
                out=facet(bone,pref+f'连摆{k}',a,b,c,d,tone,overlap=.32,offset=.024*(j%2))
                if j==0:
                    step=(b-a)/np.linalg.norm(b-a);bottomstep=(d-c)/np.linalg.norm(d-c)
                    # 局部短轴固定为 0.6，倾斜的上下接点不再把条带包围盒撑宽。
                    upper_edge=a+.30*step+out*.20;lower_edge=c+.30*bottomstep+out*.20
                    if k==3:lower_edge=border[0]
                    strand(bone,pref+f'金襟{k}',upper_edge,lower_edge,.60,.20,flat('gold'))
                if j==3 and sign==1 and k<3:
                    strand(bone,pref+f'背褶{k}',b+[.22*(k%2),0,.21],d+[.22*((k+1)%2),0,.21],.16,.10,flat('gold_d'))
                if k==3:
                    gold_strip(bone,pref+'摆底金环',border[j],border[j+1])
                # 腰部固定的整圈里布将接缝两侧都接回各自裁片内侧。
                # 动态外片遮盖这层薄布，摆开时显露深色褶里。
                facet(waist,pref+f'内衬{k}',a,b,c,d,flat('hair_d'),.52,-.21,.13)
            tips=[ch for ch in hem.children if isinstance(ch,Group) and 'Tat' in ch.name];top=coat_outline(sign,hem_y)
            for k,bone in enumerate(tips):
                a,b=top[j:j+2];p=a+(b-a)*k/len(tips);q=a+(b-a)*(k+.92)/len(tips)
                # 以整圈 24 个尖分五组。倒序经过右摆，使两侧的断口自然错落。
                deep=(.80,1.52,2.14,1.60,1.34)[tip_index%5]
                tip_index -= sign
                for tier,(t0,t1,shrink) in enumerate(((0,.46,.025),(.46,.76,.08),(.76,1,.19))):
                    u=p+(q-p)*shrink;v=q-(q-p)*shrink;fall=np.array([0,-deep,0])
                    facet(bone,pref+f'焦边{k}_{tier}',u+t0*fall,v+t0*fall,u+t1*fall,v+t1*fall,
                          coat_cloth(burn_range=(t0,t1)),0,0,.18)
    plate(rig['NomiCoatR3Hem'],'背中绣幅',(0,16.75,5.57),(3.78,3.06,.16),
          coat_cloth('center_flower','south'),(-20,0,0))


def build():
    """全部坐标按诺米 .bbmodel 实测：腿 0–18.7、躯干 18.8–25.8、颈 25.3–27.5、脸 26.6–33.0（宽 7.4）、肩 25.3。"""
    rig = nomi_skeleton()
    root = rig["Root"]
    mall = root.g("MAllBody", (0, 19.3, 0))
    allb = mall.g("AllBody", (0, 19.3, 0))
    upb = allb.g("UpBody", (0, 19.3, 0))
    upper = upb.g("UpperBody", (0, 19.3, 0))
    FZ = -3.5  # 脸正面 z

    # ---------------- 头
    allhead = upper.g("AllHead", (0, 26.75, 0))
    mhead = allhead.g("MHead", (0, 26.75, 0))
    head = mhead.g("Head", (0, 26.0, 0))
    head.children[head.children.index(rig["Face"])] = copy_nomi_group("Face",red=True)
    head.g("ViewLocator", (0, 29.4, FZ))

    hairg = head.g("Hair", (0, 30.5, 0.4))
    bh = hairg.g("BaseHair", (0, 30, 1))
    oh = hairg.g("OuterHair", (0, 34, 0))
    fr = hairg.g("front_h1", (0, 33.1, -3.6))
    overlay = fr.g("FringeOverlay", (0, 32, -3.8))
    # 发冠由贯穿高度的竖束铺成，束顶按椭圆截面收低。
    xcuts = (-6.34,-5.84,-5.13,-4.19,-3.17,-1.82,0,1.82,3.17,4.19,5.13,5.84,6.34)
    zcuts = (-5.29,-4.74,-3.91,-2.80,-1.43,.10,1.63,3.02,4.36,5.38,6.08)
    for k,(x0,x1) in enumerate(zip(xcuts,xcuts[1:])):
        for j,(z0,z1) in enumerate(zip(zcuts,zcuts[1:])):
            radius = (((x0+x1)/2)/6.52)**2 + (((z0+z1)/2-.28)/5.83)**2
            if radius > 1:
                continue
            height = min(38,round((32.30+5.83*math.sqrt(1-radius))*4)/4)
            base_y = 33.0 if x0 < 3.57 and x1 > -3.68 and z0 < 3.22 and z1 > -3.5 else 31.88
            if z0 < -3.4 and 1.3<abs((x0+x1)/2)<2.8:base_y=max(base_y,32.93)
            # Keep the crown height profile while bringing its front rows behind the new fringe.
            z0,z1 = [float(np.interp(z,[-5.29,-4.74,-3.91,-2.80,6.08],[-4.05,-3.87,-3.65,-2.80,6.08])) for z in (z0,z1)]
            bh.c(f"顶发条{k}·{j}",(x0,base_y,z0),(x1,height,z1),hair())
    # 按正面批注的下缘截线裁出八束。每一级是同一宽发束的一层，正面共面。
    for side in (-1,1):
        peak_x,peak_y=(1.98,32.84) if side>0 else (1.74,32.44)
        spans=(
            ([(0,30.09),(.75,30.04),(1.04,30.15),(peak_x-.47,30.87),(peak_x-.19,31.85),(peak_x,peak_y)],35.9,-4.34,1.20,'lock'),
            ([(peak_x,peak_y),(peak_x+.36,peak_y-.73),(3.02,31.12)],35.65,-4.16,1.18,'lock_d'),
            ([(3.02,31.12),(3.65,30.55),(4.30,30.13 if side>0 else 30.31)],35.22,-4.23,1.20,'lock_l'),
            ([(4.30,30.13 if side>0 else 30.31),(5.05,29.89),(5.75,29.64)],34.82,-4.16,1.10,'lock'))
        for k,(edge,high,front,depth,tone) in enumerate(spans):
            xs,ys=np.array(edge).T;floor=min(ys);ceiling=max(ys)
            pivot=(side*(xs[0]+xs[-1])/2,high,front+depth/2)
            fr.c(f'刘海{side}_{k}',*box(side*xs[0],side*xs[-1],ceiling,high,front,front+depth),
                 flat(tone),rot=(2,0,0),origin=pivot)
            bands=np.linspace(floor,ceiling,max(2,math.ceil((ceiling-floor)/.21)+1))
            for tier,(lo,hi) in enumerate(zip(bands,bands[1:])):
                # 用水平截面求整束边界，保留中央的微平底和逐级挑高的眉峰。
                inside=[x for x,y in edge if y<=(lo+hi)/2]
                for (x0,y0),(x1,y1) in zip(edge,edge[1:]):
                    t=((lo+hi)/2-y0)/(y1-y0) if y0!=y1 else -1
                    if 0<=t<=1:inside.append(x0+t*(x1-x0))
                if len(inside)<2:continue
                overlay.c(f'刘海收阶{side}_{k}_{tier}',*box(side*min(inside),side*max(inside),lo,hi,
                          front,front+depth),flat(tone),rot=(2,0,0),origin=pivot)
    for i in range(15):
        x = (i-7)*.79
        edge = abs(x)/5.53
        back = 6.29-1.38*edge**2 + (.12 if i%2 else 0)
        low = 25.50+1.81*edge**1.65 + (.28 if i%2 else 0)
        if abs(x)>3.0: low=max(low,26.88+(max(0,abs(x)-3.95)*2.65))
        high = 34.40+1.10*(1-edge**2)
        back_tone = "hair" if i % 2 else "hair_d"
        oh.c(f"后颅纵束{i}",(x-.40,low,3.25),(x+.40,high,back-.83),hair(back_tone))
        oh.c(f"后颅外束{i}",(x-.38,low+.24,back-.92),(x+.38,high-1.23,back),flat(back_tone))

    flh = hairg.g("FLongHair", (0, 27.6, 2.3))
    mlh = flh.g("MLongHair", (0, 27.5, 2.3))
    lh = mlh.g("LongHair", (0, 27.45, 2.3))
    rib = hairg.g("Ribbon", (0, 28.6, -.5))
    for side, nm in ((1, "Right"), (-1, "Left")):
        def paired(group, name, x0, x1, y0, y1, z0, z1, paint, **kw):
            return group.c(nm + name, *box(side*x0, side*x1, y0, y1, z0, z1), paint, **kw)
        # 模板侧颊向外转折，鬓底留在其外侧；后颈的暗发仍承托花饰。
        for j,(z0,z1) in enumerate(((-3.36,-1.05),(-1.05,1.46),(1.46,4.42))):
            for k,(low,high,outer) in enumerate(((26.80,28.15,4.45),(28.15,29.60,4.67),
                       (29.60,30.85,4.89),(30.85,32.00,5.15),(32.00,34.60,5.52))):
                paired(bh,f'鬓底纵束{j}_{k}',3.95,outer,low,high,z0,z1,flat('lock_d'))
        for k,(low,high,outer) in enumerate(((26.51,28.15,4.65),(28.15,29.60,4.78),
                         (29.60,30.85,5.02),(30.85,32.28,5.31))):
            paired(bh,f'耳后覆发{k}',4.22,outer,low,high,.14,4.45,flat('lock'))
        paired(bh,'耳根',4.65,5.06,28.85,30.06,-.76,-.01,skin_part())
        prefix='corner_h1' if side>0 else 'corner_h2'
        cg=hairg.g(prefix,(side*4.65,33,-2.81));cg.origin=[side*4.65,33,-2.81]
        cm=cg.g(prefix+'_mid',(side*4.48,28,-2.95));ct=cm.g(prefix+'_tip',(side*3.50,23.5,-3.31))
        # The cheek sections hug the face. The thicker ends follow the jacket lapel.
        levels=np.array([(17.5,3.15,.68,-4.33,.70),(19.5,3.30,.70,-4.07,.70),
              (20.8,3.34,.71,-3.99,.70),(22.0,3.40,.72,-3.43,.70),
              (23.5,3.50,.75,-3.31,.72),(25.6,3.80,.79,-3.25,.73),
              (27.2,4.48,.85,-2.97,.76),(29.5,4.49,1.00,-2.91,.92),
              (33,4.65,1.15,-2.81,1.35)])
        cuts=sorted(set(levels[:,0])|{28},reverse=True)
        for k,(hi,lo) in enumerate(zip(cuts,cuts[1:])):
            bone = cg if lo>=28 else cm if lo>=23.5 else ct
            for j in range(2):
                def point(y):
                    cx,w,z,d = [np.interp(y,levels[:,0],col) for col in levels[:,1:].T]
                    return (side*(cx+(j-.5)*w*.48),y,z+(j-.5)*.14),w*.54,d-.14
                start,w,d = point(hi);end,w2,d2 = point(lo)
                strand(bone,nm+f"前鬓{k}·{j}",start,end,(w+w2)/2,(d+d2)/2,flat("lock_l" if j else "lock"))
        name = nm+"SideLock"
        pt = lh.g(name,(side*5.4,26.2,3.48))
        pm = pt.g(name+"1",(side*6.67,23,5.30))
        pe = pm.g(name+"2",(side*6.42,20,6.13))
        pt.origin=[side*5.4,26.2,3.48];pm.origin=[side*6.67,23,5.30];pe.origin=[side*6.42,20,6.13]
        paired(pt,"发绳",4.72,6.08,25.98,26.42,2.81,4.15,flat("cord"))
        profile=np.array([(17,6.10,7.36,1.34,1.38),(18.6,6.27,6.70,1.62,1.62),
            (20,6.42,6.13,1.73,1.85),(21.6,6.58,5.76,2.41,1.96),
            (23,6.67,5.30,2.68,2.16),(24.5,6.24,4.44,2.12,1.83),(26.2,5.4,3.48,1.23,1.40)])
        for j,(u,v,tip) in enumerate(((-.5,0,18.68),(-.27,-.5,17.7),(0,.5,17.02),(.13,-.45,17.6),(.33,.41,18.03),(.5,-.03,18.95))):
            def sample(y):
                x,z,w,d = [np.interp(y,profile[:,0],col) for col in profile[:,1:].T]
                width=min(.88,w*.44);depth=min(1.14,d*.60)
                return (side*(x+u*(w-width)),y,z+v*(d-depth)),width,depth
            cuts = sorted({y for y in profile[:,0] if y>tip}|{tip+.65,tip},reverse=True)
            for k,(hi,lo) in enumerate(zip(cuts,cuts[1:])):
                bone = pt if lo>=23 else pm if lo>=20 else pe
                start,w,d = sample(hi);end,w2,d2 = sample(lo)
                taper = .27 if lo==tip else 0
                strand(bone,nm+f"泪滴发条{j}·{k}",start,end,(w+w2)/2-taper,(d+d2)/2-taper,
                       flat("hair_l" if j==4 else "hair"))
        paired(rig["hl_side"],"后颈外翻阶",3.62,4.30,26.04,27.51,3.86,4.78,hair())
        paired(rig["hl_m"],"后颈短发内层",1.18,1.96,25.46,26.44,4.09,4.90,hair("hair_d"))
        flower_center = (side*5.52,27.97,.94)
        fg = rib.g(nm + "HairFlower", flower_center)
        paired(fg,"发花托",4.38,5.38,27.66,28.24,.66,1.21,flat("flower_s"))
        add_flower(fg, nm+"发花", flower_center, side)

        hg = head.g(nm+"Horn", (side*3.6,35.78,.38))
        # 八节有重合的短弦。冠根朝外，角腹后倾，最后三节连续向内回钩。
        centers = [(4.12,.18),(4.45,.49),(4.78,.81),(5.10,1.13),
                   (5.37,1.43),(5.09,1.74),(4.76,1.45),(4.43,1.14)]
        widths = (2.40,2.40,2.36,2.30,2.18,2.08,1.57,1.05)
        for i,((cx,cz),width) in enumerate(zip(centers,widths)):
            bottom = 35.78 + .70*i
            top_y = min(41.50,bottom+1.00)
            paired(hg,f"龙角{i+1}",cx-width/2,cx+width/2,bottom,top_y,
                   cz-width*.46,cz+width*.46,horn(min(i,4)))
        hg.origin = [side*4.12,35.78,.18]
        paired(hg,"支角根",4.55,6.95,36.42,38.22,-.16,1.51,horn())
        paired(hg,"支角外阶",6.06,7.02,36.52,38.32,-.02,1.52,horn())
        eg = head.g(nm+"Ear", (side*5.40,34.12,.68))
        paired(eg,"尖耳根",5.40,6.84,33.41,35.21,-.20,1.6,horn())
        paired(eg,"耳外阶",6.27,7.48,33.13,34.93,-.12,1.40,horn())

    # 肘、腕与握点共用诺米定位器。握持物和皮肤随同一个关节转动。
    for nm in ("Right", "Left"):
        upper_arm = rig[nm+"Arm"]
        forearm = rig[nm+"ForeArm"]
        hand = rig[nm+"Hand"]
        grip = np.asarray(rig[nm+"HandLocator"].origin)
        palm = (np.asarray(hand.origin) + 3*grip)/4
        strand(upper_arm, nm+"上臂", upper_arm.origin,forearm.origin,2.60,2.60,skin_part())
        strand(forearm, nm+"前臂", forearm.origin,hand.origin,2.60,2.60,skin_part())
        hand.c(nm+"手", palm-1.20, palm+1.20, skin_part(True))

    # ---------------- 上衣
    top = upper.g("FittedTop", (0, 22.6, 0))
    top.c("胸身", (-3.4, 21.3, -1.9), (3.4, 25.6, 1.9), bodice)
    top.c("收腰", (-3.1, 19.0, -1.75), (3.1, 21.3, 1.75), bodice)
    top.c("腰带", (-3.25, 20.0, -1.9), (3.25, 21.3, 1.9), flat("black", edge="black_l"))
    upper.c("颈部", (-1.0, 25.3, -1.0), (1.0, 27.5, 1.0), skin_part())
    col = upper.g("Collar", (0, 25.8, 0))
    col.c("后领", (-1.80,25.35,-.40),(1.80,25.96,1.30),flat("white_s"))
    for side in (-1, 1):
        label = "Right" if side > 0 else "Left"
        lapel = col.g(label+"Lapel",(side*1.15,25.79,-1.99))
        hem = top.g(label+"ShirtHem",(side*2.33,20.01,-1.85))
        hem.c(label+"衣摆前片",*box(side*1.43,side*3.22,19.46,20.03,-2.01,-1.79),flat("pleat"))
        hem.c(label+"衣摆折边",*box(side*2.92,side*3.22,19.45,20.03,-2.02,-1.81),flat("white_s"))
        for i,(x0,x1,y0,y1,tone) in enumerate(((.65,1.65,25.29,25.87,"white"),
                                                (.47,1.25,24.88,25.33,"white_s"),
                                                (.33,.83,24.53,24.92,"white_s"))):
            lapel.c(f"翻领{side}·{i}",*box(side*x0,side*x1,y0,y1,-2.14-i*.015,-1.87),flat(tone))
    br = upper.g("Breast", (0,24.9,-1.8))
    for side in (-1,1):
        strand(br,f"银链{side}", (side*.69,24.87,-2.02),(0,23.75,-2.07),.10,.12,flat("silver"))
    br.c("吊坠·尖", (-.13,23.43,-2.27),(.13,23.80,-2.03),flat("red_s"))
    br.c("吊坠·水滴", (-.29,22.96,-2.34),(.29,23.49,-2.03),flat("gem"))
    br.c("吊坠·收底", (-.20,22.86,-2.26),(.20,23.00,-2.03),flat("red_s"))

    upper.g("ElytraLocator", (0, 25.8, 2))
    upper.g("BackpackLocator", (0, 25.0, 2))

    # ---------------- 下身
    down = allb.g("DownBody", (0, 19.3, 0))
    leg = down.g("Leg", (0, 18.1, 0))
    for side, nm in ((+1, "Right"), (-1, "Left")):
        cx = side * 1.9
        lg = leg.g(nm + "Leg", (cx, 18.3, 0))
        f, t = box(side * 0.25, side * 3.15, 9.2, 16.60, -1.55, 1.55)
        lg.c(nm + "Leg裁片", f, t, skin_part())
        for i,(y0,y1,outer,depth) in enumerate(((16.60,17.30,2.91,1.30),(17.30,18.00,2.62,1.04),
                                                (18.00,18.65,2.32,.92))):
            lg.c(nm+f"大腿上段{i}",*box(side*.26,side*outer,y0,y1,-depth,depth),skin_part())
        ll = lg.g(nm + "LowerLeg", (cx, 9.2, 0))
        f, t = box(side * 0.25, side * 3.15, 3.6, 9.2, -1.5, 1.5)
        ll.c(nm + "LowerLeg裁片", f, t, skin_part())
        f, t = box(side * 0.10, side * 3.30, 2.4, 3.98, -1.7, 1.7)
        ll.c(nm + "脚环", f, t, flat("black", edge="black_l"))
        ft = ll.g(nm + "Foot", (cx, 2.7, 0))
        f, t = box(side * 0.25, side * 3.15, 1.2, 2.4, -1.4, 1.4)
        ft.c(nm + "脚踝", f, t, skin_part())
        f, t = box(side * 0.25, side * 3.15, 0.0, 1.2, -3.15, 1.6)
        ft.c(nm + "脚掌", f, t, skin_part())

    wf = down.g("NomiWaistFollow", (0, 19.3, 0))
    sk = wf.g("Skirt", (0, 19.3, 0))
    # 褶根从腰带内缘起步。折深在黑边上方归零，垂直的黑边上下口各在同一平面。
    levels = [(20.04,3.13,1.65,.02),(19.42,3.16,1.74,.04),(18.52,3.49,2.26,.075),
              (17.62,3.85,2.57,.09),(16.38,4.58,3.09,.09),(15.10,5.56,3.65,0),
              (14.00,5.56,3.65,0)]
    rings = []
    for y,hw,hd,depth in levels:
        ring = []
        for k in range(24):
            angle = k*math.tau/24
            ridge = depth if k%2==0 else -depth
            z=-(hd+ridge)*math.cos(angle)
            if z<0:z=max(z,-hd*np.interp(y,[14,15.1,17.62,20.04],[.69,.69,.82,1]))
            ring.append(np.array([(hw+ridge)*math.sin(angle),y,z]))
        rings.append(ring)
    for k in range(24):
        for i in range(len(rings)-1):
            bone = rig[f"NomiPleatRoot{k}" if i < 3 else f"NomiPleatSwing{k//2}_{k%2}"]
            tone = "black" if i==len(rings)-2 else ("white" if k%2==0 else "pleat")
            edge = (k,(k+1)%24)
            top_edge = np.array([rings[i][j] for j in edge])
            bottom_edge = np.array([rings[i+1][j] for j in edge])
            if tone == "black":
                # 饰边包在白布外侧，避免斜裙片末梢露到黑边表面。
                top_edge[:,[0,2]] *= 1.014
                bottom_edge[:,[0,2]] *= 1.014
            skirt_section(bone,f"裙褶{k}·片{i}",top_edge,bottom_edge,tone)
    sk.c("裙内衬", (-2.28, 18.9, -1.21), (2.28, 19.15, 1.21), flat("white_d"))
    kx, ky, kz = -1.65, 20.10, -2.25
    bowg = wf.g("WaistBow", (kx,ky,kz))
    bowg.c("腰结系带",(kx-.22,ky+.12,kz+.10),(kx+.22,ky+.45,-1.88),flat("bow_edge"))
    # 结心的正面比两翼靠前；两翼在外端张开，在结心两侧留下可读的收腰。
    bowg.c("结心",(kx-.27,ky-.47,kz-.43),(kx+.27,ky+.47,kz+.10),flat("bow_edge"))
    bowg.c("结面",(kx-.20,ky-.34,kz-.49),(kx+.20,ky+.34,kz-.40),flat("bow_red"))
    for side in (-1,1):
        for i,(inner,outer,height) in enumerate(((.20,.54,.53),(.50,.87,.84),(.82,1.18,1.30))):
            z=kz-.12-.045*i
            bowg.c(f"蝶翼暗缘{side}_{i}",*box(kx+side*inner,kx+side*outer,ky-height/2,ky+height/2,z-.23,z+.19),flat("bow_edge"))
            bowg.c(f"蝶翼亮面{side}_{i}",*box(kx+side*(inner+.02),kx+side*(outer-.06),ky-height/2+.14,ky+height/2-.07,z-.30,z-.20),flat("bow_red"))
    for prefix,curve in (
        ('RibbonTail',[(-1.95,19.72,-2.40),(-1.84,17.35,-2.93),(-1.94,14.85,-3.46),
                       (-1.88,12.15,-3.48),(-1.78,9.18,-3.42)]),
        ('InnerRibbonTail',[(-.87,19.72,-2.42),(-.97,17.54,-2.94),(-.85,15.36,-3.47),
                            (-.75,13.17,-3.49),(-.69,10.98,-3.44)])):
        parent=bowg
        for j,(start,end) in enumerate(zip(curve,curve[1:])):
            parent=parent.g(prefix+str(j),start);draw_ribbon(parent,prefix+str(j),start,end,j)

    # 可见尾干由一条两段相切的三次 Bézier 曲线生成。按三维弧长定位骨节、尾花与切线段。
    begin = np.array([.4,12.6,5.6])
    bend = np.array([1.4,7.6,8.6])
    end = np.array([2.8,4.4,10.4])
    t = np.linspace(0,1,1001)[:,None]
    def cubic(a,b,c,d):return (1-t)**3*a+3*(1-t)**2*t*b+3*(1-t)*t**2*c+t**3*d
    approach=np.array([.56,-1.70,.72])
    curve=np.concatenate((cubic(begin,np.array([.42,10.60,5.92]),bend-approach,bend),
                          cubic(bend,bend+approach,np.array([2.22,4.52,9.60]),end)[1:]))
    arc = np.r_[0,np.cumsum(np.linalg.norm(np.diff(curve,axis=0),axis=1))]
    total = arc[-1]
    def tail_point(fraction):
        return np.array([np.interp(fraction*total,arc,curve[:,axis]) for axis in range(3)])

    # 裙内的尾根从骶部接到第一枚外摆关节，藏在腿与后裙片之间。
    sacrum = np.array([.18,19.04,1.26])
    tg = down.g("Tail", sacrum)
    inside=[sacrum,np.array([.35,17.85,1.80]),np.array([.48,16.78,2.18]),
            np.array([.41,15.30,2.48]),np.array([.36,13.18,2.54]),begin]
    for i,(a,b) in enumerate(zip(inside,inside[1:])):
        count = math.ceil(np.linalg.norm(b-a)/.40)
        for k in range(count):
            u = (k+.5)/count
            center = (1-u)*a+u*b
            radius = np.interp(i+u,[0,1,2,3,4,5],[.13,.11,.12,.19,.27,.56])
            tg.c(f"裙内尾根{i}_{k}",center-radius,center+radius,tail(0))
    parent = tg
    joints = (0,.22,.45,.64,.83,1)
    for i,(a,b) in enumerate(zip(joints,joints[1:])):
        start = tail_point(a)
        seg = parent.g(f"Tail{i}",start)
        count = math.ceil((b-a)*total/.36)
        stops = np.linspace(a,b,count+1)
        for k,(u,v) in enumerate(zip(stops,stops[1:])):
            finish = tail_point(v)
            diameter=np.interp((u+v)/2,[0,.5,1],[1.85,1.55,1.05])
            strand(seg,f"尾{i}_{k}",start,finish,diameter,diameter,tail((u+v)/2))
            start = finish
        if i == 2:
            mid = tail_point(a)
            fg = seg.g("TailFlowerMid",mid)
            add_flower(fg,"尾花中",mid,0,petal_depth=.64)
        parent = seg
    fg = parent.g("TailFlowerTip",end)
    add_flower(fg, "尾花尖", fg.origin, 0)

    add_coat(rig)
    root.g("molang", (0, -0.3, 0))
    return root


def strand(group, name, a, b, width, depth, paint):
    """把方块的局部 -Y 指向下一锚点。两端各留接缝余量。"""
    direction = np.subtract(b, a)
    length = np.linalg.norm(direction)
    center = (np.array(a) + b) / 2
    pitch = -math.degrees(math.asin(direction[2] / length))
    roll = math.degrees(math.atan2(direction[0], -direction[1]))
    half = np.array([width, length+.16, depth]) / 2
    group.c(name, center-half, center+half, paint, rot=(pitch,0,roll))


def draw_ribbon(bone, name, start, end, tier):
    tangent = np.subtract(end,start)
    length = np.linalg.norm(tangent)
    pitch = -math.degrees(math.asin(tangent[2]/length))
    roll = math.degrees(math.atan2(tangent[0],-tangent[1]))
    rotation = (pitch,0,roll)
    frame = rot_matrix(rotation)
    width = (.65,.78,.80,.70)[tier]
    # 带身保留原有折光，末段在同一条接缝接入两片斜裁口。
    notch = .32 if tier == 3 else 0.0
    spans = (-.5,-.36,-.13,.13,.36,.5)
    for k,(a,b) in enumerate(zip(spans,spans[1:])):
        front = -.035*math.cos((a+b)*math.pi)
        center = np.asarray(start) + frame @ [(a+b)*width/2,-(length-notch)/2,front]
        half = np.array([(b-a)*width+.005,length-notch+.10,.16])/2
        paint = bow_paint("red_s" if k==0 else "red")
        bone.c(name+f"·绸面{k}",center-half,center+half,paint,rot=rotation)

    if tier == 3:
        # 两个斜底面在中线相会，形成一个贯通带厚的 V 口。
        for side in (-1,1):
            tilt = -side*math.atan2(notch,width/2)
            half = np.array([math.hypot(width/2,notch),.42,.16])/2
            bevel = rot_matrix((0,0,math.degrees(tilt)))
            orient = frame @ bevel
            angles = np.degrees([math.atan2(orient[2,1],orient[2,2]),
                                 math.asin(-orient[2,0]),math.atan2(orient[1,0],orient[0,0])])
            bottom = np.array([side*width/4,-length+notch/2,0])
            center = np.asarray(start) + frame @ (bottom + bevel[:,1]*half[1])
            bone.c(name+f"·燕尾{side}",center-half,center+half,bow_paint(),rot=angles)


def add_flower(group, name, center, side, petal_depth=1.04):
    """以芯为轴，耳侧的四瓣沿 YZ 对角展开；花冠略朝前，正背面也能看到花瓣分离。"""
    c = np.asarray(center)
    core_half = .50
    group.c(name+"·芯",c-core_half,c+core_half,flower(),role="core")
    for vertical in (-1,1):
        for lateral in (-1,1):
            if side:
                shift = 1.04 if lateral>0 else -.97
                offset = np.array([side*shift, vertical*1.04, lateral*1.03])
                half = np.array([.57,.59,.58])
            else:
                offset = np.array([lateral*1.04,vertical*1.03,lateral*petal_depth])
                half = np.array([.64,.64,.64])
            stem = c+.53*offset
            group.c(f"{name}·内阶{vertical}_{lateral}",stem-.40,stem+.40,flower())
            pos = c+offset
            group.c(f"{name}·瓣{vertical}_{lateral}",pos-half,pos+half,flower())


# ------------------------------------------------------------------ atlas
FACES = ("north", "east", "south", "west", "up", "down")


def face_size(cube, f):
    if cube.role == "iris" and f == "north":
        return 12,9
    w = cube.to[0] - cube.frm[0]
    h = cube.to[1] - cube.frm[1]
    d = cube.to[2] - cube.frm[2]
    sz = {"north": (w, h), "south": (w, h), "east": (d, h), "west": (d, h), "up": (w, d), "down": (w, d)}[f]
    return max(1, round(sz[0]*PPU)), max(1, round(sz[1]*PPU))


def iter_cubes(g):
    for ch in g.children:
        if isinstance(ch, Cube):
            yield ch
        else:
            yield from iter_cubes(ch)


def make_atlas(root):
    items = []
    for cube in iter_cubes(root):
        for f in FACES:
            w, h = face_size(cube, f)
            img = cube.tiles[f] if hasattr(cube,"tiles") else cube.paint(f,w,h,cube)
            items.append((cube, f, img))
    # 去重：完全相同的贴图共用一块
    W = 512
    order = sorted(range(len(items)), key=lambda i: -items[i][2].shape[0])
    placed = {}
    x = y = row_h = 0
    rects = {}
    for i in order:
        cube, f, img = items[i]
        key = img.tobytes() + bytes(img.shape[:2])
        if key in placed:
            rects[(cube.uuid, f)] = placed[key]
            continue
        h, w = img.shape[:2]
        if x + w > W:
            x, y, row_h = 0, y + row_h, 0
        rects[(cube.uuid, f)] = (x, y, w, h)
        placed[key] = (x, y, w, h)
        x += w
        row_h = max(row_h, h)
    H = 1 << int(np.ceil(np.log2(max(64, y + row_h))))
    H = max(H, W) if y + row_h > W else W
    atlas = np.zeros((H, W, 4), np.uint8)
    for cube, f, img in items:
        rx, ry, w, h = rects[(cube.uuid, f)]
        atlas[ry:ry + h, rx:rx + w] = img
    for cube in iter_cubes(root):
        for f in FACES:
            rx, ry, w, h = rects[(cube.uuid, f)]
            l,t,r,b = getattr(cube,"uv_insets",{}).get(f,(0,0,0,0))
            cube.faces[f] = [rx+l, ry+t, rx+w-r, ry+h-b]
    return atlas


# ------------------------------------------------------------------ export bbmodel
# 正面设定为垂手站姿。模板的绑定姿势用于动画，审查图使用此单帧站姿。
REVIEW_ROTATION = {"RightArm": (23,0,-7), "LeftArm": (23,0,7),
                  "RightHand": (-18,0,10), "LeftHand": (-18,0,-10)}


def review_stance(groups):
    animators = {}
    for g in groups:
        if g["name"] in REVIEW_ROTATION:
            rx,ry,rz = REVIEW_ROTATION[g["name"]]
            key_id = str(uuidlib.uuid5(uuidlib.NAMESPACE_URL, "longnu/stand/" + g["name"]))
            animators[g["uuid"]] = {"name":g["name"], "type":"bone", "keyframes":[{
                "channel":"rotation", "time":0, "uuid":key_id, "interpolation":"linear",
                "data_points":[{"x":str(rx),"y":str(ry),"z":str(rz)}], "color":-1}]}
    if not animators:
        return []
    return [{"name":"longnu_reference_stance", "loop":"hold", "length":0.0, "snapping":24,
             "override":False, "uuid":str(uuidlib.uuid5(uuidlib.NAMESPACE_URL,"longnu/stand")),
             "animators":animators}]


# Secondary joints use local rotations about the attachment pivots already in the rig.
# Each row lists the template driver, ordered joints, and maximum degrees per joint.
def follow_chains():
    yield 'DownBody', [f'Tail{i}' for i in range(5)], 1.3
    for prefix, driver in [('RibbonTail','NomiCoatR0Hip'), ('InnerRibbonTail','NomiCoatL0Hip')]:
        yield driver, [prefix+str(i) for i in range(4)], .48
    for side in ('Left','Right'):
        yield 'LongHair', [side+'SideLock1',side+'SideLock2'], .80
        yield 'NomiHood', [side+'ShoulderCape',side+'ShoulderCapeTip'], .32
    yield 'NomiHood', ['HoodPendant','HoodPendantTip'], .45


def add_secondary_tracks(anim, ids, strength):
    tracks = anim['animators']
    duration = anim['length'] or max(k['time'] for tr in tracks.values() for k in tr.get('keyframes', []))
    leg_keys = sorted((k for k in tracks.get(ids['LeftLeg'],{}).get('keyframes',[])
                       if k['channel']=='rotation'), key=lambda k:k['time'])
    leg_times = [k['time'] for k in leg_keys]
    leg_pitch = [float(k['data_points'][0]['x']) for k in leg_keys]
    # These offsets move only the dragon accessories during the relevant source poses.
    # The tail rises from its anatomical root; the waist knot sits on top of the raised lap.
    clearance = {'run':('Tail','rotation',(-16,0,0)), 'sit':('WaistBow','position',(0,.9,-.48)),
                 'jump':('WaistBow','position',(0,.48,-.26)), 'sneak':('WaistBow','position',(0,.50,-.32))}
    if anim['name'] in clearance:
        name, channel, vector = clearance[anim['name']]
        if ids[name] in tracks:
            raise ValueError(f'附属骨已有轨道 {name}')
        tracks[ids[name]] = {'name':name,'type':'bone','keyframes':[{
            'channel':channel,'time':0,'interpolation':'linear','color':-1,
            'uuid':str(uuidlib.uuid5(uuidlib.NAMESPACE_URL,f"longnu/{anim['uuid']}/{name}/clearance")),
            'data_points':[dict(zip('xyz',map(str,vector)))]}]}
    for driver, chain, limit in follow_chains():
        frames = sorted((k for k in tracks.get(ids[driver], {}).get('keyframes', [])
                         if k['channel']=='rotation'), key=lambda k:k['time'])
        times = [k['time'] for k in frames]
        values = np.array([[float(k['data_points'][0][axis]) for axis in 'xyz'] for k in frames])
        for depth, name in enumerate(chain):
            if ids[name] in tracks:
                raise ValueError(f"从动轨与原轨冲突 {anim['name']}/{name}")
            keyframes = []
            for step in range(13):
                phase = (step/12 - .045*(depth+1)) % 1
                # Remove the driver's static posture; delay and bound only its variation.
                response = np.zeros(3)
                if times:
                    response = np.array([np.interp(phase*duration,times,col) - col.mean() for col in values.T])
                wave = math.sin(math.tau*phase)
                angles = strength*limit*np.tanh(response/12 + np.array([.32,.18,.13])*wave)
                # The lifted thigh carries the two ribbons; their lower halves still hang down.
                if 'RibbonTail' in name and leg_times:
                    lift = max(0.,np.interp(duration*step/12,leg_times,leg_pitch))
                    angles[0] += lift*(1.02,.06,-.18,-.24)[depth]
                # Keep the flowered tail above the heel during the backward kick.
                if name.startswith('Tail') and anim['name']=='run':
                    angles[0] -= (21,11,3,0,0)[depth]
                keyframes.append({'channel':'rotation','time':round(duration*step/12,6),
                    'uuid':str(uuidlib.uuid5(uuidlib.NAMESPACE_URL,f"longnu/{anim['uuid']}/{name}/{step}")),
                    'interpolation':'linear','color':-1,
                    'data_points':[{axis:f'{val:.5f}' for axis,val in zip('xyz',angles)}]})
            tracks[ids[name]] = {'name':name,'type':'bone','keyframes':keyframes}


def nomi_animations(groups):
    ids = {g['name']:g['uuid'] for g in groups}
    valid = set(ids.values()) | {'effects'}
    animations = deepcopy(nomi_model()['animations'])
    strength = {'idle':.65,'walk':.85,'run':1,'jump':.9,'sneak':.55,'sit':.42}
    for anim in animations:
        tracks = anim.get('animators', {})
        if tracks.keys()-valid:
            raise ValueError(f"动作 {anim['name']} 引用了缺失骨骼 {tracks.keys()-valid}")
        right = tracks.get(ids['corner_h1'], {})
        frames = deepcopy([k for k in right.get('keyframes', []) if k['channel']=='rotation'])
        if frames:
            if ids['corner_h2'] in tracks:
                raise ValueError('左鬓角已有动作')
            for key in frames:
                key['uuid'] = str(uuidlib.uuid5(uuidlib.NAMESPACE_URL,'longnu/left-lock/'+key['uuid']))
                for point in key['data_points']:
                    for axis in ('y','z'):
                        point[axis] = str(-float(point[axis]))
            tracks[ids['corner_h2']] = {**right,'name':'corner_h2','keyframes':frames}
        if anim['name'] in strength:
            add_secondary_tracks(anim,ids,strength[anim['name']])
    return animations


def export_bbmodel(root, atlas, path, *, full_animations=False):
    buf = io.BytesIO()
    Image.fromarray(atlas).save(buf, "PNG")
    png = buf.getvalue()
    texture_name = path.with_suffix(".png").name
    path.with_suffix(".png").write_bytes(png)
    H, W = atlas.shape[:2]
    elements, groups = [], []

    def outl(g):
        groups.append({
            "name": g.name, "uuid": g.uuid, "export": True, "locked": False, "scope": 0,
            "visibility": True, "origin": g.origin, "rotation": g.rot, "bedrock_binding": "",
            "color": 0, "reset": False, "shade": True, "mirror_uv": False, "autouv": 0,
            "isOpen": False, "children": [],
        })
        ch = []
        for c in g.children:
            if isinstance(c, Cube):
                el = {
                    "name": c.name, "box_uv": False, "render_order": "default", "locked": False,
                    "export": True, "scope": 0, "allow_mirror_modeling": True,
                    "from": c.frm, "to": c.to, "autouv": 0, "color": 0, "origin": c.origin,
                    "faces": {f: {"uv": c.faces[f], "texture": 0} for f in FACES},
                    "type": "cube", "uuid": c.uuid,
                }
                if any(c.rot):
                    el["rotation"] = c.rot
                if c.inflate:
                    el["inflate"] = c.inflate
                elements.append(el)
                ch.append(c.uuid)
            else:
                ch.append(outl(c))
        return {"uuid": g.uuid, "isOpen": g.name in ("Root", "MAllBody", "AllBody"), "children": ch}

    outliner = [outl(root)]
    model = {
        "meta": {"format_version": "5.0", "model_format": "bedrock", "box_uv": False},
        "name": "龙娘", "model_identifier": "longnu", "visible_box": [4, 3.5, 1.25],
        "variable_placeholders": "", "variable_placeholder_buttons": [],
        "bedrock_animation_mode": "entity", "timeline_setups": [], "unhandled_root_fields": {},
        "resolution": {"width": W, "height": H},
        "elements": elements, "groups": groups, "outliner": outliner,
        "textures": [{
            "name": texture_name, "relative_path": texture_name, "folder": "", "namespace": "", "id": "0",
            "group": "", "scope": 0, "width": W, "height": H, "uv_width": W, "uv_height": H,
            "particle": False, "use_as_default": False, "layers_enabled": False, "sync_to_project": "",
            "file_format": "png", "render_mode": "default", "render_sides": "auto", "wrap_mode": "limited",
            "pbr_channel": "color", "fps": 7, "force_translucent": False, "frame_time": 1,
            "frame_order_type": "loop", "frame_order": "", "frame_interpolate": False, "visible": True,
            "internal": True, "saved": True,
            "uuid": str(uuidlib.uuid5(uuidlib.NAMESPACE_URL, texture_name)),
            "source": "data:image/png;base64," + base64.b64encode(png).decode(),
        }],
        "animations": review_stance(groups) + (nomi_animations(groups) if full_animations else []),
    }
    if full_animations:
        for key in ("variable_placeholders", "variable_placeholder_buttons", "animation_variable_placeholders"):
            model[key] = nomi_model()[key]
    path.write_text(json.dumps(model, ensure_ascii=False, indent=1), encoding="utf-8")
    return len(elements), len(groups)


# ------------------------------------------------------------------ preview renderer
def rot_matrix(r):
    x, y, z = (math.radians(v) for v in r)
    Rx = np.array([[1, 0, 0], [0, math.cos(x), -math.sin(x)], [0, math.sin(x), math.cos(x)]])
    Ry = np.array([[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]])
    Rz = np.array([[math.cos(z), -math.sin(z), 0], [math.sin(z), math.cos(z), 0], [0, 0, 1]])
    return Rz @ Ry @ Rx  # Blockbench / three.js 'ZYX'


def face_quads(cube):
    (x1, y1, z1), (x2, y2, z2) = cube.frm, cube.to
    q = {  # 从外侧看：左上、右上、右下、左下
        "north": [(x2, y2, z1), (x1, y2, z1), (x1, y1, z1), (x2, y1, z1)],
        "south": [(x1, y2, z2), (x2, y2, z2), (x2, y1, z2), (x1, y1, z2)],
        "east": [(x2, y2, z2), (x2, y2, z1), (x2, y1, z1), (x2, y1, z2)],
        "west": [(x1, y2, z1), (x1, y2, z2), (x1, y1, z2), (x1, y1, z1)],
        "up": [(x1, y2, z1), (x2, y2, z1), (x2, y2, z2), (x1, y2, z2)],
        "down": [(x1, y1, z2), (x2, y1, z2), (x2, y1, z1), (x1, y1, z1)],
    }
    R = rot_matrix(cube.rot)
    o = np.array(cube.origin)
    return {f: [R @ (np.array(p) - o) + o for p in pts] for f, pts in q.items()}


def collect_faces(root, reference_stance=False):
    out = []

    def walk(g, M, t):
        # 骨骼旋转递归传递给子方块。
        pose = REVIEW_ROTATION.get(g.name,(0,0,0)) if reference_stance else (0,0,0)
        R = rot_matrix(np.add(g.rot,pose))
        o = np.array(g.origin)
        for ch in g.children:
            if isinstance(ch, Cube):
                for f, pts in face_quads(ch).items():
                    pts = [M @ (R @ (p - o) + o) + t for p in pts]
                    out.append((ch, f, pts))
            else:
                walk(ch, M @ R, M @ (o - R @ o) + t)
    walk(root, np.eye(3), np.zeros(3))
    return out


def render(faces, atlas, yaw, pitch=0.0, scale=12.5, size=(560, 640), center=(0, 21.5, 0)):
    """正交渲染。yaw=0 从正面（-Z）看。"""
    W, H = size
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    # 相机：位于 -Z 方向绕 Y 旋转 yaw；forward 指向模型
    fwd = np.array([sy * cp, -sp, cy * cp])
    up0 = np.array([0, 1, 0])
    right = np.cross(fwd, up0)
    right = right / np.linalg.norm(right)
    up = np.cross(right, fwd)
    up = -up if up[1] < 0 else up
    # 校验：yaw=0 时 right 应为 -X（角色右手在画面左）
    img = np.zeros((H, W, 3), np.float32)
    img[:] = (0.86, 0.87, 0.9)
    zb = np.full((H, W), np.inf)
    light = np.array([-0.35, 0.85, -0.55])
    light /= np.linalg.norm(light)
    c = np.array(center, float)
    for cube, f, pts in faces:
        P = np.array(pts) - c
        n = np.cross(P[3] - P[0], P[1] - P[0])
        nn = np.linalg.norm(n)
        if nn < 1e-9:
            continue
        n /= nn
        if np.dot(n, fwd) >= -1e-6:
            continue  # 背面剔除（n 指向外侧）
        u = P @ right * scale + W / 2
        v = -(P @ up) * scale + H / 2
        d = P @ fwd
        A = np.array([u[0], v[0]])
        eB = np.array([u[1] - u[0], v[1] - v[0]])
        eD = np.array([u[3] - u[0], v[3] - v[0]])
        det = eB[0] * eD[1] - eB[1] * eD[0]
        if abs(det) < 1e-6:
            continue
        x0, x1 = int(max(0, np.floor(u.min()))), int(min(W - 1, np.ceil(u.max())))
        y0, y1 = int(max(0, np.floor(v.min()))), int(min(H - 1, np.ceil(v.max())))
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        rx, ry = xs - A[0], ys - A[1]
        s = (rx * eD[1] - ry * eD[0]) / det
        t = (eB[0] * ry - eB[1] * rx) / det
        m = (s >= 0) & (s < 1) & (t >= 0) & (t < 1)
        if not m.any():
            continue
        uv = cube.faces[f]
        tu = np.clip((uv[0] + s * (uv[2] - uv[0])).astype(int), math.floor(uv[0]), math.ceil(uv[2]) - 1)
        tv = np.clip((uv[1] + t * (uv[3] - uv[1])).astype(int), math.floor(uv[1]), math.ceil(uv[3]) - 1)
        tex = atlas[tv, tu]
        m &= tex[..., 3] > 127
        dep = d[0] + s * (d[1] - d[0]) + t * (d[3] - d[0])
        sub = zb[y0:y1 + 1, x0:x1 + 1]
        m &= dep < sub - 1e-4
        shade = 0.82 + 0.18 * max(0.0, float(np.dot(n, light)))
        if f == "up":
            shade = min(1.0, shade + 0.06)
        col = tex[..., :3].astype(np.float32) / 255 * shade
        sub[m] = dep[m]
        im = img[y0:y1 + 1, x0:x1 + 1]
        im[m] = col[m]
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)


def preview(root, atlas):
    faces = collect_faces(root, reference_stance=True)
    views = [("正面", 0, 0), ("左侧", 90, 0), ("背面", 180, 0), ("3/4", -35, 12)]
    tiles = [Image.fromarray(render(faces, atlas, yaw, pitch)) for _, yaw, pitch in views]
    w, h = tiles[0].size
    sheet = Image.new("RGB", (w * len(tiles), h), (220, 222, 228))
    for i, t in enumerate(tiles):
        sheet.paste(t, (i * w, 0))
    sheet.save(OUT / "preview.png")
    # 脸部特写
    face = render(faces, atlas, 0, 0, scale=46, size=(680, 520), center=(0, 29.5, 0))
    final_face = Image.fromarray(face)
    final_face.save(OUT / "preview_face.png")
    original = copy_nomi_group("Head")
    original_tex = make_atlas(original)
    original_face = Image.fromarray(render(collect_faces(original),original_tex,0,0,scale=46,size=(680,520),center=(0,29.5,0)))
    comparison = Image.new("RGB",(1360,520))
    comparison.paste(original_face,(0,0))
    comparison.paste(final_face,(680,0))
    comparison.save(OUT/"eyes_vs_nomi.png")
    face34 = render(faces, atlas, 30, 8, scale=48, size=(640, 520), center=(0, 29.5, 0))
    Image.fromarray(face34).save(OUT / "preview_face34.png")
    return faces


def verify_nomi_face(root,reference):
    """与参考工程逐骨、逐块核对，保留两个同名侧颊及同名眼窝的顺序。"""
    model = json.loads(reference.read_text())
    names = {g["uuid"]:g["name"] for g in model["groups"]}
    elements = {e["uuid"]:e for e in model["elements"]}
    def nodes(group):
        yield group
        for c in group.children:
            if isinstance(c,Group):
                yield from nodes(c)
    own = {g.name:g for g in nodes(root)}
    checked = 0
    def verify(node):
        nonlocal checked
        name = names[node["uuid"]]
        if name in ("Face","RightEyelid","LeftEyelid","RightPupil","LeftPupil"):
            src = [elements[c] for c in node["children"] if isinstance(c,str)]
            dst = [c for c in own[name].children if isinstance(c,Cube)]
            if len(src)!=len(dst):
                raise ValueError(f"{name} 模板方块数量不符")
            for e,c in zip(src,dst):
                if e["name"] != c.name:
                    raise ValueError(f"{name}/{c.name} 模板名称不符")
                for key,values in (("from",c.frm),("to",c.to),("origin",c.origin),("rotation",c.rot)):
                    if not np.array_equal(np.round(e.get(key,[0,0,0]),3),np.round(values,3)):
                        raise ValueError(f"{name}/{c.name} 的 {key} 与模板不符")
                checked += 1
        for child in node["children"]:
            if isinstance(child,dict):
                verify(child)
    for node in model["outliner"]:
        verify(node)
    print(f"诺米脸部与眼部几何核对 {checked} 块")


def main():
    root = build()
    reference = Path.home()/"Downloads/诺米/诺米.bbmodel"
    if reference.is_file():
        verify_nomi_face(root,reference)
    atlas = make_atlas(root)
    ne, ng = export_bbmodel(root, atlas, OUT / "longnu.bbmodel", full_animations=True)
    preview(root, atlas)
    print("cubes", ne, "groups", ng, "atlas", atlas.shape)


if __name__ == "__main__":
    main()
