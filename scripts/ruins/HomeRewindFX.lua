-- The physics volumes stay in place. Only their rendering crosses the moving
-- cut, so a new request can reverse the same cells without moving a collider.
local M = {}
M.__index = M
local min, max, floor = math.min, math.max, math.floor

function M.New(parent, origin, world)
    return setmetatable({parent=parent, origin=origin, world=world, changes={}}, M)
end

-- Sample actual solid columns near each face while the island is built. Roofs
-- and arched walls leave much of their brush empty, particularly at the ridge.
function M.Measure(part)
    local b=part.brush
    local w,d=b.nx*b.s,b.nz*b.s
    local count=min(16,max(4,math.ceil((w+d)*.65)))
    local anchors={}
    for i=1,count do
        local side=(i-1)%4
        local t=(floor((i-1)/4)+.5)/math.ceil((count-side)/4)
        for _,inset in ipairs({0,1,3,7}) do
            local ix,iz
            if side%2==0 then
                ix,iz=floor(t*b.nx),side==0 and inset or b.nz-1-inset
            else
                ix,iz=side==1 and b.nx-1-inset or inset,floor(t*b.nz)
            end
            if ix>=0 and ix<b.nx and iz>=0 and iz<b.nz then
                local lo,hi
                for j=0,b.ny-1 do
                    if b.grid:IsSolid(ix,j,iz) then lo=lo or j;hi=j end
                end
                if lo then
                    local x,y,z=b:Center(ix,lo,iz)
                    local nx=side==1 and 1 or (side==3 and -1 or 0)
                    local nz=side==0 and -1 or (side==2 and 1 or 0)
                    anchors[#anchors+1]={x=x+nx*(b.s*.5+.04),z=z+nz*(b.s*.5+.04),
                        low=y-b.s*.5,high=b.lmin[2]+(hi+1)*b.s,nx=nx,nz=nz}
                    break
                end
            end
        end
    end
    part.anchors=anchors
end

local function openEffects(self)
    local fx=require('dragon.VoxelFX')
    self.root=self.parent:CreateChild('HomeHouseRewindFX')
    self.dust=fx.Motes(self.root,'StoneDust',160,'cloud',false)
    self.motes=fx.Motes(self.root,'TimePixels',192,'square',true)
    self.glints=fx.Motes(self.root,'JointGlints',72,'star',true)
    self.template=Material:new()
    self.shaderReady=self.template:SetSurfaceShader('ruins/HomeRewind.shader')
    if self.shaderReady then self.template:SetSurfaceTexture('palette_tex',self.world:GetPaletteTexture()) end
    self.dustColors={Color(.74,.67,.55,.32),Color(.69,.64,.56,.49),Color(.71,.66,.59,.24),Color(.74,.71,.66,.09)}
    self.gold={Color(.74,.86,1,.48),Color(1,.94,.73,1),Color(1,.85,.53,1)}
    self.blue={Color(.96,.91,.76,1),Color(.62,.83,1,.77),Color(.50,.71,1,.32)}
    self.flash={Color(1,.99,.85,1),Color(1,.88,.61,.92),Color(.70,.87,1,.38)}
end

local function puff(self,at,nx,nz,k)
    self.dust:Spawn{pos=at,vel=Vector3(nx*(.32+k*.36),.20+k*.31,nz*(.32+k*.36)),
        drag=1.1,life=.32+.14*k,size=.14+.17*k,colors=self.dustColors}
end

local function stir(self,c)
    for i,a in ipairs(c.part.anchors or {}) do
        local k=(i*.61803)%1
        local x,z=self.origin.x+a.x,self.origin.z+a.z
        local low,high=self.origin.y+a.low+.04,self.origin.y+a.high+.04
        local at=Vector3(x,low,z)
        local life=c.span*(.73+.25*k)
        if c.part.on then
            puff(self,at,a.nx,a.nz,k)
            local start=low+(high-low)*c.from
            local spread=.36+.75*k
            self.motes:Spawn{pos=at,life=life,size=.07+.065*k,colors=self.gold,
                fn=function(p,_,u)
                    local r=(1-u)*(1-u)*spread
                    local sway=math.sin(u*5+i)*r*.32
                    p.pos=Vector3(x+a.nx*r+a.nz*sway,start+(high-start)*u,z+a.nz*r-a.nx*sway)
                end}
        else
            self.motes:Spawn{pos=Vector3(x,low+(high-low)*c.from*(.38+.62*k),z),
                life=life+.29,vel=Vector3(a.nx*(.55+k),.25+.55*k,a.nz*(.55+k)),
                drag=.65,size=.10+.05*k,colors=self.blue}
        end
    end
