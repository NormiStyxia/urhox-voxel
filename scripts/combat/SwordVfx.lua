-- 剑攻击面片特效：全部是扁平的卡通面片（SwordSheet.shader），没有方块，也没有随机飞散。
-- 因果顺序：
--   * 挥动：刀光带只出现在剑刃已经扫过的地方，是一道两头尖、中间宽的完整月牙，尖端贴着当前剑刃
--   * 消失：先完整停留一会儿，再按各段的年龄从内侧向外缘撕开，最老的尾部先没，最后只剩外缘一线
--   * 打击点：命中那一帧在接触点出尖刺爆闪 + 一道沿挥砍方向的切线，薄片顺着剑的去向甩出
--   * 终结落地：落点一记贴地爆闪，月牙形波前从落点向前推出去
-- 所有面片写进同一个动态几何体；顶点色是给 shader 的数据（寿命 / 形状 / 种子 / 亮度）。
---@class SwordVfxSample
---@field rx number
---@field ry number
---@field rz number
---@field dx number
---@field dy number
---@field dz number
---@field len number
---@field age number
---@field life number
---@field s number 沿剑尖轨迹的累计米数
---@field w number 宽度比例（起手渐宽）
---@field reach number
---@field width number
---@field seed number
---@field power number
---@field stroke boolean 一笔的第一条采样，不与前一条相连
---@field head number 所在这一笔当前最前端的累计米数

---@class SwordVfxItem
---@field kind string burst | spindle | shard | wave | blade
---@field tag string
---@field age number
---@field life number
---@field px number
---@field py number
---@field pz number
---@field ax number
---@field ay number
---@field az number
---@field size number
---@field width number
---@field speed number
---@field from number
---@field to number
---@field seed number
---@field power number

---@class SwordVfx
---@field node Node
---@field geometry CustomGeometry
---@field material Material
---@field samples SwordVfxSample[]
---@field items SwordVfxItem[]
---@field camera Node|nil
local V={};V.__index=V

V.MAX_SAMPLES=120
V.MAX_ITEMS=40
local SHAPE_BAND,SHAPE_BURST,SHAPE_SPINDLE=0,.5,1
-- 所有刀光共用同一个节奏，对齐第五段落地的前扫波（GroundWave，全程 .65 秒）：
-- 挥砍本身约 .1 秒 + 每段 .5 秒，其中前四成完整停留，之后从内向外撕开。
local LINGER=.5
-- life：一段刀光从出现到完全撕掉的秒数；width：从剑尖向内覆盖剑身的比例；reach：甩出剑尖之外的比例。
---@type table<string, {life: number, width: number, reach: number, power: number}>
local STYLES={
    light={life=LINGER,width=.78,reach=.14,power=.7},
    heavy={life=LINGER,width=.86,reach=.20,power=.85},
    moon={life=LINGER,width=.92,reach=.26,power=1},
    cross={life=LINGER,width=.88,reach=.20,power=1},
}
local TAPER=1.0 -- 月牙两端收尖的弧长（米）
-- 视角扭转的最大强度（1 = 侧看时完全转到正对镜头）；0 = 关掉扭转，用于 A/B 对比
local TWIST_MAX=.72
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function easeOut(u) return 1-(1-u)^3 end

