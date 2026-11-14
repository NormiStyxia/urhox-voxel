-- Lua 5.4 only. These doubles validate ownership/math/state, NOT native bindings
-- or rendered pixels. Missing native methods deliberately throw instead of passing.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local Builder=require('combat.WeaponBuilder')
local Parts=require('combat.WeaponParts')
local Showroom=require('combat.ForgeShowroom')
local MASK=0x40000000
rawset(_G,'Vector2',function(x,y)return {x=x,y=y}end)
rawset(_G,'BoundingBox',function(a,b)return {min=a,max=b}end)
rawset(_G,'CULL_NONE',0);rawset(_G,'AMBIENT_COLOR',2);rawset(_G,'LIGHT_POINT',2)
for _,name in ipairs({'Scene','Texture2D','RenderTexture','VoxelPhysicsWorld'}) do rawset(_G,name,function()error('forbidden '..name)end) end
local e
local function Wrap(n)
    e.nodes[#e.nodes+1]=n;n.components={}
    function n:CreateChild(name)
        if e.fail=='child' then error('injected child error') end
        local child=Wrap(Mock.Node(name,self));self.children[#self.children+1]=child;return child
    end
    function n:CreateComponent(kind)
        assert(kind~='VoxelPhysicsWorld' and kind~='Octree','must reuse main scene world/octree')
        if e.fail==kind then return nil end
        local c=kind=='CustomGeometry' and Mock.CustomGeometry(self,e.geometryOptions) or {node=self}
        c.kind=kind;c.viewMask=0xffffffff;c.lightMask=0xffffffff;c.zoneMask=0xffffffff
        if kind=='Camera' then c.projectionOffset=Vector2(0,0) end
        if kind=='Zone' then c.ambientSource=0 end
        if e.missingKind==kind then c[e.missingField]=nil end
        self.components[#self.components+1]=c;return c
    end
    function n:GetComponents(kind,recursive)
        local out={}
        local function Visit(node)
            if node.removed then return end
            for _,c in ipairs(node.components) do if c.kind==kind then out[#out+1]=c end end
            if recursive then for _,child in ipairs(node.children) do Visit(child) end end
        end
        Visit(self);return out
    end
    function n:GetComponent(kind) return self:GetComponents(kind,false)[1] end
    function n:Remove()
        assert(not self.removed,'node removed twice')
        for _,child in ipairs(self.children) do if not child.removed then child:Remove() end end
        self.removed=true
    end
    return n
end
local function Boot()
    Showroom.Exit();e={nodes={},materials={},width=844,height=390,setCalls=0}
    e.scene=Wrap(Mock.Node('MainScene'));e.scene.components={{kind='Octree'}}
    e.oldCamera={fov=61,projectionOffset={x=.12,y=.2}}
    e.original={scene=e.scene,camera=e.oldCamera};e.viewport=e.original
    e.sun=e.scene:CreateChild('Sun'):CreateComponent('Light')
    e.sun.lightMask=0x7fffffff
    e.sky=e.scene:CreateChild('Sky'):CreateComponent('Skybox')
    e.cloud=e.scene:CreateChild('SkyClouds'):CreateComponent('CustomGeometry')
    e.cloud.viewMask=0xefffffff
    rawset(_G,'graphics',{GetWidth=function()return e.width end,GetHeight=function()return e.height end})
    rawset(_G,'renderer',{GetViewport=function(self,index) assert(self==renderer and index==0);return e.viewport end,
        SetViewport=function(self,index,v)assert(self==renderer and index==0);e.viewport=v;e.setCalls=e.setCalls+1;
            if e.fail=='switch' then e.fail=nil;error('partial switch failure') end end})
    rawset(_G,'Viewport',{new=function(self,scene,camera) assert(self==Viewport and scene==e.scene);return {scene=scene,camera=camera} end})
    rawset(_G,'Material',{new=function(self)
        assert(self==Material);local m={};e.materials[#e.materials+1]=m
        function m:SetTechnique(_,t) assert(t) end
        function m:SetShaderParameter(k,v) self[k]=v end
        function m:Dispose() assert(not self.disposed);self.disposed=true end
        return m
    end})
    rawset(_G,'cache',{GetResource=function(self,kind,path)
        assert(self==cache)
        if e.fail=='material' then return nil end
        assert(path=='Materials/NomiVoxel.xml' or path=='Techniques/NoTextureUnlit.xml')
        return {name=path}
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
end

Boot();local nodes,components=Live()
assert(Showroom.Diagnostic()=='')
assert(Showroom.State()=='off' and not Showroom.Active())
Showroom.Update(1);Showroom.SetWeapon({});Showroom.DragBegin();Showroom.Home();Showroom.Exit()
assert(Showroom.Enter(e.scene,{focusX=.3}))
assert(Showroom.Active() and Showroom.State()=='building' and not Showroom.IsReady())
assert(Room().position.x==2304 and Room().position.y==1200)
assert(e.viewport.camera.viewMask==MASK and e.viewport.scene==e.scene)
assert((e.sun.lightMask&MASK)==0 and (e.sky.viewMask&MASK)==0 and (e.cloud.viewMask&MASK)==0)
local zone=Room():GetComponent('Zone');assert(zone.ambientSource==AMBIENT_COLOR and not zone.depthFogEnable and not zone.heightFogEnable)
local lights=Room():GetComponents('Light',true);assert(#lights==2)
for _,l in ipairs(lights) do assert(l.viewMask==MASK and l.lightMask==MASK and l.range==8 and not l.castShadows) end
local bg=Room():GetChild('BackdropAndPodium'):GetComponent('CustomGeometry')
assert(bg.commits==1 and #bg.vertices==180 and bg.viewMask==MASK)
local c=Config('sword');Showroom.SetWeapon(c);c.parts.blade='invalid-mutated-after-call'
Finish();assert(Shape() and Shape():GetComponent('CustomGeometry')==nil)
local oldShape=Shape();local oldGeometry=oldShape.children[1]:GetComponent('CustomGeometry')
assert(oldGeometry:GetNumVertices(0)>0 and oldGeometry.viewMask==MASK and oldGeometry.zoneMask==MASK)
Showroom.SetWeapon(Config('bow'));Showroom.Update(1/60)
assert(not oldShape.removed and oldShape.enabled and not Showroom.IsReady(),'old weapon must survive pending compile')
Showroom.Update(1/60);Showroom.SetWeapon(Config('sword'));Finish()
assert(oldShape.removed,'replacement must dispose old geometry')
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
local combos=0
for _,weapon in ipairs({'sword','bow'}) do
    local config=Config(weapon);local slots=Parts.Slots[weapon]
    local function Visit(i)
        if i<=#slots then
            for _,part in ipairs(Parts.GetOptions(weapon,slots[i])) do config.parts[slots[i]]=part.id;Visit(i+1) end
            return
        end
        combos=combos+1;Showroom.SetWeapon(config);Finish()
        local b=Builder.Compile(config).bounds
        for _,size in ipairs({{844,390},{390,844}}) do
            e.width,e.height=size[1],size[2];Showroom.Update(0)
            local camera=e.viewport.camera;local distance=-Room():GetChild('ForgeCamera').position.z
            local tan=math.tan(math.rad(camera.fov)/2)
            for angle=0,315,45 do
                local q=Quaternion(0,angle,0)
                for xi=1,2 do for yi=1,2 do for zi=1,2 do
                    local p=q*Vector3((xi==1 and b.min[1] or b.max[1])-(b.min[1]+b.max[1])/2,
                        (yi==1 and b.min[2] or b.max[2])-(b.min[2]+b.max[2])/2,
                        (zi==1 and b.min[3] or b.max[3])-(b.min[3]+b.max[3])/2)
                    local x=.3+p.x/(2*(distance+p.z)*tan*e.width/e.height)
                    local y=.5-p.y/(2*(distance+p.z)*tan)
                    assert(x>0 and x<.55 and y>0 and y<1,'weapon clipped / under panel')
                end end end
            end
        end
    end
    Visit(1)
end
assert(combos==72);Showroom.Exit();Restored(nodes,components)

for _,fail in ipairs({'child','Zone','Light','Camera','CustomGeometry','material','switch'}) do
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
EnterFailure('geometry','Node:CreateComponent',function() e.fail='CustomGeometry' end)
EnterFailure('geometry','CustomGeometry:DefineVertex',function() e.missingKind='CustomGeometry';e.missingField='DefineVertex' end)
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