end

local function sparkle(self,c)
    local anchors=c.part.anchors or {}
    for i=1,#anchors,max(1,math.ceil(#anchors/3)) do
        local a=anchors[i]
        local pos=Vector3(self.origin.x+a.x,self.origin.y+a.high+.05,self.origin.z+a.z)
        self.glints:Spawn{pos=pos,life=.22,size=.23,colors=self.flash,
            fn=function(p,_,u) p.size=.29*math.sin(math.pi*u)^.6 end}
    end
end

local function releaseSkin(p)
    if p.skin then
        p.volume.material=p.originalMaterial
        p.skin:Dispose()
        p.skin,p.originalMaterial=nil,nil
    end
end

local function draw(self,c,q)
    local p=c.part
    p.reveal=q
    if q<=0 or q>=1 then
        self.show(p,q>=1)
        releaseSkin(p)
    elseif p.masonry and self.shaderReady then
        if not p.skin then
            p.originalMaterial=p.volume.material
            p.skin=self.template:Clone()
            p.volume.material=p.skin
        end
        local b=p.brush
        local span=b.s*(b.ny+.10*b.nx+.05*b.nz)+.24
        local cut=self.origin.y+b.lmin[2]-.02+q*span
        p.skin:SetShaderParameter('wave',Variant(Vector4(self.origin.x+b.lmin[1],self.origin.z+b.lmin[3],cut,p.on and 1 or 0)))
        self.show(p,true)
    else
        -- Panes and terrace shrubs follow the wave through their own height.
        self.show(p,q>=.55)
    end
end

function M:Begin(parts,ascending,show)
    self.show=show
    self.changes={}
    self.elapsed=0
    if self.root then
        self.dust:Clear()
        self.motes:Clear()
        self.glints:Clear()
    end
    if #parts==0 then
        if self.root then self.root.enabled=false end
        return
    end
    if not self.root then openEffects(self) end
    self.root.enabled=true
    local low,high=math.huge,-math.huge
    for _,p in ipairs(parts) do
        local b=p.brush
        local y=b and (b.lmin[2]+b.s*b.ny*.5) or p.anchor.y
        low,high=min(low,y),max(high,y)
        self.changes[#self.changes+1]={part=p,y=y,from=p.reveal}
    end
    for _,c in ipairs(self.changes) do
        local t=(c.y-low)/max(.01,high-low)
        if not ascending then t=1-t end
        local goal=c.part.on and 1 or 0
        -- A displaced old cap loosens before the replacement storey seals.
        c.start=c.from>0 and c.from<1 and 0 or (c.part.on and .12+.58*t or .02+.37*t)
        c.span=.65*math.abs(goal-c.from)
        c.goal=goal
    end
    self:Update(0)
end

function M:Update(dt)
    if #self.changes==0 then return end
    self.elapsed=self.elapsed+dt
    self.dust:Update(dt)
    self.motes:Update(dt)
    self.glints:Update(dt)
    for _,c in ipairs(self.changes) do
        local elapsed=self.elapsed-c.start
        if elapsed>=0 and not c.done then
            local u=min(1,elapsed/c.span)
            if not c.started then
                if u<1 then stir(self,c) end
                c.started=true
            end
            local q=u*u*(3-2*u)
            draw(self,c,u==1 and c.goal or c.from+(c.goal-c.from)*q)
            if u==1 then
                c.done=true
                if c.part.on and elapsed-c.span<.22 then sparkle(self,c) end
            end
        end
    end
    if self.elapsed>=1.65 then
        self.dust:Clear()
        self.motes:Clear()
        self.glints:Clear()
        self.changes={}
        self.root.enabled=false
    end
end

function M:Stop()
    for _,c in ipairs(self.changes) do draw(self,c,c.part.on and 1 or 0) end
    self.changes={}
    if not self.root then return end
    local materials={self.dust.bb:GetMaterial(),self.motes.bb:GetMaterial(),self.glints.bb:GetMaterial()}
    self.root:Remove()
    for _,m in ipairs(materials) do m:Dispose() end
    self.template:Dispose()
    self.root,self.dust,self.motes,self.glints,self.template=nil,nil,nil,nil,nil
end

return M