---@param scene Node
---@param camera Node|nil 不传则每帧取 0 号视口的相机
---@return SwordVfx
function V.New(scene,camera)
    local self=setmetatable({},V)
    local material=Material:new()
    assert(material:SetSurfaceShader('Shaders/BLGL/SwordSheet.shader'),'SwordSheet.shader unavailable')
    local ok,lowFx=pcall(function()
        local platform=require('urhox-libs.Platform.PlatformUtils')
        return platform.IsWebPlatform() or platform.IsMobilePlatform()
    end)
    -- 移动端 / Web 的泛光没有色调映射兜底，白芯的发光倍数压低。
    material:SetShaderParameter('glow',Variant((ok and lowFx==true) and 1.3 or 1.9))
    self.material=material
    self.node=scene:CreateChild('SwordVfx');self.node.temporary=true;self.node.enabled=false
    local geometry=self.node:CreateComponent('CustomGeometry') --[[@as CustomGeometry]]
    geometry:SetNumGeometries(1);geometry:SetDynamic(true)
    geometry.castShadows=false
    geometry:BeginGeometry(0,TRIANGLE_LIST);geometry:Commit()
    geometry:SetMaterial(0,material)
    self.geometry=geometry
    self.camera=camera
    self.samples,self.items,self.spare={},{},{}
    -- 每个采样扭转后的宽度方向（每帧重算），按下标复用避免每帧新建
    self.bwx,self.bwy,self.bwz={},{},{}
    self.style=STYLES.light
    self.twist=TWIST_MAX
    self.stroke,self.has,self.first=false,false,false
    self.travel,self.origin,self.idle,self.serial,self.vertices=0.0,0.0,0.0,0,0
    self.nx,self.ny,self.nz=0.0,0.0,0.0
    self.swept,self.peak=0.0,0.0
    self.lrx,self.lry,self.lrz,self.ldx,self.ldy,self.ldz,self.llen=0.0,0.0,0.0,0.0,1.0,0.0,0.0
    self.tx,self.ty,self.tz=0.0,0.0,0.0
    self.brx,self.bry,self.brz,self.bdx,self.bdy,self.bdz,self.blen=0.0,0.0,0.0,0.0,1.0,0.0,0.0
    self.chargeClock=0.0
    self.vrx,self.vry,self.vrz,self.vux,self.vuy,self.vuz,self.vfx,self.vfy,self.vfz=1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,1.0
    return self
end

--- 开始一次挥砍：新的一笔，从上一帧的剑位接起。上一刀还没撕完的刀光按自己的年龄继续消失，不会被掐掉。
---@param kind string light | heavy | moon | cross
function V:Begin(kind)
    self.style=STYLES[kind] or STYLES.light
    self.kind=kind
    self.stroke,self.first=true,true
    self.swept,self.peak=0.0,0.0
    self.serial=self.serial+1
    for i=#self.items,1,-1 do if self.items[i].tag=='charge' then table.remove(self.items,i) end end
end

function V:End()
    self.stroke=false
end

