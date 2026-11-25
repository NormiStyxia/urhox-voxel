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
import base64
import io
import json
from functools import lru_cache
import math
import uuid as uuidlib
from pathlib import Path

import numpy as np
from PIL import Image

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
def nomi_source():
    model = json.loads((Path.home()/"Downloads/诺米/诺米.bbmodel").read_text())
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


def coat_cloth(kind="plain"):
    def paint(face,w,h,cube):
        tone = "cord" if face in ("west","down") else "hair" if face in ("up","east") else "hair_d"
        tile = np.full((h,w,4),rgba(C[tone]),np.uint8)
        if face not in ("north","south","east","west"):
            return tile
        if kind in ("scorch","tat","embroidered"):
            rows = min(h,7)
            for j in range(rows):
                a = j/max(1,rows-1)
                c = np.interp(a,[0,.55,1],[C[tone][0],90,42]),np.interp(a,[0,.55,1],[C[tone][1],14,20]),np.interp(a,[0,.55,1],[C[tone][2],24,16])
                tile[h-rows+j] = rgba(c)
        if kind=="embroidered" and face in ("north","south") and min(w,h)>=6:
            # 六瓣卷曲的花丝向外展开，中央留出布底。
            pattern = ("..r..s","r.s.r.",".rsrsr","rs.s..","..rr.r",".r.sr.")
            y0=max(0,h-14); x0=(w-6)//2
            for y,row in enumerate(pattern):
                for x,ch in enumerate(row):
                    if ch!='.':tile[y0+y,x0+x]=rgba((192,26,36) if ch=='r' else (122,15,24))
        return tile
    return paint


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
            c[0]=0;size[0]=6.15;c[2]=2.40;size[2]=.40
            if "下" in name:c[2]=3.17
        elif '披肩' in name:
            size[2]-=.82;c[2]-=.48
        elif '腰侧' in name:
            c[0]=np.sign(c[0])*3.67;size[0]=.42
        elif '敞襟' in name:
            c[0]=np.sign(c[0])*2.63;size[0]=2.25;c[2]=-2.33;size[2]=.24
            if c[0]<0:
                size[1]-=2.04;c[1]+=1.02
        elif '领襟' in name:
            c[0]=np.sign(c[0])*1.76;c[2]=-2.62
        plate(shell,name,c,size,cloth,e.get('rotation',(0,0,0)))
    for side in (-1,1):
        strand(shell,f"金色前领{side}",(side*.40,25.02,-2.79),(side*2.78,24.31,-2.74),.32,.20,flat('gold'))
        strand(shell,f"前襟金缘{side}",(side*1.47,24.50,-2.62),(side*1.75,21.32 if side<0 else 19.10,-2.62),.31,.20,flat('gold'))
    plate(shell,'金饰扣',(0,24.92,-2.8),(1,1,.25),flat('gold'),(0,0,45))
    plate(shell,'扣心',(0,24.92,-2.99),(.45,.45,.16),flat('gold_d'),(0,0,45))
    strand(shell,'红绳坠',(0,24.62,-2.78),(.11,23.65,-2.73),.15,.14,flat('red_s'))
    hood=rig['NomiHood']
    for e in template_parts('NomiHood'):
        lo,hi=np.array(e['from']),np.array(e['to']);c=(lo+hi)/2;size=hi-lo
        c[0]*=.86;size[0]*=.86;c[1]-=.98;c[2]+=.50
        ht = flat("hair" if "描边" not in e["name"] else "cord")
        if '翻口卷边' in e['name'] and '描边' not in e['name']:size[2]=1.4
        plate(hood,e['name'],c,size,ht,e.get('rotation',(0,0,0)))
    plate(hood,'帽口金边',(0,24.47,4.75),(5.27,.67,.20),flat('gold'))
    pendant=hood.g('HoodPendant',(0,19.53,3.85))
    plate(pendant,'坠帽尖',(0,19.18,3.85),(.80,.82,.72),cloth)
    plate(pendant,'坠帽包金',(0,18.83,3.85),(.46,.25,.48),flat('gold_d'))
    # 以肩肘的实际连线为轴，四壁围出袖腔。金边同附在对应前臂骨。
    for nm in ('Left','Right'):
        for limb,next_name,half in [('Arm','ForeArm',1.65),('ForeArm','Hand',1.80)]:
            bone=rig[nm+limb+'Coat'];a=np.array(bone.origin);b=np.array(rig[nm+next_name].origin)
            if limb=='ForeArm': b=a+.88*(b-a)
            v=b-a;length=np.linalg.norm(v);rot=(-math.degrees(math.asin(v[2]/length)),0,math.degrees(math.atan2(v[0],-v[1])))
            frame=rot_matrix(rot);c=(a+b)/2
            for dim in (0,2):
                for sign in (-1,1):
                    size=np.array([2*half,length+.20,2*half]);size[dim]=.23;off=np.zeros(3);off[dim]=sign*(half+.115)
                    plate(bone,nm+limb+f'袖壁{dim}_{sign}',c+frame@off,size,cloth,rot)
                    if limb=='ForeArm':
                        size[1]=1.0;size[dim]=.20;off[dim]=sign*(half+.38);off[1]=-length/2+.44
                        plate(bone,nm+f'袖口金{dim}_{sign}',c+frame@off,size,flat('gold'),rot)
    # 裁片沿椭圆周围由前至后排开，各自的模板骨独立驱动。
    for sign,tag in ((-1,'L'),(1,'R')):
        waist=rig['NomiCoatLeft' if sign<0 else 'NomiCoatRight']
        for j,angle in enumerate((45,88,129,163)):
            phi=math.radians(angle); prefix=f'NomiCoat{tag}{j}'
            hip,hem=rig[prefix+'Hip'],rig[prefix+'Hem']
            def pos(y,rx,rz):return np.array([sign*rx*math.sin(phi),y,-rz*math.cos(phi)])
            p=pos(18.43,4.72,3.78);q=pos(13.52,6.63,4.80);r=pos(10.75-.30*j,7.31,5.14)
            # 法向位于布外，金边与绣花共享裁片的局部方位。
            def panel(bone,name,top,bottom,width,paint,edge=False,band=False):
                along=top-bottom;along/=np.linalg.norm(along)
                tangent=np.array([sign*math.cos(phi),0,math.sin(phi)])
                normal=np.cross(tangent,along);normal/=np.linalg.norm(normal);right=np.cross(along,normal)
                M=np.column_stack((right,along,normal));rot=np.degrees([math.atan2(M[2,1],M[2,2]),math.asin(-M[2,0]),math.atan2(M[1,0],M[0,0])]);c=(top+bottom)/2;h=np.linalg.norm(top-bottom)
                plate(bone,name,c,(width,h+.10,.28),paint,rot)
                outward=normal*(-sign)
                if edge:plate(bone,name+'·襟缘',c-right*(width/2-.42)+outward*.29,(.86,h+.12,.20),flat('gold'),rot)
                if band:plate(bone,name+'·摆金',bottom+along*.62+outward*.29,(width,1.0,.20),flat('gold_d'),rot)
                return right,outward
            width=(2.75,3.15,3.25,4.05)[j]; top=pos(20.10,4.07,3.14)
            if j==0:
                # 在腰结及鬓梢的外侧留出活动余量，再沿裙的两侧展开。
                if sign<0:
                    top+=(-1.50,0,1.60);p+=(-1.48,0,1.37);q+=(-1.72,0,.60);r+=(-1.58,0,.62)
                    width=1.90
                else:
                    p+=(.50,0,1.05);q+=(.44,0,.13)
            if sign>0 and j in (2,3):
                # 尾干位于右后开衩，后片从尾干后方垂落，侧片从外侧经过。
                if j==2:
                    p+=(.2,0,-.78);q+=(1.40,0,-1.24);r+=(1.78,0,-1.25);width=2.55
                else:
                    q+=(-.55,0,1.35);r+=(-.85,0,2.05)
            
            if j==1:
                q[0]+=sign*.53;r[0]+=sign*.53
            if j==2:
                p[2]-=.86;q[2]-=1.02
                q[0]+=sign*1.40;r[0]+=sign*.88
                width-=.60
                if sign>0:p[0]+=.48
                else:
                    p[2]-=.85;q[2]-=.84;p[0]-=.70;q[0]-=.86; width-=.30
            if j==0 and sign>0:
                p[0]+=.47;q[0]+=.64;r[0]+=.54
            if j==0 and sign<0:
                q[0]-=.78;r[0]-=1.07
            panel(waist,prefix+'腰片',top,p,width*.82,cloth,edge=j==0)
            hip.origin=p.tolist();hem.origin=q.tolist()
            panel(hip,prefix+'胯幅',p,q,width,cloth,edge=j==0)
            right,out=panel(hem,prefix+'摆幅',q,r,width*1.15,coat_cloth('embroidered' if j in (0,3) else 'scorch'),edge=j==0,band=True)
            # 侧缝、背缝内侧的搭接布随本片铰接，跨过外面破摆条之间的缝。
            if j==1:
                hip_top=np.array([sign*4.82,18.42,.03]); hip_end=np.array([sign*7.18,13.55,.20])
                hem_end=np.array([sign*7.38,10.65,.41])
                panel(hip,prefix+'侧里幅',hip_top,hip_end,4.05,cloth)
                panel(hem,prefix+'侧里摆',hip_end,hem_end,4.55,coat_cloth('scorch'),band=True)
            if j==3:
                z=5.35 if sign<0 else 6.38
                hip_top=np.array([sign*3.20,15.02,z]); hip_end=np.array([sign*3.20,13.48,z])
                hem_end=np.array([sign*3.33,10.65,z+1.16])
                panel(hip,prefix+'后里幅',hip_top,hip_end,5.80,cloth)
                panel(hem,prefix+'后里摆',hip_end,hem_end,6.00,coat_cloth('scorch'))
            tips=[child for child in hem.children if isinstance(child,Group) and 'Tat' in child.name]
            for k,bone in enumerate(tips):
                offset=((k+.5)/len(tips)-.5)*width*1.15;start=r+right*offset
                bone.origin=start.tolist();length=(.76,1.68,.94,1.20)[(k+j)%4]
                panel(bone,prefix+f'破摆{k}',start,start+[0,-length,0]+out*.08*length,width/len(tips)*.89,coat_cloth('tat'))


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
            bh.c(f"顶发条{k}·{j}",(x0,base_y,z0),(x1,height,z1),hair())
    # 八束的分界与两道露眉缺口延用正面位置，条间前缘有小的深度差。
    sections = [(-5.90,-4.25,30.90,34.74,-4.93),(-4.25,-2.85,30.80,35.20,-5.12),
                (-2.85,-1.45,31.11,35.63,-5.24),(-1.45,0,30.08,35.88,-5.34),
                (0,1.45,30.13,35.91,-5.36),(1.45,2.85,31.11,35.63,-5.23),
                (2.85,4.25,30.83,35.21,-5.12),(4.25,5.90,30.94,34.74,-4.93)]
    for k,(x0,x1,low,high,front) in enumerate(sections):
        for j in range(3):
            a = x0+(x1-x0)*j/3
            b = x0+(x1-x0)*(j+1)/3
            z = front - (.14 if j==1 else 0)
            bottom = low + (.40 if j==1 else 0)
            joint = overlay if j==1 else fr
            joint.c(f"刘海{k}·纵条{j}",(a,bottom,z),(b,high,z+1.24),hair("hair_soft" if j==1 else "hair"))
    for i in range(15):
        x = (i-7)*.79
        edge = abs(x)/5.53
        back = 6.29-1.38*edge**2 + (.12 if i%2 else 0)
        low = 25.50+1.81*edge**1.65 + (.28 if i%2 else 0)
        if abs(x)>3.0: low = max(low,26.88)
        high = 34.40+1.10*(1-edge**2)
        oh.c(f"后颅纵束{i}",(x-.40,low,3.25),(x+.40,high,back-.83),hair("hair_d"))
        oh.c(f"后颅外束{i}",(x-.38,low+.24,back-.92),(x+.38,high-1.23,back),flat("hair_d"))

    flh = hairg.g("FLongHair", (0, 27.6, 2.3))
    mlh = flh.g("MLongHair", (0, 27.5, 2.3))
    lh = mlh.g("LongHair", (0, 27.45, 2.3))
    rib = hairg.g("Ribbon", (0, 28.6, -.5))
    for side, nm in ((1, "Right"), (-1, "Left")):
        def paired(group, name, x0, x1, y0, y1, z0, z1, paint, **kw):
            return group.c(nm + name, *box(side*x0, side*x1, y0, y1, z0, z1), paint, **kw)
        # 模板侧颊向外转折，鬓底留在其外侧；后颈的暗发仍承托花饰。
        for j,(z0,z1) in enumerate(((-3.36,-1.05),(-1.05,1.46),(1.46,4.42))):
            paired(bh,f"鬓底纵束{j}",3.99,5.30+j*.09,26.82+j*.16,34.41+j*.22,z0,z1,hair("hair_d"))
        paired(bh,"耳后覆发",4.44,5.31,26.51,32.28,.14,4.45,hair())
        paired(bh,"耳根",5.31,5.72,28.85,30.06,-.76,-.01,skin_part())
        prefix = "corner_h1" if side>0 else "corner_h2"
        cg = hairg.g(prefix,(side*5,33,-3.15))
        cg.origin = [side*5,33,-3.15]
        cm = cg.g(prefix+"_mid",(side*4.47,28,-3.20))
        ct = cm.g(prefix+"_tip",(side*3.98,23.5,-3.28))
        # 每条贯穿关节。侧视微倾，正视由外向内平滑收束。
        levels = np.array([(17.5,3.55,.50,-3.58,.54),(19.5,3.75,.70,-3.55,.66),
            (22.5,4.10,.90,-3.27,1.15),(26,4.14,.90,-3.36,1.12),
            (27,4.15,.90,-3.44,1.06),(29.5,4.50,1.10,-3.44,1.16),(33,5.0,1.30,-3.15,1.60)])
        cuts = sorted(set(levels[:,0])|{28,23.5},reverse=True)
        for k,(hi,lo) in enumerate(zip(cuts,cuts[1:])):
            bone = cg if lo>=28 else cm if lo>=23.5 else ct
            for j in range(2):
                def point(y):
                    cx,w,z,d = [np.interp(y,levels[:,0],col) for col in levels[:,1:].T]
                    clearance = np.interp(y,[26,27,28,29.5,33],[0,.22,.36,.18,0])
                    return (side*(cx+(j-.5)*w*.48),y,z+(j-.5)*.14-clearance),w*.54,d-.14-clearance
                start,w,d = point(hi);end,w2,d2 = point(lo)
                strand(bone,nm+f"前鬓{k}·{j}",start,end,(w+w2)/2,(d+d2)/2,flat("hair_l" if j else "hair"))
        name = nm+"SideLock"
        pt = lh.g(name,(side*4.8,26.2,3.2))
        pm = pt.g(name+"1",(side*5.8,22,3.9))
        pe = pm.g(name+"2",(side*5.40,18.5,3.65))
        paired(pt,"发绳",3.85,5.75,25.95,26.45,2.25,4.15,flat("cord"))
        profile = np.array([(15.5,4.7,3.2,1.1,1.3),(17.5,5.2,3.5,2,2),
            (19.5,5.6,3.8,2.8,2.5),(22,5.8,3.9,3.2,2.8),(24.5,5.4,3.6,2.6,2.4),(26.2,4.8,3.2,1.8,1.8)])
        for j,(u,v,tip) in enumerate(((-.5,0,17.6),(-.27,-.5,16.55),(0,.5,15.5),(.13,-.45,16.4),(.33,.41,17.35),(.5,-.03,18.32))):
            def sample(y):
                x,z,w,d = [np.interp(y,profile[:,0],col) for col in profile[:,1:].T]
                width = min(1.04,w*.49);depth = min(1.40,d*.69)
                # 标注侧面末梢向后挑，保留上段泪滴截面与三个关节位置。
                sweep = .96*max(0,(18.5-y)/3)**1.5
                return (side*(x+u*(w-width)),y,z+sweep+v*(d-depth)),width,depth
            cuts = sorted({26.18,24.5,22,19.5,18.5,tip+.83,tip},reverse=True)
            for k,(hi,lo) in enumerate(zip(cuts,cuts[1:])):
                bone = pt if lo>=22 else pm if lo>=18.5 else pe
                start,w,d = sample(hi);end,w2,d2 = sample(lo)
                taper = .27 if lo==tip else 0
                strand(bone,nm+f"泪滴发条{j}·{k}",start,end,(w+w2)/2-taper,(d+d2)/2-taper,
                       flat("hair_l" if j==4 else "hair"))
        paired(rig["hl_side"],"后颈外翻阶",3.62,4.30,26.04,27.51,3.86,4.78,hair())
        paired(rig["hl_m"],"后颈短发内层",1.18,1.96,25.46,26.44,4.09,4.90,hair("hair_d"))
        flower_center = (side*5.90,27.97,.94)
        fg = rib.g(nm + "HairFlower", flower_center)
        paired(fg,"发花托",5.12,5.64,27.66,28.24,.66,1.21,flat("flower_s"))
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
            ring.append(np.array([(hw+ridge)*math.sin(angle),y,-(hd+ridge)*math.cos(angle)]))
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
    kx, ky, kz = -2.28, 20.18, -2.83
    bowg = wf.g("WaistBow", (kx,ky,kz))
    bowg.c("结心",(kx-.46,ky-.52,kz-.81),(kx+.46,ky+.54,kz+.23),flat("red_d"))
    for side in (-1,1):
        # 两翼在深度上打开，让侧面也能看到前后边、暗结与内褶。
        z = kz - side*.21
        bowg.c(f"蝶翼内褶{side}", *box(kx+side*.28,kx+side*.77,ky-.37,ky+.39,z-.45,z+.29),flat("red_s"))
        bowg.c(f"蝶翼展开{side}", *box(kx+side*.57,kx+side*1.42,ky-.76,ky+.76,z-.42,z+.37),flat("red_l",edge="red"))
        bowg.c(f"蝶翼外缘{side}", *box(kx+side*1.27,kx+side*1.88,ky-1.00,ky+1.00,z-.40,z+.47),flat("red_l",edge="red"))
    # 两束从各自翼下并行，外带沿裙的左前角滚下，内带沿正面下垂。
    ribbons = [
        ("RibbonTail", [(-3.12,19.18,-2.54),(-3.97,16.29,-3.01),
                        (-5.02,13.12,-3.19),(-5.82,10.18,-2.89)]),
        ("InnerRibbonTail", [(-1.43,19.18,-3.35),(-2.26,16.31,-3.78),
                             (-3.32,13.27,-4.08),(-4.31,9.18,-3.85)]),
    ]
    for prefix,points in ribbons:
        parent = bowg
        x,y,z = points[0]
        bowg.c(prefix+"翼下反折",(x-.39,y-.08,min(z-.14,kz-.04)),
               (x+.39,19.88,max(z+.14,kz+.12)),bow_paint())
        for j,(start,end) in enumerate(zip(points,points[1:])):
            parent = parent.g(prefix+str(j),start)
            draw_ribbon(parent,prefix+str(j),start,end,j)

    # 可见尾干由一条二次 Bézier 曲线生成。按三维弧长定位骨节、尾花与切线段。
    begin = np.array([3.45,13.36,2.78])
    bend = np.array([4.78,6.06,5.17])
    end = np.array([9.65,4.83,8.82])
    t = np.linspace(0,1,1001)[:,None]
    curve = (1-t)**2*begin + 2*t*(1-t)*bend + t*t*end
    arc = np.r_[0,np.cumsum(np.linalg.norm(np.diff(curve,axis=0),axis=1))]
    total = arc[-1]
    def tail_point(fraction):
        return np.array([np.interp(fraction*total,arc,curve[:,axis]) for axis in range(3)])

    # 裙内的尾根从骶部接到第一枚外摆关节，藏在腿与后裙片之间。
    sacrum = np.array([.18,19.04,1.26])
    tg = down.g("Tail", sacrum)
    inside = [sacrum, np.array([.45,17.85,1.52]),np.array([.81,16.78,1.88]),np.array([1.16,15.80,2.15]),np.array([2.22,13.72,2.14]),begin]
    for i,(a,b) in enumerate(zip(inside,inside[1:])):
        count = math.ceil(np.linalg.norm(b-a)/.40)
        for k in range(count):
            u = (k+.5)/count
            center = (1-u)*a+u*b
            radius = min(.45,.23+.06*(i+u))
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
            diameter = 1.05-.15*(u+v)/2
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
    width = (.90,1.14,1.07)[tier]
    # 带身保留原有折光，末段在同一条接缝接入两片斜裁口。
    notch = .32 if tier == 2 else 0.0
    spans = (-.5,-.36,-.13,.13,.36,.5)
    for k,(a,b) in enumerate(zip(spans,spans[1:])):
        front = -.035*math.cos((a+b)*math.pi)
        center = np.asarray(start) + frame @ [(a+b)*width/2,-(length-notch)/2,front]
        half = np.array([(b-a)*width+.005,length-notch+.10,.33])/2
        paint = bow_paint("red_s" if k==0 else "red")
        bone.c(name+f"·绸面{k}",center-half,center+half,paint,rot=rotation)

    if tier == 2:
        # 两个斜底面在中线相会，形成一个贯通带厚的 V 口。
        for side in (-1,1):
            tilt = -side*math.atan2(notch,width/2)
            half = np.array([math.hypot(width/2,notch),.42,.33])/2
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
REVIEW_ROTATION = {"RightArm": (23,0,-26.9), "LeftArm": (23,0,26.9),
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


def coat_cycles(groups):
    cycles=[]
    for name,duration,amplitude in (("longnu_coat_walk",1.0,2.0),("longnu_coat_run",.64,3.1)):
        bones={}
        for g in groups:
            label=g["name"]
            if not label.startswith(("NomiCoatR","NomiCoatL")) or not label.endswith(("Hip","Hem")):
                continue
            side=1 if label[8]=="R" else -1
            front=label[9] in "01"
            keys=[]
            for k,phase in enumerate((0,1,0,-1,0)):
                wave=phase*side
                x=(-wave if front else -1+.35*wave)*amplitude
                z=side*amplitude*(1+.4*wave) if front else 0
                if label.endswith("Hem"):x*=.55;z*=.55
                keys.append({"channel":"rotation","time":duration*k/4,"uuid":str(uuidlib.uuid5(uuidlib.NAMESPACE_URL,f"{name}/{label}/{k}")),
                             "interpolation":"catmullrom","data_points":[{"x":str(x),"y":"0","z":str(z)}]})
            bones[g["uuid"]]={"name":label,"type":"bone","keyframes":keys}
        if bones:cycles.append({"name":name,"loop":"loop","length":duration,"snapping":25,"override":False,
                                "animators":bones,"uuid":str(uuidlib.uuid5(uuidlib.NAMESPACE_URL,name))})
    return cycles


def export_bbmodel(root, atlas, path):
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
        "animations": review_stance(groups) + coat_cycles(groups),
    }
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
    ne, ng = export_bbmodel(root, atlas, OUT / "longnu.bbmodel")
    preview(root, atlas)
    print("cubes", ne, "groups", ng, "atlas", atlas.shape)


if __name__ == "__main__":
    main()
