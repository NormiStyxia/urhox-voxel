-- 剑攻击体素特效：全部由 3D 小方块组成，按固定节拍阶梯跳变，没有随机飞散。
--   * 刀光：剑刃扫过的曲面栅格化进世界体素网格，经过哪格亮哪格；外缘白、向内渐蓝，
--     内侧先灭、外缘后灭，月牙从尾到头逐级收掉
--   * 命中：沿挥砍方向延伸的切痕 + 三个正交菱形环逐层外扩
--   * 终结技：贴地方柱组成的波前向前推进
--   * 蓄力：方环沿剑身逐级收拢；蓄满时方环沿剑身依次外放
---@class SwordVfxStep
---@field t number 该档开始时间（秒）；最后一项只有 t，表示结束
---@field s number|nil 相对尺寸
---@field c integer|nil 调色板下标
---@field h number|nil 高度倍率（贴地方柱）
---@field o number|nil 沿自身方向偏移的格数

---@class SwordVfxCube
---@field node Node
---@field model StaticModel

---@class SwordVfxItem
---@field tag string
---@field steps SwordVfxStep[]
---@field age number
---@field stage integer
---@field cube SwordVfxCube|nil
---@field px number
---@field py number
---@field pz number
---@field dx number
---@field dy number
---@field dz number
---@field size number
---@field height number
---@field ground boolean
---@field live boolean

---@class SwordVfxPool
---@field free SwordVfxCube[]
---@field items SwordVfxItem[]
---@field spare SwordVfxItem[]
---@field fresh SwordVfxItem[]
---@field colors Color[]
local Pool={};Pool.__index=Pool

---@class SwordVfx
---@field root Node
---@field bladeNode Node
---@field world SwordVfxPool
---@field blade SwordVfxPool
---@field material Material
---@field cells table<number, boolean>
local V={};V.__index=V

V.WORLD_CUBES=640
V.BLADE_CUBES=48
local PITCH=.09       -- 刀光 / 命中的体素边长（米）
local GROUND_PITCH=.18
local FILL=.9         -- 方块占格比例，留一条缝让网格读得出来
local WHITE,ICE,BLUE,DEEP=1,2,3,4

-- 刀光每一行（1 = 最外缘）的时间线。内侧行寿命更短，月牙因此从内向外收；
-- 方块只收一档就整块熄灭，不会缩成散点。
---@type SwordVfxStep[][]
local ARC_ROWS={
    {{t=0,s=1,c=WHITE},{t=.07,s=1,c=ICE},{t=.16,s=.72,c=ICE},{t=.22}},
    {{t=0,s=1,c=WHITE},{t=.04,s=1,c=ICE},{t=.11,s=1,c=BLUE},{t=.16,s=.72,c=BLUE},{t=.20}},
    {{t=0,s=1,c=WHITE},{t=.03,s=1,c=BLUE},{t=.11,s=.72,c=BLUE},{t=.15}},
    {{t=0,s=1,c=ICE},{t=.03,s=1,c=BLUE},{t=.08,s=1,c=DEEP},{t=.11,s=.72,c=DEEP},{t=.14}},
    {{t=0,s=1,c=ICE},{t=.03,s=1,c=DEEP},{t=.08,s=.72,c=DEEP},{t=.11}},
    {{t=0,s=1,c=BLUE},{t=.03,s=1,c=DEEP},{t=.06,s=.72,c=DEEP},{t=.09}},
    {{t=0,s=1,c=DEEP},{t=.04,s=.72,c=DEEP},{t=.07}},
}
-- rib：最外面几行沿挥砍面法线加厚成三层。镜头常常贴着挥砍面看，单层会退化成一条线。
---@type table<string, {rows: integer, reach: number, rib: integer}>
local STYLES={
    light={rows=5,reach=1,rib=1},
    heavy={rows=6,reach=1.5,rib=2},
    moon={rows=7,reach=2,rib=2},
    cross={rows=6,reach=1.5,rib=2},
}
---@type SwordVfxStep[]
local HIT_CORE={{t=0,s=2.4,c=WHITE},{t=.05,s=1.6,c=ICE},{t=.09}}
---@type SwordVfxStep[]
local HIT_CUT={{t=0,s=1,c=WHITE},{t=.06,s=1,c=ICE},{t=.11,s=.72,c=BLUE},{t=.15}}
---@type SwordVfxStep[]
local HIT_RING={{t=0,s=1,c=WHITE},{t=.045,s=1,c=ICE},{t=.09,s=.72,c=BLUE},{t=.13}}
---@type SwordVfxStep[]
local WAVE={{t=0,s=1,c=WHITE,h=1},{t=.05,s=1,c=ICE,h=.62},{t=.10,s=.8,c=BLUE,h=.3},{t=.15,s=.6,c=DEEP,h=.14},{t=.19}}
---@type SwordVfxStep[]
local CHARGE_RING={{t=0,s=.6,c=DEEP,o=4},{t=.07,s=.75,c=BLUE,o=3},{t=.14,s=.9,c=ICE,o=2},{t=.21,s=1,c=WHITE,o=1},{t=.27}}
---@type SwordVfxStep[]
local CHARGE_BURST={{t=0,s=1,c=WHITE,o=1},{t=.05,s=1,c=ICE,o=2},{t=.10,s=.8,c=BLUE,o=3},{t=.15,s=.6,c=DEEP,o=4},{t=.20}}