function V:Push(rx,ry,rz,dx,dy,dz,len)
    local samples=self.samples
    local sample=table.remove(self.spare)
    if sample==nil then
        sample={rx=0.0,ry=0.0,rz=0.0,dx=0.0,dy=0.0,dz=0.0,len=0.0,age=0.0,life=0.0,s=0.0,w=0.0,
            reach=0.0,width=0.0,seed=0.0,power=0.0,stroke=false,head=0.0}
    end
    local style=self.style
    sample.rx,sample.ry,sample.rz,sample.dx,sample.dy,sample.dz,sample.len=rx,ry,rz,dx,dy,dz,len
    sample.age,sample.life,sample.s=0.0,style.life,self.travel
    -- 起手端收尖：刀光是被剑“拉”出来的，不是凭空整片出现
    sample.w=math.sqrt(math.min(1,.004+(self.travel-self.origin)/TAPER))
    sample.reach,sample.width,sample.power=style.reach,style.width,style.power
    sample.seed=(self.serial*.37)%1
    sample.stroke=self.first
    self.first=false
    if #samples>=V.MAX_SAMPLES then
        self.spare[#self.spare+1]=table.remove(samples,1)
        if samples[1] then samples[1].stroke=true end
    end
    samples[#samples+1]=sample
end

--- 每帧都送入剑刃根部 / 尖端的世界坐标（不在挥砍中也送，用来记住上一帧的剑位和转向）。
--- 挥砍中，上一帧到这一帧之间按“绕手臂支点旋转”补出整段圆弧：一帧转过一百多度也是完整的弧。
---@param root Vector3
---@param tip Vector3
function V:Sample(root,tip)
    local rx,ry,rz=root.x,root.y,root.z
    local dx,dy,dz=tip.x-rx,tip.y-ry,tip.z-rz
    local len=math.sqrt(dx*dx+dy*dy+dz*dz)
    if not (len>=1e-4 and len<1e4) then return end -- 也挡掉 NaN / 无穷大的骨骼坐标
    dx,dy,dz=dx/len,dy/len,dz/len
    local fresh=self.has and self.idle<.25
    self.idle=0.0
    local px,py,pz,ex,ey,ez,plen=self.lrx,self.lry,self.lrz,self.ldx,self.ldy,self.ldz,self.llen
    local mx,my,mz=tip.x-(px+ex*plen),tip.y-(py+ey*plen),tip.z-(pz+ez*plen)
    local moved=math.sqrt(mx*mx+my*my+mz*mz)
    if not fresh or moved>3.5 then
        -- 没有上一帧可接（刚拿到手 / 瞬移）：只记位置，从下一帧开始接
        self.lrx,self.lry,self.lrz,self.ldx,self.ldy,self.ldz,self.llen=rx,ry,rz,dx,dy,dz,len
        self.has,self.first=true,true
        self.nx,self.ny,self.nz=0.0,0.0,0.0
        return
    end
    if moved<.03 then return end
    -- 转轴与转角。超过 100° 时最短弧可能是反方向，用上一帧的转向来判定走哪一边。
    local kx,ky,kz=ey*dz-ez*dy,ez*dx-ex*dz,ex*dy-ey*dx
    local kl=math.sqrt(kx*kx+ky*ky+kz*kz)
    local angle=math.atan(kl,ex*dx+ey*dy+ez*dz)
    local known=self.nx*self.nx+self.ny*self.ny+self.nz*self.nz>.5
    if kl>1e-4 then kx,ky,kz=kx/kl,ky/kl,kz/kl
    elseif known and angle>1 then kx,ky,kz=self.nx,self.ny,self.nz
    else kx,ky,kz,angle=0.0,0.0,0.0,0.0 end
    if known and angle>math.rad(100) and kx*self.nx+ky*self.ny+kz*self.nz<0 then
        angle=math.pi*2-angle
        kx,ky,kz=-kx,-ky,-kz
    end
    if self.stroke then
        -- 月牙只由“挥”这一下画出来。转速掉到这一刀峰值的一小部分（收势、剑被带回架势、
        -- 身体带着剑平移），或转向反了，这一笔就结束；否则收剑的路线会接在月牙后面折出一段。
        local reversed=known and self.swept>math.rad(20) and kx*self.nx+ky*self.ny+kz*self.nz<.3
        if reversed or (self.swept>math.rad(40) and angle<self.peak*.15) then
            self.stroke=false
        elseif angle<math.rad(1.5) then
            return
        end
    end
    if self.stroke then
        self.swept=self.swept+angle
        self.peak=math.max(self.peak,angle)
        -- 支点：root = P + dir·r，两帧共用同一个 r，解出来就是手臂绕着转的那个点
        local ddx,ddy,ddz=dx-ex,dy-ey,dz-ez
        local dd=ddx*ddx+ddy*ddy+ddz*ddz
        local r=0.0
        if dd>1e-4 then r=clamp(((rx-px)*ddx+(ry-py)*ddy+(rz-pz)*ddz)/dd,0,1.5) end
        local ax,ay,az=px-ex*r,py-ey*r,pz-ez*r
        local bx,by,bz=rx-dx*r,ry-dy*r,rz-dz*r
        if self.first then
            self.origin=self.travel
            self:Push(px,py,pz,ex,ey,ez,plen)
        end
        local arc=math.max(moved,angle*(r+(plen+len)*.5))
        local n=math.min(34,math.max(1,math.ceil(math.max(angle/math.rad(6),arc/.14))))
        for i=1,n do
            local u=i/n
            local c,sn=math.cos(angle*u),math.sin(angle*u)
            local ix=ex*c+(ky*ez-kz*ey)*sn
            local iy=ey*c+(kz*ex-kx*ez)*sn
            local iz=ez*c+(kx*ey-ky*ex)*sn
            if i==n then ix,iy,iz=dx,dy,dz end
            self.travel=self.travel+arc/n
            self:Push(ax+(bx-ax)*u+ix*r,ay+(by-ay)*u+iy*r,az+(bz-az)*u+iz*r,ix,iy,iz,plen+(len-plen)*u)
        end
        -- 剑尖此刻的去向：命中特效沿它展开
        if angle>.05 then self.tx,self.ty,self.tz=ky*dz-kz*dy,kz*dx-kx*dz,kx*dy-ky*dx
        else self.tx,self.ty,self.tz=mx/moved,my/moved,mz/moved end
    end
    if angle>.03 then self.nx,self.ny,self.nz=kx,ky,kz end
    self.lrx,self.lry,self.lrz,self.ldx,self.ldy,self.ldz,self.llen=rx,ry,rz,dx,dy,dz,len
    if self.stroke then self:Draw() end
end

---@param kind string
---@param tag string
---@param life number
---@return SwordVfxItem|nil
function V:Add(kind,tag,life,px,py,pz,size)
    if #self.items>=V.MAX_ITEMS then return nil end
    ---@type SwordVfxItem
    local item={kind=kind,tag=tag,age=0.0,life=life,px=px,py=py,pz=pz,ax=0.0,ay=0.0,az=0.0,
        size=size,width=0.0,speed=0.0,from=0.0,to=0.0,seed=(#self.items*.31+self.serial*.17)%1,power=1.0}
    self.items[#self.items+1]=item
    return item
end

--- 命中：接触点爆闪；切线沿最近一次挥砍方向穿过接触点；薄片顺着剑的去向扇形甩出。
---@param pos Vector3|nil
---@param strong boolean|nil
function V:Contact(pos,strong)
    if not pos then return end
    local x,y,z=pos.x,pos.y,pos.z
    self:Basis()
    local tx,ty,tz=self.tx,self.ty,self.tz
    local swung=tx*tx+ty*ty+tz*tz>.5
    if not swung then tx,ty,tz=self.vrx,self.vry,self.vrz end
    local burst=self:Add('burst','hit',strong and .32 or .26,x,y,z,strong and 1.5 or 1.0)
    if burst then burst.power=strong and 1 or .8 end
    local cut=self:Add('spindle','hit',strong and .30 or .24,x,y,z,strong and 3.0 or 2.0)
    if cut then cut.ax,cut.ay,cut.az,cut.width=tx,ty,tz,strong and .26 or .18 end
    if not swung then self:Draw();return end
    -- 扇面在挥砍平面内：以剑的去向为轴，向剑尖外侧 / 内侧各偏开，角度和速度都是固定表
    local bx,by,bz=self.ldx,self.ldy,self.ldz
    local dot=bx*tx+by*ty+bz*tz
    bx,by,bz=bx-tx*dot,by-ty*dot,bz-tz*dot
    local bl=math.sqrt(bx*bx+by*by+bz*bz)
    if bl<1e-3 then self:Draw();return end
    bx,by,bz=bx/bl,by/bl,bz/bl
    -- 甩片散成锥形：交替向挥砍平面两侧偏出，不再是一把平面扇子
    local nX,nY,nZ=self.nx,self.ny,self.nz
    if nX*nX+nY*nY+nZ*nZ<.5 then nX,nY,nZ=ty*bz-tz*by,tz*bx-tx*bz,tx*by-ty*bx end
    local count=strong and 5 or 3
    for i=1,count do
        local a=math.rad((i-(count+1)*.5)*24)
        local c,s=math.cos(a),math.sin(a)
        local tilt=math.rad(((i%3)-1)*22)
        local ct,stt=math.cos(tilt),math.sin(tilt)
        local dx,dy,dz=tx*c+bx*s,ty*c+by*s,tz*c+bz*s
        local ox,oy,oz=nX*(s*stt),nY*(s*stt),nZ*(s*stt)
        local shard=self:Add('shard','hit',.34+(i%2)*.08,x,y,z,.46-(i%2)*.10)
        if shard then
            shard.ax,shard.ay,shard.az=dx*ct+ox,dy*ct+oy,dz*ct+oz
            shard.width,shard.speed,shard.power=.11,(strong and 5.5 or 4.2)-(i%2)*1.2,.75
        end
    end
    self:Draw()
end

--- 终结技落地：落点爆闪，一圈向外翻起的月牙波前只朝前方推出去。
---@param pos Vector3 脚下地面点
---@param forward Vector3
function V:GroundWave(pos,forward)
    local fx,fz=forward and forward.x or 0,forward and forward.z or 1
    local l=math.sqrt(fx*fx+fz*fz)
    if l<1e-4 then fx,fz,l=0,1,1 end
    fx,fz=fx/l,fz/l
    local cx,cy,cz=pos.x+fx*.65,pos.y+.05,pos.z+fz*.65
    local flash=self:Add('burst','wave',.30,cx,cy+.3,cz,1.7)
    if flash then flash.ax,flash.az=fx,fz end
    local wave=self:Add('wave','wave',.65,cx,cy,cz,2.6)
    if wave then wave.ax,wave.az=fx,fz end
    self:Draw()
end

--- 记录当前剑刃的位置，挂在剑身上的面片跟着剑走。
---@param root Vector3
---@param tip Vector3
---@return number length
function V:PlaceBlade(root,tip)
    local dx,dy,dz=tip.x-root.x,tip.y-root.y,tip.z-root.z
    local len=math.sqrt(dx*dx+dy*dy+dz*dz)
    if len<1e-4 then return 0 end
    self.brx,self.bry,self.brz=root.x,root.y,root.z
    self.bdx,self.bdy,self.bdz,self.blen=dx/len,dy/len,dz/len,len
    return len
end

--- 蓄力中每帧调用：薄片从剑根沿剑身滑到蓄力进度对应的高度，越蓄越靠近剑尖。
---@param root Vector3
---@param tip Vector3
---@param charge number 0..1
---@param dt number
function V:Charge(root,tip,charge,dt)
    if self:PlaceBlade(root,tip)<=0 then return end
    self.chargeClock=self.chargeClock-dt
    if self.chargeClock>0 then return end
    self.chargeClock=.11
    local item=self:Add('blade','charge',.24,0,0,0,.30)
    if item then item.from,item.to,item.width,item.power=0,.15+.8*clamp(charge,0,1),.10,.6 end
end

--- 蓄满：整条剑身亮一下，剑尖爆闪。
---@param root Vector3
---@param tip Vector3
function V:ChargeBurst(root,tip)
    local len=self:PlaceBlade(root,tip)
    if len<=0 then return end
    for i=#self.items,1,-1 do if self.items[i].tag=='charge' then table.remove(self.items,i) end end
    local flash=self:Add('blade','charge',.22,0,0,0,len*1.25)
    if flash then flash.from,flash.to,flash.width=.5,.5,.24 end
    local burst=self:Add('blade','charge',.20,0,0,0,.75)
    if burst then burst.from,burst.to,burst.width=1,1,-1 end
    self:Draw()
end

-- 取相机的右 / 上 / 前方向；拿不到相机时退回世界坐标轴。
function V:Basis()
    local node=self.camera
    if node==nil then
        local r=rawget(_G,'renderer') --[[@as Renderer|nil]]
        local viewport=r and r:GetViewport(0)
        local camera=viewport and viewport.camera
        node=camera and camera.node or nil
    end
    if node==nil then return end
    local right,up,forward=node.worldRight,node.worldUp,node.worldDirection
    self.vrx,self.vry,self.vrz=right.x,right.y,right.z
    self.vux,self.vuy,self.vuz=up.x,up.y,up.z
    self.vfx,self.vfy,self.vfz=forward.x,forward.y,forward.z
end

local NORMAL=Vector3(0,1,0)
---@param g CustomGeometry
---@param color Color
local function vertex(g,x,y,z,u,v,color)
    g:DefineVertex(Vector3(x,y,z));g:DefineNormal(NORMAL)
    g:DefineColor(color);g:DefineTexCoord(Vector2(u,v))
end
-- 以 c 为中心、a / b 为两条半轴的四边形。
---@param g CustomGeometry
---@param color Color
local function quad(g,cx,cy,cz,ax,ay,az,bx,by,bz,color)
    vertex(g,cx-ax-bx,cy-ay-by,cz-az-bz,0,0,color)
    vertex(g,cx+ax-bx,cy+ay-by,cz+az-bz,1,0,color)
    vertex(g,cx+ax+bx,cy+ay+by,cz+az+bz,1,1,color)
    vertex(g,cx-ax-bx,cy-ay-by,cz-az-bz,0,0,color)
    vertex(g,cx+ax+bx,cy+ay+by,cz+az+bz,1,1,color)
    vertex(g,cx-ax+bx,cy-ay+by,cz-az+bz,0,1,color)
    return 6
end

-- 沿 axis 的梭形面片，绕自身轴转到正对相机。
---@param g CustomGeometry
---@param color Color
function V:Spindle(g,cx,cy,cz,ax,ay,az,half,width,color)
    local sx,sy,sz=ay*self.vfz-az*self.vfy,az*self.vfx-ax*self.vfz,ax*self.vfy-ay*self.vfx
    local sl=math.sqrt(sx*sx+sy*sy+sz*sz)
    if sl<1e-3 then sx,sy,sz,sl=self.vux,self.vuy,self.vuz,1 end
    local w=width*.5/sl
    return quad(g,cx,cy,cz,ax*half,ay*half,az*half,sx*w,sy*w,sz*w,color)
end

-- 交叉双面片：沿轴再补一片与其垂直的，各自按正对视线的程度保留宽度。
-- 单片在正对轴的方向会被压成一条线，交叉后从任何角度都能看到实体，不会是一片纸。
---@param g CustomGeometry
---@param color Color
function V:Cross(g,cx,cy,cz,ax,ay,az,half,width,color)
    local vx,vy,vz=self.vfx,self.vfy,self.vfz
    local sx,sy,sz=ay*vz-az*vy,az*vx-ax*vz,ax*vy-ay*vx
    local sl=math.sqrt(sx*sx+sy*sy+sz*sz)
    if sl<1e-3 then sx,sy,sz,sl=self.vux,self.vuy,self.vuz,1 end
    sx,sy,sz=sx/sl,sy/sl,sz/sl
    -- 两片的宽度方向：s 与 a×s；法线分别是 a×s 与 -s
    local qx,qy,qz=ay*sz-az*sy,az*sx-ax*sz,ax*sy-ay*sx
    local f1=math.abs(qx*vx+qy*vy+qz*vz)
    local f2=math.abs(sx*vx+sy*vy+sz*vz)
    local w1=width*.5*(.45+.55*f1)
    local w2=width*.5*(.45+.55*f2)
    local n=quad(g,cx,cy,cz,ax*half,ay*half,az*half,sx*w1,sy*w1,sz*w1,color)
    return n+quad(g,cx,cy,cz,ax*half,ay*half,az*half,qx*w2,qy*w2,qz*w2,color)
end

--- 视角扭转：刀光原本只铺在挥砍平面里，视线顺着这个平面看过去时，面片被压成一条线。
--- 整一笔只用一个倾斜方向（这一笔的平均平面法线），所有横截面一起斜过去：
--- 正对平面看时不动，越接近侧看斜得越多。横截面始终平行，不会被拧成麻花或折出棱角。
function V:TwistWidths()
    local samples=self.samples
    local n=#samples
    local bwx,bwy,bwz=self.bwx,self.bwy,self.bwz
    local vx,vy,vz=self.vfx,self.vfy,self.vfz
    local twist=self.twist or 0
    local i=1
    while i<=n do
        -- 一笔的范围 [i,j]
        local j=i
        while j<n and not samples[j+1].stroke do j=j+1 end
        -- 平均平面法线：相邻采样 d×弦 累加，先按第一项对齐符号
        local nx,ny,nz=0.0,0.0,0.0
        for q=i,j-1 do
            local a,b=samples[q],samples[q+1]
            local cx,cy,cz=b.rx-a.rx,b.ry-a.ry,b.rz-a.rz
            local kx,ky,kz=a.dy*cz-a.dz*cy,a.dz*cx-a.dx*cz,a.dx*cy-a.dy*cx
            local kl=math.sqrt(kx*kx+ky*ky+kz*kz)
            if kl>1e-6 then
                kx,ky,kz=kx/kl,ky/kl,kz/kl
                if nx*kx+ny*ky+nz*kz<0 then kx,ky,kz=-kx,-ky,-kz end
                nx,ny,nz=nx+kx,ny+ky,nz+kz
            end
        end
        local nl=math.sqrt(nx*nx+ny*ny+nz*nz)
        local k=0.0
        if nl>1e-3 then
            nx,ny,nz=nx/nl,ny/nl,nz/nl
            -- 法线与视线越接近垂直（侧看），横截面斜得越多
            k=twist*(1-clamp(math.abs(nx*vx+ny*vy+nz*vz),0,1))
        end
        for q=i,j do
            local s=samples[q]
            local dx,dy,dz=s.dx,s.dy,s.dz
            -- 剑越接近平行于法线，能斜的余地越小；用渐变而不是开关，否则会折出一道棱
            local align=math.abs(dx*nx+dy*ny+dz*nz)
            local kk=k*clamp((.92-align)/.32,0,1)
            if kk>1e-3 then
                local wx,wy,wz=dx+(nx-dx)*kk,dy+(ny-dy)*kk,dz+(nz-dz)*kk
                local wl=math.sqrt(wx*wx+wy*wy+wz*wz)
                if wl>1e-4 then dx,dy,dz=wx/wl,wy/wl,wz/wl end
            end
            bwx[q],bwy[q],bwz[q]=dx,dy,dz
        end
        i=j+1
    end
end

--- 把当前所有刀光和面片重建进几何体。
function V:Draw()
    local samples,items=self.samples,self.items
    if #samples<2 and #items==0 then
        self.vertices=0
        if self.node.enabled then self.node.enabled=false end
        return
    end
    self:Basis()
    local g=self.geometry
    g:BeginGeometry(0,TRIANGLE_LIST)
    local count=0
    self:TwistWidths()
    local bwx,bwy,bwz=self.bwx,self.bwy,self.bwz
    ---@type SwordVfxSample|nil
    local p=nil
    local pox,poy,poz,pix,piy,piz=0.0,0.0,0.0,0.0,0.0,0.0
    ---@type Color
    local pc=nil
    -- 每一笔当前的最前端：月牙朝剑的那一头也收尖
    local head=nil
    for i=#samples,1,-1 do
        local s=samples[i]
        if head==nil then head=s.s end
        s.head=head
        if s.stroke then head=nil end
    end
    for i=1,#samples do
        local s=samples[i]
        local w=math.min(s.w,math.sqrt(math.min(1,.004+(s.head-s.s)/TAPER)))
        local outer=s.len*(1+s.reach*w)
        local inner=s.len*(1-s.width*w)
        -- 宽度方向可能已被扭转出挥砍平面：绕剑身中段转，中段始终压在剑上
        local wx,wy,wz=bwx[i],bwy[i],bwz[i]
        local mid=(inner+outer)*.5
        local bx,by,bz=s.rx+s.dx*mid,s.ry+s.dy*mid,s.rz+s.dz*mid
        local ox,oy,oz=bx+wx*(outer-mid),by+wy*(outer-mid),bz+wz*(outer-mid)
        local ix,iy,iz=bx+wx*(inner-mid),by+wy*(inner-mid),bz+wz*(inner-mid)
        local c=Color(clamp(s.age/s.life,0,1),SHAPE_BAND,s.seed,s.power)
        if p and not s.stroke then
            vertex(g,pix,piy,piz,p.s,0,pc);vertex(g,pox,poy,poz,p.s,1,pc);vertex(g,ox,oy,oz,s.s,1,c)
            vertex(g,pix,piy,piz,p.s,0,pc);vertex(g,ox,oy,oz,s.s,1,c);vertex(g,ix,iy,iz,s.s,0,c)
            count=count+6
        end
        p,pc=s,c
        pox,poy,poz,pix,piy,piz=ox,oy,oz,ix,iy,iz
    end
    for i=1,#items do
        local it=items[i]
        local u=clamp(it.age/it.life,0,1)
        if it.kind=='burst' then
            local h=it.size*.5*(.5+.5*easeOut(u))
            count=count+quad(g,it.px,it.py,it.pz,self.vrx*h,self.vry*h,self.vrz*h,self.vux*h,self.vuy*h,self.vuz*h,
                Color(u,SHAPE_BURST,it.seed,it.power))
        elseif it.kind=='spindle' then
            -- 切线一出现就是全长，然后变细、从尾部收掉
            count=count+self:Cross(g,it.px,it.py,it.pz,it.ax,it.ay,it.az,it.size*.5,it.width,
                Color(u,SHAPE_SPINDLE,it.seed,it.power))
        elseif it.kind=='shard' then
            -- 减速飞出：位移 = v·t·(1 - t/2T)
            local d=.18+it.speed*it.age*(1-u*.5)
            count=count+self:Cross(g,it.px+it.ax*d,it.py+it.ay*d,it.pz+it.az*d,it.ax,it.ay,it.az,it.size*.5,it.width,
                Color(u,SHAPE_SPINDLE,it.seed,it.power))
        elseif it.kind=='blade' then
            local t=it.from+(it.to-it.from)*easeOut(u)
            local x,y,z=self.brx+self.bdx*self.blen*t,self.bry+self.bdy*self.blen*t,self.brz+self.bdz*self.blen*t
            if it.width<0 then
                local h=it.size*.5*(.5+.5*easeOut(u))
                count=count+quad(g,x,y,z,self.vrx*h,self.vry*h,self.vrz*h,self.vux*h,self.vuy*h,self.vuz*h,
                    Color(u,SHAPE_BURST,it.seed,it.power))
            else
                count=count+self:Spindle(g,x,y,z,self.bdx,self.bdy,self.bdz,it.size*.5,it.width,
                    Color(u,SHAPE_SPINDLE,it.seed,it.power))
            end
        elseif it.kind=='wave' then
            -- 月牙波前：半径随时间外推，只铺前方 ±78°。内缘贴地、外缘翻起，
            -- 镜头贴着地面看过去也是一道立起来的浪，不会被压成一条线
            local grow=easeOut(u)
            local radius=.45+(it.size-.45)*grow
            local band=.85*(1-.45*u)
            local c=Color(clamp(u*.9,0,1),SHAPE_BAND,it.seed,it.power)
            local base=math.atan(it.ax,it.az)
            local segments=18
            local lx,lz,lix,liz,ls,ltop=0.0,0.0,0.0,0.0,0.0,0.0
            for k=0,segments do
                local a=base+math.rad(-78+156*k/segments)
                local sx,sz=math.sin(a),math.cos(a)
                -- 两端收尖成月牙
                local taper=math.sin(math.pi*k/segments)^.6
                local ro,ri=radius,radius-band*taper
                local x,z,jx,jz=it.px+sx*ro,it.pz+sz*ro,it.px+sx*ri,it.pz+sz*ri
                local top=it.py+.75*taper*(1-u*.7)
                local arc=radius*math.rad(156)*k/segments
                if k>0 then
                    vertex(g,lix,it.py,liz,ls,0,c);vertex(g,lx,ltop,lz,ls,1,c);vertex(g,x,top,z,arc,1,c)
                    vertex(g,lix,it.py,liz,ls,0,c);vertex(g,x,top,z,arc,1,c);vertex(g,jx,it.py,jz,arc,0,c)
                    count=count+6
                end
                lx,lz,lix,liz,ls,ltop=x,z,jx,jz,arc,top
            end
        end
    end
    g:Commit()
    self.vertices=count
    self.node.enabled=count>0
end

---@param dt number
function V:Update(dt)
    self.idle=self.idle+dt
    local samples,items=self.samples,self.items
    if #samples==0 and #items==0 then
        if self.node.enabled then self.node.enabled=false end
        return
    end
    for i=1,#samples do samples[i].age=samples[i].age+dt end
    -- 采样按时间顺序排列，过期的一定在最前面
    while samples[1] and samples[1].age>=samples[1].life do
        self.spare[#self.spare+1]=table.remove(samples,1)
        if samples[1] then samples[1].stroke=true end
    end
    for i=#items,1,-1 do
        local it=items[i]
        it.age=it.age+dt
        if it.age>=it.life then table.remove(items,i) end
    end
    self:Draw()
end

---@param tag string|nil arc | hit | wave | charge；nil 为全部
---@return integer
function V:Count(tag)
    if tag=='arc' then return #self.samples end
    local n=0
    for _,it in ipairs(self.items) do if tag==nil or it.tag==tag then n=n+1 end end
    return tag==nil and n+#self.samples or n
end

local function drop(self,tag)
    for i=#self.items,1,-1 do
        if tag==nil or self.items[i].tag==tag then table.remove(self.items,i) end
    end
end

--- 动作被打断（移动取消、收剑、受击）：不再继续画，蓄力薄片撤掉；
--- 已经留在空中的月牙、命中和落地波前按自己的节奏消失，不会被一下抹掉。
function V:Stop()
    self:End()
    drop(self,'charge')
end

--- 只清刀光与蓄力，命中和落地波前照常播完。
function V:ClearSword()
    self:End()
    for i=#self.samples,1,-1 do self.spare[#self.spare+1]=table.remove(self.samples,i) end
    drop(self,'charge')
    self:Draw()
end

function V:Clear()
    self:End()
    for i=#self.samples,1,-1 do self.spare[#self.spare+1]=table.remove(self.samples,i) end
    drop(self,nil)
    self:Draw()
end

function V:Dispose()
    self.node:Remove()
end

return V
