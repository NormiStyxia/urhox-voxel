-- 剑普攻的步法：落脚点驱动的两段腿 IK，跑在 CombatAnim.Apply 之后。
-- 步法表写在 AnimClips 的 clip.footwork 里。支撑脚锁在世界坐标，身体被突进带过去；
-- 迈步脚沿弧线走到“落地那一刻身体坐标系里的目标点”，所以突进会把脚带远。
-- 胯到脚够不着时整个人往下沉（弓步），大腿、小腿、脚掌各自解出朝向。
-- 只认导入骨架（大腿 + 小腿 + 脚）；体素版没有膝盖骨，整个模块不生效。
---@class FootPlantLeg
---@field def {key:string,hip:string,knee:string,ankle:string,side:number}
---@field hip Node
---@field knee Node
---@field ankle Node
---@field steps table[]
---@field upper number
---@field lower number
---@field kx number
---@field ky number
---@field kz number
---@field ax number
---@field ay number
---@field az number
---@field ankleY number
---@field x number
---@field y number
---@field z number
---@field yaw number
---@field pitch number
---@field heel number
---@field swing boolean
---@field fx number
---@field fy number
---@field fz number
---@field fyaw number
---@field cursor integer
---@field restX number
---@field settling boolean
---@field gx number
---@field gz number
---@field limit number

---@class FootPlant
---@field character BlockCharacter
---@field anim {Footwork: fun(self): CombatClip|nil, number, number, integer}
---@field pelvis Node|nil
---@field legs FootPlantLeg[]
---@field clip CombatClip|nil
---@field handle integer
---@field active boolean
---@field drop number
---@field weight number
local F={};F.__index=F

local LEGS={
    {key="R",hip="leg_right",knee="ysm_RightLowerLeg",ankle="ysm_RightFoot",side=1},
    {key="L",hip="leg_left",knee="ysm_LeftLowerLeg",ankle="ysm_LeftFoot",side=-1},
}
local MAX_DROP=.16   -- 弓步最多把胯压低多少（米）
local REACH=.985     -- 留一点余量，腿永远不完全伸直，膝盖不会在直腿处来回翻
local TOE_PITCH=18   -- 迈步中脚尖下压的角度（离地蹬出 / 收回）
local HEEL=.10       -- 后脚够不着时踮起脚跟的最大高度（米），脚尖仍踩在原地
local TOE=.14        -- 踝到脚尖的距离，用来把踮脚换成脚掌的下压角

local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function smooth(u) return u*u*(3-2*u) end
local function length(x,y,z) return math.sqrt(x*x+y*y+z*z) end
local function wrap(a) return (a+180)%360-180 end

-- 两组正交基（各自 X/Y/Z 三根轴）之间的旋转：R = W * L^T。
---@return Quaternion
local function fromBases(wx,wy,wz,lx,ly,lz)
    local m00=wx.x*lx.x+wy.x*ly.x+wz.x*lz.x
    local m01=wx.x*lx.y+wy.x*ly.y+wz.x*lz.y
    local m02=wx.x*lx.z+wy.x*ly.z+wz.x*lz.z
    local m10=wx.y*lx.x+wy.y*ly.x+wz.y*lz.x
    local m11=wx.y*lx.y+wy.y*ly.y+wz.y*lz.y
    local m12=wx.y*lx.z+wy.y*ly.z+wz.y*lz.z
    local m20=wx.z*lx.x+wy.z*ly.x+wz.z*lz.x
    local m21=wx.z*lx.y+wy.z*ly.y+wz.z*lz.y
    local m22=wx.z*lx.z+wy.z*ly.z+wz.z*lz.z
    local trace=m00+m11+m22
    local w,x,y,z
    if trace>0 then
        local s=math.sqrt(trace+1)*2
        w,x,y,z=s*.25,(m21-m12)/s,(m02-m20)/s,(m10-m01)/s
    elseif m00>m11 and m00>m22 then
        local s=math.sqrt(1+m00-m11-m22)*2
        w,x,y,z=(m21-m12)/s,s*.25,(m01+m10)/s,(m02+m20)/s
    elseif m11>m22 then
        local s=math.sqrt(1+m11-m00-m22)*2
        w,x,y,z=(m02-m20)/s,(m01+m10)/s,s*.25,(m12+m21)/s
    else
        local s=math.sqrt(1+m22-m00-m11)*2
        w,x,y,z=(m10-m01)/s,(m02+m20)/s,(m12+m21)/s,s*.25
    end
    return Quaternion(w,x,y,z)