-- 三个正交菱形环：半径 r 的格点中至少一个坐标为 0 的那些。
---@type integer[][][]
local DIAMONDS={}
for r=1,3 do
    ---@type integer[][]
    local list={}
    for x=-r,r do for y=-r,r do for z=-r,r do
        if math.abs(x)+math.abs(y)+math.abs(z)==r and (x==0 or y==0 or z==0) then list[#list+1]={x,y,z} end
    end end end
    DIAMONDS[r]=list
end
-- 贴地波前：只取奇数半径的圆环，保持环与环之间留空。
local WAVE_RINGS=11
---@type integer[][]
local WAVE_CELLS={}
for x=-WAVE_RINGS,WAVE_RINGS do for z=-WAVE_RINGS,WAVE_RINGS do
    local d=math.floor(math.sqrt(x*x+z*z)+.5)
    if d>=1 and d<=WAVE_RINGS and d%2==1 then WAVE_CELLS[#WAVE_CELLS+1]={x,z,d} end
end end
-- 蓄力方环：3×3 去掉中心。
---@type integer[][]
local SQUARE={{-1,-1},{0,-1},{1,-1},{-1,0},{1,0},{-1,1},{0,1},{1,1}}

---@param parent Node
---@param name string
---@param count integer
---@param material Material
---@param colors Color[]
---@return SwordVfxPool
local function NewPool(parent,name,count,material,colors)
    local self=setmetatable({free={},items={},spare={},fresh={},colors=colors},Pool)
    local model=cache:GetResource('Model','Models/Box.mdl')
    for i=1,count do
        local node=parent:CreateChild(name..i)
        node.temporary=true
        local sm=node:CreateComponent('StaticModel') --[[@as StaticModel]]
        sm:SetModel(model);sm:SetMaterial(material)
        sm.castShadows=false
        sm.instanceColor=colors[WHITE]
        node.enabled=false
        self.free[i]={node=node,model=sm}
    end
    return self
end

---@param tag string
---@param steps SwordVfxStep[]
---@param delay number
---@param size number
---@return SwordVfxItem
function Pool:Add(tag,steps,delay,px,py,pz,size)
    local item=table.remove(self.spare)
    if item==nil then
        item={tag=tag,steps=steps,age=0.0,stage=0,px=0.0,py=0.0,pz=0.0,dx=0.0,dy=0.0,dz=0.0,size=0.0,height=1.0,ground=false,live=true}
    end
    item.tag,item.steps,item.age,item.stage,item.cube=tag,steps,-delay,0,nil
    item.px,item.py,item.pz,item.size=px,py,pz,size
    item.dx,item.dy,item.dz,item.height,item.ground,item.live=0.0,0.0,0.0,1.0,false,true
    self.items[#self.items+1]=item
    self.fresh[#self.fresh+1]=item
    return item
end

---@param item SwordVfxItem
---@param stage integer
---@return boolean shown false when the pool has no cube left
function Pool:Show(item,stage)
    local cube=item.cube
    if cube==nil then
        cube=table.remove(self.free)
        if cube==nil then return false end
        item.cube=cube
    end
    item.stage=stage
    local step=item.steps[stage]
    local s=item.size*(step.s or 1)
    local sy=s*(step.h or 1)*item.height
    local o=step.o or 0
    cube.node.position=Vector3(item.px+item.dx*o,item.py+item.dy*o+(item.ground and sy*.5 or 0),item.pz+item.dz*o)
    cube.node.scale=Vector3(s,sy,s)
    cube.model.instanceColor=self.colors[step.c or WHITE]
    cube.node.enabled=true
    return true
end

--- 把本帧刚加入、没有延迟的方块立刻显示出来，不等下一次 Update。
function Pool:Present()
    local fresh=self.fresh
    for i=1,#fresh do
        local item=fresh[i]
        if item.live and item.stage==0 and item.age>=0 then self:Show(item,1) end
        fresh[i]=nil
    end
end

---@param item SwordVfxItem
function Pool:Release(item)
    local cube=item.cube
    if cube then
        cube.node.enabled=false
        self.free[#self.free+1]=cube
        item.cube=nil
    end
    item.live=false
    self.spare[#self.spare+1]=item
end

---@param dt number
function Pool:Update(dt)
    local items=self.items
    local count=#items
    if count==0 then return end
    local fresh=self.fresh
    for i=#fresh,1,-1 do fresh[i]=nil end
    local kept=0
    for i=1,count do
        local item=items[i]
        item.age=item.age+dt
        local steps=item.steps
        local last=#steps
        local stage=item.stage
        while stage<last and item.age>=steps[stage+1].t do stage=stage+1 end
        local alive=stage<last
        if alive and stage~=item.stage then alive=self:Show(item,stage) end
        if alive then kept=kept+1;items[kept]=item
        else self:Release(item) end
    end
    for i=kept+1,count do items[i]=nil end
end

---@param tag string|nil nil 清掉全部
function Pool:Clear(tag)
    local items=self.items
    local count=#items
    local kept=0
    for i=1,count do
        local item=items[i]
        if tag==nil or item.tag==tag then self:Release(item)
        else kept=kept+1;items[kept]=item end
    end
    for i=kept+1,count do items[i]=nil end
end

---@param tag string|nil
---@return integer
function Pool:Count(tag)
    if tag==nil then return #self.items end
    local n=0
    for _,item in ipairs(self.items) do if item.tag==tag then n=n+1 end end
    return n
end

local function Snap(x) return math.floor(x/PITCH+.5) end
local function Key(cx,cy,cz) return ((cx+32768)*65536+(cy+32768))*65536+(cz+32768) end

---@param scene Node
---@return SwordVfx
function V.New(scene)
    local self=setmetatable({},V)
    local material=Material:new()
    assert(material:SetSurfaceShader('Shaders/BLGL/SwordVoxel.shader'),'SwordVoxel.shader unavailable')
    local ok,lowFx=pcall(function()
        local platform=require('urhox-libs.Platform.PlatformUtils')
        return platform.IsWebPlatform() or platform.IsMobilePlatform()
    end)
    lowFx=ok and lowFx==true
    -- 移动端 / Web 的泛光没有色调映射兜底，发光倍数压低。
    material:SetShaderParameter('glow',Variant(lowFx and 1.5 or 2.4))
    self.material=material
    -- rgb 线性色，a 发光量：白 → 冰蓝 → 蓝 → 深蓝。
    local colors={Color(1,1,1,1),Color(.50,.80,1,.6),Color(.10,.38,1,.35),Color(.03,.13,.62,.12)}
    self.root=scene:CreateChild('SwordVfx');self.root.temporary=true
    self.bladeNode=self.root:CreateChild('SwordVfxBlade');self.bladeNode.temporary=true
    self.world=NewPool(self.root,'Cube',V.WORLD_CUBES,material,colors)
    self.blade=NewPool(self.bladeNode,'Cube',V.BLADE_CUBES,material,colors)
    self.cells={}
    self.style=STYLES.light
    self.stroke,self.has=false,false
    self.travel=0.0
    self.lrx,self.lry,self.lrz,self.ldx,self.ldy,self.ldz,self.llen=0.0,0.0,0.0,0.0,1.0,0.0,0.0
    self.tx,self.ty,self.tz=0.0,0.0,0.0
    self.chargeClock,self.bladeRotation=0.0,Quaternion()
    return self
end

--- 开始一次挥砍：新的一笔，已亮过的格子记录清零（上一刀的残块按自己的时间线走完）。
---@param kind string light | heavy | moon | cross
function V:Begin(kind)
    self.style=STYLES[kind] or STYLES.light
    self.kind=kind
    self.cells={}
    self.stroke,self.has=true,false
    self.travel=0.0
    self.blade:Clear('charge')
end

function V:End()
    self.stroke,self.has=false,false
end

-- 一条剑刃采样：从外缘向内逐格点亮尚未亮过的世界格子。n 是挥砍面法线（起手第一条没有，传 0）。
function V:Column(rx,ry,rz,dx,dy,dz,len,nx,ny,nz)
    local style=self.style
    -- 起手处月牙由窄变宽
    local rows=math.min(style.rows,1+math.floor(self.travel/(PITCH*1.5)))
    -- 方块快用完时先保外缘，内侧行让位
    rows=math.min(rows,1+#self.world.free//40)
    local outer=len+style.reach*PITCH
    local cells,world=self.cells,self.world
    local q=0.0
    while true do
        local row=math.floor(q/PITCH)
        if row>=rows then break end
        local d=outer-q
        local cx,cy,cz=Snap(rx+dx*d),Snap(ry+dy*d),Snap(rz+dz*d)
        local key=Key(cx,cy,cz)
        if not cells[key] then
            cells[key]=true
            world:Add('arc',ARC_ROWS[math.min(#ARC_ROWS,row+1)] or ARC_ROWS[1],0,cx*PITCH,cy*PITCH,cz*PITCH,PITCH*FILL)
        end
        if row<style.rib and nx*nx+ny*ny+nz*nz>.5 then
            -- 两侧的肋比中线暗一档、早灭一档，白热的棱线始终在正中
            local side=ARC_ROWS[math.min(#ARC_ROWS,row+2)] or ARC_ROWS[1]
            for sign=-1,1,2 do
                local o=PITCH*sign
                local sx,sy,sz=Snap(rx+dx*d+nx*o),Snap(ry+dy*d+ny*o),Snap(rz+dz*d+nz*o)
                local sideKey=Key(sx,sy,sz)
                if not cells[sideKey] then
                    cells[sideKey]=true
                    world:Add('arc',side,0,sx*PITCH,sy*PITCH,sz*PITCH,PITCH*FILL)
                end
            end
        end
        q=q+PITCH*.6
    end
end

--- 每帧送入剑刃根部 / 尖端的世界坐标；两帧之间按半格步长补采样，挥得再快也不漏格。
---@param root Vector3
---@param tip Vector3
function V:Sample(root,tip)
    if not self.stroke then return end
    local rx,ry,rz=root.x,root.y,root.z
    local dx,dy,dz=tip.x-rx,tip.y-ry,tip.z-rz
    local len=math.sqrt(dx*dx+dy*dy+dz*dz)
    if len<1e-4 then return end
    dx,dy,dz=dx/len,dy/len,dz/len
    if self.has then
        local ox,oy,oz=self.lrx+self.ldx*self.llen,self.lry+self.ldy*self.llen,self.lrz+self.ldz*self.llen
        local mx,my,mz=tip.x-ox,tip.y-oy,tip.z-oz
        local moved=math.sqrt(mx*mx+my*my+mz*mz)
        if moved>2.5 or self.ldx*dx+self.ldy*dy+self.ldz*dz<-.2 then
            -- 瞬移或剑刃近乎反向：不跨越连接，当作新的一笔起点
            self:Column(rx,ry,rz,dx,dy,dz,len,0,0,0)
        elseif moved>1e-4 then
            local tx,ty,tz=mx/moved,my/moved,mz/moved
            self.tx,self.ty,self.tz=tx,ty,tz
            local nx,ny,nz=dy*tz-dz*ty,dz*tx-dx*tz,dx*ty-dy*tx
            local nl=math.sqrt(nx*nx+ny*ny+nz*nz)
            if nl>1e-3 then nx,ny,nz=nx/nl,ny/nl,nz/nl else nx,ny,nz=0,0,0 end
            local n=math.min(40,math.max(1,math.ceil(moved/(PITCH*.5))))
            for i=1,n do
                local u=i/n
                local ix,iy,iz=self.ldx+(dx-self.ldx)*u,self.ldy+(dy-self.ldy)*u,self.ldz+(dz-self.ldz)*u
                local il=math.sqrt(ix*ix+iy*iy+iz*iz)
                if il>1e-5 then
                    self.travel=self.travel+moved/n
                    self:Column(self.lrx+(rx-self.lrx)*u,self.lry+(ry-self.lry)*u,self.lrz+(rz-self.lrz)*u,
                        ix/il,iy/il,iz/il,self.llen+(len-self.llen)*u,nx,ny,nz)
                end
            end
        end
    else
        self:Column(rx,ry,rz,dx,dy,dz,len,0,0,0)
    end
    self.lrx,self.lry,self.lrz,self.ldx,self.ldy,self.ldz,self.llen=rx,ry,rz,dx,dy,dz,len
    self.has=true
    self.world:Present()
end

--- 命中：切痕沿最近一次挥砍方向从命中点向两端延伸，菱形环逐层外扩。
---@param pos Vector3|nil
---@param strong boolean|nil
function V:Contact(pos,strong)
    if not pos then return end
    local world=self.world
    local cx,cy,cz=Snap(pos.x),Snap(pos.y),Snap(pos.z)
    local x,y,z=cx*PITCH,cy*PITCH,cz*PITCH
    world:Add('hit',HIT_CORE,0,x,y,z,PITCH*FILL)
    local tx,ty,tz=self.tx,self.ty,self.tz
    if tx*tx+ty*ty+tz*tz>.5 then
        local half=strong and 8 or 5
        local lastKey=Key(cx,cy,cz)
        for sign=-1,1,2 do
            for i=1,half do
                local d=i*PITCH*sign
                local ax,ay,az=Snap(pos.x+tx*d),Snap(pos.y+ty*d),Snap(pos.z+tz*d)
                local key=Key(ax,ay,az)
                if key~=lastKey then
                    lastKey=key
                    world:Add('hit',HIT_CUT,i*.012,ax*PITCH,ay*PITCH,az*PITCH,PITCH*FILL)
                end
            end
            lastKey=Key(cx,cy,cz)
        end
    end
    for r=1,strong and 3 or 2 do
        local ring=DIAMONDS[r] or {}
        for _,cell in ipairs(ring) do
            world:Add('hit',HIT_RING,.03+(r-1)*.045,x+cell[1]*PITCH,y+cell[2]*PITCH,z+cell[3]*PITCH,PITCH*FILL*.8)
        end
    end
    world:Present()
end

--- 终结技落地：以前方落点为圆心，方柱波前只向前半边推进，越远越矮。
---@param pos Vector3 脚下地面点
---@param forward Vector3
function V:GroundWave(pos,forward)
    local fx,fz=forward and forward.x or 0,forward and forward.z or 1
    local l=math.sqrt(fx*fx+fz*fz)
    if l<1e-4 then fx,fz,l=0,1,1 end
    fx,fz=fx/l,fz/l
    local g=GROUND_PITCH
    local cx=math.floor((pos.x+fx*.65)/g+.5)*g
    local cz=math.floor((pos.z+fz*.65)/g+.5)*g
    local world=self.world
    for _,cell in ipairs(WAVE_CELLS) do
        local x,z,d=cell[1],cell[2],cell[3]
        if (x*fx+z*fz)/d>-.3 then
            local item=world:Add('wave',WAVE,(d-1)*.026,cx+x*g,pos.y,cz+z*g,g*FILL)
            item.ground=true
            item.height=1+3.2*(1-d/WAVE_RINGS)
        end
    end
    world:Present()
end

---@param root Vector3
---@param tip Vector3
---@return number length
function V:PlaceBlade(root,tip)
    local delta=tip-root
    local len=delta:Length()
    if len<1e-4 then return 0 end
    self.bladeRotation:FromRotationTo(Vector3.UP,delta*(1/len))
    self.bladeNode.position=root
    self.bladeNode.rotation=self.bladeRotation
    return len
end

local function Ring(self,steps,delay,height)
    for _,cell in ipairs(SQUARE) do
        local item=self.blade:Add('charge',steps,delay,0,height,0,PITCH*.62)
        item.dx,item.dz=cell[1]*PITCH*.62,cell[2]*PITCH*.62
    end
    self.blade:Present()
end

--- 蓄力中每帧调用：方环在剑身上按蓄力进度的高度处逐级收拢。
---@param dt number
---@param charge number 0..1
function V:Charge(root,tip,charge,dt)
    local len=self:PlaceBlade(root,tip)
    if len<=0 then return end
    self.chargeClock=self.chargeClock-dt
    if self.chargeClock>0 then return end
    self.chargeClock=.14
    Ring(self,CHARGE_RING,0,len*(.12+.8*math.max(0,math.min(1,charge))))
end

--- 蓄满：四道方环从剑根到剑尖依次外放。
function V:ChargeBurst(root,tip)
    local len=self:PlaceBlade(root,tip)
    if len<=0 then return end
    self.blade:Clear('charge')
    for i=0,3 do Ring(self,CHARGE_BURST,i*.035,len*(.1+.28*i)) end
end

---@param dt number
function V:Update(dt)
    self.world:Update(dt)
    self.blade:Update(dt)
end

--- 只清刀光与蓄力，命中和落地波前照常播完。
function V:ClearSword()
    self:End()
    self.world:Clear('arc')
    self.blade:Clear('charge')
end

function V:Clear()
    self:End()
    self.world:Clear(nil)
    self.blade:Clear(nil)
end

function V:Dispose()
    self.root:Remove()
end

return V
