-- Lua 5.4 only. These doubles validate ownership/math/state, NOT native bindings
-- or rendered pixels. Missing native methods deliberately throw instead of passing.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local Builder=require('combat.WeaponBuilder')
local Parts=require('combat.WeaponCatalog')
local Showroom=require('combat.ForgeShowroom')
local ThornBow=require('combat.ThornBowVisual')
ThornBow.ENABLED=false -- voxel fallback path under test below; thorn bow route has its own block at the end
local Blades=require('combat.ForgeShowroomBlades')
local WingSword=require('combat.WingSwordVisual')
WingSword.ENABLED=false
local Dressing=require('combat.ForgeShowroomScene')
local MASK=0x40000000
local function Number(value,label)
    assert(type(value)=='number' and value==value and math.abs(value)<math.huge,label..': number expected')
end
local function Integer(value,label) Number(value,label);assert(value%1==0,label..': integer expected') end
local function Vector(value,dimensions,label)
    assert(type(value)=='table',label..': vector expected')
    Number(value.x,label..'.x');Number(value.y,label..'.y')
    if dimensions==3 then Number(value.z,label..'.z') end
end
local function Resource(value,kind)
    assert(type(value)=='table' and value.resourceType==kind,kind..' expected')
end
local function NoExtra(label,...) assert(select('#',...)==0,label..': unexpected extra arguments') end
-- Every property write uses a backing table, including repeated writes: a plain
-- __newindex on the original table would validate only the first assignment.
local numeric={viewMask=true,lightMask=true,zoneMask=true,brightness=true,range=true,fov=true,
    nearClip=true,farClip=true,priority=true,ambientSource=true,focalDistance=true,focalRange=true,maxBlur=true,
    nearBlurScale=true,farBlurScale=true,depthFogStart=true,depthFogEnd=true,depthFogDensity=true,
    shadowResolution=true,shadowIntensity=true,volumetricFogIntensity=true}
local integral={viewMask=true,lightMask=true,zoneMask=true,priority=true,ambientSource=true,lightType=true,quality=true}
local boolean={enabled=true,castShadows=true,occluder=true,depthFogEnable=true,heightFogEnable=true,
    volumetricFogEnabled=true,autoExposureEnabled=true,affectVolumetricFog=true,volumetricFogShadows=true}
local function ComponentProxy(data)
    return setmetatable({}, {__index=data,__newindex=function(_,key,value)
        if integral[key] then Integer(value,data.kind..'.'..key)
        elseif numeric[key] then Number(value,data.kind..'.'..key)
        elseif boolean[key] then assert(type(value)=='boolean',data.kind..'.'..key..': boolean expected')
        elseif key=='projectionOffset' then Vector(value,2,'Camera.projectionOffset') end
        data[key]=value
    end})
