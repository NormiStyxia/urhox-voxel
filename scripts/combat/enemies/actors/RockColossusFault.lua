-- Five independent stone extrusions, placed on permanent ground at direction lock.
-- Geometry is authored once. Red footprints and contact share the same cut corners.
local Fault={}
Fault.__index=Fault
Fault.COUNT,Fault.FIRST,Fault.GAP=5,1.08,1.15
Fault.HALF_X,Fault.HALF_Z,Fault.CHAMFER=.88,.55,.15
Fault.IMPACT,Fault.STEP,Fault.RISE,Fault.HOLD,Fault.END=.16,.15,.19,.31,.62
local W,D,C=Fault.HALF_X,Fault.HALF_Z,Fault.CHAMFER
local outline={{-W+C,-D},{W-C,-D},{W,-D+C},{W,D-C},{W-C,D},{-W+C,D},{-W,D-C},{-W,-D+C}}
Fault.Colors={{.34,.29,.26},{.56,.47,.41},{.78,.65,.51},{.42,.35,.31},{.88,.15,.12}}

function Fault.Contains(x,z)
    x,z=math.abs(x),math.abs(z)
    return x<=W and z<=D and x+z<=W+D-C
end

-- Flat bevels catch directional light. Different strata meet along dark fault seams.
function Fault.Mesh(index)
    local triangles={}
    local function triangle(slot,a,b,c) triangles[#triangles+1]={slot,a,b,c} end
    local function ring(y,width,shift,slope)
        local out={}
        for j,pt in ipairs(outline) do
            out[j]={pt[1]*width+shift, y+slope*pt[1],pt[2]*width}
        end
        return out
    end
    local base=ring(0,1,0,0)
    for j=2,7 do triangle(5,base[1],base[j+1],base[j]) end
    local side=index%2==0 and -1 or 1
    local courses={{.13,.95,0,0,1},{.20,.83,0,.045,3},{.42,.86,.04*side,.07,2},
        {.46,.74,.04*side,.07,1},{.66,.78,.06*side,.09,4},{.71,.72,.06*side,.09,3},
        {.92,.63,.11*side,.11,2},{1,.48,.14*side,.11,3}}
    local prev=base
    for _,course in ipairs(courses) do
        local top=ring(course[1],course[2],course[3],course[4]*side)
        for j=1,8 do
            local k=j%8+1
            triangle(course[5],prev[j],top[j],top[k]); triangle(course[5],prev[j],top[k],prev[k])
        end
        prev=top
    end
    for j=2,7 do triangle(3,prev[1],prev[j+1],prev[j]) end
    return triangles
end

local function material(slot,rgb)
    local m=Material:new()
    local path=slot==5 and 'Techniques/NoTextureUnlit.xml' or 'Techniques/PBR/PBRNoTexture.xml'
    m:SetTechnique(0,cache:GetResource('Technique',path))
    m:SetShaderParameter('MatDiffColor',Variant(Color(rgb[1],rgb[2],rgb[3],1)))
    if slot~=5 then
        m:SetShaderParameter('Roughness',Variant(.88));m:SetShaderParameter('Metallic',Variant(0.0))
    end
    m:SetCullMode(CULL_NONE)
    return m
end

-- Three sheets in one nearest-filter atlas: continuous ground fracture, shale and ejecta.
Fault.Atlas='Textures/fx/RockColossusFault.png'
local function inkFor(tex,i)
    if not tex or not Vector2 then return end
    local ok,ink=pcall(function()
        local art={}
        for _,kind in ipairs({'ground','wall','spray'}) do
            local mat=Material:new()
            local name=kind=='wall' and 'RockFaultStrata' or 'RockFaultInk'
            if not mat:SetSurfaceShader('Shaders/BLGL/'..name..'.shader') or not mat:SetSurfaceTexture('fault_atlas',tex) then return end
            mat:SetShaderParameter('bed',Variant(i-1))
            if kind=='spray' then mat:SetShaderParameter('plume',Variant(1.0)) end
            art[kind]=mat
        end
        return art
    end)
    return ok and ink or nil
end

-- Planar projection follows the face: cut caps use XZ, beds expose their actual vertical strata.
function Fault.UV(slot,p,nx,ny,nz)
    if slot==5 or math.abs(ny)>.86 then return p[1]/(2*W)+.5,p[3]/(2*D)+.5 end
    local u=math.abs(nx)>math.abs(nz) and p[3]/(2*D) or p[1]/(2*W)
    return u+.5,p[2]
end

local function sprayNode(n,art)
    local node=n:CreateChild('broken_shale_and_dust')
    local geom=node:CreateComponent('CustomGeometry');geom:BeginGeometry(0,TRIANGLE_LIST)
    for _,v in ipairs({{0,0},{1,0},{1,1},{0,0},{1,1},{0,1}}) do
        geom:DefineVertex(Vector3((v[1]-.5)*2,1-v[2],0));geom:DefineNormal(Vector3.FORWARD)
        geom:DefineTexCoord(Vector2(v[1],v[2]))
    end
    geom:Commit();geom:SetMaterial(art.spray);geom.castShadows=false;node.enabled=false
    return node
end

local function param(s,mat,name,value)
    value=math.floor(value*24+.5)/24
    if s[name]~=value then
        s[name]=value
        if s.ink then s.ink[mat]:SetShaderParameter(name,Variant(value)) end
    end
end

function Fault:Brush(progress)
    if not self.active then return end
    for i,s in ipairs(self.sections) do
        param(s,'ground','brush',math.max(-.1,math.min(1.6,progress*6.55-(i-1))))
    end
end

local function buildSection(root,i,mats,art)
    local n=root:CreateChild('fault_'..i)
    local rock=n:CreateChild('strata'); local marker=n:CreateChild('red_footprint')
    marker.position=Vector3(0,.045,0)
    local tris=Fault.Mesh(i)
    for slot=1,5 do
        local parent=slot==5 and marker or rock:CreateChild('bed_'..slot)
        local geom=parent:CreateComponent('CustomGeometry')
        geom.castShadows=slot~=5
        geom:BeginGeometry(0,TRIANGLE_LIST)
        for _,tri in ipairs(tris) do
            if tri[1]==slot then
                local a,b,c=Vector3(table.unpack(tri[2])),Vector3(table.unpack(tri[3])),Vector3(table.unpack(tri[4]))
                local u,v=b-a,c-a
                local nx,ny,nz=u.y*v.z-u.z*v.y,u.z*v.x-u.x*v.z,u.x*v.y-u.y*v.x
                local len=math.sqrt(nx*nx+ny*ny+nz*nz)
                local normal=Vector3(nx/len,ny/len,nz/len)
                for k=2,4 do
                    local pt=tri[k]
                    geom:DefineVertex(Vector3(table.unpack(pt)));geom:DefineNormal(normal)
                    if art then geom:DefineTexCoord(Vector2(Fault.UV(slot,pt,normal.x,normal.y,normal.z))) end
                end
            end
        end
        geom:Commit();geom:SetMaterial(art and (slot==5 and art.ground or art.wall) or mats[slot])
    end
    return n,rock,marker,art and sprayNode(n,art)
end

function Fault.New(scene)
    local f=setmetatable({sections={},active=false},Fault)
    local mats={}
    local texture
    if scene then
        local loaded,resource=pcall(cache.GetResource,cache,'Texture2D',Fault.Atlas)
        if loaded then texture=resource end
        f.root=scene:CreateChild('quarry_fault');f.root.enabled=false
        for slot,rgb in ipairs(Fault.Colors) do mats[slot]=material(slot,rgb) end
    end
    for i=1,Fault.COUNT do
        local s={distance=Fault.FIRST+(i-1)*Fault.GAP,peak=1.40+.15*i,start=Fault.IMPACT+(i-1)*Fault.STEP}
        if f.root then
            s.ink=inkFor(texture,i)
            s.node,s.rock,s.marker,s.spray=buildSection(f.root,i,mats,s.ink)
        end
        f.sections[i]=s
    end
    return f
end

function Fault:Lock(e)
    self.x,self.z,self.fx,self.fz=e.position.x,e.position.z,e.fx,e.fz
    self.active=true
    if self.root then self.root.enabled=true end
    local maxDistance=math.huge
    if e.world then
        local ray=Ray(Vector3(self.x,e.position.y+.5,self.z),Vector3(e.fx,0,e.fz))
        local hit=e.world:RaycastSingle(ray,self.sections[Fault.COUNT].distance+D)
        if hit.hit then maxDistance=hit.distance end
    end
    for _,s in ipairs(self.sections) do
        s.x,s.z=self.x+e.fx*s.distance,self.z+e.fz*s.distance
        local y=e.terrain.GroundHeight(s.x,s.z)
        local highest=y or e.position.y
        s.valid=s.distance+D<maxDistance and y~=nil and y~=e.terrain.VOID_Y
        if s.valid then
            for _,corner in ipairs(outline) do
                local cx=s.x+e.fz*corner[1]+e.fx*corner[2]
                local cz=s.z-e.fx*corner[1]+e.fz*corner[2]
                local cy=e.terrain.GroundHeight(cx,cz)
                if not cy or cy==e.terrain.VOID_Y or math.abs(cy-y)>.32 then s.valid=false;break end
                highest=math.max(highest,cy)
            end
        end
        if not s.valid then maxDistance=0 end -- no propagation through voids or obstacles
        s.y,s.height,s.warn,s.erupted=y or e.position.y,0,s.valid,false
        param(s,'ground','brush',-.1);param(s,'ground','ash',-1);param(s,'wall','heat',0)
        s.sprayFade=-1;s.spraySize=0
        if s.spray then s.spray.enabled=false end
        if s.node then
            s.node.enabled=s.valid;s.node.position=Vector3(s.x,s.y,s.z);s.node.rotation=Quaternion(e.yaw,Vector3.UP)
            s.marker.position=Vector3(0,highest-s.y+.045,0)
            s.marker.enabled=s.warn;s.rock.enabled=false
        end
    end
end

function Fault:Step(e,t,dt,target)
    if not self.active then return end
    local dx,dz=target.x-self.x,target.z-self.z
    local x,z=dx*self.fz-dz*self.fx,dx*self.fx+dz*self.fz
    for i,s in ipairs(self.sections) do
        local age=t-s.start
        if s.valid and age>=-1e-8 then
            if not s.erupted then
                s.erupted=true
                local side=i%2==0 and -1 or 1
                local ax,az=self.fz*side,-self.fx*side
                e.dust.pos=Vector3(s.x-ax*.79,s.y+.08,s.z-az*.79)
                e.particles:Emit(e,e.dust)
                e.chips.pos=Vector3(s.x+ax*.76,s.y+.16,s.z+az*.76)
                e.chips.normal=Vector3(ax*.65,.76,az*.65)
                e.particles:Emit(e,e.chips)
            end
            s.warn=false
            local rise=math.min(1,math.max(.09,age/Fault.RISE))
            local sink=math.min(1,math.max(0,(Fault.END-age)/(Fault.END-Fault.HOLD)))
            s.height=s.peak*rise*sink
            param(s,'wall','heat',math.max(0,1-age/.41))
            param(s,'ground','ash',math.min(1,math.max(0,(age-.42)/.36)))
            s.spraySize=age<.40 and (.76+2.20*age) or 0
            local side=i%2==0 and -1 or 1
            s.sprayX=side*(.81+.95*age);s.sprayY=.025+age*.15
            local fade=math.floor(math.min(1,age/.40)*12)/12
            if s.spray then
                s.spray.enabled=s.spraySize>0
                if s.spray.enabled then
                    s.spray.position=Vector3(s.sprayX,s.sprayY,.35);s.spray.scale=Vector3(s.spraySize,s.spraySize,1)
                    s.spray.rotation=Quaternion(side*32,Vector3.UP)
                    if fade~=s.sprayFade then s.ink.spray:SetShaderParameter('ash',Variant(fade)) end
                end
            end
            s.sprayFade=fade
            if s.node then
                s.marker.enabled=s.ink~=nil and s.ash<1;s.rock.enabled=s.height>.001
                if s.rock.enabled then s.rock.scale=Vector3(1,s.height,1) end
            end
            if not e.attackHit and age-dt<Fault.RISE and Fault.Contains(x,z-s.distance)
                and target.y+1.6>=s.y and target.y<=s.y+s.peak*rise then
                e:DamagePlayer(target,e.attack.range+1,nil,false)
            end
        end
    end
end

function Fault:Clear()
    self.active=false
    for _,s in ipairs(self.sections) do
        s.warn,s.erupted,s.height,s.spraySize=false,false,0,0
        if s.node then s.marker.enabled=false;s.rock.enabled=false end
        if s.spray then s.spray.enabled=false end
    end
    if self.root then self.root.enabled=false end
end
function Fault:Destroy()
    self:Clear()
    if self.root then self.root:Remove();self.root=nil end
end
return Fault