end

-- 骨骼的一组基：Y 轴沿骨骼朝上（指向父关节），Z 轴尽量朝 pole。
---@return {x:number,y:number,z:number}, {x:number,y:number,z:number}, {x:number,y:number,z:number}
local function basis(dx,dy,dz,px,py,pz)
    local l=length(dx,dy,dz)
    local yx,yy,yz=-dx/l,-dy/l,-dz/l
    local d=px*yx+py*yy+pz*yz
    local zx,zy,zz=px-yx*d,py-yy*d,pz-yz*d
    local zl=length(zx,zy,zz)
    if zl<1e-6 then
        -- pole 与骨骼平行：随便取一根垂直轴，只在病态姿势出现
        zx,zy,zz=math.abs(yx)<.9 and 1 or 0,0,math.abs(yx)<.9 and 0 or 1
        d=zx*yx+zy*yy+zz*yz
        zx,zy,zz=zx-yx*d,zy-yy*d,zz-yz*d
        zl=length(zx,zy,zz)
    end
    zx,zy,zz=zx/zl,zy/zl,zz/zl
    return {x=yy*zz-yz*zy,y=yz*zx-yx*zz,z=yx*zy-yy*zx},{x=yx,y=yy,z=yz},{x=zx,y=zy,z=zz}
end

local function inverse(q) return Quaternion(q.w,-q.x,-q.y,-q.z) end

-- 骨骼从模型根算起的静止高度 / 横向位置（不受当前动画影响）。
local function restPoint(character,node)
    local x,y=0,0
    while node and node~=character.root and node~=character.bones.root do
        local p=character.basePos[node.name] or node.position
        x,y=x+p.x,y+p.y
        node=node.parent
    end
    return x,y
end

---@param character BlockCharacter
---@param anim {Footwork: fun(self): CombatClip|nil, number, number, integer}
---@return FootPlant|nil
function F.New(character,anim)
    local bones=character.bones
    for _,leg in ipairs(LEGS) do
        if not (bones[leg.hip] and bones[leg.knee] and bones[leg.ankle]) then return nil end
    end
    local self=setmetatable({},F) --[[@as FootPlant]]
    self.character,self.anim=character,anim
    self.pelvis=bones.DownBody
    self.active,self.handle,self.clip=false,0,nil
    self.drop,self.weight=0.0,0.0
    self.legs={}
    for i,def in ipairs(LEGS) do
        local hip,knee,ankle=bones[def.hip],bones[def.knee],bones[def.ankle]
        local k=character.basePos[def.knee] or knee.position
        local a=character.basePos[def.ankle] or ankle.position
        local restX,ankleY=restPoint(character,ankle)
        self.legs[i]={def=def,hip=hip,knee=knee,ankle=ankle,
            upper=length(k.x,k.y,k.z),lower=length(a.x,a.y,a.z),
            kx=k.x,ky=k.y,kz=k.z,ax=a.x,ay=a.y,az=a.z,ankleY=ankleY,restX=restX,settling=false,gx=0.0,gz=0.0,limit=0.0,
            x=0.0,y=0.0,z=0.0,yaw=0.0,pitch=0.0,
            swing=false,fx=0.0,fy=0.0,fz=0.0,fyaw=0.0,cursor=1,steps={},heel=0.0}
    end
    return self
end

-- 身体坐标系：模型根节点的世界位置与朝向（含台阶平滑的下沉）。
function F:Frame()
    local root=self.character.root
    local p=root.worldPosition
    local f=root.worldRotation*Vector3(0,0,1)
    local yaw=math.deg(math.atan(f.x,f.z))
    self.px,self.py,self.pz,self.yaw=p.x,p.y,p.z,yaw
    local r=math.rad(yaw)
    self.cos,self.sin=math.cos(r),math.sin(r)
end

---@return number x, number z
function F:ToWorld(x,z)
    return self.px+x*self.cos+z*self.sin,self.pz-x*self.sin+z*self.cos
end

