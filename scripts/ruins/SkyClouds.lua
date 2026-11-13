-- 闭合的融合球云网格：六种云形分帧烘焙，近中景/地平线/岛下各一批，运行期只移动节点。
local logOK,DebugLog = pcall(require,"ruins.DebugLog")
if not logOK then DebugLog=nil end
---@class RuinsSkyClouds
local M = {}
M.__index = M

---@class CloudBakeVertex
---@field x number
---@field y number
---@field z number
---@field nx number
---@field ny number
---@field nz number
---@field thickness number
---@field height number
---@field ao number
---@field color Color|nil 在法线烘焙阶段填入
---@field farColor Color|nil 在法线烘焙阶段填入
---@class CloudBakeShape
---@field vertices CloudBakeVertex[]
---@field indices integer[]
---@field name string|nil
---@field resolution integer|nil
---@field lobeCount integer|nil

local function Clamp01(v) return math.max(0,math.min(1,v)) end

-- 兜底/远层用闭合球面拓扑。近景由下面的三维等值场提取，不再依赖径向假设。
---@param slices integer
---@param stacks integer
---@return CloudBakeShape
local function BakeSphere(slices,stacks)
    ---@type CloudBakeVertex[]
    local vertices={}
    ---@type integer[]
    local indices={}
    local function Vertex(dx,dy,dz)
        vertices[#vertices+1]={x=dx,y=dy,z=dz,nx=0,ny=0,nz=0,thickness=0,height=0,ao=0}
        if #vertices%32==0 then coroutine.yield() end
    end
    Vertex(0,1,0)
    for lat=1,stacks-1 do
        local a=math.pi*lat/stacks
        for lon=1,slices do
            local b=2*math.pi*(lon-1)/slices
            Vertex(math.sin(a)*math.cos(b),math.cos(a),math.sin(a)*math.sin(b))
        end
    end
    Vertex(0,-1,0)
    local function Ring(lat,lon) return 2+(lat-1)*slices+(lon-1)%slices end
    local function Triangle(ia,ib,ic)
        local a,b,c=vertices[ia],vertices[ib],vertices[ic]
        local ux,uy,uz=b.x-a.x,b.y-a.y,b.z-a.z
        local vx,vy,vz=c.x-a.x,c.y-a.y,c.z-a.z
        local nx,ny,nz=uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx
        assert(nx*nx+ny*ny+nz*nz>1e-14,'degenerate cloud face')
        if nx*a.x+ny*a.y+nz*a.z<0 then ib,ic=ic,ib;nx,ny,nz=-nx,-ny,-nz end
        indices[#indices+1]=ia;indices[#indices+1]=ib;indices[#indices+1]=ic
        for _,v in ipairs({a,b,c}) do v.nx,v.ny,v.nz=v.nx+nx,v.ny+ny,v.nz+nz end
        if #indices%540==0 then coroutine.yield() end
    end
    for lon=1,slices do Triangle(1,Ring(1,lon),Ring(1,lon+1)) end
    for lat=1,stacks-2 do
        for lon=1,slices do
            Triangle(Ring(lat,lon),Ring(lat,lon+1),Ring(lat+1,lon+1))
            Triangle(Ring(lat,lon),Ring(lat+1,lon+1),Ring(lat+1,lon))
        end
    end
    for lon=1,slices do Triangle(#vertices,Ring(stacks-1,lon+1),Ring(stacks-1,lon)) end
    for index,v in ipairs(vertices) do
        local n=math.sqrt(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz)
        v.nx,v.ny,v.nz=v.nx/n,v.ny/n,v.nz/n
        v.height=Clamp01((v.y+1)*.5)
        v.thickness=Clamp01(.15+.85*math.sqrt(math.max(0,1-(v.x*v.x+v.z*v.z)/2.7)))
        v.ao=Clamp01(.78+.18*v.height+.04*math.max(v.ny,0)) -- 烘焙的近似遮蔽，不是运行时光线追踪
        v.color=Color(v.thickness,v.height,v.ao,1)
        v.farColor=Color(v.thickness,v.height,v.ao,0)
        if index%32==0 then coroutine.yield() end
    end
    coroutine.yield()
    return {vertices=vertices,indices=indices}
end

-- 六套有明确主团/中团/小团的椭球配方；参数是中心xyz、半轴xyz（局部米）。
-- 不要求各团包含原点，不做平面裁切，保留凹谷、砧顶悬挑和圆收的底缘。
local CLOUD_LOBES={
    { -- 高耸塔状
        {0,0,0,.77,.44,.66},{-.12,.65,0,.87,.90,.72},
        {.08,1.42,-.08,.66,.70,.61},{-.30,2.02,.06,.47,.50,.44},
        {-.68,.78,.16,.48,.54,.46},{.61,.56,.20,.50,.54,.46},
        {-.36,1.55,.43,.38,.44,.37},{.53,1.95,-.22,.41,.44,.39},
        {.26,1.00,.59,.44,.46,.40},{.61,1.12,-.42,.32,.37,.34},
    },
    { -- 宽长云堤
        {0,0,0,1.92,.34,.68},{-1.45,.24,.02,.76,.51,.65},
        {-.52,.36,-.13,.69,.65,.66},{.63,.18,.12,.87,.48,.65},
        {1.70,.12,-.06,.61,.36,.51},{-.95,.63,.26,.36,.35,.35},
        {.20,.55,-.40,.41,.37,.38},{1.12,.39,.42,.36,.31,.34},
    },
    { -- 三峰；前后错落保留俯视凹谷
        {0,0,0,1.56,.36,.73},{-1.05,.52,.12,.65,.76,.57},
        {.04,.73,-.22,.64,.97,.62},{1.08,.34,.15,.62,.61,.60},
        {-.84,1.05,.27,.35,.40,.37},{.23,1.35,-.11,.35,.41,.35},
        {-.41,.28,.61,.40,.43,.38},{.64,.42,-.56,.37,.48,.37},
        {1.37,.55,.31,.27,.31,.28},
    },
    { -- 砧状冠，窄腰、宽顶、不对称前伸
        {-.38,0,0,.87,.43,.69},{-.36,.60,0,.68,.84,.65},
        {-.12,1.32,0,.88,.54,.72},{.65,1.48,.06,1.01,.38,.65},
        {1.48,1.48,-.03,.50,.25,.44},{-.75,1.44,.08,.53,.46,.55},
        {-.43,1.85,.15,.37,.31,.40},{.33,1.78,-.22,.39,.27,.36},
        {-.80,.38,.38,.33,.39,.35},
    },
    { -- 低矮层积：展宽但底部不是盘子
        {0,0,0,1.53,.28,.83},{-.93,.16,.32,.73,.39,.67},
        {.26,.20,.40,.79,.38,.65},{1.16,.09,-.12,.63,.31,.64},
        {-.45,.21,-.53,.66,.38,.54},{.49,.31,-.48,.48,.35,.43},
        {-.82,.42,.18,.33,.28,.33},{.08,.48,.61,.33,.24,.30},
    },
    { -- 小碎云簇：三颗偏心主团，细小团连接
        {-.43,.04,.05,.51,.37,.43},{.20,.20,-.12,.43,.53,.42},
        {.72,-.04,.15,.40,.30,.35},{-.64,.28,.23,.26,.28,.25},
        {.12,.64,-.05,.26,.27,.24},{.43,.21,.35,.25,.29,.26},
        {-.20,-.06,.38,.29,.23,.29},
    },
}
local CLOUD_NAMES={"tower","long_bank","three_peaks","anvil","stratocumulus","fragments"}

-- 极远处不采稀疏SDF（鞍点可能产生非流形边），改用严格闭合的低频椭球包络。
-- 六套长宽高来自配方，正常等值场仅用于近中景；低云同样使用该轻量LOD。
---@return CloudBakeShape
local function BakeEnvelope(variant,stacks)
    local shape=BakeSphere(12,stacks)
    local minX,minY,minZ,maxX,maxY,maxZ=100,100,100,-100,-100,-100
    for _,b in ipairs(assert(CLOUD_LOBES[variant])) do
        minX,minY,minZ=math.min(minX,b[1]-b[4]),math.min(minY,b[2]-b[5]),math.min(minZ,b[3]-b[6])
        maxX,maxY,maxZ=math.max(maxX,b[1]+b[4]),math.max(maxY,b[2]+b[5]),math.max(maxZ,b[3]+b[6])
    end
    local sx,sy,sz=(maxX-minX)/2,(maxY-minY)/2,(maxZ-minZ)/2
    for _,v in ipairs(shape.vertices) do
        local ux,uy=v.x,v.y
        local phase=ux*7+variant*.9
        local swell=1+.22*math.cos(phase)
        local slope=-1.54*math.sin(phase)
        -- 正值形变的雅可比逆转置，低频起伏避免远层成为光滑椭圆盘。
        local nx=v.nx/sx-v.ny*uy*slope/(sx*swell)
        local ny,nz=v.ny/(sy*swell),v.nz/sz
        v.x,v.y,v.z=ux*sx+(maxX+minX)/2,uy*sy*swell+(maxY+minY)/2,v.z*sz+(maxZ+minZ)/2
        local inv=1/math.sqrt(nx*nx+ny*ny+nz*nz)
        v.nx,v.ny,v.nz=nx*inv,ny*inv,nz*inv
    end
    shape.name=CLOUD_NAMES[variant]
    return shape
end

-- 固定种子三维value noise。加入等值场相当于沿局部梯度作小幅内外位移，非逐帧噪声。
local function CloudNoise(x,y,z,seed)
    local ix,iy,iz=math.floor(x),math.floor(y),math.floor(z)
    local fx,fy,fz=x-ix,y-iy,z-iz
    fx,fy,fz=fx*fx*(3-2*fx),fy*fy*(3-2*fy),fz*fz*(3-2*fz)
    local sum=0
    for corner=1,8 do
        local bits=corner-1
        local a,b,c=bits%2,math.floor(bits/2)%2,math.floor(bits/4)
        local h=math.sin((ix+a)*127.1+(iy+b)*311.7+(iz+c)*74.7+seed*19.19)*43758.5453
        sum=sum+(h-math.floor(h))*(a==1 and fx or 1-fx)*(b==1 and fy or 1-fy)*(c==1 and fz or 1-fz)
    end
    return sum*2-1
end

-- Surface nets：每个跨越零面的网格单元一个共享顶点，跨零网格边连接四个单元。
-- 相比径向球面，允许多峰之间真正的凹谷、窄腰和悬挑。算法无每帧依赖。
---@return CloudBakeShape
local function BakeVolume(variant,resolution)
    local lobes=assert(CLOUD_LOBES[variant])
    local minX,minY,minZ,maxX,maxY,maxZ=100,100,100,-100,-100,-100
    for _,b in ipairs(lobes) do
        minX,minY,minZ=math.min(minX,b[1]-b[4]),math.min(minY,b[2]-b[5]),math.min(minZ,b[3]-b[6])
        maxX,maxY,maxZ=math.max(maxX,b[1]+b[4]),math.max(maxY,b[2]+b[5]),math.max(maxZ,b[3]+b[6])
    end
    local height=maxY-minY
    -- 一次slice最多512个场采样/单元访问。梯度/投影也经过这里，不能把重活藏在单元内。
    local work=0
    local function Slice()
        work=work+1
        if work>=512 then work=0;coroutine.yield() end
    end
    local function Field(x,y,z)
        Slice()
        local d=100
        for _,b in ipairs(lobes) do
            local px,py,pz=(x-b[1])/b[4],(y-b[2])/b[5],(z-b[3])/b[6]
            local q=(math.sqrt(px*px+py*py+pz*pz)-1)*math.min(b[4],b[5],b[6])
            local h=math.max(.24-math.abs(d-q),0)/.24
            d=math.min(d,q)-h*h*.060
        end
        return d-CloudNoise(x*1.1,y*1.1,z*1.1,variant)*.028
    end
    local function Gradient(x,y,z)
        local e=.035
        local nx,ny,nz=Field(x+e,y,z)-Field(x-e,y,z),Field(x,y+e,z)-Field(x,y-e,z),Field(x,y,z+e)-Field(x,y,z-e)
        local inv=1/math.max(1e-12,math.sqrt(nx*nx+ny*ny+nz*nz))
        return nx*inv,ny*inv,nz*inv,1/(inv*2*e)
    end
    local pad=.28
    minX,minY,minZ,maxX,maxY,maxZ=minX-pad,minY-pad,minZ-pad,maxX+pad,maxY+pad,maxZ+pad
    -- 各方向接近等距采样，扁云不再把预算浪费在高度，塔云不再纵向缺细节。
    local longest=math.max(maxX-minX,maxY-minY,maxZ-minZ)
    local nx=math.max(3,math.floor(resolution*(maxX-minX)/longest))
    local ny=math.max(3,math.floor(resolution*(maxY-minY)/longest))
    local nz=math.max(3,math.floor(resolution*(maxZ-minZ)/longest))
    local dx,dy,dz=(maxX-minX)/nx,(maxY-minY)/ny,(maxZ-minZ)/nz
    local function Key(x,y,z) return 1+x+(nx+1)*(y+(ny+1)*z) end
    local values,cells={},{}
    for z=0,nz do for y=0,ny do for x=0,nx do
        values[Key(x,y,z)]=Field(minX+x*dx,minY+y*dy,minZ+z*dz);Slice()
    end end end
    ---@type CloudBakeVertex[]
    local vertices={}
    ---@type integer[]
    local indices={}
    ---@type integer[][]
    local edges={{1,2},{3,4},{5,6},{7,8},{1,3},{2,4},{5,7},{6,8},{1,5},{2,6},{3,7},{4,8}}
    for z=0,nz-1 do for y=0,ny-1 do for x=0,nx-1 do
        local px,py,pz,count=0,0,0,0
        for _,edge in ipairs(edges) do
            local ca,cb=edge[1]-1,edge[2]-1
            local ax,ay,az=ca%2,math.floor(ca/2)%2,math.floor(ca/4)
            local bx,by,bz=cb%2,math.floor(cb/2)%2,math.floor(cb/4)
            local va,vb=values[Key(x+ax,y+ay,z+az)],values[Key(x+bx,y+by,z+bz)]
            if (va<0)~=(vb<0) then
                local t=va/(va-vb)
                px,py,pz=px+ax+t*(bx-ax),py+ay+t*(by-ay),pz+az+t*(bz-az)
                count=count+1
            end
        end
        if count>0 then
            px,py,pz=minX+(x+px/count)*dx,minY+(y+py/count)*dy,minZ+(z+pz/count)*dz
            -- 边交点平均值会向内收缩、产生方角；沿场梯度投影回零面，限在原单元内防止翻面。
            for projection=1,2 do
                local gx,gy,gz,length=Gradient(px,py,pz)
                local step=Field(px,py,pz)/math.max(length,.1)
                px=math.max(minX+(x+.001)*dx,math.min(minX+(x+.999)*dx,px-gx*step))
                py=math.max(minY+(y+.001)*dy,math.min(minY+(y+.999)*dy,py-gy*step))
                pz=math.max(minZ+(z+.001)*dz,math.min(minZ+(z+.999)*dz,pz-gz*step))
            end
            local gx,gy,gz=Gradient(px,py,pz)
            local h=Clamp01((py-minY-pad)/height)
            local thickness=Clamp01(.30+.55*(1-math.abs(gy))+.10*h)
            local ao=.84+.16*h
            vertices[#vertices+1]={x=px,y=py,z=pz,nx=gx,ny=gy,nz=gz,height=h,thickness=thickness,ao=ao,
                color=Color(thickness,h,ao,1),farColor=Color(thickness,h,ao,0)}
            cells[Key(x,y,z)]=#vertices
        end
        Slice()
    end end end
    local function Face(a,b,c,d,flip)
        assert(a and b and c and d,"open cloud surface")
        if flip then b,d=d,b end
        local function Facing(ia,ib,ic)
            local p,q,r=vertices[ia],vertices[ib],vertices[ic]
            local ux,uy,uz=q.x-p.x,q.y-p.y,q.z-p.z
            local vx,vy,vz=r.x-p.x,r.y-p.y,r.z-p.z
            return (uy*vz-uz*vy)*(p.nx+q.nx+r.nx)+(uz*vx-ux*vz)*(p.ny+q.ny+r.ny)+(ux*vy-uy*vx)*(p.nz+q.nz+r.nz)
        end
        -- 弯曲四边形选择更符合梯度的对角线，避免低分辨率凹谷跨角形成反折。
        if math.min(Facing(a,b,c),Facing(a,c,d))<math.min(Facing(a,b,d),Facing(b,c,d)) then
            indices[#indices+1]=a;indices[#indices+1]=b;indices[#indices+1]=d
            indices[#indices+1]=b;indices[#indices+1]=c;indices[#indices+1]=d
            return
        end
        indices[#indices+1]=a;indices[#indices+1]=b;indices[#indices+1]=c
        indices[#indices+1]=a;indices[#indices+1]=c;indices[#indices+1]=d
    end
    for z=0,nz-1 do for y=0,ny-1 do for x=0,nx-1 do
        local here=values[Key(x,y,z)]<0
        if y>0 and z>0 and here~=(values[Key(x+1,y,z)]<0) then
            Face(cells[Key(x,y-1,z-1)],cells[Key(x,y,z-1)],cells[Key(x,y,z)],cells[Key(x,y-1,z)],not here)
        end
        if x>0 and z>0 and here~=(values[Key(x,y+1,z)]<0) then
            Face(cells[Key(x-1,y,z-1)],cells[Key(x-1,y,z)],cells[Key(x,y,z)],cells[Key(x,y,z-1)],not here)
        end
        if x>0 and y>0 and here~=(values[Key(x,y,z+1)]<0) then
            Face(cells[Key(x-1,y-1,z)],cells[Key(x,y-1,z)],cells[Key(x,y,z)],cells[Key(x-1,y,z)],not here)
        end
        Slice()
    end end end
    coroutine.yield()
    return {vertices=vertices,indices=indices,name=CLOUD_NAMES[variant],resolution=resolution,lobeCount=#lobes}
end

---@return CloudBakeShape
local function BakeShape(variant,budget,resolution)
    -- 固定上限，最多10次降分辨率；已校准的默认配方只需一次，改配方也不能失控。
    for attempt=1,10 do
        local shape=BakeVolume(variant,resolution)
        if #shape.indices/3<=budget and #shape.indices>0 then return shape end
        resolution=math.max(3,resolution-1)
    end
    error("cloud shape exceeds bounded LOD budget")
end

---@param g CustomGeometry
---@param shape CloudBakeShape
local function Emit(g,shape,x,y,z,sx,sy,sz,yaw,far)
    local cs,sn=math.cos(yaw),math.sin(yaw)
    for i,index in ipairs(shape.indices) do
        local v=shape.vertices[index]
        local px,pz=v.x*sx,v.z*sz
        g:DefineVertex(Vector3(x+cs*px+sn*pz,y+v.y*sy,z-sn*px+cs*pz))
        -- 非均匀缩放用逆转置，再旋转；不能直接缩放法线。
        local nx,ny,nz=v.nx/sx,v.ny/sy,v.nz/sz
        local inv=1/math.sqrt(nx*nx+ny*ny+nz*nz)
        g:DefineNormal(Vector3((cs*nx+sn*nz)*inv,ny*inv,(-sn*nx+cs*nz)*inv))
        g:DefineColor(assert(far and v.farColor or v.color))
        if i%240==0 then coroutine.yield() end
    end
    coroutine.yield() -- 不把多朵云上传挤到同一帧
end

---@param scene Scene
function M.New(scene,count,upper,lower)
    local self = setmetatable({},M)
    self:Init(scene,count or 24,upper~=false,lower~=false)
    return self
end

---@param scene Scene
function M:Init(scene,count,upper,lower)
    self.budget = math.max(0,math.min(24,math.floor(count)))
    self.horizonOnly=self.budget>0 and self.budget<=4
    self.upper,self.lower,self.count,self.batchCount = upper,lower,0,0
    self.triangleCount,self.disposed,self.ready,self.baking = 0,false,false,false
    self.bakeSlices,self.shapeCount,self.readyCount = 0,0,0
    ---@type thread|nil
    self.job=nil
    ---@type table<number, CloudBakeShape>
    self.shapes={}
    ---@type Scene|nil
    self.scene=scene
    ---@type Node|nil
    self.root = nil
    ---@type Material|nil
    self.material = nil
    ---@type table<number, Node>
    self.layers = {}
    ---@type table<number, CustomGeometry>
    self.geometry = {}
    self.elapsed = 0
    self.position = Vector3.ZERO
    self.fallback,self.unavailable,self.shaderFallback = false,false,false
    if self.budget==0 or not (upper or lower) then return end
    local source = cache:GetResource("Material","Materials/RuinsCloud.xml")
    self.material = source and source:Clone() or Material:new()
    if not source and not self.material:SetSurfaceShader("Shaders/BLGL/RuinsCloud.shader") then
        local technique=cache:GetResource("Technique","Techniques/PBR/PBRNoTexture.xml")
        if not technique then
            self.unavailable=true;self.material:Dispose();self.material=nil;return
        end
        self.material:SetTechnique(0,technique)
        self.material:SetShaderParameter("Roughness",Variant(1.0))
        self.material:SetShaderParameter("MatDiffColor",Variant(Color(.55,.65,.78,1)))
        self.shaderFallback=true
        if DebugLog and DebugLog.enabled then DebugLog.Log("SkyFx","cloud shader unavailable; simple shaded spheres") end
    end
    self.root = scene:CreateChild("SkyClouds")
    self.root.enabled=false
    for layer=1,3 do
        if (layer==3 and lower) or (layer~=3 and upper) then
            self.count=self.count+math.floor(self.budget/3)+(layer<=self.budget%3 and 1 or 0)
        end
    end
    if self.horizonOnly then self.count=upper and self.budget or 0 end
    self.fallback=self.shaderFallback
    self.baking=true
    self.job=coroutine.create(function() self:Build(self.fallback) end)
end

function M:Build(simple)
    local detailBudget=850
    local resolutions={15,21,16,16,17,17}
    if self.budget>12 then detailBudget=1200;resolutions={19,25,19,19,21,21} end
    if simple then
        self.shapes[1]=BakeSphere(8,4)
        self.shapeCount=1
    elseif self.horizonOnly then
        -- 低档只生成96三角包络，不采样等值场；关闭仍不建节点/不烘焙。
        self.shapes[8]=BakeEnvelope(2,5)
        self.shapes[11]=BakeEnvelope(5,5)
        self.shapeCount=2
    else
        for variant=1,6 do
            if self.upper then
                self.shapes[variant]=BakeShape(variant,detailBudget,resolutions[variant])
                self.shapes[variant+6]=BakeEnvelope(variant,5)
            end
            if self.lower then self.shapes[variant+12]=BakeEnvelope(variant,6) end
            self.shapeCount=variant
        end
    end
    self.count=0
    for layer=1,3 do
        local amount = math.floor(self.budget/3)+(layer<=self.budget%3 and 1 or 0)
        if self.horizonOnly then amount=layer==2 and self.budget or 0 end
        if self.budget>12 then
            if layer==1 then amount=amount-2 elseif layer==2 then amount=amount+2 end
        end
        if simple then amount=math.min(2,amount) end
        if amount>0 and ((layer==3 and self.lower) or (layer~=3 and self.upper)) then
            local node=self.root:CreateChild("CloudVolume"..layer)
            local g=node:CreateComponent("CustomGeometry")
            g:BeginGeometry(0,TRIANGLE_LIST)
            self.layers[layer],self.geometry[layer]=node,g
            for i=1,amount do
                local a=(i/amount+layer*.19)*math.pi*2
                local near=layer==1 and i<=math.max(2,math.floor(amount/3))
                local radius=layer==3 and (103+i*6) or (layer==2 and (232+i%3*13) or (near and 70 or 118+i*5))
                local y=layer==3 and (-40-i*2) or (layer==2 and (48+i%3*6) or (near and 48 or 67+i%3*7))
                local sx=layer==2 and 32 or (near and 14 or 12+i%3*2)
                local sy=layer==2 and 5 or (layer==3 and 9 or (near and 16 or 12))
                local sz=layer==2 and 22 or (layer==3 and 20 or 13+i%2*3)
                local index=simple and 1 or ((i+layer)%6+1+(layer-1)*6)
                if self.horizonOnly and not simple then index=i%2==0 and 8 or 11 end
                local shape=self.shapes[index]
                Emit(g,shape,math.cos(a)*radius,y,math.sin(a)*radius,sx,sy,sz,i*1.73+layer*.8,layer~=1)
                self.triangleCount=self.triangleCount+#shape.indices/3
                self.count=self.count+1
            end
            g:Commit();g:SetMaterial(self.material)
            g.castShadows,g.occluder=false,false
            g.drawDistance=470
            self.batchCount=self.batchCount+1
            coroutine.yield() -- 每个slice最多提交一个批次
        end
    end
    self.ready,self.baking,self.readyCount=true,false,self.count
    self.root.enabled=true
end

-- 宿主每帧最多调用一次；完成后连此函数也不再调用。失败只尝试一次简单球兜底。
function M:StepBake()
    if self.disposed or not self.baking or not self.job then return end
    self.bakeSlices=self.bakeSlices+1
    local ok,err=coroutine.resume(self.job)
    if ok then
        if coroutine.status(self.job)=="dead" then self.job=nil end
        return
    end
    if self.root then self.root:Dispose() end
    self.layers,self.geometry,self.shapes={},{},{}
    self.ready,self.readyCount=false,0
    self.count,self.batchCount,self.triangleCount,self.shapeCount=0,0,0,0
    if self.fallback then
        self.baking,self.unavailable,self.job=false,true,nil
        self.root=nil
        if self.material then self.material:Dispose();self.material=nil end
        if DebugLog and DebugLog.enabled then DebugLog.Log("SkyFx","cloud fallback failed; hidden safely: %s",tostring(err)) end
        return
    end
    self.fallback=true
    self.root=self.scene:CreateChild("SkyCloudFallback");self.root.enabled=false
    self.job=coroutine.create(function() self:Build(true) end)
    if DebugLog and DebugLog.enabled then DebugLog.Log("SkyFx","cloud bake failed; retry with simple spheres: %s",tostring(err)) end
end

function M:Dispose()
    if self.disposed then return end
    self.disposed,self.baking,self.ready=true,false,false
    self.job=nil
    self.shapes={}
    self.scene=nil
    if self.root then self.root:Dispose() end
    self.layers,self.geometry = {},{}
    if self.material then self.material:Dispose() end
end

-- 宿主 5Hz 调用；只移动整批节点，不重建网格。不可见批次不写 transform。
function M:Update(dt,day,dusk,dn)
    if self.disposed or not self.material then return end
    self.elapsed = self.elapsed+dt
    for i,node in pairs(self.layers) do
        local g = self.geometry[i]
        if node.enabled and g and g.inView then
            local p = self.position
            local speed=i==1 and .012 or (i==2 and .003 or .007)
            -- 从零偏移起步，隐藏烘焙完成后首个可见帧不会突然跳到随机相位位置。
            p.x,p.z = (math.sin(self.elapsed*speed+i)-math.sin(i))*9,(math.sin(self.elapsed*speed*.65+i)-math.sin(i))*5
            node.position = p
        end
    end
    -- 转头/重新启用时也必须显示当前时段。
    self.material:SetShaderParameter("day",Variant(math.max(0,math.min(1,day))))
    self.material:SetShaderParameter("dusk",Variant(math.max(0,math.min(1,dusk))))
    if dn and dn.sky then
        self.material:SetShaderParameter("sky_top",Variant(dn.sky.skyTopColor))
        self.material:SetShaderParameter("sky_horizon",Variant(dn.sky.skyHorizonColor))
    end
    if self.shaderFallback then
        self.material:SetShaderParameter("MatDiffColor",Variant(Color(.12+day*.66,.17+day*.64,.27+day*.61,1)))
    end
end

return M