end
local function StrictGeometry(g)
    local vertex,normal,color,commit=g.DefineVertex,g.DefineNormal,g.DefineColor,g.Commit
    g.numGeometries=1;g.groups={};g.materials={}
    function g:SetNumGeometries(n,...)
        NoExtra('SetNumGeometries',...);Integer(n,'geometry count');assert(n>0);self.numGeometries=n
    end
    function g:BeginGeometry(index,primitive,...)
        NoExtra('BeginGeometry',...);Integer(index,'index');Integer(primitive,'primitive')
        assert(index>=0 and index<self.numGeometries and primitive==TRIANGLE_LIST)
        self.activeGroup=index;self.groups[index]=0
    end
    function g:DefineVertex(value,...)
        NoExtra('DefineVertex',...);Vector(value,3,'position')
        self.groups[self.activeGroup]=self.groups[self.activeGroup]+1;return vertex(self,value)
    end
    function g:DefineNormal(value,...) NoExtra('DefineNormal',...);Vector(value,3,'normal');return normal(self,value) end
    function g:DefineTexCoord(value,...)
        NoExtra('DefineTexCoord',...);Vector(value,2,'UV');self.vertices[#self.vertices].uv=value
    end
    function g:DefineColor(value,...)
        NoExtra('DefineColor',...);assert(type(value)=='table','Color expected')
        for _,key in ipairs({'r','g','b','a'}) do Number(value[key],'Color.'..key) end
        return color(self,value)
    end
    function g:Commit(...) NoExtra('Commit',...);return commit(self) end -- native void return
    function g:SetMaterial(...)
        local n=select('#',...);assert(n==1 or n==2,'SetMaterial: 1 or 2 arguments expected')
        local index,mat=...;if n==1 then mat,index=index,0 end
        Integer(index,'SetMaterial index');Resource(mat,'Material');assert(index>=0 and index<self.numGeometries and self.commits>0)
        self.materials[index]=mat;if index==0 then self.material=mat end;return true
    end
    function g:GetMaterial(index,...) NoExtra('GetMaterial',...);index=index or 0;Integer(index,'index');return self.materials[index] end
    function g:GetNumVertices(index,...)
        NoExtra('GetNumVertices',...);Integer(index,'index');assert(self.commits>0);return self.groups[index] or 0
    end
    return g
end
rawset(_G,'Vector2',function(x,y,...)NoExtra('Vector2',...);Number(x,'x');Number(y,'y');return {x=x,y=y}end)
rawset(_G,'BoundingBox',function(a,b,...)NoExtra('BoundingBox',...);Vector(a,3,'min');Vector(b,3,'max');return {min=a,max=b}end)
local quaternion=Quaternion
rawset(_G,'Quaternion',function(pitch,yaw,roll,...)
    NoExtra('Quaternion Euler overload',...)
    Number(pitch or 0,'pitch');Number(yaw or 0,'yaw');Number(roll or 0,'roll')
    local q=quaternion(pitch,yaw,roll);local from=q.FromEulerAngles
    q.FromEulerAngles=function(self,x,y,z,...)
        NoExtra('FromEulerAngles',...);Number(x,'x');Number(y,'y');Number(z,'z');return from(self,x,y,z)
    end
    return q
end)
rawset(_G,'DOF_QUALITY_MEDIUM',1);rawset(_G,'BLEND_ADDALPHA',4);rawset(_G,'CULL_NONE',0);rawset(_G,'AMBIENT_COLOR',2);rawset(_G,'LIGHT_POINT',2)
rawset(_G,'LIGHT_DIRECTIONAL',0);rawset(_G,'TONEMAP_MODE_ACES',1);rawset(_G,'BLOOM_MODE_LEGACY',0)
rawset(_G,'TU_DIFFUSE',0);rawset(_G,'TU_NORMAL',1)
rawset(_G,'CascadeParameters',function(a,b,c,d,f,bias,...)
    NoExtra('CascadeParameters',...);for _,v in ipairs({a,b,c,d,f}) do Number(v,'cascade') end
    if bias~=nil then Number(bias,'bias') end;return {a,b,c,d,f}
end)
rawset(_G,'BiasParameters',function(a,b,c,...)
    NoExtra('BiasParameters',...);Number(a,'constant bias');Number(b,'slope bias')
    if c~=nil then Number(c,'normal offset') end;return {a,b,c}
end)
for _,name in ipairs({'Scene','Texture2D','RenderTexture','VoxelPhysicsWorld'}) do rawset(_G,name,function()error('forbidden '..name)end) end
local e
local function Wrap(n)
    e.nodes[#e.nodes+1]=n;n.components={}
    function n:CreateChild(name,mode,id,temporary,...)
        NoExtra('CreateChild',...);assert(name==nil or type(name)=='string')
        if mode~=nil then Integer(mode,'CreateMode') end
        if id~=nil then Integer(id,'node id') end
        assert(temporary==nil or type(temporary)=='boolean')
        if e.fail=='child' then error('injected child error') end
        if e.failNode==name then
            e.failNodeSeen=(e.failNodeSeen or 0)+1
            if e.failNodeSeen>=(e.failNodeNth or 1) then error('injected scene stage '..name) end
        end
        local child=Wrap(Mock.Node(name,self));self.children[#self.children+1]=child;return child
    end
    function n:CreateComponent(kind,mode,id,...)
        NoExtra('CreateComponent',...);assert(type(kind)=='string')
        if mode~=nil then Integer(mode,'CreateMode') end
        if id~=nil then Integer(id,'component id') end
        assert(kind~='VoxelPhysicsWorld' and kind~='Octree','must reuse main scene world/octree')
        if e.fail==kind then return nil end
        local c=kind=='CustomGeometry' and StrictGeometry(Mock.CustomGeometry(self,e.geometryOptions)) or {node=self}
        c.kind=kind;c.viewMask=0xffffffff;c.lightMask=0xffffffff;c.zoneMask=0xffffffff
        if kind=='StaticModel' then
            function c:SetModel(model,...) NoExtra('StaticModel:SetModel',...);Resource(model,'Model');self.model=model end
            function c:SetMaterial(index,mat,...)
                NoExtra('StaticModel:SetMaterial',...);Integer(index,'material index');Resource(mat,'Material')
                assert(index==0);self.material=mat;return true
            end
        end
        if kind=='Camera' then c.projectionOffset=Vector2(0,0) end
        if kind=='Zone' then
            c.ambientSource=0
            for _,method in ipairs({'SetTonemapMode','SetBloomMode','SetBloomThreshold','SetBloomWeight','SetVignetteIntensity',
                'SetVolumetricFogDensity','SetVolumetricFogHeight','SetVolumetricFogHeightFalloff','SetVolumetricFogViewDistance',
                'SetVolumetricFogStartDistance','SetVolumetricFogPhaseG','SetVolumetricFogMaxOpacity'}) do
                c[method]=function(target,value,...) NoExtra(method,...);Number(value,method);target[method:sub(4)]=value end
            end
            for _,method in ipairs({'SetVignetteEnabled','SetVolumetricFogEnabled'}) do
                c[method]=function(target,value,...) NoExtra(method,...);assert(type(value)=='boolean');target[method:sub(4)]=value end
            end
            function c:SetVignetteTexture(value,...) NoExtra('SetVignetteTexture',...);Resource(value,'Texture2D');self.VignetteTexture=value end
            function c:SetVolumetricFogScatteringColor(value,...)
                NoExtra('SetVolumetricFogScatteringColor',...)
                for _,k in ipairs({'r','g','b','a'}) do Number(value[k],'color.'..k) end;self.ScatteringColor=value
            end
            function c:SetAttribute(key,value,...) NoExtra('Zone:SetAttribute',...);assert(key=='Bloom Enable' and type(value)=='boolean');self.BloomEnable=value end
        end
        for method,field in pairs({SetBrightness='brightness',SetRange='range',SetFov='fov',SetFocalDistance='focalDistance',SetFocalRange='focalRange',SetMaxBlur='maxBlur',SetQuality='quality',SetNearBlurScale='nearBlurScale',SetFarBlurScale='farBlurScale'}) do
            c[method]=function(target,value,...) NoExtra(method,...);Number(value,method);target[field]=value end
        end
        if e.missingKind==kind then c[e.missingField]=nil end
        c=ComponentProxy(c)
        self.components[#self.components+1]=c;return c
    end
    function n:GetComponents(kind,recursive,...)
        NoExtra('GetComponents',...);assert(type(kind)=='string' and (recursive==nil or type(recursive)=='boolean'))
        local out={}
        local function Visit(node)
            if node.removed then return end
            for _,c in ipairs(node.components) do if c.kind==kind then out[#out+1]=c end end
            if recursive then for _,child in ipairs(node.children) do Visit(child) end end
        end
        Visit(self);return out
    end
    function n:GetComponent(kind,recursive,...) NoExtra('GetComponent',...);return self:GetComponents(kind,recursive)[1] end
    function n:Remove(...)
        NoExtra('Node:Remove',...)
        assert(not self.removed,'node removed twice')
        for _,child in ipairs(self.children) do if not child.removed then child:Remove() end end
        self.removed=true
    end
    return n
end
local function Boot()
    Showroom.Exit();e={nodes={},materials={},techniques={},width=844,height=390,setCalls=0}
    e.scene=Wrap(Mock.Node('MainScene'));e.scene.components={{kind='Octree'}}
    e.oldCamera={fov=61,projectionOffset={x=.12,y=.2}}
    e.original={scene=e.scene,camera=e.oldCamera};e.viewport=e.original
    e.sun=e.scene:CreateChild('Sun'):CreateComponent('Light')
    e.sun.lightMask=0x7fffffff
    e.sky=e.scene:CreateChild('Sky'):CreateComponent('Skybox')
    e.cloud=e.scene:CreateChild('SkyClouds'):CreateComponent('CustomGeometry')
    e.cloud.viewMask=0xefffffff
    rawset(_G,'graphics',{GetWidth=function(self,...)NoExtra('GetWidth',...);assert(self==graphics);return e.width end,
        GetHeight=function(self,...)NoExtra('GetHeight',...);assert(self==graphics);return e.height end})
    rawset(_G,'renderer',{GetViewport=function(self,index,...) NoExtra('GetViewport',...);Integer(index,'index');assert(self==renderer and index==0);return e.viewport end,
        SetViewport=function(self,index,v,...)NoExtra('SetViewport',...);Integer(index,'index');assert(self==renderer and index==0);assert(v==nil or type(v)=='table');e.viewport=v;e.setCalls=e.setCalls+1;
            if e.fail=='switch' then e.fail=nil;error('partial switch failure') end end})
    rawset(_G,'Viewport',{new=function(self,scene,camera,...) NoExtra('Viewport selected overload',...);assert(self==Viewport and scene==e.scene and camera.kind=='Camera');return {scene=scene,camera=camera} end})
    rawset(_G,'Material',{new=function(self,...)
        NoExtra('Material:new',...);assert(self==Material);local m={resourceType='Material'};e.materials[#e.materials+1]=m
        function m:SetTechnique(index,t,qualityLevel,lodDistance,...)
            NoExtra('SetTechnique',...);assert(self==m);Integer(index,'SetTechnique index');Resource(t,'Technique')
            if qualityLevel~=nil then Number(qualityLevel,"SetTechnique argument #4") end
            if lodDistance~=nil then Number(lodDistance,"SetTechnique argument #5") end
            self.technique=t;self.qualityLevel=qualityLevel;self.lodDistance=lodDistance
        end
        function m:SetShaderParameter(k,v,...)
            NoExtra('SetShaderParameter',...);assert(self==m and type(k)=='string' and v~=nil)
            if e.failShader==k then e.failShader=nil;error('injected shader parameter '..k) end
            self[k]=v
        end
        function m:Dispose(...) NoExtra('Material:Dispose',...);assert(self==m and not self.disposed);self.disposed=true end
        function m:SetTexture(unit,texture,...)
            NoExtra('Material:SetTexture',...);Integer(unit,'texture unit');Resource(texture,'Texture2D')
            self.textures=self.textures or {};self.textures[unit]=texture
        end
        return m
    end})
    rawset(_G,'cache',{GetFile=Mock.GetFile,GetResource=function(self,kind,path,sendEventOnFailure,...)
        NoExtra('GetResource',...);assert(self==cache and type(kind)=='string' and type(path)=='string')
        assert(sendEventOnFailure==nil or type(sendEventOnFailure)=='boolean')
        if e.fail=='material' then return nil end
        if e.failResource==path then return nil end
        assert(path=='Materials/NomiVoxel.xml' or path=='Techniques/NoTextureUnlit.xml' or path=='Techniques/PBR/PBRNoTexture.xml'
            or path=='Editor/Textures/Engine/Vignetting.png' or path=='Techniques/PBR/PBRDiffNormal.xml' or path:find('model/',1,true)==1)
        if kind=='Model' then
            if e.modelFail then return nil end
            return {resourceType='Model',boundingBox={min=Vector3(-.09,-.95,-.035),max=Vector3(.09,e.emptyModel and -.95 or .95,.035)},
                GetNumGeometries=function(self,...) NoExtra('Model:GetNumGeometries',...);Resource(self,'Model');return 1 end,
                GetGeometry=function(self,index,lod,...) NoExtra('Model:GetGeometry',...);Resource(self,'Model');assert(index==0 and lod==0);return {vertexCount=300,indexCount=600} end}
        end
        if kind=='Material' and path:find('model/',1,true)==1 and e.modelMaterialMissing then return nil end
        local resource={name=path,resourceType=kind}
        function resource:Clone(name,...)
            NoExtra('Technique:Clone',...);assert(self==resource and type(name)=='string')
            if kind=='Material' then return Material:new() end
            local clone={name=name,resourceType='Technique'};e.techniques[#e.techniques+1]=clone
            function clone:Dispose(...) NoExtra('Technique:Dispose',...);assert(self==clone and not self.disposed);self.disposed=true end
            function clone:GetPass(name,...)
                NoExtra('GetPass',...);assert(self==clone and name=='base')
                return setmetatable({}, {__newindex=function(t,k,v)
                    if k=='blendMode' then Integer(v,'blend mode') else assert(k=='depthWrite' and type(v)=='boolean') end
                    rawset(t,k,v)
                end})
            end
            return clone
        end
        return resource
    end})
    rawset(_G,'time',{GetElapsedTime=function(self)assert(self==time,'Time singleton must use colon');return os.clock()end})
end
local function Live()
    local n,g=0,0
    for _,node in ipairs(e.nodes) do if not node.removed then n=n+1;g=g+#node.components end end
    return n,g
end
local function Config(weapon) local c=Parts.DefaultWeapon(weapon);c.weapon=weapon;return c end
local function Finish()
    for _=1,240 do
        Showroom.Update(1/60)
        if Showroom.State()~='building' then break end
    end
    assert(Showroom.IsReady(),Showroom.State())
end
local function Room() return assert(e.scene:GetChild('ForgeShowroom',true)) end
local function Spin() return assert(Room():GetChild('WeaponTurntable')) end
local function Shape()
    for _,child in ipairs(Spin().children) do if not child.removed and child.enabled then return child end end
end
local function Restored(n,g)
    assert(not Showroom.Active() and not Showroom.IsReady())
    assert(e.viewport==e.original and e.oldCamera.fov==61 and e.oldCamera.projectionOffset.x==.12)
    assert(e.sun.lightMask==0x7fffffff and e.sun.viewMask==0xffffffff and e.sky.viewMask==0xffffffff and e.cloud.viewMask==0xefffffff)
    local nn,gg=Live();assert(nn==n and gg==g,'nodes/components leaked')
    for _,mat in ipairs(e.materials) do assert(mat.disposed,'owned material leaked') end
    for _,tech in ipairs(e.techniques) do assert(tech.disposed,'owned technique leaked') end
end

-- Reproduce the real tolua failure: assert(v,msg) in last position expands into
-- technique + message. The optional native numeric slots MUST reject that text.
Boot()
do
    local material=Material:new()
    local technique=cache:GetResource('Technique','Techniques/NoTextureUnlit.xml')
    local ok,err=pcall(function() material:SetTechnique(0,assert(technique,'unlit technique missing')) end)
    assert(not ok and tostring(err):find('SetTechnique argument #4',1,true),'strict mock missed the real Web failure')
    material:SetTechnique(0,technique)
    material:SetTechnique(0,technique,nil,nil)
    material:SetTechnique(0,technique,2,15)
    assert(not pcall(material.SetTechnique,material,0,technique,2,'bad lod'))
    assert(not pcall(material.SetTechnique,material,0,technique,2,15,'extra'))
    assert(not pcall(material.SetTechnique,0,technique),'dot call must not silently substitute self')
    local light=e.sun
    light:SetBrightness(5);light:SetRange(8);light:SetFov(34)
    for _,method in ipairs({'SetBrightness','SetRange','SetFov'}) do
        assert(not pcall(light[method],light,'invalid'))
        assert(not pcall(light[method],light,3,'extra'))
    end
    assert(not pcall(function() light.range='invalid repeated property write' end))
    assert(not pcall(function() light.brightness=nil end))
    local geometry=e.cloud
    assert(not pcall(geometry.BeginGeometry,geometry,0,'triangles'))
    assert(not pcall(geometry.DefineVertex,geometry,Vector3(0,0,0),'extra'))
    assert(not pcall(geometry.DefineNormal,geometry,'wrong vector'))
    assert(not pcall(geometry.DefineColor,geometry,Vector3(1,1,1)))
    assert(not pcall(geometry.Commit,geometry,'extra'))
    assert(not pcall(geometry.SetMaterial,geometry,0,technique),'Technique must not stand in for Material')
    local camera=e.scene:CreateChild('TypeProbeCamera'):CreateComponent('Camera')
    camera:SetFov(34);camera.nearClip=.05;camera.farClip=32
    assert(not pcall(camera.SetFov,camera,'wide'))
    assert(not pcall(function() camera.fov='wide' end))
    assert(not pcall(function() camera.projectionOffset=.3 end))
    local rotation=Quaternion(0,25,0)
    assert(not pcall(rotation.FromEulerAngles,rotation,0,'bad yaw',0))
    assert(not pcall(rotation.FromEulerAngles,rotation,0,25,0,'extra'))
    material:Dispose()
end
print('forge_showroom binding signatures PASS: assert multi-return regression, numeric methods/properties, geometry types/arity, colon self')

Boot();local nodes,components=Live()
assert(Showroom.Diagnostic()=='')
assert(Showroom.State()=='off' and not Showroom.Active())
Showroom.Update(1);Showroom.SetWeapon({});Showroom.DragBegin();Showroom.Home();Showroom.Exit()
assert(Showroom.Enter(e.scene,{focusX=.3}))
assert(Showroom.Active() and Showroom.State()=='building' and not Showroom.IsReady())
assert(Room().position.x==2304 and Room().position.y==1200)
assert(e.viewport.camera.viewMask==MASK and e.viewport.scene==e.scene)
assert((e.sun.lightMask&MASK)==0 and (e.sky.viewMask&MASK)==0 and (e.cloud.viewMask&MASK)==0)
local zone=Room():GetComponent('Zone');assert(zone.ambientSource==AMBIENT_COLOR and zone.depthFogEnable and not zone.heightFogEnable)
local lights=Room():GetComponents('Light',true);assert(#lights==6)
for _,l in ipairs(lights) do assert(l.viewMask==MASK and l.lightMask==MASK and l.range>0) end
assert(not Room():GetChild('RuinsShowroom_sky'),'Enter must not emit scene geometry')
local c=Config('sword');Showroom.SetWeapon(c);c.appearance='invalid-mutated-after-call'
Finish();assert(Shape() and Shape():GetComponent('CustomGeometry')==nil)
local oldShape=Shape();local oldGeometry=oldShape.children[1]:GetComponent('CustomGeometry')
assert(oldGeometry:GetNumVertices(0)>0 and oldGeometry.viewMask==MASK and oldGeometry.zoneMask==MASK)
Showroom.SetWeapon(Config('bow'));Showroom.Update(1/60)
assert(not oldShape.removed and oldShape.enabled and not Showroom.IsReady(),'old weapon must survive pending compile')
Showroom.Update(1/60);Showroom.SetWeapon(Config('sword'));Finish()
assert(oldShape.removed,'replacement must dispose old geometry')
for _=1,12000 do Showroom.Update(1/60) end -- finish decoration before idle leak check
local count=Live();local yaw=Spin().rotation.eulerAngles.y
for _=1,60 do Showroom.Update(1/60) end
Mock.Near((Spin().rotation.eulerAngles.y-yaw)%360,12,1e-5)
assert(Live()==count,'idle must not allocate new nodes')
Showroom.DragBegin();yaw=Spin().rotation.eulerAngles.y;Showroom.Update(1);Mock.Near(Spin().rotation.eulerAngles.y,yaw)
Showroom.DragBy(100);Showroom.Update(0);Mock.Near((Spin().rotation.eulerAngles.y-yaw)%360,35)
Showroom.DragEnd(100);Showroom.Update(1);Showroom.Update(.5);yaw=Spin().rotation.eulerAngles.y
Showroom.Update(.5);Mock.Near((Spin().rotation.eulerAngles.y-yaw)%360,6)
Showroom.Home();for _=1,60 do Showroom.Update(1/120) end
assert(math.abs((Spin().rotation.eulerAngles.y-25+180)%360-180)<2)
Showroom.SetFocus(.25,.4);Showroom.Update(0)
Mock.Near(e.viewport.camera.projectionOffset.x,-.25);Mock.Near(e.viewport.camera.projectionOffset.y,.1)
e.width,e.height=390,844;Showroom.Update(0);assert(Showroom.IsReady())
Showroom.Exit();Showroom.Exit();Restored(nodes,components)

-- Fitting uses the FULL compiled bounds: every option, all yaw angles, portrait
-- and landscape. Algebraic projection only: no claim of native/GPU validation.
Boot();nodes,components=Live();assert(Showroom.Enter(e.scene))
local combos,maxWeaponTriangles=0,0
local occupancyMin,occupancyMax=1,0
for _,weapon in ipairs({'sword','bow'}) do
    local config=Config(weapon)
    local function Visit()
        combos=combos+1;Showroom.SetWeapon(config);Finish()
        maxWeaponTriangles=math.max(maxWeaponTriangles,#Shape().children[1]:GetComponent('CustomGeometry').vertices/3)
        local b=Builder.Compile(config).bounds
        for _,size in ipairs({{844,390},{1280,720},{390,844}}) do
            e.width,e.height=size[1],size[2];Showroom.Update(0)
            local camera=e.viewport.camera;local cameraNode=Room():GetChild('ForgeCamera')
            local cp,sp=math.cos(math.rad(8)),math.sin(math.rad(8))
            local distance=-cameraNode.position.z/cp
            local tan=math.tan(math.rad(camera.fov)/2)
            local scale=Spin().scale.x
            Mock.Near(scale*(b.max[2]-b.min[2]),2.05)
            local dof=cameraNode:GetComponent('DepthOfField')
            Mock.Near(dof.focalDistance,distance);assert(dof.focalRange>.8 and dof.quality==DOF_QUALITY_MEDIUM)
            local standY=.5-(cp*(.65-Spin().position.y))/(2*(distance-sp*(.65-Spin().position.y))*tan)
            assert(standY>.70 and standY<.86,'stand must sit in lower screen quarter')
            local minHeight=1
            for angle=0,357,7 do
                local q=Quaternion(0,angle,0)
                local minY,maxY=1,0
                for xi=1,2 do for yi=1,2 do for zi=1,2 do
                    local p=q*Vector3((xi==1 and b.min[1] or b.max[1])-(b.min[1]+b.max[1])/2,
                        (yi==1 and b.min[2] or b.max[2])-(b.min[2]+b.max[2])/2,
                        (zi==1 and b.min[3] or b.max[3])-(b.min[3]+b.max[3])/2)
                    p=p*scale
                    local py,pz=cp*p.y+sp*p.z,-sp*p.y+cp*p.z
                    local x=.3+p.x/(2*(distance+pz)*tan*e.width/e.height)
                    local y=.5-py/(2*(distance+pz)*tan)
                    assert(x>0 and x<.55 and y>0 and y<1,'weapon clipped / under panel')
                    minY=math.min(minY,y);maxY=math.max(maxY,y)
                end end end
                minHeight=math.min(minHeight,maxY-minY)
            end
            occupancyMin=math.min(occupancyMin,minHeight);occupancyMax=math.max(occupancyMax,minHeight)
            assert(minHeight>=.55 and minHeight<=.60,'weapon occupancy '..minHeight)
        end
    end
    Visit(1)
end
assert(combos==2);print('weapon occupancy min/max='..occupancyMin..'/'..occupancyMax..' max_weapon_triangles='..maxWeaponTriangles);Showroom.Exit();Restored(nodes,components)

for _,fail in ipairs({'child','Zone','Camera','switch'}) do
    Boot();nodes,components=Live();e.fail=fail
    assert(not Showroom.Enter(e.scene));assert(Showroom.State()=='failed');Restored(nodes,components)
    Showroom.Exit();assert(Showroom.State()=='off')
end
for _,failure in ipairs({'mesh','timeout','clock'}) do
    Boot();nodes,components=Live();assert(Showroom.Enter(e.scene));Showroom.SetWeapon(Config('sword'))
    local step=Builder.StepPreview
    if failure=='mesh' then Builder.StepPreview=function() error('injected mesh failure') end
    elseif failure=='timeout' then Builder.StepPreview=function() return false end
    else rawset(_G,'time',{GetElapsedTime=function() error('clock unavailable') end}) end
    for _=1,400 do Showroom.Update(1/60);if Showroom.State()~='building' then break end end
    Builder.StepPreview=step
    if failure=='clock' then assert(Showroom.IsReady());Showroom.Exit() else assert(Showroom.State()=='failed') end
    Restored(nodes,components)
end
for _=1,10 do Boot();nodes,components=Live();assert(Showroom.Enter(e.scene));Showroom.SetWeapon(Config('bow'));Showroom.Update(.01);Showroom.Exit();Restored(nodes,components) end
-- Scene's sole SetViewport and both camera update sites are guarded; Stop cleans.
local file=assert(io.open('scripts/ruins/RuinsScene.lua'));local source=file:read('*a');file:close()
assert(source:find('if not ForgeShowroom.Active() then renderer:SetViewport',1,true))
assert(source:match('local function UpdateBaseCamera%(dt%)%s+if ForgeShowroom and ForgeShowroom.Active%(%) then return end'))
assert(source:match('local function UpdateCombatCamera%(dt,cn%)%s+if ForgeShowroom and ForgeShowroom.Active%(%) then return end'))
assert(source:find('ForgeShowroom.Exit()',1,true))
print('forge_showroom PASS: 72 configs, viewport/masks rollback, atomic rebuild/cancel, fit, drag/home, timeout/errors, lifecycle; MOCK ONLY')

-- Failure evidence must survive Exit and de-duplicate across reopen attempts.
-- Control the engine singleton clock; never use a fake Time static binding.
local realPrint=print
local lines={}
local now=1000
rawset(_G,'print',function(message) lines[#lines+1]=tostring(message) end)
local function Clock() rawset(_G,'time',{GetElapsedTime=function(self) assert(self==time);return now end}) end
local function EnterFailure(stage,api,setup)
    Boot();Clock();local before=#lines
    setup()
    assert(not Showroom.Enter(e.scene) and Showroom.State()=='failed')
    local text=Showroom.Diagnostic()
    assert(text:find('stage='..stage,1,true) and text:find(api,1,true),text)
    assert(text:find('viewport_acquired=',1,true) and text:find('mask=1073741824',1,true),text)
    assert(not text:find('[\r\n]'),'diagnostic must be one line')
    assert(#lines==before+1 and lines[#lines]:find('ForgeShowroom: enter failed stage='..stage..' error=',1,true)==1)
    Showroom.Exit();assert(Showroom.Diagnostic()==text,'Exit must not erase evidence')
end
EnterFailure('viewport','renderer:GetViewport',function() renderer.GetViewport=nil end)
EnterFailure('viewport','renderer:SetViewport',function() renderer.SetViewport=nil end)
EnterFailure('light','Node:GetComponents',function()
    -- Keep Octree lookup independent, so failure reaches the missing API itself.
    e.scene.GetComponent=function() return {kind='Octree'} end
    e.scene.GetComponents=nil
end)
for _,field in ipairs({'viewMask','lightMask','zoneMask'}) do
    EnterFailure('zone','Drawable.'..field,function() e.missingKind='Zone';e.missingField=field end)
end
EnterFailure('zone','Zone.ambientSource',function() e.missingKind='Zone';e.missingField='ambientSource' end)
EnterFailure('camera','Camera.projectionOffset',function() e.missingKind='Camera';e.missingField='projectionOffset' end)
EnterFailure('camera','Node:CreateComponent',function() e.fail='Camera' end)
-- Decorative geometry errors are deferred and cosmetic; covered below.
-- Same missing API at 0/9.99/10s: first and third log, middle is suppressed.
local before=#lines
for _,elapsed in ipairs({0,9.99,10}) do
    now=1100+elapsed;Boot();Clock();renderer.GetViewport=nil
    assert(not Showroom.Enter(e.scene));assert(Showroom.Diagnostic():find('api_type=nil',1,true))
    assert(#lines==before+(elapsed<10 and 1 or 2),'10-second dedup/reopen failed')
end
now=1200;Boot();Clock();assert(Showroom.Enter(e.scene));assert(Showroom.Diagnostic()=='')
before=#lines;Showroom.SetWeapon({weapon='axe'})
assert(Showroom.Diagnostic():find('origin=SetWeapon',1,true))
assert(#lines==before+1 and lines[#lines]:find('ForgeShowroom: update failed stage=weapon error=',1,true)==1)
-- The outer pcall catches thrown APIs; the builder also has its own error return.
local realStep=Builder.StepPreview
for _,throws in ipairs({true,false}) do
    now=now+20;Boot();Clock();assert(Showroom.Enter(e.scene));Showroom.SetWeapon(Config('bow'));Showroom.Update(0)
    Builder.StepPreview=function(job)
        job.stage='commit'
        if throws then error('injected Commit error\nsecond line') end
        return true,nil,'missing API CustomGeometry:Commit'
    end
    before=#lines;Showroom.Update(.01)
    assert(Showroom.State()=='failed' and #lines==before+1)
    assert(lines[#lines]:find('ForgeShowroom: update failed stage=geometry error=',1,true)==1)
    assert(Showroom.Diagnostic():find('geometry_stage=commit',1,true))
    assert(not Showroom.Diagnostic():find('[\r\n]'))
    for _=1,60 do Showroom.Update(1/60) end
    assert(#lines==before+1,'failed Update must not spam on subsequent frames')
    Builder.StepPreview=realStep
end
-- Missing per-frame native method is named, not a generic nil-call error.
now=now+20;Boot();Clock();assert(Showroom.Enter(e.scene));Showroom.SetWeapon(Config('sword'));Finish()
graphics.GetWidth=nil;Showroom.Update(.01)
assert(Showroom.Diagnostic():find('missing API graphics:GetWidth',1,true))
-- A missing renderer during failure cleanup must not throw out of Update or
-- replace the primary error; append the rollback API name to the diagnostic.
now=now+20;Boot();Clock();assert(Showroom.Enter(e.scene));Showroom.SetWeapon(Config('sword'));Finish()
rawset(_G,'graphics',nil);rawset(_G,'renderer',nil)
assert(pcall(Showroom.Update,.01) and Showroom.State()=='failed')
assert(Showroom.Diagnostic():find('graphics:GetWidth',1,true))
assert(Showroom.Diagnostic():find('cleanup=renderer:SetViewport',1,true))
rawset(_G,'print',realPrint)
print('forge_showroom diagnostics PASS: missing bindings, stages, single-line errors, Enter/Update/SetWeapon, 10s dedup and recovery; MOCK ONLY')


-- DOF API shape, fallback and ownership are verified; native Web pixels are not.
for _,failure in ipairs({'none','component','method','focus'}) do
    Boot();nodes,components=Live()
    if failure=='component' then e.fail='DepthOfField'
    elseif failure=='method' then e.missingKind='DepthOfField';e.missingField='SetMaxBlur'
    elseif failure=='focus' then e.missingKind='DepthOfField';e.missingField='SetFocalRange' end
    assert(Showroom.Enter(e.scene),'DOF must not reject Enter')
    local zone=Room():GetComponent('Zone')
    local dof=Room():GetChild('ForgeCamera'):GetComponent('DepthOfField')
    if failure=='none' then
        assert(dof.maxBlur==7 and dof.quality==DOF_QUALITY_MEDIUM and dof.nearBlurScale==.08 and dof.farBlurScale==.9)
        assert(zone.depthFogEnable and Showroom.Diagnostic()=='',Showroom.Diagnostic())
        assert(not pcall(dof.SetFocalDistance,dof,'bad'))
        assert(not pcall(dof.SetMaxBlur,dof,7,'extra'))
    else
        assert(zone.depthFogEnable and zone.depthFogEnd>zone.depthFogStart)
        assert(Showroom.Diagnostic():find('stage=dof',1,true),Showroom.Diagnostic())
        assert(not dof or dof.enabled==false)
    end
    Showroom.SetWeapon(Config('bow'));Finish()
    assert(Showroom.IsReady() and e.original.camera.fov==61)
    Showroom.Exit();Showroom.Exit();Restored(nodes,components)
end
print('forge_showroom DOF PASS: camera-local scope, strict signatures, nil/method/focus fallback, haze and cleanup; MOCK ONLY')

-- Round 3: local lights/post effects; never change renderer-wide settings.
for _,quality in ipairs({'high','low'}) do
    Boot();nodes,components=Live();assert(Showroom.Enter(e.scene,{quality=quality}))
    local zone=Room():GetComponent('Zone');local lights=Room():GetComponents('Light',true)
    local low=quality=='low';local shadows=0
    assert(#lights==(low and 2 or 6))
    for _,light in ipairs(lights) do
        assert(light.lightMask==MASK and light.viewMask==MASK and light.zoneMask==MASK)
        if light.castShadows then shadows=shadows+1 end
    end
    assert(shadows==(low and 0 or 1))
    local key=Room():GetChild('WarmKey'):GetComponent('Light')
    assert(key.lightType==LIGHT_DIRECTIONAL and key.node.direction.x>0 and key.node.direction.y<0 and key.node.direction.z>0)
    Mock.Near(key.brightness,low and 1.2 or 1.65);Mock.Near(zone.ambientColor.b,.39)
    assert(zone.TonemapMode==TONEMAP_MODE_ACES and zone.BloomMode==BLOOM_MODE_LEGACY and zone.BloomEnable)
    Mock.Near(zone.BloomThreshold,1.15);Mock.Near(zone.BloomWeight,low and 0 or .18)
    assert(zone.depthFogEnable and zone.depthFogEnd>zone.depthFogStart)
    assert(not pcall(zone.SetBloomWeight,zone,'bad') and not pcall(zone.SetBloomWeight,zone,.18,'extra'))
    assert(not pcall(zone.SetVolumetricFogEnabled,zone,1))
    assert(not pcall(zone.SetVignetteTexture,zone,{resourceType='Material'}))
    if low then
        assert(not zone.VignetteEnabled and not zone.VolumetricFogEnabled)
        assert(not Room():GetChild('ForgeCamera'):GetComponent('DepthOfField'))
    else
        assert(zone.VignetteEnabled and zone.VignetteIntensity==.32 and zone.VolumetricFogEnabled)
        assert(zone.VolumetricFogDensity==.003 and zone.VolumetricFogHeight==0 and zone.VolumetricFogMaxOpacity==.18)
        assert(key.shadowCascade[1]==10 and key.shadowCascade[2]==32 and key.affectVolumetricFog)
        local rim=Room():GetChild('CoolRim'):GetComponent('Light');assert(rim.range==7 and rim.color.b==1)
    end
    Showroom.SetWeapon(Config('sword'));Finish()
    local g=Shape().children[1]:GetComponent('CustomGeometry')
    assert(g.castShadows==not low and g.material.Roughness==.68 and g.material.Metallic==.35)
    if not low then
        local left=Room():GetChild('CrystalLeft'):GetComponent('Light')
        local right=Room():GetChild('CrystalRight'):GetComponent('Light')
        Showroom.Update(.5);assert(left.brightness==right.brightness and left.brightness>=1.35*.84 and left.brightness<=1.35)
        local point=Room():GetChild('WeaponSoftKey').position
        Showroom.DragBegin();Showroom.DragBy(100);Showroom.Update(0)
        local after=Room():GetChild('WeaponSoftKey').position
        assert(after.x~=point.x and after.y==point.y,'key must orbit with weapon yaw')
    end
    for field in pairs(renderer) do assert(field=='GetViewport' or field=='SetViewport','global renderer changed: '..field) end
    Showroom.Exit();Restored(nodes,components)
end
for _,missing in ipairs({'SetTonemapMode','SetBloomWeight','SetVignetteTexture','SetVolumetricFogDensity'}) do
    Boot();nodes,components=Live();e.missingKind='Zone';e.missingField=missing
    assert(Showroom.Enter(e.scene),'optional post effect must not reject Enter')
    assert(Showroom.Diagnostic():find(missing,1,true),Showroom.Diagnostic())
    Showroom.SetWeapon(Config('sword'));Finish();Showroom.Exit();Restored(nodes,components)
end
for _,failure in ipairs({'Light','shadow','vignette','material'}) do
    Boot();nodes,components=Live()
    local cascade=CascadeParameters
    if failure=='Light' then e.fail='Light'
    elseif failure=='shadow' then rawset(_G,'CascadeParameters',nil)
    elseif failure=='vignette' then e.failResource='Editor/Textures/Engine/Vignetting.png' end
    assert(Showroom.Enter(e.scene))
    rawset(_G,'CascadeParameters',cascade)
    if failure=='material' then e.failShader='Metallic' end
    Showroom.SetWeapon(Config('sword'));Finish()
    assert(Showroom.Diagnostic()~='' and Showroom.IsReady(),'enhancement failure must preserve weapon readiness')
    if failure=='material' then
        Showroom.SetWeapon(Config('bow'));Finish()
        assert(Shape().children[1]:GetComponent('CustomGeometry').material.Roughness==.68,'partial material must retry configuration')
    end
    Showroom.Exit();Restored(nodes,components)
end
print('forge_showroom light/post PASS: high 6/1 lights/shadows; low 2/0, strict setters, isolation, all optional fallbacks, material retry, teardown; MOCK ONLY')

local function Signature(j)
    local hash,count=0,0
    for _,node in pairs(j.nodes) do
        local g=node:GetComponent('CustomGeometry')
        for _,v in ipairs(g.vertices) do
            local p,c=v.position,v.color
            local h=math.floor(p.x*10000)*73856093 ~ math.floor(p.y*10000)*19349663 ~ math.floor(p.z*10000)*83492791
            h=h ~ math.floor(c.r*100000)*31 ~ math.floor(c.g*100000)*131 ~ math.floor(c.b*100000)*521
            hash=(hash+(h&0x7fffffff))%2147483647;count=count+1
        end
    end
    return hash,count
end
local function CompleteDressing(quality,seed,failName)
    Boot();nodes,components=Live()
    local root=e.scene:CreateChild('DetailTest')
    local j=Dressing.Begin(root,MASK,{quality=quality,seed=seed})
    e.failNode=failName
    assert(#root.children==0,'Begin cannot allocate mesh or materials')
    local tick,frames,peak=0,0,0
    rawset(_G,'time',{GetElapsedTime=function(self)assert(self==time);tick=tick+.00051;return tick end})
    local errors={}
    while not j.complete and not j.failed and frames<100000 do
        local before=j.operations;local err=Dressing.Step(j,1)
        if err then errors[#errors+1]=err end
        peak=math.max(peak,j.operations-before)
        assert(j.operations-before<=128,'1ms budget violated in synthetic-clock slices')
        frames=frames+1
    end
    assert(j.complete and not j.failed,'build did not finish')
    local batches,total=0,0
    for kind,node in pairs(j.nodes) do
        local g=node:GetComponent('CustomGeometry')
        assert(node.enabled and g.viewMask==MASK and g.lightMask==MASK and g.zoneMask==MASK)
        assert(g.commits==1 and #g.vertices/3==j.counts[kind])
        batches=batches+j.batches[kind];total=total+j.counts[kind]
    end
    assert(total==j.triangles and total<=55000 and batches<=12)
    if not failName then assert(#errors==0,table.concat(errors,';')) end
    local signature,vertices=Signature(j)
    print(('dressing %s seed=%d batches=%d triangles=%d vertex_bytes=%d frames=%d max_ops=%d joints=%d chips=%d cracks=%d moss=%d ao=%d signature=%d'):format(
        quality,seed,batches,total,total*3*28,frames,peak,j.joints,j.chips,j.cracks,j.moss,j.aoVertices,signature))
    return j,root,signature,vertices,errors
end
local high,root,firstSignature,firstVertices=CompleteDressing('high',71115)
assert(high.joints>0 and high.chips>0 and high.cracks>0 and high.moss>0 and high.aoVertices>0)
assert(high.nodes.atmosphere and high.nodes.arch and high.nodes.emission)
assert(high.materials.stone.Roughness==.92 and high.materials.stone.Metallic==0)
assert(high.materials.gold.Roughness==.38 and high.materials.gold.Metallic==.78)
assert(high.materials.emission.MatEmissiveColor.b>1 and high.materials.emissionGold.MatEmissiveColor.r>1)
assert(high.nodes.stone:GetComponent('CustomGeometry').numGeometries==3)
assert(high.nodes.emission:GetComponent('CustomGeometry').numGeometries==2)
for _,kind in ipairs({'stone','arch','emission'}) do
    local g=high.nodes[kind]:GetComponent('CustomGeometry');assert(g.castShadows)
    for i=1,#g.vertices,3 do
        local a,b,c=g.vertices[i],g.vertices[i+1],g.vertices[i+2]
        local u,v=b.position-a.position,c.position-a.position
        local dot=(u.y*v.z-u.z*v.y)*a.normal.x+(u.z*v.x-u.x*v.z)*a.normal.y+(u.x*v.y-u.y*v.x)*a.normal.z
        assert(dot>=0,'voxel winding disagrees with normal / shadow culling')
    end
end
for _,kind in ipairs({'sky','halo','clouds','atmosphere'}) do assert(not high.nodes[kind]:GetComponent('CustomGeometry').castShadows) end
assert(#high.nodes.atmosphere:GetComponent('CustomGeometry').vertices==36*6,'24 ambient + 12 beam dust cards')
local transparentEdge=false
for _,vertex in ipairs(high.nodes.halo:GetComponent('CustomGeometry').vertices) do
    if vertex.color.a==0 then transparentEdge=true;break end
end
assert(transparentEdge,'beam wings need zero-alpha edges')
for _,v in ipairs(high.nodes.emission:GetComponent('CustomGeometry').vertices) do
    local r=v.color.r
    assert(math.abs(r-.35)<1e-6 or math.abs(r-.45)<1e-6 or math.abs(r-1)<1e-6,'runes/crystals must bypass AO and jitter')
end
local n0=Live();local vertex0=firstVertices
for _=1,600 do assert(not Dressing.Animate(high,1/60)) end
assert(Live()==n0 and select(2,Signature(high))==vertex0,'animation must not rebuild')
assert(math.abs(high.nodes.islands.position.y)<=.12 and high.nodes.atmosphere.position.y>=0 and high.nodes.atmosphere.position.y<1.2)
-- Runtime failure of one animation never destroys the successful scene.
high.materials.emission.SetShaderParameter=function()error('injected breathing error')end
assert(Dressing.Animate(high,.01) and high.animationFailed and high.nodes.arch)
assert(not Dressing.Animate(high,.01))
Dressing.Dispose(high);Dressing.Dispose(high);root:Remove();Restored(nodes,components)
local same,sameRoot,secondSignature,secondVertices=CompleteDressing('high',71115)
assert(firstSignature==secondSignature and firstVertices==secondVertices,'same seed must reproduce masonry/AO')
Dressing.Dispose(same);sameRoot:Remove();Restored(nodes,components)
local other,otherRoot,otherSignature=CompleteDressing('high',71116)
assert(otherSignature~=firstSignature,'seed must affect stone variation/chips/cracks')
Dressing.Dispose(other);otherRoot:Remove();Restored(nodes,components)
local low,lowRoot,_,lowVertices=CompleteDressing('low',71115)
assert(not low.nodes.atmosphere and lowVertices<firstVertices and low.joints==0,'low tier must simplify')
Dressing.Dispose(low);lowRoot:Remove();Restored(nodes,components)
-- Part failure skips only that part and completes all later stages.
for _,part in ipairs({'arch','halo','islands'}) do
    local j,r,_,_,errors=CompleteDressing('low',71115,'RuinsShowroom_'..part)
    assert(#errors==1 and j.skipped[part] and not j.nodes[part])
    assert(j.nodes.sky and j.nodes.stone and j.nodes.clouds,'unrelated successful parts lost')
    Dressing.Dispose(j);r:Remove();Restored(nodes,components)
end
for _,steps in ipairs({0,1,50,250}) do
    Boot();nodes,components=Live();local r=e.scene:CreateChild('CancelDetail');local j=Dressing.Begin(r,MASK)
    for _=1,steps do Dressing.Step(j,.1) end
    Dressing.Dispose(j);r:Remove();Restored(nodes,components)
end
print('forge_showroom detail PASS: 5cm high/10cm low, 55k/12-batch bounds, deterministic stone/AO, partial failure, budget, idle no rebuild and all resources reclaimed; MOCK ONLY')

WingSword.ENABLED=true
do
    Boot();nodes,components=Live();Showroom.SetFlowStrength(.7)
    assert(Showroom.Enter(e.scene));Showroom.SetWeapon(Config('sword'));Finish()
    local g=Shape():GetComponent('CustomGeometry',true)
    local expected=Blades.Data()
    assert(#g.vertices==#expected.vertices and g.commits==1)
    assert(g.viewMask==MASK and g.lightMask==MASK and g.zoneMask==MASK)
    Mock.Near(Spin().scale.y,1);assert(g.material.flow_strength==.7)
    for _,v in ipairs(g.vertices) do assert(v.uv and v.uv.y>=0 and v.uv.y<=1) end
    local same=g.material;Showroom.SetFlowStrength(99);assert(same.flow_strength==2)
    Showroom.SetFlowStrength(0);assert(same.flow_strength==0)
    Showroom.SetFlowStrength(.7);Showroom.SetFlowStrength(0/0);Mock.Near(Showroom.GetFlowStrength(),.7)
    for _=1,120 do Showroom.Update(1/60) end
    assert(g.commits==1,'TIME animation must never re-upload geometry')
    local config=Config('sword');config.colors={primary=5,secondary=6,accent=4}
    Showroom.SetWeapon(config);Finish()
    local changed=Shape():GetComponent('CustomGeometry',true).material
    assert(same.disposed and changed.primary_color.r~=same.primary_color.r)
    assert(changed.secondary_color.r~=same.secondary_color.r and changed.accent_color.r~=same.accent_color.r)
    Showroom.SetWeapon(Config('bow'));Finish();assert(not Shape():GetChild('WingSword'))
    Showroom.SetWeapon(Config('sword'));Finish();assert(Shape():GetChild('WingSword'))
    Showroom.Exit();Restored(nodes,components)
end
for _,failure in ipairs({'material','geometry','emit','cancel','fit'}) do
    Boot();nodes,components=Live();assert(Showroom.Enter(e.scene))
    Showroom.SetWeapon(Config('sword'))
    if failure=='material' then e.failResource='model/forge-blades/WingSword.xml'
    elseif failure=='geometry' then e.fail='CustomGeometry' end
    Showroom.Update(0);e.fail=nil
    if failure=='cancel' then Showroom.SetWeapon(Config('bow'));Showroom.Update(0);Showroom.Exit()
    elseif failure=='fit' then
        -- Fail the final Fit after native Commit, before pending ownership transfers.
        local pending=Spin():GetChild('PendingWeapon'):GetComponent('CustomGeometry',true)
        while #pending.vertices+96<#Blades.Data().vertices do Showroom.Update(0) end
        graphics.GetWidth=nil;Showroom.Update(0)
        assert(Showroom.State()=='failed');Showroom.Exit()
    else
        if failure=='emit' then
            local pending=Spin():GetChild('PendingWeapon')
            pending:GetComponent('CustomGeometry',true).DefineTexCoord=function()error('injected UV failure')end
        end
        Finish();assert(Showroom.IsReady() and Showroom.Diagnostic():find('blade_route',1,true))
        assert(not Shape():GetChild('WingSword'),'failed route leaves no geometry')
        Showroom.Exit()
    end
    Restored(nodes,components)
end
-- Thorn-flower bow route: bows show the generated model in the showroom; disabling it restores the voxel bow.
do
    ThornBow.ENABLED=true
    Boot();nodes,components=Live();assert(Showroom.Enter(e.scene))
    Showroom.SetWeapon(Config('bow'));Finish()
    local g=Shape():GetComponent('CustomGeometry',true)
    assert(g and #g.vertices>0,'thorn bow geometry published')
    local shaped=Shape():GetChild('thorn_bow_visual',true)
    assert(shaped,'thorn bow node present')
    local model=require('combat.models.ThornBow').Load()
    local total=0
    local function Count(node)
        local c=node:GetComponent('CustomGeometry')
        if c then total=total+#c.vertices end
        for _,child in ipairs(node.children) do Count(child) end
    end
    Count(Shape())
    assert(total>=model.body.triangles*3,'full body + string uploaded')
    Mock.Near(Spin().scale.y*(model.bounds.max[2]-model.bounds.min[2]),2.05)
    Showroom.SetWeapon(Config('sword'));Finish()
    ThornBow.ENABLED=false
    Showroom.SetWeapon(Config('bow'));Finish();assert(not Shape():GetChild('thorn_bow_visual',true),'kill switch restores voxel bow')
    Showroom.Exit();Restored(nodes,components)
    print('forge_showroom thorn bow route PASS; MOCK ONLY')
end

-- The catalyst uploads its five visible parts over multiple updates.
Boot();nodes,components=Live();assert(Showroom.Enter(e.scene))
Showroom.SetWeapon({weapon='time'});Finish()
local clock=assert(Shape():GetChild('time_catalyst',true))
assert(clock.enabled and #clock.children==5)
for _,pivot in ipairs(clock.children) do
    local mesh=assert(pivot:GetComponent('CustomGeometry'))
    assert(pivot.enabled and mesh.viewMask==MASK and #mesh.vertices>0 and mesh.commits==1)
end
Showroom.Exit();Restored(nodes,components)