-- 新的一段：按脚分好这段的步子。上一段还在迈的脚就地落下，从那里接着走。
function F:Begin(clip,handle,fresh)
    self.clip,self.handle=clip,handle
    for _,leg in ipairs(self.legs) do
        for i=#leg.steps,1,-1 do leg.steps[i]=nil end
        for _,st in ipairs(clip.footwork.steps) do
            if st[1]==leg.def.key then leg.steps[#leg.steps+1]=st end
        end
        leg.cursor=1
        leg.settling=false
        if fresh then
            -- 从待机 / 跑动进入：脚落在当前动画里的位置，贴回地面
            local p=leg.ankle.worldPosition
            leg.x,leg.z,leg.y=p.x,p.z,self.py+leg.ankleY
            leg.yaw,leg.pitch=self.yaw,0
        elseif leg.swing then
            leg.y=self.py+leg.ankleY
            leg.pitch=0
        end
        leg.swing=false
        -- 接上一段时脚已经离胯下多远，就从这个距离起算拖拽，进招那一帧不会被拽一下
        local rx,rz=self:ToWorld(leg.restX,0)
        leg.limit=math.sqrt((leg.x-rx)^2+(leg.z-rz)^2)
    end
    print(string.format("FootPlant: %s %s steps=%d", clip.id, fresh and "from-rest" or "chained", #clip.footwork.steps))
end

-- 推进一只脚的步子：t 越过 t0 起脚，越过 t1 落地并锁住。
function F:Advance(leg,t,rise)
    while true do
        local st=leg.steps[leg.cursor]
        if not st or t<st[2] then return end
        if not leg.swing then
            leg.swing=true
            leg.fx,leg.fy,leg.fz,leg.fyaw=leg.x,leg.y,leg.z,leg.yaw
        end
        local tx,tz=self:ToWorld(st[4],st[5])
        local tyaw=self.yaw+leg.def.side*(st[7] or 0)
        local ground=self.py+leg.ankleY
        if t>=st[3] then
            leg.x,leg.y,leg.z,leg.yaw,leg.pitch=tx,ground,tz,tyaw,0
            leg.swing=false
            leg.cursor=leg.cursor+1
        else
            local u=(t-st[2])/(st[3]-st[2])
            local e=smooth(u)
            leg.x=leg.fx+(tx-leg.fx)*e
            leg.z=leg.fz+(tz-leg.fz)*e
            leg.y=leg.fy+(ground-leg.fy)*e+(st[6] or .08)*math.sin(math.pi*u)+(st[8] and rise or 0)
            leg.yaw=leg.fyaw+wrap(tyaw-leg.fyaw)*e
            -- 蹬离地面时脚尖下压，快落地时放平
            leg.pitch=TOE_PITCH*math.sin(math.pi*math.min(1,u*1.4))
            return
        end
    end
end

-- 支撑脚：不抬脚。原地生根，只有身体被突进带得太远时才贴着地面被拖过去；
-- 收招窗口里贴地滑回胯下。
function F:Support(leg,t,support)
    if leg.swing or leg.def.key~=support.foot then return end
    local rx,rz=self:ToWorld(leg.restX,0)
    local settle=support.settle
    if settle and t>=settle[1] then
        if not leg.settling then leg.settling,leg.gx,leg.gz=true,leg.x,leg.z end
        local e=smooth(clamp((t-settle[1])/(settle[2]-settle[1]),0,1))
        leg.x,leg.z=leg.gx+(rx-leg.gx)*e,leg.gz+(rz-leg.gz)*e
        leg.yaw=leg.yaw+wrap(self.yaw-leg.yaw)*e
        return
    end
    local dx,dz=leg.x-rx,leg.z-rz
    local d=math.sqrt(dx*dx+dz*dz)
    local drag=math.max(support.drag or .3,leg.limit)
    if d>drag then leg.x,leg.z=rx+dx*drag/d,rz+dz*drag/d end
    -- 身体追上来以后，拖拽上限跟着收紧，不会再被往回拽
    leg.limit=math.min(leg.limit,math.max(d,support.drag or .3))
end

local function sample(keys,t)
    if not keys or #keys==0 then return 0 end
    if t<=keys[1][1] then return keys[1][2] end
    for i=2,#keys do
        local b=keys[i]
        if t<b[1] then
            local a=keys[i-1]
            return a[2]+(b[2]-a[2])*smooth((t-a[1])/(b[1]-a[1]))
        end
    end
    return keys[#keys][2]
end

-- 胯到脚够不着时，整个人要往下沉多少。
function F:Drop()
    local need=0
    for _,leg in ipairs(self.legs) do
        local h=leg.hip.worldPosition
        local reach=(leg.upper+leg.lower)*REACH
        local dx,dz=leg.x-h.x,leg.z-h.z
        local flat=dx*dx+dz*dz
        if flat<reach*reach then
            need=math.max(need,(h.y-leg.y)-math.sqrt(reach*reach-flat))
        else need=MAX_DROP end
    end
    return clamp(need,0,MAX_DROP)
end

-- 两段腿：先由余弦定理放膝盖（朝脚尖方向弯），再把大腿、小腿、脚掌转到位。
function F:Solve(leg,w)
    local h=leg.hip.worldPosition
    local a,b=leg.upper,leg.lower
    local reach=(a+b)*REACH
    -- 弓步沉到底还够不着：后脚跟抬起，脚尖钉在原地
    local fx,fz=leg.x-h.x,leg.z-h.z
    local flat=fx*fx+fz*fz
    local low=flat<reach*reach and h.y-math.sqrt(reach*reach-flat) or h.y
    leg.heel=clamp(low-leg.y,0,HEEL)
    local pitch=leg.pitch+math.deg(math.asin(clamp(leg.heel/TOE,0,1)))
    local dx,dy,dz=fx,leg.y+leg.heel-h.y,fz
    local d=length(dx,dy,dz)
    if d>reach then dx,dy,dz,d=dx*reach/d,dy*reach/d,dz*reach/d,reach end
    d=math.max(d,math.abs(a-b)+1e-3)
    local nx,ny,nz=dx/d,dy/d,dz/d
    local r=math.rad(leg.yaw)
    local px,py,pz=math.sin(r),0,math.cos(r)
    local s=px*nx+py*ny+pz*nz
    px,py,pz=px-nx*s,py-ny*s,pz-nz*s
    local pl=length(px,py,pz)
    if pl<1e-6 then px,py,pz,pl=0,1,0,1 end
    px,py,pz=px/pl,py/pl,pz/pl
    local c=clamp((a*a+d*d-b*b)/(2*a*d),-1,1)
    local sn=math.sqrt(1-c*c)
    local kx,ky,kz=h.x+(nx*c+px*sn)*a,h.y+(ny*c+py*sn)*a,h.z+(nz*c+pz*sn)*a
    -- 大腿
    local wx,wy,wz=basis(kx-h.x,ky-h.y,kz-h.z,px,py,pz)
    local lx,ly,lz=basis(leg.kx,leg.ky,leg.kz,0,0,1)
    local thigh=fromBases(wx,wy,wz,lx,ly,lz)
    -- 小腿
    local ay=h.y+dy
    wx,wy,wz=basis(h.x+dx-kx,ay-ky,h.z+dz-kz,px,py,pz)
    lx,ly,lz=basis(leg.ax,leg.ay,leg.az,0,0,1)
    local shin=fromBases(wx,wy,wz,lx,ly,lz)
    -- 脚掌：平贴地面，朝自己的落脚朝向
    local foot=Quaternion(pitch,leg.yaw,0)
    local parent=leg.hip.parent.worldRotation
    local hip,knee,ankle=leg.hip,leg.knee,leg.ankle
    hip.rotation=hip.rotation:Slerp(inverse(parent)*thigh,w)
    knee.rotation=knee.rotation:Slerp(inverse(thigh)*shin,w)
    ankle.rotation=ankle.rotation:Slerp(inverse(shin)*foot,w)
end

---Call right after CombatAnim:Apply, before cloth / weapon visuals read the pose.
---@param dt number
function F:Apply(dt)
    local clip,t,w,handle=self.anim:Footwork()
    self.weight=w
    if not clip then self.active=false;self.drop=0;return end
    self:Frame()
    if not self.active then self:Begin(clip,handle,true);self.active=true
    elseif handle~=self.handle then self:Begin(clip,handle,false) end
    local root=self.character.bones.root
    local base=self.character.basePos.root --[[@as Vector3|nil]]
    local rise=math.max(0,root.position.y-(base and base.y or 0))
    local support=clip.footwork.support
    for _,leg in ipairs(self.legs) do
        self:Advance(leg,t,rise)
        if support then self:Support(leg,t,support) end
    end
    -- 胯：跟着躯干转一半，脚才有转身的理由
    if self.pelvis then
        self.pelvis.rotation=self.pelvis.rotation*Quaternion(0,sample(clip.footwork.hips,t)*w,0)
    end
    self.drop=self:Drop()
    if self.drop>0 then
        local p=root.position
        root.position=Vector3(p.x,p.y-self.drop*w,p.z)
    end
    for _,leg in ipairs(self.legs) do self:Solve(leg,w) end
end

---@return table[] legs
function F:Debug() return self.legs end

return F
